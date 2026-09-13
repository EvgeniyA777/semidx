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
- `CORE.md` is a **draft candidate roster**. No kind or roster version is
  accepted or published yet. Open `module` semantics block `IMPORTS`; they no
  longer block `DEFINES`, whose container endpoint now ranges over whichever
  container kinds are admitted, so basic containment does not wait on `module`.
  Textual-inclusion coverage and admission fixtures remain unresolved.
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
  specify, and no kind in CORE is admitted. `CONFORMANCE.md`,
  `ARCHITECTURE_RATIONALE.md`, and `GLOSSARY.md` are `active` because their text
  is settled — a specification is not a draft merely because the work it
  describes has not started. `ARCHITECTURE_CONSTITUTION.md` carries no
  frontmatter by rule: its status line is the single place its state is
  declared.
- `RULES.md` remains the single source of truth for agent process rules. It is
  language-agnostic because no implementation stack has been selected. Its MCP
  sections are scoped explicitly as development tooling configured outside this
  repository, not as the rebuilt public API. `RULES.md`, `AGENTS.md`, and
  `CLAUDE.md` no longer offer "documented and justified deviation" as a route
  around the constitution: inside the boundary, decisions are documented; outside
  it, §18 requires a fork. Two
  claims left over from the removed implementation were deleted: a language
  roster attributed to the constitution, and staged retrieval as the canonical
  public contract with MCP/library/HTTP/gRPC parity. Language coverage and
  public contracts are open `SPEC.md` requirements. The repository skills under
  `.agents/skills/` lost the same layer (CanonicalFactKey, provider authority,
  language lanes, MCP wire shape, a named PostgreSQL path) and now refer to the
  properties the constitution protects.
- `docs/agent-policy/{documentation,git,testing}.md` owns detailed cross-cutting
  process. Documentation policy locates architectural decision-test answers in
  repository ADRs and records the current ownership of constitution, rationale,
  requirements, core roster, and conformance.
- There are no ADRs. `docs/adr/` is deliberately empty until implementation
  starts: the pre-implementation architecture record lives in the documents
  themselves, and drafting history lives in `git log`. The reasoning for the
  distillation is in [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md).
  ADRs begin with the decisions that accompany real implementation work.
- `README.md` is a minimal human entry point. It opens with a status line
  saying the repository is design rather than implementation, states the
  capabilities as intended behavior, and links to the architecture document set.
  There is nothing to run yet.
- Git-hygiene scripts under `scripts/` and `scripts/git-hooks/` enforce
  attribution policy, memory freshness, and the constitution freeze seal.
  `.github/workflows/agent-attribution.yml` enforces attribution policy in CI.
- Toolchain installers under `scripts/` set up pinned language-analysis tools:
  JDT LS, SCIP Java/TypeScript, tree-sitter grammars, and TypeScript LSP, with
  their package manifest and Java helper. These are sources a future frontend
  can consume, not semidx's implementation stack.

## What Does Not Exist Yet

- No graph implementation, test suite, build/dependency manifest, fixed
  implementation language, or source layout.
- No `contracts/` schemas, runtime mirrors, or executable conformance fixtures.
- No accepted core roster, published semantic contract, or published capability
  matrix. Language examples in documentation are not claims of implemented
  support.

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
- No runtime conformance is claimed. The specifications describe future checks;
  the current verification is documentation consistency, references, and diff
  hygiene.
- The constitution's §1 boundary is now stated once and consistently across
  `CONFORMANCE.md`, `GLOSSARY.md`, and `README.md`: approximate and text-derived
  mechanisms discover, rank, and render; only the graph establishes a program
  relationship. Keep any future retrieval work on that line.

## Near-Term Priorities

- Choose the implementation stack and take the decisions that block a first
  vertical slice. Nothing in the document set contradicts itself any more; what
  remains open is decisions, not text.
- Select the implementation stack under the local-operation constraint, then
  update `RULES.md` with actual build tools, source layout, verification
  commands, editing tools, and service requirements.
- Resolve candidate admission dependencies in `CORE.md`, choose initial
  coverage, and supply conformance evidence. Complete the dependent requirements
  and public contracts through `SPEC.md` before publication or an execution
  plan that relies on them.
- `scripts/git-hooks/pre-push` still carries an inert block that refreshes
  `docs/code-context.md` through a Clojure alias when `deps.edn` exists. Both
  files went with the removed implementation, so the block never runs; remove it
  when the rebuilt stack settles what replaces it.
