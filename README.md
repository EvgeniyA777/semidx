# semidx

**Status: first vertical slice.** A small in-memory semantic graph exists and is
tested against Java, Clojure, and Zig source, and an experimental local MCP
server can query it. There is no persistence, no public contract, no published
language coverage, and no conformance suite. Read every capability below as
intended behavior, not as measured behavior.

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

## Running it

The slice needs [Zig](https://ziglang.org) 0.16 or newer. Its shared core needs
nothing else:

```sh
zig build test-core
```

The language frontends additionally need pinned tree-sitter grammar sources and
a local tree-sitter runtime providing `tree_sitter/api.h` and
`libtree-sitter.a`. Nothing is fetched during a build or an index run:

```sh
./scripts/setup-tree-sitter-grammars.sh
zig build test
zig build run -- fixtures/vertical-slice/java/Greeter.java
```

`zig build` reports precisely what is missing and how to point it elsewhere
(`-Dgrammars-dir=`, `-Dtree-sitter-prefix=`). The `run` command is a developer
inspection tool, not a public interface.

## Using it from an MCP client

`semidx-mcp` indexes a local directory and answers graph queries over MCP stdio.
It is an experimental preview with no stable interface, and it returns paths and
ranges rather than source text:

```sh
zig build
zig-out/bin/semidx-mcp --root /path/to/repository
```

See [docs/mcp/local_preview.md](docs/mcp/local_preview.md) for client
configuration, tools, result fields, and limits.

## License

Apache License 2.0. See [LICENSE](LICENSE).
