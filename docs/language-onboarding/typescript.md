# TypeScript Onboarding Status

Created with `scripts/new-language-adapter.sh` and now upgraded with baseline parser coverage.

## Current State

- Language key: `typescript`
- File extensions: `.ts,.tsx`
- Parser function: `parse-typescript` (regex baseline)
- Fixture files:
  - `fixtures/retrieval/typescript-happy-path.json`
  - `fixtures/retrieval/typescript-ambiguity.json`

## Next Steps (ADR-022)

1. Expand extraction coverage for object-literal methods and TS-specific syntax variants.
2. Add targeted ambiguity fixtures for overloaded signatures and namespace-like exports.
3. Consider optional tree-sitter TypeScript engine for higher semantic fidelity.
4. Keep running `./scripts/validate-language-onboarding.sh typescript`.
