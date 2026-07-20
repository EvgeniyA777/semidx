---
title: "Field Report: intent-only queries don't surface test units without explicit targets"
doc_type: "bug_report"
lifecycle: "completed"
status: "fixed"
agent_action: "historical_reference_only"
updated: "2026-07-20"
---

# Field Report: intent-only `resolve_context` under-recalls test units

Reporter: Claude Code agent, while working in a **consumer** repo
(`/Users/ae/workspace/JobApplicationTracker`, a Java/Spring Boot project) via
the semidx MCP server. This is an external-consumer field observation, not a
semidx-repo progress log.

Related prior work: [009_test_discovery_and_mirroring_progress_log.md](009_test_discovery_and_mirroring_progress_log.md)
covers test discovery/mirroring on the semidx side. This report is a *retrieval
recall* observation, adjacent to that work but about `resolve_context` ranking,
not index coverage.

## Correction of the initial framing

The first framing verbally used by the agent was "semidx doesn't return test
files." **That is inaccurate and should not be recorded as the finding.** Test
files are indexed and are retrievable — verified below (Query B). The accurate
finding is narrower:

> An **intent-only** (`intent` shorthand) `resolve_context` query whose task is
> explicitly *about tests*, with `options.include_tests: true`, returned **zero
> test units** and bounced to `narrow_query`, surfacing only main-source
> neighbors. Supplying explicit `targets.paths` / `targets.symbols` (+
> `hints.focus_on_tests`) surfaced the same test units immediately as
> `top_authority`.

So this is a **recall/ranking gap in the intent-shorthand path**, not a missing
index. `options.include_tests: true` alone did not pull test units into an
intent-only retrieval.

## Environment

- Index root: `/Users/ae/workspace/JobApplicationTracker`
- `create_index`: `file_count: 156`, `unit_count: 4114`,
  `active_languages: [java, javascript, html, css]`,
  `snapshot_id: e40b71e3-6a54-429f-b514-e093b03f3c65`,
  `index_id: 15e4e1f7-...` (fresh `force_rebuild: true`).
- Both queries below ran against that same snapshot.

## Query A — intent shorthand, `include_tests: true` → no test units

Call:

```json
resolve_context {
  "index_id": "15e4e1f7-...",
  "intent": "How existing tests mock the Google Sheets HTTP/SDK layer without live network (GoogleApiSheetsClientTest), and how GoogleSheetsController MockMvc tests are structured; also application.yml sheets/secrets config keys",
  "options": { "include_tests": true }
}
```

Response (key fields):

- `result_status: "completed"`, `confidence_level: "medium"`,
  `query_ingress_mode: "intent_shorthand"`.
- `next_step.recommended_action: "narrow_query"`, reason: *"Retrieval is
  ambiguous without explicit structural targets; narrow the query or provide
  paths, modules, or symbols."*
- `focus`: 3 units, **all from main source**
  `controller/GoogleSheetsController.java` (`credentialsFilePresent`, `redact`,
  `hasText`), `why_selected: [lexical_overlap, graph_module_neighbor]`.
- **No unit from any `src/test/...` file**, despite the intent naming
  `GoogleApiSheetsClientTest` and `MockMvc` tests directly, and despite
  `include_tests: true`.

Net effect for the consumer: the agent could not get the test conventions from
semidx here and fell back to reading the test files directly with `Read`.

## Query B — structured query with explicit targets → test units as top authority

Call:

```json
resolve_context {
  "index_id": "15e4e1f7-...",
  "query": {
    "intent": { "purpose": "test_targeting", "details": "Find the GoogleApiSheetsClientTest that mocks the Google Sheets HTTP transport with MockHttpTransport" },
    "targets": { "paths": ["src/test/java/com/example/jobtracker/service/GoogleApiSheetsClientTest.java"], "symbols": ["GoogleApiSheetsClientTest"] },
    "hints": { "focus_on_tests": true, "preferred_paths": ["src/test/java/com/example/jobtracker"] },
    "options": { "include_tests": true }
  }
}
```

Response (key fields):

- `query_ingress_mode: "mcp_shorthand"`, `next_step.recommended_action: "expand_context"`.
- `focus`: 2 units from `src/test/java/.../GoogleApiSheetsClientTest.java`
  (`newClient`, `errorClient`), `rank_band: "top_authority"`,
  `why_selected: [target_path_match, graph_module_neighbor]`.

Test units are indexed and retrieved correctly once explicit structural targets
are given.

## Why this matters

The `intent` shorthand is documented as the simplest/primary way to call
`resolve_context`. When the task is explicitly about tests and `include_tests`
is set, an agent reasonably expects test units in the result. Instead it gets a
main-source-only selection plus a `narrow_query` bounce, which trains agents to
skip semidx for test-shaped questions and read files directly — the opposite of
the MCP-first goal.

## Suggested direction (non-prescriptive)

1. When `options.include_tests: true` is set on an **intent-only** query, ensure
   test units are eligible for the top ranking bands rather than filtered to
   neighbors-only.
2. Consider letting lexical hits on test-class names in the `intent` text
   (e.g. `*Test`, `MockMvc`, `MockHttpTransport`) raise test-unit rank instead
   of only main-source symbols.
3. If `narrow_query` is returned, it could name the concrete test paths it
   *did* index as candidate targets, so the caller can immediately re-query
   without guessing.

## Repro confidence

High — both calls above were run back-to-back on the same snapshot in one
session; the divergence is reproducible by re-issuing them.

## Resolution

Fixed on 2026-07-20. Intent-only lexical retrieval now includes file paths in
lexical matching, classifies `src/test/...` paths as test paths before generic
`src/` source paths, supplements lexical seeds with matched test units when
`include_tests` is true, and applies a bounded `focus_on_tests` boost only to
already-matched test units.

Verification:

- `clojure -M:test -n semidx.integration.runtime-test`: passed, 103 tests, 468 assertions.
- `clojure -M:test`: passed, 225 tests, 1590 assertions.
- `clojure -M:ccc check --root .`: passed after refreshing CCC artifacts.
