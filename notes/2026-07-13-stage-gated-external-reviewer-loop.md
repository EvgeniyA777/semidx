---
title: "Stage-gated external reviewer loop"
doc_type: "note"
lifecycle: "concept"
status: "draft"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-07-13"
---

# Stage-gated external reviewer loop

Idea: after each work stage, automatically hand off to a *different* reviewer
agent (Claude subagent, Codex, or Antigravity), let it produce findings, then the
working agent picks them up and triages (accept / reject / defer / fix). This is
the loop we already run manually via `plans/` + `reports/*_progress_log.md`
(see plans 9–12); the note is about automating the trigger.

## Core principle

"Automatically after each stage" is an **event** the harness must fire, not
something the model can reliably self-trigger. In Claude Code that means a
**hook** in `settings.json` (the `update-config` skill is the way to add one).
Inside a single turn the model can spawn a subagent itself, but cross-stage
automation needs a hook.

## Mechanism (three parts)

1. **Trigger = a stage boundary.** Cleanest definition is a per-stage `git commit`
   (how we already work). A `PostToolUse` hook matching `git commit` fires after
   each stage. (`Stop` hook fires every turn — too coarse.) Alternative: an
   explicit `/stage-done` command the working agent calls.
2. **Hand-off packet.** The hook collects a small packet to `.review/incoming.md`:
   the stage diff (`git show HEAD`) + the relevant progress-log excerpt. The
   progress log is already the hand-off artifact.
3. **Run reviewer + return findings.** Hook shells the reviewer in headless mode,
   writes `.review/findings.md`, and returns them into context (hook JSON
   `additionalContext`) or leaves a file the agent must read next turn. The agent
   triages and records outcomes back into the same progress log.

## Reviewer options (honesty about what is known)

- **Claude subagent / `/code-review` / cloud `ultrareview`** — works today, fully
  in-harness, no cross-vendor plumbing. Fastest path for "a second pass per stage".
- **Codex** — has a non-interactive mode (`codex exec …`) suitable for hook use;
  exact flags need verification.
- **Antigravity** — unknown whether it exposes a stable headless CLI for this;
  do NOT assume. Verify before designing it in. See also
  `notes/2026-03-11-antigravity-follow-up.md`.

Cross-vendor review buys genuine independence (a different reviewer does not just
agree with itself) at the cost of file-based plumbing.

## Gotchas to design around

- **Infinite loop**: review → fix → commit → review… needs a max-rounds or a
  "converged" marker in the log.
- **Context size**: pass the diff + log excerpt, never the whole repo.
- **Cost/latency**: a hook that shells an external agent on every commit is slow
  and token-heavy; keep it commit-scoped, not `Stop`-scoped.
- **Stage crispness**: define "stage" explicitly (commit or a `stage N done`
  marker) so the trigger is deterministic.

## Next steps when picked up

1. Verify real headless surfaces (`codex exec --help`; whether Antigravity has a
   CLI) before committing to a vendor.
2. Add the `PostToolUse`/`git commit` hook via `update-config`; put the wrapper
   script under `scripts/` (project-local automation per workspace canon).
3. Start with the Claude-subagent variant as the working baseline; wire an
   external vendor as a second step.
