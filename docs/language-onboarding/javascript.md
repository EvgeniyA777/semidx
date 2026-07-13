# JavaScript Onboarding Status

Created as a first-class language lane for JavaScript source files while reusing
the existing TypeScript parser core for ECMAScript syntax.

## Current State

- Language key: `javascript`
- File extensions: `.js,.jsx,.mjs,.cjs`
- Parser function: `semidx.runtime.languages.javascript/parse-file`
- Adapter wrapper: `semidx.runtime.adapters/parse-javascript`
- Fixture files:
  - `fixtures/retrieval/javascript-happy-path.json`
  - `fixtures/retrieval/javascript-ambiguity.json`
- Current semantic coverage:
  - ESM named, namespace, and default imports through the shared TypeScript core
  - exported functions, arrow functions, and function expressions
  - class methods
  - object-literal methods
  - direct re-export alias units inherited from the TypeScript core
  - JavaScript test-file classification for `.test.*`, `.spec.*`, and `_test.*`
    files across `.js`, `.jsx`, `.mjs`, and `.cjs`
  - extensionless module identity shared with TypeScript for JS/TS import edges

## Next Steps (ADR-022)

1. Add structural JSX coverage when the tree-sitter follow-up is prioritized.
2. Consider `package.json` manifest heuristics that distinguish pure JavaScript
   from TypeScript projects.
3. Add CommonJS `require()` dependency extraction if retrieval needs it.
4. Keep running `./scripts/validate-language-onboarding.sh javascript`.
