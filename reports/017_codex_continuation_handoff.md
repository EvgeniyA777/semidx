---
title: "Codex Continuation Handoff"
doc_type: "handoff"
lifecycle: "active"
status: "ready"
agent_action: "reference_for_context"
updated: "2026-08-02"
---

# Codex Continuation Handoff

Repo: `/Users/ae/workspaces/semidx`
Branch: `main`
Latest pushed commit at handoff update: `a19986e feat: add bounded relation traversal kernel`
Expected worktree state: clean.

## Mandatory Rules

1. Read `RULES.md` first.
2. Read `docs/code-context.md` before first-pass exploration.
3. Use semidx MCP-first for code exploration:
   `create_index -> repo_map -> resolve_context -> expand_context -> fetch_context_detail`.
4. Use manual file reads only after semidx MCP narrowing or if MCP fails.
5. For Clojure structural edits, use `clojure-mcp` tools when connected. If no
   nREPL is running, start it with `clojure -M:nrepl`, then `list_nrepl_ports`.
6. Repository documentation and rule files must be written in English.
7. After each staged implementation change: verify, update docs/progress, commit, then push.
8. Run `git commit` and `git push` sequentially, never in parallel. Stage explicit paths only.

## Current Program

Plan: `plans/013_open_gaps_closure_program.md`
Progress log: `reports/014_open_gaps_closure_program_progress_log.md`
Operational memory: `MEMORY.md`
Relevant ADRs:

- `adr/034-*`: relation-first fork for interprocedural/dataflow work.
- `adr/037-scope-interprocedural-dataflow-v1.md`.
- `adr/038-make-typed-relations-the-canonical-semantic-graph.md`.
- `adr/039-separate-relation-identity-from-resolution-and-evidence.md`.

## Completed

- Stage 3.2: typed relation substrate and empty snapshot indexes.
- Stage 3.3: Clojure `dataflow/*` producer.
- Stage 3.4: Python `dataflow/*` producer.
- Stage 3.5: relation identity/evidence split and validation hardening (`ADR-039`).
- Stage 3.6: pure bounded relation traversal kernel.

Both Clojure and Python emit top-level snapshot relations:

- `dataflow/local-binding-call-result`
- `dataflow/returns-call-result`
- `dataflow/passes-argument`

`semidx.runtime.index` resolves relation `target_key` values to `target_unit_ids`
and marks relations `resolved`, `ambiguous`, or `unresolved`.

Stage 3.5 (`ADR-039`): `relation_id` now derives only from `relation_type`,
`source_unit_id`, `target_key`, and flow payload (`local_name`/`arg_index`)
scoped by `relation_schema_version`; mutable resolution/evidence are excluded so
resolving or enriching a fact keeps one edge. `relation-errors` is the explicit
internal schema; `index-relations` surfaces invalid facts as snapshot
`:relation_diagnostics` instead of dropping them silently.

Stage 3.6: `semidx.runtime.relations/traverse-relations` is a pure,
storage-independent, cycle-safe, deterministic breadth-first walk over
`:relations` / `:relation_forward_index` / `:relation_reverse_index`. Request
keys: `:direction` (`:downstream` source->target / `:upstream` target->source),
`:start_nodes`, `:relation_types` allow-list, `:resolved_only` (default true so
ambiguous/unresolved edges are skipped), and `:max_depth`/`:max_nodes`/`:max_paths`
clamped into `[0, default-traversal-bounds]` (depth 4 / 200 nodes / 50 paths).
It returns `{:direction :start_nodes :relation_types :budgets :nodes :edges
:paths :truncated}` with per-budget truncation flags. It is internal only: no
consumer is wired to it and no public graph-query API exists yet.

## Next Stage

Implement `plans/013` Stage 3 sub-step 6 (the last coding sub-step of Stage 3):
bounded, reason-coded retrieval/impact projections that consume
`semidx.runtime.relations/traverse-relations`.

- Wire relation-backed support into retrieval and `impact_analysis` as
  reason-coded, low-weight signals. Start conservative; preserve existing
  caller/callee/dependents/related_tests outputs unchanged.
- Consume the kernel; do not write a second graph walk. `build-impact-hints`
  currently reads legacy caller/module/test indexes only.
- Keep ambiguous flows conservative: rely on the kernel's `:resolved_only true`
  default; do not over-link.
- After it lands, recalibrate confidence ceilings only if evidence supports it;
  otherwise document the non-bump (as in prior sub-steps).

Constraints:

- Do not add a public graph-query API in Stage 3 (that is Stage 4).
- Do not migrate or replace existing `calls` / `imports`.
- Keep ambiguous relation-backed flows conservative.
- Do not carry legacy paths forward when a clean new-system implementation is clearer.

Verification focus for this sub-step (extraction/ranking/resolution-adjacent, so
gates matter): `clojure -M:test`, `./scripts/run-benchmarks.sh`,
`./scripts/run-semantic-quality-report.sh` (must show no regression and a
measurable gain on new interprocedural cases), `./scripts/run-mvp-gates.sh`,
`clojure -M:ccc check --root .`. Add mirrored `*-test` coverage and consider
protected replay-case promotion for the hardest new cases.

## Last Known Verification

For commit `a19986e`:

- `clojure -M:test -n semidx.runtime.relations-test` passed (`13 tests / 49 assertions`).
- `clojure -M:test` passed (`252 tests / 1695 assertions`).
- `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
- `./scripts/run-semantic-quality-report.sh` exited `0` with advisory state unchanged
  (`expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`,
  `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`,
  `unmatched_rate=0.0`).
- `./scripts/run-mvp-gates.sh` passed with `mvp_gates=ok`.
- `clojure -M:ccc check --root .` passed.

## Suggested First Prompt

Read `reports/017_codex_continuation_handoff.md`, then continue
`/Users/ae/workspaces/semidx` from the current `main` branch. Follow `RULES.md`,
use semidx MCP-first, and implement the next `plans/013` Stage 3 sub-step:
bounded, reason-coded retrieval/impact projections that consume
`semidx.runtime.relations/traverse-relations`, keeping ambiguous flows
conservative and preserving existing caller/callee outputs, with no public
graph-query API.
