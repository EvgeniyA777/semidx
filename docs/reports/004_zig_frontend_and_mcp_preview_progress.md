---
title: "Zig frontend and MCP preview progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 004: Zig Frontend And MCP Preview Progress

Companion log for
[docs/plans/004_zig_frontend_and_mcp_preview.md](../plans/004_zig_frontend_and_mcp_preview.md).

## Current Status

Session A (Stages 1–3, the Zig frontend) is in progress. Following the plan's
Execution Recommendations, execution stops after Stage 3 for a separate review
before Session B (Stages 4–5, the MCP preview and documentation).

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Zig grammar and language registration | Completed (`6bcbbd7`) | `.zig` is discovered as `model.Language.zig`; a pinned `tree-sitter-zig` is fetched by the setup script and compiled in the full lane only; a skeletal Zig frontend reports failed, unsupported, or confirmed-empty analysis and emits no facts. |
| Stage 2: Zig definition facts | Completed | Named top-level `fn` declarations and top-level `const` declarations bound directly to a struct/enum/union/opaque expression are current `definition` facts with `DEFINES` from the file. Container members and every other declaration are reported as unsupported. A body edit preserves identity; a rename is identity loss. |
| Stage 3: Zig same-unit simple calls | Pending | |
| Stage 4: Local MCP stdio preview | Pending (Session B) | |
| Stage 5: Dogfood, documentation, and handoff | Pending (Session B) | |

## Plan Readiness Gate

Re-checked by the implementing agent before Stage 1 on 2026-09-14. The plan
names scope, non-scope, stage outputs, verification commands, and stop
conditions; no hard fail. Result: ready for execution.

## Environment

- The semidx MCP server did not connect in the implementing session
  (connection timeout), so its tools were unavailable. Per
  [tooling policy](../agent-policy/tooling.md#mcp-failure-protocol), code was
  located by targeted direct reads of the files the plan names instead.
- `./scripts/setup-tree-sitter-grammars.sh` needed network access once to clone
  `tree-sitter-zig`. Build and test steps ran offline against the local
  checkout.
- Toolchain: Zig 0.16.0, tree-sitter runtime from `/opt/homebrew` (parser ABI
  15), tree-sitter CLI 0.26.3 (used only to inspect parse trees).

## Risk Matrix (Stages 1–3)

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| `.zig` files become source units (plan Stage 1) | Zig files silently invisible, or build outputs ingested | Unit (discovery) | `source/languages` table read by the walk | Mapping removed; `.zig-cache`/`zig-out` contents; `build.zig.zon` | `a scan finds zig units and skips zig build outputs` |
| Core stays parser-free (ADR 002, ADR 005) | New grammar leaks into `test-core` | Build lane | `zig build test-core -Dgrammars-dir=/nonexistent` | Grammar directory absent | lane command |
| Zig grammar reaches the adapter (ADR 002) | ABI mismatch or missing symbol | Unit (adapter) | `tree_sitter.zig` only | ABI newer than runtime | `the local zig grammar parses through the adapter`, ABI test |
| Degradation stays distinguishable (constitution §3, plan Stage 1) | Uncovered or broken Zig reads as empty | Integration (analyzer + reconcile) | `frontends/root` routing into `frontends/zig` | Unparsable source; only-uncovered source; empty source | `frontends/root.zig` Zig tests |
| Only exact declaration shapes become definitions (ADR 005, plan Stage 2) | A `var`, alias, call, conditional, error set, or container member becomes a definition | Integration (frontend through reconcile) | `frontends/zig.containerDeclaration` token reading | Each non-covered shape listed; mutation dropping the `const` requirement | `only exact zig declaration shapes become definitions`, `declarations inside a zig container are not top-level definitions` |
| Zig identity follows graph evidence, not ranges (constitution §4, plan Stage 2) | Body edit breaks ids, or rename silently retargets | Fixture / edit history | Reconciliation over `IdentityEvidence` | Rename; unparsable edit then repair | `zig/edits/01`, `02`, `03`, `05` tests in `tests/vertical_slice_test.zig` |
| Grammar defects surface as failure, not facts (plan stop condition) | A parse tree repaired with `MISSING` nodes yields guessed declarations | Integration | `root.hasError()` gate | `const Empty = struct {};` | `an empty zig container fails the unit's analysis rather than yielding a guess` |

## Stage 1: Zig Grammar And Language Registration

Changed files: `scripts/setup-tree-sitter-grammars.sh`, `build.zig`,
`src/core/model.zig`, `src/source/languages.zig`, `src/source/discovery.zig`,
`src/frontend/tree_sitter.zig`, `src/frontends/root.zig`, new
`src/frontends/zig.zig`, `tests/vertical_slice_test.zig`.

Decisions taken inside the plan's boundary:

- Grammar source: `https://github.com/tree-sitter-grammars/tree-sitter-zig`,
  pinned to `6479aa13f32f701c383083d8b28360ebd682fb7d` (the `master` head on
  2026-09-14, newer than tag `v1.1.2`). Inspection found no stop-condition
  blocker: MIT license, generated `src/parser.c` committed, no external scanner,
  and `LANGUAGE_VERSION 15`, equal to the runtime's
  `TREE_SITTER_LANGUAGE_VERSION`.
- `build.zig` now keeps one `grammar_checkouts` list for both the prerequisite
  check and compilation, so a grammar cannot be compiled without being checked
  or checked without being compiled.
- The skeletal frontend covers nothing yet, so it never claims confirmed
  absence for a unit that declares something: every top-level construct is
  reported as `unsupported_construct`. Diagnostics are aggregated per node kind
  per unit ("N top-level `variable_declaration` ...") rather than emitted per
  occurrence, because Zig units routinely open with many imports and a
  per-line diagnostic would bury the ones that matter. A unit with no
  top-level constructs (comments only, or empty) reports `confirmed_absence`.
- `build.zig` itself is a `.zig` source unit and is discovered like any other.

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass (61 + 24 tests) |
| `zig build test-core --summary all` | Pass |
| `zig build test --summary all` | Pass, 145/145 (baseline before the plan: 140/140) |
| `zig build run -- src` | Runs; 20 Zig units, 0 definitions, only unsupported-construct diagnostics |
| Negative: `.zig` mapping removed from `src/source/languages.zig` | `zig build test-core` fails; mapping restored |

## Stage 2: Zig Definition Facts

Changed files: `src/frontend/tree_sitter.zig`, `src/frontends/zig.zig`,
`src/frontends/root.zig`, `tests/vertical_slice_test.zig`, new
`fixtures/vertical-slice/zig/greeter.zig` and
`fixtures/vertical-slice/zig/edits/0{1..5}_*.zig`.

Node shapes were read from the pinned grammar before extraction was written
(`tree-sitter parse` on probe files and `grammar.js`), then pinned by tests:

- `function_declaration` exposes its name as the `name` field. A missing name
  is left uncovered.
- `variable_declaration` exposes neither its name nor its value as a field. The
  grammar rule is `[pub] [export | extern [string]] [threadlocal] (const | var)
  identifier [: type] ... [= expression] ;`, so the frontend reads the node's
  tokens in order: the `const` keyword, the first `identifier` child, then the
  first node after `=`. Only when that node is itself a `struct_declaration`,
  `enum_declaration`, `union_declaration`, or `opaque_declaration` is the
  declaration a container. To read the anonymous `const` and `=` tokens the
  adapter gained `Node.childCount` and `Node.childAt`; a test pins the exact
  token sequence of `pub const Greeter = struct {};`.

Decisions taken inside the plan's boundary:

- Roles are `function` and `container`; Zig vocabulary is in the extension
  payload as `zig.construct` (`function` or `container`) and `zig.container`
  (`struct`, `enum`, `union`, `opaque`). No shared-core kind was added.
- Identity evidence carries no signature. Zig has no overloading, so a name is
  unique among one container's declarations; a parameter edit therefore keeps
  the definition's identity. `container_path` is empty because the file is the
  only enclosing namespace covered.
- `extern fn` prototypes without a body and `inline` functions are covered:
  each is a named top-level function declaration.
- Error sets (`error{...}`) are not covered: they are types but not containers,
  and the plan's coverage names containers.
- Declarations inside a top-level container are reported once per node kind as
  "declared inside a top-level container". In Zig they live in the container's
  namespace, which nothing here resolves, so a method named like a top-level
  function is not a second definition of that name.
- `confirmed_absence` is now scoped to covered declarations ("declares no
  top-level function or container") and can stand beside unsupported-construct
  diagnostics, as in the Clojure frontend.

Grammar limitation found (residual risk, not a workaround):

- The pinned grammar parses an empty container body such as `struct {}` or
  `opaque {}` as a `container_field` whose name is a `MISSING` identifier. The
  tree therefore has an error, and the whole unit reports `analysis_failed`.
  The `tree-sitter parse` CLI shows the same tree but exits successfully,
  because it does not count `MISSING` nodes as errors. No later upstream commit
  was available. Per the plan's stop conditions the tree is not repaired by
  guessing; the behavior is pinned by a test so a grammar update that fixes it
  is noticed. None of the 20 Zig units under `src/` hits it today.

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test --summary all` | Pass, 154/154 |
| `zig build run -- src` | 20 Zig units, all current; 173 definitions; 0 unresolved, 0 approximate |
| Mutation: `const` requirement removed from `containerDeclaration` | `only exact zig declaration shapes become definitions` fails; restored |
