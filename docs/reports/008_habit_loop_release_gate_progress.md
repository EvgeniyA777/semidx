---
title: "Habit loop release gate progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# 008: Habit Loop Release Gate Progress

Companion log for
[docs/plans/008_habit_loop_release_gate.md](../plans/008_habit_loop_release_gate.md).

## Current Status

Stage 1 is complete: the gate is specified in
[docs/mcp/habit_loop_gate.md](../mcp/habit_loop_gate.md). Stages 2 to 5 are
pending.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Gate specification | Completed | The required call sequence, fourteen named hard gates, the observations, two profiles, and extension rules are specified in the habit loop gate reference. No behavior change. |
| Stage 2: Gate runner | Pending | |
| Stage 3: Multi-profile coverage | Pending | |
| Stage 4: Release-candidate evidence packaging | Pending | |
| Stage 5: Gate review and handoff | Pending | |

## Plan Readiness Gate

Applied on 2026-09-17 before Stage 1. Plans 006 and 007 are completed
(`lifecycle: completed`), so the start rule holds. Scope, non-scope, stage
order, verification commands, and DoD are explicit; no hard fail.

The plan leaves shape choices to the executor. They are decided here so later
stages do not guess:

- **Command: a new `zig build preview-gate` step.** It runs everything
  `zig build dogfood` runs (the repository-copy habit loop, the evidence-text
  opt-in proof, and refresh failure-injection recovery) plus the new fixture
  profile. `zig build dogfood` stays as the repository-copy profile alone, so
  the two commands do not compete: `preview-gate` is the canonical gate and
  `dogfood` is one of its profiles. Renaming `dogfood` into the gate would have
  put a controlled fixture root under a name that means "this repository".
- **The gate specification is a separate reference**,
  `docs/mcp/habit_loop_gate.md`: `docs/mcp/local_preview.md` is already over
  400 lines and describes using the preview, not verifying it.
- **The fixture profile copies existing `fixtures/vertical-slice` files into a
  temporary root** instead of adding new fixture files. Those files already
  have known facts, unresolved calls, unsupported constructs, and an unparsable
  edit variant, and their expectations are pinned by existing tests.
- **Hard gates print named failures.** The gate runner reports
  `gate: FAIL [<profile>] <gate>: <detail>` for the named gates; the
  pre-existing semantic assertions of the dogfood test keep their own failure
  output rather than being rewritten.
- **Latency and size stay observations**, except the 30 s hang bound and the
  Plan 007 compact-to-full ratio, which is already a hard gate and stable
  because it compares two renderings of one snapshot.

Drift check: `GLOSSARY.md` already owns `habit loop`, `release gate`, and
`release candidate`; `CONFORMANCE.md`, `SPEC.md`, and the constitution need no
change because the gate adds no semantics, contract, or core kind. Documents
to align at closure: `docs/agent-policy/testing.md` (lane table),
`docs/mcp/local_preview.md`, `RULES.md` project context commands, `MEMORY.md`.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| The habit loop works end to end over stdio | A required call is skipped or reads a stale snapshot, and the gate still passes | Runtime smoke over the built executable | `call_sequence`, `refresh_revision`, `new_snapshot_observed` | Post-refresh call on the old revision | Both profiles |
| Results are well formed and bounded | A malformed or unbounded result passes unnoticed | Runtime smoke | `result_shape`, `bounded_lists` | A call that hits its limit must say `truncated` | Both profiles |
| No source text by default | A rendering path leaks body text | Runtime smoke transcript scan | `no_source_text` | Body text present in the root and added by the edit | Both profiles; evidence-text opt-in proof stays |
| Honest degradation | A failed or stale unit is presented as current, or an unindexed file as a unit | Runtime smoke over a controlled root | `honest_degradation`, `diagnostics_visible` | Unit made unparsable by the edit; unit unparsable from the start; file with no frontend | Fixture profile |
| Resolution stays visible | An unresolved call reads like a fact | Runtime smoke | `resolution_visible` | Known unresolvable designator | Both profiles |
| Stream and exit discipline | Late stdout, non-zero exit, or hang passes | Runtime smoke | `stream_discipline`, 30 s timeouts | Server that hangs is killed | Both profiles, `mcp_stdio_client.zig` |
| Gate is local and non-mutating | The gate edits the repository or needs a network | Build step review plus temporary roots | `build.zig` step, `testing.tmpDir` | Repository and `fixtures/` unchanged after the run | `git status` after the gate |

## Stage 1: Gate Specification

Changed files: `docs/mcp/habit_loop_gate.md` (new), this log.

The specification names the required call sequence, the hard gates with the
names printed on failure, the observations, the two profiles, the evidence
summary format, what the gate does not prove, and how to extend it.

Verification: documentation only; read back against the plan's Stage 1
required behavior (call sequence, the eight required assertions, hard gates
separated from observations). No build or test lane is affected.
