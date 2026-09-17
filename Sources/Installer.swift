import Foundation

struct InstallState: Equatable {
    var scriptInstalled = false
    var helperInstalled = false
    var plistLoaded = false
    var hasStateFile = false
    var isComplete: Bool { scriptInstalled && plistLoaded }
}

enum Installer {
    static func detect() -> InstallState {
        var st = InstallState()
        let fm = FileManager.default
        st.scriptInstalled = fm.fileExists(atPath: Paths.script.path)
        st.helperInstalled = fm.fileExists(atPath: Paths.notifyBin.path)
        st.plistLoaded = Launchd.isLoaded()
        st.hasStateFile = fm.fileExists(atPath: Paths.stateFile.path)
        return st
    }

    /// Installs `scriptText` (the editor buffer) as the engine script and
    /// fills in whatever piece is missing — notify helper, updater.conf,
    /// launchd job — without touching pieces that already exist. A repeat
    /// install therefore never clobbers a hand-edited conf or a loaded
    /// schedule.
    static func deploy(scriptText: String, settings s: UpdaterSettings) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.scriptsDir, withIntermediateDirectories: true)
        try scriptText.write(to: Paths.script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Paths.script.path)

        if !fm.fileExists(atPath: Paths.notifyBin.path),
           fm.fileExists(atPath: Paths.embeddedHelper.path) {
            if fm.fileExists(atPath: Paths.helperApp.path) { try fm.removeItem(at: Paths.helperApp) }
            try fm.copyItem(at: Paths.embeddedHelper, to: Paths.helperApp)
        }

        if !fm.fileExists(atPath: Paths.conf.path) {
            try SettingsStore.save(s)
        }
        if !Launchd.isLoaded() || Launchd.plistNeedsUpgrade() {
            try Launchd.apply(s)
        }
    }

    static func uninstall() {
        Launchd.unload()
        let fm = FileManager.default
        for u in [Paths.script, Paths.conf, Paths.plist, Paths.helperApp, Paths.lockDir,
                  Paths.statusFile, Paths.draftFile] {
            try? fm.removeItem(at: u)
        }
    }
}
