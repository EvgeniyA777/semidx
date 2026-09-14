# Project Memory

Current implementation reality: what exists in this repository right now and
why. This is not a changelog of removed implementation; see `git log`.

## What Exists And Why

- `ARCHITECTURE_CONSTITUTION.md` is **RATIFIED — 2026-09-13**. It is frozen:
  §18 provides no amendment procedure, and a constraint that turns out to be
  wrong is grounds for a fork with its own constitution, never for an edit.
  What it fixes is product identity rather than conformance mechanics: semantic
  graph as the product, entity nodes rather than chunks, exact/unresolved/
  approximate separation, stable identity, incrementality with consistent
  observation, language frontends plus a common core, consumer independence, and
  local operation without mandatory source-data transmission.
- Four post-distillation corrections were applied to the DRAFT before
  ratification. §1 now states the graph-authority boundary the way the
  pre-distillation draft had resolved it: text-derived and approximate
  mechanisms may discover candidates, rank them, and render located source, but
  never establish a program relationship. The distillation had replaced that
  with a blanket "on top of the semantic graph", which contradicted
  [CONFORMANCE.md](CONFORMANCE.md). §1 also lost "Everything else is an index,
  projection, interface, or consumer of that graph": read strictly, "of that
  graph" forbade the source-text index the same section permits, and the
  preceding sentence carries the authority claim by itself. §7 lost its closing
  sentence requiring a viable non-MCP consumer path: it named one protocol in
  the identity document and turned on the undefined word "viable". Consumer
  independence remains protected by §7's authority clause and is checked by
  `CONFORMANCE.md`. §7 ¶1 then lost "of the graph" as well, so the constitution
  carries no remaining construction that could be read to require a projection
  to be derived from the graph rather than from source text.
- The constitution still owns exactly five terms whose distinctions are product
  identity: entity, node, relationship, assertion, and fact. Source containers
  are entities; source ingestion can establish facts about source organization;
  exact system resolution can establish facts when supporting evidence and
  method establish the claim.
- The former detailed rationale and detection material was moved out of the
  frozen boundary rather than discarded:
  [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md) explains why the
  principles exist, and [CONFORMANCE.md](CONFORMANCE.md) owns reviewable and
  eventually executable scenario families.
- `CORE.md` is a **draft roster with initial unversioned admission results**.
  `repository`, `file`, `definition`, `CONTAINS`, `DEFINES`, `REFERENCES`, and
  `CALLS` are accepted as shared-core meanings for the fixture-scoped
  implementation; no roster version or public contract is published. `CONTAINS`
  is direct source/program containment, while `DEFINES` is narrower
  definition-introduction whose target must be a `definition`. `module` and
  `IMPORTS` remain blocked, and textual-inclusion coverage remains unresolved.
- `SPEC.md` is a **draft requirements entry point**. It owns changing
  requirements, semantic contract lifecycle, publication and migration rules,
  outstanding specification work, and proposed delivery direction. It also owns
  the five core admission criteria (Adequacy, Identical meaning, Honest absence,
  Subsidiarity, Common cost), which were constitutional text before the
  distillation and had no owner between it and this cleanup.
- `GLOSSARY.md` holds descriptive vocabulary and points to the canonical
  [document ownership policy](docs/agent-policy/documentation.md).
- Document status is synchronized. `SPEC.md` and `CORE.md` are `draft` because
  their own text is unfinished: SPEC still lists ten requirement areas to
  specify, and CORE still has blocked candidates plus no published semantic
  contract version. `CONFORMANCE.md`,
  `ARCHITECTURE_RATIONALE.md`, and `GLOSSARY.md` are `active` because their text
  is settled — a specification is not a draft merely because the work it
  describes has not started. `ARCHITECTURE_CONSTITUTION.md` carries no
  frontmatter by rule: its status line is the single place its state is
  declared.
- `RULES.md` remains the single source of truth for agent process rules, and is
  now a kernel under an explicit 200-line budget stated in its first section: a
  rule needing more than a few lines lives in `docs/agent-policy/` or
  `.agents/skills/`, and `RULES.md` keeps one line pointing at it. It currently
  runs 168 lines. Its Project Context section now records the real build
  commands, the tree-sitter prerequisites, and what does and does not exist in
  the source tree.
- `RULES.md`, `AGENTS.md`, and `CLAUDE.md` do not offer "documented and justified
  deviation" as a route around the constitution: inside the boundary, decisions
  are documented; outside it, §18 requires a fork. Claims left over from the
  removed implementation are gone from all of them — a language roster attributed
  to the constitution, staged retrieval as the canonical public contract, and the
  same layer in the repository skills (CanonicalFactKey, provider authority,
  language lanes, MCP wire shape, a named PostgreSQL path). Language coverage and
  public contracts are open `SPEC.md` requirements.
- `docs/agent-policy/{documentation,git,testing,tooling}.md` owns detailed
  cross-cutting process. Testing policy now names the real verification lanes
  (`zig build test-core`, `zig build test`, `zig fmt --check`,
  `zig build run`) and requires runtime smoke evidence to consume the full
  stdout/stderr streams and check the exit status, not just an early summary.
  Tooling policy carries a Zig addendum naming which probe belongs to which
  edit. Documentation policy owns ownership, filenames, frontmatter, lifecycle,
  the ADR procedure, progress logs, and the Plan Readiness Gate; git policy owns
  hooks, command ordering, commit and push rules, and both the attribution and
  constitution-freeze enforcement; testing policy owns risk-based verification
  and local services; tooling policy owns MCP-first retrieval, code reading, and
  editing probes, and scopes the MCP sections as development tooling configured
  outside this repository rather than the rebuilt public API.
- `docs/followups/` is the register for accepted deferred findings that are
  concrete enough to feed a future plan but are not plans themselves. Use it for
  bugs, coverage gaps, semantic limitations, upstream limitations, and process
  defects; keep broad roadmap topics in `SPEC.md` or this memory until they
  become specific follow-up entries.
- `docs/design/001_project_roadmap.md` is the orientation layer for project
  direction. It records the current milestone, next product steps, and
  anti-drift checks; it is not an implementation plan.
- `docs/design/002_product_adoption_strategy.md` owns product positioning and
  adoption strategy: the first audience is developers already using coding
  agents, and the first promise is local, bounded, honest semantic context rather
  than broad code search or complete language understanding.
- The ADR procedure is enabled and the sequence starts at `001`;
  [docs/adr/README.md](docs/adr/README.md) is the index.
  [ADR 001](docs/adr/001_choose_zig_implementation_language.md) accepts Zig as
  the implementation language for the rebuild, and
  [ADR 002](docs/adr/002_local_tree_sitter_parser_dependency.md) fixes how
  parsing enters the build: local tree-sitter C sources behind one adapter, with
  grammar sources pinned by `scripts/setup-tree-sitter-grammars.sh` and the
  runtime linked from a local install prefix. Reasoning about the architecture
  documents themselves stays in
  [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md), and drafting history
  stays in `git log`.
- `README.md` is a minimal human entry point. Its status line says "first
  vertical slice", it still states the capabilities as intended rather than
  measured behavior, it links to the architecture document set, it names the
  three commands that run the slice, and it points MCP users to
  [docs/mcp/local_preview.md](docs/mcp/local_preview.md), the reference for
  building, starting, configuring, and reading `semidx-mcp`.
- **The first Zig vertical slice is implemented.** `docs/plans/001_zig_vertical_slice.md`
  is executed and closed; `docs/reports/001_zig_vertical_slice_progress.md`
  carries the stage outcomes, exact verification commands, review findings,
  skipped checks, and residual risk.
  `docs/reports/002_consolidated_progress.md` now owns the follow-up workstream:
  the freshness defects and fixes, the first core admission review, the
  `CONTAINS` / `DEFINES` split that resolved the first admission blocker, and
  the repository-scale ingestion plan closure covering source discovery,
  source-unit identity, rescan reconciliation, scale guards, ADR 003, dependency
  tracking, and closure. Read these two reports before extending the
  implementation.
- What the slice is: an in-memory semantic graph over Java and Clojure fixtures,
  built on Zig 0.16 and tree-sitter through the C ABI
  ([ADR 002](docs/adr/002_local_tree_sitter_parser_dependency.md)). Source lives
  in `src/`, tests in `tests/` and alongside each module, fixtures and their edit
  histories in `fixtures/vertical-slice/`.
- Module boundaries, and the dependency direction they enforce:
  `src/core/` (model, strings, frontend contract, graph, reconcile) is pure Zig
  with no parser dependency; `src/frontend/tree_sitter.zig` is the only module
  that sees the C ABI; `src/frontends/{java,clojure}.zig` translate parse nodes
  into shared-core assertions; `src/root.zig` assembles them as `Index`;
  `src/main.zig` is a developer-only inspection command whose output is not a
  contract. `zig build test-core` builds and runs the core alone, and passes with
  `-Dgrammars-dir=/nonexistent`, which is the mechanical proof that the core does
  not depend on a parser.
- **A rescan is reconciled against what the graph already holds.**
  `source/registry.zig` decides correspondence as a pure function over unit
  identity evidence — path, language, content identity — with no filesystem,
  graph, or frontend involved. The rule in order: a path present in both scans
  is the same unit whatever its contents; a unit whose path disappeared
  corresponds to a new unit with identical content and the same language, and
  only when exactly one of each exists for that content; everything else is a
  removal or an addition. A path swap is therefore two content changes rather
  than two renames, and a file that moved *and* changed is a break, because
  nothing establishes that the new unit is the old one. An ambiguous move is
  reported rather than resolved by picking one. There is no unit-level `lost`:
  a path that disappeared leaves no slot for a replacement to take, so claiming
  one would name a replacement the graph did not identify.
  `Analyzer.invocations` counts frontend reads, which is what makes "only the
  affected region was reanalyzed" a measured claim.
- **The graph stores things the way ingestion reads them.** Assertions and
  diagnostics are bucketed by the source unit they were observed in, definitions
  are indexed per unit, and paths are indexed to units, so withdrawing one unit's
  analysis touches that unit and nothing else. Before Stage 4 all three were
  graph-wide sweeps, which made a full scan of n units O(n²) — invisible at two
  units, which is why the stage existed. `Graph.unit_work` counts records
  examined while applying a change scoped to one unit, and the scale tests assert
  it is identical across trees of different sizes; the guard was verified by
  reintroducing a sweep and watching it fail. `publish` still walks the whole
  graph on purpose, and that cost is measured and accepted, not solved:
  ~1,100 records for 73 units.
- **The first production cross-unit facts exist: Java same-package type
  resolution** ([ADR 004](docs/adr/004_allow_java_same_package_type_resolution.md),
  [plan 003](docs/plans/003_java_package_type_resolution.md),
  [report 003](docs/reports/003_java_package_type_resolution_progress.md)). A
  field type or method return type written as a simple name, in a unit with an
  explicit package, resolves to the one current top-level class another unit
  declares in that package — a `REFERENCES` fact with a dependency on the
  provider unit — but only after the Java frontend rules out a type parameter, a
  declared member type, any supertype (inherited member types), a single-type or
  static import of the name, and a top-level non-class type of that name.
  Qualified, missing, other-package, default-package, ambiguous, and shadowed
  names stay unresolved with explanations naming the reason. No package entity,
  `module`, or `IMPORTS` was introduced; the package stays the `java.package`
  extension label.
- How that is wired. `contract.DraftTarget.external` names a graph-established
  definition plus its provider unit; `reconcile.integrate` refuses it before
  mutating anything unless it is a `REFERENCES`/`CALLS` target, the provider is
  another unit the batch declares a dependency on, and
  `Graph.currentDefinitionFact` finds it a current definition fact of that
  provider. The analyzer builds a `java.Context` per analysis from
  `frontends/java_packages.zig`: a per-package table rebuilt from current
  `frontend.java` class facts, bounded to one package by a hint of which units
  declared classes where (every hint is re-read from the graph).
- **Invalidation has two mechanisms, run for every index mutation.**
  `src/core/dependencies.zig` records unit-to-unit analysis dependencies and
  propagates them transitively with a bounded round count; propagation is now
  computed before a scan removes anything, because removal forgets declarations
  (it was computed after, which silently dropped a removed provider's
  dependents). A name that stayed unresolved read no provider, so
  `Index.Upkeep` also compares each changed unit's Java exports before and
  after, and reanalyzes the other units of any package whose exports changed
  that were read before the change. `addUnit`, `applyEdit`, and `removeUnit` run
  the same upkeep as `applyScan`. Work stays inside the changed package; tests
  measure it with invocation counts at two repository sizes.
- `Graph.checkInvariants` refuses a current relationship whose target entity is
  gone, but tolerates a stale one: a dependent whose own contents cannot be
  analyzed keeps its earlier cross-unit claim after the provider withdraws the
  target, and that claim no longer answers current queries.
- **A source unit's identity is not its path.** `model.Scope` is `repository` or
  `unit: SourceUnitId`, and `IdentityEvidence.scope` carries it, so renaming a
  file moves one property and leaves the unit, its contents, and every entity
  inside it alone. The source container entity has no name for the same reason:
  naming it by its path would make the container break identity on precisely the
  operation this design exists to survive. Path lookups go through the unit
  registry (`Snapshot.unitByPath`, `EntityFilter.path`), not through identity
  evidence. A rename opens a revision but does not touch `content_revision`, so
  it never makes a unit stale. Units tombstone on removal, so an identity is
  never handed to a later unit.
- How the model holds the constitutional distinctions. Entity ids are allocated
  by the graph and never derived from a range; ranges are `SourceEvidence` only.
  Every assertion carries a producer and a `Resolution` of `fact`, `unresolved`,
  or `approximate`, and construction rejects an unresolved target presented as a
  fact as well as a resolved target claiming its target is missing. `CONTAINS`
  records direct containment, including source ingestion's `repository -> file`
  claims. `DEFINES` records definition introduction only and is rejected when
  its target is not a `definition`. `calls` specializes `references`: one
  occurrence is recorded once and answers a reference query once. Language
  vocabulary stays in `ExtensionPayload`
  (`java.construct`, `clojure.form`); no Clojure or Java construct became a
  shared-core kind. `Graph` is mutable and `Snapshot` is the immutable published
  state a consumer observes; a snapshot taken before an edit keeps observing that
  state.
- Reconciliation is the only write path, on a first build and on every edit
  alike, so incrementality cannot quietly stop being exercised. Correspondence
  comes from `IdentityEvidence` (scope, language, role, name, signature,
  containment) and never from a frontend identifier or a position. A body edit
  preserves ids; a rename produces a `lost` identity event naming its replacement
  plus an unresolved identity-correspondence assertion, never a silent delete and
  create.
- Degradation stays distinguishable: `analysis_unavailable` (parser could not
  run), `analysis_failed` (source does not parse), `unsupported_construct`
  (outside the frontend's declared coverage, such as a Java field), and
  `confirmed_absence` (parsed, covered, nothing there). Diagnostics always
  describe the latest analysis attempt for a unit; the previous attempt's are
  withdrawn whether the new one succeeds or not.
- **Freshness is a separate axis from resolution**, and this is load-bearing.
  Each source unit records `content_revision` and `analysis_revision`, from
  which `UnitAnalysis` derives `pending`, `current`, or `stale`. A claim
  observed in a unit is current when it was recorded at or after that unit's
  `content_revision` — one rule for entities (`observed_revision`) and
  assertions (`revision`), with no special-casing by producer. `Index.applyEdit`
  performs the edit in its own revision before analysis runs, so an edit whose
  analysis fails leaves the unit `stale`: its earlier assertions are neither
  withdrawn (that would assert an absence nothing observed, and would destroy
  the identities a later successful analysis preserves) nor presented as current.
  Snapshot queries default to `.current`; stale claims stay recorded, stay
  attributed, and are reachable by asking for them.
- `Graph.addEntity` allocates an entity and asserts nothing. The producer that
  observed it records the existence claim with its own provenance and
  resolution, because allocating an entity and claiming it exists are different
  acts.
- Build prerequisites are local files, not services: pinned grammar sources from
  `./scripts/setup-tree-sitter-grammars.sh` and a tree-sitter runtime providing
  `tree_sitter/api.h` and `libtree-sitter.a`. `build.zig.zon` declares no
  dependencies; nothing is fetched at build or index time. A missing prerequisite
  fails `zig build` with a message naming the script and both override flags
  (`-Dgrammars-dir=`, `-Dtree-sitter-prefix=`).
- Git-hygiene scripts under `scripts/` and `scripts/git-hooks/` enforce
  attribution policy, memory freshness, and the constitution freeze seal.
  `.github/workflows/agent-attribution.yml` enforces attribution policy in CI.
- Toolchain installers under `scripts/` set up pinned language-analysis tools:
  JDT LS, SCIP Java/TypeScript, tree-sitter grammars, and TypeScript LSP, with
  their package manifest and Java helper. These are sources a future frontend
  can consume, not semidx's implementation stack.

## What Does Not Exist Yet

- No persistence. The graph is in memory and is rebuilt from source on every
  process start.
- No public contract surface: no HTTP, gRPC, CLI contract, `contracts/`
  schemas, or runtime mirrors. `semidx-dev` is a developer inspection command
  and nothing asserts against its output. `semidx-mcp` is an experimental local
  stdio consumer ([ADR 005](docs/adr/005_add_zig_frontend_and_local_mcp_preview.md))
  whose tool schemas may change; it publishes no semantic contract version and
  has no resources, prompts, pagination, subscriptions, or file watching.
- Cross-unit resolution beyond Java same-package top-level types: no Java
  imports, qualified names, nested classes, inheritance, classpath symbols, or
  interface/enum/record targets, and no Clojure namespace resolution. Those
  references stay designators. No file watching, no concurrency.
- No persistence of the measurement story: `publish` is linear in the graph,
  which is right for publishing per batch of edits and wrong for publishing per
  query. Changing it means changing what a snapshot is, which `SPEC.md` owns.
- No executable conformance suite and no capability matrix. The fixture evidence
  is scoped to two small files per language.
- No published semantic contract. The current core admission results accept
  `repository`, `file`, `definition`, `CONTAINS`, `DEFINES`, `REFERENCES`, and
  `CALLS` as unversioned implementation guidance only. `module` and `IMPORTS`
  are not admitted. Java and Clojure fixture coverage is not a claim of
  supported languages.
- No vectors, embeddings, RAG, or retrieval of any kind.

## Active Constraints And Known Gaps

- Ratification was performed on 2026-09-13, in its own commit, after the three
  post-distillation corrections and a final adversarial pass found no remaining
  identity-level conflict. The constitution is no longer correctable. Do not
  propose editing it, and do not treat a companion document as a way to
  reinterpret a clause.
- The constitution now intentionally freezes fewer things. Detailed mechanisms
  such as fingerprints, snapshot storage, revision models, fixture shapes,
  accuracy measurements, ADR procedure, and delivery sequencing live outside the
  immutable boundary.
- Local graph operation remains independent of external services. Source-derived
  outbound data is disabled by default and requires explicit destination/data
  opt-in, including for projections and diagnostics.
- Coverage, unsupported constructs, unavailable analysis, unresolved assertions,
  approximate evidence, and confirmed absence must remain visible to consumers.
- Freeze enforcement exists and is cryptographic.
  `scripts/check-constitution-freeze.sh` reads the status line from the version
  before the change: while DRAFT it requires a constitution commit to stand alone
  with at most `MEMORY.md`; once RATIFIED it pins the text to the SHA-256 seal in
  `scripts/constitution.freeze.sha256`. The sealed hash is
  `27c6cf1a87ce69bc72016a802e160c464562c0bd2681093fbd32ad27e1970975`.
- The expected hash always comes from `HEAD`'s seal, and the constitution is
  hashed from the staged blob in the git index. Regenerating the seal beside an
  edited constitution therefore does not authorise the edit, an unstaged
  experiment is not a violation, and a staged one cannot hide behind a clean file
  on disk. Deleting or renaming either file is refused, and the check fails
  closed on a missing hash tool, an unreadable status line, or an absent or
  malformed seal. The bypass `SCI_SKIP_CONSTITUTION_FREEZE=1` covers only §18's
  one exception, a mechanical repair that touches no sentence, which must
  regenerate the seal in the same commit.
- Memory freshness watches `ARCHITECTURE_CONSTITUTION.md`,
  `ARCHITECTURE_RATIONALE.md`, `CONFORMANCE.md`, `CORE.md`, `SPEC.md`,
  `GLOSSARY.md`, the root entry points, `docs/agent-policy/`, `scripts/`, and the
  working-document directories.
- No runtime conformance is claimed as a gate. `CONFORMANCE.md` now records which
  of its five first-slice properties the implementation supplies evidence for;
  none of its scenario families is adopted as an executable check.
- Known implementation limitations, in full, are in the Residual Risk sections of
  the progress logs (001, 002, 005, 003). The load-bearing ones: both frontends
  resolve by name within one source unit, with no imports, inheritance,
  overloads, macros, or local bindings, except Java same-package top-level types;
  that rule treats the indexed repository as one Java classpath, so two build
  modules sharing a package name are one package to it; renaming a *definition* is identity loss,
  while renaming a *file* with established correspondence is not, because scope
  is the unit; a file that moved and changed in the same rescan is still removal
  plus addition until stronger identity evidence exists; dependencies and package
  invalidation are coarse (a provider body edit rereads its dependents, an export
  change rereads its whole package); the unit table is append-only and never compacts; interned
  strings of removed entities and stale assertions are never reclaimed while the
  graph lives; and both `Snapshot` string borrowing and the default-current query
  rule are documented conventions rather than type-enforced boundaries.
- The constitution's §1 boundary is now stated once and consistently across
  `CONFORMANCE.md`, `GLOSSARY.md`, and `README.md`: approximate and text-derived
  mechanisms discover, rank, and render; only the graph establishes a program
  relationship. Keep any future retrieval work on that line.

## Near-Term Priorities

- **Plan 002 is closed.** The graph can now be built and maintained over a
  discovered repository tree, source-unit identity is separate from path, exact
  moves preserve the unit and entities inside it, one-unit edits reanalyze one
  unit at repository scale, and dependency propagation has a tested mechanism.
  Stage 5 deliberately took the ADR 003 rejected branch: no name-match
  assertions were added, so cross-unit references remain unresolved designators.
- **Plan 003 is closed.** Java same-package top-level type resolution is
  implemented, documented, verified, and reviewed with no confirmed findings
  ([report 003](docs/reports/003_java_package_type_resolution_progress.md)). It
  admitted no `module` or `IMPORTS` and widened no Clojure or general Java
  coverage. It did produce evidence those admission questions can use: a Java
  package was expressible as extension vocabulary plus an analyzer projection,
  with no shared-core kind.
- Next cross-unit work should again be one narrow, language-correct producer
  with its own requirement: Java single-type imports, or the multi-module
  classpath boundary the same-package rule currently ignores, are the nearest
  candidates. Each needs its own decision record; neither is implied by ADR 004.
- Source identity needs a stronger evidence story for common refactors where a
  file moves and changes in the same rescan. The current exact-content rule is
  intentionally conservative; future work should prefer explicit VCS/IDE move
  events or language-aware refactoring evidence over similarity presented as a
  fact.
- Settle storage and snapshot representation, which `SPEC.md` still lists as
  unspecified. The current `Snapshot` is a value that borrows from a live graph
  and copies the observable state per publish; persistence would change that
  contract, and so would a long-running process. Plan 002 measured the cost and
  explicitly did not act on it.
- Deepen frontend coverage only against stated risk, and report coverage through
  a capability matrix rather than by widening the fixtures quietly.
- Use [docs/design/001_project_roadmap.md](docs/design/001_project_roadmap.md)
  to check whether new plans move the project toward exact graph knowledge,
  better incremental local operation, useful local graph projections, or clearer
  evidence, contracts, and release discipline.
- Current open follow-ups are indexed in
  [docs/followups/README.md](docs/followups/README.md): Zig logical-negation
  calls, Zig empty-container grammar behavior, Java classpath boundaries, and
  release discipline for the local MCP preview.
- **Plan 004 is in progress: Stages 1–3 (the Zig frontend) are implemented and
  reviewed; Stage 3.5 fixed the review blocker; Stages 4–5 (the local MCP stdio
  preview, its dogfood run, and its documentation) are implemented and await
  review.** It onboards Zig as the next language
  frontend for dogfooding and then adds a local stdio MCP preview over published
  graph snapshots ([ADR 005](docs/adr/005_add_zig_frontend_and_local_mcp_preview.md),
  [plan 004](docs/plans/004_zig_frontend_and_mcp_preview.md),
  [report 004](docs/reports/004_zig_frontend_and_mcp_preview_progress.md)). The
  intended slice is narrow: `.zig` discovery, pinned local `tree-sitter-zig`,
  top-level Zig definitions, same-unit simple Zig calls, and graph-first MCP
  tools for health, repository map, definition lookup, references, context, and
  refresh. What exists now: `.zig` files are source units; the full lane
  compiles `tree-sitter-zig` pinned at `6479aa13`; named top-level `fn`
  declarations and top-level `const` declarations bound directly to a
  struct/enum/union/opaque expression are `function`/`container` definitions
  (`zig.construct`, `zig.container` extension labels, no signature in identity);
  a bare call in a covered function body is a `CALLS` fact only when the unit's
  top level declares that name once, as a covered function, and no parameter,
  local binding, capture, or `usingnamespace` could shadow it. Everything else —
  container members, other declarations, non-bare callees — is unsupported or
  unresolved. The pinned grammar parses an empty `struct {}` as an error, so such
  a unit reports `analysis_failed`. The same grammar parses `!helper()` as a call
  on the type-shaped callee `!helper`, so bare calls under logical negation stay
  unresolved and are undercounted. This is not a Stage 4 blocker because it does
  not create false facts, but Stage 4 must not repair it ad hoc while adding MCP;
  resolve it only in a Zig frontend follow-up with parser-node evidence and
  regression tests. `semidx-dev` over `src/` indexes all 20 units.
  The Stages 1–3 review found that `Graph.addAssertion` kept an unresolved
  target's designator as a slice of the frontend batch arena, which is freed
  after integration (latent for Java and Clojure too, exposed by the Zig
  dogfood run). The graph now interns it like every other assertion string, so
  a stored assertion borrows nothing from its producer; Stage 3.5 in report 004
  records the fix and its regression tests. Stage 4 was held until then.
  **The MCP preview exists** (`src/mcp/`, executable `semidx-mcp`,
  `zig build mcp -- --root <dir>`, `zig build test-mcp`). It scans the root at
  startup, publishes one snapshot, and answers every tool call from the snapshot
  published when the call arrives; `semidx_refresh` rescans, reconciles through
  `Index.applyScan`, and swaps in the next snapshot only after it is published,
  keeping the previous one on any failure. One dispatcher serves two eras: a
  request carrying `io.modelcontextprotocol/protocolVersion` = `2026-07-28` in
  `_meta` is served statelessly (`server/discover`, `tools/list`, `tools/call`;
  other versions get `-32022`), and a request without it is served under the
  `2025-06-18` lifecycle only after `initialize`. Modern responses advertise
  only `2026-07-28`; the legacy version is reachable only through
  `initialize`. Six tools — `semidx_health`, `semidx_repo_map`,
  `semidx_find_definitions`, `semidx_references`, `semidx_context`,
  `semidx_refresh` — render graph values only: ids, paths, ranges, kinds,
  relationships, and per claim its resolution, freshness, and producer, with
  `semantic_contract_version: null` and truncation markers on bounded lists.
  Names and designators are graph values and are returned; the only
  source-text field a snapshot carries, `SourceEvidence.text`, is rendered only
  under `--allow-evidence-text`, capped at 400 bytes per claim, and the server
  never reads unit contents into a result. Today every frontend records a name
  or designator as evidence text, not a body. stdout carries only protocol
  lines; the stdio smoke test fails on any other line, on trailing stdout, or
  on a non-zero exit, and was checked by mutation. Cross-file Zig calls such as
  `protocol.writeString(...)` stay unresolved designators, so `semidx_references`
  shows only same-unit Zig callers.
  It explicitly excludes a published semantic contract, persistence, HTTP,
  remote services, resources/prompts, source text by default, Zig imports,
  namespace/container lookup, comptime semantics, methods, fields, local
  variables, and cross-unit Zig resolution. Execution advice lives in the plan's
  [Execution Recommendations](docs/plans/004_zig_frontend_and_mcp_preview.md#execution-recommendations):
  a fresh session split at the Stage 3 / Stage 4 boundary with a review between
  the sessions, Claude Opus 5 for Stages 1–4, one-time network access for the
  grammar fetch, and reading the `2026-07-28` MCP specification rather than
  relying on model memory.
- `scripts/git-hooks/pre-push` still carries an inert block that refreshes
  `docs/code-context.md` through a Clojure alias when `deps.edn` exists. Both
  files went with the removed implementation, so the block never runs; remove it
  when the rebuilt stack settles what replaces it.
