---
title: "Minimal Python frontend"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-10-20"
---

# 018: Minimal Python Frontend

## Goal

Make Python source in an indexed repository visible to the graph: `.py` files
become source units, top-level functions, classes, and their direct methods
become definitions, and same-unit bare calls become `CALLS` facts where
Python's scoping leaves exactly one meaning, under
[ADR 015](../adr/015_add_minimal_python_frontend.md). Everything else is
reported, never approximated.

Progress log:
[018: Minimal Python Frontend Progress](../reports/018_minimal_python_frontend_progress.md).

## Start Rule

The operator requested this work on 2026-10-20 and chose the minimal slice. It
runs ahead of [Plan 017](017_adoption_baseline_and_priority_selection.md) and
alongside the paused [Plan 015](015_optional_jev_ranking_projection.md) by that
decision; it touches neither plan's files.

## Scope

- Pinned `tree-sitter-python` grammar in the setup script and `build.zig`,
  including compiling a grammar's external scanner when its checkout has one.
- `model.Language.python`, `tree_sitter.Grammar.python`, the `.py` mapping, and
  every exhaustive switch over languages.
- `src/frontends/python.zig`: the definitions, `DEFINES`, diagnostics, and call
  rules ADR 015 states.
- `.venv`, `venv`, `.tox`, `.nox` in the default excluded directories, with the
  pinned source-state identity vectors recomputed.
- Capability matrix, `SPEC.md`, `MEMORY.md`, ADR index, MCP reference, and
  `README.md` where they enumerate languages or extensions.

## Non-Scope

- Imports of any kind, cross-unit resolution, dependencies between Python units.
- Attribute, receiver, `super()`, and computed call resolution; inheritance;
  dispatch; builtins; decorator evaluation.
- `REFERENCES` from Python, module-level statement analysis, class attributes,
  nested classes, definitions inside module-level blocks.
- `.pyi` stubs, notebooks, `pyproject.toml` or any build descriptor.
- New shared-core kinds, `module`, `IMPORTS`, persistence, schemas, a semantic
  contract version, a release.
- Refactoring other frontends beyond adding Python arms to exhaustive switches.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) §3, §4, §6.
- [ADR 002](../adr/002_local_tree_sitter_parser_dependency.md) (local grammar
  sources), [ADR 003](../adr/003_reject_name_match_assertions.md) (no name
  matching), [ADR 010](../adr/010_designator_is_a_structured_name.md)
  (designators), [ADR 015](../adr/015_add_minimal_python_frontend.md) (this
  slice).
- [MEMORY.md](../../MEMORY.md), [SPEC.md](../../SPEC.md),
  [capability matrix](../spec/capability_matrix.md).
- The Zig frontend (`src/frontends/zig.zig`) is the structural model: covered
  bodies, over-approximated locals, per-kind uncovered diagnostics.

## Plan-Level Decisions

- **Grammar pin.** `tree-sitter/tree-sitter-python` tag `v0.25.0`, commit
  `293fdc02038ee2bf0e2e206711b69c90ac0d413f`, language ABI 15, which the local
  runtime (ABI 15, minimum 13) accepts.
- **Scanner compilation.** `addParserDeps` compiles `src/scanner.c` for any
  checkout that has one, so the rule is per grammar rather than a Python special
  case; `resolveParserDeps` still requires only `parser.c`.
- **Producer version.** `frontend.python` at `plan-018+ts-abi<N>`.
- **No dependencies declared.** Every Python fact is decided from one unit, so
  the Python analyzer needs no repository context and declares no providers.
- **Exclusions change identities.** The pinned vectors in
  `src/source/identity.zig` and
  `fixtures/working_copy_sync/identity_vectors.md` are recomputed from the
  implementation, not hand-edited, and the change is called out in the log.

## Stages

### Stage 1: Grammar And Python Definitions

Purpose: Python units parse and record their definitions.

Outputs:

- setup script and `build.zig` pin and compile the grammar and its scanner;
- `Language.python`, `Grammar.python`, `.py` mapping, Python arms in every
  exhaustive language switch;
- `src/frontends/python.zig` recording functions, classes, methods, `DEFINES`,
  labels, uncovered-construct diagnostics, `analysis_failed`, and
  `confirmed_absence`, with no call analysis yet (a covered body is not yet
  walked, and the coverage note says so);
- tests: mapping, grammar ABI, scanner-dependent parse, definitions and roles,
  decorated and async forms, uncovered constructs reported, broken parse,
  empty module, identity preserved across a body edit and lost on rename.

DoD: `zig build test --summary all` and `zig build test-core -Dgrammars-dir=/nonexistent --summary all` pass;
`zig build run -- <a .py file>` prints Python definitions.

### Stage 2: Bare Call Facts

Purpose: calls in covered bodies, under ADR 015's four rules.

Outputs: the call walk, binding collection for the definition and the module,
decisions and reasons, designators; tests for each rule's fact and each
unresolved reason ADR 015 lists, the method-past-same-named-method case,
attribute and computed callees, nested `def`/`lambda` attribution, nested class
not walked.

DoD: the Stage 1 commands pass; every ADR 015 call check has a named test.

### Stage 3: Scan Policy For Python Repositories

Purpose: a virtual environment under the root does not flood the index.

Outputs: exclusions added; pinned vectors and their fixture document
recomputed; a discovery test that a `.venv/lib/x.py` is not a unit while
`src/x.py` is.

DoD: Stage 1 commands and `zig build test-mcp` pass.

### Stage 4: End-To-End Proof, Documentation, Closure

Purpose: prove the slice through the index and MCP, and align documents.

Outputs: an index-level test over several Python units (rescan with one edit
reanalyzes one unit; stale-on-broken-parse); a manual MCP run over a temporary
root with Python files whose `semidx_repo_map` and `semidx_references`
output is recorded in the log; capability matrix Python section, source
ingestion row, `SPEC.md` implementation paragraph, `MEMORY.md`, ADR index,
MCP reference language lists, README language mention; log closed and this plan
marked completed.

DoD: `zig fmt --check build.zig src tests`, `zig build test`, `zig build
test-mcp`, `zig build preview-gate` pass; drift-control closure recorded.

## Verification Strategy

| Risk | Check |
| --- | --- |
| A rebinding form is missed and a call becomes a false fact | one test per binding form in ADR 015 rule 1 and rule 3 |
| Decorated definition presented as the call target | decorated-target test |
| Class scope wrongly consulted or wrongly ignored | method-past-same-named-method test |
| External scanner not linked | indentation-dependent parse test through the adapter |
| Core picks up parser dependency | `test-core -Dgrammars-dir=/nonexistent` |
| Uncovered constructs read as confirmed absence | uncovered-diagnostic and confirmed-absence tests |
| Identity regressions | body edit preserves, rename loses, broken parse stale |
| Identity vectors drift silently | recomputed pinned vectors committed with the exclusion change |
| MCP rejects `python` filters | `zig build test-mcp` and the recorded manual run |

## Definition Of Done

- ADR 015 accepted; Stages 1-4 committed with log entries and verification.
- `.py` units are indexed with the ADR 015 subset; every unresolved and
  unsupported case named there is tested.
- `zig fmt --check build.zig src tests`, `zig build test-core -Dgrammars-dir=/nonexistent`,
  `zig build test`, `zig build test-mcp`, and `zig build preview-gate` pass.
- Capability matrix, `SPEC.md`, `MEMORY.md`, ADR index, MCP reference, and
  README agree with the implementation; no document claims Python support
  beyond the slice.
