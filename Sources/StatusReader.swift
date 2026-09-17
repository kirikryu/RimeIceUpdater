import Foundation

struct RunRecord: Equatable {
    let timeText: String
    let label: String
    let isOK: Bool
}

enum StatusReader {
    static func currentVersion() -> String? {
        guard let raw = try? String(contentsOf: Paths.stateFile, encoding: .utf8) else { return nil }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static func prettyVersion(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "GMT")
        guard let d = f.date(from: iso) else { return iso }
        return d.formatted(date: .numeric, time: .shortened)
    }

    // last-status is written by the engine script at every terminal outcome:
    // "time|ok-or-fail|key args" (notify_result there).
    static func lastRun() -> RunRecord? {
        guard let raw = try? String(contentsOf: Paths.statusFile, encoding: .utf8) else { return nil }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let key = parts[2].split(separator: " ").first, !key.isEmpty else {
            return nil
        }
        return RunRecord(timeText: String(parts[0].prefix(16)),
                         label: outcomeLabel(String(key)),
                         isOK: parts[1] == "ok")
    }

    // Keys are the stable ASCII identifiers from the script's notify_result
    // call sites; this table is display wording only.
    private static func outcomeLabel(_ key: String) -> String {
        switch key {
        case "updated_deployed", "updated_deploy_manually":
            return L("已更新完成", "Updated")
        case "up_to_date":
            return L("已是最新版本", "Already up to date")
        case "github_unreachable":
            return L("GitHub 不可达", "GitHub unreachable")
        case "download_failed":
            return L("下载失败", "Download failed")
        case "zip_corrupt":
            return L("压缩包校验失败", "Zip check failed")
        case "zip_missing":
            return L("压缩包缺文件", "Zip missing files")
        case "proxy_timeout":
            return L("代理未就绪", "Proxy not ready")
        case "proxy_not_ready":
            return L("代理未运行", "Proxy not running")
        case "flclash_stop_failed":
            return L("无法退出 FlClash", "Cannot stop FlClash")
        case "flclash_launch_failed":
            return L("无法启动 FlClash", "Cannot launch FlClash")
        case "no_last_modified", "bad_last_modified":
            return L("版本响应异常", "Bad version response")
        default:
            return L("已跳过", "Skipped")
        }
    }
}
