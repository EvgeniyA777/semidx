---
title: "Zig dogfood semantic coverage progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-17"
---

# 006: Zig Dogfood Semantic Coverage Progress

Companion log for
[docs/plans/006_zig_dogfood_semantic_coverage.md](../plans/006_zig_dogfood_semantic_coverage.md),
implementing
[ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md).

## Current Status

Plan 006 is complete. Stages 1 to 5 are implemented and verified; the closure lane passes, and the self-review below found no open defect. Residual risks are recorded below.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Coverage probes and fixture design | Completed | Fixtures for member functions, nested containers, local import aliases, exact and unresolved qualified calls, and provider edits; expected graph deltas and risk matrix recorded below. No behavior change. |
| Stage 2: Container member function definitions | Completed | Named `fn` declarations directly inside covered top-level containers are `function` definitions with `container_path` and `container DEFINES member`; their bodies are reported as not analyzed. A renamed container reports its members' loss with replacements through a new generic reconciliation fallback. |
| Stage 3: Local Zig import alias context | Completed | Exact top-level `const alias = @import("relative.zig")` declarations naming one indexed Zig unit establish an alias and declare a provider dependency; every other file import is reported with its reason. `Index` now registers a scan's additions before analyzing any, reanalyzes a unit read before a provider analyzed later in the same batch, and treats a moved unit as a dependency seed. |
| Stage 4: Exact qualified call facts | Completed | `alias.foo(...)` through an established local import alias is a cross-unit `CALLS` fact to the one exported `pub fn` of that name in a current provider; member bodies are analyzed under the same rules with the container's names in scope. Provider body edits, added exports, renames, visibility changes, broken analysis, and removal all update the importer without editing it. |
| Stage 5: Dogfood and documentation | Completed | `zig build dogfood` proves both deltas on a copy of this repository: `Server.handleLine` is a member definition, and `protocol.writeString` has 23 current call facts: 19 from `src/mcp/tools.zig`, 1 from `src/mcp/root.zig`, and 3 from its own unit. Capability matrix, local preview reference, `SPEC.md`, follow-up 006, and `MEMORY.md` state the implemented subset and its false negatives. |

## Plan Readiness Gate

Applied on 2026-09-16 before Stage 1. Plan 005 is completed, so the start rule
holds. Scope, non-scope, stage order, verification commands, and DoD are
explicit and tied to ADR 006; no hard fail.

One execution risk the plan does not name, recorded here instead of reopening
the plan because Stage 3 already admits `src/root.zig` changes when existing
dependency propagation cannot keep dependents current:

- **Analysis order inside one batch.** `Index.applyScan` registers and analyzes
  each added unit in turn, and `Upkeep.finish` skips a dependent that was
  analyzed anywhere in the batch. On a first scan an importer analyzed before
  its provider is registered finds no unit at the import path and declares no
  dependency; an importer analyzed after the provider is registered but before
  it is analyzed declares one that is never honoured. Either way a scan would
  yield graphs that depend on path order. Stage 3 resolves this in `Index`.
- **Provider moves.** A scan rename is not a dependency seed today. An alias
  resolves by path, so a provider moved away from the import path must
  reanalyze its importers, or a current fact would survive the path that
  established it. Stage 3 resolves this in `Index`.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| ADR 006: direct member functions of covered top-level containers are definitions | Members stay invisible, or become top-level definitions | Frontend unit test and fixture test | `src/frontends/zig.zig` through `Analyzer.indexUnit` | Nested containers, fields, member declarations other than `fn`, members of containers inside function bodies stay unsupported | Stage 2 tests in `src/frontends/root.zig` and `tests/vertical_slice_test.zig` |
| Member identity: unit scope, role, name, container names; never ranges | Body edit or reordering breaks identity; rename or container rename hidden as unrelated change | Fixture edit-history test | Reconciliation of member drafts | `edits/08_member_renamed.zig` and `edits/09_container_renamed.zig` are identity loss | Stage 2 fixture tests |
| Local import path rule: lexical, root-bounded, exact bytes | Root escape, case-folded, package, or malformed import establishes an alias | Pure unit test of the path normalizer plus fixture test | `zig.zig` path resolution and `Graph.unitByPath` | `../../../outside.zig`, `Wire.zig`, `std`, escape sequences, absolute paths, empty segments | Stage 3 tests |
| Every established alias declares a provider dependency | Provider edits never reach importers | Integration test over `Index` | `BatchBuilder.addDependency` through `reconcile.integrate` | Unresolved call through an established alias still declares; unestablished alias declares none | Stage 3 tests |
| Scan order does not change the graph | Importer analyzed before its provider keeps unresolved calls or unhonoured dependencies | Integration test with `Tree.rescan` | `Index.applyScan` and `Upkeep.finish` | Importer path sorts before its provider | Stage 3 test |
| `alias.foo(...)` is a fact only for one current exported provider callable | False cross-unit fact | Fixture test | Frontend decision plus `reconcile.checkExternalTargets` | Non-`pub`, duplicate provider name, missing name, `alias.Container.foo`, shadowing parameter, duplicate alias, non-import alias, stale provider | Stage 4 tests |
| Member bodies use the same narrow call rules | Receiver or container-scope calls resolved by name | Fixture test | Member body walk | `self.flush()`, bare call to a container member name | Stage 4 tests |
| Provider changes reanalyze dependents | Stale current fact after provider rename, removal, or visibility change; resolvable call left unresolved after export addition | Integration test | `Upkeep` dependency propagation | Unrelated units are not reanalyzed by a provider body edit | Stage 4 tests with `imports/edits/*` |
| MCP renders the new values without source text and without deciding semantics | Dogfood shows no delta, or source text leaks | Runtime smoke | `zig build dogfood` | `semantic_contract_version` stays `null`; no `source_text` without the flag | Stage 5 dogfood test |

## Stage 1: Coverage Probes And Fixture Design

Changed files:

- `fixtures/vertical-slice/zig/imports/wire.zig`,
  `fixtures/vertical-slice/zig/imports/session.zig`,
  `fixtures/vertical-slice/zig/imports/support/util.zig` (new);
- `fixtures/vertical-slice/zig/imports/edits/wire_01_body_edit.zig`,
  `wire_02_added_export.zig`, `wire_03_renamed_export.zig`,
  `wire_04_export_made_private.zig` (new);
- `fixtures/vertical-slice/zig/edits/07_member_body_edit.zig`,
  `08_member_renamed.zig`, `09_container_renamed.zig` (new);
- this progress log.

Every new fixture parses without `ERROR` or `MISSING` nodes under the pinned
grammar (checked with `tree-sitter parse` against
`.tree-sitter-grammars/tree-sitter-zig`).

### Expected Graph Deltas

The existing `zig/greeter.zig` fixture already carries a representative
semidx pattern: `Greeter.greet` is a `pub fn` member of a top-level struct,
like `Server.handleLine` in `src/mcp/root.zig`. The import fixture mirrors
`protocol.writeString(...)` calls from `src/mcp/tools.zig`.

Member definitions (Stage 2):

| Declaration | Expected |
| --- | --- |
| `greeter.zig` `Greeter.greet` | `definition` fact, role `function`, `container_path` `["Greeter"]`, `DEFINES` from `Greeter` |
| `session.zig` `Session.send`, `Session.flush`, `Session.reset` | same shape under `["Session"]` |
| `session.zig` `Session.Nested`, `Session.Nested.deep`, fields | unsupported construct diagnostics, no definitions |
| `wire.zig` `Frame.encode` | definition under `["Frame"]` |
| `edits/07_member_body_edit.zig` | every definition id preserved |
| `edits/08_member_renamed.zig` | `Greeter.greet` identity lost, replaced by `Greeter.welcome` |
| `edits/09_container_renamed.zig` | `Greeter` and its member lose identity; replacements `Welcomer` and `Welcomer.greet` |

Calls (Stages 3 and 4), from `imports/session.zig` unless stated:

| Call | Expected |
| --- | --- |
| `run`: `wire.writeString(text)` | `CALLS` fact to `wire.zig` `writeString`, provider dependency on `wire.zig` |
| `run`: `util.clean()` | fact to `support/util.zig` `clean` via `./support/../support/util.zig` |
| `support/util.zig` `clean`: `session.run("")` | fact to `session.zig` `run` via `../session.zig` |
| `Session.send`: `wire.writeString(text)` | fact (member body) |
| `Session.send`: `self.flush()` | unresolved: qualifier is a parameter |
| `Session.flush`: `helper()` | fact to top-level `helper` |
| `Session.flush`: `reset()` | unresolved: the enclosing container declares a member of that name |
| `run`: `wire.hidden()` | unresolved: the provider has no `pub fn` of that name declared once at its top level (it is not `pub`) |
| `run`: `wire.twice()` | unresolved for the same reason (the provider declares `twice` twice) |
| `run`: `wire.flushAll()` | unresolved; a fact after `wire_02_added_export.zig` |
| `run`: `wire.Frame.encode(undefined)` | unresolved: qualifier is not a bare alias |
| `run`: `std.debug.print(...)` | unresolved: qualifier is not a bare alias |
| `run`: `outside.run()` | unresolved: import path escapes the root |
| `run`: `upper.run()` | unresolved: no indexed unit at `zig/imports/Wire.zig` |
| `run`: `absent.run()` | unresolved: no indexed unit at the path |
| `run`: `twin.run()` | unresolved: alias name declared more than once |
| `run`: `copy.writeString(text)` | unresolved: `copy` is not an `@import` alias |
| `shadowed`: `wire.writeString("x")` | unresolved: qualifier is a parameter |

Provider edits of `imports/wire.zig`:

| Edit | Expected in `session.zig` without editing it |
| --- | --- |
| `wire_01_body_edit.zig` | `writeString` id preserved; facts still target it |
| `wire_02_added_export.zig` | `wire.flushAll()` becomes a fact |
| `wire_03_renamed_export.zig` | `wire.writeString` calls become unresolved; no current fact targets the lost entity |
| `wire_04_export_made_private.zig` | `wire.writeString` calls become unresolved |

Dependencies: `session.zig` depends on `wire.zig` and `support/util.zig` only;
`support/util.zig` depends on `session.zig`. `outside`, `upper`, `absent`, and
`twin` establish no alias and declare nothing. `std` is not a local import.

Baseline before implementation: none of the member definitions above exist,
and every qualified call is unresolved with "the callee is not a bare name".
No red baseline was committed.

Verification:

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches. |
| `tree-sitter parse` over every new fixture | No `ERROR` or `MISSING` node. |
| `zig build test --summary all` | 20/20 steps; 186/187 passed, 1 skipped. The skip is the pre-existing environment-dependent `src/mcp/root.zig` dogfood-root test. The fixture discovery test now also registers the new fixtures and stays green. |

## Stage 2: Container Member Function Definitions

Changed files: `src/frontends/zig.zig`, `src/core/model.zig`,
`src/core/reconcile.zig`, `src/frontends/root.zig`,
`tests/vertical_slice_test.zig`, `tests/mcp_smoke_test.zig`,
`docs/spec/capability_matrix.md`, this log.

Decisions taken inside the plan's boundary:

- A named `function_declaration` directly inside a covered top-level container
  is a `function` definition with `container_path = [container name]`, labels
  `zig.construct = function` and `zig.placement = container_member`, and a
  `DEFINES` fact from the container. No signature, as for top-level functions.
  Every other member kind stays an unsupported construct per kind.
- Member drafts are emitted after every top-level declaration, so a unit's
  top-level definitions keep the batch order they had.
- Member bodies are not walked yet (Stage 4). Until then the unit reports one
  `unsupported_construct` count of member function bodies whose calls were not
  analyzed, so their calls read as unanalyzed rather than absent.
- **Shared-core change.** Reconciliation reported a renamed container's members
  as `removed` plus `created`, because `IdentityEvidence.sameSlot` requires the
  same `container_path`. Constitution section 4 forbids hiding identity loss as
  an unrelated deletion and creation, and the plan's Stage 2 DoD requires
  observable loss for containment changes. `IdentityEvidence.sameNameElsewhere`
  (same scope, language, role, and name under a different container path) is
  now a second replacement search in pass 3, used only when no same-slot
  replacement exists. It records the existing unresolved
  `identity_correspondence`, never a fact, and applies to every frontend: a
  renamed Java class now reports its methods as lost with replacements too.
- The producer version is now `plan-006+ts-abi15`.

Verification:

| Command | Result |
| --- | --- |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 89/89 passed, including the new reconcile test for a renamed container. |
| `zig fmt --check build.zig src tests` | Clean. |
| `zig build test --summary all` | 20/20 steps; 190/191 passed, 1 skipped (the pre-existing environment-dependent MCP dogfood-root test). New: member definition shape test, member body edit, member rename, container rename. Updated: fixture counts (six definitions), the MCP smoke test (two `greet` definitions told apart by `container_path`). |

Mutation checks, run and reverted:

- Without the `sameNameElsewhere` fallback, the reconcile container-rename test
  and the Zig container-rename fixture test fail (`lost` expected 2, found 1).
- With member `container_path` left empty, the member-shape frontend test and
  the MCP smoke test fail, and the four member fixture tests abort on a
  missing member lookup.

## Stage 3: Local Zig Import Alias Context

Changed files: `src/frontends/zig.zig`, `src/frontends/root.zig`,
`src/root.zig`, `tests/vertical_slice_test.zig`, this log.

Decisions taken inside the plan's boundary:

- `zig.resolveImportPath` is pure and lexical. A literal not ending in `.zig`
  is a package or builtin import (`std`, `builtin`, `root`) and is not
  resolved or reported beyond its uncovered declaration. A `.zig` literal is
  resolved against the importer's directory with `.` and `..`; an absolute
  path, a backslash, an empty segment, or a `..` above the root rejects it.
  The result is compared with indexed unit paths byte for byte through
  `Graph.unitByPath`, so a case-mismatched path names no unit.
- An import declaration is read token by token: optional `pub`, `const`, one
  identifier, `=`, and `@import` with exactly one plain string literal. `var`,
  a type annotation, `extern` or `export`, escape sequences, a second argument,
  and an import used in a larger expression (`@import("x.zig").Frame`) are not
  import declarations.
- The analyzer builds `zig.Context` from the graph before analysis: one
  provider per requested path that names a live Zig unit, with whether its
  analysis is current. A pending provider still establishes the alias.
- The frontend establishes an alias only when its provider exists, is not the
  analyzed unit, the alias name is declared once at the top level, and the unit
  has no `usingnamespace`. An established alias always declares a dependency on
  its provider. A declined `.zig` import is an `unsupported_construct`
  diagnostic naming the alias, the literal, and the reason, capped at 16 per
  unit with an overflow count. Analysis without a graph declines every file
  import. No entity, relationship, `module`, or `IMPORTS` is recorded.
- **`Index` ordering (the readiness-gate risk).** `applyScan` registers every
  added unit before analyzing any, so a path lookup does not depend on scan
  order. `Upkeep.finish` additionally reanalyzes any unit whose declarations,
  as they stand after the batch, name a provider analyzed at a later step of
  the same batch. A scan rename, and `Index.renameUnit`, now seed dependency
  propagation, because an alias found its provider by path. Java units are
  covered by the same rules; no Java or Clojure expectation changed.

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Clean. |
| `zig build test --summary all` | 20/20 steps; 199/200 passed, 1 skipped (pre-existing environment-dependent test). New: import path normalization, import declaration shapes and dependencies, duplicate and `usingnamespace` aliases, analysis without a graph, fixture dependencies and declined-alias diagnostics, importer scanned before its provider, provider scanned first, provider moved and removed, provider added later. |

Mutation checks, run and reverted:

- Without the same-batch step rule in `Upkeep.finish`, the importer-before-
  provider test fails.
- Without renames as seeds, the provider move test fails.
- Without `addDependency` for an established alias, six import tests fail.
- Not run: analyzing additions as they are registered. The importer-before-
  provider test asserts the dependency that such ordering would lose.

## Stage 4: Exact Qualified Call Facts

Changed files: `src/frontends/zig.zig`, `src/frontends/root.zig`,
`tests/vertical_slice_test.zig`, `docs/spec/capability_matrix.md`, this log.

Decisions taken inside the plan's boundary:

- **Exported callable.** The provider's own frontend decides it, because only
  that analysis sees the unit's whole top-level namespace, including uncovered
  declarations: a covered top-level `fn` written with `pub`, whose name the top
  level declares exactly once (read in a pre-pass over every top-level
  declaration), in a unit without `usingnamespace`, carries
  `zig.export = callable`. `pub extern fn` counts; members never do.
- The analyzer reads a current provider's exports from the graph: live
  top-level `function` definitions labelled exported whose existence
  `Graph.currentDefinitionFact` finds as a current `frontend.zig` fact. A
  provider that is not current offers none. `reconcile.checkExternalTargets`
  still re-checks every external target at integration.
- `alias.foo(...)` is decided only for a `field_expression` callee whose object
  and member are both identifiers. The qualifier is unresolved when a
  parameter or local binding, a member of the enclosing container, or a
  `usingnamespace` could give it another meaning; when it is not an import
  alias; when it is a package import; when its import was declined (the
  explanation carries the reason); when the provider is not current; and when
  the provider exports no single function of that name.
- Member bodies are walked like top-level bodies. A bare name or a qualifier
  that the enclosing container declares (fields included) stays unresolved,
  and a container `usingnamespace` leaves every call in its members
  unresolved. The Stage 2 "member bodies not analyzed" diagnostic is gone.
- The generic explanation for other callees is now "the callee is not a bare
  name or a name qualified by a local import alias"; `Shape.make`-style calls
  say the qualifier is not a top-level `@import` alias.
- No `REFERENCES`, `module`, `IMPORTS`, or approximate assertion is added; the
  fixture test asserts zero approximate assertions.

Verification:

| Command | Result |
| --- | --- |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 89/89 passed. |
| `zig fmt --check build.zig src tests` | Clean. |
| `zig build test --summary all` | 20/20 steps; 203/204 passed, 1 skipped (pre-existing environment-dependent test). New: export label rules; member-body call rules with container scope and container `usingnamespace`; the fixture fact/unresolved table (5 facts, 13 named unresolved calls, incoming counts, evidence, dependency); provider body edit (identity preserved, importer and its coarse dependent reanalyzed, unrelated unit not), added export, renamed export, private export, stale provider, removed provider. |

Mutation checks, run and reverted:

- Never labelling exports: four tests fail, one aborts.
- Ignoring a parameter or local that shadows a qualifier: the member-body test
  and the fixture table test fail.
- Ignoring container member names for bare calls: the same two tests fail.

A provider body edit reanalyzes the importer and, transitively, units that
depend on the importer (`support/util.zig` in the fixture), because
dependency propagation is coarse and transitive. That is existing, documented
behavior, not new; unrelated units are not reanalyzed.

## Stage 5: Dogfood And Documentation

Changed files: `tests/mcp_dogfood_test.zig`, `docs/spec/capability_matrix.md`,
`docs/mcp/local_preview.md`, `SPEC.md`, `MEMORY.md`,
`docs/followups/006_zig_cross_unit_and_member_calls.md`,
`docs/followups/README.md`, `docs/plans/006_zig_dogfood_semantic_coverage.md`,
this log.

Dogfood checks added to the habit-loop test:

- **Member definition.** `semidx_find_definitions` for `handleLine` in
  `src/mcp/root.zig` returns one current `frontend.zig` fact with
  `container_path = ["Server"]`; the repository map lists it among the unit's
  nested definitions (30), not its top-level ones. Before Plan 006 it was an
  unsupported container member.
- **Exact qualified call.** `semidx_references` for `writeString` in
  `src/mcp/protocol.zig` returns only current `calls` facts from
  `frontend.zig`, 23 in all: 19 from `src/mcp/tools.zig` and 1 from
  `src/mcp/root.zig` (each through its own
  `const protocol = @import("protocol.zig")`), and 3 from its own unit. The
  test classifies every caller path and checks that the buckets add up to the
  reported total. Before Plan 006 the follow-up recorded only the 3 same-unit
  callers.
- `semidx_context` for `health` in `src/mcp/tools.zig` shows an outgoing fact
  into `src/mcp/protocol.zig` beside unresolved `std.…` calls.
- The existing context check for `scan` in `src/source/discovery.zig` now
  matches two definitions (the top-level function and the `scan` member of the
  unit's test `Tree` container), so it selects the one without a container.

Output-size and latency observations (Debug build, 66 units, 714,844 bytes;
observations, not gates or benchmarks):

| Call | Observation |
| --- | --- |
| `semidx_health {}` | 639 ms to first response, 6,683 bytes |
| `semidx_repo_map {"limit":1000}` | 39 ms, 314,779 bytes (members are counted, not listed) |
| `semidx_find_definitions` `handleLine` | 0 ms, 2,104 bytes |
| `semidx_references` `writeString`, limit 1000 | 7 ms, 56,824 bytes |
| `semidx_context` `scan` | 10 ms, 22,947 bytes |
| `semidx_context` `health`, relationship limit 500 | 20 ms, 150,632 bytes |
| `semidx_refresh {}` after one edit | 31 ms, 1,213 bytes |
| `semidx_repo_map` with `--allow-evidence-text`, 500 per file | 56 ms, 364,277 bytes; 423 definition evidence texts, none cut |

Plan 005 recorded 260,109 bytes for the repository map and 14,591 bytes for the
`scan` context over 56 units. The unit count differs (Plan 006 added 10 fixture
files), so these rows are not a like-for-like delta.

Graph delta, measured with the developer command built from the pre-plan
revision `46b7ec0` (via `git archive` into a scratch directory) and from the
final tree, over the same inputs:

| Input | Revision | Definitions | Facts | Unresolved | Approximate |
| --- | --- | --- | --- | --- | --- |
| `src` (25 units) | `46b7ec0` | 294 | 844 | 1,354 | 0 |
| `src` (25 units) | final | 537 | 1,645 | 2,134 | 0 |
| repository (66 units) | `46b7ec0` | 467 | 1,350 | 1,721 | 0 |
| repository (66 units) | final | 750 | 2,257 | 2,604 | 0 |

Unresolved assertions grew because member bodies are now analyzed, and most of
their calls go through receivers or values. Every run exited 0 with its whole
output consumed and no non-printable bytes.

Plan 007 check: Plan 007 records no numeric budget assumption that these results
contradict; its premise, that whole responses are unbudgeted, still holds. Plan
007 is not edited; the larger call-heavy context is recorded as residual risk.

## Closure Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches. |
| `zig fmt --check build.zig src tests` | Clean. |
| `zig build test-core --summary all` | 5/5 steps; 89/89 passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 5/5 steps; 89/89 passed. |
| `zig build test --summary all` | 20/20 steps; 203/204 passed, 1 skipped (the pre-existing environment-dependent `src/mcp/root.zig` dogfood-root test). |
| `zig build test-mcp --summary all` | 9/9 steps; 18/19 passed, 1 skipped (the same test). |
| `zig build dogfood --summary all` | 10/10 steps; 5/5 passed; refresh recovery over 66 units: 32 failure points, 28 rebuilds, one-shot and sticky. |

Not run: a mutation check of the dogfood assertions themselves. Their frontend
behavior is mutation-checked in Stages 2 to 4.

## Review Findings

Findings-first self-review of the final diff, then an external review after
closure:

| Finding | Disposition |
| --- | --- |
| The new dogfood context check for `health` read `focus[0]`, which a same-named member would silently replace. | Fixed: it selects the focus entity without a container, like the `scan` check. |
| The existing dogfood `scan` context check assumed one match; member coverage made it two. | Fixed in Stage 5 (see above). |
| `sameNameElsewhere` can pair a removed declaration with an unrelated new one of the same name and role under a different container. | Accepted: the pairing is recorded as the existing unresolved identity correspondence, never a fact, and only when no same-slot replacement exists. |
| Scan renames now seed propagation for every language, so a moved Java provider reanalyzes its Java dependents. | Accepted: redundant but correct; Java bindings do not read paths. |
| External review, low, confirmed: the dogfood proof and this log reported `writeString` callers as 19 from `tools.zig` and 3 same-unit, silently leaving out a current fact from `src/mcp/root.zig` (23 in all). Behavior was correct; the evidence was incomplete. | Fixed: the dogfood test classifies every caller path, asserts the buckets add up to `relationships_total`, and prints each other caller unit; the Stage Log and Stage 5 evidence now state 19 + 1 + 3 = 23. Verified with `zig build dogfood` (5/5). |
| `Index.addUnit` one unit at a time does not revisit a Zig importer added before its provider. The developer command does this for individual file arguments (1,401 facts over `src` files versus 1,645 for the `src` directory). | Accepted as residual risk: same class as the named missing-provider risk, unresolved rather than false. Scans, which the MCP preview uses, are order-independent. |

## Residual Risk

- **Missing provider file (named by the plan).** If a Zig unit imports a
  relative file that does not exist yet, no provider dependency is declared.
  Adding that provider later, or moving a unit onto that path, does not
  reanalyze the importer until the importer changes or is otherwise
  reanalyzed. Calls through that alias stay unresolved meanwhile: a false
  negative, not a false fact. Tested by "a zig provider added after its
  importer is not noticed until the importer is reanalyzed".
- **One-at-a-time additions.** The same false negative applies to
  `Index.addUnit` when an importer is added before its provider outside a scan.
- **Coarse, transitive invalidation.** A provider body edit reanalyzes its
  importers and their dependents in turn (`support/util.zig` in the fixture),
  though no exported name changed.
- **Larger call-heavy responses.** Cross-unit facts carry full target entity
  references; `semidx_context` for a call-heavy Zig function reached 150 KB at
  `relationship_limit: 500`. Input for Plan 007.
- **Remaining false negatives** stay in
  [follow-up 006](../followups/006_zig_cross_unit_and_member_calls.md), which
  stays open with a dated note: receiver and value calls, nested namespaces,
  container-member targets, and package imports.

## Drift Control

- `ARCHITECTURE_CONSTITUTION.md`: not edited. New facts are frontend-established
  (section 3), member identity uses containment names and renamed containers
  report loss with replacement (section 4), provider changes and moves
  reanalyze dependents and scan order no longer changes the graph (section 5),
  Zig vocabulary stays in `zig.*` labels (section 6), and MCP decides nothing
  (section 7).
- ADR 006: aligned; every planned check it lists has a test named above.
- `CORE.md`: aligned; no kind added. `module` and `IMPORTS` remain unadmitted.
- `SPEC.md`: updated (Zig coverage paragraph).
- `CONFORMANCE.md`: aligned; "a rename is recorded as identity loss naming its
  replacement" now also holds for container renames.
- `GLOSSARY.md`: aligned; "import alias" and "provider source unit" already
  exist, and "exported callable" is owned by ADR 006.
- `docs/spec/capability_matrix.md` and `docs/mcp/local_preview.md`: updated
  with the implemented subset, the named residual risk, and the remaining false
  negatives; `semantic_contract_version` is still `null`.
- `MEMORY.md`: the Plan 006 priority entry is replaced by implemented reality.
- Follow-up 006: open, with a dated note for the resolved portion.
- Plan 007: not edited; see Residual Risk.
