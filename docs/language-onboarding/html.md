# HTML Onboarding Status

Created as a first-class language lane for static markup context and selector
references.

## Current State

- Language key: `html`
- File extensions: `.html,.htm`
- Parser function: `semidx.runtime.languages.html/parse-file`
- Adapter wrapper: `semidx.runtime.adapters/parse-html`
- Fixture files:
  - `fixtures/retrieval/html-happy-path.json`
  - `fixtures/retrieval/html-ambiguity.json`
- Current semantic coverage:
  - document units
  - element units for ids, classes, forms, buttons, links, scripts, stylesheets,
    images, and landmark tags
  - static references from `href`, `src`, `action`, `poster`, and `data-src`
  - selector calls for `.class-name` and `#id-name` references
  - cross-language caller edges from HTML selector usage to CSS selector units

## Next Steps (ADR-022)

1. Add richer retrieval fixtures for multi-page markup and shared stylesheets.
2. Consider Tree-sitter HTML parsing only after regex coverage proves useful.
3. Keep framework-specific component semantics out of the core HTML parser until
   a dedicated component lane or Shadow IR representation exists.
4. Keep running `./scripts/validate-language-onboarding.sh html`.
