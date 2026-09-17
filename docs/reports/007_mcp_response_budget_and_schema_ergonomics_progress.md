---
title: "MCP response budget and schema ergonomics progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# 007: MCP Response Budget And Schema Ergonomics Progress

Companion log for
[docs/plans/007_mcp_response_budget_and_schema_ergonomics.md](../plans/007_mcp_response_budget_and_schema_ergonomics.md).

## Current Status

Stage 1 is complete: the baseline output inventory and the budget gates are
recorded below. Stages 2 to 5 are pending.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Response inventory and budget targets | Completed | Baseline transcript and structured sizes per tool over this repository, the fields that dominate `repo_map` and `context`, and the hard gates versus observations below. No behavior change. |
| Stage 2: Tool schema and argument validation cleanup | Pending | |
| Stage 3: Compact repository map | Pending | |
| Stage 4: Focused context budgeting | Pending | |
| Stage 5: Documentation and habit loop update | Pending | |

## Plan Readiness Gate

Applied on 2026-09-17 before Stage 1. Plan 006 is completed
(`lifecycle: completed`), so the start rule holds. Scope, non-scope, stage
order, verification commands, and DoD are explicit; no hard fail.

The plan leaves two shape choices to the executor. They are decided here so
later stages do not guess:

- **Compact is the default, full is explicit.** `semidx_repo_map` and
  `semidx_context` gain `detail` (`compact` default, `full`). `full` renders
  exactly the fields the tool returned before this plan, plus budget metadata,
  so a detailed call recovers every existing field. Compact keeps field names
  and JSON types and only omits sub-fields, so a client reading
  `resolution.category`, `producer.name`, or `evidence.unit.path` works in both
  modes.
- **Budget metadata is one `budget` object** on every tool that returns lists
  (`semidx_repo_map`, `semidx_find_definitions`, `semidx_references`,
  `semidx_context`), naming the detail level where the tool has one and every
  limit applied. Totals and truncation flags stay where they are.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Advertised schema and argument validation agree | A documented argument is refused, or an advertised default or maximum differs from the validator | Unit test over every tool definition | `tools.zig` schema generation and `Args` | Unknown argument, wrong JSON type, count below 1 or above maximum, unsupported enum value | Stage 2 tests in `src/mcp/root.zig` |
| Tool annotations stay accurate | A read-only tool is advertised as writing, or refresh as destructive | Unit test | `writeToolList` | `semidx_refresh` is the only non-read-only tool | Stage 2 test |
| Compact output keeps graph authority visible | Compact mode hides resolution, freshness, or producer, or turns an unresolved claim into something that reads as a fact | Unit test over a fixture with a fact and an unresolved call | `writeRelationship` and `writeEntity` shapes | Unresolved designator keeps `resolution.category`, names no entity | Stage 4 tests |
| Full mode keeps every existing field | Detailed mode silently loses method, explanation, producer version, byte ranges, existence, extension | Unit test comparing full to the pre-plan fields | `detail: "full"` | Full context exposes `explanation` and `existence.producer.version` | Stage 3 and Stage 4 tests |
| Budgets are structural, never byte-chopped | Invalid JSON, or truncation that does not say which list was cut | Unit test plus stdio smoke | Tool renderers | Limits of 1 report totals and truncation per list | Stage 3 and Stage 4 tests |
| Compact defaults are materially smaller | The default cold-start call stays the large one | Runtime dogfood gate | `zig build dogfood` over this repository | Ratio gate below | Stage 3 and Stage 4 dogfood |
| No source text by default in either mode | A new rendering path reads evidence text without the opt-in | Unit test and dogfood transcript scan | `writeEvidence` | Both `detail` values, with and without `--allow-evidence-text` | Existing source-text tests extended |

## Stage 1: Response Inventory And Budget Targets

### Baseline

Measured on 2026-09-17 at `efbc8b3`, Zig 0.16.0, Debug build.
`zig build dogfood` passed (5 of 5 tests) over a copy of 66 source units
(716,072 bytes). "Transcript" is the whole JSON-RPC response line the client
receives; "structured" is `structuredContent` alone, measured with a stdio
client over the same tree.

| Call | Transcript bytes | Structured bytes | Latency |
| --- | ---: | ---: | ---: |
| `semidx_health {}` | 6,683 | | 361 ms (first call includes indexing) |
| `semidx_repo_map {"limit":1000}` | 314,779 | 146,203 | 23 ms |
| `semidx_repo_map {"limit":1000,"definitions_per_file":500}` with `--allow-evidence-text` | 364,277 | | 20 ms |
| `semidx_find_definitions {"name":"scanDir","language":"zig"}` | 2,003 | | 0 ms |
| `semidx_references {"entity_id":…}` (`scanDir`) | 6,697 | | 1 ms |
| `semidx_references` for `protocol.writeString`, limit 1000 (23 calls) | 56,824 | | 3 ms |
| `semidx_context {"name":"scan","path":"src/source/discovery.zig"}` | 22,947 | 10,611 | 5 ms |
| `semidx_context` for `health` in `src/mcp/tools.zig`, limit 500 | 150,632 | 70,282 | 10 ms |
| `semidx_refresh {}` after one edit | 1,213 | | 21 ms |

### What Dominates

Bytes attributed to each field name, summed over the structured result:

- **`semidx_repo_map`:** `definitions` 121,557 of 146,203. Inside them the
  per-definition `evidence` object is 74,064: `range` 45,081 (six numbers per
  definition) and `unit` 34,114, which repeats the file's id and path in every
  definition of that file. `freshness`, `name`, `kind`, `language`, and `role`
  are 7,000 to 9,000 each.
- **`semidx_context` (`health`, 500):** `outgoing` 65,995 of 70,282. Per
  relationship: `evidence` 28,493, `source` 22,300 (the focus entity repeated,
  with its own evidence, in every outgoing relationship), `resolution` 15,441
  of which `explanation` is 9,148 (the same few sentences repeated), `producer`
  5,440.
- **Envelope:** every transcript is about 2.15 times its structured result,
  because the text content block carries the same object serialized again as a
  JSON string. Both protocol eras recommend that fallback; this plan does not
  change the envelope. See [Residual Risk](#residual-risk).

### Budget Gates

Hard gates, kept stable because they compare shapes or ratios over one snapshot
instead of absolute sizes of a repository that keeps growing:

1. **Repository map ratio (dogfood).** Over the same snapshot, the default
   `semidx_repo_map {"limit":1000}` transcript is at most half the
   `{"limit":1000,"detail":"full"}` transcript.
2. **Context ratio (dogfood).** The default `semidx_context` for `health` in
   `src/mcp/tools.zig` with `relationship_limit` 500 is at most half the same
   call with `detail: "full"`.
3. **Shape gates (unit tests).** Compact results carry no byte offsets, columns,
   extension labels, resolution methods or explanations, producer versions, or
   relationship revisions; full results carry all of them. Every list reports a
   total and a truncation flag, and every list tool reports `budget`.
4. **Schema gates (unit tests).** Every advertised schema parses, names exactly
   the arguments the validator accepts, and agrees with it on types, enum
   values, defaults, and maxima.
5. **Source text (unit tests and dogfood).** No `source_text` and no body text
   in any mode without `--allow-evidence-text`.

Observations, printed by `zig build dogfood` and recorded here, not enforced:
absolute byte counts per call, latency, and the transcript to structured
multiplier.

## Residual Risk

- **Envelope duplication.** Every `tools/call` result repeats its structured
  object as a JSON string in a text block, roughly doubling transcript size.
  Both supported protocol eras recommend that fallback for clients without
  structured-content support, so this plan leaves it; removing or shortening it
  is a protocol decision for a later plan.
