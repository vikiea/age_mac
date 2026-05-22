---
name: age-mac-development
description: Develop, build, run, debug, package, verify, or release the Age Mac standalone macOS app. Use when working in this repository, changing SwiftUI UI, the Go age engine, long-running task execution, key/history/settings persistence, Liquid Glass styling, project verification, the age-mac CLI, or release workflows.
---

<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->

# Age Mac Development

## Scope

Use this skill for the standalone `age_mac` project. Do not edit Android companion code unless the user explicitly asks for cross-project changes.

## Architecture Map

- `Package.swift`: SwiftPM app package.
- `Sources/AgeMac/App/AgeMacApp.swift`: app entrypoint, commands, settings scene.
- `Sources/AgeMac/Views/`: SwiftUI screens and shared UI components.
- `Sources/AgeMac/Stores/AppStore.swift`: app state, JSON persistence, long-running task lifecycle.
- `Sources/AgeMac/Services/AgeEngineClient.swift`: `Process` bridge to the Go engine, JSONL event parsing, temp secret/file-list handling.
- `Sources/AgeMac/Services/FilePanelService.swift`: AppKit open panels and Finder reveal actions.
- `Sources/AgeMac/Models/AppModels.swift`: shared enums and codable models.
- `Engine/main.go`: streaming tar/gzip/age CLI engine.
- `script/build_and_run.sh`: single build/run entrypoint for Go + Swift + staged `.app`.
- `.codex/environments/environment.toml`: Codex Run button action.

## Behavior Rules

- Preserve local-only privacy. Do not add network behavior, upload telemetry, cloud sync, or remote key storage.
- Never log or persist passphrases or private keys outside intended local key storage and the temporary secret file used to invoke the engine.
- Preserve streaming behavior for large files. Avoid whole-file reads in Go engine archive/encrypt/decrypt paths.
- Preserve Android-compatible output behavior:
  - batch encryption emits `.tar.gz.age` or `.tar.age`;
  - separate encryption emits one `.tar.age` per input file;
  - decrypt auto-extracts tar/tar.gz when possible.
- Keep the app desktop-native: sidebar/detail layout, menus, keyboard shortcuts, AppKit panels, and Finder reveal actions.
- Use Liquid Glass-style UI through system materials and guarded `glassEffect` usage:
  `if #available(macOS 26.0, *) { ...glassEffect(...) } else { ...regularMaterial... }`.

## Build And Run

From the repository root:

```bash
swift build
env -u GOROOT go test ./...
./script/build_and_run.sh --verify
```

Use `./script/build_and_run.sh` for a normal launch. The script builds `Engine/age-engine`, builds SwiftPM, stages `dist/AgeMac.app`, copies the engine into app resources, and launches the app bundle.

The local shell may export a stale `GOROOT` from another Go installation. Use `env -u GOROOT` for manual Go commands and keep that protection in scripts.

## Age Mac CLI

Use the installed `age-mac` CLI for repeatable project operations, especially release work:

```bash
command -v age-mac
age-mac --json doctor
```

`doctor` reports the resolved config path, repository, default base branch, default remote, script paths, release asset naming, tool commands, and GitHub auth source. If defaults are missing:

```bash
age-mac init --repo /path/to/age_mac
```

Config lives at `~/.age-mac/config.toml`. Prefer config defaults for repeated work and command flags for one-off overrides. Auth uses `gh` first; `GH_TOKEN` or `GITHUB_TOKEN` can also be used, but do not print token values.

Configurable groups:

- `[repo]`: `default_repo`, `default_base`, `default_remote`
- `[paths]`: `build_script`, `release_script`, `release_dir`, `app_bundle`
- `[tools]`: `swift`, `go`, `git`, `gh`, `hdiutil`, `codesign`, `lldb`, `xmllint`, `lipo`
- `[release]`: `asset_name`, `display_name`

Safe local commands:

```bash
age-mac --json repo status
age-mac --json dev verify
age-mac --json dev roundtrip
age-mac --verbose --json dev package --arch all --version 1.3.2
age-mac --verbose --json repo release verify --version 1.3.2
```

Preview write commands first when possible:

```bash
age-mac repo commit --path Tools/age-mac-cli --message "chore: update project automation cli" --dry-run
age-mac repo push --set-upstream --dry-run
age-mac repo pr create --fill --draft --dry-run
age-mac repo release create --version 1.3.2 --title "Age Mac 1.3.2" --notes "Release notes" --asset pages/releases/AgeMac-1.3.2-universal.dmg --dry-run
age-mac repo release publish --version 1.3.2 --dry-run
```

Only run live PR creation, release creation, release asset upload, or public release publishing when the user explicitly asks for that action. Release creation defaults to a GitHub draft; use `--live` only when the user asks to publish a non-draft release.

Use repeated `--asset <PATH>` flags with `repo release create` when creating a release and uploading prepared DMGs in one command. Use `repo release verify` after publishing to validate appcast XML, local DMG images, and uploaded GitHub release asset names/sizes in one CLI-level check. Use `--verbose` for long build/package/release commands so progress goes to stderr while JSON stays clean on stdout.

Use the raw `gh` escape hatch only when the high-level command is missing:

```bash
age-mac --json request -- release view v1.3.1 --json tagName,assets
```

Do not use raw mutating `gh` commands unless the user requested that exact write.

## Engine Roundtrip Check

Run this after changing `Engine/main.go`, `AgeEngineClient.swift`, encryption/decryption forms, or file/output handling:

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

Expected result: both `cmp` commands exit `0`.

## Implementation Guidance

- Put UI-only changes in `Views/`.
- Put app state, persistence, task orchestration, and user actions in `AppStore.swift`.
- Put engine invocation or JSONL parsing changes in `AgeEngineClient.swift`.
- Put crypto/archive/file-format changes in `Engine/main.go`.
- Keep Go engine stdout machine-readable JSON Lines; use stderr only for diagnostics.
- When adding engine flags, update both `Engine/main.go` and `AgeEngineClient.swift`, then run the roundtrip check.

## Completion Checklist

Before claiming completion:

```bash
swift build
env -u GOROOT go test ./...
git diff --check
```

Also run `./script/build_and_run.sh --verify` for UI, launch, script, or packaging changes.
