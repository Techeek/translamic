# TranslaMic（译麦）

TranslaMic is an open-source, Apple Silicon native meeting translator for macOS. It listens to your microphone or a selected app, transcribes and translates speech with Apple frameworks, then speaks the translated result through a virtual microphone that meeting apps can select as an input device.

> Current status: `0.1.0` MVP. The app and driver build successfully, but real meeting-app interoperability still needs installation and end-to-end testing.

## How it works

1. Apple Speech transcribes microphone or app audio on device.
2. Apple Translation produces the target-language text on device.
3. `AVSpeechSynthesizer` generates target-language speech.
4. `TranslaMic Virtual Microphone`, a Core Audio HAL plug-in based on Apple's Audio Server Driver sample, exposes that audio to other apps.

The existing bilingual subtitle overlay and transcript features inherited from [v2s](https://github.com/franklioxygen/v2s) remain available.

## Requirements

- macOS 26 or newer
- Apple Silicon
- Xcode 26 or newer when building from source

## Install an unsigned development build

Download `translamic-x.y.z.pkg` from GitHub Releases and install it, then restart macOS so Core Audio loads the virtual device. The package installs:

- `/Applications/TranslaMic.app`
- `/Library/Audio/Plug-Ins/HAL/TranslaMicVirtualAudio.driver`

The installer package is intentionally unsigned and not notarized. Its payload uses local ad-hoc signatures, not an Apple Developer identity. macOS may still block it; use it only when you trust the release source. Developer ID signing and notarization are planned for a later release.

After restarting, enable **Virtual Microphone** in TranslaMic settings and select **TranslaMic Virtual Microphone** as the microphone in your meeting app.

## Build from source

```bash
git clone https://github.com/Techeek/translamic.git
cd translamic
xcodebuild -project TranslaMic.xcodeproj -scheme TranslaMic -configuration Debug build
```

Build the single unsigned installer artifact:

```bash
./scripts/build-pkg.sh 0.1.0
```

Output: `dist/translamic-0.1.0.pkg`.

## Privacy

TranslaMic has no account, analytics, telemetry, or project-operated cloud backend. Speech recognition, translation, and speech synthesis use macOS capabilities. Some Apple language resources may need to be downloaded first.

## License and attribution

TranslaMic is released under the [MIT License](LICENSE) and is derived from [franklioxygen/v2s](https://github.com/franklioxygen/v2s). The virtual audio driver contains adapted code from Apple's “Creating an Audio Server Driver Plug-in” sample under the notice in `Drivers/TranslaMicVirtualAudio/APPLE_SAMPLE_LICENSE.txt`.

See [README.zh-CN.md](README.zh-CN.md) for Chinese documentation.
