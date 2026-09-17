#!/bin/bash
# rime-ice auto-update script
# Source: official GitHub release (latest/download/full.zip), fetched through
# FlClash's system proxy. No mirror, no direct fetch.
# Flow: make sure the system proxy (127.0.0.1:7890) is up. If it is down:
# launch FlClash when it is not running, or restart it when it is running
# (auto-connect on startup re-enables the system proxy). The old process is
# always stopped and confirmed gone before relaunching, so a second FlClash
# instance never runs. Then compare the release asset's Last-Modified with the
# last applied version, and only install when the release is newer. The GitHub
# HEAD check below is retried a few times: right after FlClash starts its
# proxy port is already listening while the tunnel is not yet ready (a run
# failed on 2026-09-07 exactly like that).
# When the job starts FlClash itself (it was not running before), the script
# closes it again before exiting, on every path (updated / no update / failed),
# so no FlClash window is left behind - launchd may fire this job in a
# lid-closed darkwake, and a leftover FlClash would sit on the desktop at wake.
# Every terminal outcome (updated / already current / skipped / failed) is also
# posted to Notification Center via the bundled RimeNotify.app helper, so the
# run's result is visible without reading the logs. Each outcome is recorded
# to scripts/last-status as "time|ok-or-fail|key args"; the RimeIceUpdater app
# displays the last run from that file and does not parse this log.
# Schedule: once a week via launchd (local.rime-ice-dict-updater.plist, Monday
# 09:00; if asleep at that time launchd runs the job on wake). A lock in
# scripts/.runlock keeps the app's manual run and the launchd run mutually
# exclusive.
# Settings can be overridden through scripts/updater.conf (written by the
# RimeIceUpdater app or edited by hand): PROXY_HOST, PROXY_PORT,
# FLCLASH_BUNDLE, MANAGE_FLCLASH (1 = start/stop FlClash when the proxy is
# down, 0 = manual proxy mode, only use the system proxy as-is), NOTIFY (1/0).
# NOTE: keep this file ASCII-only (bash 3.2 has multibyte parsing quirks on macOS)
set -euo pipefail

RIME_DIR="$HOME/Library/Rime"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/last-version"
LOG_FILE="$SCRIPT_DIR/update.log"
STATUS_FILE="$SCRIPT_DIR/last-status"
DOWNLOAD_URL="https://github.com/iDvel/rime-ice/releases/latest/download/full.zip"
PROXY_HOST="127.0.0.1"
PROXY_PORT="7890"
FLCLASH_BUNDLE="com.follow.clash"
MANAGE_FLCLASH="1"
NOTIFY="1"
# Overrides written by the RimeIceUpdater app (or by hand)
if [ -f "$SCRIPT_DIR/updater.conf" ]; then
    . "$SCRIPT_DIR/updater.conf"
fi
PROXY_ADDR="http://$PROXY_HOST:$PROXY_PORT"
SQUIRREL="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
STARTED_FLCLASH="" # set to 1 when this run launches FlClash (it was not running)
RUNLOCK="$SCRIPT_DIR/.runlock" # one run at a time (app + launchd)
LOCK_MINE="" # set when this run owns the lock; only the owner cleans it up
TMP_DIR="$(mktemp -d /tmp/rime-ice-update.XXXXXX)"
trap 'close_flclash_if_started; rm -rf "$TMP_DIR"; if [ -n "$LOCK_MINE" ]; then rm -rf "$RUNLOCK"; fi' EXIT

# Keep the log bounded: rotate past 1 MiB, keep one old generation.
if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

NOTIFY_BIN="$SCRIPT_DIR/RimeNotify.app/Contents/MacOS/RimeNotify"

# Post the run's outcome to Notification Center. osascript's display
# notification is silently dropped on macOS 15, so prefer the bundled
# RimeNotify.app helper: it takes ASCII keys + args and picks the wording
# by system language (Chinese/English). The case below is the English
# fallback for when the helper is missing. Best-effort either way - the log
# above always records the outcome.
notify() {
    [ "$NOTIFY" = "1" ] || return 0
    if [ -x "$NOTIFY_BIN" ]; then
        "$NOTIFY_BIN" "$@" >/dev/null 2>&1 || true
        return
    fi
    local msg=""
    case "$1" in
        flclash_stop_failed)      msg="FAILED: cannot stop old FlClash, abort" ;;
        flclash_launch_failed)    msg="FAILED: could not launch FlClash" ;;
        proxy_timeout)            msg="Skipped: system proxy not up after 90s" ;;
        proxy_not_ready)          msg="Skipped: proxy not running (manual proxy mode)" ;;
        github_unreachable)       msg="Skipped: GitHub unreachable via proxy" ;;
        no_last_modified)         msg="Skipped: no Last-Modified from GitHub" ;;
        bad_last_modified)        msg="Skipped: cannot parse Last-Modified" ;;
        up_to_date)               msg="Already up to date ($2)" ;;
        download_failed)          msg="FAILED: download failed after retries" ;;
        zip_corrupt)              msg="FAILED: zip integrity check" ;;
        zip_missing)              msg="FAILED: zip missing $2" ;;
        updated_deployed)         msg="Updated to $2, deploy triggered" ;;
        updated_deploy_manually)  msg="Updated to $2, deploy Squirrel manually!" ;;
        *)                        msg="$*" ;;
    esac
    osascript -e "display notification \"$msg\" with title \"Rime dict update\"" >/dev/null 2>&1 || true
}

# Every terminal outcome funnels through here: record it to last-status for
# the app's status display (always written; NOTIFY only gates the
# notification itself), then post the notification.
# Usage: notify_result <ok|fail> <key> [args ...]
notify_result() {
    local verdict="$1"; shift
    printf '%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$verdict" "$*" > "$STATUS_FILE"
    notify "$@"
}

# 1. Make sure the system proxy is up
proxy_up() {
    local p
    p="$(scutil --proxy 2>/dev/null)" || return 1
    printf '%s\n' "$p" | grep -q 'HTTPEnable : 1' && \
    printf '%s\n' "$p" | grep -q "HTTPProxy : $PROXY_HOST" && \
    printf '%s\n' "$p" | grep -q "HTTPPort : $PROXY_PORT" && \
    nc -z "$PROXY_HOST" "$PROXY_PORT" >/dev/null 2>&1
}

flclash_running() { pgrep -x FlClash >/dev/null 2>&1; }

# Wait up to 15s for the FlClash process to disappear; return 1 if still alive
wait_flclash_exit() {
    for _ in $(seq 1 15); do
        flclash_running || return 0
        sleep 1
    done
    return 1
}

# Close FlClash before exiting when this run launched it, so the weekly job
# never leaves an app behind. Graceful quit only: killing FlClash hard would
# leave the system proxy enabled but pointing at the dead proxy port.
close_flclash_if_started() {
    [ -n "$STARTED_FLCLASH" ] || return 0
    flclash_running || return 0
    log "closing FlClash started by this run ..."
    osascript -e "tell application id \"$FLCLASH_BUNDLE\" to quit" >/dev/null 2>&1 || true
    if wait_flclash_exit; then
        log "FlClash closed"
    else
        log "WARNING: FlClash still running 15s after quit request, leaving it"
    fi
    return 0
}

# One run at a time: the app's manual run and the launchd schedule may
# otherwise overlap. A dead owner's lock is taken over.
acquire_lock() {
    if mkdir "$RUNLOCK" 2>/dev/null; then
        echo "$$" > "$RUNLOCK/pid"
        LOCK_MINE=1
        return 0
    fi
    local old
    old="$(cat "$RUNLOCK/pid" 2>/dev/null || true)"
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        return 1
    fi
    rm -rf "$RUNLOCK"
    if mkdir "$RUNLOCK" 2>/dev/null; then
        echo "$$" > "$RUNLOCK/pid"
        LOCK_MINE=1
        return 0
    fi
    return 1
}
if ! acquire_lock; then
    log "another update run is already active, skip"
    exit 0
fi

log "=== check rime-ice update ==="

if proxy_up; then
    log "system proxy already up"
elif [ "$MANAGE_FLCLASH" != "1" ]; then
    log "proxy down and FlClash management disabled (manual proxy mode), skip"
    notify_result fail proxy_not_ready
    exit 0
else
    if flclash_running; then
        log "FlClash running but proxy down, restarting it ..."
        osascript -e "tell application id \"$FLCLASH_BUNDLE\" to quit" >/dev/null 2>&1 || true
        wait_flclash_exit || {
            pkill -TERM -x FlClash 2>/dev/null || true
            wait_flclash_exit || {
                pkill -KILL -x FlClash 2>/dev/null || true
                sleep 2
            }
        }
        if flclash_running; then
            log "cannot stop old FlClash process, abort to avoid a second instance"
            notify_result fail flclash_stop_failed
            exit 1
        fi
    else
        log "FlClash not running, launching it ..."
    fi
    open -b "$FLCLASH_BUNDLE" || { log "failed to launch FlClash, skip"; notify_result fail flclash_launch_failed; exit 1; }
    STARTED_FLCLASH=1
    PROXY_READY=""
    for _ in $(seq 1 30); do
        if proxy_up; then
            PROXY_READY=1
            break
        fi
        sleep 3
    done
    if [ -z "$PROXY_READY" ]; then
        log "system proxy not up after 90s (FlClash auto-connect failed?), skip"
        notify_result fail proxy_timeout
        exit 0
    fi
fi

# 2. Get the release asset's Last-Modified and compare with what we applied.
# Retried with pauses: a freshly launched FlClash opens port 7890 before its
# tunnel is usable, so the first attempt may fail for a few seconds.
HEAD_OK=""
for _ in 1 2 3 4; do
    if HEADERS="$(curl -fsSLI --max-time 60 -x "$PROXY_ADDR" "$DOWNLOAD_URL" 2>/dev/null)"; then
        HEAD_OK=1
        break
    fi
    sleep 5
done
[ -n "$HEAD_OK" ] || { log "failed to reach GitHub release (proxy/node?), skip"; notify_result fail github_unreachable; exit 1; }
LM="$(printf '%s\n' "$HEADERS" | tr -d '\r' | sed -n 's/^[Ll]ast-[Mm]odified: //p' | tail -1)"
[ -n "$LM" ] || { log "no Last-Modified header from GitHub, skip"; notify_result fail no_last_modified; exit 1; }
# LC_ALL=C keeps %a/%b matching English day/month names in any shell locale
# (zh_CN locales fail on them); TZ=GMT reads the wall clock as UTC (GitHub
# always sends GMT) instead of relying on %Z parsing.
NEW_EPOCH="$(LC_ALL=C TZ=GMT date -j -f '%a, %d %b %Y %H:%M:%S' "${LM% *}" '+%s' 2>/dev/null || echo 0)"
[ "$NEW_EPOCH" -gt 0 ] || { log "cannot parse Last-Modified ($LM), skip"; notify_result fail bad_last_modified; exit 1; }
NEW_VERSION="$(TZ=GMT date -j -r "$NEW_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')"

if [ -f "$STATE_FILE" ]; then
    OLD_EPOCH="$(TZ=GMT date -j -f '%Y-%m-%dT%H:%M:%SZ' "$(cat "$STATE_FILE")" '+%s' 2>/dev/null || echo 0)"
    if [ "$NEW_EPOCH" -le "$OLD_EPOCH" ]; then
        log "already up to date ($NEW_VERSION <= $(cat "$STATE_FILE")), skip"
        notify_result ok up_to_date "$NEW_VERSION"
        exit 0
    fi
fi

# 3. Download through the proxy, with retries for transient failures
log "new version found ($NEW_VERSION), downloading full.zip ..."
DL_OK=""
for _ in 1 2 3; do
    if curl -fsSL --max-time 120 -x "$PROXY_ADDR" "$DOWNLOAD_URL" -o "$TMP_DIR/full.zip" 2>/dev/null; then
        DL_OK=1
        break
    fi
    sleep 5
done
[ -n "$DL_OK" ] || { log "download failed, abort"; notify_result fail download_failed; exit 1; }
unzip -tq "$TMP_DIR/full.zip" >/dev/null || { log "zip integrity check failed, abort"; notify_result fail zip_corrupt; exit 1; }

# 4. Extract and verify key files exist
unzip -oq "$TMP_DIR/full.zip" -d "$TMP_DIR/x"
[ -f "$TMP_DIR/x/rime_ice.schema.yaml" ] || { log "zip missing rime_ice.schema.yaml, abort"; notify_result fail zip_missing rime_ice.schema.yaml; exit 1; }
[ -d "$TMP_DIR/x/cn_dicts" ] || { log "zip missing cn_dicts/, abort"; notify_result fail zip_missing cn_dicts; exit 1; }
[ -d "$TMP_DIR/x/lua" ] || { log "zip missing lua/, abort"; notify_result fail zip_missing lua; exit 1; }

# 5. Overwrite all files contained in the release into the user dir
rsync -a "$TMP_DIR/x/" "$RIME_DIR/"
echo "$NEW_VERSION" > "$STATE_FILE"
log "all files updated, version $NEW_VERSION"

# 6. Trigger redeploy
if [ -x "$SQUIRREL" ]; then
    "$SQUIRREL" --reload
    log "deploy triggered"
    notify_result ok updated_deployed "$NEW_VERSION"
else
    log "WARNING: Squirrel not found ($SQUIRREL), please deploy manually"
    notify_result ok updated_deploy_manually "$NEW_VERSION"
fi
log "done"
