#!/usr/bin/env bash

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  candidates=(/opt/homebrew/bin/bash /usr/local/bin/bash)
  if command -v brew > /dev/null 2>&1; then
    candidates=("$(brew --prefix bash 2> /dev/null)/bin/bash" "${candidates[@]}")
  fi
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]] && "$candidate" -c '((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3)))'; then
      exec "$candidate" "$0" "$@"
    fi
  done
  echo "Error: Bash 4.3 or later is required, but no suitable interpreter was found (tried: ${candidates[*]})." >&2
  exit 1
fi

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "[1/3] verify README documents em_/en_ symlinks and omits _mnn"
if ! grep -qF -- "- [\`em_\`](em_):" README.md; then
  echo "README is missing the em_ symlink entry" >&2
  exit 1
fi
if ! grep -qF -- "- [\`en_\`](en_):" README.md; then
  echo "README is missing the en_ symlink entry" >&2
  exit 1
fi
if grep -qF -- "- [\`_mnn\`](_mnn):" README.md; then
  echo "README should document em_ and en_ symlinks, not _mnn" >&2
  exit 1
fi

echo "[2/3] verify prepare-readme succeeds on current repository"
./scripts/prepare-readme.sh

echo "[3/3] verify prepare-readme fails on malformed README entry"
cp README.md "$tmpdir/README.md.bak"
restore_readme() {
  cp "$tmpdir/README.md.bak" README.md
}
trap 'restore_readme; rm -rf "$tmpdir"' EXIT

# Intentionally inject a malformed script entry inside the Scripts section.
awk '
{ print }
/^- \[`en_`\]\(en_\):/ {
  print "- [`em_`](em_) / [`en_`](en_): Malformed combined entry."
}
' README.md > "$tmpdir/README.md.bad"

if cmp -s README.md "$tmpdir/README.md.bad"; then
  echo "Failed to inject malformed README entry for prepare-readme negative test" >&2
  exit 1
fi

cp "$tmpdir/README.md.bad" README.md

if ./scripts/prepare-readme.sh > /dev/null 2>&1; then
  echo "Expected prepare-readme.sh to fail for malformed README, but it succeeded" >&2
  exit 1
fi

echo "prepare-readme tests passed"
