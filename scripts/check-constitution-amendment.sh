#!/bin/sh
set -eu

# Enforces ARCHITECTURE_CONSTITUTION.md section 18: an amendment is a standalone
# commit and must not be combined with the change it permits.
#
# A commit that touches ARCHITECTURE_CONSTITUTION.md may touch only that file
# and MEMORY.md. MEMORY.md is allowed because check-memory-freshness.sh requires
# a memory update in the same pushed range.

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

if [ "${SCI_SKIP_CONSTITUTION_AMENDMENT:-}" = "1" ]; then
  echo "Constitution amendment check: skipped by SCI_SKIP_CONSTITUTION_AMENDMENT=1"
  exit 0
fi

constitution="ARCHITECTURE_CONSTITUTION.md"
allowed_pattern="^(ARCHITECTURE_CONSTITUTION\.md|MEMORY\.md)$"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/check-constitution-amendment.sh --staged
  scripts/check-constitution-amendment.sh --commit <rev>

Set SCI_SKIP_CONSTITUTION_AMENDMENT=1 to bypass after deliberately deciding
that the combined commit is correct.
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

case "$1" in
  --staged)
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    if git rev-parse --verify --quiet HEAD >/dev/null; then
      changed_files="$(git diff --cached --name-only --diff-filter=ACMRT HEAD --)"
    else
      changed_files="$(git diff --cached --name-only --diff-filter=ACMRT --)"
    fi
    scope_label="staged changes"
    ;;
  --commit)
    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi
    changed_files="$(git show --name-only --format= --diff-filter=ACMRT "$2" --)"
    scope_label="commit $2"
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [ -z "$changed_files" ]; then
  exit 0
fi

if ! printf '%s\n' "$changed_files" | grep -qx "$constitution"; then
  exit 0
fi

disallowed="$(printf '%s\n' "$changed_files" | grep -Ev "$allowed_pattern" || true)"

if [ -z "$disallowed" ]; then
  exit 0
fi

cat >&2 <<EOF
Constitution amendment check failed.

$scope_label amends $constitution but also changes other files:

$disallowed

ARCHITECTURE_CONSTITUTION.md section 18 requires an amendment to be a
standalone commit, so that the constitution is never edited into agreement with
the change it is supposed to constrain. Commit the amendment on its own (with
MEMORY.md if the freshness guard needs it), then commit the dependent change
separately.

If the combined commit is genuinely correct, bypass deliberately with:

  SCI_SKIP_CONSTITUTION_AMENDMENT=1 git commit ...
EOF

exit 1
