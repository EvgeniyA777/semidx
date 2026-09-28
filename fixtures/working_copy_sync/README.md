# Working-Copy Synchronization Fixtures

Committed by [Plan 016](../../docs/plans/016_trustworthy_working_copy_sync.md)
Stage 0. These fixtures freeze the inputs later stages must reproduce and
compare against, so no stage invents its own ad hoc regression data or
guesses the shape of a result before the code that renders it exists.

## The Regression Sequence

[ADR 014](../../docs/adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md)
records a real external Java review where a nine-unit repository was indexed,
another process changed two files' contents while the server stayed alive, and
an unrefreshed `semidx_health`/`semidx_repo_map` call kept reporting all nine
units `current` with the old line ranges. This directory's `units/` holds a
synthetic nine-unit stand-in for that repository (Zig, not Java, so the
fixture needs nothing beyond the existing frontend and carries no content from
the external repository or its source) plus one edited variant of one unit,
used to reproduce the same shape of regression:

1. index `units/` (nine current units, no diagnostics);
2. replace `unit_03.zig` on disk with `unit_03_edited.zig`'s contents, from
   outside the server (a plain file write, standing in for "another process");
3. call a graph-reading tool without syncing first — today this still answers
   from the untouched snapshot and reports `unit_03.zig` `current` at its old
   range, which is exactly the defect ADR 014 D1/D4 close;
4. sync (Stage 2's `semidx_sync`/`semidx_refresh`) and repeat the call — the
   corrected range must come back, and the working-copy status must read
   `in_sync`.

Stage 3 turns this sequence into an executable gate test (`tests/`, alongside
`mcp_fixture_gate_test.zig`) once fail-closed preflight exists to make step 3
fail closed instead of answering stale. Stage 0 commits only the fixture data
and the documented sequence, so the gate's assertions are written against a
frozen input rather than one invented alongside the test.

## Files

| Path | Purpose |
| --- | --- |
| `units/unit_01.zig` .. `unit_09.zig` | Nine minimal top-level `pub fn` definitions, one per file, each with a distinct name and body so a byte-level or line-range change is unambiguous. |
| `units/unit_03_edited.zig` | `unit_03.zig` with its function body changed by one statement (same name, later line for its closing brace), the file this fixture's edit step writes over `unit_03.zig`. |
| `identity_vectors.md` | The frozen input sets Stage 1's source-state identity vectors (empty, one-unit, reordered, byte-change, path-change, diagnostic-change, policy-change) are computed from. It names inputs, not hashes: the encoding does not exist yet. |
| `health_examples.md` | Frozen example `semidx_health` compact and full result shapes under ADR 014 D5, for Stage 2/4 to match rather than to invent. |

None of these fixtures contains content from the external repository the
regression was observed on; every name and body here is synthetic.
