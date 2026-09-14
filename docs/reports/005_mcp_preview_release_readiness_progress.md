---
title: "MCP preview release readiness progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 005: MCP Preview Release Readiness Progress

Companion log for
[docs/plans/005_mcp_preview_release_readiness.md](../plans/005_mcp_preview_release_readiness.md).

## Current Status

Execution started on 2026-09-14. Stages 1–2 are complete; Stage 3 is next.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Product version and preview identity | Completed (`db7caa6`) | `0.1.0-preview.1` is defined once in `build.zig.zon` and reported by `semidx-mcp --version`, `serverInfo.version`, and `semidx_health.product_version`; `semantic_contract_version` stays `null`. |
| Stage 2: Install and local agent configuration | Completed (`7ad042a`) | README gives a four-step source-built path to a registered MCP server; a clean clone followed it to a first successful tool call. |
| Stage 3: Capability matrix and consent boundary | Pending | |
| Stage 3.5: Refresh failure recovery | Pending | |
| Stage 4: Dogfood proofs and release gate | Pending | |
| Stage 5: Preview release candidate handoff | Pending | |

## Plan Readiness Gate

Checked by the implementing agent before Stage 1 on 2026-09-14 against the
current plan text (commit `0e0fbc6`). Scope, non-scope, stage outputs,
verification, and stop conditions are explicit; no hard fail. Two points are
left to execution and are decided in the stage that meets them:

- how Stage 4 induces a refresh failure on this repository, given that a
  mid-reconciliation failure can only be injected in a test;
- what "clean worktree" means for the Stage 5 release gate, given that pinned
  grammar sources are ignored by git and not part of a checkout.

## Environment

- The semidx MCP server failed to connect (connection timeout), so its tools
  were unavailable. Per
  [tooling policy](../agent-policy/tooling.md#mcp-failure-protocol), code was
  located by targeted direct reads of the files the plan names.
- Toolchain: Zig 0.16.0, tree-sitter runtime from `/opt/homebrew`.

## Stage 1: Product Version And Preview Identity

Changed files: `build.zig.zon`, `build.zig`, `src/mcp/protocol.zig`,
`src/mcp/tools.zig`, `src/mcp/root.zig`, `src/mcp/main.zig`,
`tests/mcp_smoke_test.zig`, `docs/mcp/local_preview.md`, `MEMORY.md`.

Decisions taken inside the plan's boundary:

- **The one implementation-owned place is `build.zig.zon`'s `version`.**
  `build.zig` imports the manifest (verified to work in Zig 0.16 with a probe
  before use) and passes the version to the MCP module as a build option;
  `protocol.product_version` is the only code constant. The package manifest
  and the product therefore cannot disagree.
- `--version` prints `semidx-mcp 0.1.0-preview.1` to stdout and exits 0 without
  indexing. stdout carries protocol messages only while serving; a version
  printed where scripts read it does not break that. `--help` keeps stderr and
  gained only the `--version` line.
- `semidx_health` gains a top-level `product_version` beside the existing
  `server` identity, so the version is visible without knowing the identity
  object's shape.
- The smoke test pins the expected release literal (`0.1.0-preview.1`) in
  addition to comparing against the manifest value: the definition stays in one
  place, and the gate states which release this tree prepares.
- `semidx-dev` did not gain version output: it shares no version plumbing, and
  the plan limits it to that case.

Risk matrix:

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| One version, reported consistently (plan Stage 1) | Binary, identity, and health drift apart | Integration + runtime smoke | Manifest to build option to `protocol.product_version` | Manifest version changed | `the product version is reported in server identity and health ...`; smoke `--version` test; mutation below |
| Product version is not a contract version (plan decision) | A client reads the preview version as a semantic contract | Integration | `beginStructured` | Health result checked for `semantic_contract_version: null` | same tests |
| `--version` cannot pollute a serving stdout | Version text reaches a protocol stream | Runtime smoke | `main.zig` argument handling | `--version` runs without serving; stdio smoke unchanged | smoke tests |

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-mcp --summary all` | Pass, 16/16 |
| `zig build test --summary all` | Pass, 181/181 (179 before) |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass, 87/87 |
| `zig-out/bin/semidx-mcp --version` | Exit 0; stdout `semidx-mcp 0.1.0-preview.1`; stderr empty |
| `zig-out/bin/semidx-mcp --help` | Exit 0; stdout empty; usage on stderr with the added `--version` line |
| Mutation: manifest version set to `0.1.0-preview.2` | Smoke `--version` test fails; restored |

No document describes the semantic contract as published or stable: the local
preview reference states the product version is not a semantic contract
version.

## Stage 2: Install And Local Agent Configuration

Changed files: `README.md`, `docs/mcp/local_preview.md` (commit `7ad042a`);
this log and follow-up 007 in the next commit.

Decisions taken inside the plan's boundary:

- The README carries the whole first-call path in four numbered steps and one
  configuration example; `docs/mcp/local_preview.md` keeps exact prerequisites,
  options, tools, and fields, and gains a short "First Calls" sequence that
  follows the adoption strategy's agent habit loop.
- Runtime installation is stated only as far as it was verified: `zig build`
  searches `/opt/homebrew`, `/usr/local`, and `/usr` (read from `build.zig`), and
  Homebrew's `tree-sitter` 0.26.3 provides both required files (checked with
  `brew list tree-sitter`). No Linux package name is claimed.
- The configuration example stays in the command-and-arguments `mcpServers`
  shape already used by the reference; no separate sample file was needed.

Clean-clone proof (the DoD's fresh-agent check), run in a scratch directory:

| Step | Command | Result |
| --- | --- | --- |
| Clone | `git clone /path/to/semidx semidx` | HEAD `7ad042a` |
| Grammars | `./scripts/setup-tree-sitter-grammars.sh` | Exit 0 in 12 s (network); pinned refs for Java, Clojure, Zig, TypeScript; Elixir at `main` |
| Build | `zig build` | Exit 0 in 11 s; stderr empty |
| Version | `zig-out/bin/semidx-mcp --version` | `semidx-mcp 0.1.0-preview.1` |
| First call | A client script reading the README's JSON example literally, with the placeholder paths replaced, sending `semidx_health` for another local working copy | Response in 346 ms from process start: `isError: false`, 54 units (51 current), `product_version` `0.1.0-preview.1`; exit 0, no trailing stdout, stderr only startup and exit lines |

The clone took the Stage 1 and Stage 2 commits, so the proof covers the
documentation as committed rather than the working tree.

Finding filed: the setup script also clones `tree-sitter-typescript` and an
unpinned `tree-sitter-elixir` (`main`), neither compiled by `build.zig`. The
build stays reproducible; the setup step does not. Tracked as
[follow-up 007](../followups/007_grammar_setup_fetches_unused_unpinned_sources.md).

Verification:

| Command | Result |
| --- | --- |
| Clean-clone proof above | Pass |
| `./scripts/check-agent-attribution.sh --all` | Pass (exit 0) |
| `git diff --check` | Pass |

No code changed in Stage 2.
