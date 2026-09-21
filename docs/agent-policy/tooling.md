---
title: "Tooling Policy"
doc_type: "policy"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# Tooling Policy

How agents retrieve, read, and edit code in this repository. `RULES.md` owns the
always-loaded summary and points here.

## Scope Of The MCP Sections

The MCP sections below describe repository-development tooling available to
agents today. This repository's `.mcp.json` registers the experimental local
`semidx-mcp` preview built by this repository
([ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md)). It is a local
consumer over published graph snapshots, not a public semantic contract.

The tool names, wire shapes, and error codes below describe the preview as it
currently behaves. They do not define or constrain the future stable public API,
which is an open requirement owned by [SPEC.md](../../SPEC.md).

## MCP-First Workflow

- If the `semidx` MCP server is available, do not begin codebase exploration with
  directory listing, wildcard search, grep, broad file reads, or shell crawling.
- Use MCP before manual file crawling. When implementation work requires reading
  code before edits, use semidx retrieval first.
- First-pass flow is strict:
  1. `semidx_health`
  2. `semidx_outline` (repeat with a directory `path_prefix` to descend)
  3. `semidx_repo_map` with the `path_prefix` of one directory or file
  4. `semidx_find_definitions`
  5. `semidx_references` or `semidx_context`
  6. `semidx_refresh` after edits
- A successful `semidx_health` is not a reason to switch to filesystem browsing.
  Continue with `semidx_outline`, a scoped `semidx_repo_map`, and graph-backed
  lookup.
- When a result is cut, follow its `narrowing_hints` before raising limits or
  walking `next_cursor` pages.
- Use `semidx_context` to read the focused graph neighborhood before patching
  source files.
- Use manual file reads only as a fallback when semidx MCP fails, when the target
  is outside indexed source files, or when exact patch-safe line context is still
  needed after MCP retrieval.
- Do not silently fall back to manual inspection if MCP fails. State that MCP
  failed, then continue manually if needed.

## MCP Query And Wire Shape

- The configured server is `semidx` and exposes:
  `semidx_health`, `semidx_outline`, `semidx_repo_map`,
  `semidx_find_definitions`, `semidx_references`, `semidx_context`, and
  `semidx_refresh`.
- The server indexes one root at startup. In this repository `.mcp.json` passes
  the repository root explicitly. For other repositories, register
  `/Users/ae/workspaces/semidx/scripts/semidx-mcp.sh` with that repository's
  absolute path as `--root`.
- Prefer `semidx_context` for focused orientation around an entity, name, or
  path. It returns graph values, diagnostics, freshness, and relationship
  context, not source bodies.
- Entity ids are process-local. After reconnecting or restarting the MCP server,
  look up targets again by name/path before using an old id.
- Source text is off by default. Do not add `--allow-evidence-text` unless the
  task explicitly needs recorded evidence text and the user has opted in.

## MCP Failure Protocol

- Treat parser or analysis diagnostics from `semidx_health` and
  `semidx_context` as part of the answer, not as noise to hide.
- Treat missing, unresolved, unsupported, stale, approximate, and unavailable
  results as distinct outcomes. Do not convert one into another in prose.
- Use `semidx_refresh` after edits before trusting later graph answers.
- If MCP returns an error or timeout after two attempts, say
  `SCI MCP unavailable, switching to manual` and proceed with filesystem tools.

## Preferred Tool Boundaries

- Use semidx MCP for high-level project mapping, code retrieval, dependency
  context, impact analysis, and staged context expansion.
- Once relevant context is resolved, prefer a structure-aware editing or
  REPL/eval tool for the active implementation language when one is configured
  for this repository; fall back to generic file edits otherwise.
- Use semidx for retrieval only. It is not a replacement for a REPL, a
  formatter, or a file reader.

## Code Reading Rules

Choose the reading tool by the question being answered, not by file type. semidx
and a language-specific reader answer different questions and do not compete:
semidx finds which code matters, a language-specific reader shows a file that has
already been identified.

| Question | Tool |
| --- | --- |
| Which code is relevant? Who calls this? What is the nearby graph context? | semidx (`semidx_context`, `semidx_references`) — always first |
| What is the shape of one already-identified file? | A structure-aware reader for the active language (collapsed view), if one is configured |
| Which exact lines am I about to patch? | `Read` with `offset`/`limit` |
| What is the body of one symbol already located? | `Read` with `offset`/`limit` on the known file |

- **A language-specific reader never substitutes for the first semidx call.** If
  it is not yet known which file is needed, that is semidx's job. Opening files
  one after another to get oriented is prohibited, however cheap each individual
  read looks. This is the failure mode semidx exists to prevent.
- Do not route narrow source reads through semidx. The local preview deliberately
  returns graph context, paths, ranges, and diagnostics rather than source
  bodies by default. Use `Read` with `offset`/`limit` for exact patch context
  after semidx has located the relevant entity or file.
- Prefer a language-specific structure-aware reader over a full `Read` when
  orienting inside a single large known file: a collapsed, structure-aware view
  costs less than dumping the whole file and is more reliable than guessing line
  ranges.
- Language-specific MCP tools are commonly path-contained to the repository root
  or a configured directory set. When a target lies outside that set, fall back
  to `Read` plus whatever verification probe applies to that language.
- No hook enforces any of this. The `semidx-first` guard matches only `Grep`,
  `Glob`, and `Bash`, and has no visibility into MCP tool calls. These rules hold
  by discipline alone.

## Editing Rules

Choose the editing tool by the risk of the edit, not by file extension. Every
edit carries a required safety step. The safety step is not optional.

| Situation | Tool | Required follow-up |
| --- | --- | --- |
| New file written in full | `Write` or heredoc | Compile/typecheck/lint probe for the language, or a read-back check for non-code files |
| Structural edit to a whole function or definition | A structure-aware editor for the active language, when one is configured | Confirm the returned diff |
| Narrow edit inside a large existing file | `Edit` | Compile/typecheck/lint probe |
| Markdown, scripts, and other non-code files | `Edit` | Normal review |

- **A verification probe after any code edit is mandatory, not advisory.** For
  Zig, the probe is the build; the Zig addendum below names which command for
  which edit.
- Prefer a structure-aware editor whenever one is configured for the active
  language and the unit of change is a whole function or definition — such tools
  typically validate syntax on the way in, so a rewrite cannot land unbalanced or
  malformed.
- Keep patches scoped to one logical unit (function, definition, form) where
  possible, and avoid large rewrites of deeply nested code when a narrower edit
  will work.
- The Zig addendum below names the probe commands for the implementation
  language. Add a comparable addendum when another language enters the build.

## Runtime Budget For Repository Tooling

Building, indexing, and querying require Zig 0.16.0 and a local tree-sitter, and
nothing else. A tool that quietly widens what a contributor must install has
changed the project's terms, not just its tooling.

| Class | What it is | What it may require |
| --- | --- | --- |
| Guards and launchers | Run by git hooks, by build lanes, or in the daily loop — `check-*.sh`, `semidx-mcp.sh`, `install-git-hooks.sh` | POSIX `sh`. A hook that cannot start is a hook that is not there |
| Environment setup | Run once to prepare a machine — `setup-*.sh` | External tools and the network, named in the script and failing loudly when absent |
| Developer tools | Inspection and measurement commands — `semidx-dev`, `semidx-claim-sample`, `semidx-designator-shape` | Zig, built by `zig build` as its own step that no lane depends on |

**A developer tool is written in Zig.** The toolchain is already required, the
formatter and compiler check it like any other source, and it can read the graph
directly instead of re-deriving what the project already knows. Another language
buys speed of writing and charges everyone who runs it; that is not a trade this
project makes for its own tools.

Introducing a language or runtime beyond `sh` and Zig is a decision, and it is
recorded where policy requires decisions to be recorded. "It was faster to
write" is a reason, not a decision, and it does not survive the next person
asking why the file is in that language.

Two rules hold whatever the language:

- **Nothing that gates work may depend on a developer tool.** No build lane, git
  hook, `.mcp.json` entry, or build prerequisite names it. Verify that rather
  than assume it.
- **A tool is never the only copy of its procedure.** What it does is written
  out in the document that owns the measurement, in enough detail to be
  reimplemented without reading the source. A procedure that lives only in one
  implementation is lost when that implementation is not kept — which is what
  [Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md)
  records happening twice.

## Zig Addendum

The implementation language is Zig
([ADR 001](../adr/001_choose_zig_implementation_language.md)).

The target version is Zig 0.16.0 exactly, recorded in `.zigversion` and
`build.zig.zon`. All Zig source, build scripts, examples, tests, and
agent-generated changes must target Zig 0.16.0. Do not rely on code examples or
standard-library APIs from earlier or later Zig releases unless they are checked
against Zig 0.16.0.

| Need | What to use |
| --- | --- |
| Verify the selected toolchain | `./scripts/check-zig-version.sh` — fails unless `zig version` is exactly `0.16.0` and `build.zig.zon` agrees. |
| Probe after a shared-core edit | `zig build test-core` — compiles and runs `src/core/` alone, with no parser dependency, so it is the fastest signal. |
| Probe after any other code edit | `zig build test` — the full lane. Required before committing a change to a frontend, the adapter, `build.zig`, or a fixture. |
| Syntax and formatting check | `zig fmt --check build.zig src tests`; drop `--check` to fix. |
| Structure-aware editor | None is configured for Zig. Use `Read` with `offset`/`limit` to see the exact lines, then `Edit`. |
| REPL or eval | Zig has none. The equivalent smoke check is `zig build run -- <source files>`, which indexes the named files and prints a graph summary. |

- The probe after a Zig edit is required, not optional. A compile error is cheap
  to find now and expensive to leave.
- When using external examples, documentation, or memory for Zig APIs, first
  verify that the API shape is valid on Zig 0.16.0.
- `zig build` fails loudly when the tree-sitter prerequisites are missing and
  names both override flags. Do not work around that message by editing
  `build.zig`; run `./scripts/setup-tree-sitter-grammars.sh` or point the flags
  at the right paths.
