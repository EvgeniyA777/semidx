#!/usr/bin/env bash
set -euo pipefail

# Repo-managed scip-typescript toolchain (plans/018 Stage 3, ADR-046).
#
# scip-typescript is the exact-tier semantic provider for the TypeScript lane.
# Like the tree-sitter toolchain (ADR-047), it is resolved through explicit
# configuration and a repository-managed install rather than an ambient global
# command, so a SCIP index is reproducible across developer and agent machines.
#
# Resolution order for the CLI (implemented by the provider adapter, mirrored
# here):
#   1. explicit provider option (:scip_typescript_cli_path)
#   2. environment: SEMIDX_SCIP_TYPESCRIPT_CLI_PATH
#   3. repo-managed: .scip-toolchain/node_modules/.bin/scip-typescript
#   4. ambient PATH (developer convenience only)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN_DIR="${SEMIDX_SCIP_TOOLCHAIN_DIR:-$ROOT_DIR/.scip-toolchain}"
SCIP_TYPESCRIPT_PKG="@sourcegraph/scip-typescript"
SCIP_TYPESCRIPT_REF="${SEMIDX_SCIP_TYPESCRIPT_REF:-0.4.0}"
MANAGED_CLI="$TOOLCHAIN_DIR/node_modules/.bin/scip-typescript"
ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v npm >/dev/null 2>&1; then
  echo "scip_typescript_status=unavailable"
  echo "scip_typescript_reason=npm_missing"
  exit 1
fi

mkdir -p "$TOOLCHAIN_DIR"

# A minimal manifest keeps the pinned version in one place and lets `npm install`
# be idempotent. It is intentionally not the repo's own package.json.
cat > "$TOOLCHAIN_DIR/package.json" <<EOF
{
  "name": "semidx-scip-toolchain",
  "private": true,
  "description": "Repo-managed scip-typescript toolchain for plans/018. Managed by scripts/setup-scip-typescript.sh.",
  "dependencies": {
    "$SCIP_TYPESCRIPT_PKG": "$SCIP_TYPESCRIPT_REF"
  }
}
EOF

(cd "$TOOLCHAIN_DIR" && npm install --silent --no-audit --no-fund >/dev/null)

if [[ -x "$MANAGED_CLI" ]]; then
  SCIP_TYPESCRIPT_CLI_PATH="$MANAGED_CLI"
  SCIP_TYPESCRIPT_STATUS="managed"
  SCIP_TYPESCRIPT_VERSION="$(cd "$TOOLCHAIN_DIR" && node -p "require('$SCIP_TYPESCRIPT_PKG/package.json').version" 2>/dev/null || echo unknown)"
else
  SCIP_TYPESCRIPT_CLI_PATH=""
  SCIP_TYPESCRIPT_STATUS="unavailable"
  SCIP_TYPESCRIPT_VERSION=""
fi

if [[ -n "$ENV_FILE" ]]; then
  {
    if [[ -n "$SCIP_TYPESCRIPT_CLI_PATH" ]]; then
      echo "SEMIDX_SCIP_TYPESCRIPT_CLI_PATH=$SCIP_TYPESCRIPT_CLI_PATH"
    fi
    echo "SEMIDX_SCIP_TYPESCRIPT_REF=$SCIP_TYPESCRIPT_REF"
  } > "$ENV_FILE"
  echo "wrote_env_file=$ENV_FILE"
fi

echo "scip_typescript_status=$SCIP_TYPESCRIPT_STATUS"
echo "scip_typescript_ref=$SCIP_TYPESCRIPT_REF"
if [[ -n "$SCIP_TYPESCRIPT_CLI_PATH" ]]; then
  echo "scip_typescript_cli=$SCIP_TYPESCRIPT_CLI_PATH"
  echo "scip_typescript_version=$SCIP_TYPESCRIPT_VERSION"
  echo "export SEMIDX_SCIP_TYPESCRIPT_CLI_PATH=$SCIP_TYPESCRIPT_CLI_PATH"
fi
