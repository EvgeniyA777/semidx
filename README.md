# semidx

semidx is an incrementally maintained semantic graph of a codebase that
provides exact program relationships as a foundation for search, AI context,
navigation, impact analysis, and future incremental analysis and compilation
tooling.

The semantic graph is the source of truth. Search, vector embeddings, RAG,
MCP, agent context, and navigation are consumers of that graph, not the
architectural center of the system. See
[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md) for the immutable
product identity, [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md) for
the reasoning, [SPEC.md](SPEC.md) and [CORE.md](CORE.md) for changing
requirements, and [CONFORMANCE.md](CONFORMANCE.md) for verification scenarios.

## License

Apache License 2.0. See [LICENSE](LICENSE).
