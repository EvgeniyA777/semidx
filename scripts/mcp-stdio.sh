#!/usr/bin/env bash
# Launch the semidx MCP stdio server from any working directory.
#
# Claude Code (and some other MCP hosts) spawn stdio servers in the host
# session's working directory and do not reliably honor a per-server `cwd`
# field. Running `clojure -M:mcp` outside the semidx project resolves no
# `:mcp` alias and drops into a bare REPL, which corrupts the JSON-RPC stream
# and fails the connection. This launcher makes the command self-contained by
# always cd-ing into the semidx project root before exec-ing clojure.
#
# Reference it by absolute path from any repo's .mcp.json:
#   "semidx": { "command": "/Users/ae/workspaces/semidx/scripts/mcp-stdio.sh" }
set -euo pipefail

# Resolve the semidx project root relative to this script (scripts/..),
# following symlinks so the launcher works if referenced via a symlink.
source="${BASH_SOURCE[0]}"
while [ -h "$source" ]; do
  dir="$(cd -P "$(dirname "$source")" && pwd)"
  source="$(readlink "$source")"
  [[ "$source" != /* ]] && source="$dir/$source"
done
project_root="$(cd -P "$(dirname "$source")/.." && pwd)"

cd "$project_root"
exec clojure -M:mcp
