#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AgeMac"
BUNDLE_ID="com.vikiea.age-mac"
MIN_SYSTEM_VERSION="14.0"
BUNDLE_VERSION="1.0.2"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/Engine"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_NAME="AgeMacIcon"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

(cd "$ENGINE_DIR" && env -u GOROOT go build -o age-engine .)
(cd "$ROOT_DIR" && swift build)

BUILD_BINARY="$(cd "$ROOT_DIR" && swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ENGINE_DIR/age-engine" "$APP_RESOURCES/age-engine"
if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/$APP_ICON_NAME.icns"
fi
chmod +x "$APP_BINARY" "$APP_RESOURCES/age-engine"

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
  <key>CFBundleDisplayName</key>
  <string>Age Mac</string>
  <key>CFBundleShortVersionString</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME.icns</string>
  <key>CFBundleIconName</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_CONTENTS/PkgInfo"

xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_BUNDLE" >/dev/null 2>&1 || true

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
