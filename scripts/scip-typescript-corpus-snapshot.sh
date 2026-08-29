#!/usr/bin/env bash
set -euo pipefail

# Regenerate the committed real-SCIP reference artifact for the plans/018
# provider-authority TypeScript corpus.
#
# This is a preflight/verification aid, not part of the runtime. It proves the
# Stage 0 identity fixtures against real `scip-typescript` output and gives a
# reviewer a stable JSON to diff. The Stage 3 provider adapter reads SCIP in the
# JVM and does not depend on this script.
#
# Requires: scripts/setup-scip-typescript.sh has been run (repo-managed CLI),
# and node on PATH.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS_DIR="$ROOT_DIR/fixtures/provider-authority/corpus/typescript"
OUT_JSON="$ROOT_DIR/fixtures/provider-authority/scip/typescript-corpus.observed.json"
TOOLCHAIN_DIR="${SEMIDX_SCIP_TOOLCHAIN_DIR:-$ROOT_DIR/.scip-toolchain}"
CLI="${SEMIDX_SCIP_TYPESCRIPT_CLI_PATH:-$TOOLCHAIN_DIR/node_modules/.bin/scip-typescript}"

if [[ ! -x "$CLI" ]]; then
  echo "scip-typescript CLI not found at $CLI" >&2
  echo "run scripts/setup-scip-typescript.sh first" >&2
  exit 1
fi

# Fail closed if the installed toolchain drifted from the committed lock: SCIP
# output depends on the resolved `typescript` version, and the fixture records
# it. setup-scip-typescript.sh already guards this, but a stale .scip-toolchain/
# must not be able to produce a snapshot silently.
LOCK="$ROOT_DIR/scripts/scip-toolchain/package-lock.json"
LOCKED_TS="$(node -p "require('$LOCK').packages['node_modules/typescript'].version")"
INSTALLED_TS="$(node -p "require('$TOOLCHAIN_DIR/node_modules/typescript/package.json').version")"
if [[ "$LOCKED_TS" != "$INSTALLED_TS" ]]; then
  echo "typescript version drift: locked $LOCKED_TS, installed $INSTALLED_TS" >&2
  echo "re-run scripts/setup-scip-typescript.sh" >&2
  exit 1
fi

TMP_SCIP="$(mktemp -t scip-typescript-corpus.XXXXXX.scip)"
trap 'rm -f "$TMP_SCIP"' EXIT

(cd "$CORPUS_DIR" && "$CLI" index --no-progress-bar --output "$TMP_SCIP" >/dev/null)

node "$ROOT_DIR/scripts/lib/decode-scip.js" "$TMP_SCIP" > "$OUT_JSON"

echo "wrote $OUT_JSON"
