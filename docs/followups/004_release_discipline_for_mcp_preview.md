---
title: "Release discipline for MCP preview"
doc_type: "follow_up"
lifecycle: "active"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-16"
---

# Release Discipline For MCP Preview

## Classification

`release_readiness`

## Source

Accepted while Plan 004 was preparing the local MCP preview as the first semidx
surface intended for direct use by local AI clients.

See
[Plan 004 Stage 5](../plans/004_zig_frontend_and_mcp_preview.md#stage-5-dogfood-documentation-and-handoff)
and
[SPEC Requirements Still To Specify](../../SPEC.md#requirements-still-to-specify).

## Current Behavior

There is no release procedure yet. `SPEC.md` records packaging, distribution,
and long-running process mode as still unspecified. Plan 004 intentionally
delivers a local MCP preview without publishing a stable semantic contract.

## Why Deferred

Release discipline depends on the result of Plan 004 Stage 4 and Stage 5:
the MCP executable name, build step, smoke test, local configuration document,
and final review evidence should exist before a release process is frozen.

## Acceptance Direction

After Plan 004 is implemented, dogfooded, documented, and reviewed, add a small
release plan for the local CLI/MCP product.

Use separate version concepts:

- Product release tags version the semidx binary, CLI, MCP preview, packaging,
  and installation instructions.
- Semantic contract versions are separate and remain unpublished until `SPEC.md`
  admits and publishes them.

Recommended initial product milestones:

- `v0.1.0-preview.1`: local MCP preview usable by the maintainer and local
  agents, with no promise of a stable semantic contract.
- `v0.1.0`: first stable CLI/MCP product release.

The preview release should make one installed semidx binary usable against many
local repository roots through a `--root` argument. The indexed repository is
the user's local working copy, not the remote repository that supplied semidx.

## Required Decisions

- Tag naming and whether preview releases use SemVer prerelease tags.
- Which platforms and artifacts are published for the first preview.
- Whether the release is source-only, binary-only, or both.
- How grammar prerequisites are installed or bundled.
- Whether the binary exposes its own product version at runtime.
- Which commands form the release gate.
- How release notes describe experimental MCP without implying a stable
  semantic contract.

## Required Tests

- Build from a clean checkout at the candidate tag.
- Run parser-free core tests without grammar sources.
- Run the full test lane with pinned local grammar sources.
- Run full-output runtime smoke for `src` and repository-root dogfood.
- Run the MCP smoke added by Plan 004 Stage 4.
- Verify default MCP output does not include source text.
- Verify attribution, memory freshness, formatting, and whitespace gates.

## Resolution

Completed by
[Plan 005](../plans/005_mcp_preview_release_readiness.md) and its
[progress log](../reports/005_mcp_preview_release_readiness_progress.md).

Plan 005 established the preview product version, source-built release shape,
stable local launcher, local setup docs, capability matrix, release notes,
hosted-client source-data wording, and release gate for `v0.1.0-preview.1`.
The release candidate remains source-built and local-only; no Git tag, binary
artifact, package-manager publication, signing, or CI release automation was
created.

The completed release gate includes Zig 0.16.0 verification, parser-free core
tests, the full test lane, MCP tests, formatting, developer inspection output,
dogfood over a temporary copy of this repository, attribution, memory freshness,
and whitespace checks.
