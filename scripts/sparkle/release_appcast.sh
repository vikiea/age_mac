#!/usr/bin/env bash
#
# Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
# This code is released under the MIT License.
# See LICENSE for details.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "$ROOT_DIR/scripts/release/build_dmg_release.sh" all
