---
name: semidx-zig-implementation
description: "Work on semidx's Zig implementation, build, tests, or frontend/core boundaries. Use for Zig source changes, build.zig changes, and verification planning tied to the current Zig vertical slice; do not use for generic Zig syntax help."
---

# semidx Zig Implementation

Use this skill when modifying or reviewing the Zig implementation in `src/`,
`tests/`, `build.zig`, or implementation-facing fixtures.

Target Zig version: 0.16.0 exactly. All source, build scripts, examples, tests,
and agent-generated changes must target and be verified against Zig 0.16.0. Do
not assume APIs from earlier or later Zig releases remain valid.

## Read First

- Read `MEMORY.md` for current implementation reality before changing behavior.
- Read ADR 001 and ADR 002 when a change touches implementation language,
  build shape, parser integration, grammar sources, or tree-sitter linkage.
- Use `semidx-code-exploration` before non-trivial source navigation,
  caller/test discovery, or blast-radius assessment.
- Use `semidx-test-design` when selecting verification beyond an obvious narrow
  probe.

## Local Boundaries

- `src/core/` is pure Zig shared core. It must not depend on parser inputs,
  tree-sitter headers, grammar sources, frontend-specific syntax, or C ABI.
- `src/frontend/tree_sitter.zig` is the only layer that talks to tree-sitter
  through the C ABI.
- `src/frontends/{java,clojure}.zig` translate language parse evidence into
  shared-core assertions and language-extension payloads; they do not define the
  shared core.
- `src/root.zig` assembles indexing behavior. `src/main.zig` is a
  developer-only inspection command; its printed output is not a public
  contract.

## Model Invariants

- Entity ids are allocated by the graph and are not derived from source ranges,
  frontend ids, or paths. Ranges are source evidence.
- `Graph.addEntity` allocates an entity but does not assert that it exists.
  Producers record existence and relationship claims with provenance.
- Every assertion keeps its producer and `Resolution`; do not collapse facts,
  unresolved assertions, and approximate assertions.
- `Resolution` and `Freshness` are separate axes. Current queries must not
  silently present stale claims as current, and failed analysis must not invent
  confirmed absence.
- Calls specialize references. An all-references query includes calls without
  double-counting one occurrence.
- `CONTAINS` is direct containment; `DEFINES` is direct definition
  introduction and its target must be a `definition`.

## Core And Frontend Changes

- Do not add or widen a shared-core entity or relationship kind without updating
  the admission evidence owned by `CORE.md` and the lifecycle requirements in
  `SPEC.md`.
- Keep language-specific constructs and meanings in `ExtensionPayload` unless
  shared-core admission has been completed.
- Treat Java and Clojure fixture coverage as current evidence for the slice, not
  as a supported-language roster.
- Keep source-derived outbound behavior local by default; no Zig build, index,
  or verification step should require network access.

## Verification

Choose the smallest meaningful probe first, then broaden based on risk:

- Toolchain pin:
  `./scripts/check-zig-version.sh`.
- Core-only model, graph, freshness, snapshot, or reconcile change:
  `zig build test-core --summary all`.
- Proof that core stayed parser-independent:
  `zig build test-core -Dgrammars-dir=/nonexistent --summary all`.
- Frontend, tree-sitter adapter, fixture, or cross-module behavior:
  `zig build test --summary all`.
- Developer inspection sanity check when output helps diagnosis:
  `zig build run -- <files>`.
- Formatting:
  `zig fmt --check build.zig src tests`.

If tree-sitter prerequisites are unavailable, say which verification was skipped
instead of implying the full lane passed.
