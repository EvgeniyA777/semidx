# `semidx_health` Compact/Full Examples — Frozen Shapes

Frozen by [Plan 016](../../docs/plans/016_trustworthy_working_copy_sync.md)
Stage 0, for [ADR 014](../../docs/adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md)
D5 and Plan 016 Stage 4. Illustrative over the nine-unit fixture in `units/`
after it is indexed with no working-copy drift; field values are examples, not
a claim about a real run. Both examples add `source_state_id` and
`working_copy` beside the existing fields; neither removes a field D5 requires
compact health to keep. Stage 2 (the `snapshot`/`working_copy` envelope) and
Stage 4 (the `detail` argument and the compact/full split itself) implement
this; this file exists so their shape is decided before that code is written.

## Compact (default, `detail` omitted or `"compact"`)

```json
{
  "snapshot": { "revision": 1, "source_state_id": "<64 lowercase hex>" },
  "working_copy": { "status": "in_sync", "observed_source_state_id": "<same 64 lowercase hex>" },
  "semantic_contract_version": null,
  "product_version": "0.1.0-preview.4",
  "root": "/tmp/working-copy-sync-fixture",
  "units": { "total": 9, "pending": 0, "current": 9, "stale": 0 },
  "diagnostics": { "analysis_unavailable": 0, "analysis_failed": 0, "unsupported_construct": 0, "confirmed_absence": 0 },
  "languages": [
    { "language": "zig", "parser": { "available": true } }
  ],
  "recovery": { "rebuilds": 0, "rebuilt_index_unpublished": false, "needs_rebuild": false },
  "outbound_projection": { "jev_ranking": { "enabled": false } }
}
```

Compact keeps: root, product/server identity, snapshot revision and
`source_state_id`, `working_copy` status and observed identity, unit and
diagnostic counts, per-language parser availability, recovery state, and
redacted outbound capability status — everything D5 requires an agent to
decide whether it can trust the next call.

## Full (`detail: "full"`)

```json
{
  "snapshot": { "revision": 1, "source_state_id": "<64 lowercase hex>" },
  "working_copy": { "status": "in_sync", "observed_source_state_id": "<same 64 lowercase hex>" },
  "semantic_contract_version": null,
  "product_version": "0.1.0-preview.4",
  "server": { "name": "semidx", "title": "semidx local MCP preview", "version": "0.1.0-preview.4" },
  "root": "/tmp/working-copy-sync-fixture",
  "evidence_text": { "enabled": false, "max_bytes": 400 },
  "units": { "total": 9, "pending": 0, "current": 9, "stale": 0, "by_language": { "zig": 9 } },
  "graph": {
    "entities": { "repository": 1, "file": 9, "definition": 9, "stale": 0 },
    "assertions": { "recorded": 18, "current": { "fact": 18, "unresolved": 0, "approximate": 0 }, "stale": 0 }
  },
  "languages": [
    {
      "language": "zig",
      "extensions": [".zig"],
      "parser": { "available": true },
      "producer": { "name": "frontend.zig", "version": "plan-006+ts-abi15" },
      "entity_roles": ["function", "container"],
      "relationship_kinds": ["defines", "calls"],
      "coverage_note": "…"
    }
  ],
  "diagnostics": { "analysis_unavailable": 0, "analysis_failed": 0, "unsupported_construct": 0, "confirmed_absence": 0 },
  "last_scan": { "unchanged": 9, "changed": 0, "renamed": 0, "added": 0, "removed": 0, "analyzed": 0, "ambiguous_renames": 0, "invalidated": 0 },
  "recovery": { "rebuilds": 0, "rebuilt_index_unpublished": false, "needs_rebuild": false },
  "outbound_projection": { "jev_ranking": { "enabled": false } }
}
```

Full adds graph entity/assertion counts, per-language producer/capability
notes, and the full last-scan outcome, on top of every compact field.

## Out-Of-Date Example (compact)

After an external edit and no sync, `semidx_health` reports the mismatch
without repairing it (D5: health reports, it does not repair):

```json
{
  "snapshot": { "revision": 1, "source_state_id": "<hex A>" },
  "working_copy": { "status": "out_of_date", "observed_source_state_id": "<hex B, differs from A>" },
  "...": "every other compact field unchanged from the retained snapshot"
}
```

## Scan-Failed Example (compact)

```json
{
  "snapshot": { "revision": 1, "source_state_id": "<hex A>" },
  "working_copy": { "status": "scan_failed", "observed_source_state_id": null },
  "...": "every other compact field unchanged from the retained snapshot"
}
```
