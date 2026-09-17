# RimeIceUpdater

English | [中文](README.md)

A macOS window app that keeps the [rime-ice](https://github.com/iDvel/rime-ice) dictionaries
up to date — **no [plum](https://github.com/rime/plum), no command line**. Install once, and
the official dictionaries are checked, downloaded and installed automatically on the schedule
you choose, then Squirrel is redeployed and the result is pushed to Notification Center.

> Note: the app UI and notifications are currently in Chinese only.

## Quick Start

1. Drag `RimeIceUpdater.app` into `/Applications` and **right-click → Open** it once
   (the app is ad-hoc signed, so the first launch needs this to bypass Gatekeeper);
2. On the **Status** page click **Install & enable auto-update**;
3. Done. Update results arrive as notifications; reopen the app anytime to check status
   or change settings.

## Requirements

- macOS 15+
- [Squirrel](https://github.com/rime/squirrel) (Rime input method for macOS), user directory `~/Library/Rime`

## How It Works

Scheduled updates run through a launchd agent, so the app does not need to stay open —
close the window and updates continue. The engine is a battle-hardened bash script
(version gating, retry on failure, concurrency lock) that downloads the latest rime-ice
`full.zip` through your proxy and triggers a Squirrel redeploy; a small helper app
(`RimeNotify.app`) posts the result notifications. The app itself handles installation,
settings, a graphical script editor and status display.

## Key Settings

| Setting | Description |
|---|---|
| Schedule | Day of week (Mon–Sun, default Monday) + hour; runs missed during sleep catch up on wake |
| Notifications | Turn off result notifications (logging continues) |
| Proxy address/port | Always used for GitHub access (default `127.0.0.1:7890`) |
| FlClash management | Auto-start/restart FlClash when the proxy is down, quit self-started instances afterwards |

Settings are saved in `~/Library/Rime/scripts/updater.conf`; reinstalling only creates it
when missing, so hand edits are preserved.

## Files & Uninstall

Everything installs under `~/Library/Rime/scripts/` (engine script, config, helper app,
logs, status files). Uninstall from **Settings → Uninstall**: removes the schedule, script,
helper and editor draft — dictionaries and logs are kept.

## Build

```bash
./build.sh   # output: build/RimeIceUpdater.app (ad-hoc signed)
```

Requires Xcode Command Line Tools (`swiftc`).

## License

[MIT](LICENSE)
