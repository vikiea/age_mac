#!/usr/bin/env bash
#
# Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
# This code is released under the MIT License.
# See LICENSE for details.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

find_generate_keys() {
  local candidate
  for candidate in \
    "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys" \
    "$ROOT_DIR/.build/checkouts/Sparkle/generate_keys"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if ! GENERATE_KEYS="$(find_generate_keys)"; then
  (cd "$ROOT_DIR" && swift build >/dev/null)
  GENERATE_KEYS="$(find_generate_keys)"
fi

"$GENERATE_KEYS"
