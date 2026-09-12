# semidx

semidx is an incrementally maintained semantic graph of a codebase that
provides exact program relationships as a foundation for search, AI context,
navigation, impact analysis, and future incremental analysis and compilation
tooling.

The semantic graph is the source of truth. Search, vector embeddings, RAG,
MCP, agent context, and navigation are consumers of that graph, not the
architectural center of the system. See
[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md) for the full
definition, the semantic layers (L1 structural, L2 program graph, L3
fine-grained dependencies), and the architectural invariants that any
implementation must preserve.

## License

Apache License 2.0. See [LICENSE](LICENSE).
