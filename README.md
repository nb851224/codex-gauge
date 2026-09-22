# Codex Gauge

Codex Gauge 是一个极简的 macOS 菜单栏用量监控器。它直接读取本机 Codex App Server 的账户额度，不会发起模型对话。

当前版本：`0.2.1`

## 界面

菜单栏常态显示双层圆环和剩余百分比：外圈表示剩余用量，内圈表示当前额度周期的剩余时间。点开后显示：

- 剩余用量
- 距离下次重置的时间
- 自动识别套餐；Plus 同时显示 5 小时和周额度，Pro 显示主额度
- 按剩余时间分配的每日额度
- 账户的可用重置卡数量、最早过期时间和卡片明细

应用不做用量预警，不申请系统通知权限。
重置卡页面只展示信息，不会自动使用卡片。

## 构建和运行

需要 macOS 13 或更高版本、Swift 5.10+，以及已登录的 Codex CLI。

    cd codex-gauge
    chmod +x Scripts/build-app.sh
    Scripts/build-app.sh
    open "dist/Codex Gauge.app"

也可在开发时直接运行：

    swift run CodexGauge

## 隐私和用量

- 数据来自本机 codex app-server --stdio。
- 不调用模型，不会为刷新额外生成 Codex 推理用量。
- 用量样本只保存在本机 UserDefaults，最长保留 30 天。
- 收到 App Server 用量更新时立即刷新，另每 5 分钟兜底刷新。
- 每次点击菜单栏百分比打开面板时，也会立即查询一次最新用量。
