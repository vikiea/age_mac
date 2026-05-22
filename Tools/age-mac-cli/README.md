# age-mac CLI

`age-mac` is the durable project automation CLI for the Age Mac repository. It wraps the existing build, verification, packaging, GitHub, and release flows with commands that work from any directory.

## Install

```bash
cd ~/www/github/vikiea/age_mac/Tools/age-mac-cli
make install-local
```

The binary is installed at:

```text
~/.local/bin/age-mac
```

## Command Shape

```bash
age-mac --json doctor
age-mac init --repo /Users/qinfuling/www/github/vikiea/age_mac
age-mac --json dev verify
age-mac --verbose --json dev package --arch all --version 1.3.2
age-mac dev run
age-mac dev debug
age-mac dev logs
age-mac --json dev package --arch all
age-mac --json repo status
age-mac repo commit --message "chore: update release tooling"
age-mac repo push --set-upstream
age-mac repo pr create --title "..." --body "..."
age-mac repo release create --version 1.3.2 --notes-file RELEASE_NOTES.md --draft
age-mac repo release upload --version 1.3.2
age-mac request gh release view v1.3.2 --json tagName,assets
```

`dev` commands are local build and runtime operations. `repo` commands are Git/GitHub operations. `request` is a raw escape hatch that runs `gh` with the configured repository environment.

Use `--verbose` for long commands to print each step, working directory, command line, exit status, and elapsed time to stderr. In `--json` mode stdout remains a single machine-readable JSON object.

## Config

`age-mac` reads `~/.age-mac/config.toml`. Explicit command flags win first, then environment variables such as `AGE_MAC_REPO`, then this config file, then repository defaults.

Run this to create or refresh the file:

```bash
age-mac init --repo /Users/qinfuling/www/github/vikiea/age_mac
```

The generated file includes these configurable values:

- `[repo]`: `default_repo`, `default_base`, `default_remote`
- `[paths]`: `build_script`, `release_script`, `release_dir`, `app_bundle`
- `[tools]`: `swift`, `go`, `git`, `gh`, `hdiutil`, `codesign`, `lldb`, `xmllint`, `lipo`
- `[release]`: `asset_name`, `display_name`

Path values may be absolute or relative to the configured repository root. Tool values affect commands launched directly by `age-mac`; build and release scripts still resolve their own internal tools and variables.

## JSON Policy

When `--json` is provided:

- stdout contains one JSON object.
- subprocess output is summarized in fields such as `stdout`, `stderr`, and `steps`.
- failures return a machine-readable error object on stdout and exit nonzero.
- credentials are not printed. `doctor` reports auth source categories only.
- verbose progress is written to stderr so JSON stdout stays parseable.

Success shape:

```json
{"ok":true,"action":"doctor","repo":"/Users/qinfuling/www/github/vikiea/age_mac","checks":[]}
```

Error shape:

```json
{"ok":false,"action":"repo release create","error":"release notes file does not exist"}
```

Write commands do narrow named actions. Remote writes such as PR creation, release creation, and release asset upload require explicit subcommands and arguments. Use `--dry-run` where available to preview the underlying commands.
