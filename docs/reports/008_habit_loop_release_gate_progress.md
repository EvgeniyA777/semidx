---
title: "Habit loop release gate progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-17"
---

# 008: Habit Loop Release Gate Progress

Companion log for
[docs/plans/008_habit_loop_release_gate.md](../plans/008_habit_loop_release_gate.md).

## Current Status

Plan 008 is complete. The gate is specified in
[docs/mcp/habit_loop_gate.md](../mcp/habit_loop_gate.md), and
`zig build preview-gate` runs it over the repository-copy and fixture profiles.
Release-candidate evidence, review outcome, residual risks, and the next
recommended release action are recorded below.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Gate specification | Completed (`63129db`) | The required call sequence, fourteen named hard gates, the observations, two profiles, and extension rules are specified in the habit loop gate reference. No behavior change. |
| Stage 2: Gate runner | Completed (`97a07e0`) | `zig build preview-gate` runs the gate. `tests/mcp_gate.zig` checks every tool result's shape, envelope, and budget, tracks the required call sequence, fails named gates with `gate: FAIL [<profile>] <gate>`, and prints the evidence summary. The dogfood habit loop is its `repository-copy` profile. |
| Stage 3: Multi-profile coverage | Completed (`97a07e0`) | `tests/mcp_fixture_gate_test.zig` is the `fixture` profile: a temporary root of seven `fixtures/vertical-slice` files plus one unindexed file, proving facts, unresolved calls, unsupported constructs, a failing unit, and a unit made stale by the edit. |
| Stage 4: Release-candidate evidence packaging | Completed (`035d234`) | The release-candidate command set ran at `97a07e0`; hard results, observations, skipped and failed checks, and residual risks are recorded below. The preview reference, testing policy, and `RULES.md` point at the gate. |
| Stage 5: Gate review and handoff | Completed | `preview-gate` is the one canonical gate and `dogfood` is its repository-copy profile; stale next-step bookkeeping in the roadmap, Plan 009, and `MEMORY.md` is aligned; review found no defect. |

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

## Stage 4: Release-Candidate Evidence

Changed files: `docs/mcp/habit_loop_gate.md` (summary example matched to the
real output, owned terms), `docs/mcp/local_preview.md`,
`docs/agent-policy/testing.md`, `RULES.md`, this log. `README.md` names no
preview proof command, so the plan's conditional README update does not apply.

### Environment

- Commit `97a07e0` on `dev`, 2026-09-17.
- macOS 26.6.2 arm64, Zig 0.16.0, Homebrew tree-sitter 0.26.3, grammar
  sources from `./scripts/setup-tree-sitter-grammars.sh` already present.
- Debug build (the `zig build` default). No network access was used by any
  command below.
- The worktree was not clean: `README.md` carried an uncommitted change made
  outside this plan, which this plan did not touch. No build or test input
  reads `README.md`, and the gate's repository scan copies source units only,
  so the results below hold for `97a07e0`.

### Commands

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Pass; Zig 0.16.0 |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass; 89/89 |
| `zig build test --summary all` | Pass; 206 passed, 1 skipped |
| `zig build test-mcp --summary all` | Pass; 21 passed, 1 skipped |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build preview-gate --summary all` | Pass; 14/14 steps, 6/6 tests; 26 `hard pass` lines, 42 observations |
| `zig-out/bin/semidx-mcp --version` | Pass; stdout `semidx-mcp 0.1.0-preview.2` |
| `./scripts/check-agent-attribution.sh --all` | Pass |
| `git diff --check` | Pass |
| `./scripts/check-memory-freshness.sh` | Fail, not caused by this plan: with no range it compares the worktree with `HEAD`, and the only trigger is the uncommitted `README.md` above. The committed range is checked at closure. |

Skipped: `zig build run -- src` full-output smoke, a Plan 005 release-gate
command. It exercises the developer inspection command, which this plan did not
change, and no release is being prepared.

The skipped test in `test` and `test-mcp` is the dogfood recovery test, which
only `zig build dogfood` (and so `preview-gate`) runs.

### Hard Gates

Both profiles passed every hard gate that applies to them.

| Gate | `repository-copy` | `fixture` |
| --- | --- | --- |
| `call_sequence` | Pass | Pass |
| `result_shape` | Pass (every call) | Pass (every call) |
| `product_version` | Pass; `0.1.0-preview.2` | Pass |
| `semantic_contract_null` | Pass | Pass |
| `parsers_available` | Pass; 3 languages | Pass; 3 languages |
| `diagnostics_visible` | Pass; `unsupported_construct` 167 | Pass; `unsupported_construct` 15, `analysis_failed` 1 |
| `bounded_lists` | Pass; map `limit` 2 returned 2 of 68 files, truncated | Pass; 2 of 7 files, truncated |
| `resolution_visible` | Pass; `scan` calls `scanDir` as a fact and `root_dir.close` as unresolved | Pass; `announce` calls `greet` as a fact and `report` as unresolved |
| `refresh_revision` | Pass; 90 -> 93 | Pass; 9 -> 13 |
| `new_snapshot_observed` | Pass; the added call is visible at 93 | Pass; repaired unit current, broken unit stale at 13 |
| `no_source_text` | Pass; 2 body texts absent | Pass; 4 body texts absent |
| `stream_discipline` | Pass; exit 0, 817,496 stdout bytes | Pass; exit 0, 44,669 stdout bytes |
| `compact_budget` | Pass; map 47%, `health` context 39% | Not applicable |
| `honest_degradation` | Not applicable | Pass |

The rest of `preview-gate` also passed: the evidence-text opt-in proof checked
441 definition evidence texts, none over the bound, and refresh recovery over
68 units rebuilt 28 times over 32 failure points for both one-shot and sticky
failures.

### Observations

Not gates. Debug build, one run, this machine.

| Observation | `repository-copy` | `fixture` |
| --- | ---: | ---: |
| Source units (bytes) | 68 (776,278) | 7 (3,483) plus 1 unindexed file |
| Units current / pending / stale | 65 / 3 / 0 | 6 / 1 / 0 |
| Current facts / unresolved assertions | 2,352 / 2,752 | 87 / 22 |
| Diagnostics: failed / unsupported / confirmed absence | 3 / 167 / 2 | 1 / 15 / 0 |
| First response after start | 434 ms | 24 ms |
| `semidx_health` | 6,683 bytes | 6,651 bytes |
| Compact `semidx_repo_map` | 155,341 bytes (`limit` 1000), 3 ms | 8,749 bytes |
| Full `semidx_repo_map` (`limit` 1000) | 327,270 bytes | |
| `semidx_find_definitions` | 2,051 bytes | 3,577 bytes |
| `semidx_references` by id | 6,785 bytes | 4,357 bytes |
| `semidx_references` `writeString`, `limit` 1000 | 56,928 bytes (23 call facts) | |
| Compact / full `semidx_context` `health`, limit 500 | 60,962 / 153,194 bytes | |
| `semidx_refresh` | 20 ms; 1 changed, 2 analyzed | 4 ms; 2 changed, 2 analyzed |

For Plan 009, which asked this plan to refresh the Plan 007 observations: the
compact whole-repository map is still about 155 KB and grows with the
repository (152,595 bytes over 66 units in Plan 007, 155,341 over 68 now);
`semidx_references` rendering is unchanged at about 57 KB for `writeString`;
budgets remain per list. Nothing here sets a threshold.

### Residual Risks

- **Unsupported languages and constructs.** The gate proves behavior over Java,
  Clojure, and Zig roots within the frontends' declared coverage; it is not a
  language-support claim.
- **No stable semantic contract.** `semantic_contract_version` is `null`; tool
  names and fields may change, and the gate asserts current fields only.
- **No persistence and no HTTP.** The graph is rebuilt on every start; the
  gate covers stdio only.
- **Local-only operation.** The gate proves semidx sends nothing; a hosted MCP
  client may transmit tool results onward, outside semidx's control
  ([Data leaving the server](../mcp/local_preview.md#data-leaving-the-server)).
- **Observations are single-machine.** Timings came from one Debug run on one
  machine and are not comparable across machines or build modes.
- **Profile roots are narrow.** Two roots cannot show behavior on much larger
  or differently shaped repositories.

## Stage 5: Gate Review And Handoff

Changed files: `MEMORY.md`, `docs/design/001_project_roadmap.md`,
`docs/plans/008_habit_loop_release_gate.md`,
`docs/plans/009_mcp_progressive_discovery_and_budgets.md` (frontmatter only),
this log.

### Duplication With Plan 005

The gate extends Plan 005's dogfood work rather than replacing or copying it.
`zig build dogfood` (the Plan 005 habit loop, evidence-text, and recovery
proofs, widened by Plans 006 and 007) is now the `repository-copy` profile, and
`zig build preview-gate` depends on that step instead of re-running its tests
under another name. The Plan 005 release-gate command set lives in historical
release notes and plan documents; it does not conflict with the new gate, and
`docs/agent-policy/testing.md` now says a release candidate records its own
command set, with `preview-gate` as its habit-loop part.

### Stale Instructions

- `docs/agent-policy/testing.md` said "Release gates: No command"; updated in
  Stage 4.
- `docs/design/001_project_roadmap.md` still listed Plans 007 and 008 as next;
  it now names Plan 009 and the gate.
- `docs/plans/009_mcp_progressive_discovery_and_budgets.md` was marked
  `blocked_until_plan_008_completed`; it is now `ready_for_execution`. Its own
  readiness gate still applies before execution.
- `MEMORY.md` named Plan 008 as next; it now names the gate command and Plan
  009, with the observations Plan 009 asked for.
- Historical documents (Plan 005, release notes, follow-up 004) were left
  unchanged.

### Extending The Gate

[Extending The Gate](../mcp/habit_loop_gate.md#extending-the-gate) owns the
rule: a new hard gate only for habit-loop behavior an agent relies on that holds
on every machine meeting the prerequisites, a new profile only for a root that
shows something the existing ones cannot, and never counts or broad benchmarks
as gates. The mechanics are `Gate.require`/`Gate.pass` in `tests/mcp_gate.zig`
and one run step added to `preview-gate` in `build.zig`.

### Review

Self-review of the diff `91ffbb0..035d234` against the plan, the testing
policy, and the specification:

| Item | Disposition |
| --- | --- |
| Every named gate in the specification has a `require` and a `pass` in the runner or a profile, with the same name. | Checked; no finding. |
| `Gate.call` checks the envelope without optional unwraps, but `Gate.refresh` and `Gate.checkHealth` unwrap nested fields of an already shape-checked result, so a missing nested field panics instead of naming a gate. | Accepted as is: the test still fails with a stack trace, and the specification's `result_shape` gate covers only the envelope. |
| `semantic_contract_null` is recorded as passed at health time, before later calls are checked. | Rejected as a defect: every call checks it, and the summary prints only after every call passed. |
| The call-sequence check treats every call after the refresh as `after_refresh`, including a full-detail map. | Accepted: the specification requires a lookup or context call after the refresh, and both profiles make one. |
| The fixture profile's no-source-text list uses short strings (`hello`, `text.len`). | Checked against the passing transcript and the fixture names and designators: none of them is a name, path, or designator. |
| Concurrency: another change committed `README.md` as `e36d7ba` between Stages 3 and 4 on this branch. | No overlap with this plan's files; the new README names no proof command, so the conditional README update still does not apply. |

### Closure Verification

Code is unchanged since the Stage 4 run at `97a07e0` (Stages 4 and 5 touch
documentation only), so the build lanes were not rerun. Run on the final tree:

- `./scripts/check-agent-attribution.sh --all`: pass.
- `./scripts/check-memory-freshness.sh --range 91ffbb0..HEAD`: pass (the range
  updates `MEMORY.md`).
- `git diff --check`: pass. `wc -l RULES.md`: 170, within the 200-line budget.

Drift check at closure: `GLOSSARY.md` terms (`habit loop`, `release gate`,
`release candidate`) are used as defined; the gate reference owns `hard gate`,
`observation`, and `gate profile`. `SPEC.md`, `CORE.md`, `CONFORMANCE.md`, and
the constitution are unaffected: no semantics, contract, core kind, persistence,
or remote operation was added.

### Next Recommended Release Action

Do not cut a preview for this plan: it changed tests, the build graph, and
documentation, not `semidx-mcp` behavior, so `0.1.0-preview.2` still describes
the binary. Execute Plan 009 next, and make `zig build preview-gate` part of the
release gate of the next preview that changes MCP behavior.
