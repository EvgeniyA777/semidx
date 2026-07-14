#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

hook_dir="$(git rev-parse --git-path hooks)"
mkdir -p "$hook_dir"

chmod +x scripts/git-hooks/pre-push scripts/check-memory-freshness.sh
ln -sf "$repo_root/scripts/git-hooks/pre-push" "$hook_dir/pre-push"

echo "Installed versioned pre-push hook -> $hook_dir/pre-push"
