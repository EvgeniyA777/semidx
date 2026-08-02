---
title: "Codex Continuation Handoff"
doc_type: "handoff"
lifecycle: "active"
status: "ready"
agent_action: "reference_for_context"
updated: "2026-08-01"
---

# Codex Continuation Handoff

Repo: `/Users/ae/workspaces/semidx`
Branch: `dev`
Latest pushed commit at handoff creation: `daf105e feat: emit python dataflow relations`
Expected worktree state: clean.

## Mandatory Rules

1. Read `RULES.md` first.
2. Read `docs/code-context.md` before first-pass exploration.
3. Use semidx MCP-first for code exploration:
   `create_index -> repo_map -> resolve_context -> expand_context -> fetch_context_detail`.
4. Use manual file reads only after semidx MCP narrowing or if MCP fails.
5. For Clojure structural edits, use `clojure-mcp` tools when connected.
6. Repository documentation and rule files must be written in English.
7. After each staged implementation change: verify, update docs/progress, commit, then push.
8. Run `git commit` and `git push` sequentially, never in parallel.

## Current Program

Plan: `plans/013_open_gaps_closure_program.md`
Progress log: `reports/014_open_gaps_closure_program_progress_log.md`
Operational memory: `MEMORY.md`
Relevant ADRs:

- `adr/034-*`: relation-first fork for interprocedural/dataflow work.
- `adr/037-scope-interprocedural-dataflow-v1.md`.

## Completed

- Stage 3.2: typed relation substrate and empty snapshot indexes.
- Stage 3.3: Clojure `dataflow/*` producer.
- Stage 3.4: Python `dataflow/*` producer.

Both Clojure and Python now emit top-level snapshot relations:

- `dataflow/local-binding-call-result`
- `dataflow/returns-call-result`
- `dataflow/passes-argument`

`semidx.runtime.index` resolves relation `target_key` values to `target_unit_ids`
and marks relations `resolved`, `ambiguous`, or `unresolved`.

## Next Stage

Superseded ordering note: an earlier draft of this handoff sent the next agent
straight to bounded retrieval/impact projections over the existing relation
indexes. The `Stage 3 Architecture Re-review - 2026-08-01` in
`reports/014_open_gaps_closure_program_progress_log.md` re-sequenced Stage 3.
The traversal kernel and any relation-backed consumers are now blocked on a
prerequisite identity/evidence split.

Continue `plans/013` Stage 3 in this order (matching the re-review Follow-up
Sequence and Stage 3 sub-steps 3-6):

1. Separate semantic relation identity from mutable resolution and evidence.
   The `relation_id` must derive only from relation type, source endpoint,
   semantic target key, and flow payload. Resolution status, resolved target
   IDs, evidence quality, provenance, and evidence location must not create a
   second semantic edge. Record this durable identity/evidence split in the next
   ADR (next free number is `ADR-039`) before changing v1 relation IDs.
2. Replace permissive validation and silent invalid-fact filtering with an
   explicit internal schema plus structured diagnostics.
3. Only then add the pure, storage-independent bounded traversal kernel under
   `runtime.relations` (depth <= 4, <= 200 nodes, <= 50 paths).
4. Then add bounded, reason-coded retrieval/impact projections over the
   traversal kernel.

Constraints:

- Do not add a public graph-query API in Stage 3.
- Do not migrate or replace existing `calls` / `imports`.
- Keep ambiguous relation-backed flows conservative.
- Do not carry legacy paths forward when a clean new-system implementation is clearer.

## Last Known Verification

For commit `daf105e`:

- `clojure -M:test -n semidx.integration.runtime-test` passed.
- `clojure -M:test -n semidx.runtime.relations-test` passed.
- `clojure -M:test` passed.
- `./scripts/run-benchmarks.sh` passed.
- `./scripts/run-semantic-quality-report.sh` exited `0` with advisory state unchanged.
- `./scripts/run-mvp-gates.sh` passed with `mvp_gates=ok`.
- `clojure -M:ccc check --root .` passed.
- `git diff --check` passed.

## Suggested First Prompt

Read `reports/017_codex_continuation_handoff.md`, then continue
`/Users/ae/workspaces/semidx` from the current `dev` branch. Follow `RULES.md`,
use semidx MCP-first, and implement the next `plans/013` Stage 3 sub-step:
the relation identity/evidence split plus schema-hardening diagnostics
(recorded in `ADR-039`), which is the prerequisite for the bounded traversal
kernel and any relation-backed retrieval/impact projections.
