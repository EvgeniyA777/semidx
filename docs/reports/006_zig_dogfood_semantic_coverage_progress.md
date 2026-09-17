---
title: "Zig dogfood semantic coverage progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-16"
---

# 006: Zig Dogfood Semantic Coverage Progress

Companion log for
[docs/plans/006_zig_dogfood_semantic_coverage.md](../plans/006_zig_dogfood_semantic_coverage.md),
implementing
[ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md).

## Current Status

Stages 1 to 3 are complete. Stages 4 and 5 are pending.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Coverage probes and fixture design | Completed | Fixtures for member functions, nested containers, local import aliases, exact and unresolved qualified calls, and provider edits; expected graph deltas and risk matrix recorded below. No behavior change. |
| Stage 2: Container member function definitions | Completed | Named `fn` declarations directly inside covered top-level containers are `function` definitions with `container_path` and `container DEFINES member`; their bodies are reported as not analyzed. A renamed container reports its members' loss with replacements through a new generic reconciliation fallback. |
| Stage 3: Local Zig import alias context | Completed | Exact top-level `const alias = @import("relative.zig")` declarations naming one indexed Zig unit establish an alias and declare a provider dependency; every other file import is reported with its reason. `Index` now registers a scan's additions before analyzing any, reanalyzes a unit read before a provider analyzed later in the same batch, and treats a moved unit as a dependency seed. |
| Stage 4: Exact qualified call facts | Pending | |
| Stage 5: Dogfood and documentation | Pending | |

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
