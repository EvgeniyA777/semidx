#!/bin/sh
set -eu

# Enforces ARCHITECTURE_CONSTITUTION.md section 18, which gives the document two
# states declared on its own status line.
#
# DRAFT: a commit touching the constitution may touch only that file and
# MEMORY.md, so the document is never edited into agreement with the change it is
# supposed to constrain. MEMORY.md is allowed because check-memory-freshness.sh
# requires a memory update in the same pushed range.
#
# RATIFIED: the file does not change at all. Section 18 permits only a mechanical
# repair that touches no sentence — a broken link, a malformed table — and
# requires it to be visibly that. No rule here can tell a repair from a rewrite,
# so a repair goes through the explicit bypass and is visible in the commit.
#
# The state is read from the version *before* the change, so the ratification
# commit itself passes under the DRAFT rule and every later change is blocked.

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

if [ "${SCI_SKIP_CONSTITUTION_FREEZE:-}" = "1" ]; then
  echo "Constitution freeze check: skipped by SCI_SKIP_CONSTITUTION_FREEZE=1"
  exit 0
fi

constitution="ARCHITECTURE_CONSTITUTION.md"
allowed_pattern="^(ARCHITECTURE_CONSTITUTION\.md|MEMORY\.md)$"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/check-constitution-freeze.sh --staged
  scripts/check-constitution-freeze.sh --commit <rev>

Set SCI_SKIP_CONSTITUTION_FREEZE=1 to bypass. Before ratification that means a
deliberately combined commit. After ratification it means a mechanical repair
that touches no sentence, and nothing else.
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
      base_rev="HEAD"
    else
      changed_files="$(git diff --cached --name-only --diff-filter=ACMRT --)"
      base_rev=""
    fi
    scope_label="staged changes"
    ;;
  --commit)
    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi
    changed_files="$(git show --name-only --format= --diff-filter=ACMRT "$2" --)"
    base_rev="$(git rev-parse --verify --quiet "$2^" || true)"
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

status_before=""
if [ -n "$base_rev" ]; then
  status_before="$(
    git show "$base_rev:$constitution" 2>/dev/null |
      sed -n 's/^\*\*Status: \([A-Z]*\).*/\1/p' |
      head -1
  )"
fi

if [ "$status_before" = "RATIFIED" ]; then
  cat >&2 <<EOF
Constitution freeze check failed.

$scope_label changes $constitution, which is RATIFIED.

Section 18 gives a ratified document one behaviour: it does not change. No clause
is rewritten, relaxed, strengthened, clarified, renumbered, or reworded, and
there is no amendment procedure to invoke. A constraint that turns out to be
wrong is not a defect in this file; it means a different product needs to exist,
and the mechanism for that is a fork with its own constitution.

If this is the one permitted exception — a mechanical repair that touches no
sentence, such as a broken link or a malformed table — make that visible and
bypass deliberately:

  SCI_SKIP_CONSTITUTION_FREEZE=1 git commit ...
EOF
  exit 1
fi

disallowed="$(printf '%s\n' "$changed_files" | grep -Ev "$allowed_pattern" || true)"

if [ -z "$disallowed" ]; then
  exit 0
fi

cat >&2 <<EOF
Constitution commit check failed.

$scope_label changes $constitution but also changes other files:

$disallowed

While the constitution is DRAFT, section 18 lets its text change freely, but a
change to the definition of the product must stand on its own, so that the
document is never edited into agreement with the change it is supposed to
constrain. Commit it alone (with MEMORY.md if the freshness guard needs it), then
commit the dependent change separately.

If the combined commit is genuinely correct, bypass deliberately with:

  SCI_SKIP_CONSTITUTION_FREEZE=1 git commit ...
EOF

exit 1
