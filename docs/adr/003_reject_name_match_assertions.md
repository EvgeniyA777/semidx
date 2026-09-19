---
title: "Reject repository-wide name matching as graph assertions"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 003: Reject Repository-Wide Name Matching As Graph Assertions

## Feature Or Dependency

Every reference in the graph resolves inside its own source unit or stays a
designator. `fixtures/repository-scale/` makes that visible: `Greeter` names the
type `Helper`, `Helper` is declared one unit away, and the graph records an
unresolved designator.

A cheap way to close that gap is to match the designator against definitions
elsewhere in the indexed source tree, and record the match as an assertion whose
resolution is `approximate` rather than `fact`. That is what
[plan 002](../plans/002_repository_scale_ingestion.md) Stage 5 was written to
decide before implementing, because it sits between two constitutional clauses.

The question: may a repository-wide unique-name match be recorded as an
assertion in the graph, given that
[§1](../../ARCHITECTURE_CONSTITUTION.md#1-semantic-graph-is-the-product) forbids
an approximate mechanism from establishing a program relationship while
[§3](../../ARCHITECTURE_CONSTITUTION.md#3-exact-unresolved-and-approximate-knowledge-stay-distinct)
provides the approximate category and requires it to stay distinct from fact?

## Decision

**No.** A name match across source units is not recorded as an assertion, in any
resolution category. A reference whose target is not resolved by the analyzed
unit stays an unresolved designator with its explanation.

This is a decision about what may enter the graph. It does not forbid a future
projection from offering name-matched candidates, and it does not forbid a
frontend from resolving across units when it does so by the language's own rules.

## Rationale

### §1 Constrains The Producer, Not The Label

§1 permits a text-derived or approximate mechanism to "discover candidates, rank
them, and render located source", and forbids it to "establish a program
relationship".

A repository-wide name match is text-derived: the relationship does not exist
until the matcher invents it, and nothing but a string comparison stands behind
it. Recording it as `approximate` changes how the claim is *presented*. §1
constrains what *produced* it. A claim that would not exist without a text match
is established by a text match whatever label it carries.

### The Rationale Document States The Intended Reading

[ARCHITECTURE_RATIONALE.md](../../ARCHITECTURE_RATIONALE.md), under "Why
Exactness Is A Product Claim":

> Approximate retrieval belongs in projections. It may discover candidates, rank
> results, or connect related material, but it must not establish program
> relationships.

"Belongs in projections" is the disposition for this mechanism. The rationale is
not normative and cannot add obligations, but where a clause admits two readings
it records which one the clause was written for.

### The Same Section Prescribes The Alternative

> A frontend may know that a call-like reference exists while the target is
> unresolved. Dropping that assertion loses useful information. Promoting it to a
> fact makes the graph false. Keeping a separate unresolved category preserves
> both honesty and usefulness.

That is the case at hand, and the answer is the unresolved category — which is
what the implementation already does. The gap this decision declines to close is
not an omission; it is the category working.

### What §3's Approximate Category Is Actually For

Rejecting name matching does not make `approximate` dead vocabulary. It
distinguishes two things that look alike:

- **Language analysis that genuinely computes an approximate result.** A dispatch
  analysis narrowing a virtual call to a candidate set, a partial overload
  resolution, a points-to analysis with a confidence. These are producers
  reasoning about program meaning, and their output is approximate because the
  program is.
- **Retrieval standing in for analysis that was not performed.** A name match is
  not an approximate answer to "what does this reference"; it is a different
  question — "what else is called this" — recorded in the first question's slot.

§3's category is for the first. The slice has no producer of the first kind, and
this decision does not manufacture one. `Snapshot.countApproximateAssertions`
stays at zero, honestly, until a producer earns it.

### What Would Be Legitimate

An unqualified type name in a Java file resolves to a type in the same package by
Java's scoping rules, not by coincidence of spelling. A frontend implementing
those rules establishes a fact, and its fact depends on what that package
declares. The difference between that and a name match is not accuracy — both may
give the same answer here — but whether the rule comes from the language or from
convenience.

That work needs a common meaning for the unit of organization a name resolves
within, which is the blocked `module` candidate in
[CORE.md](../../CORE.md#admission-status), and plan 002 places both language
resolution and `module` admission outside its scope. So cross-unit resolution is
not merely deferred by this decision; it is waiting on an admission this project
has not made.

### The Practical Argument, Which Did Not Decide It

Had the answer been yes, approximate assertions with entity targets would be
indistinguishable from facts to any traversal that does not filter on resolution
— unlike unresolved assertions, whose designator targets make them structurally
distinct. Keeping the distinction real would have required changing the default
of every relationship query, the way freshness already did.

That is a reason to be careful, not a reason to refuse, and it is recorded here
so the decision is not mistaken for a convenience.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** This is the clause the decision turns
   on. Keeping text-derived matches out of the graph keeps every relationship in
   it established by something that analyzed the program.
2. **Nodes as entities, not chunks.** Unaffected. No node is created or removed.
3. **Facts, unresolved, and approximate stay distinct.** Strengthened. The
   approximate category keeps a meaning — producers that genuinely compute
   approximate results — rather than becoming the place uncertain retrieval is
   filed.
4. **Stable semantic identity.** Unaffected.
5. **Incrementality and consistent observation.** Unaffected by the rejection.
   The dependency mechanism built alongside it exists precisely so that a future
   legitimate cross-unit fact does not require retrofitting invalidation.
6. **Language frontends preserve meaning.** Supported. A cross-unit reference
   will be resolved by a frontend applying its language's scoping rules, not by
   a shared matcher applying none.
7. **Consumers do not define the model.** Supported. The pressure to record a
   match came from wanting cross-unit edges to exist for consumers, which is the
   direction §7 rules out.
8. **Local operation without mandatory source-data transmission.** Unaffected.

## Consequences

- Cross-unit references stay unresolved. `fixtures/repository-scale/` records
  that as expected behavior, with a test.
- Plan 002 Stage 5 takes its rejected branch: the dependency mechanism is built
  and proved, and no cross-unit resolution is added.
- No producer declares a cross-unit dependency yet, so the mechanism is a no-op
  in practice today. It is built now rather than later because the rule it
  overrides — a unit whose own content did not change is never re-read — is
  currently unconditional and lives in the registry. The rationale's argument
  against retrofitting incrementality applies to invalidation as much as to
  storage.
- `Snapshot.countApproximateAssertions` remains zero across all fixtures, and
  that is the honest number, not a gap in coverage.
- A future ADR may permit approximate assertions from a producer that computes
  them from program meaning. This record rejects one mechanism, not a category.
- If cross-unit resolution is wanted, the path is language-correct scoping, which
  runs through `module` admission in `CORE.md`. That is a requirements change
  with its own lifecycle, not an implementation task.

## Verification Evidence And Planned Checks

- `tests/vertical_slice_test.zig` asserts that `Greeter` referencing `Helper`
  and `demo.greeter/greet` calling `decorate` stay unresolved designators with
  recorded explanations, while same-unit references resolve as facts, over
  `fixtures/repository-scale/`.
- Every fixture reports zero approximate assertions.
- The dependency mechanism is proved by a synthetic declared dependency in the
  core tests, which need no parser and no language semantics.
