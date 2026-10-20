---
title: "Minimal Python frontend progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-10-20"
---

# 018: Minimal Python Frontend Progress

Companion log for
[docs/plans/018_minimal_python_frontend.md](../plans/018_minimal_python_frontend.md),
implementing [ADR 015](../adr/015_add_minimal_python_frontend.md).

## Current Status

Stage 1 completed; Stage 2 next.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Grammar and Python definitions | Completed | `tree-sitter-python` v0.25.0 pinned and compiled with its external scanner; `.py` units record module-level functions and classes, their direct methods, `DEFINES`, `python.*` labels, and per-kind uncovered diagnostics. Bodies are reported as not analyzed. |
| Stage 2: Bare call facts | Planned | |
| Stage 3: Scan policy for Python repositories | Planned | |
| Stage 4: End-to-end proof, documentation, closure | Planned | |

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
