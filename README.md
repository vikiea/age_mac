# Age Mac

Native macOS companion for Age Android. It encrypts and decrypts local files with age, supports passphrases and X25519 key pairs, preserves streaming I/O through a bundled Go engine, and presents long-running operations in a SwiftUI desktop interface.

## Features

- Batch pack multiple files into `.tar.gz.age` or `.tar.age`
- Encrypt files separately as `.tar.age`
- Decrypt `.age` files and unpack tar/tar.gz archives automatically
- Generate and store X25519 age key pairs locally
- Persist operation history and output settings
- Run long operations through a cancellable process task with live progress

## Build And Run

```bash
./script/build_and_run.sh
```

The script builds the Go engine, builds the SwiftPM app, stages `dist/AgeMac.app`, and launches it as a foreground macOS app bundle.

## Verify

```bash
swift build
(cd Engine && env -u GOROOT go test ./...)
./script/build_and_run.sh --verify
git diff --check
```
