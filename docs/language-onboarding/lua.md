# Lua Onboarding Status

Created as a dedicated Lua lane following `ADR-022` and concretized by `ADR-027`.

## Current State

- Language key: `lua`
- File extensions: `.lua`
- Parser function: `semidx.runtime.languages.lua/parse-file` (regex default)
- Fixture files:
  - `fixtures/retrieval/lua-happy-path.json`
  - `fixtures/retrieval/lua-ambiguity.json`
- Current semantic coverage:
  - `require("...")` and `require '...'` import extraction
  - top-level function definitions
  - module-table function definitions
  - module-table method definitions
  - normalized dot-call and colon-call extraction for the common module-table path
  - bounded fallback behavior through the shared parser fallback contract

## Next Steps (ADR-022)

1. Expand ambiguity coverage for local-table helpers versus exported module-table ownership.
2. Add a follow-up parser deepening slice only if fixture and benchmark evidence shows regex limits are materially affecting retrieval quality.
3. Keep Lua tree-sitter out of scope until the regex lane needs stronger evidence-backed depth.
4. Keep running `./scripts/validate-language-onboarding.sh lua`.
