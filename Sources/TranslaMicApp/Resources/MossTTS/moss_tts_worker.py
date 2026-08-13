#!/usr/bin/env python3
"""Long-lived MOSS-TTS-Nano ONNX worker using a JSON-lines protocol."""

from __future__ import annotations

import argparse
import base64
import json
import sys
import time
from pathlib import Path

import numpy as np

TTS_REPO = "OpenMOSS-Team/MOSS-TTS-Nano-100M-ONNX"
TTS_REVISION = "f52645cb467506d8e18e746ddd59482685b74e58"
CODEC_REPO = "OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX"
CODEC_REVISION = "ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae"
START_BUFFER_SECONDS = 0.5


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def download(model_dir: Path):
    from huggingface_hub import snapshot_download

    tts_dir = model_dir / "MOSS-TTS-Nano-100M-ONNX"
    codec_dir = model_dir / "MOSS-Audio-Tokenizer-Nano-ONNX"
    emit({"event": "downloading"})
    snapshot_download(repo_id=TTS_REPO, revision=TTS_REVISION, local_dir=str(tts_dir))
    snapshot_download(repo_id=CODEC_REPO, revision=CODEC_REVISION, local_dir=str(codec_dir))
    marker = {"tts": TTS_REVISION, "codec": CODEC_REVISION}
    (model_dir / ".translamic-ready").write_text(json.dumps(marker), encoding="utf-8")
    emit({"event": "downloaded"})


def pcm_base64(samples):
    mono = np.asarray(samples, dtype=np.float32).reshape(-1)
    pcm = np.round(np.clip(mono, -1.0, 1.0) * 32767.0).astype("<i2")
    return base64.b64encode(pcm.tobytes()).decode("ascii"), len(mono)


def stream_sentence(runtime, text, voice, on_pcm):
    from ort_cpu_runtime import _resolve_stream_decode_frame_budget

    prompt_codes = runtime.resolve_prompt_audio_codes(voice=voice, prompt_audio_path=None)
    text_ids = runtime.encode_text(text)
    request_rows = runtime.build_voice_clone_request_rows(prompt_codes, text_ids)
    pending_frames = []
    emitted_samples = 0
    first_decode_at = None
    started_at = time.perf_counter()
    sample_rate = int(runtime.codec_meta["codec_config"]["sample_rate"])
    runtime.codec_streaming_session.reset()

    def decode_pending(force):
        nonlocal emitted_samples, first_decode_at
        if not pending_frames:
            return
        budget = _resolve_stream_decode_frame_budget(emitted_samples, sample_rate, first_decode_at)
        if not force and len(pending_frames) < max(1, budget):
            return
        count = len(pending_frames) if force else min(len(pending_frames), max(1, budget))
        frames = pending_frames[:count]
        del pending_frames[:count]
        decoded = runtime.codec_streaming_session.run_frames(frames)
        if decoded is None:
            return
        audio, audio_length = decoded
        if audio_length <= 0:
            return
        if first_decode_at is None:
            first_decode_at = time.perf_counter()
        emitted_samples += audio_length
        # Official presets currently produce identical stereo channels. The HAL
        # virtual microphone consumes mono, so emit the first channel directly.
        on_pcm(np.asarray(audio[0, 0, :audio_length], dtype=np.float32), sample_rate)

    def on_frame(_generated, _step, frame):
        pending_frames.append(list(frame))
        decode_pending(False)

    try:
        generated = runtime.generate_audio_frames(request_rows, on_frame=on_frame)
        decode_pending(True)
    finally:
        runtime.codec_streaming_session.reset()
    return generated, time.perf_counter() - started_at


def serve(model_dir: Path):
    from onnx_tts_runtime import OnnxTtsRuntime

    emit({"event": "loading"})
    runtime = OnnxTtsRuntime(
        model_dir=model_dir,
        thread_count=2,
        max_new_frames=375,
        sample_mode="fixed",
        execution_provider="cpu",
    )
    # Compile and populate the common ONNX paths before the first audible request.
    runtime.synthesize(
        text="Ready.", voice="Adam", output_audio_path=model_dir / ".warmup.wav",
        sample_mode="fixed", streaming=True, enable_wetext=False, seed=7,
    )
    emit({"event": "ready"})

    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            if request.get("command") == "quit":
                break
            request_id = request["id"]
            started_at = time.perf_counter()
            pending_pcm = []
            pending_samples = 0
            first_audio_latency = None
            audio_samples = 0
            chunk_count = 0
            sample_rate = 48_000

            def emit_pcm(samples, rate):
                nonlocal pending_samples, first_audio_latency, audio_samples, chunk_count, sample_rate
                sample_rate = int(rate)
                pending_pcm.append(np.asarray(samples, dtype=np.float32).copy())
                pending_samples += len(samples)
                audio_samples += len(samples)
                if first_audio_latency is None and pending_samples < int(sample_rate * START_BUFFER_SECONDS):
                    return
                if first_audio_latency is None:
                    first_audio_latency = time.perf_counter() - started_at
                while pending_pcm:
                    chunk = pending_pcm.pop(0)
                    encoded, frame_count = pcm_base64(chunk)
                    chunk_count += 1
                    emit({
                        "event": "audio", "id": request_id,
                        "sampleRate": sample_rate, "pcmBase64": encoded,
                    })

            _, generation_latency = stream_sentence(
                runtime, request["text"], request.get("voice", "Adam"), emit_pcm
            )
            # Very short utterances may finish before the 500 ms threshold.
            if pending_pcm:
                if first_audio_latency is None:
                    first_audio_latency = time.perf_counter() - started_at
                while pending_pcm:
                    chunk = pending_pcm.pop(0)
                    encoded, _ = pcm_base64(chunk)
                    chunk_count += 1
                    emit({
                        "event": "audio", "id": request_id,
                        "sampleRate": sample_rate, "pcmBase64": encoded,
                    })
            emit({
                "event": "completed", "id": request_id,
                "firstAudioLatency": first_audio_latency,
                "totalLatency": generation_latency,
                "audioDuration": audio_samples / sample_rate,
                "chunkCount": chunk_count,
            })
        except Exception as error:
            emit({"event": "failed", "id": request.get("id"), "message": str(error)})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    if args.download:
        download(args.model_dir)
    else:
        serve(args.model_dir)


if __name__ == "__main__":
    main()
