---
title: "MCP response budget and schema ergonomics progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-17"
---

# 007: MCP Response Budget And Schema Ergonomics Progress

Companion log for
[docs/plans/007_mcp_response_budget_and_schema_ergonomics.md](../plans/007_mcp_response_budget_and_schema_ergonomics.md).

## Current Status

Plan 007 is complete. Stages 1 to 5 are implemented and verified: tool
schemas are generated from the argument declarations the validator reads, the
repository map and graph context are compact by default with a full detail
level, list tools report their budgets, and the preview reference teaches the
compact habit loop. The closure lanes pass; residual risks are recorded below.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Response inventory and budget targets | Completed | Baseline transcript and structured sizes per tool over this repository, the fields that dominate `repo_map` and `context`, and the hard gates versus observations below. No behavior change. |
| Stage 2: Tool schema and argument validation cleanup | Completed | Each tool's arguments are declared once as `Param` values; the advertised JSON Schema is generated from them at compile time, and `Args(tool)` reads types, enum values, defaults, and maxima from the same declarations. The advertised `tools/list` is unchanged. |
| Stage 3: Compact repository map | Completed | `semidx_repo_map` takes `detail` (`compact` default, `full`) and reports `budget`. Over this repository the default map with `limit` 1000 is 152,579 transcript bytes against 322,104 for `full` (47%, gate at most 50%). |
| Stage 4: Focused context budgeting | Completed | `semidx_context` takes `detail` and `diagnostic_limit` and reports `budget`; `semidx_find_definitions` and `semidx_references` report the limits they applied. The default context for `health` in `src/mcp/tools.zig` at limit 500 is 60,962 transcript bytes against 153,194 for `full` (39%, gate at most 50%). |
| Stage 5: Documentation and habit loop update | Completed | The local preview reference documents `detail`, `diagnostic_limit`, every compact field, and `budget`, and recommends compact orientation before one focused full call; the capability matrix, the exploration skill, and `MEMORY.md` state the new bounds. |

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

## Stage 2: Tool Schema And Argument Validation Cleanup

Changed files: `src/mcp/tools.zig`, `src/mcp/root.zig`, this log.

- `Definition.params` declares every argument: `string`, `entity_id`,
  `count` (default, maximum), or `choice` (enum values from a Zig enum, optional
  default). `freshness`, `resolution`, `language`, `entity_id`, `name`, and
  `path` are shared declarations. `inputSchema` renders the one-line schema at
  compile time.
- `Args(tool)` refuses undeclared arguments at run time. Its accessors take
  only a parameter name and look the declaration up at compile time: reading an
  undeclared parameter, reading one as the wrong type, or reading a choice
  through an enum whose tags differ from the declared values does not compile.
- Behavior is unchanged: the parsed `tools/list` from the new binary equals the
  one from `efbc8b3` for every tool.

Tests:

- `tools.zig`: every schema is one line, `additionalProperties: false`, and
  names exactly the declared arguments with matching types, enum values,
  defaults, and maxima.
- `root.zig`: for every tool, an unknown argument is refused; for every
  declared argument, a wrong JSON type is refused with a message naming the
  expected type; counts refuse 0 and maximum + 1 and accept the maximum;
  choices refuse an unknown value and accept every declared value; entity ids
  refuse -1. Annotations: only `semidx_refresh` is not read-only, it is not
  destructive, and no tool is open-world.
- Mutation check: rendering `maximum + 1` into the schema fails the schema
  test (`expected 1000, found 1001`); reverted.

Verification:

- `./scripts/check-zig-version.sh`: 0.16.0 matches.
- `zig fmt src/mcp`: clean.
- `zig build test-mcp --summary all`: 19 of 20 passed, 1 skipped (the dogfood
  recovery test, which runs only under `zig build dogfood`).

## Stage 3: Compact Repository Map

Changed files: `src/mcp/tools.zig`, `src/mcp/root.zig`,
`tests/mcp_dogfood_test.zig`, `docs/mcp/local_preview.md`, this log.

- `detail` is a shared declared argument (`compact` default, `full`).
- Compact: each file's `unit` has `id`, `path`, `language`, `analysis`; each
  top-level definition has `id`, `role`, `name`, `freshness`, and
  `range: {start_line, end_line}`. Diagnostic counts, the three per-file totals
  and truncation flags, `files_total`, and `truncated` are unchanged.
- Full: exactly the pre-plan fields (unit revisions and `file_entity_id`,
  definitions as brief entities with `evidence`), plus `budget`.
- `budget: {detail, limit, definitions_per_file}` names what was applied.
- Under `--allow-evidence-text` a compact listed definition keeps its
  `source_text`; the opt-in is not narrowed by the detail level.

**Deviation from the Stage 1 shape rule, recorded:** a compact listed
definition carries `range` directly instead of `evidence.range`. Its evidence
unit is the file it is listed under, so the wrapper only repeated structure.
With the wrapper the compact map was 164,173 of 320,845 bytes (51%), above the
gate set before implementation; the gate was kept and the shape changed.
Everything else compact renders is a subset of the full fields.

Tests:

- `root.zig` "the default repository map is compact, and a full map recovers
  every unit and entity field": compact field sets (no `start_byte`, no
  `file_entity_id`, no `evidence` or `kind` on definitions), full field sets
  (seven unit fields, seven entity fields, six range fields), full larger than
  compact, `budget` values, and `definitions_per_file: 1` reporting
  `definitions_truncated` with the total.
- The source-text test also calls `semidx_repo_map` with `detail: "full"`.
- `mcp_dogfood_test.zig`: the budget gate compares the default map with
  `detail: "full"` over one snapshot; the evidence-text dogfood reads
  `evidence.range` from a full map.

Verification:

- `zig fmt src tests`: clean.
- `zig build test-mcp --summary all`: 20 of 21 passed, 1 skipped (dogfood
  recovery, run by `zig build dogfood`).
- `zig build dogfood --summary all`: 5 of 5 passed; repository map budget
  gate at 47%.

## Stage 4: Focused Context Budgeting

Changed files: `src/mcp/tools.zig`, `src/mcp/root.zig`,
`tests/mcp_dogfood_test.zig`, `docs/mcp/local_preview.md`, this log.

- `semidx_context` declares `diagnostic_limit` (default 50, max 500; it was a
  fixed 50) and `detail`. `budget` reports `detail`, `relationship_limit`,
  `diagnostic_limit`, and `focus_limit` (10).
- Compact focus entity: `id`, `kind`, `language`, `role`, `name`,
  `freshness`, `evidence` (unit `path`, `start_line`, `end_line`),
  `container_path`, and `existence` with `resolution.category`,
  `producer.name`, and `freshness`. The unit has `id`, `path`, `language`,
  `analysis`.
- Compact relationship: `assertion_id`, `kind`, the focus end as `{id}`, the
  other end as `id`, `kind`, `role`, `name`, `freshness`, `evidence`; a
  designator target unchanged; `resolution` with `category` plus `missing`
  (unresolved) or `confidence` (approximate); `producer.name`; `freshness`;
  compact `evidence`. Dropped: resolution `method`, `explanation`, `basis`,
  producer `version`, the relationship `revision`, unit ids in evidence, and
  columns and byte offsets.
- Compact diagnostic: `kind`, `producer.name`, `message`; the unit is the
  focus unit and is not repeated.
- Full is the pre-plan context plus `budget`.
- `semidx_find_definitions` reports `budget: {limit}` and `semidx_references`
  `budget: {limit, target_limit}`. Their rendering is unchanged.

Tests:

- `root.zig` "compact context keeps every claim's resolution, producer, and
  freshness; full context keeps the evidence for review": over a unit with an
  unresolved `std.debug.print` call, compact text carries no `explanation`,
  `method`, byte or column offsets, `extension`, `version`, or
  `file_entity_id`; the focus end is `{id}`; every outgoing claim has a
  producer name and freshness and no revision; the unresolved claim keeps its
  category, `missing`, and designator and names no entity. Full context has
  existence `assertion_id`, `method`, producer `version`, relationship
  `revision`, six range fields, and `explanation` on the unresolved claim.
  `relationship_limit: 1` and `diagnostic_limit: 1` truncate outgoing
  relationships and diagnostics separately from incoming ones and from focus.
- The source-text test also calls `semidx_context` with `detail: "full"`.
- `mcp_dogfood_test.zig`: the compact `scan` context keeps the call fact and
  an unresolved designator with `missing`; its full context has an
  `explanation` for every unresolved claim; the context budget gate compares
  compact and full `health` contexts at limit 500.

Verification:

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-mcp --summary all`: 21 of 22 passed, 1 skipped.
- `zig build dogfood --summary all`: 5 of 5 passed; gates at 47%
  (repository map) and 39% (context).
- `zig build test --summary all`: 206 of 207 passed, 1 skipped.

## Stage 5: Documentation And Habit Loop Update

Changed files: `docs/mcp/local_preview.md`, `docs/spec/capability_matrix.md`,
`.agents/skills/semidx-code-exploration/SKILL.md`, `MEMORY.md`,
`src/mcp/tools.zig` (review cleanup), the Plan 007 frontmatter, this log.

- `docs/mcp/local_preview.md`: First Calls uses compact defaults and names the
  large-output call pattern to avoid; the tool table documents every new
  argument with its default; a new "Detail Levels And Budgets" section lists
  what compact keeps and drops per value, the one shape exception, `budget`
  per tool, and that detail levels are experimental preview ergonomics, not a
  semantic contract; Limits records the remaining large-output cases and the
  envelope duplication.
- `docs/spec/capability_matrix.md`: the MCP Bounds row states the compact
  default, `budget`, and that responses are still not size-bounded.
- `.agents/skills/semidx-code-exploration/SKILL.md`: keep compact detail and
  ask for full on one target only.
- `MEMORY.md`: current MCP argument and detail reality; Plan 008 is next.
- `README.md` names no MCP call pattern and was not changed. Release notes for
  `v0.1.0-preview.2` are historical and were not changed.

### Final Output Observations

`zig build dogfood` over a copy of 66 units (746,700 bytes), transcript bytes:

| Call | Before (`efbc8b3`) | Compact default | `detail: "full"` |
| --- | ---: | ---: | ---: |
| `semidx_repo_map {"limit":1000}` | 314,779 | 152,595 (47% of full) | 322,120 |
| `semidx_context` `scan` in `src/source/discovery.zig` | 22,947 | 11,793 | 23,140 |
| `semidx_context` `health` in `src/mcp/tools.zig`, limit 500 | 150,632 | 60,962 (39% of full) | 153,194 |
| `semidx_references` `protocol.writeString`, limit 1000 | 56,824 | unchanged rendering | |
| `semidx_repo_map {"path_prefix":"src/mcp/"}` | | 25,641 | |

Full sizes grew slightly over the baseline because the source copied grew
during the plan and `budget` was added.

## Closure Verification

Run on the final tree:

- `./scripts/check-zig-version.sh`: 0.16.0 matches.
- `zig fmt --check build.zig src tests`: clean.
- `zig build test --summary all`: 206 of 207 passed, 1 skipped (the dogfood
  recovery test, run only by `zig build dogfood`); this includes
  `zig build test-mcp`'s unit tests and stdio smoke test.
- `zig build dogfood --summary all`: 5 of 5 passed; budget gates at 47%
  (repository map) and 39% (context).

## Review Findings

Self-review of the diff from `efbc8b3` with `semidx-code-review`:

- **Fixed (cosmetic):** `writeEntity` had two consecutive blocks guarded by the
  same `focus or full` condition; merged. Verified by the closure lanes above.
- **Rejected:** compact output hiding authority. Every compact claim keeps
  `resolution.category`, `producer.name`, and `freshness`; an unresolved claim
  keeps `missing` and its designator and names no entity (Stage 4 test).
- **Rejected:** evidence text escaping the opt-in through a new path. Compact
  listed definitions and compact evidence call the same `writeSourceText`,
  which checks the opt-in; the source-text test covers both detail levels.

No open finding from the self-review.

### Independent Review (Post-Closure)

An independent review of `efbc8b3..HEAD` found the mechanics sound: MCP stays a
projection, compact never turns an unresolved relationship into a fact, full
context returns the evidence-heavy form, and the 50% gates were not tuned after
measurement. Its verification: `./scripts/check-zig-version.sh`,
`git diff --check efbc8b3..HEAD`, `zig fmt --check build.zig src tests`,
`zig build test` (206 of 207, 1 skipped), `zig build dogfood` (5 of 5; 47% and
39%). Both findings are about wording overstating the implementation.

1. **Medium, confirmed, fixed: documentation overpromised `semidx_repo_map`
   detail.** `detail: "full"` renders definitions as brief entities
   (`tools.zig`, `repoMap`), so it has no `existence`, `extension`, or entity
   revisions, and compact listed definitions carry no existence resolution or
   producer. `docs/mcp/local_preview.md` said `full` renders every field, and
   `docs/spec/capability_matrix.md` and `MEMORY.md` said compact keeps each
   claim's resolution and producer. Impact: an agent could treat a full
   repository map as provenance-complete.
   Fix: `local_preview.md` now says `full` is each tool's pre-detail rendering
   plus `budget`, spells out what a full map lacks, and points to
   `semidx_find_definitions` or `semidx_context` for existence provenance; the
   "compact never changes a claim" paragraph is scoped to context, and the map
   is described as orientation at both levels. The capability matrix Bounds
   row and `MEMORY.md` say the same. The Post-Closure Assessment below was
   corrected where it repeated the overstatement.
2. **Low, confirmed, fixed: compact map evidence-text shape was
   undocumented.** Under `--allow-evidence-text` a compact listed definition
   writes `source_text` next to `range`, while the Source Text section said
   each `evidence` object gains it; no test covered that path.
   Fix: documented as part of the repository map exception (Detail Levels
   paragraph and table, Source Text section). The code keeps the sibling shape:
   adding an `evidence` wrapper only under the opt-in would make the shape
   depend on a server flag. The source-text test now asserts that a compact map
   definition over 600 bytes of recorded text has no `evidence`, has `range`,
   and carries a 400-byte truncated `source_text`, and that the field is absent
   without the opt-in. Mutation check: removing the `writeSourceText` call from
   the listed shape fails that test; reverted.

Verification after the fixes:

- `zig fmt --check build.zig src tests`: clean; `git diff --check`: clean.
- `zig build test --summary all`: 206 of 207 passed, 1 skipped.

## Post-Closure Assessment

Recorded on 2026-09-17 after the closure commit, at the user's request.

### Live Server Check

The repository's `.mcp.json` server was restarted on the Plan 007 binary and
exercised from an agent session (snapshot revision 86):

- `semidx_health`: product version `0.1.0-preview.2`, all three parsers
  available; the 3 `analysis_failed` units are the intentionally unparsable
  `fixtures/vertical-slice/*/edits/05_unparsable.*` fixtures.
- `semidx_repo_map {"path_prefix":"src/mcp/main"}`: compact unit and definition
  fields, `range` lines, and `budget`.
- `semidx_context` for `fail` in `src/mcp/main.zig` with `diagnostic_limit: 1`:
  the focus end is `{id}`, the four unresolved calls keep
  `category: unresolved`, `missing`, and their designators, every claim carries
  `producer.name` and `freshness`, and `budget` echoes the limit.
- The same call with `detail: "full"` and `relationship_limit: 1`: resolution
  `method` and `explanation`, producer versions, byte offsets, and `extension`
  are back; incoming (3) and outgoing (4) report truncation separately.
- `semidx_find_definitions` with `detail`: refused with
  `unknown argument "detail"`, as its declaration has none.

### Structured Size Before And After

What an agent reads is the structured result. The client used in this session
showed one JSON copy per call; whether other clients also surface the text
block is not known.

| Call | Before | After (compact) | Reduction |
| --- | ---: | ---: | ---: |
| `semidx_repo_map`, whole repository (66 units) | 146 KB | 70 KB | 2.1x |
| `semidx_context` for `health`, limit 500 | 70 KB | 28 KB | 2.5x |
| `semidx_context` for `scan` | 10.6 KB | 5.4 KB | 2.0x |

Token counts were not measured; JSON of this shape is roughly 3 to 4 bytes per
token, so the whole-repository compact map is on the order of 20,000 tokens.

### Better

- **Cost of the common loop** (map one directory, find, context) fell 2 to 2.5
  times.
- **Readability.** The largest waste was repetition: the focus entity with its
  full evidence inside every relationship, and the same `explanation` sentence
  repeated dozens of times. Compact output keeps what an agent acts on: who
  calls, at which line, what is called, and whether each claim is a fact.
- **Authority unchanged in context.** Unresolved claims stay unresolved with a
  designator, and every relationship and focus existence claim keeps its
  resolution category, producer, and freshness, proven by tests. The
  repository map never carried existence provenance and still does not; it is
  orientation (corrected after the independent review above).
- **Schema drift removed.** Advertised schemas and validation derive from one
  declaration; a mismatch fails compilation or the schema test.
- **Visible budgets.** `budget` states which limits shaped a result.

### Worse Or Debatable

- **Unresolved reasons are hidden by default.** Compact keeps `missing` but not
  `explanation`; understanding why a call is unresolved takes a second
  `detail: "full"` call, an extra step for review and impact analysis.
- **Breaking default shape.** A client reading `start_byte`,
  `producer.version`, or unit revisions from default responses no longer gets
  them. Acceptable for a preview with no contract, but a break.
- **One shape exception.** A compact repository map definition carries `range`
  instead of `evidence`, so code parsing both levels needs a branch.
- **More arguments to know.** An agent unaware of `detail` fails safe (compact)
  but may miss unresolved explanations.

### Not Solved

- **Whole-repository cold start is still heavy.** The plan's Definition of Done
  says the repository map should be cheap enough for default cold-start use.
  That holds with a `path_prefix` (about 12 KB structured for `src/mcp/`), not
  for an unfiltered map, which stays linear in repository size. This DoD item is
  met only partially; pagination was non-scope.
- **`semidx_references` is unchanged** (about 57 KB on the wire for
  `protocol.writeString`), repeating the target entity in every relationship.
- **Response size is bounded per list, not per response.**
- **Wire duplication** of the structured result as text remains.

### Summary

| Criterion | Assessment |
| --- | --- |
| Cost of the typical loop | Clearly better, 2 to 2.5 times smaller |
| Usefulness of default answers | Better: less noise, everything needed to act kept |
| Depth by default | Slightly worse: unresolved reasons need a second call |
| Whole-repository cold start | Better, still heavy |
| Reliability of schemas and validation | Substantially better |
| Compatibility of default shapes | Worse: breaking change |

Highest-value follow-ups: a compact level for `semidx_references`, and a way to
walk a large repository in portions, which needs its own plan or a revisit of
the pagination non-scope.

## Drift Control

- Constitution §1, §3, §7, §8: MCP remains a projection; compact rendering
  omits sub-fields but never changes a claim's category, producer, or
  freshness, and adds no network or source-text path.
- `SPEC.md`: tool shapes remain experimental; `semantic_contract_version` stays
  `null`. No change needed.
- `docs/mcp/local_preview.md`, `docs/spec/capability_matrix.md`, `MEMORY.md`,
  and the exploration skill: updated in Stage 5.
- `docs/agent-policy/tooling.md`: names the tools and flow, not arguments;
  aligned without change.
- Plan 008: already expects a compact `semidx_repo_map`; aligned.
- `GLOSSARY.md`: "detail level" and "budget" are MCP preview argument and field
  names owned by `docs/mcp/local_preview.md`, not durable project vocabulary.

## Residual Risk

- **Envelope duplication.** Every `tools/call` result repeats its structured
  object as a JSON string in a text block, roughly doubling transcript size.
  Both supported protocol eras recommend that fallback for clients without
  structured-content support, so this plan leaves it; removing or shortening it
  is a protocol decision for a later plan.
- **Per-response size is still unbounded.** Budgets bound lists, not whole
  messages: a high `relationship_limit` on a call-heavy function, up to 10
  focus entities each with its own lists, or a widely called function in
  `semidx_references` can still produce tens of kilobytes or more.
- **`semidx_references` has no compact level.** Its relationships repeat the
  target entity in full; Plan 007 scoped detail levels to `semidx_repo_map`
  and `semidx_context`.
- **The budget gates are ratios over this repository.** They catch a compact
  default growing toward full; they do not bound absolute sizes as the
  repository grows.
- **Compact omits prose an agent may need.** Resolution methods and unresolved
  explanations need a `detail: "full"` call; the reference says so.
