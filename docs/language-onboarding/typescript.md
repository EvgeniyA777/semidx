# TypeScript Onboarding Status

Created with `scripts/new-language-adapter.sh` and now upgraded with strategic semantic-core coverage on the default regex path.

## Current State

- Language key: `typescript`
- File extensions: `.ts,.tsx`
- Parser function: `parse-typescript` (regex default, tree-sitter optional)
- Fixture files:
  - `fixtures/retrieval/typescript-happy-path.json`
  - `fixtures/retrieval/typescript-ambiguity.json`
- Current semantic coverage:
  - named imports
  - namespace imports
  - default-import ownership for both `export default function ...` and `export default foo;`
  - `this.` and local class-qualified method targeting
  - exported arrow/function-expression bindings as first-class units
  - object-literal methods and class field arrow methods
  - direct re-export alias units for simple barrel-style `export { foo as bar } from "./mod"` lines

## Next Steps (ADR-022)

1. Tighten tree-sitter parity with the newer regex-side object/class-field/default-alias coverage.
2. Expand ambiguity fixtures beyond direct one-hop re-export aliases into deeper barrel chains.
3. Raise the public confidence ceiling only after a stronger parser path proves it.
4. Keep running `./scripts/validate-language-onboarding.sh typescript`.
