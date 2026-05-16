#!/usr/bin/env bash
# Release-gate cross-runtime parity check (PLAN.md Edge Cases #7).
# Runs the fuse-js and fuse-swift oracles against the shared query
# battery at scripts/parity/queries.json and diffs the canonicalized
# results with score tolerance.
#
# Exit 0 on full parity, 1 on mismatch, 2 on infra failure (missing
# fuse-js / node, oracle build failure, etc.). Output to stderr is
# diagnostic; stdout carries the summary line.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARITY_DIR="$SCRIPT_DIR/parity"

# Default fuse-js location is a sibling checkout of fuse-swift. Override
# with FUSE_JS_PATH (e.g. for CI that vendors fuse-js elsewhere).
FUSE_JS_PATH="${FUSE_JS_PATH:-$REPO_ROOT/../fuse-js/dist/fuse.mjs}"

if ! command -v node >/dev/null 2>&1; then
    echo "parity-check: node not found on PATH" >&2
    exit 2
fi
if [[ ! -f "$FUSE_JS_PATH" ]]; then
    echo "parity-check: fuse-js not found at $FUSE_JS_PATH" >&2
    echo "  set FUSE_JS_PATH to override (path must point to dist/fuse.mjs)" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

JS_OUT="$WORK/oracle-js.json"
SW_OUT="$WORK/oracle-swift.json"

echo "==> running fuse-js oracle"
FUSE_JS_PATH="$FUSE_JS_PATH" node "$PARITY_DIR/oracle-js.mjs" > "$JS_OUT"

echo "==> running fuse-swift oracle"
( cd "$PARITY_DIR/SwiftOracle" && swift run --quiet SwiftOracle ) > "$SW_OUT"

echo "==> diffing"
node "$PARITY_DIR/compare.mjs" "$JS_OUT" "$SW_OUT"
