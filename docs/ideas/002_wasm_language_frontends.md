---
title: "WASM-Based Modular Language Frontends"
doc_type: "idea"
lifecycle: "concept"
status: "proposed"
agent_action: "reference_for_context"
updated: "2026-09-19"
---

# 002: WASM-Based Modular Language Frontends

## Context

Currently, `semidx` is compiled as a statically linked monolithic binary. Tree-sitter grammars (which consist of generated C code) and the language frontends (`src/frontends/*.zig`) are compiled directly into the core executable. 

As the project enters the adoption track and aims to support dozens of languages, this monolithic approach presents scaling challenges:
- **Binary Bloat:** Compiling C parsers for every supported language drastically increases the binary size for all users, even if they only need a subset of languages (e.g., a Python developer downloading Java and Zig parsers).
- **Host Stability:** A bug or segmentation fault in a single C-based parser can crash the entire `semidx-mcp` host process, violating the reliability expected from a background MCP server.
- **Distribution Matrix:** Shipping pre-compiled dynamic libraries (`.so`, `.dll`) for all combinations of operating systems, CPU architectures, and languages creates a "Matrix of Doom" for CI/CD and release management.

## Proposal

Transition language frontends from statically linked modules to dynamically loaded **WebAssembly (WASM)** plugins.

In this architecture:
- The `src/core` remains the language-agnostic orchestrator and semantic graph authority.
- `tree-sitter` grammars and their corresponding language-specific frontend logic are compiled into individual `.wasm` modules.
- `semidx` embeds a WASM runtime and loads only the necessary `.wasm` language frontends at runtime, based on the codebase's contents.

## Why WebAssembly over Dynamic Libraries?

While dynamic libraries are the traditional approach for plugin architectures, WASM is highly preferable for `semidx` due to the following architectural alignment:

1. **Platform Independence (Write Once, Run Anywhere):** A single `python-frontend.wasm` file works identically across macOS, Linux, and Windows on both ARM and x86 architectures. This completely solves the distribution matrix problem.
2. **Fault Isolation:** WASM executes in a strict sandbox. If a language parser panics, hits an infinite loop, or exhausts memory, the WASM runtime traps the error. The core `semidx` graph and MCP server remain stable, gracefully degrading the affected file's state to an `analysis_failed` diagnostic.
3. **Security (Aligned with Constitution §8):** The constitution mandates strict local operation and data privacy. Using WASI capabilities, `semidx` can completely deny network access to WASM plugins, technically guaranteeing that a community-provided parser cannot exfiltrate source code.
4. **Ecosystem Synergy:** Zig has first-class, built-in support for compiling to WASM and embedding WASM runtimes. Furthermore, `tree-sitter` officially supports compiling its grammars to WebAssembly out of the box.

## Impact

- **Core Shrinkage:** The base `semidx` binary becomes exceptionally lightweight, containing only the graph logic and the WASM runtime.
- **On-Demand Loading:** Users can fetch only the language capability packs they need on the fly.
- **Community Extensibility:** Developers can build, test, and distribute custom language frontends safely without modifying the core `semidx` repository, accelerating language support coverage.
