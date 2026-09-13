# semidx

**Status: design, not implementation.** There is no graph implementation, no
public surface, and no conformance evidence yet; this repository holds the
architecture an implementation will have to satisfy. Read every capability below
as intended behavior, not as measured behavior.

semidx is designed to be an incrementally maintained semantic graph of a
codebase that provides exact program relationships as a foundation for search,
AI context, navigation, impact analysis, and future incremental analysis and
compilation tooling.

The semantic graph is the source of truth. Search, vector embeddings, RAG, MCP,
agent context, and navigation are consumers of that graph, not the architectural
center of the system. Text-derived retrieval may discover candidates and render
located source; it never establishes a program relationship. See
[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md) for the product
identity it freezes (ratified 2026-09-13), [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md) for
the reasoning, [SPEC.md](SPEC.md) and [CORE.md](CORE.md) for changing
requirements, and [CONFORMANCE.md](CONFORMANCE.md) for verification scenarios.

## License

Apache License 2.0. See [LICENSE](LICENSE).
