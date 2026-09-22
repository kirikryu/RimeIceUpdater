# RimeIceUpdater

English | [中文](README.md)

A macOS app that keeps the [rime-ice](https://github.com/iDvel/rime-ice) dictionaries up to date. No plum, no command line.

Install once, and the dictionaries are checked, downloaded and deployed automatically on the schedule you set, with results pushed as system notifications.

## Features

- One-click install and enable; updates then run as a launchd job, so the app can be closed
- Check on a weekly schedule, choosing a day and time; runs missed during sleep catch up on wake
- Results delivered as system notifications
- Edit the update script and proxy settings in the app; script edits are auto-saved as a draft
- Status page shows the installed dictionary version, last result, next run time, and checks the Rime directory
- Reinstalling is safe: missing files are created, existing config and the loaded schedule are left alone

## Install

Download the latest zip from [Releases](https://github.com/kirikryu/RimeIceUpdater/releases) and unzip it to get `RimeIceUpdater.app`.

Requires macOS 15 or later on Apple Silicon. [Squirrel](https://github.com/rime/squirrel) must be installed and launched at least once, so that `~/Library/Rime` exists.

1. Drag `RimeIceUpdater.app` into your Applications folder.
2. Right-click it in Finder and choose Open. The app is unsigned, and this is required the first time to get past Gatekeeper. If it is still blocked, go to System Settings → Privacy & Security and click Open Anyway.
3. On the Status page, click the large install button.

After that, checks, downloads and deployment run as a launchd job, and the app can be closed. Open it again when you want to change settings.

## Usage

### Status

The app opens on this page. It shows the installed dictionary version, the last run result, the schedule and next run time, and checks the Rime directory.

- `Check Now`: run an update immediately, with live output
- `Open Log`: reveal `update.log` in Finder
- Before installation, the page shows a single large install button

### Settings

| Setting | Description |
|---|---|
| Schedule | Day of week and time to run, Monday by default. Runs missed during sleep catch up on wake |
| Notifications | Turn off to stop result notifications; the log is still written |
| Proxy host / port | Used by the engine to reach GitHub, default `127.0.0.1:7890` |
| Manage FlClash | When on, starts or restarts the proxy app if the proxy is unreachable, and closes instances it started. When off, only the system proxy is used, and the check is skipped if the proxy is down |
| Bundle ID | Bundle identifier of the managed proxy app, default `com.follow.clash` |

Settings live in `~/Library/Rime/scripts/updater.conf` and can be edited by hand. The app only creates the file when it is missing, and never overwrites manual edits.

### Update script

Settings → Advanced → Update Script opens the update engine for viewing and editing.

- When installed, edits apply to the copy in `~/Library/Rime/scripts/`; otherwise the built-in version is shown
- `Save and Install` writes to disk and takes effect immediately, no reload needed
- `Restore Built-in` upgrades an older install to the engine shipped with this version, or reverts manual edits
- The script must be pure ASCII (for compatibility with macOS's bash 3.2); the footer counts non-ASCII characters as you type

Edits are auto-saved as a draft at `scripts/.editor-draft`, which survives closing the window or quitting. Installing or discarding clears it.

## FAQ

- **I'm not getting notifications.** Go to System Settings → Notifications → RimeNotify and allow notifications. To diagnose, run:

  ```
  ~/Library/Rime/scripts/RimeNotify.app/Contents/MacOS/RimeNotify --status
  ```

  `auth=2` means it is working.

- **"Cannot verify the developer" when opening.** Right-click the app in Finder and choose Open. If it is still blocked, go to System Settings → Privacy & Security and click Open Anyway.

- **It keeps saying GitHub is unreachable.** Check that the proxy is up and the port matches your settings. In manual proxy mode, the system proxy must be enabled.

- **Do updates still run after I close the window?** Yes. Updates run as a system launchd job, independent of whether the app is open. Open it again when you want to change settings.

- **Why can't I choose a different dictionary directory?** Squirrel hardcodes the user directory to `~/Library/Rime`. The installer offers no option, and neither the config files nor librime provide a way to override it, so the updater has to write there. If that path is a symlink, writes go through to the real location, which the Status page displays.

## Files

All files live in `~/Library/Rime/scripts/`, except for the launchd job:

- `update-rime-ice-dicts.sh` — the update engine, editable in the app
- `updater.conf` — settings, safe to edit by hand
- `.editor-draft` — draft of uninstalled script edits
- `RimeNotify.app` — helper app that delivers system notifications
- `update.log` — run log, rotated to `update.log.1` past 1 MB
- `last-version` — installed dictionary version
- `last-status` — last run result, read by the Status page

The launchd job lives at `~/Library/LaunchAgents/local.rime-ice-dict-updater.plist`.

## Uninstall

In Settings, click `Uninstall…` at the bottom and confirm. This removes the launchd job, the update script, the notification helper, and the draft. Dictionaries and logs are kept.

You can reinstall at any time from Settings → Advanced → Update Script. To remove the app entirely, drag `RimeIceUpdater.app` to the Trash.

## Build

Build from source. Intended for development and debugging only.

```bash
./build.sh   # output: build/RimeIceUpdater.app, ad-hoc signed
```

Xcode Command Line Tools is the only dependency, providing `swiftc` and `codesign`. On a fresh Mac, the first run prompts to install it; click Install and wait for the download, about 1–2 GB. Full Xcode is not needed. Everything else, such as bash and plutil, ships with macOS.

In a terminal, `cd` into the repository and run `bash build.sh`. You can also right-click `build.sh` in Finder and choose Open With → Terminal. Double-clicking opens it in a text editor instead of running it. The script pauses at the end, so output and errors stay on screen.

Locally built binaries carry no quarantine attribute and are not blocked by Gatekeeper.

To change the engine logic, edit `Resources/update-rime-ice-dicts.sh`, keeping it pure ASCII. After release, you can also edit the installed copy from Settings → Advanced → Update Script.

Design decisions are documented in [DESIGN.md](DESIGN.md) (Chinese).

## License

[MIT](LICENSE)
