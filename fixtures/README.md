# Fixtures

Versioned retrieval fixtures used to govern behavior changes, contract stability, and benchmark expectations.

## Layout

- `retrieval/` - scenario fixtures for retrieval correctness, confidence, guardrails, and diagnostics
- `retrieval/corpus.json` - index of the current curated retrieval fixture set

## Fixture Design Rules

Fixtures in this repository follow the governance direction from `ADR-014`:

- each fixture has a stable `fixture_id`
- each fixture states a clear use-case category and purpose
- queries are included as structured data, not prose only
- expectations focus on behavior bands and required outputs, not brittle implementation details
- confidence and guardrail expectations are explicit where they matter

## Notes

- These fixtures are intentionally compact and repository-agnostic. They describe expected retrieval behavior, not a full runnable repo snapshot.
- A later implementation slice can attach concrete mini-repos or generated test corpora to these fixtures.
