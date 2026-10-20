---
title: "Minimal Python frontend progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-10-20"
---

# 018: Minimal Python Frontend Progress

Companion log for
[docs/plans/018_minimal_python_frontend.md](../plans/018_minimal_python_frontend.md),
implementing [ADR 015](../adr/015_add_minimal_python_frontend.md).

## Current Status

Plan 018 is complete. Stages 1-4 are implemented and verified; the closure lane passes. Residual risks are recorded below and the deferred coverage in [Follow-up 022](../followups/022_python_cross_unit_and_attribute_calls.md).

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Grammar and Python definitions | Completed | `tree-sitter-python` v0.25.0 pinned and compiled with its external scanner; `.py` units record module-level functions and classes, their direct methods, `DEFINES`, `python.*` labels, and per-kind uncovered diagnostics. Bodies are reported as not analyzed. |
| Stage 2: Bare call facts | Completed | Every call in a covered body is recorded. A bare callee is a `CALLS` fact only under ADR 015's four rules; every other call is unresolved with its own reason. Binding walks use an explicit stack, so no binding is lost to a depth limit. |
| Stage 3: Scan policy for Python repositories | Completed | `.venv`, `venv`, `.tox`, and `.nox` are excluded by default; the two pinned source-state vectors were recomputed because the policy is hashed. |
| Stage 4: End-to-end proof, documentation, closure | Completed | An index-level test and a manual `semidx-mcp` run over a temporary Python root prove the slice end to end; the habit-loop gate's "unindexed file" changed from `tool.py` to `tool.rb`; capability matrix, `SPEC.md`, `MEMORY.md`, `RULES.md`, README, MCP references, ADR index, and Follow-up 022 are aligned. |

## Plan Readiness Gate

Applied on 2026-10-20 before Stage 1. Scope, non-scope, stage order, outputs,
verification commands, and DoD are explicit and tied to ADR 015. The grammar pin
was checked before writing the plan: `v0.25.0` declares language ABI 15 and the
local runtime accepts 13-15. The one build change it implies, compiling an
external scanner, is a named plan decision. No hard fail.

## Stage 1: Grammar And Python Definitions

Changed: `scripts/setup-tree-sitter-grammars.sh`, `build.zig` (grammar list;
`scanner.c` compiled whenever a pinned checkout has one),
`src/core/model.zig`, `src/frontend/tree_sitter.zig`,
`src/source/languages.zig`, `src/frontends/python.zig` (new),
`src/frontends/root.zig`, Python arms in `src/designator_shape.zig`,
`src/claim_sample.zig`, and `tests/vertical_slice_test.zig`.

Verification:

- `./scripts/check-zig-version.sh`: 0.16.0 matches.
- `./scripts/setup-tree-sitter-grammars.sh`: Python checkout at `293fdc0`,
  `src/scanner.c` present.
- `zig build test --summary all`: 22/22 steps, 348/350 passed, 2 skipped (the
  pre-existing skips).
- `zig build test-core -Dgrammars-dir=/nonexistent --summary all`: 109/110
  passed, 1 skipped.
- `zig fmt --check build.zig src tests`: clean.
- `zig build run -- demo.py` (a class with one method and a function): three
  Python definitions and the "2 function and method bodies were not analyzed
  for calls" diagnostic.

New tests: the adapter parses indentation-dependent source (fails without the
external scanner), the Python grammar's ABI is accepted, `.py` maps and `.pyi`
does not, definitions/roles/labels/containment/`DEFINES`, uncovered constructs
by kind with docstrings skipped, confirmed absence, a broken parse leaving the
previous definition stale, and identity preserved across body and parameter
edits but lost (with replacements) on a class rename.

## Stage 2: Bare Call Facts

Changed: `src/frontends/python.zig` (binding collection for the module region,
the enclosing definition, and unit-wide `global`/`:=`/`import *`; the call walk;
`decideName`; capabilities now declare `CALLS`), `src/frontends/root.zig`
(tests).

Design note: Zig's binding walk stops at depth 64 because a Zig binding only
shadows calls in its own block or deeper. A Python binding such as `:=` deep in
an expression binds for the whole function, so a depth cut-off could hide a
binding and make a call a false fact. Every Python walk therefore uses an
explicit stack and reads the whole subtree; there is no depth diagnostic.

Verification:

- `zig build test --summary all`: 22/22 steps, 351/353 passed, 2 skipped.
- `zig build test-core -Dgrammars-dir=/nonexistent --summary all`: 109/110
  passed, 1 skipped.
- `zig fmt --check build.zig src tests`: clean.
- `zig build run -- demo.py`: the method's `helper()` is now a fact (10 facts,
  0 unresolved) and the "bodies were not analyzed" diagnostic is gone.

New tests map to ADR 015's checks: the fact for an undecorated module-level
function and for a class; a recursive call; a method's `helper()` resolving past
the class's own `helper` method; a default value's call not attributed to the
body; unresolved for a decorated target, for a second module-level binding by
assignment, import, `global`, `:=` in another function, `if`-nested `def`,
`for`, `try`/`import`, `with ... as`, `type`, and `match`; for an imported name;
for an unbound name (builtin); for every rule-1 binding form (parameters,
`*args`, `**kw`, assignment, `for`, `with ... as`, `except ... as`, `import`,
`del`, comprehension, `lambda`, nested `def`, `match` capture, `:=`); for
`import *`; an attribute callee keeping its last name with no qualifier; and a
nested class reported and not walked.

## Stage 3: Scan Policy For Python Repositories

Changed: `src/source/scan.zig` (four exclusions), `src/source/discovery.zig`
(test), `src/source/identity.zig` (pinned vectors),
`fixtures/working_copy_sync/identity_vectors.md` (update note).

Pinned vectors, recomputed by running the pinned-vector test against the new
policy and copying the values it found:

| Case | Before | After |
| --- | --- | --- |
| Empty, default policy | `bd5e16cf...251f2f0e` | `31812246...36171c16` |
| One unit, default policy | `79fe9b6c...27aed27b` | `f28698e9...30fb52f8` |

Every `source_state_id` computed under the default policy changes once with
this commit; nothing persists one, so the effect is that a running server
built before it and one built after it report different ids for the same tree.
No document cited the old values.

Verification:

- `zig build test --summary all`: 22/22 steps, 352/354 passed, 2 skipped.
- `zig build test-mcp --summary all`: 11/11 steps, 85/86 passed, 1 skipped.

New test: `app/main.py` is a Python unit; `app/types.pyi` is not a unit;
`.py` files under `.venv/`, `venv/`, `.tox/`, and `.nox/` are not entered, and
none of this produces a diagnostic.

## Stage 4: End-To-End Proof, Documentation, Closure

Changed: `tests/vertical_slice_test.zig` (index-level Python test),
`tests/mcp_fixture_gate_test.zig` and `docs/mcp/habit_loop_gate.md` (see
below), `docs/spec/capability_matrix.md`, `SPEC.md`, `MEMORY.md`, `RULES.md`
(one factual language list), `README.md` (same), `docs/mcp/local_preview.md`,
`docs/adr/README.md`, `docs/followups/022_python_cross_unit_and_attribute_calls.md`
and its index row.

Index-level test: three Python units and one under `.venv/`; the scan adds three;
`run -> local` is a fact; `run -> shared`, where `shared` is defined in another
indexed unit and imported, stays unresolved and no fact targets `shared`
(ADR 003); editing one unit is one frontend invocation with every id kept; a
unit that stops parsing reports `analysis_failed` and its class goes stale.

Manual MCP run (`zig-out/bin/semidx-mcp --root <tmp>`, legacy initialized
shape) over `app/main.py`, `app/util.py`, and `.venv/lib/dep.py`:

- `semidx_sync`: `units.total = 2`, `by_language.python = 2`; the `.venv` file
  is not a unit.
- `semidx_repo_map {"language": "python"}`: `app/main.py` with `run`, `local`
  (functions) and `Service` (class), one `unsupported_construct` (the import);
  `app/util.py` with `shared`.
- `semidx_references {"name": "run", "language": "python", "direction":
  "both"}`: incoming fact from method `handle`; outgoing fact to `local`;
  outgoing unresolved `CALLS` with designator `{"name": "shared"}`. No error.

Gate fix: the habit-loop gate's fixture profile wrote `tool.py` as "a file with
an extension no frontend declares" and required it not to be a unit. That stopped
being true with this plan, and the gate failed with "health counts 8 units for
7 indexable files". The file is now `tool.rb`; the property the gate checks is
unchanged.

Closure verification:

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-core -Dgrammars-dir=/nonexistent --summary all`: 110/111
  passed, 1 skipped.
- `zig build test --summary all`: 22/22 steps, 353/355 passed, 2 skipped.
- `zig build test-mcp --summary all`: 11/11 steps, 85/86 passed, 1 skipped.
- `zig build preview-gate`: success, including `parsers_available: 4 languages`
  in the repository-copy profile.
- `./scripts/check-readme-stewardship.sh --all`: passes.

## Drift Control

Checked against the constitution (§3, §4, §6 unchanged in meaning; no edit),
ADR 003 (no name matching: proven by the cross-unit test), ADR 010
(designators: names only, no qualifier), `CORE.md` (no kind admitted, not
edited), `CONFORMANCE.md` (no scenario family changed), and `GLOSSARY.md` (no
new durable term). Updated: capability matrix, `SPEC.md`, `MEMORY.md`,
`RULES.md`, `README.md`, `docs/mcp/local_preview.md`,
`docs/mcp/habit_loop_gate.md`, ADR index, follow-ups. No document claims
Python support beyond the slice.

## Review

Self-review of the final diff, recorded with disposition:

- **Depth limit could hide a binding (fixed in Stage 2 design).** Zig's walk
  stops at depth 64; a Python `:=` deeper than that would still bind for the
  whole function. Every Python walk uses an explicit stack.
- **A covered definition's own name as a local (fixed in Stage 2).** Reading the
  `def`'s own name as a binding of its body would leave every recursive call
  unresolved; it is excluded for the walked definition only, and a test pins it.
- **Gate fixture assumed `.py` is unindexed (fixed in Stage 4).** See above.
- **Run-time rebinding (accepted, documented).** Another module's assignment,
  `globals()`, `exec`, or `setattr` can rebind a module global; ADR 015 and the
  capability matrix state the boundary, as the Clojure frontend's same-unit
  facts already have it.

## Residual Risk

- A binding form the grammar exposes under a node kind this frontend does not
  list would be missed. The listed kinds follow the language reference's
  binding constructs; a missed one turns a call into a false fact only when that
  name is also bound once by an undecorated module-level definition.
- Same-identity definitions (getter and setter) correspond by source order, so
  reordering them swaps their ids without an identity event.
- Every `source_state_id` under the default policy changed once (Stage 3).
- The grammar setup now fetches a fourth repository; a machine that has not
  rerun `./scripts/setup-tree-sitter-grammars.sh` cannot build until it does.
