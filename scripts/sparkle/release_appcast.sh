#!/usr/bin/env bash
#
# Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
# This code is released under the MIT License.
# See LICENSE for details.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="AgeMac"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/docs/releases"
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"
PROJECT_LINK="https://vikiea.github.io/age_mac/"

find_generate_appcast() {
  local candidate
  for candidate in \
    "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$ROOT_DIR/.build/checkouts/Sparkle/generate_appcast"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

(cd "$ROOT_DIR" && ./script/build_and_run.sh --verify)

if ! GENERATE_APPCAST="$(find_generate_appcast)"; then
  (cd "$ROOT_DIR" && swift build >/dev/null)
  GENERATE_APPCAST="$(find_generate_appcast)"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
ARCHIVE="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DOWNLOAD_PREFIX="https://github.com/vikiea/age_mac/releases/download/v$VERSION/"

mkdir -p "$RELEASE_DIR"
rm -f "$ARCHIVE"
(cd "$ROOT_DIR/dist" && ditto -c -k --keepParent "$APP_NAME.app" "$ARCHIVE")

"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "$PROJECT_LINK" \
  -o "$APPCAST_PATH" \
  "$RELEASE_DIR"

if ! grep -q 'Copyright (c) 2026 vikiea' "$APPCAST_PATH"; then
  tmp_appcast="$(mktemp)"
  awk 'NR == 1 {
         print
         print "<!--"
         print "Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>"
         print "This code is released under the MIT License."
         print "See LICENSE for details."
         print "-->"
         next
       } { print }' "$APPCAST_PATH" > "$tmp_appcast"
  mv "$tmp_appcast" "$APPCAST_PATH"
fi

tail -c 1 "$APPCAST_PATH" | grep -q '^$' || printf '\n' >> "$APPCAST_PATH"

printf 'Updated %s with %s\n' "$APPCAST_PATH" "$ARCHIVE"
