---
title: "Defines and contains split"
doc_type: "report"
lifecycle: "completed"
status: "final"
agent_action: "historical_reference_only"
updated: "2026-09-14"
---

# 004: Defines And Contains Split

This report records the follow-up to the `DEFINES` blocker found in
[report 003](003_core_admission_review.md). The implementation now separates
direct containment from definition introduction:

- `CONTAINS` records that one source or program container directly contains an
  entity.
- `DEFINES` records that a container directly introduces a program definition.

This remains an unversioned implementation guidance result. It does not publish
a semantic contract version, declare supported languages, or add a public API.

## Context

The first admission review found that `CORE.md` described `DEFINES` as
container-to-definition, while the implementation also used it for
`repository -> file` source-tree containment. External graph-modeling practice
supports keeping those meanings separate: definition/binding claims are narrower
than containment/parenthood claims, and source-file membership should not be
mistaken for a program definition.

Semantic Code Indexing was required by repository policy, but no semidx MCP
tools were available through tool discovery in this environment. The change used
targeted direct inspection instead. Runtime code here is Zig, which is not one
of the supported languages listed by the current semidx skill.

## Decision

`CONTAINS` is admitted as the shared-core relation for direct containment.
Source ingestion uses it for `repository -> file` claims.

`DEFINES` is admitted as the shared-core relation for direct definition
introduction. Its target must be a `definition`. A `repository -> file` relation
is therefore invalid as `DEFINES`.

`CALLS` and `REFERENCES` behavior is unchanged: calls continue to satisfy a
reference query, while both `CONTAINS` and `DEFINES` do not.

## Implementation

- `src/core/model.zig` adds `RelationshipKind.contains`.
- `src/core/graph.zig` records source-unit membership as `CONTAINS` and rejects
  `DEFINES` when the target is not a `definition`.
- `src/core/reconcile.zig` updates stale-source-unit expectations to look for
  current ingestion `CONTAINS` assertions.
- `tests/vertical_slice_test.zig` proves fixture ingestion uses `CONTAINS`
  while frontend definition introduction remains `DEFINES`.
- `CORE.md` accepts `CONTAINS` and `DEFINES` with distinct meanings.
- `MEMORY.md` records the current reality and removes the `DEFINES` blocker from
  near-term priorities.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Source-tree membership uses containment | `repository -> file` keeps masquerading as a definition introduction | Core unit test and fixture test | Snapshot queries observe `CONTAINS` for source-unit membership | Querying repository `DEFINES` returns nothing | `zig build test-core`, `zig build test` |
| Definition introduction remains narrow | A non-definition target can be recorded as `DEFINES` | Core unit test | `Graph.addRelationship` rejects a live `file` target for `DEFINES` | `repository DEFINES file` fails | `zig build test-core` |
| Reference query semantics stay unchanged | `CONTAINS` or `DEFINES` pollutes "all references" queries | Model unit test | `RelationshipKind.satisfiesReferenceQuery` excludes both | Calls still satisfy the query | `zig build test-core` |
| Frontends stay language-specific | Java/Clojure fixtures lose definition-introduction edges | Fixture integration test | Existing fixture expectations still require file/class/namespace `DEFINES` edges | Source ingestion edge changed independently | `zig build test` |

## Verification

Run after implementation:

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 38/38 tests passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 38/38 tests passed; the shared core remains independent of parser inputs. |
| `zig build test --summary all` | 67/67 tests passed across the core, adapter, frontend, and fixture lanes. |
| `zig build run -- fixtures/vertical-slice/java/Greeter.java fixtures/vertical-slice/clojure/greeter.clj` | Printed 1 repository, 2 files, 8 definitions, 31 assertions, 26 facts, 5 unresolved assertions, 0 approximate assertions, and 0 stale assertions. |

## Residual Risk

- `CONTAINS` currently has only source-ingestion fixture evidence for
  `repository -> file`; broader program-container uses remain future endpoint
  expansion work.
- `DEFINES` is admitted for direct introduction in the fixture-scoped frontends,
  not as complete Java or Clojure language support.
- There is still no published semantic contract, capability matrix, or public
  consumer surface.
- `module`, `IMPORTS`, textual inclusion, and cross-unit invalidation remain
  unsettled.
