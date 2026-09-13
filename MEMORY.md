# Project Memory

Current implementation reality: what exists in this repository right now and
why. This is not a changelog of removed implementation; see `git log`.

## What Exists And Why

- `ARCHITECTURE_CONSTITUTION.md` remains **DRAFT, not ratified**. It has been
  distilled to product identity rather than conformance mechanics: semantic
  graph as the product, entity nodes rather than chunks, exact/unresolved/
  approximate separation, stable identity, incrementality with consistent
  observation, language frontends plus a common core, consumer independence, and
  local operation without mandatory source-data transmission.
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
  accepted or published yet. Open `module` semantics block dependent
  `IMPORTS` and the current `DEFINES` candidate. Textual-inclusion coverage and
  admission fixtures also remain unresolved.
- `SPEC.md` is a **draft requirements entry point**. It owns changing
  requirements, semantic contract lifecycle, publication and migration rules,
  outstanding specification work, and proposed delivery direction.
- `GLOSSARY.md` holds descriptive vocabulary and points to the canonical
  [document ownership policy](docs/agent-policy/documentation.md).
- `RULES.md` remains the single source of truth for agent process rules. It is
  language-agnostic because no implementation stack has been selected.
- `docs/agent-policy/{documentation,git,testing}.md` owns detailed cross-cutting
  process. Documentation policy locates architectural decision-test answers in
  repository ADRs and records the current ownership of constitution, rationale,
  requirements, core roster, and conformance.
- [ADR 001](docs/adr/001_constitution_distillation.md) records the decision to
  distill the constitution and move detailed engineering protection into
  rationale, requirements, and conformance documents.
- `README.md` is a minimal human entry point describing semidx and linking to
  the architecture document set. There is nothing to run yet.
- Git-hygiene scripts under `scripts/` and `scripts/git-hooks/` enforce
  attribution policy, memory freshness, and isolated constitution commits.
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

- Ratification has not been performed. The DRAFT status keeps the constitution
  correctable until an explicit ratification commit changes the status line.
- The constitution now intentionally freezes fewer things. Detailed mechanisms
  such as fingerprints, snapshot storage, revision models, fixture shapes,
  accuracy measurements, ADR procedure, and delivery sequencing live outside the
  immutable boundary.
- Local graph operation remains independent of external services. Source-derived
  outbound data is disabled by default and requires explicit destination/data
  opt-in, including for projections and diagnostics.
- Coverage, unsupported constructs, unavailable analysis, unresolved assertions,
  approximate evidence, and confirmed absence must remain visible to consumers.
- Freeze enforcement is deliberately deferred until after ratification.
  `scripts/check-constitution-amendment.sh` still enforces the useful boundary
  that constitution changes may share a commit only with `MEMORY.md`. Its
  obsolete amendment terminology is to be corrected with post-ratification
  freeze enforcement, not by disabling the existing check.
- Memory freshness currently watches `ARCHITECTURE_CONSTITUTION.md` and
  `SPEC.md`, but not `CORE.md`, `ARCHITECTURE_RATIONALE.md`, or
  `CONFORMANCE.md`. Updates to those documents still fall under the memory
  update rule in `RULES.md`; extending mechanical coverage remains process work.
- No runtime conformance is claimed. The specifications describe future checks;
  the current verification is documentation consistency, references, and diff
  hygiene.

## Near-Term Priorities

- Review the distilled constitution as the ratification candidate. The key
  question is no longer whether every important mechanism is listed, but whether
  every listed constraint really defines product identity.
- Select the implementation stack under the local-operation constraint, then
  update `RULES.md` with actual build tools, source layout, verification
  commands, editing tools, and service requirements.
- Resolve candidate admission dependencies in `CORE.md`, choose initial
  coverage, and supply conformance evidence. Complete the dependent requirements
  and public contracts through `SPEC.md` before publication or an execution
  plan that relies on them.
