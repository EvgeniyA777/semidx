#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GRAMMARS_DIR="${SEMIDX_TREE_SITTER_GRAMMARS_DIR:-$ROOT_DIR/.tree-sitter-grammars}"
MANAGED_BIN_DIR="${SEMIDX_TREE_SITTER_MANAGED_BIN_DIR:-$GRAMMARS_DIR/bin}"
MANAGED_TREE_SITTER_CLI="$MANAGED_BIN_DIR/tree-sitter"
TREE_SITTER_CLI_SOURCE="${SEMIDX_TREE_SITTER_CLI_PATH:-}"
CLOJURE_REPO="${SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_REPO:-https://github.com/sogaiu/tree-sitter-clojure.git}"
JAVA_REPO="${SEMIDX_TREE_SITTER_JAVA_GRAMMAR_REPO:-https://github.com/tree-sitter/tree-sitter-java.git}"
ZIG_REPO="${SEMIDX_TREE_SITTER_ZIG_GRAMMAR_REPO:-https://github.com/tree-sitter-grammars/tree-sitter-zig.git}"
CLOJURE_REF="${SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_REF:-e43eff80d17cf34852dcd92ca5e6986d23a7040f}"
JAVA_REF="${SEMIDX_TREE_SITTER_JAVA_GRAMMAR_REF:-e10607b45ff745f5f876bfa3e94fbcc6b44bdc11}"
ZIG_REF="${SEMIDX_TREE_SITTER_ZIG_GRAMMAR_REF:-6479aa13f32f701c383083d8b28360ebd682fb7d}"
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

# Product grammars: exactly the checkouts `build.zig` compiles, in the order of
# its `grammar_checkouts` list. This script fetches nothing the build does not
# compile; analysis tooling that needs other grammars owns its own setup.
PRODUCT_GRAMMARS=("tree-sitter-java" "tree-sitter-clojure" "tree-sitter-zig")

# Fail before any network access when this list and `build.zig` disagree.
check_grammars_match_build() {
  local build_file="$ROOT_DIR/build.zig"
  local declared
  declared="$(sed -n 's/^const grammar_checkouts = \[_\]\[\]const u8{ \(.*\) };$/\1/p' "$build_file" | tr -d '",')"
  if [[ -z "$declared" ]]; then
    echo "error: could not read grammar_checkouts from $build_file" >&2
    exit 1
  fi
  if [[ "$(echo $declared)" != "${PRODUCT_GRAMMARS[*]}" ]]; then
    echo "error: PRODUCT_GRAMMARS disagrees with grammar_checkouts in $build_file" >&2
    echo "  build.zig: $(echo $declared)" >&2
    echo "  script:    ${PRODUCT_GRAMMARS[*]}" >&2
    exit 1
  fi
}

check_grammars_match_build

mkdir -p "$GRAMMARS_DIR" "$MANAGED_BIN_DIR"

sync_grammar() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local dir="$GRAMMARS_DIR/$name"

  if [[ -d "$dir/.git" ]]; then
    # A full commit id that is already present cannot move, so a rerun needs no
    # network access. Any other ref is fetched so it resolves against origin.
    if [[ "$ref" =~ ^[0-9a-f]{40}$ ]] && git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null; then
      :
    else
      git -C "$dir" fetch --tags --force --prune origin >/dev/null
    fi
  else
    git clone --filter=blob:none "$repo" "$dir" >/dev/null
  fi

  git -C "$dir" checkout --detach "$ref" >/dev/null
}

for grammar in "${PRODUCT_GRAMMARS[@]}"; do
  case "$grammar" in
    tree-sitter-clojure) sync_grammar "$grammar" "$CLOJURE_REPO" "$CLOJURE_REF" ;;
    tree-sitter-java) sync_grammar "$grammar" "$JAVA_REPO" "$JAVA_REF" ;;
    tree-sitter-zig) sync_grammar "$grammar" "$ZIG_REPO" "$ZIG_REF" ;;
    *)
      echo "error: no repository and ref configured for $grammar" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TREE_SITTER_CLI_SOURCE" ]]; then
  TREE_SITTER_CLI_SOURCE="$(command -v tree-sitter || true)"
fi

if [[ -n "$TREE_SITTER_CLI_SOURCE" && -x "$TREE_SITTER_CLI_SOURCE" ]]; then
  if [[ "$TREE_SITTER_CLI_SOURCE" != "$MANAGED_TREE_SITTER_CLI" ]]; then
    ln -sf "$TREE_SITTER_CLI_SOURCE" "$MANAGED_TREE_SITTER_CLI"
  fi
  TREE_SITTER_CLI_PATH="$MANAGED_TREE_SITTER_CLI"
  TREE_SITTER_CLI_STATUS="managed"
else
  TREE_SITTER_CLI_PATH=""
  TREE_SITTER_CLI_STATUS="unavailable"
fi

CLOJURE_PATH="$GRAMMARS_DIR/tree-sitter-clojure"
JAVA_PATH="$GRAMMARS_DIR/tree-sitter-java"
ZIG_PATH="$GRAMMARS_DIR/tree-sitter-zig"

if [[ -n "$ENV_FILE" ]]; then
  {
    if [[ -n "$TREE_SITTER_CLI_PATH" ]]; then
      echo "SEMIDX_TREE_SITTER_CLI_PATH=$TREE_SITTER_CLI_PATH"
    fi
    echo "SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_PATH=$CLOJURE_PATH"
    echo "SEMIDX_TREE_SITTER_JAVA_GRAMMAR_PATH=$JAVA_PATH"
    echo "SEMIDX_TREE_SITTER_ZIG_GRAMMAR_PATH=$ZIG_PATH"
  } > "$ENV_FILE"
  echo "wrote_env_file=$ENV_FILE"
fi

echo "tree_sitter_cli_status=$TREE_SITTER_CLI_STATUS"
if [[ -n "$TREE_SITTER_CLI_PATH" ]]; then
  echo "tree_sitter_cli=$TREE_SITTER_CLI_PATH"
fi
echo "tree_sitter_clojure_grammar=$CLOJURE_PATH"
echo "tree_sitter_java_grammar=$JAVA_PATH"
echo "tree_sitter_zig_grammar=$ZIG_PATH"
echo "tree_sitter_clojure_ref=$CLOJURE_REF"
echo "tree_sitter_java_ref=$JAVA_REF"
echo "tree_sitter_zig_ref=$ZIG_REF"

if [[ -n "$TREE_SITTER_CLI_PATH" ]]; then
  echo "export SEMIDX_TREE_SITTER_CLI_PATH=$TREE_SITTER_CLI_PATH"
fi
echo "export SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_PATH=$CLOJURE_PATH"
echo "export SEMIDX_TREE_SITTER_JAVA_GRAMMAR_PATH=$JAVA_PATH"
echo "export SEMIDX_TREE_SITTER_ZIG_GRAMMAR_PATH=$ZIG_PATH"
