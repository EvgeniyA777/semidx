---
title: "Tooling Policy"
doc_type: "policy"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# Tooling Policy

How agents retrieve, read, and edit code in this repository. `RULES.md` owns the
always-loaded summary and points here.

## Scope Of The MCP Sections

The MCP sections below describe repository-development tooling available to
agents today. The `semidx` MCP server they use is configured outside this
repository: `.mcp.json` here declares no servers, and nothing in this repository
builds, ships, or defines it.

The tool names, wire shapes, and error codes below describe that tool as it
currently behaves. They do not define or constrain the public API of the rebuilt
`semidx`, which is an open requirement owned by [SPEC.md](../../SPEC.md). Do not
carry them into the rebuild as contract.

## MCP-First Workflow

- If the `semidx` MCP server is available, do not begin codebase exploration with
  directory listing, wildcard search, grep, broad file reads, or shell crawling.
- Use MCP before manual file crawling. When implementation work requires reading
  code before edits, use semidx retrieval first.
- First-pass flow is strict:
  1. `create_index`
  2. `repo_map`
  3. `resolve_context`
  4. optional `expand_context`
  5. optional `fetch_context_detail`
- A successful `create_index` is not a reason to switch to filesystem browsing.
  Continue with `repo_map` and semantic retrieval.
- Use `resolve_context`, `expand_context`, `fetch_context_detail`, and
  `skeletons` to read code shape and detail before patching source files.
- Use manual file reads only as a fallback when semidx MCP fails, when the target
  is outside indexed source files, or when exact patch-safe line context is still
  needed after MCP retrieval.
- Do not silently fall back to manual inspection if MCP fails. State that MCP
  failed, then continue manually if needed.

## MCP Query And Wire Shape

- `initialize.params.clientInfo` must be an object, not a string.
- `tools/call.arguments` must be a JSON object, not a JSON-encoded string.
- `resolve_context` accepts a flat top-level `intent` string, a `query.intent`
  shorthand, or the full structured `query` object.
- The simplest `resolve_context` shape is
  `{"index_id": "...", "intent": "your task"}`.
- After a successful `resolve_context`, keep context compact by continuing with
  `selection_id` and `snapshot_id` for `expand_context` or
  `fetch_context_detail`.
- Do not expand prompts manually when a selection artifact is available.
- Canonical MCP client prompts, once documented, belong in `docs/`; no such
  document exists yet.

## MCP Failure Protocol

- Treat `no_supported_languages_found` as a user-guidance path: ask for the core
  language and suggest activating other languages later.
- Treat `language_refresh_required` as a signal to rerun `create_index`.
- Treat `language_activation_in_progress` as a wait-and-retry signal for the same
  request.
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
| Which code is relevant? Who calls this? What is the blast radius? | semidx (`resolve_context`, `impact_analysis`) — always first |
| What is the shape of one already-identified file? | A structure-aware reader for the active language (collapsed view), if one is configured |
| Which exact lines am I about to patch? | `Read` with `offset`/`limit` |
| What is the body of one symbol from an existing selection? | semidx `fetch_context_detail` with `selection_id` |

- **A language-specific reader never substitutes for the first semidx call.** If
  it is not yet known which file is needed, that is semidx's job. Opening files
  one after another to get oriented is prohibited, however cheap each individual
  read looks. This is the failure mode semidx exists to prevent.
- Do not route narrow reads through semidx. `fetch_context_detail` wraps the code
  in a full retrieval envelope (stage events, capabilities, guardrails,
  diagnostics), so it is the wrong tool for "show me the lines I am about to
  edit". Use `Read` with `offset`/`limit` there.
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

- **A verification probe after any code edit is mandatory, not advisory.** What
  counts as a probe (compile, typecheck, lint, or a REPL/eval smoke) is
  determined by the implementation language chosen for the affected code; no
  language is fixed right now.
- Prefer a structure-aware editor whenever one is configured for the active
  language and the unit of change is a whole function or definition — such tools
  typically validate syntax on the way in, so a rewrite cannot land unbalanced or
  malformed.
- Keep patches scoped to one logical unit (function, definition, form) where
  possible, and avoid large rewrites of deeply nested code when a narrower edit
  will work.
- Once an implementation language is chosen, add a language-specific addendum
  here naming the exact probe command, the structure-aware editor, and the
  REPL/eval workflow for that language.
