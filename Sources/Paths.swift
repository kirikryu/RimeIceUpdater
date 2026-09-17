import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let label = "local.rime-ice-dict-updater"

    // Squirrel hardcodes this as its user data dir in every release, so the
    // updater must target exactly here too (symlinks are followed by both).
    static var rimeDir: URL { home.appendingPathComponent("Library/Rime", isDirectory: true) }
    static var scriptsDir: URL { rimeDir.appendingPathComponent("scripts", isDirectory: true) }
    static var script: URL { scriptsDir.appendingPathComponent("update-rime-ice-dicts.sh") }
    static var conf: URL { scriptsDir.appendingPathComponent("updater.conf") }
    static var helperApp: URL { scriptsDir.appendingPathComponent("RimeNotify.app") }
    static var stateFile: URL { scriptsDir.appendingPathComponent("last-version") }
    static var logFile: URL { scriptsDir.appendingPathComponent("update.log") }
    static var statusFile: URL { scriptsDir.appendingPathComponent("last-status") }
    static var lockDir: URL { scriptsDir.appendingPathComponent(".runlock") }
    // Editor autosave: survives quit-on-close and crashes, cleared on
    // install or explicit discard.
    static var draftFile: URL { scriptsDir.appendingPathComponent(".editor-draft") }

    static var launchAgentsDir: URL { home.appendingPathComponent("Library/LaunchAgents", isDirectory: true) }
    static var plist: URL { launchAgentsDir.appendingPathComponent("local.rime-ice-dict-updater.plist") }

    static var notifyBin: URL { helperApp.appendingPathComponent("Contents/MacOS/RimeNotify") }

    // resources embedded in this app bundle, released at install time
    static var embeddedScript: URL { (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        .appendingPathComponent("update-rime-ice-dicts.sh") }
    static var embeddedHelper: URL { (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        .appendingPathComponent("RimeNotify.app") }
}
