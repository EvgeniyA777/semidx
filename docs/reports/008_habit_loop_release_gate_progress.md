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

Stages 1 to 3 are complete: the gate is specified in
[docs/mcp/habit_loop_gate.md](../mcp/habit_loop_gate.md), and
`zig build preview-gate` runs it over the repository-copy and fixture profiles.
Stages 4 and 5 are pending.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Gate specification | Completed (`63129db`) | The required call sequence, fourteen named hard gates, the observations, two profiles, and extension rules are specified in the habit loop gate reference. No behavior change. |
| Stage 2: Gate runner | Completed | `zig build preview-gate` runs the gate. `tests/mcp_gate.zig` checks every tool result's shape, envelope, and budget, tracks the required call sequence, fails named gates with `gate: FAIL [<profile>] <gate>`, and prints the evidence summary. The dogfood habit loop is its `repository-copy` profile. |
| Stage 3: Multi-profile coverage | Completed | `tests/mcp_fixture_gate_test.zig` is the `fixture` profile: a temporary root of seven `fixtures/vertical-slice` files plus one unindexed file, proving facts, unresolved calls, unsupported constructs, a failing unit, and a unit made stale by the edit. |
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

## Stages 2 And 3: Gate Runner And Multi-Profile Coverage

Implemented together: the runner's sequence and summary are only testable with
a profile that uses them, and the fixture profile is the second user of the
runner. Changed files: `build.zig`, `tests/mcp_gate.zig` (new),
`tests/mcp_dogfood_test.zig`, `tests/mcp_fixture_gate_test.zig` (new), this
log.

- **`build.zig`**: a `preview-gate` step depends on the `dogfood` step and on a
  new fixture-profile test run. Every run is marked `has_side_effects`, so the
  cache never skips reading the repository or fixtures.
- **`tests/mcp_gate.zig`**: `Gate.call` writes the request itself and parses
  the response without optional unwraps, so a malformed result fails
  `result_shape` by name instead of panicking. Timeouts and killing a hung
  child stay in `mcp_stdio_client.zig`, unchanged.
- **`tests/mcp_dogfood_test.zig`**: the habit loop test runs through the gate.
  Its Plan 006 and Plan 007 assertions are kept; the budget ratios became the
  named `compact_budget` gate; a `semidx_repo_map` with `limit` 2 proves
  truncation is reported. The evidence-text test calls the client directly.
- **`tests/mcp_fixture_gate_test.zig`**: behavior was probed against the built
  server before it was pinned: an unparsable file at startup is analysis
  `pending` with one `analysis_failed` diagnostic and no definitions; `.py`
  files are not units; after an edit makes `greeter.zig` unparsable, default
  lookups return none of its definitions, `freshness: "any"` returns them
  `stale` under the same entity ids, and its unit reports analysis `stale`.

### Verification

Zig 0.16.0 (`./scripts/check-zig-version.sh`), Debug build, 2026-09-17.

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build preview-gate --summary all` | Pass; 14/14 steps, 6/6 tests; both evidence summaries printed |
| `zig build dogfood --summary all` | Pass; 10/10 steps, 5/5 tests |
| `zig build test-mcp --summary all` | Pass; 21 passed, 1 skipped (the dogfood recovery test, run by `dogfood`) |
| `zig build test --summary all` | Pass; 206 passed, 1 skipped (same test) |
| Mutation: `announce` added to the fixture profile's forbidden body texts | Gate fails as intended: `gate: FAIL [fixture] no_source_text: the transcript contains source text \`announce\``, 5/6 tests, exit 1. Mutation reverted. |
| `git status --short` after the gate | Only this change's files; the gate edited nothing in the repository or `fixtures/` |

The Zig build runner prints each test's stderr under a `failed command:` line
even when the test passes; the build summary and exit status are the result.

Not run: mutations for the other named gates. Each is a single `require` over
a value the passing run printed, and the one mutation run proves failures are
named and fail the step.
