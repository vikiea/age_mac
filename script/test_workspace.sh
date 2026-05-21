#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/.build/workspace-checks"
runner="$build_dir/workspace-checks"

mkdir -p "$build_dir"

swiftc \
  -parse-as-library \
  "$repo_root/Sources/AgeMac/Models/AppModels.swift" \
  "$repo_root/Sources/AgeMac/Support/AppStrings.swift" \
  "$repo_root/Sources/AgeMac/Support/KeyFileCodec.swift" \
  "$repo_root/Sources/AgeMac/Services/AgeEngineClient.swift" \
  "$repo_root/Sources/AgeMac/Services/FilePanelService.swift" \
  "$repo_root/Sources/AgeMac/Services/KeychainSecretStore.swift" \
  "$repo_root/Sources/AgeMac/Services/LocalAuthenticationService.swift" \
  "$repo_root/Sources/AgeMac/Stores/AppPersistence.swift" \
  "$repo_root/Sources/AgeMac/Stores/AppStore.swift" \
  "$repo_root/Sources/AgeMac/Stores/WorkspaceStore.swift" \
  "$repo_root/Tests/WorkspaceChecks/main.swift" \
  -o "$runner"

"$runner"
