import Foundation
import AppKit
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    // Shared so the NSApplicationDelegate can check editor dirtiness at
    // quit time; the App scene binds the same instance via @StateObject.
    static let shared = AppModel()

    enum ScriptSource {
        case installed   // editing ~/Library/Rime/scripts/update-rime-ice-dicts.sh
        case bundled     // nothing installed yet; showing the built-in copy
    }

    @Published var state = InstallState()
    @Published var settings = UpdaterSettings()
    @Published var env = EnvCheck()
    @Published var version: String?
    @Published var lastRun: RunRecord?
    @Published var running = false
    @Published var runOutput = ""
    @Published var errorMessage: String?

    // Script editor state. scriptText is the editing buffer; savedScriptText
    // is the installed baseline. refresh() deliberately never touches them so
    // a background refresh cannot wipe unsaved edits.
    @Published var scriptText = ""
    @Published var savedScriptText = ""
    @Published var scriptSource: ScriptSource = .bundled
    @Published var deployedAt: Date?

    var scriptDirty: Bool { scriptText != savedScriptText }

    private var process: Process?

    init() {
        // The windowed app is a tool you open when needed; the schedule runs
        // via launchd without it. Drop login-item registrations left by the
        // old menu-bar version so no window pops up at every login.
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    func refresh() {
        // launchctl probing and file reads are blocking; run them off the
        // main actor so interacting with the window never hitches.
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                (Installer.detect(), SettingsStore.load(), EnvCheck.probe(),
                 StatusReader.currentVersion(), StatusReader.lastRun())
            }.value
            state = snapshot.0
            settings = snapshot.1
            env = snapshot.2
            version = snapshot.3
            lastRun = snapshot.4
        }
    }

    // MARK: - script editor

    func loadScript() {
        let fm = FileManager.default
        if fm.fileExists(atPath: Paths.script.path),
           let text = try? String(contentsOf: Paths.script, encoding: .utf8) {
            scriptText = text
            savedScriptText = text
            scriptSource = .installed
        } else if let text = try? String(contentsOf: Paths.embeddedScript, encoding: .utf8) {
            scriptText = text
            savedScriptText = text
            scriptSource = .bundled
        } else {
            scriptText = ""
            savedScriptText = ""
            scriptSource = .bundled
            errorMessage = AppError.embeddedScriptMissing.localizedDescription
            return
        }
        // Restore unsaved edits: the windowed app quits when its window
        // closes, so the draft is the only thing that carries edits across
        // sessions.
        if let draft = try? String(contentsOf: Paths.draftFile, encoding: .utf8),
           draft != savedScriptText {
            scriptText = draft
        }
    }

    /// Persists the editing buffer when it differs from the installed
    /// baseline, removes the draft otherwise. Called debounced on edits and
    /// synchronously at quit time.
    func flushDraft() {
        let fm = FileManager.default
        if scriptDirty {
            try? fm.createDirectory(at: Paths.scriptsDir, withIntermediateDirectories: true)
            try? scriptText.write(to: Paths.draftFile, atomically: true, encoding: .utf8)
        } else if fm.fileExists(atPath: Paths.draftFile.path) {
            try? fm.removeItem(at: Paths.draftFile)
        }
    }

    /// Discards unsaved edits and reloads the installed (or built-in) script.
    func discardEdits() {
        try? FileManager.default.removeItem(at: Paths.draftFile)
        loadScript()
    }

    /// Replaces the editing buffer with the built-in engine script. Kept
    /// separate from loadScript(): existing installs keep their (possibly
    /// older or hand-tweaked) script, so upgrading the engine to the bundled
    /// version must be an explicit user action.
    func loadBundledScript() {
        guard let text = try? String(contentsOf: Paths.embeddedScript, encoding: .utf8) else {
            errorMessage = AppError.embeddedScriptMissing.localizedDescription
            return
        }
        scriptText = text
    }

    /// Writes the edited script to ~/Library/Rime/scripts/ and fills in any
    /// missing piece (helper, conf, schedule). The launchd job needs no
    /// reload: it invokes the script by path, so the next run picks the new
    /// file up on its own.
    func deploy() {
        guard !running else { return }
        guard !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = L("脚本内容为空，已取消安装", "The script is empty; install cancelled")
            return
        }
        do {
            try Installer.deploy(scriptText: scriptText, settings: settings)
            savedScriptText = scriptText
            scriptSource = .installed
            deployedAt = Date()
            errorMessage = nil
            try? FileManager.default.removeItem(at: Paths.draftFile)
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    // MARK: - engine run

    func checkNow() {
        guard !running, state.scriptInstalled else { return }
        running = true
        runOutput = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Paths.script.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { self?.runOutput += text }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false
                self.refresh()
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            running = false
            errorMessage = error.localizedDescription
        }
    }

    func stopRun() {
        process?.terminate()
    }

    // MARK: - settings / uninstall

    func saveSettingsAndApply() {
        do {
            try SettingsStore.save(settings)
            try Launchd.apply(settings)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func uninstall() {
        Installer.uninstall()
        refresh()
        // The editor now falls back to the built-in copy, ready to reinstall.
        loadScript()
    }

    func revealLogFile() {
        NSWorkspace.shared.selectFile(Paths.logFile.path,
                                      inFileViewerRootedAtPath: Paths.scriptsDir.path)
    }
}
