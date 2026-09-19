#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

zero_sha="0000000000000000000000000000000000000000"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/check-readme-stewardship.sh --all
  scripts/check-readme-stewardship.sh --staged
  scripts/check-readme-stewardship.sh --text <scope-label> <text-file>
  scripts/check-readme-stewardship.sh --range <git-range>
  scripts/check-readme-stewardship.sh --pre-push <local-sha> <remote-sha>

This guard keeps the root README as public presentation and routing, not a
progress log, release gate, staged-plan checklist, or implementation evidence
store.
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

changed_files_for_range() {
  range="$1"
  case "$range" in
    *..*)
      git diff --name-only --diff-filter=ACMRT "$range" --
      ;;
    *)
      git diff-tree --no-commit-id --name-only -r --diff-filter=ACMRT "$range" --
      ;;
  esac
}

tip_for_range() {
  range="$1"
  case "$range" in
    *..*) printf '%s\n' "${range##*..}" ;;
    *) printf '%s\n' "$range" ;;
  esac
}

has_readme_change() {
  range="$1"
  changed_files_for_range "$range" | grep -qx 'README.md'
}

scan_file() {
  scope="$1"
  file="$2"
  if [ ! -f "$file" ]; then
    echo "README stewardship: text file not found: $file" >&2
    exit 2
  fi

  progress_pattern='(^|[^[:alnum:]_])(Plan[[:space:]]+[0-9]{3}|Stage[[:space:]]+[0-9]+|Stage[[:space:]]+Log|progress[[:space:]-]+log|release[[:space:]-]+gate[[:space:]-]+evidence|hard[[:space:]-]+pass|Build[[:space:]]+Summary|[0-9]+/[0-9]+[[:space:]]+(steps|tests)[[:space:]]+(passed|succeeded)|residual[[:space:]-]+risk|Next[[:space:]-]+Handoff|Changed[[:space:]]+files|commit[[:space:]]+[0-9a-f]{7,40}|docs/reports/|docs/plans/)'
  inventory_pattern='^[[:space:]]*(Implemented today:|Not present yet:|Current implementation reality|Known gaps|Near-term priorities)'

  progress_matches="$(grep -n -E -i "$progress_pattern" "$file" || true)"
  inventory_matches="$(grep -n -E "$inventory_pattern" "$file" || true)"
  matches="$(
    {
      if [ -n "$progress_matches" ]; then
        printf '%s\n' "$progress_matches"
      fi
      if [ -n "$inventory_matches" ]; then
        printf '%s\n' "$inventory_matches"
      fi
    } | sed '/^$/d'
  )"

  if [ -n "$matches" ]; then
    cat >&2 <<EOF
README stewardship check failed in $scope.

The root README should stay a public project presentation and routing entry
point. Move progress-log, release-gate, staged-plan, implementation-inventory,
and evidence details to MEMORY.md, docs/spec/capability_matrix.md,
docs/mcp/local_preview.md, docs/releases/, docs/reports/, or docs/plans/.

Matches:
$matches
EOF
    return 1
  fi
}

scan_all() {
  if ! git rev-parse --verify --quiet HEAD >/dev/null; then
    return 0
  fi
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  if git show HEAD:README.md >"$tmp" 2>/dev/null; then
    scan_file "README.md at HEAD" "$tmp"
  fi
}

scan_staged() {
  if ! git diff --cached --name-only --diff-filter=ACMRT -- | grep -qx 'README.md'; then
    return 0
  fi
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  git show :README.md >"$tmp"
  scan_file "staged README.md" "$tmp"
}

scan_range() {
  range="$1"
  if [ -z "$range" ]; then
    usage
    exit 2
  fi

  if ! has_readme_change "$range"; then
    return 0
  fi

  tree="$(tip_for_range "$range")"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  if git show "$tree:README.md" >"$tmp" 2>/dev/null; then
    scan_file "README.md at $tree" "$tmp"
  fi
}

scan_pre_push() {
  local_sha="$1"
  remote_sha="$2"

  if [ "$local_sha" = "$zero_sha" ]; then
    return 0
  fi

  if [ "$remote_sha" = "$zero_sha" ]; then
    range="$(range_for_new_branch "$local_sha")"
  else
    range="$remote_sha..$local_sha"
  fi

  scan_range "$range"
}

case "${1:-}" in
  --all)
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    scan_all
    ;;
  --staged)
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    scan_staged
    ;;
  --text)
    if [ "$#" -ne 3 ]; then
      usage
      exit 2
    fi
    scan_file "$2" "$3"
    ;;
  --range)
    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi
    scan_range "$2"
    ;;
  --pre-push)
    if [ "$#" -ne 3 ]; then
      usage
      exit 2
    fi
    scan_pre_push "$2" "$3"
    ;;
  *)
    usage
    exit 2
    ;;
esac
