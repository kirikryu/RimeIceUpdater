# 设计取舍

维护者笔记，记录 RimeIceUpdater 的设计决策与背景。使用说明见 [README](README.md)。

- 普通窗口而非菜单栏常驻：这是个“设置完就能关”的工具，定时更新由 launchd 负责，常驻状态栏没有意义；
  关窗即退出，未保存的脚本修改靠 `.editor-draft` 草稿跨会话保留；
- 脚本编辑放在「设置 → 高级」的二级页面而非首页：直接改脚本属于进阶操作，普通用户的自定义
  用设置表单即可完成；
- 计划采用经典的“每周几 + 时刻”模型（launchd `StartCalendarInterval` 原生支持，睡眠错过自动补跑），
  而非“每 N 天”间隔闸门——后者需要脚本内 gating 与锚点文件，复杂且不直观；从旧“每 N 天”版本升级时，
  安装会自动把每日触发的 plist 换回每周触发；
- 「安装」只补缺失件、不覆盖已有件（脚本本体除外，它就是被安装的对象）：重复安装安全，
  手改过的 `updater.conf` 与已加载的计划任务不会被冲掉；升级引擎走「恢复内置版本」+「保存并安装」；
- 引擎保留 bash 而非 Swift 重写：逻辑已长期验证，App 只做编辑/安装/设置/状态，风险最小；
- 通知经独立 helper App：osascript 的 `display notification` 在 macOS 15 被静默丢弃，
  `RimeNotify.app`（UNUserNotificationCenter）随引擎一起安装并已内置授权引导；它与主程序共用同一份
  二进制（`Sources/NotifyCLI.swift`，带结果 key 参数启动时只发通知即退出），因为定时任务由 launchd 触发，
  主程序可能未运行，通知必须来自路径稳定的独立 bundle；
- launchd 计划沿用 `local.rime-ice-dict-updater` label，与手动安装时代无缝衔接。
