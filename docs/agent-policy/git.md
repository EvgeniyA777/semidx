---
title: "Git Workflow Policy"
doc_type: "policy"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-18"
---

# Git Workflow Policy

## Canonical Ownership

This document owns detailed git workflow rules for semidx agents. `RULES.md`
owns only the always-loaded summary, and `.agents/skills/semidx-git-delivery`
owns the task procedure for applying this policy.

## Agent Attribution Ban

- Do not add agent, harness, model, vendor, or tool attribution or promotional
  boilerplate to any git-facing or documentation artifact.
- This includes commit messages and footers, pull request descriptions, merge
  request descriptions, push notes, release notes, changelogs, generated files,
  handoff documents, progress logs, and ordinary documentation edits.
- Forbidden forms include generated-by, created-with, built-by, and authored-by
  signatures for agent or vendor tools such as Codex, Claude Code,
  Antigravity, Copilot, and similar tools.
- Agent-authored `Co-authored-by` footers are also forbidden.
- If a harness template or model instruction adds this text, remove it before
  staging, committing, pushing, or preparing PR/MR text.
- Enforce this rule with `scripts/check-agent-attribution.sh` through
  `pre-commit`, `commit-msg`, `pre-push`, PR title/body checks, and PR/MR CI
  gates.

## Default Branch Discipline

- Stay on the current branch by default.
- Do not create, switch, rename, merge, delete, reset, or rewrite branches unless
  the user explicitly asks for that git operation.
- Do not infer a new branch from a new task, stage, bug, finding, or handoff.
- If the user asks for work to continue after another agent finishes, stop
  before implementation until the user gives the next command.
- If branch isolation is needed for safety, propose it with the exact current
  branch, target branch name, and reason, then wait for approval.

## Concurrent Agent Safety

- Check `git status --short` before any file edit, staging operation, commit, or
  push.
- Treat pre-existing dirty files as user-owned or another-agent-owned unless
  the user says otherwise.
- Do not modify, stage, stash, commit, or revert another-owned dirty file.
- If another-owned changes overlap the files required for the task, stop and ask
  how to coordinate before editing.
- If another-owned changes are unrelated, continue with explicit file paths only
  and report the remaining dirty files in the handoff.
- Do not use `git add -A`, `git add .`, or broad pathspecs unless the user
  explicitly asks for that exact operation.

## Constitution Freeze Enforcement

- `ARCHITECTURE_CONSTITUTION.md` was ratified on 2026-09-13 and is frozen. Its
  §18 has no amendment procedure; `RULES.md` owns the rule, this section owns its
  enforcement.
- `scripts/check-constitution-freeze.sh` runs from the versioned `pre-commit`
  hook. It reads the status line from the version before the change: while DRAFT,
  a constitution commit may touch only that file and `MEMORY.md`; once RATIFIED,
  the text is pinned by the SHA-256 seal in
  `scripts/constitution.freeze.sha256`.
- The seal check hashes the staged blob from the git index, not the working tree,
  and compares it with the hash recorded in `HEAD`'s seal. A staged edit is
  refused even when the seal is regenerated in the same commit, and the seal
  itself may not be modified, deleted, or renamed.
- It fails closed: a missing SHA-256 tool, an unreadable status line, or an
  absent or malformed seal blocks the commit.
- The bypass is `SCI_SKIP_CONSTITUTION_FREEZE=1 git commit`. After ratification it
  exists only for the one exception §18 allows — a mechanical repair that touches
  no sentence — and that repair must regenerate the seal in the same commit with
  `shasum -a 256 ARCHITECTURE_CONSTITUTION.md > scripts/constitution.freeze.sha256`.

## Hooks

- Install the versioned hooks with `./scripts/install-git-hooks.sh`; the tracked
  sources live under `scripts/git-hooks/`.
- The hooks are `pre-commit`, `commit-msg`, and `pre-push`. Keep
  `scripts/check-agent-attribution.sh` wired into all three,
  `scripts/check-constitution-freeze.sh` into `pre-commit`, and
  `scripts/check-memory-freshness.sh` into `pre-push`.
- Keep `scripts/check-readme-stewardship.sh` wired into `pre-commit` for staged
  README changes and into `pre-push` for pushed ranges.

## Command Ordering

- Never run dependent git commands in parallel. `git commit` and `git push` are
  always sequential.
- Use parallel tool execution only for independent reads or checks, never for
  state-changing commands that depend on each other.
- `git commit` records the whole index, not only the paths just added. Check
  `git status --short` before committing, or commit explicit paths with
  `git commit -- <paths>`.

## Commit Discipline

- Commit each coherent repository mutation after verification.
- Commit whenever code or documentation is touched, and make sure a completed
  implementation stage ends with a commit.
- Do not commit secrets, tokens, private credentials, or environment files.
- Keep commits atomic: one behavior, contract, policy, or documentation concern
  per commit.
- Stage only the files that belong to the current change.
- Inspect the staged diff before committing.
- Use commit messages that name the behavior, contract, policy, or bug fixed.
- Do not mix implementation work with unrelated notes, scratch files, or
  another agent's changes.
- If a task is intentionally analysis-only, do not create a commit.

## Push Discipline

- Push only when explicitly requested.
- Before pushing, fetch the intended remote, identify the current branch, HEAD
  SHA, configured upstream, intended target, and whether the remote branch
  exists.
- Report the exact `local@sha -> remote/branch` mapping before the push.
- Stop for confirmation if the push would create or recreate a remote branch,
  the upstream is missing, the intended target differs from the current branch,
  or local history diverges from the remote.
- Push with an explicit refspec and verify the remote SHA afterward.
- Never run `git commit` and `git push` in parallel.

## Recovery

- Do not revert existing user changes unless the user explicitly asks.
- Before risky or multi-file changes, surface the dirty working tree and ask
  whether to checkpoint it first. If uncommitted files remain from previous agent
  runs, surface them and offer to commit and push them separately.
- Prefer a new corrective commit for published or shared mistakes.
- Prefer `git revert` for committed mistakes when preserving history matters.
- Use destructive commands such as `git reset --hard`, branch deletion, or
  checkout-over-write only after explicit user authorization.
- Do not use stash as a coordination mechanism for user-owned work unless the
  user asks for it.
