#!/bin/bash
# Build RimeIceUpdater.app (window app) + embedded resources.
# RimeNotify.app (notification helper) is assembled from the main binary:
# launched with a bare outcome key it posts the notification and exits
# before any UI exists (see Sources/NotifyCLI.swift). This keeps the helper's
# bundle structure and calling interface identical to what the engine script
# has always used, so scripts and grants carry over unchanged.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/RimeIceUpdater.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "[1/4] building main app..."
xcrun swiftc -target arm64-apple-macosx15.0 Sources/*.swift \
    -o "$APP/Contents/MacOS/RimeIceUpdater"

echo "[2/4] assembling RimeNotify helper from the main binary..."
# The Info.plist is required: UNUserNotificationCenter refuses to run without
# a bundle identifier, and the identifier below is what the user's existing
# notification authorization is bound to.
mkdir -p Resources/RimeNotify.app/Contents/MacOS
cp "$APP/Contents/MacOS/RimeIceUpdater" Resources/RimeNotify.app/Contents/MacOS/RimeNotify
plutil -lint Resources/RimeNotify-Info.plist
cp Resources/RimeNotify-Info.plist Resources/RimeNotify.app/Contents/Info.plist
codesign --force -s - Resources/RimeNotify.app

echo "[3/4] embedding Info.plist..."
plutil -lint Resources/Info.plist
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "[4/4] embedding resources + signing..."
cp Resources/update-rime-ice-dicts.sh "$APP/Contents/Resources/"
cp -R Resources/RimeNotify.app "$APP/Contents/Resources/RimeNotify.app"
codesign --force -s - "$APP"

echo "built: $PWD/$APP"
