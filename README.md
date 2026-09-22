# Codex Gauge

[English](README.md) · [简体中文](README.zh-CN.md)

A quiet, open-source macOS menu-bar gauge that shows your remaining Codex usage before it interrupts your flow. It reads account limits from the local Codex App Server and never starts a model conversation.

一个安静、开源的 macOS 菜单栏工具，在工作被额度打断之前显示 Codex 剩余用量。它从本机 Codex App Server 读取账户额度，不会发起模型对话。

Current version: `0.2.7` · Unofficial community project, not affiliated with OpenAI.

![Codex Gauge shows remaining Codex limits before they interrupt your flow](Media/campaign/codex-gauge-hero-en.png)

## What it shows

The compact menu-bar icon keeps the essentials visible: the outer ring shows remaining usage, the translucent inner sector shows remaining time in the current quota cycle, and the center shows the usage number without a redundant percent sign. Both indicators start at 12 o'clock. Hover over the icon to open the panel; move away from both the icon and panel to close it.

Open the panel to see:

- Remaining usage and time until reset
- Automatic plan detection with no manual switch
- Separate 5-hour and weekly quotas for Plus
- A focused primary-quota view for Pro / Prolite
- Daily allowance distributed across the remaining cycle
- Available reset cards and their earliest expiration
- English and Simplified Chinese, following the macOS system language

Codex Gauge does not send usage alerts or request notification permission. Reset cards are displayed only and are never consumed automatically.

![Codex Gauge adapts its quota view for Plus and Pro](Media/campaign/codex-gauge-plus-pro.png)

## Install the release

Download `Codex-Gauge-v0.2.7-macOS-arm64.zip` from [GitHub Releases](https://github.com/nb851224/codex-gauge/releases), unzip it, and open `Codex Gauge.app`.

The current prebuilt release supports Apple Silicon and requires macOS 13 or later. Intel users can build from source.

The app is locally signed but not Apple-notarized. If macOS blocks the first launch, right-click the app in Finder and choose **Open**, or build it from source.

## Build from source

Requirements: macOS 13 or later, Swift 5.10+, and a signed-in Codex CLI.

```bash
cd codex-gauge
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
open "dist/Codex Gauge.app"
```

For development:

```bash
swift run CodexGauge
```

## Privacy and quota usage

- Reads data from the local `codex app-server --stdio` process.
- Makes no model calls, so refreshing does not generate additional Codex inference usage.
- Stores usage samples only in local `UserDefaults` for up to 30 days.
- Refreshes when the App Server reports an update, with a five-minute fallback refresh.
- Refreshes immediately whenever the menu-bar percentage is clicked.
- Uses no API key and collects no telemetry.

![Codex Gauge runs locally without API keys, model calls, or telemetry](Media/campaign/codex-gauge-local-privacy.png)

## Early feedback

If you use Codex Plus, Pro, or Prolite, please share your experience in the [early-feedback thread](https://github.com/nb851224/codex-gauge/issues/1). We especially want to know whether your plan and quota are detected correctly, whether the two-layer menu-bar gauge is clear at a glance, and whether you need Intel, Homebrew, or an Apple-notarized build.

## License

[MIT License](LICENSE)
