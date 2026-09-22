# Codex Gauge 早期验证发布包

## 这一轮要验证什么

不是先验证“大家喜不喜欢界面”，而是验证三个更具体的问题：

1. 高频 Codex 用户会不会因为无法随时看见 5 小时与周额度而被工作中断。
2. Plus 与 Pro / Prolite 的差异化界面是否符合真实账户返回的数据。
3. “菜单栏一眼看见、本地读取、不产生额外模型用量”是否足以促使用户安装。

统一落点：https://github.com/nb851224/codex-gauge

反馈入口：https://github.com/nb851224/codex-gauge/issues/1

## Reddit：r/codex

**标题**

I kept getting surprised by Codex limits, so I built a local macOS menu-bar gauge. Does this match how you think about quota?

**正文**

I use Codex throughout the day and wanted one quiet place to see what matters before a limit interrupts the flow: remaining usage and time until reset.

So I built Codex Gauge, an open-source macOS menu-bar utility. It reads the local Codex App Server, makes no model calls, uses no API key, and has no telemetry. Plus accounts get separate 5-hour and weekly views; Pro / Prolite get the simpler view their account data supports. Clicking the menu-bar percentage refreshes it immediately.

I’m looking for early feedback rather than stars:

- Does it identify your plan and limits correctly?
- Is the outer usage ring + inner time sector understandable at a glance?
- What would block you from installing it: Apple notarization, Homebrew, or Intel support?

GitHub: https://github.com/nb851224/codex-gauge

Unofficial community project, not affiliated with OpenAI.

配图：`codex-gauge-hero-en.png`，评论补充 `codex-gauge-plus-pro.png`。

## Reddit：r/ChatGPTCoding 周度自荐帖

I built **Codex Gauge**, a small open-source macOS menu-bar utility for people who use Codex heavily and want to see their remaining 5-hour / weekly quota before it interrupts a coding session.

It reads the local Codex App Server, makes no model calls, needs no API key, and collects no telemetry. The interface adapts automatically for Plus versus Pro / Prolite accounts.

I’d especially value feedback on whether the two-layer menu-bar gauge is understandable and whether notarization or Homebrew is essential for installation.

https://github.com/nb851224/codex-gauge

配图：`codex-gauge-plus-pro.png`。

## V2EX：分享创造

**标题**

[macOS] 做了一个 Codex 菜单栏用量小工具，想验证 Plus / Pro 的真实使用体验

**正文**

我使用 Codex 时最困扰的不是“总共用了多少”，而是工作进行到一半才发现 5 小时额度或周额度快没了。为此做了 Codex Gauge：平时只在菜单栏显示一个比例圆环和剩余百分比，点开后再看重置时间与额度细节。

目前的产品取舍：

- Plus 显示 5 小时和周额度；Pro / Prolite 按账户数据显示精简界面
- 点击菜单栏数字时立即刷新，平时安静运行
- 本地读取 Codex App Server，不需要 API Key，不调用模型，不收集遥测
- 不做预警、不发通知，避免把一个查看工具做得太吵

这是非官方开源项目，目前发布包支持 Apple Silicon，尚未做 Apple 公证。希望找真实用户帮忙验证三件事：套餐识别是否准确、圆环是否一眼能看懂、安装上最需要先补 Homebrew、公证还是 Intel 支持。

项目与下载：https://github.com/nb851224/codex-gauge

配图：首图使用 `codex-gauge-hero-en.png`，正文补充 `codex-gauge-local-privacy.png`。

## Product Hunt（准备完成后再发）

建议在 Universal Binary、Apple 公证和 Homebrew Cask 至少完成其中两项后再正式发布，避免首次曝光被安装摩擦消耗掉。

**Tagline**

See your Codex limits before they interrupt your flow.

**Short description**

Codex Gauge is a quiet, open-source macOS menu-bar utility that shows remaining Codex usage and time to reset. It adapts to Plus and Pro accounts, refreshes on click, makes no model calls, and collects no telemetry.

## 7 天验证记录

每个渠道只记录这五项，避免被浏览量误导：

| 指标 | 说明 |
| --- | --- |
| 有效反馈数 | 描述了套餐、额度或安装体验的回复 |
| 下载点击数 | GitHub Release asset 下载量增量 |
| 安装成功数 | 用户明确确认已经运行 |
| 数据正确数 | Plus / Pro / Prolite 的识别和额度均正确 |
| 阻塞原因 | 公证、Homebrew、Intel、权限或数据缺失 |

第一轮判断标准：收集至少 10 个有效反馈，其中至少 3 个 Plus 和 3 个 Pro / Prolite；如果超过三分之一的人卡在同一安装问题，优先修复该问题，再扩大传播。
