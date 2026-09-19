---
title: "Use local tree-sitter C sources for language frontends"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# 002: Use Local Tree-sitter C Sources For Language Frontends

## Feature Or Dependency

The first Zig vertical slice needs to turn Java and Clojure source text into
structure a language frontend can read. That is a parser dependency, and
[ADR 001](001_choose_zig_implementation_language.md) deliberately left it open.

This record fixes how parsing enters the build and where its inputs come from.
It does not decide which languages `semidx` supports, which is an open `SPEC.md`
requirement.

## Decision

Language frontends parse through the tree-sitter C ABI, behind one adapter
module.

- Grammar C sources are pinned local checkouts. `scripts/setup-tree-sitter-grammars.sh`
  already materializes them at fixed commits under `.tree-sitter-grammars/`;
  `build.zig` compiles `parser.c` from that directory. The location is
  overridable with `-Dgrammars-dir=` or `SEMIDX_TREE_SITTER_GRAMMARS_DIR`.
- The tree-sitter runtime comes from a local install prefix, discovered at
  configure time and overridable with `-Dtree-sitter-prefix=` or
  `SEMIDX_TREE_SITTER_PREFIX`. It is linked statically.
- `build.zig.zon` declares no dependencies. Neither a build nor an index run
  fetches anything.
- Exactly one module, `src/frontend/tree_sitter.zig`, sees the C ABI. It exposes
  parsing and node traversal and nothing else. The shared core has no include
  path, no C source, and no knowledge that tree-sitter exists, which
  `zig build test-core` proves by building and running the core alone with the
  grammar directory pointed at a path that does not exist.

Missing parser inputs fail the build with a message naming the setup script and
both override flags, rather than silently degrading to a different parsing
strategy.

## Rationale

The plan for the first slice required parser dependencies to be local and
explicit, and forbade replacing them with ad hoc regex parsing if setup proved
awkward. Tree-sitter satisfies that: its generated parsers are plain C with no
runtime service, its C ABI needs no binding generator from Zig, and the grammar
checkouts this repository already pins were built for exactly this purpose.

Two inputs were treated differently because they are differently available.
Grammar sources are reproducible from pinned commits through a script that is
already in the repository, so they are referenced rather than duplicated into
version control — the generated `parser.c` files total several megabytes.
The runtime has no local source on the development machine, only headers and a
static library from a system package, so it is resolved from an install prefix
and recorded as a setup prerequisite rather than vendored.

The alternative of vendoring everything into the repository would remove the
setup step, at the cost of committing multi-megabyte generated C and a second
copy of a dependency the repository already knows how to pin. The alternative of
a package-manager dependency in `build.zig.zon` would fetch over the network at
build time, which conflicts with keeping the toolchain reproducible from what is
already on the machine.

Writing a parser per language was rejected outright: the slice is meant to test
the shared semantic model against two language families, not to spend its budget
on lexing.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Compatible. A parse tree is an input
   to a frontend, never an answer. Every semantic claim in the slice is read
   from a published graph snapshot.
2. **Nodes as entities, not chunks.** Compatible. Parse nodes supply names,
   containment, and ranges. Ranges are stored as evidence; entity identity comes
   from identity evidence and is allocated by the graph.
3. **Facts, unresolved assertions, and approximate assertions stay distinct.**
   Compatible. A frontend records a fact only when it resolved the target inside
   the analyzed unit; anything else stays an unresolved designator, and
   construction rejects the combination of an unresolved target with a fact.
4. **Stable semantic identity across edits.** Compatible. Nothing from the
   parser is used as identity. The adapter exposes no node id, and a node's
   position reaches the model only as evidence.
5. **Incrementality and consistent observation.** Compatible. An edit reanalyzes
   the changed source unit and reconciles it against the existing graph. The
   slice reparses a changed unit in full rather than feeding the previous tree
   back, because reusing a tree requires the edit ranges that produced it;
   `contract.PreviousParse` is where an adapter that tracks edits would supply
   one.
6. **Language frontends preserve meaning.** Compatible. The adapter is
   language-neutral; `method_declaration` and `defn` stay in extension payloads,
   and neither language's constructs became shared-core kinds.
7. **Consumers do not define the model.** Not applicable. No consumer or public
   surface is introduced here.
8. **Local operation without mandatory source-data transmission.** Compatible,
   and this is the main reason the dependency is shaped this way. No build step
   and no index run contacts the network, and no source-derived data leaves the
   machine.

## Consequences

- A clean checkout needs two local setup steps before `zig build test` can run:
  `./scripts/setup-tree-sitter-grammars.sh`, and a tree-sitter runtime providing
  `tree_sitter/api.h` and `libtree-sitter.a` under a discoverable prefix.
  `zig build test-core` needs neither.
- Grammar versions are whatever the setup script pins. Changing a pin can change
  fixture expectations, so a grammar bump is a change to verify, not a refresh.
- The grammar ABI and the runtime ABI must stay compatible. A test asserts that
  each grammar's ABI version is within what the runtime supports, so a mismatch
  fails as a mismatch instead of as a parse error.
- If a language needs analysis tree-sitter cannot provide — type resolution
  across units, for instance — that frontend gains a second producer rather than
  this decision being reversed. Coverage per producer is already a thing the
  model records.
- A parse that cannot run is reported as unavailable analysis, so a failing
  parser can never be read as an absence of entities.

## Verification Evidence And Planned Checks

Evidence from the first slice, on Zig 0.16.0 with tree-sitter runtime 0.26.3:

- `zig build test-core` passes with `-Dgrammars-dir=/nonexistent`, proving the
  shared core builds and is tested without any parser input.
- `zig build test` fails with the setup message when parser inputs are missing,
  and otherwise runs the adapter, frontend, and fixture lanes.
- Adapter tests parse Java and Clojure through the C ABI, observe a syntax error
  as an error rather than as an empty tree, and cancel a parse that exceeds its
  byte budget.
- Frontend tests show a cancelled parse producing an unavailable-analysis
  diagnostic with no entities, distinct from a parsed unit that confirms absence.
- `zig build run -- <files>` indexes and queries with no service running.
