# TranslaMic（译麦）

TranslaMic 是一款面向 Apple Silicon Mac 的开源会议翻译工具。它监听麦克风或指定应用的音频，使用 Apple 自带能力完成语音识别与翻译，再把目标语言语音送入虚拟麦克风，供腾讯会议、Zoom、Teams 等会议软件选择使用。

> 当前状态：`0.1.0` MVP。应用和驱动已经可以编译，但安装后的会议软件兼容性仍需逐项实机验证。

## 工作流程

1. Apple Speech 在本机将麦克风或应用音频转成文字。
2. Apple Translation 在本机生成目标语言文本。
3. `AVSpeechSynthesizer` 使用 macOS 系统语音生成目标语言音频。
4. 基于 Apple Audio Server Driver 示例改造的 `TranslaMic Virtual Microphone`，把音频作为麦克风输入提供给其他应用。

项目保留了上游 [v2s](https://github.com/franklioxygen/v2s) 的双语字幕、悬浮字幕和转写记录功能。

## 系统要求

- macOS 26 或更高版本
- Apple Silicon
- 从源码构建时需要 Xcode 26 或更高版本

## 安装未签名开发版

从 GitHub Releases 下载 `translamic-x.y.z.pkg` 并安装，然后重启 macOS，让 Core Audio 加载虚拟设备。安装包只包含：

- `/Applications/TranslaMic.app`
- `/Library/Audio/Plug-Ins/HAL/TranslaMicVirtualAudio.driver`

当前安装包没有 Developer ID 签名，也没有公证；包内应用和驱动仅使用无需开发者账号的本地 ad-hoc 签名。macOS 仍可能阻止安装或首次运行。请只安装来自你信任的 GitHub Release；Developer ID 签名与公证留到正式发布阶段处理。

重启后，在 TranslaMic 设置中启用“虚拟麦克风”，再到会议软件中选择 **TranslaMic Virtual Microphone** 作为麦克风。

## 从源码构建

```bash
git clone https://github.com/Techeek/translamic.git
cd translamic
xcodebuild -project TranslaMic.xcodeproj -scheme TranslaMic -configuration Debug build
```

生成唯一的未签名安装包：

```bash
./scripts/build-pkg.sh 0.1.0
```

输出文件为 `dist/translamic-0.1.0.pkg`。

## 隐私

TranslaMic 不需要账号，不包含分析、遥测或项目方云端后台。语音识别、翻译和语音合成使用 macOS 能力；部分 Apple 语言资源可能需要提前下载。

## 许可证与来源

TranslaMic 采用 [MIT License](LICENSE) 开源，并基于 [franklioxygen/v2s](https://github.com/franklioxygen/v2s) 开发。虚拟音频驱动改编自 Apple 的“Creating an Audio Server Driver Plug-in”示例，许可声明见 `Drivers/TranslaMicVirtualAudio/APPLE_SAMPLE_LICENSE.txt`。
