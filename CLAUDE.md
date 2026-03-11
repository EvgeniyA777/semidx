# Project Instructions

## MCP-first workflow for this repo

- If `semantic-code-indexing` MCP is configured, use it before manual file browsing.
- First-pass order:
  1. `create_index`
  2. `repo_map`
  3. `resolve_context`
  4. optional `expand_context`
  5. optional `fetch_context_detail`
- If MCP returns `no_supported_languages_found`, ask the user to choose the core language from the supported set.
- If MCP returns `language_refresh_required`, rerun `create_index`.
- If MCP returns `language_activation_in_progress`, wait and retry the same request.
- Do not silently abandon MCP. If it fails, say so explicitly, then use manual repo inspection.
- Send `clientInfo` as an object and `tools/call.arguments` as an object.
- Canonical prompt snippets live in `docs/mcp-agent-prompts.md`.
