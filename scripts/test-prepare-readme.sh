#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "[1/2] verify prepare-readme succeeds on current repository"
./scripts/prepare-readme.sh

echo "[2/2] verify prepare-readme fails on malformed README entry"
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
