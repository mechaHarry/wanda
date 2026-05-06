#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Wanda"
BUNDLE_ID="com.mechaharry.Wanda"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
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
  local app_version
  build_binary="$(swift build --show-bin-path)/$APP_NAME"
  app_version="$(tr -d '[:space:]' < "$VERSION_FILE")"
  if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must contain a semver in MAJOR.MINOR.PATCH form" >&2
    return 1
  fi

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
  <key>CFBundleShortVersionString</key>
  <string>$app_version</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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

wait_for_window() {
  local attempts=50
  local saw_process=false
  local system_events_error=""
  local count

  while (( attempts > 0 )); do
    if pgrep -x "$APP_NAME" >/dev/null; then
      saw_process=true
      if count="$(/usr/bin/osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to count windows" 2>&1)"; then
        system_events_error=""
        if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
          return 0
        fi
      else
        system_events_error="$count"
      fi
    fi

    sleep 0.1
    attempts=$((attempts - 1))
  done

  if [[ "$saw_process" != true ]]; then
    echo "$APP_NAME did not start within verification timeout" >&2
    return 1
  fi

  if ! pgrep -x "$APP_NAME" >/dev/null; then
    echo "$APP_NAME exited before opening a window" >&2
    return 1
  fi

  if [[ -n "$system_events_error" ]]; then
    echo "Unable to inspect $APP_NAME windows through System Events." >&2
    echo "Grant Accessibility permission to the calling terminal or Codex app, then retry --verify." >&2
    echo "$system_events_error" >&2
    return 1
  fi

  echo "$APP_NAME did not open a window within verification timeout" >&2
  return 1
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
    wait_for_window
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
