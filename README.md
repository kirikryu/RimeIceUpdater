# 雾凇词库更新器 (RimeIceUpdater)

中文 | [English](README.en.md)

一个普通窗口小工具，让 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) 词库保持自动更新。
**不需要东风破（plum）、不需要命令行**：装好本 App 点一次"安装"，之后官方词库会按你设定的节奏
自动检查、下载、覆盖安装并触发鼠须管重新部署，结果推送到通知中心（中文）。
更新引擎是经过实战加固的 bash 脚本（版本门槛 + 失败重试 + 并发锁），本 App 负责安装、编辑、设置与状态展示。

安装完成后即可关闭本应用——定时更新由系统的计划任务（launchd）执行，不依赖本应用保持打开；
关闭窗口即退出本应用，需要时再从"应用程序"打开。

## 快速上手（三步）

1. 把 `RimeIceUpdater.app` 拖入"应用程序"文件夹，在 Finder 中**右键 → 打开**一次（应用未签名，首次需要这样绕过 Gatekeeper）；
2. 打开后在「状态」页点 **安装并启用自动更新**；
3. 完成。之后每次更新结果会以中文通知推送，可随时打开 App 查看状态。

## 两个页面

- **状态**（默认首页）：当前词库版本、上次运行结果、检查频率与下次运行时间、鼠须管/Rime 目录健康检测；
  **立即检查更新**实时显示运行输出；**打开日志**在 Finder 中定位 `update.log`。未安装时给一个大按钮
  **安装并启用自动更新**，一步完成。
- **设置**：计划与代理等参数（见下表）与卸载入口。底部「高级」里有 **更新脚本…** 二级页面，可图形化
  查看与修改更新引擎脚本——已安装时编辑 `~/Library/Rime/scripts/` 里的副本，未安装时显示内置初始版本；
  点 **保存并安装** 写入磁盘（原子写入 + 可执行权限，立即生效，无需重载定时任务）。**恢复内置版本**可把
  旧安装升级为本 App 自带的最新引擎或撤销手改。脚本要求纯 ASCII（兼容 macOS 自带 bash 3.2），页脚实时
  统计非 ASCII 字符，安装前会提示确认。编辑内容自动暂存为草稿（`scripts/.editor-draft`），关窗、退出甚至
  崩溃都不会丢，安装或"放弃修改"后清除。

## 设置说明

| 设置 | 说明 |
|---|---|
| 计划运行 | 每周几（周一–周日，默认周一）+ 几点（launchd 定点触发；睡眠错过会在唤醒后补跑） |
| 通知 | 关闭后不再推送运行结果（日志仍记录） |
| 代理地址/端口 | 引擎始终通过该代理访问 GitHub（默认 `127.0.0.1:7890`） |
| 代管 FlClash | 开：代理不可用时自动启动/重启 FlClash，结束后自动关闭自己启动的实例（合盖定时任务也不会留下窗口）。
  关：手动代理模式，只使用已开启的系统代理，代理不通时跳过本次检查 |
| Bundle ID | 代管的代理 App 标识（默认 `com.follow.clash`） |

设置保存在 `~/Library/Rime/scripts/updater.conf`，可以直接手改（App 安装时只在缺失时生成，不会覆盖你的手改）。

## 系统要求

- macOS 15+
- Squirrel（鼠须管）输入法，配置目录 `~/Library/Rime`

## 文件布局

```
~/Library/Rime/scripts/update-rime-ice-dicts.sh   引擎脚本（可在"脚本"页图形化编辑）
~/Library/Rime/scripts/.editor-draft              未安装修改的自动草稿（隐藏文件）
~/Library/Rime/scripts/updater.conf               设置（App 生成/手改）
~/Library/Rime/scripts/RimeNotify.app             通知助手（中文通知走它；osascript 通知在 macOS 15 被系统静默丢弃）
~/Library/Rime/scripts/update.log                 运行日志（超 1MB 自动轮转为 update.log.1）
~/Library/Rime/scripts/last-version               已安装版本
~/Library/Rime/scripts/last-status                上次运行结果（时间|结果|键，状态页读它）
~/Library/LaunchAgents/local.rime-ice-dict-updater.plist   每周定点计划（周几与时刻可设置）
```

## 卸载

打开 **设置** 页 → 底部 **卸载…** → 确认。移除计划任务、更新脚本、通知助手与编辑草稿；
词库与日志保留。卸载后本应用不再自动退出，可随时到「设置 → 高级 → 更新脚本」重新安装。

## 常见问题

- **没收到通知**：系统设置 → 通知 → RimeNotify → 允许通知（横幅）。
  诊断：`~/Library/Rime/scripts/RimeNotify.app/Contents/MacOS/RimeNotify --status`，`auth=2` 为正常。
- **打开提示"无法验证开发者"**：右键 → 打开；或在系统设置 → 隐私和安全性里点"仍要打开"。
- **每次都提示 GitHub 不可达**：检查代理是否可用、端口是否与设置一致；手动代理模式下需保证系统代理已开启。
- **关掉窗口后更新还会跑吗**：会。定时更新由系统计划任务执行，与本应用是否打开无关；需要改设置时再打开本应用。
- **为什么不能自定义词库目录**：鼠须管（macOS 版）在所有版本中都把用户目录硬编码为
  `~/Library/Rime`——安装器没有选项、配置文件与 librime 也没有覆盖机制（`RimeUserDir` 是
  Windows 小狼毫的注册表项）。更新器只能也必须写入该目录；若你把它做成了符号链接（如指向
  同步盘），更新会穿透链接写入真实目录，状态页会显示实际位置。

## 构建

```bash
./build.sh   # 产物: build/RimeIceUpdater.app（ad-hoc 签名）
```

需要 Xcode Command Line Tools（swiftc）。引擎逻辑修改只需编辑 `Resources/update-rime-ice-dicts.sh`（保持纯 ASCII），
也可以发布后在「脚本」页直接改已安装副本。

## 设计取舍

- 普通窗口而非菜单栏常驻：这是个"设置完就能关"的工具，定时更新由 launchd 负责，常驻状态栏没有意义；
  关窗即退出，未保存的脚本修改靠 `.editor-draft` 草稿跨会话保留；
- 脚本编辑放在「设置 → 高级」的二级页面而非首页：直接改脚本属于进阶操作，普通用户的自定义
  用设置表单即可完成；
- 计划采用经典的"每周几 + 时刻"模型（launchd `StartCalendarInterval` 原生支持，睡眠错过自动补跑），
  而非"每 N 天"间隔闸门——后者需要脚本内 gating 与锚点文件，复杂且不直观；从旧"每 N 天"版本升级时，
  安装会自动把每日触发的 plist 换回每周触发；
- 「安装」只补缺失件、不覆盖已有件（脚本本体除外，它就是被安装的对象）：重复安装安全，
  手改过的 `updater.conf` 与已加载的计划任务不会被冲掉；升级引擎走「恢复内置版本」+「保存并安装」；
- 引擎保留 bash 而非 Swift 重写：逻辑已长期验证，App 只做编辑/安装/设置/状态，风险最小；
- 通知经独立 helper App：osascript 的 `display notification` 在 macOS 15 被静默丢弃，
  `RimeNotify.app`（UNUserNotificationCenter）随引擎一起安装并已内置授权引导；它与主程序共用同一份
  二进制（`Sources/NotifyCLI.swift`，带结果 key 参数启动时只发通知即退出），因为定时任务由 launchd 触发，
  主程序可能未运行，通知必须来自路径稳定的独立 bundle；
- launchd 计划沿用 `local.rime-ice-dict-updater` label，与手动安装时代无缝衔接。

## 许可证

[MIT](LICENSE)
