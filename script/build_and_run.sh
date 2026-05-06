#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Wanda"
BUNDLE_ID="com.mechaharry.Wanda"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  echo "usage: $0 [run|--package-only|--verify|--debug|--logs|--telemetry]" >&2
}

stop_existing_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

stage_bundle() {
  swift build
  local build_binary
  build_binary="$(swift build --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_bundle() {
  test -x "$APP_BINARY"
  test -f "$INFO_PLIST"
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
}

case "$MODE" in
  run)
    stop_existing_app
    stage_bundle
    open_app
    ;;
  --package-only|package)
    stage_bundle
    verify_bundle
    ;;
  --verify|verify)
    stop_existing_app
    stage_bundle
    verify_bundle
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --debug|debug)
    stop_existing_app
    stage_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_existing_app
    stage_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_existing_app
    stage_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    usage
    exit 2
    ;;
esac
