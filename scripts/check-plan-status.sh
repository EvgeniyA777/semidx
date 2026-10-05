#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

zero_sha="0000000000000000000000000000000000000000"
plans_dir="docs/plans"
reports_dir="docs/reports"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/check-plan-status.sh [--list]
  scripts/check-plan-status.sh --check [<rev>]
  scripts/check-plan-status.sh --pre-push <local-sha> <remote-sha>

--list (default) prints unfinished staged plans with their progress logs and any
status drift, reading the working copy. --check prints only drift and exits 1
when drift exists, reading the working copy or <rev>.

A plan's progress log is the docs/reports/NNN_*.md file the plan itself links
whose NNN equals the plan's own number.
EOF
}

# Reads from the working copy when rev is empty, otherwise from that revision.
rev=""

list_plans() {
  if [ -z "$rev" ]; then
    for f in "$plans_dir"/[0-9][0-9][0-9]_*.md; do
      [ -f "$f" ] && printf '%s\n' "$f"
    done
  else
    git ls-tree --name-only "$rev" "$plans_dir/" |
      grep -E "^$plans_dir/[0-9]{3}_[^/]*\.md$" || true
  fi
}

doc_exists() {
  if [ -z "$rev" ]; then
    [ -f "$1" ]
  else
    git cat-file -e "$rev:$1" 2>/dev/null
  fi
}

doc_text() {
  if [ -z "$rev" ]; then
    cat "$1"
  else
    git show "$rev:$1"
  fi
}

frontmatter_field() {
  doc_text "$1" | awk -v key="$2" '
    NR == 1 && /^---[[:space:]]*$/ { inside = 1; next }
    inside && /^---[[:space:]]*$/ { exit }
    inside && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }'
}

own_report() {
  plan="$1"
  number="$(basename "$plan" | cut -c1-3)"
  name="$(doc_text "$plan" |
    grep -oE "reports/${number}_[A-Za-z0-9_-]+\.md" | head -n 1 || true)"
  if [ -n "$name" ]; then
    printf '%s/%s\n' "$reports_dir" "${name#reports/}"
  fi
}

drift_found=0
drift_lines=""
unfinished_lines=""

add_drift() {
  drift_found=1
  drift_lines="${drift_lines}  $1: $2
"
}

scan() {
  plans="$(list_plans)"
  if [ -z "$plans" ]; then
    echo "plan status: no staged plans found under $plans_dir" >&2
    exit 2
  fi

  for plan in $plans; do
    number="$(basename "$plan" | cut -c1-3)"
    status="$(frontmatter_field "$plan" status)"
    title="$(frontmatter_field "$plan" title)"
    report="$(own_report "$plan")"
    report_status=""
    report_note="no progress log named by the plan"

    if [ -n "$report" ]; then
      if doc_exists "$report"; then
        report_status="$(frontmatter_field "$report" status)"
        report_note="$report ($report_status)"
      else
        report_note="$report (not created yet)"
      fi
    fi

    case "$status" in
      in_progress|blocked|completed)
        if [ -z "$report" ]; then
          add_drift "$plan" "plan is $status but names no progress log"
        elif [ -z "$report_status" ] && ! doc_exists "$report"; then
          add_drift "$plan" "plan is $status but $report does not exist"
        elif [ "$report_status" != "$status" ]; then
          add_drift "$plan" "plan is $status but $report is ${report_status:-missing a status}"
        fi
        ;;
      draft|planned)
        if [ -n "$report" ] && doc_exists "$report"; then
          add_drift "$plan" "plan is $status but $report already exists ($report_status)"
        fi
        ;;
      cancelled)
        if [ "$report_status" = "in_progress" ]; then
          add_drift "$plan" "plan is cancelled but $report is in_progress"
        fi
        ;;
      *)
        add_drift "$plan" "plan status '${status}' is not a plan status"
        ;;
    esac

    if [ -n "$report_status" ]; then
      case "$report_status" in
        in_progress|blocked|completed) ;;
        *) add_drift "$report" "status '${report_status}' is not a progress-log status" ;;
      esac
    fi

    case "$status" in
      completed|cancelled) ;;
      *)
        unfinished_lines="${unfinished_lines}  $number  $status  $title
       plan:   $plan
       report: $report_note
"
        ;;
    esac
  done
}

print_drift() {
  if [ "$drift_found" -eq 1 ]; then
    printf 'Plan status drift:\n%s' "$drift_lines"
  else
    echo "Plan status drift: none"
  fi
}

check_failed() {
  cat >&2 <<EOF
Plan status check failed${rev:+ at $rev}.

A staged plan and its progress log must agree on status; update both
frontmatters in the same commit (docs/agent-policy/documentation.md, Progress
Logs).

$(print_drift)
EOF
  exit 1
}

case "${1:---list}" in
  --list)
    if [ "$#" -gt 1 ]; then
      usage
      exit 2
    fi
    scan
    if [ -n "$unfinished_lines" ]; then
      printf 'Unfinished plans:\n%s' "$unfinished_lines"
    else
      echo "Unfinished plans: none"
    fi
    print_drift
    ;;
  --check)
    if [ "$#" -gt 2 ]; then
      usage
      exit 2
    fi
    rev="${2:-}"
    scan
    [ "$drift_found" -eq 0 ] || check_failed
    ;;
  --pre-push)
    if [ "$#" -ne 3 ]; then
      usage
      exit 2
    fi
    if [ "$2" = "$zero_sha" ]; then
      exit 0
    fi
    rev="$2"
    scan
    [ "$drift_found" -eq 0 ] || check_failed
    ;;
  *)
    usage
    exit 2
    ;;
esac
