# Zig Onboarding Status

Created as a first-class language lane following `ADR-022` and `ADR-048`.

## Current State

- Language key: `zig`
- File extension: `.zig`
- Parser function: `semidx.runtime.languages.zig/parse-file`
- Public strength and confidence ceiling: `low`
- Fixture files:
  - `fixtures/retrieval/zig-happy-path.json`
  - `fixtures/retrieval/zig-ambiguity.json`
- Current semantic coverage:
  - path-based module identity
  - static `@import("...")` dependency and alias extraction
  - top-level functions
  - functions owned by named `struct`, `union`, `enum`, and `opaque` containers
  - Zig `test` blocks and test-to-source module linkage
  - imported, local, and receiver-style call tokens
  - bounded fallback behavior through the shared adapter facade

## Deliberate Limits

- The v1 parser is regex-first and does not claim compiler-grade resolution.
- Multiline declarations, generic/comptime evaluation, inferred receiver dispatch,
  and dynamic imports are outside the supported surface.
- No Zig-specific tree-sitter or compiler-provider option is exposed in v1.

## Next Steps (ADR-022)

1. Expand fixtures from real Zig repositories when concrete parsing gaps appear.
2. Consider tree-sitter or Zig compiler evidence only when measured retrieval
   quality justifies a stronger provider.
3. Keep running `./scripts/validate-language-onboarding.sh zig`.
