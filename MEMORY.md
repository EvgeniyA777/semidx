# Project Memory

Current implementation reality: what exists in this repository right now and
why. This is not a changelog of removed implementation; see `git log`.

## What Exists And Why

- `ARCHITECTURE_CONSTITUTION.md` remains **DRAFT, not ratified**. It defines
  product constraints and has fourteen invariants, each with Statement,
  Rationale, Implications, and Detection. Most checks require a future
  implementation; process records can be inspected now. An empty section 17
  records the absence of unresolved constitutional questions, not approval to
  ratify. Ratification is a separate deliberate act under section 18.
- The draft's Defined Terms still owns exactly five terms: entity, node,
  relationship, assertion, and fact. Source containers now fall within entity;
  source ingestion is their evidence source. Facts may be established by source
  ingestion about source organization, frontend analysis about program meaning,
  or exact system resolution with preserved evidence. Heuristics and unresolved
  assertions do not acquire fact status through confidence or specificity.
- The shared core is governed by requirements in constitution section 4, not a
  frozen list. Published meaning is protected by explicit contract versions and
  migrations; draft candidates remain editable. Coverage can differ across
  frontends without changing the common model. Pairwise extension mappings are
  applied at query time and preserve attribution.
- `CORE.md` is a **draft candidate roster**. No kind or roster version is
  accepted or published yet. Open `module` semantics block dependent
  `IMPORTS` and the current `DEFINES` candidate. Textual-inclusion coverage
  and admission fixtures also remain unresolved. Container/entity status is
  settled constitutionally; the proposed reference-query contract counts a call
  occurrence once even if storage records both general and specialized relations.
- `SPEC.md` now exists as a **draft requirements entry point**, including core
  contract lifecycle, conformance scenarios, outstanding specification work, and
  proposed delivery direction. It is not a complete implementation plan or a
  published runtime contract.
- `GLOSSARY.md` holds descriptive vocabulary and points to the canonical
  [document ownership policy](docs/agent-policy/documentation.md).
- `RULES.md` remains the single source of truth for agent process rules. It is
  language-agnostic because no implementation stack has been selected.
- `docs/agent-policy/{documentation,git,testing}.md` owns detailed cross-cutting
  process. Documentation policy now locates architectural decision-test answers
  in repository ADRs and requires a link from the change.
- [ADR 001](docs/adr/001_pre_ratification_semantic_contracts.md) records the
  rationale and section 15 answers for the pre-ratification corrections,
  including the deliberate revision of former OQ-1 and the source-container
  decision. It does not ratify the constitution or accept the candidate roster.
- [ADR 002](docs/adr/002_pre_ratification_scope_corrections.md) records a second
  round of draft corrections, all of scope rather than of substance: Invariant 1
  now constrains semantic answers instead of every path to source text, which
  removes its contradiction with the retrieval mechanisms section 8 permits;
  section 9 illustrates consumer questions instead of mandating test and
  documentation linkage; the architectural decision test has one scope, stated
  once in section 15 and referenced by Invariant 10; and section 13 forbids each
  listed system as the center while permitting it as a consumer. It also records
  two items deliberately left unchanged — the unconditional freeze in section 18
  and the fingerprint wording in section 7.
- `.agents/skills/` holds task procedures for exploration, review, delivery,
  testing, documentation rules, and progress logs.
- `README.md` remains a minimal human entry point describing semidx and
  pointing to the constitution, plus the license. There is nothing to run yet.
- Git-hygiene scripts under `scripts/` and `scripts/git-hooks/` enforce
  attribution policy, memory freshness, and isolated constitution commits.
  `.github/workflows/agent-attribution.yml` enforces attribution policy in CI.
- Toolchain installers under `scripts/` set up pinned language-analysis tools:
  JDT LS, SCIP Java/TypeScript, tree-sitter grammars, and TypeScript LSP, with
  their package manifest and Java helper. These are sources a future frontend
  can consume, not semidx's implementation stack.

## What Does Not Exist Yet

- No graph implementation, test suite, build/dependency manifest, or fixed
  implementation language and source layout.
- No `contracts/` schemas, runtime mirrors, or executable conformance fixtures.
  The draft specifications name the work needed before publication.
- No accepted core roster or published capability matrix. Language examples in
  documentation are not claims of implemented support.

## Active Constraints And Known Gaps

- The reviewed corrections are incorporated in the DRAFT. Section 17 is empty;
  ratification has not been performed. Remaining roster and specification work
  is explicit and must not be mistaken for completed implementation.
- Local graph operation remains independent of external services. A shared
  graph service is restricted to a locally reproducible baseline. Source-derived
  outbound data is disabled by default and requires explicit destination/data
  opt-in, including for projections and diagnostics (constitution section 6).
- Reproducibility is defined for fixed analysis inputs, including dependencies,
  producer/contract versions, and incremental history. Ordered graph results
  have deterministic order. Producer identity incapacity is declared before
  analysis; a runtime failure cannot excuse identity churn (section 5).
- Interface and implementation fingerprints are independent when both aspects
  exist. Vector-removal checks compare graph answers at fixed inputs, while
  candidate discovery may differ (section 7 and Invariant 4).
- Freeze enforcement is deliberately deferred until after ratification.
  `scripts/check-constitution-amendment.sh` still enforces the useful boundary
  that constitution changes may share a commit only with `MEMORY.md`. Its
  obsolete amendment terminology is to be corrected with post-ratification
  freeze enforcement, not by disabling the existing check.
- Memory freshness currently watches `ARCHITECTURE_CONSTITUTION.md` and
  `SPEC.md`, but not `CORE.md`. Updates to core definitions still fall under
  the memory update rule in `RULES.md`; extending mechanical coverage remains
  process work.
- No runtime conformance is claimed. The specifications describe future checks;
  the current verification is documentation consistency, references, and diff
  hygiene.

## Near-Term Priorities

- Treat the constitution as a ratification candidate rather than as work
  pending completion. Section 17 is empty, so nothing blocks ratification, but
  nothing forces it either: the document already binds work through `RULES.md`
  while DRAFT keeps it correctable, so the only thing ratification adds today is
  the irreversibility. The recorded reason to wait is that no constraint has met
  an implementation. A vertical slice that exercises identity, incremental
  update, and consistent snapshots is the intended evidence, and it needs two
  frontends of different shape, because a single language cannot exercise
  Invariant 8 or the core/extension split at all. After ratification, implement
  freeze enforcement as required by `RULES.md`.
- Select the implementation stack under the local-operation constraint, then
  update `RULES.md` with actual build tools, source layout, verification
  commands, editing tools, and service requirements.
- Resolve candidate admission dependencies in `CORE.md`, choose initial
  coverage, and supply conformance evidence. Complete the dependent requirements
  and public contracts through `SPEC.md` before publication or an execution
  plan that relies on them.
