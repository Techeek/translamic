(function (global) {
  const STORAGE_KEY = "TranslaMic-home-lang";

  const strings = {
    en: {
      meta: {
        title: "TranslaMic — Live bilingual subtitles for macOS",
        description:
          "TranslaMic — live bilingual subtitles for meetings, calls, streams, and videos on macOS. On-device speech and translation, menu bar workflow, zero cloud.",
      },
      a11y: {
        skip: "Skip to content",
        brand: "TranslaMic home",
        nav: "Primary",
        menuOpen: "Open menu",
        menuClose: "Close menu",
        langSwitch: "Language",
      },
      nav: {
        features: "Features",
        howItWorks: "How it works",
        languages: "Languages",
        privacy: "Privacy",
        getStarted: "Get started",
        github: "GitHub",
        download: "Download",
      },
      hero: {
        badgeOnDevice: "100% on-device",
        badgeMac: "macOS 26+",
        title: "TranslaMic: Live bilingual subtitles, never uploaded to the cloud.",
        lead:
          "TranslaMic turns microphone or app audio into a clean two-line subtitle bar for meetings, calls, streams, and videos. Hear the original language, read the translation, and stay on the window you already use.",
        ctaDownload: "Download for macOS",
        ctaQuickStart: "Quick start",
        ctaSource: "View source",
        demoTranslation: "Welcome back — glad you could join today's call.",
        demoSource: "欢迎回来，很高兴你能参加今天的通话。",
        demoWindow: "Zoom — Team standup",
        imgAlt: "TranslaMic subtitle overlay on a video call",
      },
      highlights: {
        h1Title: "Private by design",
        h1Body:
          "No account, analytics, or cloud backend. Audio and subtitles stay on your Mac through Apple's on-device frameworks.",
        h2Title: "Menu bar first",
        h2Body:
          "Always one click away. Start, stop, and tune languages without leaving your meeting or player fullscreen.",
        h3Title: "Pick your audio",
        h3Body:
          "Capture your microphone or audio from a specific running app — not the whole system mix.",
      },
      features: {
        eyebrow: "Features",
        title: "Built for real-time conversations, not post-production.",
        lead:
          "Everything you need to follow live speech in another language, without juggling browser tabs or heavyweight caption apps.",
        f1Title: "Live overlay",
        f1Body:
          "Translated line on top, original speech below — both visible so you can switch context instantly.",
        f2Title: "Per-app capture",
        f2Body:
          "Route Zoom, Teams, browsers, or players as the input source while the rest of your desktop stays quiet.",
        f3Title: "Apple SpeechAnalyzer",
        f3Body: "On-device transcription tuned for the languages Apple supports on your Mac.",
        f4Title: "Apple Translation",
        f4Body:
          "On-device translation with language packs managed through System Settings when needed.",
        f5Title: "AI summaries",
        f5Body:
          "Apple Intelligence can summarize your transcript when you need a quick recap after a long call.",
        f6Title: "Readable styling",
        f6Body:
          "Adjust overlay appearance so subtitles stay legible on top of slides, code, or dark video.",
      },
      howItWorks: {
        eyebrow: "How it works",
        title: "Three steps from download to subtitles.",
        step1Title: "Install",
        step1Body:
          "Download and install the latest <code>translamic-x.y.z.pkg</code>, then restart macOS.",
        step2Title: "Configure",
        step2Body:
          "Choose mic or app audio, set input and subtitle languages, grant permissions once.",
        step3Title: "Start",
        step3Body:
          "Click Start in the menu bar — subtitles appear at the top of your screen in real time.",
        caption: "Menu bar controls and language settings",
        imgAlt: "TranslaMic settings and menu bar interface",
      },
      inputLangs: {
        eyebrow: "Input languages",
        title: "Ten languages on the Apple speech path.",
        lead:
          "TranslaMic lists only languages supported by SpeechAnalyzer/SpeechTranscriber. Regional variants are collapsed to Apple's default locale per language.",
        noteBefore: "Subtitle (output) languages follow Apple Translation availability on your Mac. ",
        readmeLink: "Read the full README →",
        readmeHref: "https://github.com/Techeek/translamic/blob/main/README.md",
        chipCantonese: "Cantonese",
        chipZh: "Chinese (Simplified)",
        chipEn: "English",
        chipFr: "French",
        chipDe: "German",
        chipIt: "Italian",
        chipJa: "Japanese",
        chipKo: "Korean",
        chipPt: "Portuguese",
        chipEs: "Spanish",
      },
      privacy: {
        eyebrow: "Privacy",
        title: "Your meeting stays on your machine.",
        li1: "No account, cloud backend, analytics, or telemetry",
        li2: "Audio and subtitle text never leave your Mac through TranslaMic",
        li3: "Speech and translation use Apple's on-device frameworks",
        li4: "Permissions requested only for speech, mic, or app audio capture",
      },
      quickStart: {
        eyebrow: "Quick start",
        title: "From download to first subtitle in minutes.",
        s1Title: "Download",
        s1Body: "Grab the latest <code>translamic-x.y.z.pkg</code> from GitHub Releases.",
        s2Title: "Install",
        s2Body:
          "Install the package, restart macOS, then launch TranslaMic from the menu bar.",
        s3Title: "Build from source",
        s3Body: "Requires Xcode and macOS 26+ for speech and translation APIs.",
        copy: "Copy",
        copied: "Copied",
        copyFailed: "Failed",
        copyCmd: "Copy command",
        copyCmds: "Copy commands",
        permsTitle: "First-run permissions",
        perm1Title: "Speech Recognition",
        perm1Body: "transcribe audio to text",
        perm2Title: "Microphone",
        perm2Body: "when using mic as input",
        perm3Title: "Audio Capture",
        perm3Body: "when capturing another app's audio",
      },
      cta: {
        title: "Ready to follow every word?",
        body: "Free, open source, and built for macOS. Download TranslaMic and keep your conversations accessible.",
        download: "Download latest",
        star: "Star on GitHub",
      },
      footer: {
        license: "MIT License · ",
        docLink: "中文文档",
        docHref: "https://github.com/Techeek/translamic/blob/main/README.zh-CN.md",
      },
    },
    zh: {
      meta: {
        title: "TranslaMic — macOS 实时双语字幕",
        description:
          "TranslaMic — 适用于会议、通话、直播和视频的 macOS 实时双语字幕。本地语音与翻译、菜单栏工作流、零云端。",
      },
      a11y: {
        skip: "跳到正文",
        brand: "TranslaMic 首页",
        nav: "主导航",
        menuOpen: "打开菜单",
        menuClose: "关闭菜单",
        langSwitch: "语言",
      },
      nav: {
        features: "功能",
        howItWorks: "使用方式",
        languages: "语言",
        privacy: "隐私",
        getStarted: "快速开始",
        github: "GitHub",
        download: "下载",
      },
      hero: {
        badgeOnDevice: "100% 本地处理",
        badgeMac: "macOS 26+",
        title: "TranslaMic: 实时双语字幕，绝不上传云端。",
        lead:
          "TranslaMic 将麦克风或应用音频转换为简洁的双行字幕条，适用于会议、通话、直播和视频。一边听原语言，一边读翻译，无需切换窗口。",
        ctaDownload: "下载 macOS 版",
        ctaQuickStart: "快速开始",
        ctaSource: "查看源码",
        demoTranslation: "欢迎回来，很高兴你能参加今天的通话。",
        demoSource: "Welcome back — glad you could join today's call.",
        demoWindow: "Zoom — 团队站会",
        imgAlt: "TranslaMic 在视频会议上的字幕叠加效果",
      },
      highlights: {
        h1Title: "隐私优先",
        h1Body: "无需账号、分析或云端后台。音频与字幕通过 Apple 本地框架留在你的 Mac 上。",
        h2Title: "菜单栏即用",
        h2Body: "始终一键可达。开始、停止与语言设置，无需离开会议或播放器全屏。",
        h3Title: "自选音频源",
        h3Body: "捕获麦克风或指定运行中应用的音频 — 而非整个系统混音。",
      },
      features: {
        eyebrow: "功能特性",
        title: "为实时对话而生，而非后期制作。",
        lead: "跟随另一种语言的现场语音所需的一切，无需在浏览器标签与笨重字幕应用之间来回切换。",
        f1Title: "实时悬浮字幕",
        f1Body: "第一行显示翻译，第二行显示原文 — 便于即时对照。",
        f2Title: "按应用捕获",
        f2Body: "将 Zoom、Teams、浏览器或播放器设为输入源，桌面其余部分保持安静。",
        f3Title: "Apple SpeechAnalyzer",
        f3Body: "基于 Apple 本地语音识别，适配 Mac 支持的语言。",
        f4Title: "Apple Translation",
        f4Body: "本地翻译；部分语言包可在系统设置中按需下载。",
        f5Title: "AI 摘要",
        f5Body: "长会后可用 Apple Intelligence 快速回顾字幕记录要点。",
        f6Title: "可读样式",
        f6Body: "调节悬浮条外观，在幻灯片、代码或深色视频上保持清晰可读。",
      },
      howItWorks: {
        eyebrow: "使用方式",
        title: "三步：从下载到字幕。",
        step1Title: "安装",
        step1Body: "下载并安装最新 <code>translamic-x.y.z.pkg</code>，然后重启 macOS。",
        step2Title: "配置",
        step2Body: "选择麦克风或应用音频，设置输入与字幕语言，首次使用时授予权限。",
        step3Title: "开始",
        step3Body: "在菜单栏点击 Start — 字幕实时出现在屏幕顶部。",
        caption: "菜单栏控制与语言设置",
        imgAlt: "TranslaMic 设置界面与菜单栏",
      },
      inputLangs: {
        eyebrow: "输入语言",
        title: "Apple 语音路径支持的十种语言。",
        lead: "TranslaMic 仅列出 SpeechAnalyzer/SpeechTranscriber 支持的语言；地区变体合并为 Apple 的默认区域。",
        noteBefore: "字幕（输出）语言取决于 Mac 上 Apple Translation 的可用性。 ",
        readmeLink: "阅读完整 README →",
        readmeHref: "https://github.com/Techeek/translamic/blob/main/README.zh-CN.md",
        chipCantonese: "粤语",
        chipZh: "简体中文",
        chipEn: "英语",
        chipFr: "法语",
        chipDe: "德语",
        chipIt: "意大利语",
        chipJa: "日语",
        chipKo: "韩语",
        chipPt: "葡萄牙语",
        chipEs: "西班牙语",
      },
      privacy: {
        eyebrow: "隐私保护",
        title: "会议内容留在你的机器上。",
        li1: "无需账号、云端后台、分析或遥测",
        li2: "音频与字幕文本不会通过 TranslaMic 离开 Mac",
        li3: "语音与翻译使用 Apple 本地框架",
        li4: "仅在需要时请求语音、麦克风或应用音频捕获权限",
      },
      quickStart: {
        eyebrow: "快速开始",
        title: "几分钟内从下载到首条字幕。",
        s1Title: "下载",
        s1Body: "从 GitHub Releases 获取最新 <code>translamic-x.y.z.pkg</code>。",
        s2Title: "安装",
        s2Body: "安装软件包并重启 macOS，然后从菜单栏启动 TranslaMic。",
        s3Title: "从源码构建",
        s3Body: "需要 Xcode 与 macOS 26+（语音与翻译 API）。",
        copy: "复制",
        copied: "已复制",
        copyFailed: "失败",
        copyCmd: "复制命令",
        copyCmds: "复制命令",
        permsTitle: "首次运行权限",
        perm1Title: "语音识别",
        perm1Body: "将音频转写为文本",
        perm2Title: "麦克风",
        perm2Body: "使用麦克风作为输入时",
        perm3Title: "音频捕获",
        perm3Body: "捕获其他应用音频时",
      },
      cta: {
        title: "准备好听懂每一句话？",
        body: "免费开源，为 macOS 打造。下载 TranslaMic，让对话更易理解。",
        download: "下载最新版",
        star: "在 GitHub 标星",
      },
      footer: {
        license: "MIT 许可证 · ",
        docLink: "English Doc",
        docHref: "https://github.com/Techeek/translamic/blob/main/README.md",
      },
    },
  };

  function getNested(obj, path) {
    return path.split(".").reduce((o, k) => (o && o[k] !== undefined ? o[k] : null), obj);
  }

  function detectLang() {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "en" || stored === "zh") return stored;
    const browser = (navigator.language || "").toLowerCase();
    return browser.startsWith("zh") ? "zh" : "en";
  }

  let currentLang = detectLang();

  function t(key) {
    return getNested(strings[currentLang], key) ?? getNested(strings.en, key) ?? "";
  }

  function applyLang(lang) {
    currentLang = lang === "zh" ? "zh" : "en";
    localStorage.setItem(STORAGE_KEY, currentLang);

    const htmlLang = currentLang === "zh" ? "zh-CN" : "en";
    document.documentElement.lang = htmlLang;
    document.documentElement.dataset.lang = currentLang;

    document.title = t("meta.title");
    const metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc) metaDesc.setAttribute("content", t("meta.description"));

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      const value = t(key);
      if (value == null || value === "") return;
      if (el.hasAttribute("data-i18n-html")) {
        el.innerHTML = value;
      } else {
        el.textContent = value;
      }
    });

    document.querySelectorAll("[data-i18n-attr]").forEach((el) => {
      const spec = el.getAttribute("data-i18n-attr");
      if (!spec) return;
      spec.split(";").forEach((pair) => {
        const [attr, key] = pair.split(":").map((s) => s.trim());
        if (attr && key) el.setAttribute(attr, t(key));
      });
    });

    document.querySelectorAll("[data-i18n-href]").forEach((el) => {
      const key = el.getAttribute("data-i18n-href");
      if (key) el.setAttribute("href", t(key));
    });

    document.querySelectorAll(".lang-option").forEach((btn) => {
      const active = btn.getAttribute("data-lang") === currentLang;
      btn.classList.toggle("is-active", active);
      btn.setAttribute("aria-pressed", String(active));
    });

    document.dispatchEvent(new CustomEvent("TranslaMic:langchange", { detail: { lang: currentLang } }));
  }

  function initLangToggle() {
    document.querySelectorAll(".lang-option").forEach((btn) => {
      btn.addEventListener("click", () => {
        const lang = btn.getAttribute("data-lang");
        if (lang && lang !== currentLang) applyLang(lang);
      });
    });
  }

  global.V2sI18n = {
    t,
    applyLang,
    initLangToggle,
    getLang: () => currentLang,
    detectLang,
  };

  applyLang(currentLang);
})(window);
