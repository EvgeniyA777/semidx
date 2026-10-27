---
title: "Minimal Elixir frontend"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-10-27"
---

# 019: Minimal Elixir Frontend

## Goal

Make Elixir source in an indexed repository visible to the graph: `.ex` and
`.exs` files become source units, modules and the clause runs of their functions
and macros become definitions identified by `name/arity`, and same-module local
calls become `CALLS` facts where Elixir's local-call rule leaves exactly one
target, under [ADR 016](../adr/016_add_minimal_elixir_frontend.md). Everything
else is reported, never approximated.

Progress log: created at Stage 1 as
`docs/reports/019_minimal_elixir_frontend_progress.md`.

## Start Rule

The operator requested this work on 2026-10-27 and chose the minimal slice and
a review stop before implementation.

- **Do not start Stage 1 until the operator has accepted ADR 016**, recorded by
  its frontmatter reading `lifecycle: "accepted"` and `status: "accepted"`. If
  review changes a decision, revise ADR 016 and this plan first and reapply the
  Plan Readiness Gate.
- The plan runs ahead of
  [Plan 017](017_adoption_baseline_and_priority_selection.md) and alongside the
  paused [Plan 015](015_optional_jev_ranking_projection.md) by that decision, as
  Plan 018 did, and touches neither plan's files. Plan 017 has recorded no
  runtime measurement, so the Stage 3 exclusion change invalidates no baseline.
- The working tree's untracked `docs/ideas/004_jev_project_watch.md` belongs to
  other work: never stage, edit, or delete it.

## Scope

- Pinned `tree-sitter-elixir` grammar in the setup script and `build.zig`; the
  existing per-checkout scanner rule compiles its `src/scanner.c`.
- `model.Language.elixir`, `tree_sitter.Grammar.elixir`, the `.ex` and `.exs`
  mappings, and Elixir arms in every exhaustive switch over languages.
- `src/frontends/elixir.zig`: the definitions, clause runs, `DEFINES`,
  diagnostics, and call rules ADR 016 states.
- `deps` and `_build` in the default excluded directories, with the pinned
  source-state identity vectors recomputed.
- Capability matrix, `SPEC.md`, `MEMORY.md`, `RULES.md` project context, ADR
  index, MCP reference, and `README.md` where they enumerate languages or
  extensions; one follow-up for the deferred cross-unit surface.

## Non-Scope

- Aliases, `import`, `require`, `use` and every other macro expansion;
  remote and cross-unit calls; dependencies between Elixir units.
- `defdelegate`, `defguard`, `defstruct`, `defexception`, `defprotocol`,
  `defimpl`, `defoverridable` as definitions; behaviours, callbacks, protocols,
  dispatch; module attributes and typespecs as claims.
- Variable binding analysis; `REFERENCES` from Elixir, including captures
  (`&foo/1`); calls in module bodies outside covered clauses; calls inside
  `quote`.
- Templates (`.eex`, `.heex`, `.leex`), `mix.exs` as a build descriptor,
  `mix.lock`, compiled `.beam` files.
- New shared-core kinds, `module`, `IMPORTS`, persistence, schemas, a semantic
  contract version, a release.
- Refactoring other frontends beyond adding Elixir arms to exhaustive switches.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) §3, §4, §6.
- [ADR 002](../adr/002_local_tree_sitter_parser_dependency.md) (local grammar
  sources), [ADR 003](../adr/003_reject_name_match_assertions.md) (no name
  matching), [ADR 010](../adr/010_designator_is_a_structured_name.md)
  (designators), [ADR 016](../adr/016_add_minimal_elixir_frontend.md) (this
  slice).
- [MEMORY.md](../../MEMORY.md), [SPEC.md](../../SPEC.md),
  [CORE.md](../../CORE.md) (`module` stays a blocked candidate),
  [capability matrix](../spec/capability_matrix.md).
- The Python frontend (`src/frontends/python.zig`) is the structural model:
  per-kind uncovered diagnostics with overflow, fixed unresolved reasons, no
  declared dependencies. The Clojure frontend's `definitionSignature` is the
  precedent for a `name/arity` signature.

## Plan-Level Decisions

- **Grammar pin.** `elixir-lang/tree-sitter-elixir` tag `v0.3.5`, commit
  `e2d9e6e0e76b0c436fa48a0b8c32a031d0cbdf49`, language ABI 14, which the local
  runtime (ABI 15, minimum 13) accepts. The checkout has `src/parser.c` and a
  C-only `src/scanner.c` that includes only `tree_sitter/parser.h`. Upstream
  `main` is newer than the tag and is not used.
- **Grammar stop rule.** If the pinned checkout does not compile, link, or load
  at the runtime's ABI, stop and record the failure in the progress log. Do not
  switch to an unpinned ref or patch the grammar; a different pin is an operator
  decision recorded in this plan before resuming.
- **Producer version.** `frontend.elixir` at `plan-019+ts-abi<N>`.
- **No dependencies declared.** Every Elixir fact is decided from one unit, so
  the analyzer needs no repository context and declares no providers.
- **Node shapes.** Read from the pinned grammar's `test/corpus`: a definition
  form is `call` with an `identifier` target and `arguments`, plus an optional
  `do_block`; a remote call is `call` whose target is `dot` with an `alias` or
  other left side and an `identifier` right side; an anonymous call is `call`
  whose target is `dot` with only a left side; a pipe is `binary_operator` with
  operator `|>`; a guard is `binary_operator` with operator `when`; a default is
  `binary_operator` with operator `\\`; a capture is `unary_operator` `&`. Stage
  1 pins each shape it relies on with a parse test through the adapter.
- **Special forms.** The identifier-named `Kernel.SpecialForms` the frontend
  recognizes are one constant in `elixir.zig`: `alias`, `case`, `cond`, `for`,
  `import`, `quote`, `receive`, `require`, `super`, `try`, `unquote`,
  `unquote_splicing`, `with`, `__CALLER__`, `__DIR__`, `__ENV__`, `__MODULE__`,
  `__STACKTRACE__`. `quote` is not walked, `super` is unresolved, and the rest
  are not recorded while their arguments are walked (ADR 016).
- **Designator shape.** `src/designator_shape.zig` gains an Elixir arm: name
  bytes are ASCII alphanumerics, `_`, `?`, and `!`; the qualifier separator is
  `.`.
- **Exclusions change identities.** The pinned vectors in
  `src/source/identity.zig` and
  `fixtures/working_copy_sync/identity_vectors.md` are recomputed from the
  implementation, not hand-edited, and the change is called out in the log.
- **Setup needs the network once.** Stage 1 reruns
  `./scripts/setup-tree-sitter-grammars.sh`, which clones the new checkout;
  every later build and test is offline. If the network is unavailable, stop
  before Stage 1 code and record it; do not vendor the grammar into the
  repository.

## Drift Control

Readiness check, 2026-10-27:

- Constitution §3, §4, §6, §11: answered in ADR 016; no clause is reinterpreted.
- `CORE.md`: `module` and `IMPORTS` stay blocked candidates; the `defmodule`
  role is a `definition` role, not an admission.
- `SPEC.md` owns the language question as an open requirement; Stage 4 updates
  its implementation paragraph, not the requirement.
- [Follow-up 007](../followups/007_grammar_setup_fetches_unused_unpinned_sources.md):
  the new grammar is a product grammar, pinned by full commit id, and listed in
  both `PRODUCT_GRAMMARS` and `grammar_checkouts`, which the setup script's
  existing check enforces.
- `GLOSSARY.md`: no new durable vocabulary. "Clause run" is owned by ADR 016.
- Capability matrix, `MEMORY.md`, `RULES.md`, MCP reference, README: aligned at
  Stage 4 closure, with the closure check recorded in the log.

## Stages

### Stage 1: Grammar And Elixir Definitions

Purpose: Elixir units parse and record their definitions.

Outputs:

- setup script `PRODUCT_GRAMMARS` and `build.zig` `grammar_checkouts` pin and
  compile the grammar and its scanner, in the same order;
- `Language.elixir`, `Grammar.elixir`, `.ex` and `.exs` mappings, Elixir arms
  in every exhaustive language switch (at least `src/frontends/root.zig`,
  `src/designator_shape.zig`, `src/claim_sample.zig`, and
  `tests/vertical_slice_test.zig`, as Plan 018 found; the compiler names any
  other);
- `src/frontends/elixir.zig` recording modules (top-level and nested), clause
  runs of `def`/`defp`/`defmacro`/`defmacrop` with `name/arity` signatures,
  `elixir.construct`, `elixir.module`, `elixir.min_arity`, `DEFINES`,
  split-run diagnostics, uncovered-form diagnostics, `analysis_failed`, and
  `confirmed_absence`, with no call analysis yet (a covered body is not walked,
  and the coverage note says so);
- tests: mapping (`.ex`, `.exs` yes; `.eex`, `.heex` no), grammar ABI, parse of
  a heredoc and a sigil through the adapter, each node shape the frontend relies
  on, definitions and roles, nested module naming and containment, multi-clause
  run as one entity with a spanning range, guard and keyword-`do:` heads,
  bodiless head with defaults and `elixir.min_arity`, split run reported,
  operator and `unquote` heads unsupported, documentation attributes silent and
  other attributes reported, broken parse, unit with no module (for example
  `config/config.exs`), identity preserved across a body edit, a clause addition,
  and a `def`→`defp` switch, and lost on an arity change and a module rename.

DoD: `zig build test --summary all` and `zig build test-core
-Dgrammars-dir=/nonexistent --summary all` pass; `zig build run -- <an .ex
file>` prints Elixir definitions with their signatures.

### Stage 2: Local Call Facts

Purpose: calls in covered clauses, under ADR 016's local-call rule.

Outputs: the clause walk (guards, defaults, bodies, `fn` bodies, capture
bodies), arity counting, innermost-module lookup, special-form handling,
decisions and reasons, designators; tests for:

- a fact for each arity form: parenthesized, no parentheses, keyword list as one
  argument, `do` block as one argument, pipe into a call, pipe into a bare
  identifier, a call inside `fn`, a call inside `&foo(&1, 2)`, a call in a guard
  and in a default value, and a call whose arity is inside a default range;
- each unresolved reason: arity not defined in the module (including a
  `Kernel` name such as `is_nil`), split run, overlapping default ranges,
  `super`, remote call through an alias (qualifier recorded as written), remote
  call through a variable, atom, or `__MODULE__` (no qualifier), anonymous call
  and non-identifier callee (empty name);
- a call in a nested module resolving to the nested module's function past a
  same-named function of the enclosing module, and never to the enclosing one;
- a `quote` body not walked and reported; `case`/`with`/`for` not recorded
  while calls in their arguments are; a bare identifier not recorded;
- calls to a `defp` and to a `defmacro` of the same module both resolving.

DoD: the Stage 1 commands pass; every ADR 016 call check has a named test.

### Stage 3: Scan Policy For Mix Projects

Purpose: dependency source and build output under the root do not flood the
index.

Outputs: `deps` and `_build` added to `default_excluded_directories` in
`src/source/scan.zig` with a comment naming Mix; pinned vectors and their
fixture document recomputed; a discovery test that `deps/x/lib/x.ex` and
`_build/dev/lib/x.ex` are not units while `lib/x.ex` is.

DoD: Stage 1 commands and `zig build test-mcp` pass.

### Stage 4: End-To-End Proof, Documentation, Closure

Purpose: prove the slice through the index and MCP, and align documents.

Outputs:

- an index-level test in `tests/vertical_slice_test.zig` over several Elixir
  units: a rescan with one edit reanalyzes one unit; a broken parse leaves
  previous claims stale; two units defining the same module name never resolve
  calls across each other;
- a manual MCP run over a temporary root with a small Mix-shaped tree (`lib/`,
  `test/`, `config/`, a `deps/` directory) whose `semidx_outline`,
  `semidx_repo_map language=elixir`, and `semidx_references` output is recorded
  in the log;
- `tests/mcp_fixture_gate_test.zig` and any MCP test that enumerates languages
  updated to accept `elixir`;
- capability matrix Elixir section (including the macro-expansion boundary),
  source ingestion row, and exclusion list; `SPEC.md` implementation paragraph;
  `MEMORY.md`; `RULES.md` project-context language list; MCP reference language lists in `docs/mcp/local_preview.md` and
  `docs/mcp/habit_loop_gate.md`; README language mention;
- a follow-up in `docs/followups/` for aliases, imports, remote and cross-unit
  calls, `defdelegate`, and `use`, indexed in its README;
- log closed and this plan marked completed.

DoD: `zig fmt --check build.zig src tests`, `zig build test`, `zig build
test-mcp`, `zig build preview-gate` pass; `wc -l RULES.md` stays within its
budget; drift-control closure recorded.

## Verification Strategy

| Risk | Check |
| --- | --- |
| An arity is miscounted and a call resolves to the wrong function | one test per arity form in Stage 2 |
| A multi-clause function becomes several entities, or two arities one | multi-clause run test and `foo/1` plus `foo/2` test |
| A split or overlapping definition yields a false fact | split-run and overlapping-default tests |
| A nested module's call resolves to the enclosing module | nested-module test |
| Calls inside `quote` attributed to the macro | `quote` not-walked test |
| External scanner not linked | heredoc and sigil parse through the adapter; link failure is a build error |
| Core picks up parser dependency | `test-core -Dgrammars-dir=/nonexistent` |
| Uncovered forms read as confirmed absence | uncovered-diagnostic and confirmed-absence tests |
| Identity regressions | body edit, clause addition, `def`→`defp` preserve; arity change and rename lose; broken parse stale |
| Identity vectors drift silently | recomputed pinned vectors committed with the exclusion change |
| `deps` exclusion hides more than intended | discovery test names both excluded and kept paths; consequence stated in ADR 016 and the capability matrix |
| MCP rejects `elixir` filters | `zig build test-mcp` and the recorded manual run |

## Definition Of Done

- ADR 016 accepted before Stage 1; Stages 1-4 committed with log entries and
  verification.
- `.ex` and `.exs` units are indexed with the ADR 016 subset; every unresolved
  and unsupported case named there is tested.
- `zig fmt --check build.zig src tests`, `zig build test-core
  -Dgrammars-dir=/nonexistent`, `zig build test`, `zig build test-mcp`, and
  `zig build preview-gate` pass.
- Capability matrix, `SPEC.md`, `MEMORY.md`, `RULES.md`, ADR index, MCP
  reference, and README agree with the implementation; no document claims
  Elixir support beyond the slice.
