import Foundation

/// Health probe for the environment this updater depends on: the Squirrel
/// input method and the Rime user directory it reads. Squirrel hardcodes
/// ~/Library/Rime in every release (no installer option, no config override,
/// no env var in librime), so this is detection-only: surface anomalies,
/// never offer to redirect the updater elsewhere.
struct EnvCheck: Equatable {
    enum RimeDirState: Equatable {
        case ok        // deployed: recognizable Rime files present
        case empty     // exists but nothing Rime-like inside
        case missing
    }

    var squirrelInstalled = false
    var rimeDirState = RimeDirState.missing
    // absolute path when ~/Library/Rime sits behind a symlink (some users
    // link it to a synced volume); shown for transparency only, the engine
    // already writes through the link correctly
    var rimeDirRealPath: String?

    var isHealthy: Bool { squirrelInstalled && rimeDirState == .ok }

    static let squirrelAppPath = "/Library/Input Methods/Squirrel.app"

    static func probe() -> EnvCheck {
        var e = EnvCheck()
        let fm = FileManager.default
        e.squirrelInstalled = fm.fileExists(atPath: squirrelAppPath)

        let dir = Paths.rimeDir
        var isDir: ObjCBool = false
        // fileExists resolves symlinks, so a linked dir counts as present
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return e
        }
        // markers of a deployed Rime dir: stock Squirrel writes
        // installation.yaml + default.yaml on first deploy; rime-ice adds
        // cn_dicts/ and the compiled build/ dir
        let markers = ["installation.yaml", "default.yaml", "default.custom.yaml",
                       "rime_ice.schema.yaml", "cn_dicts", "build"]
        e.rimeDirState = markers.contains {
            fm.fileExists(atPath: dir.appendingPathComponent($0).path)
        } ? .ok : .empty

        // symlink transparency: resolvingSymlinksInPath collapses the whole
        // chain, so a link on ~/Library itself shows up too - fine, the
        // point is where the dicts actually land
        let resolved = dir.resolvingSymlinksInPath().path
        if resolved != dir.path {
            e.rimeDirRealPath = resolved
        }
        return e
    }
}
