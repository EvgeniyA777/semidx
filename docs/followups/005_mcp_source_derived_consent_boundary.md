---
title: "MCP source-derived consent boundary"
doc_type: "follow_up"
lifecycle: "active"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-16"
---

# MCP Source-Derived Consent Boundary

## Classification

`release_readiness`

## Source

Plan 004's final review accepted the local MCP preview, but kept one product
question out of the implementation: how to describe consent when a local MCP
client may forward semidx results to a hosted model.

See
[Plan 004 final review](../reports/004_zig_frontend_and_mcp_preview_progress.md#final-review),
[ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md), and
[ARCHITECTURE_CONSTITUTION.md §8](../../ARCHITECTURE_CONSTITUTION.md#8-local-operation-is-required).

## Current Behavior

`semidx-mcp` is a local stdio process. It scans the configured local root,
publishes an in-memory snapshot, and returns graph values to the client process
that launched it. The server does not contact a network service.

Source text is disabled by default. With no `--allow-evidence-text`, results may
still include graph values derived from the source tree: repository-relative
paths, entity names, unresolved designators, ranges, diagnostic messages,
resolution metadata, freshness, producers, and ids.

## Why Deferred

The implementation boundary is clear enough for the local preview: semidx itself
does not transmit data outside the local machine. The product boundary for MCP
clients is less clear, because some clients can forward tool results to hosted
models after the user configures the server.

That is not a code blocker for Plan 004, but it should be settled before a
preview release is promoted as an installable product.

## Acceptance Direction

Before `v0.1.0-preview.1`, document the consent boundary in the local MCP setup
path and release notes:

- distinguish source text from source-derived graph values;
- state that configuring a hosted MCP client may send returned graph values to
  that client's model or service;
- keep source text disabled by default and require `--allow-evidence-text` for
  recorded evidence text;
- name what data the opt-in enables and what it still does not enable;
- avoid implying that semidx can enforce a hosted client's onward transmission
  policy.

## Progress

Plan 005 Stage 3 added the consent wording to the local setup path: a "What
leaves your machine" paragraph next to the README configuration example and a
"Data Leaving The Server" section next to the reference's configuration example.
Both distinguish source text from source-derived graph values, name the values
that are always returned, state that a hosted client may forward them, describe
exactly what `--allow-evidence-text` adds, and say semidx cannot enforce the
client's onward transmission. The preview capability matrix repeats the boundary
in its MCP section.

Still open: whether release notes carry an explicit privacy section (Plan 005
Stage 5) and whether a data-level allowlist is needed.

## Required Decisions

- Whether the preview documentation needs a stronger warning next to hosted
  client examples.
- Whether release notes require an explicit privacy/consent section.
- Whether a future config should include a data-level allowlist beyond
  `--allow-evidence-text`.

## Required Tests

- Keep the default no-source-text MCP tests from Plan 004.
- If a data-level allowlist is added, test every default-off field and every
  opt-in field independently.

## Resolution

Completed by
[Plan 005](../plans/005_mcp_preview_release_readiness.md) and the
[`v0.1.0-preview.1` release notes](../releases/v0.1.0-preview.1.md).

The preview setup path, local MCP reference, capability matrix, and release
notes distinguish source text from source-derived graph values. They state that
semidx itself is local, that default MCP output excludes source text, that graph
values still go to the launching client, that a hosted client may forward those
values, and that semidx cannot enforce the client's onward transmission policy.

`--allow-evidence-text` remains the only implemented data-level opt-in. It is
documented as bounded to 400 bytes per claim and currently records names or
designators rather than source bodies. The Plan 005 dogfood gate verified that
default output does not include source text and that evidence-text opt-in stays
within the bound.

No broader data-level allowlist was added for this preview. If needed, that is a
future optional-outbound-data requirement rather than unresolved release
readiness for `v0.1.0-preview.1`.
