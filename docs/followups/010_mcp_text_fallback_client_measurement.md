---
title: "MCP text fallback client measurement"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-17"
---

# MCP Text Fallback Client Measurement

## Classification

`release_readiness`

## Source

Split from [Follow-up 009](009_mcp_progressive_discovery_and_response_budgets.md)
acceptance direction 7 at the closure of
[Plan 009](../plans/009_mcp_progressive_discovery_and_budgets.md); evidence in
the [Plan 009 progress log](../reports/009_mcp_progressive_discovery_and_budgets_progress.md#payload-copies).

## Current Behavior

Every successful `semidx-mcp` tool result carries `structuredContent` and a
text block holding the same object serialized as JSON, so the response on the
wire is about twice the structured size. Plan 009 bounded the structured size
(`max_response_bytes`, 32,000 bytes by default) but did not change the
fallback.

Measured so far: the maintained stdio client
(`tests/mcp_stdio_client.zig`) receives both copies. One Claude Code VS Code
extension session received one copy of a 28,095-byte structured result, inline,
with no warning and no spill to a file. No larger call and no other client was
measured.

## Deferral Reason

Plan 009's non-scope forbids changing the text fallback before client
measurements show which clients need it and which expose it to the model. One
client and one call are not that evidence, and the fallback is a protocol and
client compatibility question separate from semantic output budgeting.

## Acceptance Direction

- Measure, for the maintained stdio client and at least two real MCP clients,
  whether the model sees the text block, the structured content, or both, and
  at what result size each client warns, truncates, or spills to a file.
- Only then decide whether to keep, shorten, or make the text block
  configurable, per protocol version, without removing it for clients that
  lack structured-content support.
- Record the thresholds as observations; do not make client behavior a hard
  gate.

## Required Tests

- A smoke test for any changed fallback shape in both protocol eras.
- Gate observations of transcript bytes before and after the change.
