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
  runs 161 lines. Its Project Context section now records the real build
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
  `zig build run`), and tooling policy carries a Zig addendum naming which probe
  belongs to which edit. Documentation policy owns ownership, filenames,
  frontmatter, lifecycle, the ADR procedure, progress logs, and the Plan
  Readiness Gate; git policy owns hooks, command ordering, commit and push rules,
  and both the attribution and constitution-freeze enforcement; testing policy
  owns risk-based verification and local services; tooling policy owns MCP-first
  retrieval, code reading, and editing probes, and scopes the MCP sections as
  development tooling configured outside this repository rather than the rebuilt
  public API.
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
  measured behavior, it links to the architecture document set, and it names the
  three commands that run the slice.
- **The first Zig vertical slice is implemented.** `docs/plans/001_zig_vertical_slice.md`
  is executed and closed; `docs/reports/001_zig_vertical_slice_progress.md`
  carries the stage outcomes, exact verification commands, review findings,
  skipped checks, and residual risk.
  `docs/reports/002_slice_freshness_followup.md` records three defects a review
  found afterwards and how they were fixed.
  `docs/reports/003_core_admission_review.md` records the first core admission
  review, and `docs/reports/004_defines_contains_split.md` records the
  `CONTAINS` / `DEFINES` split that resolved the first admission blocker. Read
  these reports before extending the implementation.
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
- No public surface: no MCP, HTTP, gRPC, CLI contract, `contracts/` schemas, or
  runtime mirrors. `semidx-dev` is a developer inspection command and nothing
  asserts against its output.
- No repository-scale ingestion: no source discovery, no cross-unit assertions,
  no invalidation across units, no file watching, no concurrency.
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
  both progress logs. The load-bearing ones: both frontends resolve by name
  within one source unit, with no imports, inheritance, overloads, macros, or
  local bindings; a rename and a file rename are both identity loss because the
  scope is the unit path; interned strings of removed entities and stale
  assertions are never reclaimed while the graph lives; freshness is tracked per
  unit, so cross-unit invalidation is undecided and must be settled before any
  cross-unit assertion exists; and both `Snapshot` string borrowing and the
  default-current query rule are documented conventions rather than type-enforced
  boundaries.
- The constitution's §1 boundary is now stated once and consistently across
  `CONFORMANCE.md`, `GLOSSARY.md`, and `README.md`: approximate and text-derived
  mechanisms discover, rank, and render; only the graph establishes a program
  relationship. Keep any future retrieval work on that line.

## Near-Term Priorities

- **The active plan is `docs/plans/002_repository_scale_ingestion.md`**, with
  companion log `docs/reports/005_repository_scale_ingestion_progress.md`. It has
  passed the Plan Readiness Gate and is ready to execute, starting at Stage 1.
  It takes the implementation to repository scale: source discovery, a
  source-unit registry whose identity is not a path, rename-surviving identity,
  measured affected-region reanalysis, and a dependency mechanism invalidation
  can act on.
- That track was chosen over `module` / `IMPORTS` admission deliberately. The two
  blocked candidates need evidence that a cross-unit availability question is
  answerable and that availability changes invalidate what depended on them; with
  every reference resolving inside its own unit, none of that is observable, so
  admitting them now would admit a paper model. Plan 002 does not admit either
  kind and says so in its non-scope.
- Settle storage and snapshot representation, which `SPEC.md` still lists as
  unspecified. The current `Snapshot` is a value that borrows from a live graph
  and copies the observable state per publish; persistence would change that
  contract, and so would a long-running process. Plan 002 measures the cost and
  explicitly does not act on it.
- Deepen frontend coverage only against stated risk, and report coverage through
  a capability matrix rather than by widening the fixtures quietly.
- `scripts/git-hooks/pre-push` still carries an inert block that refreshes
  `docs/code-context.md` through a Clojure alias when `deps.edn` exists. Both
  files went with the removed implementation, so the block never runs; remove it
  when the rebuilt stack settles what replaces it.
