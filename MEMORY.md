# Project Memory

## Purpose

This file stores lightweight operational memory for the project:

- current implementation reality
- key non-ADR decisions
- active assumptions and constraints
- near-term next steps

Use this as a fast session bootstrap before deep-diving into ADRs and code.

For Codex continuation handoff, read
[`reports/017_codex_continuation_handoff.md`](reports/017_codex_continuation_handoff.md)
after this memory file.

## Current State

- Contract layer is established (`contracts/schemas`, `contracts/examples`, `fixtures/retrieval`).
- Clojure-side contract mirror is implemented with `malli`.
- MVP runtime is implemented with public API in `semidx.core`.
- Clojure parser path supports `clj-kondo` primary with regex fallback and optional tree-sitter extraction mode.
- Clojure fallback parsing now rewrites alias-qualified calls (`order/validate-order` -> `my.app.order/validate-order`), ignores nested defs inside wrapper forms such as `comment`, links test namespaces back to source namespaces for stronger `related_tests` hints including one helper-namespace hop inside `test/`, emits dispatch-aware `defmethod` unit identities, can rank the correct multimethod implementation from dispatch hints in the query text, and adds recursive graph-level inherited caller edges for custom macros across syntax-quote, list-built, local-helper-generated, top-level-helper-generated, and common composed expansions without leaking plain macro helper functions or unioning conflicting branch-only generated calls.
- Java parser path supports regex mode and optional tree-sitter extraction mode.
- Elixir/Python parser paths are regex-based with class/module-aware symbol and call normalization.
- TypeScript parser supports regex mode and optional tree-sitter extraction mode.
- Elixir parser now supports alias-aware call token expansion (`alias Foo.Bar, as: Baz` -> `Baz.fn()` -> `Foo.Bar.fn` token).
- Elixir extraction now distinguishes form operators (`def`, `defp`, `defmacro`, `defdelegate`) and uses `do/end` balancing for tighter unit boundaries.
- Elixir alias parsing now covers brace aliases and alias-chains (`alias Foo.{Bar,Baz}`, nested alias prefixes, `as:` single-target overrides).
- Elixir semantic-core now also expands unqualified imported calls toward imported modules, propagates implicit imports emitted by `__using__/1`, records per-function arity for same-name identities, prefers same-module local definitions over imported or `use`-expanded collisions with arity awareness, links `defdelegate` units to delegated targets, and surfaces ExUnit test-file linkage through `related_tests`.
- Java semantic-core now uses arity-aware overload resolution for caller/callee linking, handles static-import/class ownership more accurately when matching method calls, suppresses false same-name edges on qualified/static-import collisions, and keeps explicit `this.` / `super.` calls local to the caller class.
- Python semantic-core now expands imported symbols, relative imports, and module aliases toward owning modules, rewrites `self`/`cls` calls toward class-owned methods, preserves explicit module-alias ownership under same-name collisions, supports local class-qualified ownership (for example `OrderService.handle(...)`), and surfaces Python test-file linkage through `related_tests`.
- TypeScript semantic-core now expands named, namespace, and default-import ownership toward the right module targets, keeps `this.` and local class-qualified calls attached to their owning class methods, and emits first-class units for exported function-expression bindings in both runtime and onboarding coverage.
- Retrieval uses structural-first tiered scoring with non-compensating confidence ceilings.
- Raw-code escalation stage is implemented (opt-in, late, bounded by query constraints).
- Semantic resolution includes import-aware and owner-aware call target disambiguation.
- Optional persistence adapters exist: in-memory and PostgreSQL (snapshots + unit/call-edge projections + query API).
- Retrieval benchmark suite exists and is integrated into gates (`scripts/run-benchmarks.sh`).
- Retrieval fixtures/benchmarks now include multi-language ambiguity scenarios (Python, Java, Elixir).
- Retrieval fixtures/benchmarks now include TypeScript baseline and ambiguity onboarding scenarios.
- Postgres integration smoke exists in tests (enabled by `SEMIDX_TEST_POSTGRES_URL`) and CI service job.
- Reproducible tree-sitter grammar bootstrap script exists (`scripts/setup-tree-sitter-grammars.sh`) with pinned grammar refs (Clojure/Elixir/Java/TypeScript) and a repo-managed CLI link at `.tree-sitter-grammars/bin/tree-sitter` when an executable source is available.
- CI runtime gates now install tree-sitter CLI + grammars before running tests.
- Minimal HTTP runtime edge exists (`clojure -M:runtime-http`) and boundary ADR is documented (`ADR-018`).
- HTTP boundary conformance tests exist and run in standard `clojure -M:test` gates (`semidx.runtime-http-test`).
- Minimal gRPC runtime edge exists (`clojure -M:runtime-grpc`) with parity tests in standard `clojure -M:test` gates (`semidx.runtime-grpc-test`).
- Service-mode policy boundary is documented in `ADR-019` and implemented as optional API-key + tenant gate on HTTP/gRPC edges.
- gRPC transport now uses dedicated runtime protobuf envelope messages defined in `proto/semidx/runtime/grpc/v1/runtime.proto`.
- Host-integrated authz policy contract is implemented on HTTP/gRPC edges via `:authz_check` callback and optional EDN policy adapter (`--authz-policy-file`, `ADR-021`).
- Language onboarding automation scripts now scaffold and validate adapter integration steps (`scripts/new-language-adapter.sh`, `scripts/validate-language-onboarding.sh`, `ADR-022`).
- Java method unit identities are signature/arity-sensitive (`...$arityN$sigXXXX`) to disambiguate overloads.
- Offline policy governance now supports registry lifecycle states (`draft`, `shadow`, `active`, `retired`), replay scorecards, side-by-side policy comparison, and promotion gates via `clojure -M:eval`.
- Replay datasets can now mark `protected_case` queries, and promotion gates reject candidate policies that introduce newly failed protected cases.
- Shadow-vs-active operational workflow now exists via `shadow-review`, which evaluates all `shadow` policies against the current `active` registry policy and can persist `:shadow_review` metadata back into the registry.
- Promotion governance now includes policy-level approval tiers and allow/block auto-promotion constraints, and direct `promote-policy` enforcement now requires explicit manual approval for `manual_approval_required` policies while still refusing `blocked` policies and replay-gate regressions.
- Capabilities are now language-strength-aware: retrieval emits `:selected_language_strengths` plus a derived `:confidence_ceiling`, final confidence is capped by that ceiling after raw-fetch upgrades, guardrails surface `capability_ceiling` signals, and governed replay scorecards include `confidence_ceiling_distribution`.
- HTTP/gRPC health endpoints and MCP initialization now expose a versioned capabilities contract (`contracts/schemas/capabilities.schema.json`) detailing language coverage and confidence ceilings.
- Index lifecycle now emits `:index_lifecycle` metadata with TTL-aware stale detection, snapshot provenance, snapshot pinning on the library/storage path, and rebuild reasons; `resolve-context` surfaces stale snapshot state through capabilities and guardrails via `stale_index`.
- Error handling is now taxonomy-backed across library, HTTP, gRPC, and MCP: normalized `ExceptionInfo` ex-data carries `:error_code` / `:error_category`, HTTP responses emit the same fields, gRPC emits them in trailers (`x-sci-error-code`, `x-sci-error-category`), and MCP tool errors expose them in `structuredContent.details`.
- Clojure semantic-core now also traces macro-generated ownership through direct threading macros such as `->`, `->>`, `some->`, and `some->>` when they emit real call targets, while keeping ambiguous threaded branches conservative instead of over-linking both sides.
- Java semantic-core now also emits constructor units and resolves `new ClassName(...)` caller edges arity-sensitively, so constructor targeting is no longer collapsed into method-only matching.
- Elixir semantic-core now also expands `__MODULE__.foo(...)` to the owning local module, which closes another common collision path where imported or `use`-expanded helpers previously competed with explicit local-module qualification.
- Usage metrics now support SLO-facing rollups through `slo-report`, covering index latency, retrieval latency, cache hit ratio, degraded rate, fallback rate, and policy version distribution for both in-memory and PostgreSQL-backed sinks.
- HTTP/gRPC operational consistency is now tighter: both surfaces accept tenant/correlation metadata (`x-tenant-id`, `x-trace-id`, `x-request-id`, `x-session-id`, `x-task-id`, `x-actor-id`), feed that context into normalized usage events, and preserve correlation markers back to callers (`x-sci-*` headers for HTTP, `x-sci-*` trailers on gRPC errors).
- Phase 5 now includes a closed-loop governance cadence: `resolve_context` usage events retain query/outcome snapshots, `harvest-replay-dataset` can build replay corpora automatically from usage metrics plus structured feedback, difficult cases are promoted into harvested `protected_case` entries, `calibration-report` measures confidence calibration against real feedback outcomes, `weekly-review-report` emits linked `query -> selected context -> feedback -> outcome` artifacts, those review artifacts can be converted back into protected replay datasets for governance, `policy-review-pipeline` can bundle weekly review generation plus registry-backed `shadow-review`, `scheduled-policy-review` can persist timestamped review bundles with manifest-driven review windows and retention, `scheduled-governance-cycle` can retain promotion decisions, emit deterministic `candidate_ranking`, and auto-promote either a single eligible shadow policy or a best-ranked candidate when explicitly allowed, with optional history-aware selection plus `required_candidate_streak_runs` and `promotion_cooldown_runs`, and `governance-history-report` can summarize promoted/skipped trends across retained governance runs.
- `scheduled-policy-review` now also retains standalone `weekly-review-*`, `protected-replay-dataset-*`, and `shadow-review-*` artifacts alongside each bundle and records direct manifest pointers to the latest copies, so Phase 5 review outputs can be reused without reopening the aggregate bundle first.
- Phase 5 orchestration now also maintains retained review/governance indexes plus derived `phase5-review-queue` and `phase5-status-report` outputs, so operators can see pending review work and recent loop state without scanning raw retained artifacts by hand.
- Phase 5 now also has a top-level retained orchestration command, `scheduled-phase5-cycle`, which snapshots the current governance run, queue state, and aggregate status into one first-class artifact stream plus `phase5-run-index.json`.
- Canonical in-repo roadmap status checklist now lives in `docs/roadmap-status.md`, with a dated rationale and status snapshot stored under `notes/`.
- Versioned git hook sources now live under `scripts/git-hooks/`, with `scripts/install-git-hooks.sh` installing the tracked pre-push hook into `.git/hooks`.
- Pre-push freshness now has two gates: CCC refresh/check for `docs/code-context.md`, and a `MEMORY.md` freshness check that blocks high-signal project changes unless project memory is updated or explicitly bypassed with `SCI_SKIP_MEMORY_FRESHNESS=1`.
- Agent REPL support is repo-local: `deps.edn` provides the canonical `:nrepl` alias for clojure-mcp sessions (`clojure -M:nrepl`), binding to `127.0.0.1`, selecting an available port, and writing the ignored `.nrepl-port` file for discovery.
- The project test runner now supports focused namespace selection through `clojure -M:test -n <namespace>` / `--namespace <namespace>` while preserving full auto-discovery when no selectors are supplied.
- Runnable contract query examples are intentionally unpinned: they omit `constraints.snapshot_id` so `clojure -M:runtime --query contracts/examples/queries/*.json` and `scripts/run-mvp-gates.sh` can resolve them against the current worktree index while stricter snapshot-bound continuation checks remain enforced elsewhere.
- Product roadmap progress is now effectively through the main Phase 5 slices: governed quality loop, language-priority semantic-core deepening, capabilities/calibration, index lifecycle, unified error taxonomy, SLO-facing metrics, tenant/trace consistency, governance-tier enforcement, and retained self-improvement orchestration are in place; the next major tranche is post-roadmap deeper compiler-grade semantic follow-up.
- The post-roadmap semantic deepening tranche tracked in `plans/003_post_roadmap_semantic_deepening_plan.md` is now fully delivered across Stages 1-8.
- A dated architecture review note capturing vertical/horizontal findings plus meta-architect critique now lives in `notes/2026-03-11-architecture-review.md`; the main takeaways are TypeScript parser-mode drift, one local re-export line-mapping defect, Python nested-scope suppression coarseness, Java direct-super-only inheritance narrowing, and the broader need to split `runtime/adapters.clj` before the next major semantic tranche.

## Hard Invariants

- JSON Schema is the external contract source of truth.
- `malli` is a runtime mirror, not a competing source of truth.
- `runtime/language_registry.clj` is the single source of truth for language semantic strength.
- Documentation lifecycle is explicit: current work uses active/accepted
  lifecycle plus `reference_for_context`; completed, archived, and superseded
  documents are historical, and document-type status values follow `RULES.md`.
- Outputs must remain bounded and contract-valid (`context_packet`, diagnostics, guardrails, events).
- If limits are exhausted, stop immediately and wait for explicit user instruction.
- Before any service-backed tests (PostgreSQL or other servers): detect running instance -> shutdown if running -> start fresh with required config -> only then run tests.

## Known Gaps

- No full compiler-grade interprocedural semantic resolution across all supported languages yet.
- Stage 5.1 is complete under ADR-042: `runtime.proto` now carries all 16 envelope
  messages and all eight unary RPCs, and the repo-managed generated-Java
  toolchain contract is accepted. Runtime message classes are still
  descriptor-built until the remaining Stage 5 build, parity, and cutover
  slices wire the generated stubs.
- No dynamic external policy backend integration yet (current authz adapter is local file/callback based).
- HTTP/gRPC/MCP surfaces now support server-configured registries and selector-based `resolve_context` policy lookup, but broader online policy-management/control-plane APIs are still intentionally absent.
- Rate limiting is delegated to ingress/proxy/host layer and not implemented in runtime edges.
- Tree-sitter remains an optional process-backed acceleration path; regex parsing is the guaranteed default, and CLI resolution now prefers explicit parser opts, environment configuration, and the repo-managed bootstrap link before falling back to ambient `PATH` for developer machines.
- The semantic graph query surface (gap 7) is delivered as a bounded relation-traversal surface, not a general-purpose graph-query language (deliberate, ADR-040): the Stage 3 kernel is exposed on library + MCP (`traverse_relations`) and executable over a forward-only PostgreSQL `semantic_index_relations` projection at parity with the pure kernel. It is now exposed on all four surfaces: library, MCP (`traverse_relations`), HTTP (`POST /v1/retrieval/traverse-relations`), and gRPC (`TraverseRelations`), all reusing the one kernel/contract.
- Phase 3 roadmap closure is now complete across Clojure, Elixir, Java, Python, and TypeScript; remaining semantic work is post-roadmap deepening rather than an open roadmap tail.
- Clojure fallback/tree-sitter call extraction now suppresses false same-name global edges when calls are actually owned by local params, destructured bindings, `when-let` locals, comprehension bindings, `as->` locals, or `letfn` helper names.
- Clojure multimethod/protocol handling now also emits literal dispatch-aware call tokens for `defmulti`/`defmethod` targeting and first-class `defprotocol` method units, while keeping generic multimethod calls from over-linking every implementation.
- Java semantic-core now also carries direct superclass metadata plus method-reference call tokens, so resolver narrowing can keep `super.` calls, inherited unqualified subclass calls, lambda-owned inherited calls, and `super::method` references attached to the parent implementation instead of same-name overrides.
- Python semantic-core now also preserves decorated `@classmethod` / `@staticmethod` ownership while suppressing nested local def/class over-linking and keeping plain `@property` access conservative instead of turning attribute reads into synthetic call edges.
- Elixir semantic-core now also treats pipeline calls and local captures (`&normalize/1`) as arity-aware caller edges and has regression coverage for `__MODULE__.Nested.foo(...)` nested-module linkage without regressing local-vs-import precedence.
- TypeScript semantic-core now also emits object-literal methods, class field arrow methods, `export default foo` aliases, and direct re-export alias units in both runtime and onboarding coverage while still keeping the public confidence ceiling conservative.
- Confidence recalibration pass kept the public ceilings unchanged: Clojure stays `high`, Elixir/Java/Python stay `medium`, and TypeScript stays `low`, with runtime/docs/tests now explicitly aligned on that non-bump.
- The next frontier after the delivered post-roadmap tranche is the ADR-037 Stage 3 relation-first interprocedural/dataflow v1 slice. ADR-038 makes typed relation facts and snapshot indexes the canonical graph for all new graph semantics; Semantic IR remains extraction-only, while legacy calls/imports stay compatibility projections until a parity-gated migration.
- Runtime hardening is now effectively complete for the main roadmap scope; any remaining ops work is incremental polish rather than a missing Phase 4 primitive.
- Real self-improvement loop is now operationally complete for the current roadmap scope: replay harvesting, difficult-case capture, calibration reports, weekly review artifacts, protected replay dataset conversion, retained review/governance runs, queue/status reporting, and top-level retained Phase 5 orchestration all exist.
- Compact-first staged retrieval is now fully aligned as the canonical public flow: `resolve_context` is compact-first, `expand_context` / `fetch_context_detail` are the explicit later stages, selection artifacts are snapshot-bound, and the implementation/docs/examples line is captured by `ADR-024` plus the completed `plans/002_compact_first_staged_retrieval_plan.md`.
- Dedicated `impact_analysis` now computes impact hints directly from the resolved selection artifact instead of reading `expand_context`'s budget-gated `:impact_hints` field; it must return a non-null map with `:callers`, `:dependents`, `:related_tests`, and `:risky_neighbors` vectors even when `expand_context` omits impact hints for token-budget reasons.
- MCP `create_index` handles are workspace-root isolated: stale cache entries whose entry `:root_path` does not match the embedded index `:root_path`, or whose cache key points at a different requested root, are discarded instead of being reused; a storage-loaded index with an unexpected root is rebuilt for the requested canonical root.
- Intent-only retrieval with `include_tests` now has a test-aware lexical path: file paths participate in lexical matching, `src/test/...` is classified as test code before generic `src/` source code, and `focus_on_tests` boosts already-matched test units without broadening to unrelated tests.
- Retrieval benchmark baselines are aligned with current runtime behavior again: the synthetic benchmark repo includes JavaScript, HTML, and CSS paths used by fixtures, public context-packet unit kinds are normalized to the contract enum, and fixture confidence expectations follow the current per-language capability ceilings.
- Language adapter extraction has moved the Clojure, Java, Python, Lua, TypeScript, and JavaScript lanes out of `semidx.runtime.adapters`: `semidx.runtime.languages.clojure/parse-file` owns Clojure regex, clj-kondo, and optional tree-sitter parsing; `semidx.runtime.languages.java/parse-file` owns Java regex and optional tree-sitter parsing, including overload, constructor, static-import, superclass, and method-reference call extraction; `semidx.runtime.languages.python/parse-file` owns Python module/import/call extraction, class/method ownership, relative imports, test linkage, and nested-scope suppression; `semidx.runtime.languages.lua/parse-file` owns Lua module/import/call extraction, table/method ownership, module return-owner detection, local call suppression, and test linkage; `semidx.runtime.languages.typescript/parse-file` owns TypeScript regex and optional tree-sitter parsing, and `semidx.runtime.languages.javascript/parse-file` owns JavaScript dispatch via the TypeScript lane with JavaScript language tagging. `adapters/parse-file` dispatches directly to those lane namespaces without legacy adapter facades or a legacy TypeScript fallback block. `semidx.runtime.languages.shared` owns generic line/signature/token and tree-sitter CLI/config/CST helpers for language lane implementations.
- ADR-036 Stage 2 is implemented: shared tree-sitter helpers resolve the CLI through `:tree_sitter_cli_path` / `:tree-sitter-cli-path`, `SEMIDX_TREE_SITTER_CLI_PATH`, the repo-managed `.tree-sitter-grammars/bin/tree-sitter` link, then ambient `PATH` only as a developer fallback. Availability is cached per resolved CLI path, language lanes pass parser opts through probe/CST calls, and the bootstrap script can write CLI plus grammar env vars for smoke runs.
- ADR-037 scopes `plans/013` Stage 3: add a typed-relation schema/index boundary first, emit only new `dataflow/local-binding-call-result`, `dataflow/returns-call-result`, and `dataflow/passes-argument` facts as relations, ship Clojure then Python producers, and expose relation-backed gains only through bounded retrieval/impact projections without migrating existing `calls`/`imports` or adding a broad graph query API. ADR-038 establishes that this is the canonical graph boundary for all future providers and graph semantics.
- Stage 3 relation substrate plus the Clojure and Python producers are implemented: `semidx.runtime.relations` owns relation normalization, deterministic IDs, schema versioning, and forward/reverse indexes; Clojure and Python parsing now emit `dataflow/local-binding-call-result`, `dataflow/returns-call-result`, and `dataflow/passes-argument` facts into top-level snapshot relations; `semidx.runtime.index` resolves relation `target_key` values to `target_unit_ids` during index construction without changing existing caller/callee retrieval behavior.
- ADR-039 separates relation identity from mutable resolution/evidence and hardens validation: `relation-id-input` (hence `relation_id`) derives only from `relation_type`, `source_unit_id`, `target_key`, and flow payload (`local_name`/`arg_index`) scoped by schema version, so resolving an unresolved fact or attaching richer evidence enriches one edge instead of minting a new one. `relation-errors` is the explicit internal schema (known `relation-types`/`resolution-statuses`/`evidence-qualities`, resolved-requires-targets, evidence-shape checks); `normalize-relations-with-diagnostics` and `index-relations` surface invalid facts as snapshot `:relation_diagnostics` instead of silently dropping them. `valid-relation?` is now an empty `relation-errors`.
- `semidx.runtime.relations/traverse-relations` is a pure, storage-independent bounded traversal kernel over the relation indexes. Requests specify `:direction` (`:downstream`/`:upstream`), `:start_nodes`, a `:relation_types` allow-list, `:resolved_only` (default true, so ambiguous/unresolved edges are skipped), and `:max_depth`/`:max_nodes`/`:max_paths` clamped to `default-traversal-bounds` (depth 4 / 200 nodes / 50 paths). It is breadth-first, cycle-safe (each node discovered once at its shortest depth), deterministic regardless of set iteration order, and returns `{:nodes :edges :paths :truncated :budgets ...}`. It is internal only and no public graph-query API is exposed in Stage 3; its only consumer is the relation-backed impact projection below. Stage 4 refactored the kernel onto a batched frontier seam: `traverse-relations-with` runs the level-by-level BFS and calls a provider `(fn [frontier-nodes direction] -> {node -> relations})` once per depth level so an execution backend can batch neighbor lookups (no N+1), while all eligibility/fan-out/ordering/cycle/budget policy stays in the kernel; `traverse-relations` is now the thin `in-memory-neighbor-provider` wrapper and its output is byte-identical (parity test in `relations-test`).
- Stage 3 relation-backed impact projections are delivered: `semidx.runtime.retrieval/build-impact-hints` now also consumes `traverse-relations` to attach an optional, reason-coded `:relation_support` field to `impact_hints` (shared by `impact_analysis`, detail, and expansion packets). From the selected units it runs the bounded, `:resolved_only true` kernel under a conservative sub-ceiling (`relation-projection-bounds`: depth 2 / 24 nodes / 12 paths) in both directions: `:downstream` dataflow dependencies and `:upstream` dataflow dependents, returned as distinct `path::symbol` strings excluding the selected units, plus `:reasons` codes (`relation_downstream_dataflow`, `relation_upstream_dataflow`, `relation_traversal_truncated`). The field is omitted entirely when no resolved relation-backed unit is found, so the legacy `:callers`/`:dependents`/`:related_tests`/`:risky_neighbors` outputs stay byte-identical; ambiguous and unresolved relations are never surfaced. The `context_packet` and `expansion-result` `impact_hints` contracts now carry an optional `relation_support` object (`{downstream, upstream, reasons}`) in both the JSON schema and the malli mirror. Confidence ceilings are unchanged (documented non-bump: the projection is additive low-weight support, not a ranking/resolution change).
- ADR-040 fixes the Stage 4 public relation-traversal contract: there is one
  bounded graph walk owned by the Stage 3 kernel; Stage 4 exposes library + MCP
  first, reports HTTP/gRPC as `not_exposed`, and lets PostgreSQL optimize batched
  frontier lookup without owning traversal semantics. The JSON schemas, examples,
  catalog mappings, and malli mirrors for the request/result contract are
  delivered. The batched frontier provider seam in the kernel
  (`traverse-relations-with` / `in-memory-neighbor-provider`) is delivered with a
  proven parity checkpoint. The public library + MCP surface is delivered:
  `semidx.core/relation-traversal` (usage-metrics-wrapped) and
  `semidx.runtime.retrieval/relation-traversal` run the kernel on a loaded
  snapshot, return the compact contract result, and build a stored selection over
  the discovered units so the existing `expand_context` / `fetch_context_detail`
  flow delivers code; the MCP `traverse_relations` tool exposes the same on stdio
  and `usage-operation` gained `traverse_relations`. HTTP
  (`POST /v1/retrieval/traverse-relations`) and gRPC (`TraverseRelations`,
  descriptor-built JSON-string messages) now expose the same contract too,
  reusing the one kernel — so all four surfaces (library/MCP/HTTP/gRPC) are
  aligned. The forward-only PostgreSQL `semantic_index_relations` projection
  and PostgreSQL frontier provider are delivered: `init-storage!` creates the
  projection (source/target frontier indexes), `save-index-tx!` writes it
  forward-only (no historical backfill in migration),
  `storage/pg-relation-neighbor-provider` batches one query per depth level, and
  its output is proven byte-identical to the pure in-memory kernel (with-redefs
  parity plus a `SEMIDX_TEST_POSTGRES_URL`-gated real-PostgreSQL round-trip parity
  test, verified locally against an ephemeral PostgreSQL 17 cluster). Stage 4 is
  code-complete across all four surfaces: the HTTP edge
  (`POST /v1/retrieval/traverse-relations`) and the gRPC edge
  (`TraverseRelations`) now expose the same contract and kernel, so the ADR-040
  phased-exposure follow-up is done.
- Detail-stage raw fetch is now budget-adaptive instead of all-or-nothing: `perform-raw-fetch` measures the full requested-level token requirement (`required_tokens`), degrades the fetch level down the `whole_file -> local_neighborhood -> enclosing_unit -> target_span` ladder to fit the raw-fetch byte cap (`raw_fetch_level_degraded`), and slices the front of an oversized chunk into a partial snippet instead of returning an empty `raw_context` (`raw_snippets_truncated`, `raw_fetch_budget_limited`). When the detail payload is truncated or degraded, the context packet budget, perf `budget_summary`, and stage events carry `suggested_token_budget` (computed by inverting the 10/20/70 stage split and the 35% detail structure share, +10% margin), and the detail result exposes a top-level `next_step` with `recommended_action "raise_token_budget"` so clients can retry once with an adequate budget instead of falling back to manual file reads. The zero-detail-budget path (tiny requested budgets) intentionally still returns an empty, `skipped` raw fetch.
- Antigravity first-contact MCP behavior is now partially verified in production-like use: it successfully stayed on `create_index -> repo_map -> resolve_context` without drifting into manual browsing, but staged continuation still needs one explicit follow-up check to prove that it will keep using `expand_context` and `fetch_context_detail` via `selection_id` / `snapshot_id` instead of switching back to filesystem reads or broad summarization.

## Next Execution Priorities

1. Stage 3 is code-complete: relation identity/evidence split (ADR-039), the pure bounded traversal kernel (`traverse-relations`), and the bounded, reason-coded relation-backed impact projection (`:relation_support`) are all delivered. Any remaining Stage 3 work is confidence-ceiling recalibration only if future evidence supports it (currently a documented non-bump).
2. Ambiguous relation-backed flows stay conservative and no public graph-query API exists in Stage 3; the kernel and the projection both default to `:resolved_only true`.
3. Stage 4 (semantic graph query surface, gap 7) is fully code-complete under
   ADR-040: JSON/malli contract (4.1), the batched `traverse-relations-with`
   kernel seam (4.2), the public `relation-traversal` on library + MCP
   `traverse_relations` (4.2), the forward-only PostgreSQL
   `semantic_index_relations` projection + `pg-relation-neighbor-provider` at
   parity with the pure kernel (4.3), and HTTP (`POST
   /v1/retrieval/traverse-relations`) + gRPC (`TraverseRelations`) exposure of the
   same contract (4.4). The only optional residual is an explicit reprojection
   command for snapshots saved before the projection existed. Next frontier: the
   post-Stage-4 product sequence (provider catalog/discovery) and the independent
   operational Stages 5-7. Stage 5.1 (ADR-042 plus the complete authoritative
   `.proto`) is delivered; the next Stage 5 slice is tool acquisition,
   deterministic generation, and idempotent javac preparation. Stages 6-7 are
   the online policy control-plane and runtime-edge rate limiting.
4. After the public graph surface, sequence provider catalog/discovery work before the Protobuf/OpenAPI contract-linking vertical slice and the SCIP evidence-provider spike.
5. Keep tightening operational/docs alignment so roadmap, ADRs, examples, and runtime surfaces continue to describe the same canonical flow.
6. On the next Antigravity touchpoint, explicitly test staged continuation after `resolve_context`: require `expand_context` and `fetch_context_detail`, verify the client reuses `selection_id` / `snapshot_id`, and check whether evidence quality improves without falling back to manual browsing.

## Update Rule

Update this file when any of the following changes:

- runtime behavior materially changes
- new invariants are introduced
- priorities or known gaps change
- integration assumptions change

The versioned pre-push hook runs a conservative freshness check for this file
when high-signal project files change. If a change is intentionally
memory-neutral, bypass with `SCI_SKIP_MEMORY_FRESHNESS=1` only after checking
the update rule above.
