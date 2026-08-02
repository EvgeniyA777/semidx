---
title: "Codex Continuation Handoff"
doc_type: "handoff"
lifecycle: "completed"
status: "consumed"
agent_action: "historical_reference_only"
updated: "2026-08-02"
---

# Codex Continuation Handoff

Repo: `/Users/ae/workspaces/semidx`
Branch: `dev`
Latest pushed commit at handoff update: `f06b956 feat: add relation-backed impact projection`
Branch note: active work continues on `dev`; `main` is intentionally left one
commit behind (`2fcb5ec`) and is fast-forwarded to `dev` manually by the
maintainer. Continue on `dev`.
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
- Stage 3.7: relation-backed impact projection (Stage 3 is now code-complete).

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
:paths :truncated}` with per-budget truncation flags. No public graph-query API
exists yet; its only consumer is the Stage 3.7 projection.

Stage 3.7: `semidx.runtime.retrieval/build-impact-hints` consumes
`traverse-relations` and attaches an optional, reason-coded `:relation_support`
field to `impact_hints` (shared by `impact_analysis`, detail, and expansion
packets). From the selected units it runs the bounded, `:resolved_only true`
kernel under a conservative local sub-ceiling (`relation-projection-bounds`:
depth 2 / 24 nodes / 12 paths) in both directions: `:downstream` dataflow
dependencies and `:upstream` dataflow dependents, as distinct `path::symbol`
strings excluding the selected units, plus `:reasons` codes
(`relation_downstream_dataflow`, `relation_upstream_dataflow`,
`relation_traversal_truncated`). The field is omitted entirely when no resolved
relation-backed unit is found, so legacy
`:callers`/`:dependents`/`:related_tests`/`:risky_neighbors` outputs stay
byte-identical; ambiguous/unresolved relations are never surfaced. The
`context_packet` and `expansion-result` `impact_hints` contracts carry an
optional `relation_support` object (`{downstream, upstream, reasons}`) in both
the JSON schema and the malli mirror. No public graph-query API was added;
confidence ceilings are unchanged (documented non-bump). Stage 3 is code-complete.

## Next Stage

Implement `plans/013` Stage 4: the semantic graph query surface (gap 7). This
productizes the Stage 3 traversal semantics as a bounded public graph-query
surface and adds a PostgreSQL physical projection, without moving graph policy
into storage. Before starting, read `plans/013` Stage 4 in full.

- Specify the public query surface in a new ADR (next available ADR number at
  execution time). Reuse the Stage 3 `traverse-relations` semantics and bounds
  instead of defining a second graph walk.
- Add JSON Schema under `contracts/schemas/` plus a `malli` mirror in
  `src/semidx/contracts/` for the new query request/response.
- Add a `semantic_index_relations` PostgreSQL projection scoped by repository and
  snapshot (source, target, relation-type, evidence indexes) with an explicit
  migration/backfill policy.
- Implement a PostgreSQL execution adapter for the canonical traversal contract
  and prove parity with the pure in-memory kernel. Storage may optimize
  execution but must not own traversal semantics.
- Expose it on the public surfaces only where it fits the staged-retrieval
  contract; keep MCP/library/HTTP/gRPC aligned.

Constraints:

- Storage optimizes execution but must not own traversal policy/semantics; the
  pure kernel stays the source of truth.
- Do not migrate or replace existing `calls` / `imports`.
- Keep ambiguous relation-backed flows conservative (`:resolved_only`).
- Before running PostgreSQL parity tests: detect a running instance -> stop it
  cleanly -> start fresh with the test config -> only then run (`SCI_TEST_POSTGRES_URL`).

Verification focus for Stage 4 (contract + storage surfaces):
`./scripts/validate-contracts.sh`, `clojure -M:test`, in-memory vs PostgreSQL
storage parity tests, `./scripts/run-mvp-gates.sh`, `clojure -M:ccc check --root .`.
Add mirrored `*-test` coverage for the new contract and the storage adapter.

## Last Known Verification

For commit `f06b956` (Stage 3.7):

- `./scripts/validate-contracts.sh` passed (`checked_json_files=61`, `contracts_validation=ok`).
- `clojure -M:test` passed (`256 tests / 1712 assertions`).
- `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
- `./scripts/run-semantic-quality-report.sh` exited `0` with advisory state unchanged
  (`expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`,
  `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`,
  `unmatched_rate=0.0`).
- `./scripts/run-mvp-gates.sh` passed with `mvp_gates=ok`.
- `clojure -M:ccc check --root .` passed.

## Suggested First Prompt

Read `reports/017_codex_continuation_handoff.md`, then continue
`/Users/ae/workspaces/semidx` from the current `dev` branch. Follow `RULES.md`,
use semidx MCP-first, and implement `plans/013` Stage 4: the bounded public
semantic graph-query surface plus a PostgreSQL `semantic_index_relations`
projection. Reuse the Stage 3 `semidx.runtime.relations/traverse-relations`
contract and bounds instead of writing a second graph walk, keep traversal
semantics in the pure kernel (storage only optimizes execution), prove
in-memory vs PostgreSQL parity, add the JSON + malli contract mirror, and record
the decision in a new ADR.
