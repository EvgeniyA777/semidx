---
name: semidx-code-exploration
description: "Explore semidx source, callers, tests, and blast radius with Semantic Code Indexing before manual search. Use for cold-start orientation, symbol lookup, impact analysis, test discovery, or preparation for multi-file changes."
---

# semidx Code Exploration

Use the global `semidx` skill and MCP tools as the canonical retrieval contract.
This repository skill adds semidx-specific evidence requirements.

## Workflow

1. Read `RULES.md`.
2. Run the semantic flow:

   ```text
   semidx_health -> semidx_repo_map -> semidx_find_definitions
   -> semidx_references or semidx_context
   ```

   Keep the default compact `detail`; ask for `detail: "full"` only on the one
   target whose resolution explanations, producer versions, or byte offsets
   the task needs ([detail levels](../../../docs/mcp/local_preview.md#detail-levels-and-budgets)).
3. Verify reported root path, snapshot revision, language counts, parser
   availability, analysis state, and diagnostics.
4. Refine broad results with concrete `path`, `path_prefix`, `language`, `role`,
   `name`, or `entity_id` filters before concluding context is thin.
5. For a change, inspect relevant definitions, callers, callees, related tests,
   contracts, fixtures, frontend coverage, storage/runtime edges, and
   documentation ownership.
6. Use manual `rg` or file reads only after semantic refinement is insufficient,
   the target is outside indexed source, or an MCP tool returns an explicit
   error. Record the fallback reason.
7. After editing indexed source, call `semidx_refresh` before relying on later
   graph answers.

## Required Output Before Non-Trivial Edits

- relevant definitions and ownership boundaries;
- inbound and outbound dependencies;
- related tests, fixtures, and missing test seam;
- contract, identity, storage, runtime, and documentation impacts;
- resolution, freshness, limitations, snapshot revision, and exact files needing direct
  inspection.

Do not stop after only `semidx_health` or `semidx_repo_map`. The preview is
exact when it knows and honest when it does not; unresolved, unsupported,
stale, approximate, and unavailable results are useful signals, not permission
to present guesses as facts.
