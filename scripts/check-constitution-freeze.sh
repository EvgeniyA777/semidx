#!/bin/sh
set -eu

# Enforces ARCHITECTURE_CONSTITUTION.md section 18.
#
# The document has two states, declared on its own status line, and this script
# reads that state from the version *before* the change being checked.
#
# DRAFT
#   The text may change freely, but a commit touching the constitution may touch
#   only that file and MEMORY.md, so the document is never edited into agreement
#   with the change it is supposed to constrain.
#
# RATIFIED
#   The file does not change. The protection is a SHA-256 seal committed at
#   scripts/constitution.freeze.sha256, in shasum format:
#
#       <sha256>  ARCHITECTURE_CONSTITUTION.md
#
#   The expected hash is always read from HEAD's seal, never from the seal being
#   staged, so regenerating the seal alongside an edited constitution does not
#   authorise the edit. The constitution is hashed from the staged blob in the
#   git index, not from the working tree, so an unstaged experiment is not a
#   violation and a staged one cannot hide behind a clean file on disk.
#
#   Bootstrap: the constitution was ratified before this seal existed, so the
#   first commit that adds the seal is allowed on three conditions — HEAD carries
#   no seal, the staged constitution is byte-for-byte HEAD's, and the new seal
#   records the SHA-256 of HEAD:ARCHITECTURE_CONSTITUTION.md. Any constitution
#   change in that same commit is refused.
#
#   After bootstrap the seal itself is frozen too: modifying, deleting, or
#   renaming it is refused, as is deleting or renaming the constitution.
#
# The check fails closed. A missing SHA-256 tool, an unreadable status line, or a
# seal that is absent, malformed, or unparseable blocks the commit rather than
# waving it through.
#
# SCI_SKIP_CONSTITUTION_FREEZE=1 remains the one manual bypass. After
# ratification it exists for section 18's single exception — a mechanical repair
# that touches no sentence — and such a repair must regenerate the seal in the
# same commit.

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

constitution="ARCHITECTURE_CONSTITUTION.md"
seal="scripts/constitution.freeze.sha256"

if [ "${SCI_SKIP_CONSTITUTION_FREEZE:-}" = "1" ]; then
  cat >&2 <<EOF
WARNING: constitution freeze check bypassed by SCI_SKIP_CONSTITUTION_FREEZE=1.

$constitution is RATIFIED. The only change this bypass is meant to release is the
mechanical repair section 18 allows — one that touches no sentence. If you made
such a repair, regenerate $seal in the same commit, or every later commit will be
refused.
EOF
  exit 0
fi

usage() {
  cat >&2 <<EOF
Usage:
  scripts/check-constitution-freeze.sh --staged
  scripts/check-constitution-freeze.sh --commit <rev>

Regenerate the seal (only alongside a deliberate, bypassed section 18 repair):
  shasum -a 256 $constitution > $seal
EOF
}

scope_label=""

fail() {
  cat >&2 <<EOF
Constitution freeze check failed.

$scope_label: $1

Section 18 gives a ratified document one behaviour: it does not change. No clause
is rewritten, relaxed, strengthened, clarified, renumbered, or reworded, and
there is no amendment procedure to invoke. A constraint that turns out to be
wrong is not a defect in this file; it means a different product needs to exist,
and the mechanism for that is a fork with its own constitution.

If this is section 18's one exception — a mechanical repair that touches no
sentence, such as a broken link or a malformed table — make that visible and
bypass deliberately, regenerating the seal in the same commit:

  SCI_SKIP_CONSTITUTION_FREEZE=1 git commit ...
EOF
  exit 1
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
    target=":"
    if git rev-parse --verify --quiet HEAD >/dev/null; then
      base="HEAD"
    else
      base=""
    fi
    scope_label="staged changes"
    ;;
  --commit)
    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi
    if ! git rev-parse --verify --quiet "$2" >/dev/null; then
      echo "check-constitution-freeze.sh: unknown revision '$2'" >&2
      exit 2
    fi
    target="$2:"
    base="$(git rev-parse --verify --quiet "$2^" || true)"
    scope_label="commit $2"
    ;;
  *)
    usage
    exit 2
    ;;
esac

if command -v shasum >/dev/null 2>&1; then
  sha_cmd="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  sha_cmd="sha256sum"
else
  fail "no SHA-256 tool is available (looked for shasum and sha256sum), so the seal cannot be verified"
fi

blob_exists() {
  git cat-file -e "$1" 2>/dev/null
}

blob_sha256() {
  git cat-file blob "$1" | $sha_cmd | cut -d' ' -f1
}

seal_hash() {
  # stdin: seal file content. stdout: the recorded hash, or nothing if the seal
  # is not exactly one line of "<64 hex>  ARCHITECTURE_CONSTITUTION.md".
  content="$(cat)"
  lines="$(printf '%s\n' "$content" | grep -cv '^[[:space:]]*$' || true)"
  if [ "$lines" != "1" ]; then
    return 1
  fi
  line="$(printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | head -1)"
  if ! printf '%s\n' "$line" | grep -Eq "^[0-9a-f]{64}  $constitution\$"; then
    return 1
  fi
  printf '%s\n' "$line" | cut -c1-64
}

if [ -z "$base" ]; then
  exit 0
fi

if blob_exists "$base:$constitution"; then
  status="$(
    git cat-file blob "$base:$constitution" |
      sed -n 's/^\*\*Status: \([A-Za-z]*\).*/\1/p' |
      head -1
  )"
else
  # The constitution does not exist yet in the base revision, so there is no
  # ratified text to protect. Treat it as a draft being introduced.
  status="DRAFT"
fi

case "$status" in
  RATIFIED|DRAFT) ;;
  *)
    fail "the status line in $base:$constitution is missing or unreadable, so the freeze state cannot be determined"
    ;;
esac

if [ "$status" = "RATIFIED" ]; then
  if ! blob_exists "$target$constitution"; then
    fail "$constitution is deleted or renamed; a ratified constitution stays where it is"
  fi

  base_constitution="$(blob_sha256 "$base:$constitution")"
  now_constitution="$(blob_sha256 "$target$constitution")"

  if blob_exists "$base:$seal"; then
    if ! blob_exists "$target$seal"; then
      fail "$seal is deleted or renamed; the seal is frozen with the document it protects"
    fi

    if [ "$(blob_sha256 "$base:$seal")" != "$(blob_sha256 "$target$seal")" ]; then
      fail "$seal is modified; the sealed hash is fixed, and regenerating it does not authorise a change to $constitution"
    fi

    expected="$(git cat-file blob "$base:$seal" | seal_hash || true)"
    if [ -z "$expected" ]; then
      fail "$seal in $base is malformed; expected exactly one line of '<sha256>  $constitution'"
    fi

    if [ "$now_constitution" != "$expected" ]; then
      fail "$constitution does not match the sealed hash (sealed $expected, staged $now_constitution)"
    fi

    exit 0
  fi

  # Bootstrap: HEAD carries no seal yet.
  if ! blob_exists "$target$seal"; then
    if [ "$now_constitution" != "$base_constitution" ]; then
      fail "$constitution is changed (no seal exists yet, and a ratified document does not change)"
    fi
    exit 0
  fi

  if [ "$now_constitution" != "$base_constitution" ]; then
    fail "the commit that introduces $seal must not change $constitution; seal the ratified text first, then nothing at all"
  fi

  recorded="$(git cat-file blob "$target$seal" | seal_hash || true)"
  if [ -z "$recorded" ]; then
    fail "$seal is malformed; expected exactly one line of '<sha256>  $constitution'"
  fi

  if [ "$recorded" != "$base_constitution" ]; then
    fail "$seal records $recorded, but $base:$constitution hashes to $base_constitution"
  fi

  exit 0
fi

# DRAFT: the standalone-commit rule.
case "$1" in
  --staged)
    if [ "$base" = "HEAD" ]; then
      changed_files="$(git diff --cached --name-only HEAD --)"
    else
      changed_files="$(git diff --cached --name-only --)"
    fi
    ;;
  --commit)
    changed_files="$(git show --name-only --format= "$2" --)"
    ;;
esac

if [ -z "$changed_files" ]; then
  exit 0
fi

if ! printf '%s\n' "$changed_files" | grep -qx "$constitution"; then
  exit 0
fi

disallowed="$(printf '%s\n' "$changed_files" | grep -Ev "^($constitution|MEMORY\.md)\$" || true)"

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
