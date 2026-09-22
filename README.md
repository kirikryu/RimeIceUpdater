# RimeIceUpdater

中文 | [English](README.en.md)

让 [雾凇拼音](https://github.com/iDvel/rime-ice) 词库自动更新的 macOS 小工具。无需 plum，无需命令行。

安装一次后，词库会按设定的时间自动检查、下载并部署，结果通过系统通知推送。

## 特性

- 一键安装并启用自动更新；之后由系统的 launchd 计划任务执行，本应用可以关闭
- 按「每周几 + 几点」设定检查时间，睡眠错过的任务在唤醒后补跑
- 更新结果推送系统通知
- 在应用内编辑更新脚本与代理设置，脚本修改自动暂存草稿，关窗不丢
- 状态页显示已装词库版本、上次运行结果、下次运行时间，并检测 Rime 目录健康
- 重复安装安全：只补缺失文件，手改过的配置与已加载的计划任务不会被覆盖

## 安装

从 [Releases](https://github.com/kirikryu/RimeIceUpdater/releases) 下载最新的 zip，解压得到 `RimeIceUpdater.app`。

需要 macOS 15 或更高版本，Apple Silicon（M 系列芯片）。另需先装好 [Squirrel（鼠须管）](https://github.com/rime/squirrel) 并至少运行过一次，`~/Library/Rime` 目录已生成。

1. 把 `RimeIceUpdater.app` 拖入“应用程序”文件夹；
2. 在 Finder 中右键点击它，选择“打开”。应用未签名，首次启动需要这样绕过 Gatekeeper；若仍被拦截，到“系统设置 → 隐私和安全性”点“仍要打开”；
3. 在「状态」页点 `安装并启用自动更新`。

完成后，检查、下载与部署都由系统的计划任务执行，应用可以关闭。需要改设置时再打开。

## 使用

### 状态页

打开应用默认进入这一页，显示当前词库版本、上次运行结果、检查频率与下次运行时间，并检测 Rime 目录是否正常。

- `立即检查更新`：马上运行一次，实时显示输出
- `打开日志`：在 Finder 中定位 `update.log`
- 尚未安装时，页面中央是一个 `安装并启用自动更新` 按钮

### 设置页

| 设置 | 说明 |
|---|---|
| 计划运行 | 每周的哪一天、几点执行，默认周一。睡眠期间错过的任务在唤醒后补跑 |
| 通知 | 关闭后不再推送结果，日志照常记录 |
| 代理地址 / 端口 | 引擎通过它访问 GitHub，默认 `127.0.0.1:7890` |
| 代管 FlClash | 开启后，代理不可用时自动启动或重启代理应用，结束后关闭由自己启动的实例；关闭则只使用已开启的系统代理，代理不通时跳过本次检查 |
| Bundle ID | 代管代理应用的标识，默认 `com.follow.clash` |

设置保存在 `~/Library/Rime/scripts/updater.conf`，可以直接手动编辑。应用只在文件缺失时生成，不会覆盖手改内容。

### 更新脚本

「设置 → 高级 → 更新脚本…」用于查看和修改更新引擎。

- 已安装时编辑 `~/Library/Rime/scripts/` 下的副本，未安装时显示内置版本
- `保存并安装` 写入磁盘并立即生效，无需重载计划任务
- `恢复内置版本` 可把旧安装升级为当前应用自带的引擎，或撤销手改
- 脚本要求纯 ASCII（兼容 macOS 自带的 bash 3.2），页脚会实时统计非 ASCII 字符

编辑内容自动存为草稿 `scripts/.editor-draft`，关窗或退出都不会丢，安装或放弃修改后清除。

## 文件

除计划任务外，所有文件都在 `~/Library/Rime/scripts/`：

- `update-rime-ice-dicts.sh` — 更新引擎，可在应用内编辑
- `updater.conf` — 设置，可手动编辑
- `.editor-draft` — 未安装的脚本修改草稿
- `RimeNotify.app` — 发送系统通知的助手应用
- `update.log` — 运行日志，超过 1 MB 自动轮转为 `update.log.1`
- `last-version` — 已安装词库版本
- `last-status` — 上次运行结果，状态页读取

计划任务位于 `~/Library/LaunchAgents/local.rime-ice-dict-updater.plist`。

## 卸载

在「设置」页底部点 `卸载…`，确认即可。这会移除计划任务、更新脚本、通知助手和编辑草稿；词库与日志保留。

之后可以随时在「设置 → 高级 → 更新脚本」中重新安装。若要彻底移除本应用，把 `RimeIceUpdater.app` 拖入废纸篓即可。

## 常见问题

- **没收到通知**：到“系统设置 → 通知 → RimeNotify”允许通知。诊断命令，`auth=2` 为正常：

  ```
  ~/Library/Rime/scripts/RimeNotify.app/Contents/MacOS/RimeNotify --status
  ```

- **打开时提示“无法验证开发者”**：在 Finder 中右键点击应用，选择“打开”。若仍被拦截，到“系统设置 → 隐私和安全性”点“仍要打开”。

- **每次都提示 GitHub 不可达**：检查代理是否可用、端口是否与设置一致。手动代理模式下需保证系统代理已开启。

- **关掉窗口后更新还会跑吗**：会。定时更新由系统计划任务执行，与应用是否打开无关。需要改设置时再打开应用。

- **为什么不能自定义词库目录**：鼠须管把用户目录固定在 `~/Library/Rime`，安装器没有选项，配置文件和 librime 也没有覆盖机制。更新器只能写入该目录。若该路径是指向别处的符号链接，写入会穿透链接，状态页会显示实际位置。

## 构建

从源码构建，仅供开发和调试使用。

```bash
./build.sh   # 产物：build/RimeIceUpdater.app，ad-hoc 签名
```

只需 Xcode Command Line Tools，它提供 `swiftc` 和 `codesign`。全新的 Mac 上首次运行会提示安装，点「安装」等下载完成，约 1–2 GB，无需完整 Xcode。其余工具如 bash、plutil 都是 macOS 自带。

在终端中 `cd` 到仓库目录，执行 `bash build.sh`。也可以在 Finder 中右键 `build.sh`，选择「打开方式 → 终端」；双击默认用文本编辑器打开，不会执行。脚本结束时会停留等待按键，输出和报错不会随窗口消失。

本地构建的产物没有隔离属性，不会被 Gatekeeper 拦截。

引擎逻辑的修改在 `Resources/update-rime-ice-dicts.sh`，保持纯 ASCII。发布后也可以直接在「设置 → 高级 → 更新脚本」中修改已安装的副本。

设计决策的完整记录见 [DESIGN.md](DESIGN.md)。

## 许可证

[MIT](LICENSE)
