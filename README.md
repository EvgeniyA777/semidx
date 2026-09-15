# semidx

**Status: first vertical slice.** A small in-memory semantic graph exists and is
tested against Java, Clojure, and Zig source, and an experimental local MCP
server can query it. There is no persistence, no public contract, no published
language coverage, and no conformance suite. What each language frontend
records, and what it leaves unresolved or unsupported, is stated in the
[preview capability matrix](docs/spec/capability_matrix.md). Read every
capability below as intended behavior, not as measured behavior.

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

`semidx-mcp` (preview `0.1.0-preview.1`) indexes a local directory and answers
graph queries over MCP stdio. It is an experimental preview with no stable
interface and no published semantic contract, and it returns paths and ranges
rather than source text. It is built from source; there are no binary packages.

1. Install [Zig](https://ziglang.org) 0.16 or newer, `git`, and a tree-sitter
   runtime that provides `tree_sitter/api.h` and `libtree-sitter.a` (on macOS,
   `brew install tree-sitter`; elsewhere, install it under a prefix and pass
   `-Dtree-sitter-prefix=<prefix>` to `zig build`).
2. From this repository, fetch the pinned grammar sources once (needs network):
   `./scripts/setup-tree-sitter-grammars.sh`
3. Build: `zig build`. Check it: `zig-out/bin/semidx-mcp --version`.
4. Register the binary with your MCP client, using absolute paths:

   ```json
   {
     "mcpServers": {
       "semidx": {
         "type": "stdio",
         "command": "/path/to/semidx/scripts/semidx-mcp.sh",
         "args": ["--root", "/path/to/your/repository"]
       }
     }
   }
   ```

`--root` is a local working copy on your machine — the repository you want your
agent to work on, not this one. One built binary serves any number of
repositories: register it once per repository with a different `--root`. The
launcher also supports `SEMIDX_ROOT=/path/to/repository` or, when the MCP client
starts servers from inside the repository, automatic Git-root detection.

**What leaves your machine.** semidx is local and opens no network connection,
and by default returns no source text. Its results still contain values derived
from your source — file paths, entity names, callee names, ranges, and
diagnostic messages — and a client backed by a hosted model may send them to
its service. semidx cannot enforce what the client does with them.
`--allow-evidence-text` adds bounded recorded evidence text per claim; it never
returns file contents.

See [docs/mcp/local_preview.md](docs/mcp/local_preview.md) for the first calls
to make, tools, result fields, source-text rules, and limits, and the
[preview capability matrix](docs/spec/capability_matrix.md) for what each
language covers.

## License

Apache License 2.0. See [LICENSE](LICENSE).
