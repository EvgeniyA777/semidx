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
- A `plans/013` post-delivery SOLID review closed five findings: the online policy-control-plane `retire` endpoint now refuses retiring the `active` baseline (only `promote` swaps active, keeping "exactly one active" intact) and idempotently refuses an already-`retired` entry, both as `policy_not_eligible` (409); `run-policy-transition!` scopes its `catch` to the persistence boundary only, so a bug escaping a pure transition surfaces as an internal error via `with-handler` instead of being mislabelled `registry_persistence_failed`; and the relation-traversal public fields were renamed `max_paths` -> `max_discovery_paths` and `paths` -> `discovery_paths` across kernel/`malli`/JSON Schema/MCP/HTTP/gRPC/docs/tests (behaviour-preserving: one deterministic shortest first-discovery path per reached node, no multipath enumeration; see the ADR-040 amendment). Defensive notes were added documenting the rate-limiter `locking` invariant and that the relation-id SHA-1 is non-crypto content addressing whose change would require a `relation-schema-version` bump plus PostgreSQL projection backfill.

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
- Stage 5 is complete under ADR-042: `runtime.proto` carries all 16 envelope
  messages and all eight unary RPCs; the pinned repo-managed toolchain generates
  and verifies 34 committed Java sources; ordinary test/runtime starts perform
  offline idempotent javac; and the runtime now uses generated message and
  `RuntimeServiceGrpc` descriptors with the descriptor-built oracle removed.
- No dynamic external policy backend integration yet (current authz adapter is local file/callback based).
- HTTP edge now exposes an online policy control-plane (`GET /v1/policies/registry`, `POST /v1/policies/promote`, `POST /v1/policies/retire`). Offline review emits digest/revision-bound promotion decisions; restricted policies require decision-bound approver records; file authz is deny-by-default per policy operation; and serialized transitions atomically replace the registry file before publishing memory state (Stage 6).
- Stage 7 runtime-edge rate limiting is delivered under ADR-044: HTTP and gRPC
  share an optional, default-off, bounded fixed-window limiter with tenant or
  tenant+actor scope, monotonic windows, unified HTTP 429 / gRPC
  `RESOURCE_EXHAUSTED` errors, retry metadata, and decision-based usage/SLO
  metrics. Ingress/proxy/host remains responsible for distributed/global quotas.
- ADR-046 is the current parser-authority decision for Java and TypeScript:
  fresh SCIP/LSP evidence is primary per operation, tree-sitter fills structural
  gaps, and regex is explicitly degraded fallback. The current regex-first code
  path is a legacy migration baseline under plans/018 and must not be treated as
  target policy. ADR-047 retains repo-managed tree-sitter CLI/grammar resolution:
  explicit parser/provider options, environment configuration, the repo bootstrap
  link, then ambient `PATH` only as developer fallback.
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
- `plans/019` is the planned LLM one-shot delivery track: add an external `get_context` facade over the same snapshot-bound staged state machine, retain ContextPacket as the structured source of truth, make Markdown an optional bounded projection, and contribute staged/one-shot strategy adapters to the benchmark substrate owned exclusively by `plans/020`. Its top-level response budget is authoritative, `structured`/`markdown`/diagnostic allocations are disjoint, and usage telemetry distinguishes aggregate from stage accounting. ADR-024 remains current; changing the documented canonical default requires comparative evidence and a new ADR.
- `plans/020` is in progress and is the exclusive owner of the real-repository task corpus, immutable `BenchmarkRun`/`TaskAttempt` identities, A/B/C/D strategy harness, provider/API/model usage adapters, price schedules, and success-per-cost aggregation. Stage 1 (`returned_tokens` fidelity) is delivered. Stage 0 now separates harness executor models from `evaluated_*` attempt identities, uses `implicit_cache_observed_v1` (no explicit cache objects; implicit reads recorded), and gates the current Gemini 2.5 schedule at 2026-10-16; calibration/final lock remain pending, and Stage 2 has not started.
- `plans/018` remains planned and source-unimplemented. Multi-provider evidence must normalize to a provider-neutral `CanonicalFactKey` before arbitration; provider ids, native symbols, source identity, and mutable evidence are not stable merge keys. Cross-provider Java overload and TypeScript re-export identity fixtures are Stage 0/1 admission gates.
- `plans/007` remains an active architecture reference, not an executable queue. It closes only after its continuation ownership, freshness/lifecycle, provider-catalog, relation-parity, public-boundary, and documentation-handoff gates have recorded evidence; a future successor must be self-contained rather than merely linked. On closure its frontmatter becomes `completed` / `historical_reference_only`, and active implementation must use the named successor plans and ADRs instead.
- Stage execution routing is explicit in `plans/018`, `plans/019`, and `plans/020`: Claude Code owns the provider-authority track, while Antigravity owns the benchmark and one-shot delivery tracks. High effort is allowed when justified by contract irreversibility, identity/arbitration, freshness, benchmark verdicts, public defaults, conflicting evidence, or repeated verification failures, and a high-effort handoff must record its concrete justification. Every stage-closing model must read the candidate next stage, cross-plan gates, progress/MEMORY/SPEC state, completed diff and checks, file ownership, and current model/quota constraints, then record a `NextStageRoutingRecommendation`; it may recommend `stop` or `defer` and never auto-bypasses an admission gate.
- Dedicated `impact_analysis` now computes impact hints directly from the resolved selection artifact instead of reading `expand_context`'s budget-gated `:impact_hints` field; it must return a non-null map with `:callers`, `:dependents`, `:related_tests`, and `:risky_neighbors` vectors even when `expand_context` omits impact hints for token-budget reasons.
- MCP `create_index` handles are workspace-root isolated: stale cache entries whose entry `:root_path` does not match the embedded index `:root_path`, or whose cache key points at a different requested root, are discarded instead of being reused; a storage-loaded index with an unexpected root is rebuilt for the requested canonical root.
- Intent-only retrieval with `include_tests` now has a test-aware lexical path: file paths participate in lexical matching, `src/test/...` is classified as test code before generic `src/` source code, and `focus_on_tests` boosts already-matched test units without broadening to unrelated tests.
- Retrieval benchmark baselines are aligned with current runtime behavior again: the synthetic benchmark repo includes JavaScript, HTML, and CSS paths used by fixtures, public context-packet unit kinds are normalized to the contract enum, and fixture confidence expectations follow the current per-language capability ceilings.
- Language adapter extraction has moved the Clojure, Java, Python, Lua, Zig, TypeScript, and JavaScript lanes out of `semidx.runtime.adapters`: `semidx.runtime.languages.clojure/parse-file` owns Clojure regex, clj-kondo, and tree-sitter parsing; the Java and TypeScript parser-engine functions own the current legacy regex/tree-sitter implementation baseline pending plans/018; `semidx.runtime.languages.python/parse-file` owns Python module/import/call extraction, class/method ownership, relative imports, test linkage, and nested-scope suppression; `semidx.runtime.languages.lua/parse-file` owns Lua module/import/call extraction, table/method ownership, module return-owner detection, local call suppression, and test linkage; `semidx.runtime.languages.zig/parse-file` owns the accepted ADR-048 low-strength regex-first Zig surface for static imports, top-level/container functions, test blocks, calls, and test linkage; and `semidx.runtime.languages.javascript/parse-file` owns JavaScript dispatch via the TypeScript lane with JavaScript language tagging. `adapters/parse-file` currently dispatches directly to those lane namespaces; plans/018 replaces that Java/TypeScript single-parser authority path with provider planning. `semidx.runtime.languages.shared` owns generic line/signature/token and tree-sitter CLI/config/CST helpers for language lane implementations.
- The language-onboarding scaffold and validator target dedicated `semidx.runtime.languages.<language>/parse-file` modules rather than the removed adapter-private parser stubs; Zig is the first lane onboarded through the corrected flow, and the existing Lua structural validation is green under it.
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
  generated protobuf messages with JSON-string envelope fields) now expose the same contract too,
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
- `plans/016` Stage 2 is delivered: `impact_analysis` now conditionally adds a
  bounded `state_invariants` Slice-1 packet for state/lifecycle queries when an
  entity/model candidate is corroborated by selected, call-graph, or import
  facts. The dedicated `runtime/state_invariants` policy surfaces one entity
  representative per path, selected state writers, evidence-prioritized test
  paths, fixture helpers, and a mandatory whole-file-read guardrail. It makes no
  field-level claims; JSON Schema/Malli and MCP exposure are the next Stage 3.
- `plans/016` is fully delivered through Stage 4. Stage 3 made the
  `state_invariants` packet contract-backed:
  contract-backed. `state-invariants` + `state-invariant-unit-ref` Malli mirrors
  (`contracts/schemas.clj`, registered `:example/state-invariants`), a standalone
  `contracts/schemas/state-invariants.schema.json`, and a validated
  `contracts/examples/state-invariants/impact-analysis-packet.json` (wired into
  the catalog + validator path mapping). `packet_version` uses an independent
  `^[0-9]+\.[0-9]+$` pattern to allow additive evolution. All packet lists,
  including `:triggered_by`, are now bounded to 12. MCP passthrough required no
  reshaping: `tool-impact-analysis` returns the whole hint map, so
  `:state_invariants` rides inside `:impact_hints` and usage-metric counters stay
  additive. Stage 4 additionally exposes the same conditional packet as a
  budget-accounted sibling on `expand_context` and the detail context packet;
  the Malli expansion/context mirrors and JSON context-packet schema accept it,
  and library/HTTP/gRPC parity tests cover the Java lifecycle fixture. When the
  packet cannot fit, staged retrieval emits `state_invariants_omitted` rather
  than exceeding its reserved budget.
- `plans/017` (ADR-045) is fully delivered: the deferred field-level
  state-invariant tranche, with entity fields modeled as relation target keys,
  never units. The Java lane (`languages/java.clj`, both regex and tree-sitter
  paths) emits two additive typed-relation kinds registered in
  `relation-types`: `structure/declares-field` for class-body fields of
  entity-like classes only (entity annotation / entity-or-model path /
  class-or-module suffix; method-body locals excluded), sourced at the synthetic
  `path::module` class node with `target_key` `pkg.Class#field` and
  annotation/nullability hints in `evidence_location`; and
  `dataflow/writes-field` for state-transition methods (writer-named methods or
  entity-class methods) from setter calls (`x.setStatus(..)`) and direct
  `this.field = ...` assignments, sourced at the writer method unit with a
  `field:<name>` sentinel target key. Both kinds have no target unit, normalize
  to `unresolved`, and are skipped by resolved-only traversal, so
  callers/callees, `impact_analysis`, and `relation_support` stay byte-identical.
  `runtime/state_invariants` consumes them: the packet gains an optional
  `entity_fields` section (declared fields + nullability/annotation evidence +
  `state_bearing` hint) and an optional `field_writes` section (fields each
  selected state writer touches), with a guardrail that names state-bearing
  fields and contrasts written vs. declared fields. `packet_version` is now
  dynamic: `1.2` with field writes, `1.1` with only declared fields, `1.0`
  (Slice-1) otherwise. The `state-invariants` Malli mirror, JSON Schema, and the
  example packet carry the additive sections (all lists bounded); both sections
  are present only when relations exist, so lanes/queries without field facts
  keep the exact `1.0` packet. `impact_analysis`, `expand_context`, and the
  detail packet all carry the upgraded packet through the existing
  budget-accounted seams. Non-Java lanes, migration/schema linkage, and richer
  column facts remain deferred to a future plan reusing these relation types.
- Antigravity first-contact MCP behavior is now partially verified in production-like use: it successfully stayed on `create_index -> repo_map -> resolve_context` without drifting into manual browsing, but staged continuation still needs one explicit follow-up check to prove that it will keep using `expand_context` and `fetch_context_detail` via `selection_id` / `snapshot_id` instead of switching back to filesystem reads or broad summarization.

## Next Execution Priorities

1. Continue `plans/020`: freeze the A/B/C/D arms, suite/run/attempt schemas,
   shared task-prompt and arm-policy bundle, execution-budget policy, cache
   protocol, provider usage-adapter versions, and price schedule;
   then implement the four-arm harness, attempt-first aggregator, and first
   external-repository evidence run. Do not start the pilot with unresolved
   pricing semantics.
2. Complete `plans/018` admission work: approve `CanonicalFactKey`, add
   cross-provider Java overload and TypeScript re-export identity fixtures, and
   confirm TypeScript as the first SCIP slice unless toolchain evidence justifies
   reversing it. Then implement provider evidence/arbitration and shadow planning
   before any default authority switch.
3. Execute `plans/019` as an additive one-shot delivery track after its budget
   ledger and the `plans/020` run/strategy contracts are accepted. Its evaluation
   stage contributes adapters to `plans/020`; it does not own a second corpus,
   usage normalizer, or scorecard.
4. Keep relation-backed flows conservative: ambiguous facts remain excluded from
   resolved-only traversal, and confidence ceilings change only with replay and
   task-value evidence.
5. Keep roadmap, ADRs, examples, runtime surfaces, and active-plan lifecycle
   metadata aligned with the same canonical staged flow and current ownership.
6. On the next Antigravity touchpoint, explicitly test staged continuation after
   `resolve_context`: require `expand_context` and `fetch_context_detail`, verify
   reuse of `selection_id` / `snapshot_id`, and check that evidence quality
   improves without fallback to manual browsing.

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
