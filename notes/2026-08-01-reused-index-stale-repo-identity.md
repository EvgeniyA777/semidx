---
title: "Reused Index Returns Stale Repository Identity"
doc_type: "bug_report"
lifecycle: "active"
status: "open"
agent_action: "reference_for_context"
updated: "2026-08-01"
---

# Reused Index Returns Stale Repository Identity

## Reproduction

Repository root:

```text
/Users/ae/workspaces/semidx
```

Call:

```json
{"root_path":"/Users/ae/workspaces/semidx"}
```

Relevant `create_index` response fields:

```json
{
  "index_id": "6842ae7c-215b-42c3-be6e-abd5b8573364",
  "snapshot_id": "32a868ae-130c-4aa0-9f3b-0ba2cfc8a1e9",
  "cache_hit": true,
  "lifecycle_reason": "workspace_unchanged",
  "index_lifecycle": {
    "repo_identity": {
      "git_commit": "a065442b2ca1c596a568dc660d7669c4d65e92f5",
      "git_dirty": true
    }
  }
}
```

Current Git state at the same time:

```text
HEAD: 889d2c603217e41f163ff0f4267a9ca700c82efc
working tree: clean
```

## Expected

Snapshot reuse may preserve indexed source content, but the returned repository
identity should describe the current checkout or explicitly distinguish current
workspace identity from snapshot provenance.

## Actual

`create_index` returns the reused snapshot's stale `git_commit` and
`git_dirty` values as the active `repo_identity`.

## Context

- Active indexed language: Clojure (`high` confidence ceiling).
- The intervening commits changed documentation rather than indexed source.
- No `resolve_context` retry applies because the defect is in the
  `create_index` lifecycle response.
