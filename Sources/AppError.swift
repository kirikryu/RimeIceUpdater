import Foundation

enum AppError: LocalizedError {
    case embeddedScriptMissing
    case launchctlBootstrapFailed(String)

    var errorDescription: String? {
        switch self {
        case .embeddedScriptMissing:
            return L("应用资源缺失：内嵌引擎脚本未找到",
                     "App resources broken: embedded engine not found")
        case .launchctlBootstrapFailed(let detail):
            return L("launchctl 加载失败：", "launchctl bootstrap failed: ") + detail
        }
    }
}
