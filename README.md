<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->

# Age Mac

Age Mac is a native macOS file encryption app built around the age format. It is a standalone SwiftUI desktop app with a bundled Go streaming engine, designed for local file work: choose files, encrypt or decrypt them, watch progress, and keep keys on your own machine.

Repository: [github.com/vikiea/age_mac](https://github.com/vikiea/age_mac)

## Features

- Encrypt multiple files into one `.tar.gz.age` or `.tar.age` archive.
- Encrypt files separately, one age archive per input file.
- Decrypt `.age` files and automatically unpack tar or tar.gz payloads.
- Use passphrases or X25519 age keys.
- Generate, import, rename, view, and export local age keys.
- Import existing keys from `~/.config/age` on launch.
- Keep operation history, outputs, and task progress local.
- Check for app updates with Sparkle through the public GitHub Pages appcast.

## Architecture

```text
Sources/AgeMac/App/AgeMacApp.swift          App entry, commands, scenes
Sources/AgeMac/Views/                      SwiftUI screens and components
Sources/AgeMac/Stores/AppStore.swift       State, persistence, task lifecycle
Sources/AgeMac/Services/AgeEngineClient.swift
                                            Process bridge to the Go engine
Sources/AgeMac/Services/UpdateService.swift Sparkle update checks
Sources/AgeMac/Models/AppModels.swift      Shared app models
Engine/main.go                             Streaming age engine
script/build_and_run.sh                    Local build and bundle staging
```

The Swift app owns UI, local state, AppKit panels, and task orchestration. The Go engine owns streaming tar, gzip, encryption, and decryption work. Communication between them is JSON Lines over a child process.

## Privacy Model

Age Mac is local-first. Files, passphrases, private keys, and operation history are processed and stored only on this Mac. The app does not upload files, telemetry, keys, or usage history.

When update checking is enabled or triggered, Sparkle reads public update metadata from:

```text
https://vikiea.github.io/age_mac/appcast-arm64.xml
https://vikiea.github.io/age_mac/appcast-x86_64.xml
```

The app chooses the matching feed at runtime based on the current Mac architecture.

See [PRIVACY.md](PRIVACY.md) and the hosted privacy page at [vikiea.github.io/age_mac/privacy/](https://vikiea.github.io/age_mac/privacy/).

## Build And Run

Requirements:

- macOS 14 or later
- Xcode command line tools with Swift 5.10 or newer
- Go with the toolchain declared by `Engine/go.mod`

Run the app:

```bash
./script/build_and_run.sh
```

The script builds the Go engine, builds the SwiftPM executable, stages `dist/AgeMac.app`, embeds resources and Sparkle, signs locally, registers the bundle, and launches it.

## Verify

```bash
swift build
(cd Engine && env -u GOROOT go test ./...)
./script/build_and_run.sh --verify
git diff --check
codesign --verify --deep --strict --verbose=2 dist/AgeMac.app
```

Use `env -u GOROOT` for Go commands if your shell has a stale `GOROOT` from another installation.

## Release And Updates

Age Mac uses Sparkle 2 for online updates. Architecture-specific appcasts are hosted from the `pages/` directory by GitHub Pages.

Key points:

- `SUPublicEDKey` is written into the generated app `Info.plist`.
- The Sparkle private EdDSA key stays in the local macOS Keychain or another private secret store.
- DMG release assets and appcast entries are generated with `scripts/release/build_dmg_release.sh all`.
- `scripts/sparkle/release_appcast.sh` is kept as a compatibility wrapper for the same DMG release flow.
- GitHub Pages publishes `pages/appcast-arm64.xml` and `pages/appcast-x86_64.xml`.

See [COOKBOOK.md](COOKBOOK.md) for detailed build, key, release, and appcast workflows.

## License

Age Mac is released under the [MIT License](LICENSE). Third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
