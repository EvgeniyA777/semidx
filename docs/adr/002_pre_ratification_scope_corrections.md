---
title: "Pre-ratification scope corrections"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# Pre-ratification Scope Corrections

## Context

A second review of the DRAFT constitution, conducted against the text rather
than against the disposition table of
[ADR 001](001_pre_ratification_semantic_contracts.md), found four clauses whose
scope did not match their intent. One is an internal contradiction; three are
readings that a frozen document would make permanent.

These are corrections to scope and wording. No constraint is relaxed and no
invariant is removed. The constitution remains DRAFT; this record does not
ratify it.

## Decisions And Rationale

1. **Invariant 1 constrains semantic answers, not every path to source text.**
   Section 8 permits lexical search, BM25, and grep as retrieval mechanisms, and
   section 8 already separates discovering candidates from establishing program
   relationships. Invariant 1 did not carry that separation: its implications
   forbade any capability attached to a text-derived index, and its detection
   forbade consumer modules from depending on raw source readers. Rendering a
   located snippet and searching comment text were therefore violations, while
   section 8 permitted them. A frozen document that contradicts itself licenses
   a later reader to choose the convenient clause, which is the silent
   reinterpretation section 18 exists to prevent. The invariant now forbids a
   semantic answer that bypasses the graph, and permits discovery and rendering.

2. **Section 9 illustrates consumer questions instead of mandating a feature
   list.** "Agents must be able to ask questions such as" turned examples,
   including test linkage and documentation linkage, into obligations. Those are
   capabilities, not project identity, and they fail the admission test in
   Scope. The retained obligation is the one that is constitutional: a
   consumer's questions are expressed over entities and relationships rather
   than over text. Which questions a version answers is a concrete requirement.

3. **The architectural decision test has one scope, defined once.** Section 15
   applied to a "major feature or dependency" while Invariant 10 treated any
   merged feature without recorded answers as a violation. The narrower reading
   left "major" undefined; the wider one made the invariant routinely
   unsatisfiable, and an invariant nobody can satisfy constrains nothing. The
   scope is now stated once in section 15, by effect rather than by size: a
   change to what the graph contains, how it is maintained, or what a consumer
   can rely on. Invariant 10 refers to that scope instead of restating one.

4. **Section 13 forbids the center, not the capability.** "`semidx` is not
   primarily" followed by "It must never become them" left it unresolved
   whether the prohibition inherited the qualifier. Read strictly, an embedded
   compilation consumer was forbidden, which contradicts section 16's future
   compilation tooling and the compilation consumer in section 3. The section
   now permits every listed system as a consumer or projection and forbids it as
   the center.

## Architectural Decision Test

Answers correspond to constitution section 15.

1. **Entities and relationships:** none added. The corrections change which
   capabilities may attach to the graph and how the decision test is scoped.
2. **Source of truth or view:** the graph remains the source of truth.
   Correction 1 makes explicit that text-derived indexes are views that discover
   candidates and never establish relationships.
3. **Identity:** unaffected.
4. **Incrementality:** unaffected.
5. **Knowledge categories:** unaffected. Correction 1 reinforces that an
   approximate retrieval result is not an established relationship.
6. **Product drift:** correction 4 states the drift prohibition more precisely
   than the previous wording, which forbade capabilities rather than centers.
   Correction 1 keeps grep and lexical search as projections under section 8.
7. **Future impact analysis:** unaffected.
8. **Attribution:** unaffected.
9. **Open constitutional questions:** section 17 is empty and stays empty. These
   are corrections to draft text, not answers to recorded questions.

## Disposition

| Review item | Disposition | Result |
| --- | --- | --- |
| Section 8 contradicts Invariant 1 | Fixed | Invariant 1 constrains semantic answers; discovery and rendering are permitted |
| Section 9 mandates example queries | Fixed | Examples are illustrative; the expressed-over-entities obligation is retained |
| Decision-test scope mismatch | Fixed | One scope, defined in section 15 and referenced by Invariant 10 |
| Section 13 qualifier ambiguity | Fixed | Listed systems are permitted as consumers and forbidden as the center |

Two further review items were considered and deliberately not changed. The
unconditional freeze in section 18 stands: an amendment procedure would be
performed by the same party that wants the amendment, and a second ratified
version retires the first product without the visibility a fork provides. The
fingerprint wording in section 7 stands: its normative content is independent
per-aspect change indicators, and "digest" appears only in the descriptive
glossary.

Ratification remains deliberate and has not been performed. The constitution is
a ratification candidate whose remaining risk is that its constraints have not
met an implementation.
