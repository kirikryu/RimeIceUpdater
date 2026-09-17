import Foundation
import Darwin

enum Launchd {
    static var uid: Int { Int(getuid()) }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (127, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func plistXML(_ s: UpdaterSettings) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Paths.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(Paths.script.path)</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Weekday</key>
                <integer>\(s.weekday)</integer>
                <key>Hour</key>
                <integer>\(s.hour)</integer>
                <key>Minute</key>
                <integer>\(s.minute)</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>\(Paths.logFile.path)</string>
            <key>StandardErrorPath</key>
            <string>\(Paths.logFile.path)</string>
        </dict>
        </plist>
        """
    }

    static func isLoaded() -> Bool {
        run("/bin/launchctl", ["print", "gui/\(uid)/\(Paths.label)"]).code == 0
    }

    static func apply(_ s: UpdaterSettings) throws {
        try FileManager.default.createDirectory(at: Paths.launchAgentsDir, withIntermediateDirectories: true)
        try plistXML(s).write(to: Paths.plist, atomically: true, encoding: .utf8)
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Paths.label)"])
        let r = run("/bin/launchctl", ["bootstrap", "gui/\(uid)", Paths.plist.path])
        guard r.code == 0 else {
            throw AppError.launchctlBootstrapFailed(
                r.out.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func unload() {
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Paths.label)"])
    }

    // Next time the job will actually do work: launchd fires daily at
    // hour:minute, and the engine's interval gate only lets a fire through
    // once intervalDays calendar days have passed since the last real run
    // (scripts/last-run-date, written by the engine itself).
    /// True when the on-disk plist still schedules the interval-era daily
    /// fire (no Weekday key). Used to migrate installs from the every-N-days
    /// version back to the weekly schedule.
    static func plistNeedsUpgrade() -> Bool {
        guard let text = try? String(contentsOf: Paths.plist, encoding: .utf8) else {
            return false
        }
        return !text.contains("<key>Weekday</key>")
    }

    static func nextRun(_ s: UpdaterSettings) -> Date? {
        // launchd weekday 1..7 = Mon..Sun; Calendar weekday 1=Sun ... 7=Sat
        let calWeekday = s.weekday == 7 ? 1 : s.weekday + 1
        var dc = DateComponents()
        dc.weekday = calWeekday
        dc.hour = s.hour
        dc.minute = s.minute
        return Calendar.current.nextDate(after: Date(), matching: dc, matchingPolicy: .nextTime)
    }
}
