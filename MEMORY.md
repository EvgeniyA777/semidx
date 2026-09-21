# Project Memory

Current implementation reality and near-term operating context. This file is a
bounded index, not a changelog: prefer concise current facts plus links to the
documents that own history, rationale, and evidence.

## Orientation

- `semidx` is defined by
  [ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md): an incrementally
  maintained semantic graph of a codebase that provides exact program
  relationships for search, AI context, navigation, impact analysis, and future
  incremental analysis and compilation tooling.
- The constitution is **RATIFIED - 2026-09-13** and frozen by §18. Do not edit,
  clarify, relax, strengthen, or reinterpret it in place. A contradiction means
  fork, not local exception.
- The constitution owns exactly five terms: entity, node, relationship,
  assertion, and fact. Detailed mechanisms, schemas, fixture shapes, delivery
  plans, and verification procedures live in companion documents.
- [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md) owns explanatory design
  reasoning, [CONFORMANCE.md](CONFORMANCE.md) owns constitutional scenario
  families, [SPEC.md](SPEC.md) owns changing requirements and semantic contract
  lifecycle, and [CORE.md](CORE.md) owns the shared-core roster.
- [RULES.md](RULES.md) is the always-loaded agent rule kernel. Detailed process
  lives in [docs/agent-policy/](docs/agent-policy/), and task procedures live in
  [.agents/skills/](.agents/skills/).

## Current Decisions

- [ADR 001](docs/adr/001_choose_zig_implementation_language.md) chooses Zig for
  the rebuild. The target toolchain is exactly Zig 0.16.0; run
  `./scripts/check-zig-version.sh` before Zig or build changes.
- [ADR 002](docs/adr/002_local_tree_sitter_parser_dependency.md) fixes parser
  integration: local tree-sitter C sources behind one adapter. Use
  `./scripts/setup-tree-sitter-grammars.sh` and a local tree-sitter runtime;
  build and index steps do not fetch from the network.
- [ADR 003](docs/adr/003_reject_name_match_assertions.md) rejects
  repository-wide unique-name matching as graph authority. Unresolved
  designators stay unresolved unless a frontend can prove a language-correct
  target.
- [ADR 004](docs/adr/004_allow_java_same_package_type_resolution.md) admits the
  narrow Java same-package top-level type rule. It does not admit `module`,
  `IMPORTS`, Java imports, classpath modeling, inheritance, nested classes, or
  broader Java semantics.
- [ADR 005](docs/adr/005_add_zig_frontend_and_local_mcp_preview.md) admits the
  narrow Zig frontend and the local MCP stdio preview as a consumer, not a
  semantic contract.
- [ADR 006](docs/adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md)
  admits the Zig dogfood extension Plan 006 implemented: direct member functions
  inside covered top-level containers are definitions whose bodies use the same
  exact narrow call rules, and exact-case relative local `@import` aliases
  declare provider dependencies and support exact `alias.foo(...)` `CALLS`
  facts, without admitting `module`, `IMPORTS`, dispatch, arbitrary member
  lookup, or package imports.
- [ADR 008](docs/adr/008_java_visibility_boundaries.md) bounds Java resolution
  to a derived source root, with a test source root reading its module's main
  source root and nothing else crossing. It reads no build descriptor and admits
  no core kind.

## Implementation Reality

- The source tree contains the rebuilt first vertical slice: an in-memory graph
  over Java, Clojure, and Zig source units under `src/`, `tests/`, and
  `fixtures/`.
- Main commands: `zig build test-core`, `zig build test`,
  `zig fmt --check build.zig src tests`, `zig build run -- <files>`,
  `zig build mcp -- --root <dir>`, `zig build test-mcp`, `zig build dogfood`,
  and `zig build preview-gate`. The format check names its paths because
  `zig fmt --check .` can never pass: `fixtures/` holds source that is
  deliberately unparsable. `zig build test-core -Doptimize=ReleaseFast` also
  runs the query work-bound proof at external scale, which a debug build skips.
- `zig build preview-gate` is the one canonical local habit-loop gate
  ([specification](docs/mcp/habit_loop_gate.md)): the dogfood proofs as its
  `repository-copy` profile plus a `fixture` profile over a temporary root that
  proves honest degradation. Named hard gates fail it; latency and sizes are
  printed observations only. It is not a release and not part of
  `zig build test`.
- Build prerequisites are local files: pinned tree-sitter grammar sources and a
  local tree-sitter runtime exposing `tree_sitter/api.h` and
  `libtree-sitter.a`. `build.zig.zon` declares no fetched dependencies.
  `./scripts/setup-tree-sitter-grammars.sh` fetches only the grammars
  `build.zig` compiles, each at a pinned commit, and fails if its list disagrees
  with `grammar_checkouts`; a rerun with the commits present needs no network.
- `src/core/` is parser-free Zig core: model, strings, source registry,
  frontend contract, graph, dependencies, reconcile, and index orchestration.
  `zig build test-core` must pass with `-Dgrammars-dir=/nonexistent`.
- `src/frontend/tree_sitter.zig` is the only C ABI adapter.
  `src/frontends/{java,clojure,zig}.zig` translate language syntax into shared
  core assertions plus extension payloads.
- `src/root.zig` assembles the `Index`; `src/main.zig` is a developer inspection
  command whose output is not a contract.
- Source-unit identity is not path identity. The source registry preserves a
  unit across path-stable edits and exact single-file moves; a move plus content
  change remains removal plus addition until stronger evidence exists.
- Reconciliation is the write path for first build and every edit. Entity
  identity comes from semantic evidence, never from byte ranges, frontend-local
  ids, or tree-sitter node ids.
- Assertions carry producer and resolution (`fact`, `unresolved`, or
  `approximate`). Constructors reject unresolved targets presented as facts.
- Freshness is independent of resolution. A failed analysis leaves previous
  claims stale, not current and not silently withdrawn.
- `Graph` is mutable; `Snapshot` is the immutable published state observed by
  consumers. `publish` still walks the graph and is acceptable for edit batches,
  not for per-query publication.
- A designator — the target of every unresolved relationship — is a **structured
  name**: `name` is the identifier a producer read, and `qualifier` is present
  only where the frontend knows the prefix the source wrote names a scope (an
  `@import` alias path, a Clojure namespace, a Java class established as one),
  absent where it is a value ([ADR 010](docs/adr/010_designator_is_a_structured_name.md)).
  The written form is `SourceEvidence.text`, so default MCP output carries names
  and qualifiers only and expression text needs `--allow-evidence-text`. A
  producer that read no identifier records an empty name, which is not bucketed.
- `semidx_references` answers with relationships **and** `unresolved_mentions`:
  recorded claims whose producer could not resolve them and whose designator
  name equals the target's name byte for byte in the target's language. A
  mention keeps its own resolution, reason, producer, freshness and evidence,
  names no target, has its own `mention_limit` (50, max 500), totals, truncation
  flag, budget share and hint, and is never merged into `relationships`. It
  establishes nothing, so [ADR 003](docs/adr/003_reject_name_match_assertions.md)
  stands.
- A published snapshot carries its own read indexes, derived in `publish` and
  nowhere else: dense id-to-position tables behind `Snapshot.unit` and
  `Snapshot.entityById`, and compressed-sparse-row adjacency by source entity,
  by target entity, and by `designator.name` behind `Snapshot.relationships`. They are
  projections of that snapshot's own assertions, rebuildable from them with
  nothing lost, and no answer exists only in an index. An anchor the index does
  not hold returns empty rather than falling back to a scan; `kind`,
  `reference_query`, `resolution`, and `freshness` stay post-filters
  ([Plan 011](docs/plans/011_external_scale_graph_query_indexes.md)).
- Java cross-unit references are graph facts only when ADR 004's exact rule
  holds, the provider unit dependency is declared, and ADR 008's visibility
  boundary permits it. A unit's scope is its **Java source root**: what remains
  of its path once the directories its declared package spells and the file name
  are removed from the end. Two units see each other when their source roots are
  equal, or when the referring root is `<base>/src/test/<lang>` and the provider
  is `<base>/src/main/<lang>` — that direction only. A unit whose path does not
  spell its declared package has no source root, resolves nothing beyond itself,
  and is a candidate for nothing. Single-type imports (`import a.b.C;`) resolve
  inside that same boundary and are asked before the unit's own package;
  on-demand and static imports never resolve. A name declared out of the unit's
  scope is unresolved for its own stated reason, distinct from a name nothing
  declares. Provider removal, rename, or relevant export change reanalyzes
  dependents, and a package's importers are reanalyzed with its declarers.
- Zig covers top-level `fn` definitions, top-level container declarations bound
  directly to struct/enum/union/opaque expressions, and named `fn` members
  directly inside them (`container_path` = container name). In every covered
  body, a bare call resolves to the unit's one top-level function of that name,
  and `alias.foo(...)` resolves to the one `zig.export = callable` top-level
  `pub fn foo` of the unit a top-level `const alias = @import("relative.zig")`
  names, with a provider dependency. Receivers, values, package imports, nested
  namespaces, and container-member targets stay unresolved
  ([capability matrix](docs/spec/capability_matrix.md#zig)).
- `Index.applyScan` registers every added unit before analyzing any, and
  `Upkeep` reanalyzes a unit that read a provider analyzed later in the same
  batch; scan renames and `Index.renameUnit` seed dependency propagation. So a
  scan's graph does not depend on path order. `Index.addUnit` one unit at a time
  still does for Zig importers added before their providers.
- Reconciliation reports a renamed container's members as identity loss with a
  same-name replacement under the new container (`sameNameElsewhere`), for
  every frontend, instead of removal plus creation.
- `semidx-mcp` is the experimental local stdio preview. It scans one local root,
  publishes one snapshot, serves both the current `2026-07-28` stateless MCP
  shape and the legacy initialized `2025-06-18` shape, and exposes
  `semidx_health`, `semidx_outline`, `semidx_repo_map`,
  `semidx_find_definitions`, `semidx_references`, `semidx_context`, and
  `semidx_refresh`.
- MCP results return graph values only by default: ids, paths, ranges, kinds,
  relationships, and per-claim resolution, freshness, and producer.
  `semantic_contract_version` is still `null`.
- Tool arguments are declared once in `src/mcp/tools.zig`; the advertised
  schema and the validator both derive from them. `semidx_repo_map`,
  `semidx_references`, and `semidx_context` default to `detail: "compact"` and
  take `detail: "full"`. Compact context and references keep each claim's
  resolution category, producer name, freshness, and location; the repository
  map carries freshness and location but no existence provenance at either
  level. List tools report `budget`
  ([detail levels](docs/mcp/local_preview.md#detail-levels-and-budgets)).
- Plan 009 made discovery progressive: `semidx_outline` gives per-directory
  counts without definitions as the first orientation call; every list tool
  stops at `max_response_bytes` (32000 structured bytes by default, whole
  items only) and reports `budget_exhausted`; cut lists carry
  `narrowing_hints`; outline, map, definitions, and references return
  `next_cursor`, which carries the call's canonical arguments under a tag
  keyed by a per-process secret and is valid only for the same tool, arguments,
  and snapshot revision; `semidx_context` takes `direction` and `depth` (max 3) for a
  traversal that renders each entity once. All are projection mechanics, not
  graph semantics.
- `semidx_refresh` keeps the previous snapshot on failure. If a refresh fails
  after reconciliation starts, the server discards that index and rebuilds from
  the same scan to avoid publishing partial state.
- `scripts/semidx-mcp.sh` is the stable local launcher for agents. The older
  `scripts/start-mcp-server.sh` and `scripts/mcp-stdio.sh` remain compatibility
  aliases.
- The product version is `0.1.0-preview.3` (`build.zig.zon`): the preview.2
  surface plus Plan 009 progressive MCP discovery and response-budget behavior
  ([release notes](docs/releases/v0.1.0-preview.3.md)). Annotated tags pushed
  to `origin`: `v0.1.0-preview.1` at `e36693a`, `v0.1.0-preview.2` at
  `8818bb6`, and `v0.1.0-preview.3` at `58af737`; no GitHub release was
  created.

## What Does Not Exist

- No persistence, HTTP, gRPC, stable CLI contract, `contracts/` schemas,
  resources, prompts, subscriptions, file watching, package-manager
  distribution, binary release, remote service dependency, vectors, embeddings,
  RAG, or retrieval pipeline.
- No published semantic contract version. Current core admissions are
  unversioned implementation guidance only.
- No admitted shared-core `module` or `IMPORTS`.
- No complete language support. Java, Clojure, and Zig fixtures prove current
  slice behavior; they are not a supported-language roster.
- No Java on-demand or static import resolution, qualified names, nested
  classes, inheritance, classpath symbols, interface/enum/record targets, or
  reading of any build descriptor: cross-module visibility a build tool would
  permit stays unresolved
  ([Follow-up 011](docs/followups/011_java_cross_module_visibility.md)).
- No Clojure namespace or lexical-scope model beyond the current conservative
  same-unit rules.
- No Zig package imports, namespace/container/member lookup beyond ADR 006's
  implemented subset, receiver dispatch, fields, locals, comptime semantics,
  generics, or nested-container semantics.
- No executable conformance suite yet; conformance remains documented scenario
  material unless a requirement adopts a specific check.

## Active Constraints And Risks

- The graph-authority boundary is load-bearing: approximate and text-derived
  mechanisms may discover, rank, and render, but only graph-established evidence
  may create program relationships.
- Unsupported constructs, unavailable analysis, unresolved assertions,
  approximate evidence, stale claims, and confirmed absence must stay visible and
  distinguishable.
- Local operation remains mandatory. Source-derived outbound data requires
  explicit opt-in for the destination and data involved.
- Documentation drift is controlled by
  [docs/agent-policy/documentation.md](docs/agent-policy/documentation.md):
  source-of-truth edits, ADRs, staged plans, release handoffs, and plan closure
  must check the relevant owners and either align them or record residual risk.
- The root README is the public project presentation and routing entry point.
  Proof workflows, release gates, stage evidence, and plan-specific checklists
  stay in their owning references, plans, reports, releases, or policies.
  `scripts/check-readme-stewardship.sh` guards the obvious drift markers in
  pre-commit and pre-push.
- `MEMORY.md` is intentionally bounded. Compress stale detail into links to
  ADRs, reports, plans, follow-ups, specs, or implementation files instead of
  appending history.
- Constitution freeze enforcement is cryptographic via
  `scripts/check-constitution-freeze.sh` and
  `scripts/constitution.freeze.sha256`.
- Memory freshness is enforced by `scripts/check-memory-freshness.sh` and the
  pre-push hook for high-signal documentation and policy changes.
- External Java measurement has two harnesses, both developer tools no lane
  depends on: `zig build claim-sample` (`src/claim_sample.zig`), which samples by
  `sha256(seed + key)` rank and counts any unclassified reason rather than
  dropping it, and `zig build designator-shape` (`src/designator_shape.zig`),
  which reports what unresolved designators hold and how `DesignatorAdjacency`
  buckets them. Tooling is `sh` or Zig ([tooling.md](docs/agent-policy/tooling.md));
  Plan 012's numbers predate them ([017](docs/followups/017_plan_012_external_evidence_reproducibility.md)).
  Current external baseline, apache/dubbo at `df9c5e1`: 92,637 facts, 138,222
  unresolved, 118,471 unresolved calls, and 83.6% of their designators are
  expression text rather than names
  ([Plan 013 Stage 0](docs/reports/013_unresolved_mentions_from_the_callee_anchor_progress.md)).
- Known implementation risks live in progress-log residual-risk sections and
  [docs/followups/README.md](docs/followups/README.md). The load-bearing ones:
  Java coverage, not its boundary, is what limits it — receiver-qualified and
  class-name-qualified calls dominate what stays unresolved; definition renames
  are identity loss; a file moved and changed in one rescan loses identity;
  dependency invalidation is intentionally coarse and
  transitive; a Zig importer of a relative file that did not exist when it was
  analyzed is not reanalyzed when it appears (unresolved, never false); unit ids
  and interned strings are not reclaimed while the graph lives;
  `Snapshot` string borrowing and default-current query discipline are
  conventions rather than type-enforced boundaries.

## Near-Term Priorities

- Plan 009 is published as `0.1.0-preview.3`, gated by `zig build preview-gate`.
- The project is on the adoption track: work is chosen because it moves semidx
  toward the audience named in
  [the adoption strategy](docs/design/002_product_adoption_strategy.md), not
  because it improves semidx's view of itself. Dogfood-only coverage such as
  [006](docs/followups/006_zig_cross_unit_and_member_calls.md) sits behind that.
- [Plan 010](docs/plans/010_java_resolution_boundaries.md) is executed:
  resolution is bounded by ADR 008's source root with single-type imports inside
  it, Follow-up 003 is closed and cross-module visibility split into
  [011](docs/followups/011_java_cross_module_visibility.md). The remaining Java
  blockers are coverage, not the boundary.
- [Plan 011](docs/plans/011_external_scale_graph_query_indexes.md) is executed
  and Follow-up 012 is closed: identity lookups are constant time, anchored
  queries inspect exactly what they return under a committed work bound past
  Dubbo's assertion count, and `semidx_context depth=2` there fell from 90.71 s
  to 0.019 s.
- [Plan 012](docs/plans/012_java_semantic_quality_without_query_regression.md)
  is **executed**: `ClassName.method(...)` is a `CALLS` fact when every
  [ADR 009](docs/adr/009_java_static_calls.md) condition holds at once, and
  otherwise stays unresolved naming the condition that failed. Java definitions
  carry `java.supertypes`, `java.access` and `java.static`; a resolved call
  declares a provider dependency, an unresolved one is reached by an
  aspect-grained reader hint. Value receivers stay with
  [014](docs/followups/014_java_instance_receiver_calls.md) and the supertype
  guard with [013](docs/followups/013_java_supertype_guard_relaxation.md); its
  post-closure review left
  [017](docs/followups/017_plan_012_external_evidence_reproducibility.md) and
  [018](docs/followups/018_unexplained_assertion_delta.md) open and fixed
  [015](docs/followups/015_unit_path_change_does_not_reanalyze.md) and
  [016](docs/followups/016_java_static_call_rule_narrow_gaps.md).
- [Plan 013](docs/plans/013_unresolved_mentions_from_the_callee_anchor.md) is
  **executed**: structured designators and `unresolved_mentions`, closing
  [019](docs/followups/019_designator_may_carry_source_expression.md) and
  narrowing [017](docs/followups/017_plan_012_external_evidence_reproducibility.md).
  It converted no claim and moved no fact; on apache/dubbo at `df9c5e1` it took
  unresolved calls reachable from the definition they name from 10,141 to
  91,087 of 118,471.
- Text fallback duplication is **kept by decision**, not left open, by
  [ADR 007](docs/adr/007_text_fallback_migration_flag.md) (`proposed`): most MCP
  clients read `content`, not `structuredContent`, so the copy is load-bearing.
  Only the `--text-fallback=full|none` diagnostic probe is added, `none` never a
  production value, and
  [Follow-up 010](docs/followups/010_mcp_text_fallback_client_measurement.md)
  closes against it.
- Source identity needs stronger evidence for move-plus-edit refactors: prefer
  VCS or IDE move events over similarity presented as fact.
- Storage and snapshot representation remain SPEC-owned unresolved areas: any
  persistence design changes the current snapshot story.
- Keep frontend coverage tied to stated risk and report it through the
  [capability matrix](docs/spec/capability_matrix.md), never as broad
  language-support claims.
- Remove the inert `scripts/git-hooks/pre-push` block for the removed Clojure
  `docs/code-context.md` flow once the stack has a replacement.

## Current Evidence Pointers

- Plans 001-009 history — vertical slice, repository-scale ingestion, Java
  same-package resolution, Zig frontend and MCP preview, release readiness,
  dogfood coverage, response budgets, habit-loop gate, progressive discovery —
  is one progress log per plan in [docs/reports/](docs/reports/), with the
  preview notes in [docs/releases/](docs/releases/); current release candidate
  [v0.1.0-preview.3](docs/releases/v0.1.0-preview.3.md).
- Plan 010 Java resolution boundaries, and the first external evidence:
  [docs/reports/010_java_resolution_boundaries_progress.md](docs/reports/010_java_resolution_boundaries_progress.md).
- Plan 011 query indexes, the cost model and its measurements:
  [docs/reports/011_external_scale_graph_query_indexes_progress.md](docs/reports/011_external_scale_graph_query_indexes_progress.md).
- Plan 012 Java static calls, its costs and its post-closure review:
  [docs/reports/012_java_semantic_quality_without_query_regression_progress.md](docs/reports/012_java_semantic_quality_without_query_regression_progress.md).
- Plan 013 designators and mentions, with the external before/after:
  [docs/reports/013_unresolved_mentions_from_the_callee_anchor_progress.md](docs/reports/013_unresolved_mentions_from_the_callee_anchor_progress.md).
- Active follow-ups: [docs/followups/README.md](docs/followups/README.md).
- Product direction: [docs/design/001_project_roadmap.md](docs/design/001_project_roadmap.md),
  [docs/design/002_product_adoption_strategy.md](docs/design/002_product_adoption_strategy.md).
