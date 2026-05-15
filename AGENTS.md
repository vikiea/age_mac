# Age Mac Project Instructions

## Project Identity

This repository is the standalone macOS companion app for Age Android. Treat it as an independent project from `/Users/qinfuling/www/github/person/age_android`; inspect the Android repo only when intentionally comparing behavior.

The app is a SwiftPM macOS GUI app plus a local Go age engine:

- Swift app entrypoint: `Sources/AgeMac/App/AgeMacApp.swift`
- SwiftUI views: `Sources/AgeMac/Views/`
- App state and persistence: `Sources/AgeMac/Stores/AppStore.swift`
- Process bridge to the engine: `Sources/AgeMac/Services/AgeEngineClient.swift`
- File picker bridge: `Sources/AgeMac/Services/FilePanelService.swift`
- Shared models: `Sources/AgeMac/Models/AppModels.swift`
- Go streaming engine: `Engine/main.go`
- Build/run entrypoint: `script/build_and_run.sh`
- Codex Run action: `.codex/environments/environment.toml`

## Product Rules

- Preserve local-only privacy: do not add network calls, telemetry upload, cloud sync, or remote key storage unless explicitly requested.
- Keep encryption/decryption compatible with the current Go engine and age file format.
- Preserve streaming behavior for large files. Do not replace the engine pipeline with whole-file reads for archive, gzip, encryption, or decryption.
- Private keys and passphrases must not be logged, printed, stored in history records, or written outside the intended temporary secret file used by `AgeEngineClient`.
- Keep the app desktop-native: use `NavigationSplitView`, menus, toolbar actions, AppKit panels, keyboard shortcuts, and pointer-friendly controls.
- Keep the visual language Liquid Glass-style: prefer system materials, `glassEffect` behind `#available(macOS 26.0, *)`, and material fallbacks for macOS 14+.

## Development Workflow

Use the project-local skill `age-mac-development` for build, run, engine, UI, and verification tasks.

Before changing behavior:

1. Read the relevant Swift view/store/service or Go engine section.
2. Decide whether the change belongs in Swift UI/state, the Go engine, or the process bridge.
3. Keep source files focused; add a new file under `Views`, `Services`, `Stores`, `Models`, or `Support` when a file starts taking unrelated responsibilities.

## Verification

Use these commands from the repository root:

```bash
swift build
(cd Engine && env -u GOROOT go test ./...)
./script/build_and_run.sh --verify
git diff --check
```

For engine behavior changes, also run a real roundtrip with `Engine/age-engine` or through the app. The local shell may have a stale `GOROOT`; always unset it for Go commands unless you have confirmed the environment is clean.

## Git Hygiene

- This repo is intentionally standalone and has its own `.git`.
- Do not edit `age_android` while working on `age_mac` unless the user asks for a cross-project change.
- Build outputs are ignored: `.build/`, `dist/`, and `Engine/age-engine`.
- Leave unrelated local changes alone.
