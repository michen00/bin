#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$repo_root/README.md"

if [[ ! -f "$readme" ]]; then
  echo "README.md not found at $readme" >&2
  exit 1
fi

# Validate script docs consistency; this enforces current project assumptions:
# - symlinks such as em_/en_ are excluded from script discovery
# - symlink targets such as _mnn are excluded from script discovery
"$repo_root/.github/scripts/validate-scripts.sh"

# Keep output stable for CI and local runs.
echo "README is up to date"
