#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/.build/localization-checks"
runner="$build_dir/localization-checks"

mkdir -p "$build_dir"

swiftc \
  "$repo_root/Sources/AgeMac/Models/AppModels.swift" \
  "$repo_root/Sources/AgeMac/Support/AppStrings.swift" \
  "$repo_root/Sources/AgeMac/Support/KeyFileCodec.swift" \
  "$repo_root/Sources/AgeMac/Services/AgeEngineClient.swift" \
  "$repo_root/Sources/AgeMac/Stores/AppPersistence.swift" \
  "$repo_root/Tests/LocalizationChecks/main.swift" \
  -o "$runner"

"$runner"
