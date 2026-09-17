import Foundation
import UserNotifications

// Notification helper mode for the updater engine. RimeNotify.app (bundled
// in this app, released at install time into ~/Library/Rime/scripts/) is
// assembled from this very binary by build.sh. The engine script launches it
// from its launchd context - where this menu bar app may not be running -
// with the same interface the standalone helper always had:
//   RimeNotify <key> [arg ...]   post a localized notification
//   RimeNotify --status          print authorization state and exit
// osascript's display notification is silently dropped on macOS 15, hence
// this bundle-backed path. The script passes ASCII keys + args only (its
// source must stay ASCII for bash 3.2); wording is picked here by system
// language (Chinese / English).
enum NotifyCLI {
    // Called from the app's init: when the binary was launched with helper
    // arguments, serve the request and exit before any UI exists. A normal
    // launch passes no arguments, so this is a no-op for the menu bar app.
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--status") {
            printStatusAndExit()
        }
        if let key = args.first, !key.hasPrefix("-") {
            post(key: key, args: Array(args.dropFirst()))
        }
    }

    // auth= values: 0 notDetermined, 1 denied, 2 authorized, 3 provisional,
    // 4 ephemeral.
    private static func printStatusAndExit() {
        let probe = UNUserNotificationCenter.current()
        let done = DispatchSemaphore(value: 0)
        probe.getNotificationSettings { settings in
            print("auth=\(settings.authorizationStatus.rawValue)")
            print("alerts=\(settings.alertSetting.rawValue)")
            print("sound=\(settings.soundSetting.rawValue)")
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        exit(0)
    }

    private static func post(key: String, args fnArgs: [String]) {
        let title = isZh ? "Rime 词典更新" : "Rime dict update"

        // (english, chinese) per key; %@ placeholders are filled from fnArgs
        let table: [String: (String, String)] = [
            "flclash_stop_failed": ("FAILED: cannot stop old FlClash, abort",
                                    "失败：无法退出旧的 FlClash，已中止"),
            "flclash_launch_failed": ("FAILED: could not launch FlClash",
                                      "失败：无法启动 FlClash"),
            "proxy_timeout": ("Skipped: system proxy not up after 90s",
                              "已跳过：90 秒内系统代理未就绪"),
            "proxy_not_ready": ("Skipped: proxy not running (manual proxy mode)",
                                "已跳过：代理未运行（手动代理模式）"),
            "github_unreachable": ("Skipped: GitHub unreachable via proxy",
                                   "已跳过：经代理无法访问 GitHub"),
            "no_last_modified": ("Skipped: no Last-Modified from GitHub",
                                 "已跳过：GitHub 未返回 Last-Modified"),
            "bad_last_modified": ("Skipped: cannot parse Last-Modified",
                                  "已跳过：无法解析 Last-Modified 时间"),
            "up_to_date": ("Already up to date (%@)", "已是最新版本（%@）"),
            "download_failed": ("FAILED: download failed after retries",
                                "失败：多次重试后下载仍未成功"),
            "zip_corrupt": ("FAILED: zip integrity check",
                            "失败：压缩包完整性校验未通过"),
            "zip_missing": ("FAILED: zip missing %@", "失败：压缩包缺少 %@"),
            "updated_deployed": ("Updated to %@, deploy triggered",
                                 "已更新到 %@，已触发重新部署"),
            "updated_deploy_manually": ("Updated to %@, deploy Squirrel manually!",
                                        "已更新到 %@，请手动部署 Squirrel！"),
        ]

        let body: String
        if let entry = table[key] {
            body = String(format: isZh ? entry.1 : entry.0, arguments: fnArgs)
        } else {
            // unknown key: pass the raw arguments through so nothing is silently lost
            body = ([key] + fnArgs).joined(separator: " ")
        }

        let center = UNUserNotificationCenter.current()
        let authDone = DispatchSemaphore(value: 0)
        center.requestAuthorization(options: [.alert, .sound, .provisional]) { _, _ in
            authDone.signal()
        }
        _ = authDone.wait(timeout: .now() + 30)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let addDone = DispatchSemaphore(value: 0)
        center.add(request) { error in
            if let error {
                FileHandle.standardError.write(Data("add_error=\(error)\n".utf8))
                exit(1)
            }
            addDone.signal()
        }
        _ = addDone.wait(timeout: .now() + 5)
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        exit(0)
    }
}
