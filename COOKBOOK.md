<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->

# Age Mac Cookbook

This cookbook collects the operational recipes for building, verifying, releasing, and maintaining Age Mac.

## Local Build

```bash
./script/build_and_run.sh
```

The script performs these steps:

1. Builds `Engine/age-engine` with `env -u GOROOT go build`.
2. Builds the SwiftPM app.
3. Stages `dist/AgeMac.app`.
4. Copies the Go engine and app icon into `Contents/Resources`.
5. Embeds Sparkle when the SwiftPM artifact is available.
6. Writes `Info.plist`, signs locally, registers the bundle, and launches it.

Use verification mode when you only need to confirm launch:

```bash
./script/build_and_run.sh --verify
```

## Standard Verification

```bash
swift build
(cd Engine && env -u GOROOT go test ./...)
./script/build_and_run.sh --verify
git diff --check
codesign --verify --deep --strict --verbose=2 dist/AgeMac.app
```

## Engine Roundtrip

Run this after changing `Engine/main.go`, `AgeEngineClient.swift`, encryption/decryption options, or output handling.

```bash
tmp=$(mktemp -d)
out="$tmp/out"
mkdir -p "$tmp/in" "$out"
printf 'hello age mac\n' > "$tmp/in/a.txt"
printf 'second file\n' > "$tmp/in/b.txt"
printf '[{"path":"%s","name":"a.txt"},{"path":"%s","name":"b.txt"}]\n' "$tmp/in/a.txt" "$tmp/in/b.txt" > "$tmp/files.json"
printf 'test-passphrase' > "$tmp/secret.txt"
./Engine/age-engine encrypt-batch --files-json "$tmp/files.json" --output-dir "$out" --output-name sample.tar.gz.age --compress=true --auth passphrase --secret-file "$tmp/secret.txt" --duplicate overwrite
enc="$out/encrypted/sample.tar.gz.age"
printf '[{"path":"%s","name":"sample.tar.gz.age"}]\n' "$enc" > "$tmp/enc-files.json"
./Engine/age-engine decrypt --files-json "$tmp/enc-files.json" --output-dir "$out" --auth passphrase --secret-file "$tmp/secret.txt" --duplicate overwrite
cmp "$tmp/in/a.txt" "$out/decrypted/a.txt"
cmp "$tmp/in/b.txt" "$out/decrypted/b.txt"
```

## Key Import

Age Mac imports existing age key files from:

```text
~/.config/age
```

The importer supports age key files with or without file extensions. It understands the standard `age-keygen` format:

```text
# created: 2026-05-18T00:00:00Z
# public key: age1...
AGE-SECRET-KEY-...
```

Manual import and file import are also available in the app's Keys tab.

## Sparkle Key Pair

Generate a Sparkle EdDSA signing key:

```bash
scripts/sparkle/generate_keys.sh
```

By default, Sparkle stores the private key in the macOS Keychain and prints a public key. Commit only the public key by placing it in `script/build_and_run.sh` as `SPARKLE_PUBLIC_ED_KEY`.

Never commit a private update signing key. If you export one to a file for CI or release automation, keep it outside the repository or under an ignored private path.

## DMG Release And Appcast

Build DMG release assets and refresh the appcasts:

```bash
scripts/release/build_dmg_release.sh all
```

The script:

1. Builds the Swift app for `arm64` and `x86_64`.
2. Builds the Go engine for `arm64` and `amd64`.
3. Stages three app bundles under `dist/`: `arm64`, `x86_64`, and `universal`.
4. Creates three DMGs under `docs/releases/`:
   - `AgeMac-<version>-arm64.dmg`
   - `AgeMac-<version>-x86_64.dmg`
   - `AgeMac-<version>-universal.dmg`
5. Signs the architecture-specific DMGs for Sparkle.
6. Writes `docs/appcast-arm64.xml` and `docs/appcast-x86_64.xml`.
7. Writes `docs/appcast.xml` as a lightweight index feed.
8. Mounts each DMG, verifies the app signature, and checks the app and engine architecture slices.

The legacy command is still supported and delegates to the same DMG flow:

```bash
scripts/sparkle/release_appcast.sh
```

The app chooses the matching Sparkle feed at runtime:

```text
https://vikiea.github.io/age_mac/appcast-arm64.xml
https://vikiea.github.io/age_mac/appcast-x86_64.xml
```

DMGs are uploaded as GitHub Release assets. Appcasts point to:

```text
https://github.com/vikiea/age_mac/releases/download/v<version>/AgeMac-<version>-arm64.dmg
https://github.com/vikiea/age_mac/releases/download/v<version>/AgeMac-<version>-x86_64.dmg
```

The universal DMG is uploaded for manual downloads:

```text
https://github.com/vikiea/age_mac/releases/download/v<version>/AgeMac-<version>-universal.dmg
```

## GitHub Pages

The `pages.yml` workflow publishes the `docs/` directory. After pushing to GitHub, enable Pages with GitHub Actions as the source if it is not already enabled.

Public URLs:

- Project page: `https://vikiea.github.io/age_mac/`
- Privacy policy: `https://vikiea.github.io/age_mac/privacy/`
- Sparkle arm64 appcast: `https://vikiea.github.io/age_mac/appcast-arm64.xml`
- Sparkle x86_64 appcast: `https://vikiea.github.io/age_mac/appcast-x86_64.xml`
- Sparkle index appcast: `https://vikiea.github.io/age_mac/appcast.xml`

## Commercial Readiness

The project currently uses the MIT License, which permits private and commercial use. For future commercial distribution:

- Keep third-party notices current.
- Keep Sparkle signing keys private and rotate them if compromised.
- Notarize production builds with an Apple Developer ID.
- Add a clear release checklist for versioning, appcast signing, archive signing, notarization, and rollback.
- Keep privacy docs aligned with any future network features before shipping them.
