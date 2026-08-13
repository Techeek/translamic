<p align="center">
  <img src="Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" width="128" height="128" alt="TranslaMic icon">
</p>

# TranslaMic

TranslaMic is an open-source, real-time voice translator for Apple Silicon Macs. It listens to a microphone or a selected application's audio, uses macOS capabilities to transcribe and translate the speech, then sends synthesized speech in the target language to a virtual microphone that Tencent Meeting, Zoom, Microsoft Teams, and other meeting apps can use as an input device.

In addition to letting you speak one language while the meeting hears another, TranslaMic provides bilingual captions, a floating subtitle overlay, a glossary, and session transcripts.

> Current version: `0.2.0` usable preview. macOS 26+ and Apple Silicon only. The core transcription, translation, MOSS streaming speech, and virtual-microphone path is working; the installer is not yet signed with Developer ID or notarized by Apple, and meeting-app compatibility still requires per-app testing.

[简体中文](README.zh-CN.md)

## Features

- Transcribe a microphone or selected application's audio in real time.
- Translate text locally with Apple Translation.
- Speak translated text into `TranslaMic Virtual Microphone`.
- Choose between macOS system voices and the optional low-latency MOSS-TTS-Nano engine.
- Show source text, translated text, or bilingual floating captions.
- Keep a transcript of the current session.
- Use a glossary for names, product terms, and specialized vocabulary.
- No TranslaMic account, analytics, or telemetry.

## How it works

1. Apple Speech converts input audio to text on the Mac.
2. Apple Translation produces text in the target language on the Mac.
3. A macOS system voice or local MOSS-TTS-Nano converts the translation into speech.
4. A Core Audio virtual driver exposes that speech to other apps as microphone input.

The virtual microphone carries synthesized translated speech, not the original microphone signal. Captions normally appear first; translated speech follows after translation and synthesis latency.

## Requirements

- macOS 26 or newer
- Apple Silicon (M-series chip)
- Ability to restart the Mac after driver installation
- An initial internet download of about 730 MB of model weights when using MOSS-TTS-Nano
- Xcode 26 or newer when building from source

Intel Macs and macOS 25 or earlier are not supported. A Mac App Store release is not planned.

## Installation

1. Download `translamic-x.y.z.pkg` from GitHub Releases.
2. Confirm that the installer came from a trusted TranslaMic project release.
3. Install the package, then restart the Mac so Core Audio loads the virtual microphone driver.
4. Launch TranslaMic and grant the requested microphone, speech recognition, and Screen & System Audio Recording permissions.

The package installs:

- `/Applications/TranslaMic.app`
- `/Library/Audio/Plug-Ins/HAL/TranslaMicVirtualAudio.driver`

### About unsigned development builds

The current `.pkg` is not signed with Developer ID and is not notarized. Its app and driver use local ad-hoc signatures that do not require an Apple Developer account. macOS may block installation or the first launch.

Install only builds from a source you trust. If macOS blocks the app, open System Settings → Privacy & Security, verify that the blocked application is TranslaMic, and then allow it to open. Developer ID signing and notarization will be considered before a future stable release.

## Quick start

### 1. Select the audio source and languages

In General settings:

1. Select a microphone or the application you want to monitor.
2. Choose the input language.
3. Choose the subtitle and translation target language.
4. If macOS reports missing speech or translation resources, download them before starting.

### 2. Configure the translated virtual microphone

1. Enable **Speak translations into the virtual microphone**.
2. Confirm the translation target language.
3. Select a voice engine and output voice.
4. Enter a sentence in the test field and click **Test Virtual Microphone**. This test plays directly through the Mac's speakers so you can confirm the selected voice and pronunciation.
5. If the driver is reported as unavailable, restart the Mac and then click **Refresh Sources**.

### 3. Configure the meeting app

Open the meeting app's audio settings and select **TranslaMic Virtual Microphone** as its microphone. Use the meeting app's microphone test to confirm that its input meter moves.

Do not select `TranslaMic Virtual Microphone` as TranslaMic's own monitored input. Doing so can create a loop or provide no useful source audio.

### 4. Start translating

Click **Start** in TranslaMic. As you speak, the app transcribes, translates, displays captions, and sends synthesized speech to the virtual microphone. Click **Stop** when the meeting ends, and open **Transcript** if you need to copy the session text.

## Voice engines

| Engine | Characteristics | Best for | Considerations |
| --- | --- | --- | --- |
| macOS System Voice | Fast startup, low latency, no additional model | Live meetings and stability-first use | Naturalness depends on installed system voices |
| MOSS-TTS-Nano ONNX | Low-latency local synthesis, 17 regular built-in voices and multilingual voice transfer | Live meetings and natural-voice previews | About 730 MB of model weights on first download; uses two CPU threads and starts playback after a 500 ms buffer |

When MOSS-TTS-Nano is selected, TranslaMic prepares an isolated runtime and downloads pinned ONNX model revisions in the background. The UI remains responsive. After loading, it performs one silent warmup and a separate long-lived process keeps the model in memory. Each committed translation sentence is submitted as a whole, while decoded PCM is streamed continuously after a 500 ms initial buffer. Text is never split into character-level TTS requests.

MOSS runtime files are stored in:

```text
~/Library/Application Support/TranslaMic/MossTTS
```

On an Apple M2 test machine, warm MOSS-TTS-Nano synthesis ran faster than playback in English and Japanese, with audio beginning after the initial buffer. Actual end-to-end delay still includes speech recognition, sentence commitment, and translation. The macOS engine remains the lowest-resource fallback.

## Troubleshooting

### The meeting app cannot see the virtual microphone

- Restart the Mac after installing the `.pkg`.
- Click **Refresh Sources** in TranslaMic.
- Fully quit and reopen the meeting app, then check its microphone list again.
- Confirm that `/Library/Audio/Plug-Ins/HAL/TranslaMicVirtualAudio.driver` exists.

### The test button produces no sound

- The test plays through the Mac's current speaker output, not through the meeting app.
- Check system volume, the active output device, and that the test field is not empty.
- Confirm that the selected voice matches the target language.
- With MOSS-TTS-Nano, wait until the status becomes **Ready** before testing again.

### MOSS-TTS-Nano remains on downloading or loading

- The first setup downloads about 730 MB of model weights and installs an isolated runtime. The completed installation uses about 1.3 GB, so keep the network connected and reserve at least 1.5 GB of free space.
- The first model load still takes time after the download finishes.
- If the connection was interrupted, selecting MOSS-TTS-Nano again or restarting the app will check and complete missing files.

### Captions work, but the meeting app receives no sound

- Confirm that **Speak translations into the virtual microphone** is enabled.
- Confirm that the meeting app uses **TranslaMic Virtual Microphone**, not the built-in Mac microphone.
- Watch the meeting app's microphone input meter; the virtual microphone does not automatically play through the Mac's speakers.
- Confirm that a TranslaMic session is running and has produced non-empty translated text.

## Important notes and known limitations

- This is a usable preview whose core path has passed local testing. Zoom, Teams, Tencent Meeting, and other apps should still be validated separately on real devices.
- Real-time translation always introduces latency. MOSS-TTS-Nano streams decoded audio after a 500 ms buffer, but recognition, sentence commitment and translation happen before synthesis can begin.
- Speech recognition, translation, and synthesis can be wrong. Do not rely on them as the only source for medical, legal, safety, or other high-risk instructions.
- Changing a voice affects future speech only; it does not modify audio that has already been sent.
- Speakers and an external microphone can create acoustic echo. Headphones are recommended during meetings.
- App updates normally reuse the downloaded MOSS models, but a future model change may require additional disk space.
- Unsigned builds are intended for development and testing. Do not install one when you cannot verify its source.

## Privacy and network access

TranslaMic requires no account and contains no project-operated analytics, telemetry, or cloud backend. The default workflow uses macOS speech recognition, translation, and system voice capabilities. macOS may download required Apple language resources.

Only selecting MOSS-TTS-Nano triggers downloads of its isolated runtime and pinned open ONNX models. Inference then runs locally on the Mac. See `Sources/TranslaMicApp/Resources/MossTTS/THIRD_PARTY_NOTICES.md` for third-party notices.

## Build from source

```bash
git clone https://github.com/Techeek/translamic.git
cd translamic
/bin/bash ./scripts/prepare-moss-runtime.sh
xcodebuild -project TranslaMic.xcodeproj -scheme TranslaMic -configuration Debug build
```

The package build automatically prepares the MOSS runtime launcher and creates the single unsigned installer artifact:

```bash
./scripts/build-pkg.sh 0.2.0
```

Output: `dist/translamic-0.2.0.pkg`.

## Acknowledgements

Special thanks to [Frank Li (franklioxygen)](https://github.com/franklioxygen) for creating and open-sourcing [v2s](https://github.com/franklioxygen/v2s). TranslaMic continues from v2s's foundation in real-time speech recognition, translation, bilingual captions, and transcripts, and adds the virtual microphone, target-language speech output, and related capabilities. TranslaMic would not exist without the original author's work and the contributions of the v2s community.

## License and attribution

TranslaMic is released under the [MIT License](LICENSE) and is derived from [franklioxygen/v2s](https://github.com/franklioxygen/v2s). The virtual audio driver contains adapted code from Apple's “Creating an Audio Server Driver Plug-in” sample under the notice in `Drivers/TranslaMicVirtualAudio/APPLE_SAMPLE_LICENSE.txt`. See `Sources/TranslaMicApp/Resources/MossTTS/THIRD_PARTY_NOTICES.md` for MOSS-TTS-Nano, ONNX Runtime, and uv notices.
