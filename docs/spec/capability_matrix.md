---
title: "Preview capability matrix"
doc_type: "specification"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# Preview Capability Matrix

What the `0.1.0-preview.1` implementation records, per producer, and what it
does not. Owned by [SPEC.md](../../SPEC.md#coverage-and-conformance).

This is an **unversioned preview matrix**. It describes current implementation
behavior so users and agents can tell what to trust. It is not the published
coverage matrix of a semantic contract, not a supported-language roster, and not
an accuracy claim: no semantic contract version exists, and every result reports
`semantic_contract_version: null`. It changes whenever the implementation does.

## How To Read It

Every claim the graph returns carries one of these outcomes, and they stay
distinct on every surface:

| Outcome | Meaning | Where it appears |
| --- | --- | --- |
| Fact | Fully established by the producer's rule below | `resolution.category = "fact"` |
| Unresolved | Part of the claim is established, the target is not; the explanation says why | `resolution.category = "unresolved"`, target is a `designator` |
| Approximate | Heuristic or confidence-based | `resolution.category = "approximate"`. **No current producer emits one.** |
| Unsupported construct | The construct exists but is outside the producer's coverage; nothing is claimed about it | `unsupported_construct` diagnostic |
| Analysis unavailable | Analysis could not run (no parser, unreadable input, budget) | `analysis_unavailable` diagnostic |
| Analysis failed | Analysis ran and the source did not parse | `analysis_failed` diagnostic |
| Confirmed absence | Analysis ran, the coverage applies, and nothing is there | `confirmed_absence` diagnostic |
| Stale | Recorded against contents the unit no longer has | `freshness = "stale"`; excluded from default queries |

"Not recorded" in the tables below means no claim and no diagnostic is
produced for that construct: absence of a claim there says nothing.

## Source Ingestion

Producer `source-ingestion`.

| Aspect | Current behavior |
| --- | --- |
| Source units | Files under `--root` ending in `.java`, `.clj`, `.cljc`, or `.zig`. Other files are not source units and produce no diagnostic. |
| Facts | The repository entity, one `file` entity per unit, and `repository CONTAINS file`. |
| Excluded directories (policy, no diagnostic) | `.git`, `.zig-cache`, `zig-out`, `.cache`, `.cpcache`, `node_modules`, `target`, `.tree-sitter-grammars`, `.jdtls-toolchain`, `.lsp-toolchain`, `.scip-toolchain`, `.scip-java-toolchain`. Ignore files such as `.gitignore` are not read. |
| Unsupported | Symbolic links are reported and never followed. |
| Unavailable | A file at or above 4 MiB, a directory deeper than 64 levels, units beyond 20,000, and unreadable files or directories are reported and not ingested. |
| Identity | A unit's identity is not its path. A path present in two scans is the same unit; a unit that disappeared corresponds to exactly one new unit with identical content and language (a move). A file that moved and changed in one rescan is a removal plus an addition; ambiguous moves are reported, not resolved. |
| Not covered | Generated or virtual source origins, multiple roots, and file watching: edits are observed only on refresh. |

## Java

Producer `frontend.java`. Fixture-scoped coverage, not a Java support claim.

| Aspect | Current behavior |
| --- | --- |
| Definitions (facts) | Named top-level `class` declarations (role `class`) and the methods declared directly in them (role `method`). Java vocabulary stays in extension labels (`java.construct`, `java.package`, `java.return_type`). |
| Relationships (facts) | `file DEFINES class`, `class DEFINES method`. `REFERENCES` from a class (field types) or method (return type) to a class declared in the same unit. `REFERENCES` to the one current top-level class another unit declares in the same explicit package, with a recorded dependency on that unit. `CALLS` for an unqualified invocation when the enclosing class declares exactly one method of that name, has no superclass or interfaces, and the call is not inside a class body declared in the method. |
| Unresolved | Qualified type names; types named by an import; type parameters; names a member type or a supertype may claim; units without a package; other packages; ambiguous same-package names; qualified invocations (`a.b()`); invocations of overloaded names; invocations in classes with supertypes; invocations inside anonymous or local classes; names no method in the class declares. |
| Unsupported | Top-level interfaces, enums, records, and annotation types; class members other than methods (fields as definitions, constructors, nested types, initializers); unnamed classes; bodies nested deeper than 64 levels. |
| Not recorded | Parameter and local-variable types, constructor calls (`new X()`), field reads and writes, inheritance and dispatch. |
| Identity | Method identity includes the parameter types: changing a parameter type or renaming a class or method is identity loss. |
| Known overbroad case | The same-package rule treats the indexed root as one classpath. If two build modules use the same package name and only one declares a class, a reference from the other module is a fact about a class that may not be on its classpath ([follow-up 003](../followups/003_java_classpath_boundaries.md)). |
| Known false negatives | Almost every cross-package reference and every call through a receiver is unresolved or not recorded. |

## Clojure

Producer `frontend.clojure`. Fixture-scoped coverage, not a Clojure support claim.

| Aspect | Current behavior |
| --- | --- |
| Definitions (facts) | The unit's first `ns` form (role `namespace`), and top-level `def`, `defn`, and `defn-` forms (roles `def`, `defn`). Vocabulary in labels `clojure.form`, `clojure.namespace`, `clojure.var`. |
| Relationships (facts) | `file DEFINES namespace`, `namespace DEFINES def` (or `file DEFINES def` without `ns`). A symbol in a definition body is a `REFERENCES` fact, or a `CALLS` fact in head position, only when it names the unit's one top-level `def`-like declaration of that name, is not a parameter of the enclosing definition, sits in a definition with a single parameter vector, and every enclosing form is known to bind nothing: the body itself, `do`, `if`, collection literals, calls of the unit's own definitions, and applications whose head is not a symbol. |
| Unresolved | Every symbol under any other form — `let`, `fn`, `loop`, `for`, threading macros, `clojure.core` functions such as `str`, and macros from other namespaces — because such a form may bind the name locally. Parameters, names declared more than once (including by `defmacro`), symbols in multi-arity definitions, namespaced symbols, and names nothing in the unit defines. **Clojure calls are narrow: most real references are unresolved** ([follow-up 008](../followups/008_clojure_lexical_scope_coverage.md)). |
| Unsupported | Top-level forms other than `ns`, `def`, `defn`, `defn-` (for example `defmacro`, `defonce`, `require`); top-level forms that are not lists or whose head is not a symbol; unnamed definitions; top-level forms with 4,096 or more values; forms nested deeper than 64 levels. |
| Confirmed absence | A unit with no `ns` form, or with no `def`/`defn`. |
| Not recorded | Namespace aliases and `require`, cross-unit resolution, anonymous functions (`#(...)`), quoted and syntax-quoted forms, reader conditionals. A second `ns` form in a unit is ignored without a diagnostic. |
| Identity | A `defn` signature includes its arity: changing the arity or renaming is identity loss. |

## Zig

Producer `frontend.zig`. Dogfood coverage for this repository, not a Zig support
claim.

| Aspect | Current behavior |
| --- | --- |
| Definitions (facts) | Named top-level `fn` declarations, including `extern` and `inline` (role `function`), top-level `const` declarations bound directly to a `struct`, `enum`, `union`, or `opaque` expression (role `container`), and named `fn` declarations directly inside such a container (role `function`, `container_path` naming the container, label `zig.placement = container_member`; [ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md)). Labels `zig.construct`, `zig.container`, `zig.placement`, and `zig.export = callable` on a top-level `pub fn` whose name the unit's top level declares once, in a unit without `usingnamespace`. |
| Local import aliases | A top-level `[pub] const alias = @import("relative/path.zig");` with one plain string literal, resolved lexically from the importing unit's directory (`.` and `..` allowed), staying under the root, and naming an indexed Zig unit by exact root-relative path bytes, is analysis context: not an entity, not a relationship, no `module` or `IMPORTS`. It is established only when the alias name is declared once at the top level, the path is not the unit itself, and the unit has no `usingnamespace`; an established alias always declares a dependency on the unit it names. |
| Relationships (facts) | `file DEFINES function|container`, `container DEFINES function` for its direct members. In the body of every covered function, top-level or member: a bare call `foo(...)` is a `CALLS` fact only when the unit's top level declares `foo` exactly once, as a covered function, and no parameter, local binding, capture, member of the enclosing container, or `usingnamespace` could give it another meaning; a qualified call `alias.foo(...)` is a cross-unit `CALLS` fact only when `alias` is an established local import alias not shadowed by a parameter, local binding, or container member, the imported unit's analysis is current, and it exports exactly one function `foo`. No `REFERENCES` are emitted. |
| Unresolved | Calls through values and receivers (`self.x()`, a parameter or local qualifier); longer or computed callees (`std.debug.print`, `alias.Container.foo()`); qualifiers that are not local import aliases, including package imports such as `std`; calls through a declined import (root escape, absolute or malformed path, no indexed unit at the exact path, duplicate alias name, self-import) or through an alias whose unit is stale or exports no single `pub fn` of that name; bare calls naming a member of the enclosing container; shadowed, duplicated, or aliased names; every call in a unit or container with `usingnamespace`; calls under logical negation such as `!helper()`, which the pinned grammar parses as a type-shaped callee ([follow-up 001](../followups/001_zig_logical_negation_calls.md)). |
| Unsupported | Every other top-level declaration (`var`, aliases, `@import` bindings, error sets, `test`, `comptime`, `usingnamespace`), reported per kind per unit; a `.zig` import that establishes no alias, reported with its reason; container members other than named `fn` declarations (fields, nested containers and their members, constants, tests), reported per kind; container expressions inside function bodies; nesting deeper than 64 levels. |
| Analysis failed | A unit containing an empty container body such as `struct {}`, which the pinned grammar parses as an error ([follow-up 002](../followups/002_zig_empty_container_grammar.md)). |
| Not recorded | Builtin calls (`@as(...)`) themselves (their arguments are walked); calls inside `test` blocks, `comptime` blocks, and nested containers; `@import` graph semantics. |
| Identity | No signature in identity: a parameter edit keeps the definition; a rename is identity loss. A member's identity includes its container's name: renaming the container is identity loss for the container and for each member, reported with the renamed member as replacement. |
| Known false negatives | **References and calls are same-unit only.** `semidx_references` never lists a caller from another unit, and callers inside methods are not recorded ([follow-up 006](../followups/006_zig_cross_unit_and_member_calls.md)). |

## MCP Output (`semidx-mcp`)

| Aspect | Current behavior |
| --- | --- |
| Transport | Local stdio only, one process per `--root`. No HTTP, no network access. |
| Protocol | `2026-07-28` per-request `_meta` with `server/discover`, and `2025-06-18` after `initialize`; `tools/list` and `tools/call` in both. |
| Tools | `semidx_health`, `semidx_repo_map`, `semidx_find_definitions`, `semidx_references`, `semidx_context` read the published snapshot; `semidx_refresh` rescans and publishes the next one. No resources, prompts, pagination, or subscriptions. |
| Authority | Tools render recorded graph values and select them by exact name, path, language, or role. They resolve nothing and never change a claim's resolution. |
| Per claim | Resolution, freshness, producer, revision, and evidence location (unit, path, range). |
| Bounds | Every list has a limit and reports its total and whether it was truncated. Responses as a whole are not size-bounded. |
| Source text | Off by default: no unit contents are ever returned. `--allow-evidence-text` adds each claim's recorded evidence text, at most 400 bytes; current producers record a name or callee there, not a body. |
| Source-derived values | Always returned: root and unit paths, entity names, designators, ranges, ids, and diagnostic messages. They are derived from the indexed source and go to the client process that launched the server. |
| Versions | Product version `0.1.0-preview.1` in `--version`, `serverInfo.version`, and `semidx_health`; `semantic_contract_version` is always `null`. |
| Refresh | Publishes a new snapshot only on success. A failure after reconciliation started never publishes a partly updated graph: the index is rebuilt from the same scan and published by the next refresh, which then reports `entity_ids_preserved: false`; ids from earlier snapshots name nothing in the rebuilt index. |

The full tool and field reference is [docs/mcp/local_preview.md](../mcp/local_preview.md).
