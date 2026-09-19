---
title: "Java instance receiver calls"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-19"
---

# Java Instance Receiver Calls

## Classification

`coverage_gap`

## Source

The subject [Plan 012](../plans/012_java_semantic_quality_without_query_regression.md)
was written for, and which its own Stage 0 gate declined. See
[the measurement](../reports/012_java_semantic_quality_without_query_regression_progress.md#the-addressable-receiver-subset)
and
[Amendment 1](../plans/012_java_semantic_quality_without_query_regression.md#amendment-1-from-instance-receivers-to-static-calls).

## Current Behavior

Any `method_invocation` with an `object` field is recorded as an unresolved
`CALLS` assertion whose designator is the full invocation text, with the reason
"the invocation is qualified by a receiver this frontend does not resolve". That
is 4,624 of 5,662 unresolved calls in the Plan 012 Stage 0 sample. Plan 012
resolves the 1,041 of those whose receiver is a class name; the remaining 3,583,
whose receiver is a value, stay unresolved.

## Why Deferred

Resolving a value receiver needs the static type of an expression, which needs a
lexical receiver type environment over method bodies: covered binding
introducers, shadowing rules, poison regions for every construct that is not
covered, and declaration-order visibility. Plan 012 specified that work in full
and then measured what it would buy.

Measured on apache/dubbo at `df9c5e1`, over a sample of 1,200 definitions:

| Measurement | Count |
| --- | ---: |
| Receiver-qualified unresolved calls | 4,624 |
| Exactly resolvable under the covered binding list, public target method | **63** |
| Same, protected or private target method | 8 |
| Blocked: receiver type does not resolve under current rules | 1,311 |
| Blocked: chained or field receiver expression | 789 |
| Blocked: declared type shape not covered (generic, array, wildcard) | 636 |
| Blocked: target class declares supertypes | 283 |
| Blocked: binding introducer not covered (for-each, lambda, catch, resource) | 351 |

Plan 012's gate required 100. At 63 the type-environment machinery was not paid
for, especially beside the 135 static calls that need none of it.

Two adjacent relaxations were priced at the same time. Admitting generic and
array base types into the covered bindings adds 18. Admitting target classes
that declare supertypes when the name is declared once in the class itself would
add 211, but of 210 such hierarchies re-derived from the sample **none** is
closed in indexed source, so the static target cannot be established and the
fact would be a guess.

## Acceptance Direction

A future plan may take this up when at least one of these changes:

- **The blocking evidence becomes available.** The largest blocker is receiver
  types that do not resolve, and 627 of those 1,311 are the supertype guard, so
  [Follow-up 013](013_java_supertype_guard_relaxation.md) lands first and this
  entry is re-measured afterwards rather than assumed.
- **A different repository shows a different shape.** These counts are one
  Maven, interface-heavy codebase. A second external sample may move them, and
  the classification harness is described in the Plan 012 progress log.
- **The type environment becomes cheap because something else needs it.** If a
  later plan builds a lexical environment for another reason, the marginal cost
  of this work drops and the 63 is worth re-pricing.

Whatever the trigger, keep Plan 012's rules: covered binding list, shadow-only
poison for everything outside it, exact receiver type inside the ADR 008
boundary, one declared method of that name, covered access, target class with no
declared supertypes, and no resolution inside a nested class body.

## Required Tests

- `this.m()` and `local.m()` to a unique declared method in a class with no
  supertypes resolve; parameter, field, and `new Type().m()` shapes resolve
  under the same conditions.
- Unknown receiver, out-of-scope receiver class, duplicate local binding,
  overloads, target class with supertypes, nested class body, `super.m()`,
  chained receivers, and unsupported receiver types stay unresolved with
  distinct reasons.
- Every binding introducer outside the covered list poisons the name in its
  lexical region: for-each, catch, resource, lambda, type and record patterns,
  varargs, and declarators with dimensions.
- A declaration that appears after the invocation does not bind it.
- Provider method and class-shape edits reanalyze the caller.
