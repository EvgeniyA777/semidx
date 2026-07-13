# CSS Onboarding Status

Created as a first-class language lane for stylesheet selector context and static
asset references.

## Current State

- Language key: `css`
- File extensions: `.css`
- Parser function: `semidx.runtime.languages.css/parse-file`
- Adapter wrapper: `semidx.runtime.adapters/parse-css`
- Fixture files:
  - `fixtures/retrieval/css-happy-path.json`
  - `fixtures/retrieval/css-ambiguity.json`
- Current semantic coverage:
  - stylesheet units
  - selector units for `.class-name`, `#id-name`, tag selectors, and simple
    compound selectors
  - at-rule units for `@media`, `@supports`, and `@keyframes`
  - CSS custom property units such as `--brand-color`
  - static dependencies from `@import` and `url(...)`

## Next Steps (ADR-022)

1. Add more ambiguity fixtures for selector collisions across multiple
   stylesheets.
2. Consider Tree-sitter CSS parsing after the native parser has stable evidence.
3. Defer full cascade and specificity modeling until retrieval requires it.
4. Keep running `./scripts/validate-language-onboarding.sh css`.
