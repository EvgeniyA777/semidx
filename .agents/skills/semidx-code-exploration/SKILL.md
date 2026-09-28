---
name: semidx-code-exploration
description: "Explore semidx source, callers, tests, and blast radius with Semantic Code Indexing before manual search. Use for cold-start orientation, symbol lookup, impact analysis, test discovery, or preparation for multi-file changes."
---

# semidx Code Exploration

Use the global `semidx` skill and MCP tools as the canonical retrieval contract.
This repository skill adds semidx-specific evidence requirements.

## Workflow

1. Read `RULES.md`.
2. Run the semantic flow, starting with a sync so every later read can trust
   the working copy it answers from:

   ```text
   semidx_sync -> semidx_health (only when a diagnostic summary is needed)
   -> semidx_outline -> semidx_repo_map(path_prefix)
   -> semidx_find_definitions -> semidx_references or semidx_context
   ```

   `semidx_sync` and every call after it are dependent, not independent:
   never launch them in parallel, since a later call must observe the
   snapshot the sync just confirmed or published
   ([ADR 014](../../../docs/adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md)).
   A graph-reading call after an external edit without a prior sync fails
   closed (`isError: true`, naming `semidx_sync` as the next step) rather than
   answering from an unconfirmed snapshot. Keep the default compact `detail`;
   ask for `detail: "full"` only on the one target whose resolution
   explanations, producer versions, or byte offsets the task needs
   ([detail levels](../../../docs/mcp/local_preview.md#detail-levels-and-budgets)).
   When a result is cut, follow its `narrowing_hints`; for impact beyond one
   step, use `semidx_context` with `direction` and `depth: 2`.
3. Verify reported root path, snapshot revision, source-state identity,
   working-copy status, language counts, parser availability, analysis state
   (`current`/`stale`/`pending` — snapshot-relative, not evidence the working
   copy still has those bytes), and diagnostics.
4. Refine broad results with concrete `path`, `path_prefix`, `language`, `role`,
   `name`, or `entity_id` filters before concluding context is thin.
5. For a change, inspect relevant definitions, callers, callees, related tests,
   contracts, fixtures, frontend coverage, storage/runtime edges, and
   documentation ownership.
6. Use manual `rg` or file reads only after semantic refinement is insufficient,
   the target is outside indexed source, or an MCP tool returns an explicit
   error. Record the fallback reason.
7. After editing indexed source, call `semidx_sync` before relying on later
   graph answers (`semidx_refresh` remains a compatible alias).

## Required Output Before Non-Trivial Edits

- relevant definitions and ownership boundaries;
- inbound and outbound dependencies;
- related tests, fixtures, and missing test seam;
- contract, identity, storage, runtime, and documentation impacts;
- resolution, freshness, limitations, snapshot revision, and exact files needing direct
  inspection.

Do not stop after only `semidx_sync`, `semidx_health`, `semidx_outline`, or `semidx_repo_map`. The preview is
exact when it knows and honest when it does not; unresolved, unsupported,
stale, approximate, and unavailable results are useful signals, not permission
to present guesses as facts.
