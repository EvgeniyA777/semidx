---
title: "Local MCP preview"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-15"
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
- watch files, persist the graph, serve HTTP, or offer resources, prompts,
  pagination, or subscriptions;
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
zig-out/bin/semidx-mcp --version           # semidx-mcp 0.1.0-preview.2
zig build test-mcp                         # optional: unit tests and the stdio smoke test
zig build dogfood                          # optional: habit loop and refresh recovery on a copy of this repository
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

A useful order for an agent starting on a repository:

1. `semidx_health`: is every unit `current`, and which languages have parsers?
2. `semidx_repo_map` with a `path_prefix`: which files and top-level
   definitions exist?
3. `semidx_find_definitions` with a `name`: where is a definition introduced?
4. `semidx_references` or `semidx_context` on it: what calls it, what does it
   call, and which of those claims are facts?
5. `semidx_refresh` after editing files, before trusting later answers.

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

Every list is bounded and reports its total and whether it was truncated.
Invalid argument values are returned as a tool result with `isError: true` and
an explanation.

| Tool | Arguments (defaults) | Returns |
| --- | --- | --- |
| `semidx_health` | none | Product version, root, snapshot revision, refresh recovery state (`recovery`: rebuild count, a rebuilt index awaiting publication, a rebuild still needed), unit counts by analysis state and language, entity and assertion counts, per-language parser availability and declared coverage, diagnostic counts, the last scan outcome, and whether evidence text is enabled. |
| `semidx_repo_map` | `path_prefix`, `language`, `limit` (100, max 1000 files), `definitions_per_file` (50, max 500), `detail` (`compact`) | Units sorted by path, each with its analysis state, diagnostic counts, and top-level definitions (definitions with an empty container path), plus the number of nested definitions. `compact` gives each unit's `id`, `path`, `language`, and `analysis`, and each definition's `id`, `role`, `name`, `freshness`, and `range` lines; `full` gives the unit's revisions and entity id and each definition as an entity with its `evidence`. |
| `semidx_find_definitions` | `name`, `path`, `language`, `role`, `freshness` (`current`), `resolution` (`any`), `limit` (50, max 500) | Definitions matching every given filter, each with its existence claim's resolution, producer, and freshness. |
| `semidx_references` | `entity_id`, or `name` with optional `path`/`language`; `direction` (`incoming`), `freshness` (`current`), `resolution` (`any`), `limit` (100, max 1000) | The target definitions (at most 50) and the `REFERENCES`/`CALLS` relationships into them (`incoming`) or out of them (`outgoing`). A call is one occurrence and is listed once. |
| `semidx_context` | `entity_id`, `name` (with optional `path`/`language`), or `path` alone for a source unit; `freshness` (`current`), `relationship_limit` (50, max 500, per direction), `diagnostic_limit` (50, max 500), `detail` (`compact`) | Up to 10 focus entities, each with its unit's analysis state, incoming and outgoing relationships of every kind, the unit's diagnostics, and the entity's last identity event. `compact` names the focus end of each relationship by `id` alone and renders the other end, resolutions, producers, evidence, and diagnostics without their full fields; `full` renders them all. |
| `semidx_refresh` | none | The new and previous snapshot revisions, `entity_ids_preserved` (false when this refresh published an index rebuilt after a failure), the scan outcome (unchanged, changed, renamed, added, removed, analyzed, ambiguous renames, invalidated), unit counts, and diagnostic counts. |

`freshness` is `current`, `stale`, or `any`. `resolution` is `any`, `fact`,
`unresolved`, or `approximate`. `language` is `java`, `clojure`, or `zig`.
`role` is the frontend's role for a definition: for Zig `function` or
`container`. A Zig member function has role `function` and a one-element
`container_path`; `semidx_repo_map` counts it as nested.

## Result Fields

Every structured result carries:

| Field | Meaning |
| --- | --- |
| `snapshot.revision` | The graph revision every value in this result was read from. |
| `semantic_contract_version` | Always `null`: no semantic contract is published. |

The product version (`0.1.0-preview.2`) is reported by `--version`, in
`serverInfo.version`, and as `product_version` in `semidx_health`. It versions
the binary and its behavior; it is not a semantic contract version.

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
`semidx_references`, `direction` says whether the relationship enters or leaves
the target.

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

## Source Text

- **Default:** no source text. The server never reads a unit's contents into a
  result. Paths, ranges, entity names, designators, and diagnostic messages are
  graph values and are returned.
- **`--allow-evidence-text`:** each `evidence` object gains
  `source_text: {text, truncated}`, the text a producer recorded for that claim,
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
- The graph lives in memory and is rebuilt on every start. Edits are observed
  only after `semidx_refresh`. A refresh with no source changes publishes the
  same revision.
- Output is bounded per list, not per response: a `semidx_context` call can
  still return a large message.
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
  [v0.1.0-preview.2](../releases/v0.1.0-preview.2.md), which add the Plan 006
  Zig coverage. The earlier
  [v0.1.0-preview.1](../releases/v0.1.0-preview.1.md) notes describe the tree
  before it, with release-gate evidence recorded in the
  [Plan 005 progress log](../reports/005_mcp_preview_release_readiness_progress.md#stage-5-preview-release-candidate-handoff).
