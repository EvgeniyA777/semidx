---
title: "Grammar setup fetches unused and unpinned sources"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-14"
---

# Grammar Setup Fetches Unused And Unpinned Sources

## Classification

`release_readiness`

## Source

Found while verifying the Plan 005 Stage 2 clean-clone setup path.

See
[Plan 005 progress, Stage 2](../reports/005_mcp_preview_release_readiness_progress.md#stage-2-install-and-local-agent-configuration).

## Current Behavior

`scripts/setup-tree-sitter-grammars.sh` clones five grammars. `build.zig`
compiles three of them (`tree-sitter-java`, `tree-sitter-clojure`,
`tree-sitter-zig`), each pinned to a commit. It also clones
`tree-sitter-typescript` (pinned) and `tree-sitter-elixir` at `main`, which is
not pinned; neither is compiled or used.

The build itself is reproducible: every compiled grammar is pinned, and nothing
is fetched at build or index time. The setup step is not: it needs network
access for two repositories the product does not use, and one of them resolves
to whatever `main` is on the day it runs.

## Why Deferred

Plan 005 Stage 2 documents the existing setup path and does not change
toolchain scripts. The unused grammars were installed for analysis tooling
outside the current build (see `MEMORY.md` on toolchain installers), so
removing them may affect other consumers of the script.

## Acceptance Direction

- Either pin `tree-sitter-elixir` to a commit, or stop fetching grammars the
  build does not compile, or split product setup from analysis-tool setup.
- Keep one list of product grammars shared by the script and `build.zig`, or
  check that they agree.

## Required Tests

- A clean clone plus the setup script plus `zig build` succeeds.
- Running the setup script twice fetches no moving reference.
- If product and tooling setup are split, the product path clones only the
  grammars `build.zig` compiles.
