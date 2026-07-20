#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GRAMMARS_DIR="${SEMIDX_TREE_SITTER_GRAMMARS_DIR:-$ROOT_DIR/.tree-sitter-grammars}"
MANAGED_BIN_DIR="${SEMIDX_TREE_SITTER_MANAGED_BIN_DIR:-$GRAMMARS_DIR/bin}"
MANAGED_TREE_SITTER_CLI="$MANAGED_BIN_DIR/tree-sitter"
TREE_SITTER_CLI_SOURCE="${SEMIDX_TREE_SITTER_CLI_PATH:-}"
CLOJURE_REPO="${SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_REPO:-https://github.com/sogaiu/tree-sitter-clojure.git}"
ELIXIR_REPO="${SEMIDX_TREE_SITTER_ELIXIR_GRAMMAR_REPO:-https://github.com/elixir-lang/tree-sitter-elixir.git}"
JAVA_REPO="${SEMIDX_TREE_SITTER_JAVA_GRAMMAR_REPO:-https://github.com/tree-sitter/tree-sitter-java.git}"
TYPESCRIPT_REPO="${SEMIDX_TREE_SITTER_TYPESCRIPT_GRAMMAR_REPO:-https://github.com/tree-sitter/tree-sitter-typescript.git}"
CLOJURE_REF="${SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_REF:-e43eff80d17cf34852dcd92ca5e6986d23a7040f}"
ELIXIR_REF="${SEMIDX_TREE_SITTER_ELIXIR_GRAMMAR_REF:-main}"
JAVA_REF="${SEMIDX_TREE_SITTER_JAVA_GRAMMAR_REF:-e10607b45ff745f5f876bfa3e94fbcc6b44bdc11}"
TYPESCRIPT_REF="${SEMIDX_TREE_SITTER_TYPESCRIPT_GRAMMAR_REF:-75b3874edb2dc714fb1fd77a32013d0f8699989f}"
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

mkdir -p "$GRAMMARS_DIR" "$MANAGED_BIN_DIR"

sync_grammar() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local dir="$GRAMMARS_DIR/$name"

  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --tags --force --prune origin >/dev/null
  else
    git clone --filter=blob:none "$repo" "$dir" >/dev/null
  fi

  git -C "$dir" checkout --detach "$ref" >/dev/null
}

sync_grammar "tree-sitter-clojure" "$CLOJURE_REPO" "$CLOJURE_REF"
sync_grammar "tree-sitter-elixir" "$ELIXIR_REPO" "$ELIXIR_REF"
sync_grammar "tree-sitter-java" "$JAVA_REPO" "$JAVA_REF"
sync_grammar "tree-sitter-typescript" "$TYPESCRIPT_REPO" "$TYPESCRIPT_REF"

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
ELIXIR_PATH="$GRAMMARS_DIR/tree-sitter-elixir"
JAVA_PATH="$GRAMMARS_DIR/tree-sitter-java"
TYPESCRIPT_PATH="$GRAMMARS_DIR/tree-sitter-typescript/typescript"

if [[ -n "$ENV_FILE" ]]; then
  {
    if [[ -n "$TREE_SITTER_CLI_PATH" ]]; then
      echo "SEMIDX_TREE_SITTER_CLI_PATH=$TREE_SITTER_CLI_PATH"
    fi
    echo "SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_PATH=$CLOJURE_PATH"
    echo "SEMIDX_TREE_SITTER_ELIXIR_GRAMMAR_PATH=$ELIXIR_PATH"
    echo "SEMIDX_TREE_SITTER_JAVA_GRAMMAR_PATH=$JAVA_PATH"
    echo "SEMIDX_TREE_SITTER_TYPESCRIPT_GRAMMAR_PATH=$TYPESCRIPT_PATH"
  } > "$ENV_FILE"
  echo "wrote_env_file=$ENV_FILE"
fi

echo "tree_sitter_cli_status=$TREE_SITTER_CLI_STATUS"
if [[ -n "$TREE_SITTER_CLI_PATH" ]]; then
  echo "tree_sitter_cli=$TREE_SITTER_CLI_PATH"
fi
echo "tree_sitter_clojure_grammar=$CLOJURE_PATH"
echo "tree_sitter_elixir_grammar=$ELIXIR_PATH"
echo "tree_sitter_java_grammar=$JAVA_PATH"
echo "tree_sitter_typescript_grammar=$TYPESCRIPT_PATH"
echo "tree_sitter_clojure_ref=$CLOJURE_REF"
echo "tree_sitter_elixir_ref=$ELIXIR_REF"
echo "tree_sitter_java_ref=$JAVA_REF"
echo "tree_sitter_typescript_ref=$TYPESCRIPT_REF"

if [[ -n "$TREE_SITTER_CLI_PATH" ]]; then
  echo "export SEMIDX_TREE_SITTER_CLI_PATH=$TREE_SITTER_CLI_PATH"
fi
echo "export SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_PATH=$CLOJURE_PATH"
echo "export SEMIDX_TREE_SITTER_ELIXIR_GRAMMAR_PATH=$ELIXIR_PATH"
echo "export SEMIDX_TREE_SITTER_JAVA_GRAMMAR_PATH=$JAVA_PATH"
echo "export SEMIDX_TREE_SITTER_TYPESCRIPT_GRAMMAR_PATH=$TYPESCRIPT_PATH"
