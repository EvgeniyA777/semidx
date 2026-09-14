---
title: "Zig semantic graph vertical slice progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-13"
---

# 001: Zig Semantic Graph Vertical Slice Progress

Companion log for
[docs/plans/001_zig_vertical_slice.md](../plans/001_zig_vertical_slice.md).

## Current Status

All eight stages are implemented and verified. The slice builds, indexes the
Java and Clojure fixtures, reconciles edits incrementally, and runs locally with
no service and no network access.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created the staged implementation plan and this companion progress log. |
| Stage 1: Zig scaffold and dependency probe | Completed | `build.zig`, `build.zig.zon`, module layout, and the local parser dependency resolution. Toolchain state recorded below. |
| Stage 2: Core semantic model | Completed | `src/core/model.zig` and `src/core/strings.zig`: entity, relationship, assertion, resolution, provenance, source evidence, identity evidence, diagnostics, identity events, and construction-time validation. |
| Stage 3: In-memory graph and query harness | Completed | `src/core/graph.zig`: mutable store, invariant checks, atomic `publish`, immutable `Snapshot`, and the relationship/entity/diagnostic queries the tests read from. |
| Stage 4: Frontend contract and parser adapter | Completed | `src/core/contract.zig` and `src/frontend/tree_sitter.zig`: the batch contract, and the single module that sees the tree-sitter C ABI. |
| Stage 5: Java fixture frontend | Completed | `src/frontends/java.zig` plus `fixtures/vertical-slice/java/`. |
| Stage 6: Clojure fixture frontend | Completed | `src/frontends/clojure.zig` plus `fixtures/vertical-slice/clojure/`. |
| Stage 7: Incremental reconciliation | Completed | `src/core/reconcile.zig` and the edit histories under each fixture's `edits/`. |
| Stage 8: Slice closure and documentation | Completed | This log, `MEMORY.md`, `RULES.md`, `README.md`, `SPEC.md`, `CONFORMANCE.md`, the tooling and testing policies, the plan's frontmatter, and [ADR 002](../adr/002_local_tree_sitter_parser_dependency.md). |

## Stage 1 Dependency Record

Recorded on the development machine before any semantic code depended on it.

| Input | State |
| --- | --- |
| Zig | `zig version` reports `0.16.0` (Homebrew `zig 0.16.0_1`). |
| tree-sitter runtime | `0.26.3` from a Homebrew prefix: `/opt/homebrew/include/tree_sitter/api.h` and `/opt/homebrew/lib/libtree-sitter.a`. `TREE_SITTER_LANGUAGE_VERSION` is 15. |
| tree-sitter runtime source | Not available locally; only headers and a static library are installed. The runtime is therefore linked from an install prefix rather than vendored. |
| Java grammar | Local checkout at `e10607b45ff745f5f876bfa3e94fbcc6b44bdc11`, pinned by `scripts/setup-tree-sitter-grammars.sh`. Parser ABI 14. |
| Clojure grammar | Local checkout at `e43eff80d17cf34852dcd92ca5e6986d23a7040f`, pinned by the same script. Parser ABI 14. |

Both grammars' ABI (14) is within what the runtime accepts (15), and a test
asserts that relation so a future bump fails as a mismatch rather than as a
parse error.

Dependency locations chosen for the slice, and how to override them:

- grammar directory: `.tree-sitter-grammars/` by default,
  `-Dgrammars-dir=<path>` or `SEMIDX_TREE_SITTER_GRAMMARS_DIR`;
- runtime prefix: `/opt/homebrew`, `/usr/local`, `/usr` probed in that order,
  `-Dtree-sitter-prefix=<path>` or `SEMIDX_TREE_SITTER_PREFIX`.

Zig 0.16 moved the filesystem and process APIs behind an explicit `Io`
parameter (`std.Io.Dir`, `std.process.Init`), so code written against earlier
Zig examples does not compile unchanged. This affected `build.zig`,
`src/main.zig`, and the fixture loader only.

No blocker was hit: Zig and both grammars were available locally, and no
network access was needed at any stage.

## Changed Files

Implementation:

- `build.zig`, `build.zig.zon`
- `src/core/{root,model,strings,contract,graph,reconcile}.zig`
- `src/frontend/tree_sitter.zig`
- `src/frontends/{root,java,clojure}.zig`
- `src/root.zig`, `src/main.zig`
- `tests/vertical_slice_test.zig`
- `fixtures/vertical-slice/java/Greeter.java` and `java/edits/*.java`
- `fixtures/vertical-slice/clojure/greeter.clj` and `clojure/edits/*.clj`
- `.gitignore` (Zig build outputs)

Documentation:

- `docs/adr/002_local_tree_sitter_parser_dependency.md`, `docs/adr/README.md`
- `docs/plans/001_zig_vertical_slice.md` (frontmatter only)
- `docs/reports/001_zig_vertical_slice_progress.md`
- `docs/agent-policy/{testing,tooling}.md`
- `RULES.md`, `MEMORY.md`, `README.md`, `SPEC.md`, `CONFORMANCE.md`

## Verification

Commands run from the repository root, with results:

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 32/32 tests passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 32/32 tests passed, proving the shared core builds and is tested with no parser input. |
| `zig build test --summary all` | 58/58 tests passed across four lanes: core 32, tree-sitter adapter 6, frontends 6, fixture and edit-history 14. |
| `zig build test -Dgrammars-dir=/nonexistent` | Fails with the setup message naming the script and both override flags; the core lane still passes within the same run. |
| `zig build run -- fixtures/vertical-slice/java/Greeter.java fixtures/vertical-slice/clojure/greeter.clj` | Printed 1 repository, 2 files, 8 definitions, 31 assertions (26 facts, 5 unresolved, 0 approximate), the five unresolved targets with their explanations, and the unsupported-construct diagnostic for the Java field. No service running, no network access. |
| `zig fmt --check build.zig src tests` | Clean after one formatting pass over `src/frontend/tree_sitter.zig`. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

The full test lane was also run after deleting `.zig-cache/` and `zig-out/`, so
the result is not a cache artifact.

## What The Slice Proves

Mapped to the plan's risk matrix:

- **Zig stack builds locally.** `zig build test` from a clean checkout and a
  cleared cache, with the toolchain state recorded above.
- **Parser dependencies integrate cleanly.** The adapter parses both fixture
  languages through the C ABI. Parse node types appear nowhere in
  `src/core/`; `zig build test-core -Dgrammars-dir=/nonexistent` is the
  mechanical proof.
- **Nodes represent entities.** Ids are allocated by the graph and never derived
  from a range. A core test records two definitions with identical ranges and
  they stay distinct entities; another moves a definition and only its
  projection changes.
- **Facts and unresolved assertions stay distinct.** Construction rejects an
  unresolved target presented as a fact and a resolved target claiming its
  target is missing. The fixtures carry five unresolved targets across both
  languages, and a test walks every relationship asserting that no designator
  target is a fact.
- **`CALLS` does not flatten language semantics.** One occurrence is recorded
  once, as the specialized kind; the reference query returns calls without a
  second assertion for the same occurrence. `java.construct` and `clojure.form`
  retain the language's own vocabulary.
- **Graph is the semantic authority.** Every test expectation is read from a
  published `Snapshot`. No test asserts against a frontend batch, a parse tree,
  or the developer command's output.
- **Incremental reconciliation preserves identity.** Body edits in both
  languages preserve all four entity ids. An added definition preserves the rest.
  A rename produces a `lost` identity event naming its replacement, plus an
  unresolved identity-correspondence assertion — not a silent delete and create.
  Editing the Java unit leaves the Clojure entities, their ranges, and their
  assertion counts untouched.
- **Unavailable analysis is honest.** A cancelled parse yields
  `analysis_unavailable` and leaves the previous state of that unit in place.
  Source that does not parse yields `analysis_failed`. A unit that parses with
  no definitions yields `confirmed_absence`. All three are distinguishable, and
  none of them is an empty result.
- **Local operation and privacy.** `build.zig.zon` declares no dependencies, the
  build reads only local paths, and the developer command indexes and queries
  with no service.
- **Documentation stays truthful.** No document claims published Java or Clojure
  support, an accepted core roster, or a published contract.

## Review Findings

Findings raised and resolved during implementation:

| Finding | Disposition |
| --- | --- |
| `dropAssertionsForUnit` first identified source ingestion by comparing string pointers, which interning makes unreliable. | Fixed: it compares producer names. |
| `addSourceUnit` had an `errdefer` that could free source bytes already owned by the unit record, a double free on an allocation-failure path. | Fixed: the bytes are freed explicitly on each failing step instead. |
| The Clojure frontend first collected a form's values into a fixed 512-node stack array inside a function that recurses to depth 64, which would have overflowed the stack. | Fixed: values are iterated lazily; nothing large is held on the stack. |
| Feeding the previous parse tree back for a changed unit would have been wrong, because tree-sitter requires the edit ranges that produced it and this pipeline receives replacement contents. | Accepted as a limitation: a changed unit is reparsed in full, incrementality is graph-level, and `contract.PreviousParse` marks where an edit-tracking adapter would supply the tree. |

## Skipped Checks

- No benchmark, memory budget, or performance measurement was run. The plan puts
  performance work out of scope, and the only budget implemented is the
  parser byte budget that prevents pathological input from running unbounded.
- Network isolation was argued from the build inputs rather than demonstrated
  with the network physically disabled. The build declares no dependencies and
  every path it reads is local.
- No conformance suite exists. `CONFORMANCE.md` scenario families are satisfied
  in the narrow sense that this slice provides evidence for several of them;
  none of them is adopted as an executable gate yet.

## Blockers

None.

## Residual Risk

- **Fixture-scoped frontends.** Both frontends cover only what their fixtures
  exercise. Java resolves an invocation by matching an unqualified name against
  methods of the enclosing class, with no overload resolution, no inheritance,
  no imports, and no qualified receivers. Clojure treats head position as
  invocation and any other symbol as designation, with no macro expansion, no
  local bindings, no `require` aliases, and no multi-arity handling beyond an
  arity in the signature. Neither is a supported-language claim.
- **Identity evidence is name-shaped.** Correspondence uses scope, language,
  role, name, signature, and containment. Renaming is therefore always identity
  loss, and a file rename would be too, because the scope is the unit path. Both
  are honest outcomes under the constitution, but a stronger identity model may
  be wanted before the graph is persisted.
- **Memory is not reclaimed on removal.** Interned strings of removed entities
  and withdrawn assertions stay in the graph's arena until the graph is
  released. Acceptable for an in-memory slice over a few units; not acceptable
  for a long-lived process over a repository.
- **Snapshot lifetime is by convention.** A `Snapshot` owns its entity and
  assertion arrays but borrows interned strings from the graph, so it must be
  released before the graph. This is documented, not enforced by the type.
- **The runtime dependency is a setup prerequisite.** A clean machine needs a
  tree-sitter runtime installed and the grammar setup script run. The build says
  so precisely when either is missing, but it cannot produce them.

## Next Handoff

The slice is a working in-memory graph, not a product surface. The obvious next
decisions, none of which this slice makes:

1. Whether the fixture evidence here supports admitting any `CORE.md` candidate.
   The plan explicitly forbade admitting one as part of this work, so the
   candidates are unchanged and the admission criteria in `SPEC.md` still apply.
2. Storage and snapshot representation, which `SPEC.md` still lists as
   unspecified. The current snapshot is a value that borrows from a live graph;
   persistence would change that contract.
3. Repository-scale ingestion: source discovery, a source-unit registry that
   survives renames, and invalidation across units. The slice reconciles one
   unit at a time and has no cross-unit assertions to invalidate.
4. A public surface. There is none, deliberately. Any consumer decision is bound
   by constitution §7 and by the contract-lifecycle rules in `SPEC.md`.
