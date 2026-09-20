---
title: "Local MCP preview"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-18"
---

# Local MCP Preview

How to build, start, and use `semidx-mcp`, and exactly what its tools return.

**Status: experimental and local-only.** `semidx-mcp` is a consumer of the
semantic graph ([ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md)).
It publishes no semantic contract version: tool names, arguments, and result
fields may change with the implementation. It speaks MCP over stdio only.

## What It Does And Does Not Do

It does:

- index one local directory (`--root`) into an in-memory graph at startup and
  publish one snapshot;
- answer every tool call from the snapshot published when the call arrives;
- report, for every claim it returns, the claim's resolution (`fact`,
  `unresolved`, `approximate`), freshness (`current`, `stale`), and producer;
- rescan the root and publish the next snapshot when `semidx_refresh` is called.

It does not:

- resolve names, search text, rank, or guess: a tool shows what the graph
  recorded, selected by exact name, path, language, or role;
- return source code: results carry paths and ranges, not file contents;
- watch files, persist the graph, serve HTTP, or offer resources, prompts, or
  subscriptions; its only continuation mechanism is a [cursor](#cursors) bound
  to one snapshot revision;
- contact any network service.

You may infer:

- a relationship with resolution `fact` was established by its producer under
  that producer's declared coverage;
- a definition listed under a path exists in the current contents of that unit
  when its freshness is `current`.

You must not infer:

- that no caller exists because `semidx_references` lists none. Coverage is
  narrow (see [Limits](#limits)); unsupported constructs and unresolved calls
  are reported through diagnostics and resolution, not as absence;
- that an unresolved designator such as `std.debug.print` refers to a definition
  with that name. It is text the producer could not resolve;
- that a list is complete when its `…_truncated` flag or `budget_exhausted` is
  true, or that items a limit or budget left out matter less than the ones
  returned. A narrowing hint is usage guidance, not a claim about the graph;
- that result fields are a stable interface.

## Build

The preview is built from source. Prerequisites:

- Zig 0.16.0 exactly. Run `./scripts/check-zig-version.sh` before building.
- `git` and network access once, for the grammar setup script.
- A tree-sitter runtime providing `tree_sitter/api.h` and `libtree-sitter.a`.
  `zig build` looks under `/opt/homebrew`, `/usr/local`, and `/usr`; on macOS
  `brew install tree-sitter` provides both files (verified with 0.26.3). For any
  other install prefix pass `-Dtree-sitter-prefix=<prefix>` or set
  `SEMIDX_TREE_SITTER_PREFIX`.

From the root of a semidx checkout:

```sh
./scripts/setup-tree-sitter-grammars.sh   # once; clones pinned grammar sources into .tree-sitter-grammars/
./scripts/check-zig-version.sh             # fails unless `zig version` is 0.16.0
zig build                                  # installs zig-out/bin/semidx-mcp
zig-out/bin/semidx-mcp --version           # semidx-mcp 0.1.0-preview.3
zig build test-mcp                         # optional: unit tests and the stdio smoke test
zig build dogfood                          # optional: habit loop and refresh recovery on a copy of this repository
zig build preview-gate                     # optional: the habit loop gate, dogfood plus a small fixture profile
```

Building and indexing never use the network. `zig build` names any missing
prerequisite and the flags that point at it (`-Dgrammars-dir=`,
`-Dtree-sitter-prefix=`).

## Start

```sh
zig-out/bin/semidx-mcp --root /path/to/repository
scripts/semidx-mcp.sh --root /path/to/repository # stable launcher for MCP clients
zig build mcp -- --root .                  # same, through the build system
```

| Option | Meaning |
| --- | --- |
| `--root <dir>` | Directory to index. Default: the current directory. Result paths are relative to it and `/`-separated. |
| `--allow-evidence-text` | Opt-in: include the source text producers recorded as evidence for each claim, at most 400 bytes per claim. Off by default. See [Source Text](#source-text). |
| `--version` | Print `semidx-mcp <product version>` to stdout and exit. |
| `--help` | Print usage to stderr and exit. |

Streams and exit status:

- While serving, stdout carries MCP messages only, one JSON object per line.
  `--version` is the one invocation that writes anything else to stdout, and it
  does not serve.
- stderr carries a startup summary, refresh failures, ignored notifications, and
  an exit line.
- The server exits with status 0 when its stdin closes, 1 when the root cannot
  be indexed, and 2 on a usage error.

## Configure A Local Client

Any MCP client that launches stdio servers from a command and arguments can
start it. For clients that read an `mcpServers` map, such as a project
`.mcp.json`:

```json
{
  "mcpServers": {
    "semidx": {
      "type": "stdio",
      "command": "/path/to/semidx/scripts/semidx-mcp.sh",
      "args": ["--root", "/path/to/repository"]
    }
  }
}
```

Use absolute paths for committed or shared project configuration: a client may
start the server from any working directory. Other clients have their own
configuration format; the command and arguments are the same.

`--root` names a local working copy on this machine: the repository your agent
works on, not the semidx checkout that built the binary. One binary serves any
number of repositories. Register it once per repository with a different
`--root`, or run separate processes; each process indexes one root and shares
nothing with the others.

For local personal configuration, `scripts/semidx-mcp.sh` may be registered
without `args`. In that mode it indexes `SEMIDX_ROOT` when that environment
variable is set, otherwise the Git root of the process working directory. If
neither exists, it exits with a usage error instead of indexing an arbitrary
directory. Prefer explicit `--root` in project `.mcp.json` files because client
working directories are not universal.

### Data Leaving The Server

Read this before registering semidx with a client that uses a hosted model.

- semidx itself is local: indexing and every tool call run in this process, and
  it opens no network connection.
- Tool results go to the MCP client that launched the server. A client backed by
  a hosted model may send those results to its service. semidx cannot see or
  enforce what the client does with them; that is governed by the client and
  your agreement with its provider.
- By default no source text is returned: no file contents, no function bodies,
  no snippets.
- Results always contain values derived from your source: file paths, entity
  names, unresolved designators (callee names as written), ranges, entity ids,
  and diagnostic messages. Registering semidx with a hosted client means those
  values may leave your machine through that client.
- `--allow-evidence-text` additionally returns the text each producer recorded
  as evidence for a claim, at most 400 bytes per claim. It does not return file
  contents. See [Source Text](#source-text).

### First Calls

Discover progressively: learn where to look, then open a small map, then ask
focused questions. Every step uses the default compact
[detail level](#detail-levels-and-budgets) and response budget:

1. `semidx_health`: is every unit `current`, and which languages have parsers?
2. `semidx_outline`: which directories and files exist under the root, and how
   many units, definitions, and diagnostics each holds? Repeat with a
   directory's `path_prefix` to descend. It lists no definitions.
3. `semidx_repo_map` with the `path_prefix` of one directory (or file): which
   top-level definitions exist there, and at which lines?
4. `semidx_find_definitions` with a `name`: where is a definition introduced?
5. `semidx_references` or `semidx_context` on it: what calls it, what does it
   call, and which of those claims are facts? For impact beyond one step, give
   `semidx_context` a `direction` and `depth: 2`.
6. `semidx_refresh` after editing files, before trusting later answers.

When a result is cut, read its `narrowing_hints` and narrow the next call
rather than raising every limit; follow `next_cursor` only when you need the
rest of that exact list.

Use `semidx_outline`, not `semidx_repo_map`, for the first look at a
repository: over this repository the root outline is about 5 KB on the wire,
while a whole-repository map lists every top-level definition (about 157 KB
compact with no budget, so by default it stops at the response budget and
continues over three cursor pages). Use `semidx_repo_map` once you know which
directory or file matters. Ask for `detail: "full"` only for the one entity
whose resolution methods, unresolved explanations, producer versions, or byte
offsets you need, for example to review a claim or plan an impact analysis.

A neighbourhood is as large as the graph makes it. On one external Java
repository, `semidx_context depth=2` incoming on a widely used static utility
method exhausts the default 32000-byte budget, where the same call on the same
repository did not before Java static calls resolved — the answer grew because
the edges now exist. `semidx_context` has no cursor, so raise
`max_response_bytes`, lower `depth`, or lower `relationship_limit` when
`budget_exhausted` is true.

### Protocol Versions

One process serves both of these, decided per request:

| Client | How it talks to the server |
| --- | --- |
| `2026-07-28` | Every request carries `io.modelcontextprotocol/protocolVersion` = `2026-07-28` and `io.modelcontextprotocol/clientCapabilities` in `params._meta`. No handshake. `server/discover`, `tools/list`, and `tools/call` are served. |
| `2025-06-18` | `initialize`, then `notifications/initialized`, then `tools/list` and `tools/call` without `_meta`. `ping` is answered. |

`server/discover` and a modern `-32022` error list only `2026-07-28`; the
`2025-06-18` version is reached through `initialize`, which always answers
`2025-06-18`.

A `2026-07-28` session, one request and response per line:

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}},"name":"semidx_find_definitions","arguments":{"path":"src/mcp/protocol.zig","role":"function"}}}
```

The response is a `CallToolResult` with `resultType: "complete"`, a
`structuredContent` object, a text block holding the same object serialized as
JSON, and `isError: false`.

## Tools

Every list is bounded and reports its total and whether it was truncated, and
every tool that returns lists reports the limits it applied in `budget`. List
tools also stop at a [response budget](#response-budget), may add
[narrowing hints](#narrowing-hints), and some continue through
[cursors](#cursors).
Invalid argument values, wrong argument types, and unknown arguments are
returned as a tool result with `isError: true` and an explanation. Each tool's
`inputSchema` in `tools/list` names exactly the arguments, types, enum values,
defaults, and maxima the server validates.

| Tool | Arguments (defaults) | Returns |
| --- | --- | --- |
| `semidx_health` | none | Product version, root, snapshot revision, refresh recovery state (`recovery`: rebuild count, a rebuilt index awaiting publication, a rebuild still needed), unit counts by analysis state and language, entity and assertion counts, per-language parser availability and declared coverage, diagnostic counts, the last scan outcome, and whether evidence text is enabled. |
| `semidx_outline` | `path_prefix` (a directory; omitted for the root), `language`, `limit` (100, max 1000 entries), `max_response_bytes`, `cursor` | The directories and files directly under `path_prefix`, sorted by name, with counts and no definitions. See [Outline](#outline). |
| `semidx_repo_map` | `path_prefix`, `language`, `limit` (100, max 1000 files), `definitions_per_file` (50, max 500), `detail` (`compact`), `max_response_bytes`, `cursor` | Units sorted by path, each with its analysis state, diagnostic counts, and top-level definitions (definitions with an empty container path), plus the number of nested definitions. `path_prefix` is a plain string prefix of unit paths. `compact` gives each unit's `id`, `path`, `language`, and `analysis`, and each definition's `id`, `role`, `name`, `freshness`, and `range` lines; `full` gives the unit's revisions and entity id and each definition as an entity with its `evidence`. |
| `semidx_find_definitions` | `name`, `path`, `language`, `role`, `freshness` (`current`), `resolution` (`any`), `limit` (50, max 500), `max_response_bytes`, `cursor` | Definitions matching every given filter, each with its existence claim's resolution, producer, and freshness. |
| `semidx_references` | `entity_id`, or `name` with optional `path`/`language`; `direction` (`incoming`), `freshness` (`current`), `resolution` (`any`), `limit` (100, max 1000), `detail` (`compact`), `max_response_bytes`, `cursor` | The target definitions (at most 50, on every page) and the `REFERENCES`/`CALLS` relationships into them (`incoming`) or out of them (`outgoing`). A call is one occurrence and is listed once. `compact` renders each target once, with its existence claim, and names a relationship end that is a target by `id` alone; `full` renders both ends of every relationship. |
| `semidx_context` | `entity_id`, `name` (with optional `path`/`language`), or `path` alone for a source unit; `freshness` (`current`), `direction` (`both`), `depth` (1, max 3), `relationship_limit` (50, max 500, per direction), `diagnostic_limit` (50, max 500), `detail` (`compact`), `max_response_bytes` | Up to 10 focus entities, each with its unit's analysis state, incoming and outgoing relationships of every kind (only those `direction` includes), the unit's diagnostics, and the entity's last identity event. `compact` names the focus end of each relationship by `id` alone and renders the other end, resolutions, producers, evidence, and diagnostics without their full fields; `full` renders them all. `depth` 2 or 3 adds a [traversal](#traversal). |
| `semidx_refresh` | none | The new and previous snapshot revisions, `entity_ids_preserved` (false when this refresh published an index rebuilt after a failure), the scan outcome (unchanged, changed, renamed, added, removed, analyzed, ambiguous renames, invalidated), unit counts, and diagnostic counts. |

`freshness` is `current`, `stale`, or `any`. `resolution` is `any`, `fact`,
`unresolved`, or `approximate`. `language` is `java`, `clojure`, or `zig`.
`detail` is `compact` or `full`. `direction` is `incoming`, `outgoing`, or
`both`. `max_response_bytes` defaults to 32000 (max 2000000).
`role` is the frontend's role for a definition: for Zig `function` or
`container`. A Zig member function has role `function` and a one-element
`container_path`; `semidx_repo_map` counts it as nested.

## Result Fields

Every structured result carries:

| Field | Meaning |
| --- | --- |
| `snapshot.revision` | The graph revision every value in this result was read from. |
| `semantic_contract_version` | Always `null`: no semantic contract is published. |

The product version (`0.1.0-preview.3`) is reported by `--version`, in
`serverInfo.version`, and as `product_version` in `semidx_health`. It versions
the binary and its behavior; it is not a semantic contract version.

The values below are described at the `full` detail level. `semidx_repo_map`
and `semidx_context` render a subset of them by default; see
[Detail Levels And Budgets](#detail-levels-and-budgets).

An **entity** carries `id`, `kind` (`repository`, `file`, `definition`),
`language`, `role`, `name`, `freshness`, and `evidence`. Full entities (from
`semidx_find_definitions`, `semidx_context`, and reference targets) add
`container_path`, `extension` (the language namespace and labels, such as
`zig.construct`), `existence` (the latest existence claim: `assertion_id`,
`resolution`, `producer`, `freshness`, `revision`), `created_revision`, and
`observed_revision`. Entity ids are allocated by the graph and keep meaning
only within one server process: the graph is rebuilt on every start, so an id
is not guaranteed to name the same entity after a restart.

A **relationship** carries `assertion_id`, `kind` (`contains`, `defines`,
`references`, `calls`), `source` (an entity), `target`, `resolution`,
`producer`, `freshness`, `revision`, and `evidence`. `target` is either
`{"entity": …}` or `{"designator": "…"}`; a designator is never an entity. In
`semidx_references` and traversal edges, `direction` says whether the
relationship enters or leaves the entity it was found from; a traversal edge
also carries `distance` and `from`. An entity rendered as `{"id": …}` alone is
rendered with its fields elsewhere in the same result.

A **resolution** carries `category` and, by category: `method` (`fact`),
`missing` and `explanation` (`unresolved`), or `basis` and `confidence`
(`approximate`).

**Evidence** carries `unit` (`id`, `path`) and `range`: `start_line` and
`end_line` are 1-based; `start_column` and `end_column` are 0-based byte
columns; `start_byte` and `end_byte` are byte offsets into the unit.

A **diagnostic** carries `kind` (`analysis_unavailable`, `analysis_failed`,
`unsupported_construct`, `confirmed_absence`), `unit`, `producer`, `message`,
and `revision`.

Strings that are not valid UTF-8 in the source tree are returned with each
invalid byte replaced by U+FFFD.

## Detail Levels And Budgets

`semidx_repo_map`, `semidx_references`, and `semidx_context` take `detail`. Like every other argument
and field here, detail levels are experimental preview ergonomics, not a
published semantic contract: `semantic_contract_version` stays `null`, and the
graph values behind both levels are the same.

- **`full`** renders what the tool rendered before detail levels existed, plus
  `budget`. For `semidx_context` that is every field described in
  [Result Fields](#result-fields), including full focus entities with their
  `existence` claims. For `semidx_repo_map` it is the richer unit and each
  definition as a brief entity (`id`, `kind`, `language`, `role`, `name`,
  `freshness`, `evidence`): it carries no `existence`, `extension`, or entity
  revisions. For a definition's existence claim, producer, and resolution, use
  `semidx_find_definitions` or `semidx_context`.
- **`compact`** (the default) renders a subset of the same fields under the
  same names and JSON types, with one exception: a definition listed by
  `semidx_repo_map` carries `range` directly instead of `evidence`, because
  its unit is the file it is listed under. Under `--allow-evidence-text` its
  `source_text` is likewise a sibling of that `range`.

What compact keeps and drops:

| Value | Compact keeps | Compact drops |
| --- | --- | --- |
| Unit (`semidx_repo_map` file, `semidx_context` focus unit) | `id`, `path`, `language`, `analysis` | `file_entity_id`, `content_revision`, `analysis_revision` |
| Repository map definition | `id`, `role`, `name`, `freshness`, `range` (`start_line`, `end_line`), and `source_text` under `--allow-evidence-text` | `kind`, `language`, `evidence` |
| Context focus entity | `id`, `kind`, `language`, `role`, `name`, `freshness`, `evidence`, `container_path`, `existence` (`resolution`, `producer`, `freshness`) | `extension`, `created_revision`, `observed_revision`, existence `assertion_id` and `revision` |
| Relationship in context | `assertion_id`, `kind`, `source`, `target`, `resolution`, `producer`, `freshness`, `evidence`. The focus end is `{"id": …}` alone; the other end has `id`, `kind`, `role`, `name`, `freshness`, `evidence`; a designator target is unchanged. | `revision`; `language` of the other end |
| References target | `id`, `kind`, `language`, `role`, `name`, `freshness`, `evidence`, `container_path`, `existence` (`resolution`, `producer`, `freshness`) | `extension`, `created_revision`, `observed_revision`, existence `assertion_id` and `revision` |
| Relationship in references | As in context, plus `direction`; an end that is a listed target is `{"id": …}` alone. | `revision`; `language` of the other end |
| Resolution | `category`; `missing` when unresolved; `confidence` when approximate | `method`, `explanation`, `basis` |
| Producer | `name` | `version` |
| Evidence | `unit.path`, `range.start_line`, `range.end_line`, and `source_text` under `--allow-evidence-text` | `unit.id`, columns, byte offsets |
| Diagnostic in context | `kind`, `producer`, `message` | `unit` (the focus unit), `revision` |

Compact never changes a claim: in `semidx_context` and `semidx_references` an
unresolved claim still has category `unresolved` and a designator target, and
every relationship, focus or target existence claim still carries its
resolution category, producer name, and freshness. `semidx_repo_map` is orientation at both levels: its
definitions carry freshness and location, never their existence claim's
resolution or producer. The evidence-text opt-in applies at both levels.

`budget` names what bounded the result:

| Tool | `budget` |
| --- | --- |
| `semidx_outline` | `limit`, `max_response_bytes` |
| `semidx_repo_map` | `detail`, `limit`, `definitions_per_file`, `max_response_bytes` |
| `semidx_find_definitions` | `limit`, `max_response_bytes` |
| `semidx_references` | `detail`, `limit`, `target_limit` (50), `max_response_bytes` |
| `semidx_context` | `detail`, `direction`, `depth`, `relationship_limit`, `diagnostic_limit`, `focus_limit` (10), `max_response_bytes` |

Budgets select whole items before rendering. A result is never cut in the
middle; a list that returns fewer items than it selected says so through its
`…_total` and `…_truncated` fields (`truncated` is true exactly when fewer
items were returned than the total).

This section and the five below own the preview terms *outline*, *response
budget*, *narrowing hint*, *cursor*, and *traversal*. They are MCP output
mechanics: none of them changes what the graph records or what a query
selects.

### Outline

`semidx_outline` answers "where should I look?" without listing definitions.
`path_prefix` names a directory, root-relative and `/`-separated; a trailing
`/` is optional, and omitting it means the root. The result echoes the
normalized `path_prefix` (`""` or ending in `/`) and lists `entries`, the
immediate children that contain at least one unit (after the `language`
filter):

- a **directory** entry: `name`, `path` (ending in `/`), `type: "directory"`,
  and `counts` summed over every unit below it: `units`, `languages` (units
  per language), `analysis` (units per analysis state), `diagnostics` (per
  kind), `top_level_definitions`, and `nested_definitions`;
- a **file** entry: `name`, `path`, `type: "file"`, its compact `unit`, and
  `counts` with `diagnostics`, `top_level_definitions`, and
  `nested_definitions`.

`totals` has the directory counts over every matched unit, and
`entries_total` and `truncated` bound the list. Definition counts are current
definitions split as `semidx_repo_map` splits them. A counted definition is a
count, not a listed entity: open `semidx_repo_map` for its name and lines. A
`path_prefix` under which no unit exists returns no entries and zero totals.

### Response Budget

Every list tool takes `max_response_bytes` (default 32000, max 2000000). Items
are selected whole: an outline entry, a map file with its definitions, a
definition, a relationship, a context focus entity, a diagnostic, or a
traversal edge is rendered on its own first and appended only when the
structured result stays within the budget. The first item of a result is
always returned, so a small budget still makes progress. Once one item does
not fit, no later item is appended, so each list returns a prefix of what it
selected. The totals, hints, and `budget` that close a result follow the last
item and are not counted; they add a few hundred bytes. `semidx_references`
targets (at most 50) are outside the budget, so its first relationship is the
item always returned. The text block repeats the structured result, so the
response on the wire is about twice the budget.

Every budgeted result reports `budget_exhausted`. When it is true it also
reports `omitted_by_budget`: for each list, how many items were selected within
that list's own limit but not returned (`entries`; `files`; `definitions`;
`relationships`; or `focus`, `relationships`, `diagnostics`, and `edges`).
Omitted items are not less relevant or less certain than returned ones; they
come later in the list's order.

### Narrowing Hints

A result whose list was cut, by a limit or by the budget, carries
`narrowing_hints`; a complete result carries none. Each hint is
`{"list": …, "action": …, "arguments": […]}`:

| `action` | Meaning |
| --- | --- |
| `narrow` | Give one of these arguments to select fewer items. |
| `raise` | Give a larger value for one of these arguments. |
| `lower` | Give a smaller value for one of these arguments. |
| `continue` | Repeat the call with `cursor` set to `next_cursor`. |

`list` names the cut list, or `response` when the budget cut it. A hint names
only arguments the same tool declares; it omits arguments the call already
gave (except `path_prefix`, which a longer prefix narrows, and a `direction`
or `resolution` that still selects everything) and limits already at their
maximum. Hints are derived from which list was cut and which arguments were
given, never from entity names, paths, or counts, and they are not graph
claims: a hint says nothing about the items it did not return.

### Cursors

`semidx_outline`, `semidx_repo_map`, `semidx_find_definitions`, and
`semidx_references` return `offset` (the position of their first returned
item) and, while items remain after this page, `next_cursor`. Repeat the call
with `cursor` set to it and the same other arguments; `limit` and
`max_response_bytes` may change between pages. Pages over one snapshot
revision return every item exactly once, in order, and keep the whole call's
totals. `semidx_context` has no cursor: narrow it with `entity_id`,
`direction`, or its limits.

A cursor is opaque and authenticated: it carries a tag over its fields, keyed
by a secret the server process generates at startup. A cursor that was altered
or truncated, or that came from another server process, does not verify and is
refused, so a page is never a continuation the server did not issue — a
restarted server refuses every earlier cursor, because its revision numbers
start again. A cursor that verifies is still used only for the tool that
issued it, the snapshot revision it was issued at, and the same arguments: it
carries the arguments of the call that issued it, and they are compared byte
for byte, so no two argument sets can be taken for each other. Anything else
is a tool error (`isError: true`) that says which of those differs. Treat the string as a token to pass back unchanged; do not build or
edit one. After
`semidx_refresh` publishes a new revision, every earlier cursor fails, so a
walk never mixes two graph states; repeat the call without `cursor`. A refresh
that finds no change keeps the revision, and cursors stay valid because the
graph is the same. `tools/list` is not paginated and refuses any `cursor`.

### Traversal

`semidx_context` takes `direction` (`both`, `incoming`, `outgoing`) and `depth`
(1 to 3). A `direction` that excludes a list omits that list and its
`…_total` and `…_truncated` fields. At `depth` 1 (the default) the result is
the one-step context described above.

At `depth` 2 or 3 the result adds `traversal`: `depth`, `direction`, `edges`,
`edges_total`, `edges_truncated`, and `reached_total`. Starting from the
entities the focus lists reached, each step lists the relationships of the
entities reached at the step before (in `direction`), up to `depth` steps from
the focus. Each edge is a relationship with `direction`, `distance` (2 or 3),
and `from`, the entity it was found from. In a traversal result:

- every entity is rendered with its fields at its first occurrence and as
  `{"id": …}` afterwards (a focus entity keeps its own focus rendering);
- a relationship already listed, in a focus list or at an earlier step, is not
  listed again;
- an entity is expanded at most once and focus entities never, so cycles end;
- a designator is never followed, and every edge keeps its resolution,
  producer, freshness, and evidence, so a fact and an unresolved call stay
  apart at every distance;
- `relationship_limit` applies per expanded entity and direction;
  `edges_total` counts the relationships of the entities that were expanded,
  and `edges_truncated` says whether fewer edges were listed. An entity reached
  only through an edge that was not listed is not expanded.

## Source Text

- **Default:** no source text. The server never reads a unit's contents into a
  result. Paths, ranges, entity names, designators, and diagnostic messages are
  graph values and are returned.
- **`--allow-evidence-text`:** each `evidence` object gains
  `source_text: {text, truncated}` (a compact `semidx_repo_map` definition,
  which has no `evidence`, carries it next to its `range`), the text a
  producer recorded for that claim,
  cut at 400 bytes on a UTF-8 boundary. Current frontends record a name or a
  callee as written, not a declaration body.
- Results go only to the client process that started the server. What that
  client does with them — including sending them to a hosted model — is
  governed by the client, not by semidx. See
  [Data Leaving The Server](#data-leaving-the-server).

## Errors

| Situation | Response |
| --- | --- |
| Line is not JSON | `-32700`, no `id` |
| Batch array, missing `method`, `jsonrpc` other than `"2.0"`, `null` id | `-32600` |
| Message longer than 1 MiB | `-32600`; the next line is read normally |
| Unknown method | `-32601` |
| Non-object `params` or `_meta`; non-string `io.modelcontextprotocol/protocolVersion`; `2026-07-28` request without `clientCapabilities`; `tools/call` without a string `name` or with non-object `arguments`; unknown tool; any `cursor`; `tools/list` or `tools/call` in `2025-06-18` form before `initialize`; `initialize` without a string `protocolVersion` | `-32602` |
| `io.modelcontextprotocol/protocolVersion` other than `2026-07-28` | `-32022` with `data.supported` and `data.requested` |
| Invalid argument value or unknown argument | Tool result with `isError: true` |
| `cursor` altered after it was issued, issued by another server process, or issued by another tool, at another snapshot revision, or for other arguments | Tool result with `isError: true` saying which, and to repeat the call without `cursor` after a refresh |
| Refresh cannot scan the root | Tool result with `isError: true`; the index is unchanged and the previous snapshot stays published |
| Refresh fails while reconciling or publishing | Tool result with `isError: true` saying whether the index was rebuilt; the previous snapshot stays published, and the next refresh publishes the rebuilt index or retries the rebuild |

Notifications, including malformed ones, are never answered.

## Limits

- Coverage is the frontends' coverage, stated per producer in the
  [preview capability matrix](../spec/capability_matrix.md). For Zig: top-level
  functions, top-level containers, and functions declared directly inside those
  containers are definitions
  ([ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md)).
  In their bodies, a bare call is a `calls` fact only when it names the unit's
  one top-level function of that name, and `alias.foo(...)` is a cross-unit
  `calls` fact only when `alias` is a top-level
  `const alias = @import("relative/path.zig")` naming one indexed Zig unit that
  exports exactly one top-level `pub fn foo`. So `semidx_references` lists
  callers of such a function from files that import it that way. Calls through
  receivers or values (`self.handle()`), package imports (`std.…`), nested
  namespaces, and container members stay unresolved designators. An importer of
  a file that did not exist when it was analyzed is not reanalyzed when the
  file appears; refresh after editing the importer. Calls under logical negation
  (`!helper()`) stay unresolved
  ([follow-up 001](../followups/001_zig_logical_negation_calls.md)), and a unit
  with an empty container body fails analysis
  ([follow-up 002](../followups/002_zig_empty_container_grammar.md)).
- Java answers stop at a **visibility boundary**. A Java unit's scope is its
  source root: what remains of its path once the directories its declared
  package spells and the file name are removed from the end, so
  `a/b/src/main/java/demo/X.java` declaring `package demo` has source root
  `a/b/src/main/java`. Same-package names and single-type imports
  (`import a.b.C;`) resolve only to units in that same root, or from a
  `<base>/src/test/<lang>` root into `<base>/src/main/<lang>` — that direction
  only. Two modules that share a package resolve nothing into each other, even
  where a build tool would permit it, and a unit whose path does not spell its
  declared package resolves nothing beyond itself
  ([ADR 008](../adr/008_java_visibility_boundaries.md)). Each case says which it
  is: a name declared out of reach reads differently from a name nothing
  declares. On-demand imports (`import a.b.*;`) and static imports never
  resolve.
- A Java invocation written `ClassName.method(...)` is a `calls` fact only when
  nothing in scope binds that name — no parameter, local, field, `for`
  variable, `catch` parameter, resource, lambda parameter, or pattern — the
  enclosing class declares no supertypes, the name reaches one current
  top-level class inside the boundary above, that class declares no supertypes,
  and it declares exactly one method of the invoked name that is `static` and
  either public or inside the enclosing class
  ([ADR 009](../adr/009_java_static_calls.md)). So `semidx_references incoming`
  on a static utility method lists its callers. A receiver that is a value
  (`local.m()`, `field.m()`, `new T().m()`, `a().b()`, `super.m()`) stays an
  unresolved designator, and so does an overloaded, inherited, non-static, or
  less-accessible target — each saying which condition failed. Nothing here
  records dispatch, hiding, or overload selection. Java definitions carry the
  shape a caller has to check as extension labels: `java.supertypes` on a
  class, `java.access` and `java.static` on a method.
- A reference to a type with no source under `--root` — every JDK type, and
  anything from a dependency not checked out here — is an unresolved designator.
  semidx reads no `.jar`, no class file, and no build descriptor, so no
  configuration changes that. Expect it to be most of what Java leaves
  unresolved.
- The graph lives in memory and is rebuilt on every start. Edits are observed
  only after `semidx_refresh`. A refresh with no source changes publishes the
  same revision.
- List results stop at the response budget, 32000 structured bytes by
  default, plus the few hundred bytes of fields that close a result. Every
  tool result also repeats its structured object as JSON text for clients
  without structured-content support, so a default response can reach about
  65 KB on the wire. Whether a client shows the model one copy or both, and
  where it starts warning or spilling to a file, depends on the client. An
  explicit `max_response_bytes` up to 2000000 returns larger results, and
  `semidx_health` and `semidx_refresh` are not budgeted (their size does not
  grow with the number of definitions).
- A refresh that fails after reconciliation started (for example, out of
  memory) never publishes a partly updated graph. The server discards that index
  and rebuilds a fresh one from the same scan; the published snapshot stays the
  previous one until the next refresh publishes the rebuilt index. A rebuilt
  index cannot establish identity with the old one: entity ids from earlier
  snapshots name nothing in it (they are never reused for other entities), and
  that refresh reports `entity_ids_preserved: false`. Look targets up again by
  name or path.
- The product version is a preview version: tool names, arguments, and result
  fields may change between previews. The current release-candidate notes are
  [v0.1.0-preview.3](../releases/v0.1.0-preview.3.md), which publish
  Plan 009 progressive MCP discovery and response-budget behavior. The
  [v0.1.0-preview.2](../releases/v0.1.0-preview.2.md) notes describe the
  Plan 006 Zig coverage, and the earlier
  [v0.1.0-preview.1](../releases/v0.1.0-preview.1.md) notes describe the tree
  before it, with release-gate evidence recorded in the
  [Plan 005 progress log](../reports/005_mcp_preview_release_readiness_progress.md#stage-5-preview-release-candidate-handoff).
  What the habit loop gate proves, and what it does not, is specified in
  [Habit loop gate](habit_loop_gate.md).
