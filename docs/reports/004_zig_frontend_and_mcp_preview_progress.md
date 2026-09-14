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
| Stage 1: Zig grammar and language registration | Completed | `.zig` is discovered as `model.Language.zig`; a pinned `tree-sitter-zig` is fetched by the setup script and compiled in the full lane only; a skeletal Zig frontend reports failed, unsupported, or confirmed-empty analysis and emits no facts. |
| Stage 2: Zig definition facts | Pending | |
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
