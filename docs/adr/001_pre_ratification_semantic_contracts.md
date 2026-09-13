---
title: "Pre-ratification semantic contracts"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# Pre-ratification Semantic Contracts

## Context

The constitution is DRAFT. Its review found that moving the core roster to a
separate document did not make mistakes repairable while an unconditional
ratchet still prohibited removal and redefinition. It also exposed conflicting
coverage obligations, unresolved container identity, and a conflation of a
relationship's specificity with its resolution level.

This decision records the corrections to the draft and their architectural scope.
It does not ratify the constitution. The constitution owns the resulting
constraints; this record owns their rationale and the architectural decision
test. The final document roles are recorded in the
[documentation policy](../agent-policy/documentation.md).

## Decisions And Rationale

1. Replace the unconditional core ratchet with protection of published meaning.
   Draft candidates remain editable. Published contracts evolve explicitly with
   versions and migrations, so an erroneous admission can be corrected without
   silently changing what an existing consumer reads.
2. Retain a mandatory common model and an existence/reference floor, while
   distinguishing schema conformance from extraction coverage. Unavailable
   coverage is reported. Pairwise mappings enrich queries without rewriting
   language-specific assertions. This deliberately revises the former OQ-1
   decision that all cross-language queries use the core alone: a shared
   extension between two languages need not burden every other language.
3. Include source containers in the constitutional meaning of entity. A
   repository and a file represent real source organization, not arbitrary
   retrieval chunks. Their assertions may be produced by source ingestion;
   requiring a language frontend to invent them would misstate provenance.
4. Permit facts established by exact system resolution of frontend assertions.
   Evidence and the resolution method remain attributable. A confirmed general
   reference is a fact even when a more specific relationship is unknown.
5. Make source-data transmission opt-in, and require reproducibility under
   fixed analysis inputs. These are consumer guarantees distinct from local
   operability and snapshot consistency. Identity history is an analysis input;
   identical source alone does not imply identical historical correspondence.
6. Require independently fingerprinted interface and implementation aspects
   when both exist. Make vector-removal checks compare graph queries at fixed
   inputs. These make existing invariants testable without prescribing storage
   or language-specific fingerprint formats.
7. Keep delivery order and contract lifecycle in the companion requirements
   document. Record architectural decision-test answers in repository ADRs.
   Questions left to implementation after ratification remain subject to every
   constitutional clause; an ADR cannot reinterpret or override one.

## Architectural Decision Test

Answers correspond to constitution section 15.

1. **Entities and relationships:** source containers are explicitly entities;
   exact derived relationships and declared extension mappings are permitted.
   Candidate kinds and admission dependencies are recorded in the core roster.
2. **Source of truth or view:** identity, resolution, and fingerprints strengthen
   the graph. Extension mappings are query-time views of preserved assertions.
3. **Identity:** fixed analysis inputs reproduce identities; declared frontend
   limitations and recorded breaks bound the permitted exceptions.
4. **Incrementality:** aspect fingerprints and consistent observations remain
   mandatory. Incremental-work checks account for the affected dependency region;
   a local edit with global effects is not mistaken for unnecessary rebuilding.
5. **Knowledge categories:** facts, partially resolved assertions, and
   approximate assertions remain separate, including exact system derivations.
6. **Product drift:** no consumer becomes authoritative; network and vector
   services remain optional for building and querying the graph.
7. **Future impact analysis:** interface/implementation separation and preserved
   provenance retain the information required for fine-grained dependencies.
8. **Attribution:** source-ingestion assertions, frontend assertions, and exact
   derivations retain their actual producers and resolution evidence.
9. **Open constitutional questions:** the container, core-evolution, coverage,
   resolution, privacy, and reproducibility questions are settled by this draft
   revision. Remaining module and import admission questions are subordinate
   contract work; they cannot be resolved by changing constitutional meanings.

## Review Disposition And Verification

| Original review item | Disposition | Result |
| --- | --- | --- |
| 1. Frozen core catalogue | Fixed | Constitution section 4 protects published meaning; SPEC owns explicit versioning and migration |
| 2. Cross-language ceiling | Fixed | Declared query-time extension mappings are permitted with provenance |
| 3. Source-data privacy | Fixed | Section 6 and Invariant 14 require opt-in and default-deny transmission |
| 4. Reproducibility | Fixed | Section 5 fixes analysis inputs and result ordering; Invariants 9 and 11 provide checks |
| 5. Exact system resolution | Fixed | Defined Terms and section 11 allow evidenced derivations without requiring them in the first frontend |
| 6. Identity exception | Fixed | Producer limitations are published before analysis; runtime failures are not exceptions |
| 7. Fixed requirements filename | Fixed | Constitution names document roles; documentation policy owns file mapping |
| 8. Fingerprint floor | Fixed | Section 7 separates interface and implementation when both exist |
| 9. Post-ratification questions | Fixed | Sections 15 and 17 distinguish draft questions from later subordinate decisions |
| 10. Decision-test artifact | Fixed | Invariant 10 requires an ADR; documentation policy defines location and change linkage |
| 11. Frozen delivery sequence | Fixed | Section 14 preserves consumer direction; SPEC owns proposed delivery order |
| 12. Category names | Fixed | Section 11 consistently names facts and the two assertion categories |
| 13. Hybrid query boundary | Fixed | Invariant 4 compares graph queries at fixed inputs and permits discovery differences |
| 14. Diagram and wording | Fixed | Compilation consumer label, explicit meaning of exactness, and normative-word description are aligned |

The follow-up findings are covered by the removal of the unconditional ratchet,
the distinction between model conformance and coverage, transitive admission
blocking, the distinction between specificity and resolution, and synchronized
document ownership and memory. Container identity is settled by the explicit
Defined Terms change. Roster acceptance remains pending, not presumed by this ADR.

Verification passed: final document consistency review; `git diff --check`;
and a read-only Ruby check of eight documents covering 15 local links,
frontmatter, English text, code fences, 18 sections, 14 invariants with their
four parts, five defined terms, nine ADR answers, and DRAFT status. Runtime
conformance remains unverified: there is no semantic-graph implementation or
fixture suite. Intended behavior is not presented as measured accuracy.
