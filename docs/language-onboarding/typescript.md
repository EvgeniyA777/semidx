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
  - default-import ownership for `export default function ...`
  - `this.` and local class-qualified method targeting
  - exported arrow/function-expression bindings as first-class units

## Next Steps (ADR-022)

1. Expand extraction coverage for object-literal methods and TS-specific syntax variants.
2. Add targeted ambiguity fixtures for re-export chains and `export default foo` indirection.
3. Raise the public confidence ceiling only after a stronger parser path proves it.
4. Keep running `./scripts/validate-language-onboarding.sh typescript`.
