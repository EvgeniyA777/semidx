#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

if [ "${SCI_SKIP_MEMORY_FRESHNESS:-}" = "1" ]; then
  echo "MEMORY freshness: skipped by SCI_SKIP_MEMORY_FRESHNESS=1"
  exit 0
fi

zero_sha="0000000000000000000000000000000000000000"
range=""

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/check-memory-freshness.sh --range <git-range>
  scripts/check-memory-freshness.sh --pre-push <local-sha> <remote-sha>

Set SCI_SKIP_MEMORY_FRESHNESS=1 to bypass after manually confirming MEMORY.md
does not need an update.
EOF
}

default_branch_ref() {
  git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true
}

range_for_new_branch() {
  local_sha="$1"
  default_ref="$(default_branch_ref)"

  if [ -n "$default_ref" ]; then
    base="$(git merge-base "$local_sha" "$default_ref" 2>/dev/null || true)"
    if [ -n "$base" ]; then
      printf '%s..%s\n' "$base" "$local_sha"
      return 0
    fi
  fi

  parent="$(git rev-parse --verify --quiet "$local_sha^" 2>/dev/null || true)"
  if [ -n "$parent" ]; then
    printf '%s..%s\n' "$parent" "$local_sha"
  else
    printf '%s\n' "$local_sha"
  fi
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    --range)
      if [ "$#" -ne 2 ]; then
        usage
        exit 2
      fi
      range="$2"
      ;;
    --pre-push)
      if [ "$#" -ne 3 ]; then
        usage
        exit 2
      fi
      local_sha="$2"
      remote_sha="$3"
      if [ "$local_sha" = "$zero_sha" ]; then
        exit 0
      fi
      if [ "$remote_sha" = "$zero_sha" ]; then
        range="$(range_for_new_branch "$local_sha")"
      else
        range="$remote_sha..$local_sha"
      fi
      ;;
    *)
      usage
      exit 2
      ;;
  esac
else
  if git rev-parse --verify --quiet HEAD >/dev/null; then
    range="HEAD"
  else
    usage
    exit 2
  fi
fi

changed_files="$(git diff --name-only --diff-filter=ACMRT "$range" --)"

if [ -z "$changed_files" ]; then
  exit 0
fi

if printf '%s\n' "$changed_files" | grep -qx 'MEMORY.md'; then
  exit 0
fi

trigger_files="$(
  printf '%s\n' "$changed_files" |
    grep -E '^(src/|test/|scripts/|contracts/|proto/|deps\.edn$|README\.md$|RULES\.md$|AGENTS\.md$|CLAUDE\.md$|docs/(runtime-api|mcp-api|roadmap-status)\.md$|plans/|adr/|docs/(adr|design|plans)/)' || true
)"

if [ -z "$trigger_files" ]; then
  exit 0
fi

cat >&2 <<EOF
MEMORY.md freshness check failed.

The pushed range ($range) changes files that commonly affect project memory,
but does not update MEMORY.md.

Trigger files:
$trigger_files

Update MEMORY.md if current implementation reality, invariants, known gaps,
priorities, or integration assumptions changed. If you verified that no memory
update is needed, rerun with:

  SCI_SKIP_MEMORY_FRESHNESS=1 git push
EOF

exit 1
