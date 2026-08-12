#!/usr/bin/env python3
"""Long-lived local Qwen3-TTS worker. JSON-lines protocol over stdin/stdout."""

import argparse
import base64
import json
import sys
import time
from pathlib import Path

MODEL_REPO = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"
MODEL_REVISION = "6415d95f88be018ff9e46813119dc3bc12261328"


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def download(model_dir):
    from huggingface_hub import snapshot_download

    emit({"event": "downloading"})
    snapshot_download(
        repo_id=MODEL_REPO,
        revision=MODEL_REVISION,
        local_dir=str(model_dir),
    )
    (model_dir / ".translamic-ready").write_text(MODEL_REVISION, encoding="utf-8")
    emit({"event": "downloaded"})


def pcm_base64(audio):
    import numpy as np

    samples = np.asarray(audio, dtype=np.float32).reshape(-1)
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    return base64.b64encode(pcm.tobytes()).decode("ascii"), len(samples)


def prewarm(model, mx):
    """Compile the common MLX path once so the first audible request is faster."""
    emit({"event": "warming"})
    try:
        for _ in model.generate(
            text="Hi.",
            voice="vivian",
            lang_code="english",
            stream=False,
            verbose=False,
        ):
            pass
    except Exception as error:
        # Prewarming is an optimization. A failed warmup must not disable TTS.
        emit({"event": "warning", "message": f"Prewarm failed: {error}"})
    finally:
        mx.clear_cache()


def serve(model_dir):
    import mlx.core as mx
    from mlx_audio.tts.utils import load_model

    emit({"event": "loading"})
    model = load_model(model_dir)
    prewarm(model, mx)
    emit({"event": "ready", "voices": model.get_supported_speakers()})

    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            if request.get("command") == "quit":
                break
            request_id = request["id"]
            started_at = time.perf_counter()
            first_audio_latency = None
            audio_frame_count = 0
            chunk_count = 0
            sample_rate = int(model.sample_rate)
            for result in model.generate(
                text=request["text"],
                voice=request["voice"],
                lang_code=request.get("language", "auto"),
                stream=False,
                verbose=False,
            ):
                encoded_audio, frame_count = pcm_base64(result.audio)
                if frame_count == 0:
                    continue
                sample_rate = int(result.sample_rate)
                if first_audio_latency is None:
                    first_audio_latency = time.perf_counter() - started_at
                audio_frame_count += frame_count
                chunk_count += 1
                emit({
                    "event": "audio",
                    "id": request_id,
                    "sampleRate": sample_rate,
                    "pcmBase64": encoded_audio,
                })
            if chunk_count == 0:
                raise RuntimeError("The model returned no audio.")
            total_latency = time.perf_counter() - started_at
            mx.clear_cache()
            emit({
                "event": "completed",
                "id": request_id,
                "firstAudioLatency": first_audio_latency,
                "totalLatency": total_latency,
                "audioDuration": audio_frame_count / sample_rate,
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
