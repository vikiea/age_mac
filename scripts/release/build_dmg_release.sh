#!/usr/bin/env bash
#
# Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
# This code is released under the MIT License.
# See LICENSE for details.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="AgeMac"
BUNDLE_ID="com.vikiea.age-mac"
MIN_SYSTEM_VERSION="14.0"
BUNDLE_VERSION="${BUNDLE_VERSION:-1.1.0}"
SPARKLE_PUBLIC_ED_KEY="IGjw2mVnG2Q/TyUK14//dlR7yeJMYS2Fzx4mRa1ZBuA="
PROJECT_LINK="https://vikiea.github.io/age_mac/"
RELEASE_BASE_URL="https://github.com/vikiea/age_mac/releases/download/v$BUNDLE_VERSION"

ENGINE_DIR="$ROOT_DIR/Engine"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/docs/releases"
APPCAST_MAIN="$ROOT_DIR/docs/appcast.xml"
APPCAST_ARM64="$ROOT_DIR/docs/appcast-arm64.xml"
APPCAST_X86_64="$ROOT_DIR/docs/appcast-x86_64.xml"
APP_ICON_NAME="AgeMacIcon"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

ARCHITECTURES=(arm64 x86_64 universal)

usage() {
  cat >&2 <<EOF
usage: $0 [arm64|x86_64|universal|all]

Builds architecture-specific Age Mac DMGs and Sparkle appcasts.
Default: all
EOF
}

selected_architectures() {
  local target="${1:-all}"
  case "$target" in
    all)
      printf '%s\n' "${ARCHITECTURES[@]}"
      ;;
    arm64|x86_64|universal)
      printf '%s\n' "$target"
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

go_arch_for() {
  case "$1" in
    arm64) printf 'arm64\n' ;;
    x86_64) printf 'amd64\n' ;;
    *) return 1 ;;
  esac
}

swift_build_args_for() {
  case "$1" in
    arm64) printf '%s\n' "-c" "release" "--arch" "arm64" ;;
    x86_64) printf '%s\n' "-c" "release" "--arch" "x86_64" ;;
    *) return 1 ;;
  esac
}

find_sign_update() {
  local candidate
  for candidate in \
    "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$ROOT_DIR/.build/checkouts/Sparkle/bin/sign_update"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

swift_build_path_for() {
  local arch="$1"
  local args=()
  if [[ "$arch" == "universal" ]]; then
    printf '%s\n' "$DIST_DIR/release-work/universal-build"
    return 0
  fi
  while IFS= read -r arg; do
    args+=("$arg")
  done < <(swift_build_args_for "$arch")
  (cd "$ROOT_DIR" && swift build "${args[@]}" >/dev/null)
  (cd "$ROOT_DIR" && swift build "${args[@]}" --show-bin-path)
}

build_engine_for() {
  local arch="$1"
  local output="$2"

  case "$arch" in
    universal)
      local arm64_engine="$DIST_DIR/release-work/age-engine-arm64"
      local x86_engine="$DIST_DIR/release-work/age-engine-x86_64"
      build_engine_for arm64 "$arm64_engine"
      build_engine_for x86_64 "$x86_engine"
      lipo -create "$arm64_engine" "$x86_engine" -output "$output"
      ;;
    arm64|x86_64)
      (cd "$ENGINE_DIR" && GOOS=darwin GOARCH="$(go_arch_for "$arch")" env -u GOROOT go build -o "$output" .)
      ;;
    *)
      return 1
      ;;
  esac
}

prepare_universal_build_dir() {
  local universal_dir="$DIST_DIR/release-work/universal-build"
  local arm64_dir
  local x86_dir

  arm64_dir="$(swift_build_path_for arm64)"
  x86_dir="$(swift_build_path_for x86_64)"

  rm -rf "$universal_dir"
  mkdir -p "$universal_dir"
  cp -R "$arm64_dir/Sparkle.framework" "$universal_dir/Sparkle.framework"
  lipo -create "$arm64_dir/$APP_NAME" "$x86_dir/$APP_NAME" -output "$universal_dir/$APP_NAME"
}

write_info_plist() {
  local plist="$1"
  local feed_url="https://vikiea.github.io/age_mac/appcast.xml"

  cat >"$plist" <<PLIST
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
  <key>SUFeedURL</key>
  <string>$feed_url</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
</dict>
</plist>
PLIST
}

stage_app_for() {
  local arch="$1"
  local build_dir="$2"
  local app_bundle="$DIST_DIR/$APP_NAME-$arch.app"
  local contents="$app_bundle/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"
  local frameworks="$contents/Frameworks"

  rm -rf "$app_bundle"
  mkdir -p "$macos" "$resources" "$frameworks"

  if [[ "$arch" == "universal" ]]; then
    prepare_universal_build_dir
  fi

  cp "$build_dir/$APP_NAME" "$macos/$APP_NAME"
  build_engine_for "$arch" "$resources/age-engine"

  if [[ -d "$build_dir/Sparkle.framework" ]]; then
    cp -R "$build_dir/Sparkle.framework" "$frameworks/Sparkle.framework"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$macos/$APP_NAME" 2>/dev/null || true
  fi

  if [[ -f "$APP_ICON_SOURCE" ]]; then
    cp "$APP_ICON_SOURCE" "$resources/$APP_ICON_NAME.icns"
  fi

  chmod +x "$macos/$APP_NAME" "$resources/age-engine"
  write_info_plist "$contents/Info.plist"
  printf 'APPL????' > "$contents/PkgInfo"

  xattr -cr "$app_bundle" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$app_bundle" >/dev/null

  printf '%s\n' "$app_bundle"
}

create_dmg_for() {
  local arch="$1"
  local app_bundle="$2"
  local dmg_path="$RELEASE_DIR/$APP_NAME-$BUNDLE_VERSION-$arch.dmg"
  local root="$DIST_DIR/dmg-root-$arch"

  rm -rf "$root" "$dmg_path"
  mkdir -p "$root"
  cp -R "$app_bundle" "$root/$APP_NAME.app"
  ln -s /Applications "$root/Applications"

  hdiutil create \
    -volname "Age Mac $BUNDLE_VERSION" \
    -srcfolder "$root" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

  printf '%s\n' "$dmg_path"
}

signature_attribute_for() {
  local update_path="$1"
  local sign_update="$2"
  "$sign_update" "$update_path" | tr -d '\n'
}

write_appcast_header() {
  local path="$1"
  cat >"$path" <<XML
<?xml version="1.0" encoding="utf-8"?>
<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>Age Mac Updates</title>
        <link>$PROJECT_LINK</link>
        <description>Public update feed for Age Mac.</description>
        <language>zh-CN</language>
XML
}

write_appcast_footer() {
  local path="$1"
  cat >>"$path" <<XML
    </channel>
</rss>
XML
}

append_update_item() {
  local path="$1"
  local arch="$2"
  local dmg_path="$3"
  local signature_attribute="$4"
  local pub_date
  pub_date="$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"

  cat >>"$path" <<XML
        <item>
            <title>$BUNDLE_VERSION ($arch)</title>
            <pubDate>$pub_date</pubDate>
            <link>$PROJECT_LINK</link>
            <sparkle:version>$BUNDLE_VERSION</sparkle:version>
            <sparkle:shortVersionString>$BUNDLE_VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
            <enclosure url="$RELEASE_BASE_URL/$(basename "$dmg_path")" $signature_attribute type="application/octet-stream"/>
        </item>
XML
}

write_index_appcast() {
  local path="$1"
  local universal_dmg="$2"
  local signature_attribute="$3"

  write_appcast_header "$path"
  append_update_item "$path" "universal" "$universal_dmg" "$signature_attribute"
  write_appcast_footer "$path"
}

write_empty_index_appcast() {
  local path="$1"
  cat >"$path" <<XML
<?xml version="1.0" encoding="utf-8"?>
<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>Age Mac Updates</title>
        <link>$PROJECT_LINK</link>
        <description>Use appcast-arm64.xml or appcast-x86_64.xml for architecture-specific updates.</description>
        <language>zh-CN</language>
    </channel>
</rss>
XML
}

verify_dmg() {
  local arch="$1"
  local dmg_path="$2"
  local mount_point="$DIST_DIR/verify-mount-$arch"

  rm -rf "$mount_point"
  mkdir -p "$mount_point"
  hdiutil attach "$dmg_path" -mountpoint "$mount_point" -nobrowse -quiet

  test -d "$mount_point/$APP_NAME.app"
  test -x "$mount_point/$APP_NAME.app/Contents/MacOS/$APP_NAME"
  test -x "$mount_point/$APP_NAME.app/Contents/Resources/age-engine"
  codesign --verify --deep --strict --verbose=2 "$mount_point/$APP_NAME.app"
  file "$mount_point/$APP_NAME.app/Contents/MacOS/$APP_NAME"
  file "$mount_point/$APP_NAME.app/Contents/Resources/age-engine"

  hdiutil detach "$mount_point" -quiet
  rm -rf "$mount_point"
}

main() {
  local target="${1:-all}"
  local selected=()
  local sign_update

  while IFS= read -r arch; do
    selected+=("$arch")
  done < <(selected_architectures "$target")
  mkdir -p "$DIST_DIR/release-work" "$RELEASE_DIR"

  swift build -c release >/dev/null
  sign_update="$(find_sign_update)"

  local arm64_dmg=""
  local x86_dmg=""
  local universal_dmg=""

  for arch in "${selected[@]}"; do
    local build_dir
    local app_bundle
    local dmg_path
    build_dir="$(swift_build_path_for "$arch")"
    app_bundle="$(stage_app_for "$arch" "$build_dir")"
    dmg_path="$(create_dmg_for "$arch" "$app_bundle")"
    verify_dmg "$arch" "$dmg_path"
    case "$arch" in
      arm64) arm64_dmg="$dmg_path" ;;
      x86_64) x86_dmg="$dmg_path" ;;
      universal) universal_dmg="$dmg_path" ;;
    esac
  done

  if [[ "$target" == "all" ]]; then
    local arm64_signature
    local x86_signature
    local universal_signature
    arm64_signature="$(signature_attribute_for "$arm64_dmg" "$sign_update")"
    x86_signature="$(signature_attribute_for "$x86_dmg" "$sign_update")"
    universal_signature="$(signature_attribute_for "$universal_dmg" "$sign_update")"

    write_appcast_header "$APPCAST_ARM64"
    append_update_item "$APPCAST_ARM64" "arm64" "$arm64_dmg" "$arm64_signature"
    write_appcast_footer "$APPCAST_ARM64"

    write_appcast_header "$APPCAST_X86_64"
    append_update_item "$APPCAST_X86_64" "x86_64" "$x86_dmg" "$x86_signature"
    write_appcast_footer "$APPCAST_X86_64"

    write_index_appcast "$APPCAST_MAIN" "$universal_dmg" "$universal_signature"
    xmllint --noout "$APPCAST_MAIN" "$APPCAST_ARM64" "$APPCAST_X86_64"
  fi

  printf 'Built release assets in %s\n' "$RELEASE_DIR"
  ls -lh "$RELEASE_DIR"/"$APP_NAME-$BUNDLE_VERSION-"*.dmg
}

main "$@"
