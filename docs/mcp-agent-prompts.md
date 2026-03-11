# MCP Agent Prompts

These prompts are the canonical copy-ready snippets for IDEs and coding agents that should use `semantic-code-indexing` correctly on the first pass.

Use them when:

- an IDE has an MCP server instruction field
- an agent supports repo-level onboarding prompts
- you want agents to prefer MCP over manual file crawling for initial repo understanding

## Universal Strict Prompt

```text
Use the `semantic-code-indexing` MCP server as the primary tool for first-pass repository understanding.

Operational rules:
1. Always call `create_index` first for the repository root.
2. Immediately call `repo_map` after a successful `create_index`.
3. For code understanding or implementation work, use the canonical retrieval flow:
   - `resolve_context`
   - optional `expand_context`
   - optional `fetch_context_detail`
4. If the server returns `no_supported_languages_found`, ask the user which core language the project uses. Recommend selecting one core language first and activating additional languages later if needed.
5. If the server returns `language_refresh_required`, rerun `create_index` instead of abandoning MCP.
6. If the server returns `language_activation_in_progress`, wait briefly and retry the same request.
7. Do not silently fall back to manual file inspection. If MCP fails, explicitly state that MCP failed, then continue with manual repository inspection only if necessary.

Wire-shape requirements:
- Send `initialize.params.clientInfo` as an object, not a string.
- Send `tools/call.arguments` as a JSON object, not a JSON-encoded string.
```

## Codex Prompt

```text
For this repository, use `semantic-code-indexing` in MCP-first mode.

Required first-pass workflow:
1. `create_index`
2. `repo_map`
3. `resolve_context`
4. optional `expand_context`
5. optional `fetch_context_detail`

Behavior rules:
- Use MCP before broad manual file reads whenever the server is available.
- If `no_supported_languages_found` is returned, ask the user to choose the core language from the supported list and recommend enabling additional languages later only as needed.
- If `language_refresh_required` is returned, rerun `create_index`.
- If `language_activation_in_progress` is returned, retry the same request after a short wait.
- Do not silently abandon MCP. Explicitly report MCP failure before switching to manual repository inspection.

Protocol rules:
- `initialize.params.clientInfo` must be an object.
- `tools/call.arguments` must be a JSON object.
```

## Claude / IDE-Agent Prompt

```text
Use the `semantic-code-indexing` MCP server first, not manual repo browsing, for initial codebase understanding.

Workflow:
1. call `create_index`
2. call `repo_map`
3. use `resolve_context`
4. use `expand_context` only when you need structural widening
5. use `fetch_context_detail` only when you need richer evidence or raw code

Error handling:
- `no_supported_languages_found`: ask the user to choose the core language; recommend activating other languages later
- `language_refresh_required`: rerun `create_index`
- `language_activation_in_progress`: wait and retry the same request

Fallback:
- if MCP fails, say that MCP failed
- only then switch to manual file inspection

Protocol constraints:
- `clientInfo` must be an object
- `tools/call.arguments` must be an object
```

## Generic IDE Field Prompt

```text
Use semantic-code-indexing in MCP-first mode: call create_index, then repo_map, then use resolve_context -> expand_context -> fetch_context_detail. Treat no_supported_languages_found as a prompt to ask for the core language, language_refresh_required as rerun-create_index, and language_activation_in_progress as wait-and-retry. Report MCP failure explicitly before falling back to manual repo inspection. Send clientInfo and tools/call.arguments as JSON objects, not strings.
```

## Description-Field Snippet

Use this only when the client gives you a tiny MCP `description` field and nothing else:

```text
Repository-aware MCP for MCP-first code understanding: create_index, repo_map, resolve_context, staged expansion/detail, impact analysis, and skeletons with explicit language activation and refresh guidance.
```
