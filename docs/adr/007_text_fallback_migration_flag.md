---
title: "Keep the MCP text fallback and add a diagnostic probe flag"
doc_type: "adr"
lifecycle: "proposed"
status: "proposed"
agent_action: "reference_for_context"
updated: "2026-09-18"
---

# 007: Keep The MCP Text Fallback And Add A Diagnostic Probe Flag

## Feature Or Dependency

Every successful `semidx-mcp` tool result carries its structured object twice:
once as `structuredContent`, and once as that same object serialized into
`content[0].text` (`src/mcp/root.zig`, the result writer). The text copy is
JSON-escaped, so a result is more than twice the structured payload.
[The local preview reference](../mcp/local_preview.md) records a default
response reaching about 65 KB on the wire against a 32000-byte structured
budget.

[Follow-up 010](../followups/010_mcp_text_fallback_client_measurement.md)
deferred the question until real MCP clients could be measured, and proposed a
staged measurement program to do it. This record closes it on protocol and
ecosystem evidence instead.

### Protocol history

- `2025-03-26` has no `structuredContent` and no `outputSchema`. A tool result
  was `content` blocks only, so a server with structured data had no channel
  other than a JSON text block. Serializing JSON into text was not a fallback
  then; it was the only mechanism.
- `2025-06-18` introduced `structuredContent` and `outputSchema`, together with:
  "For backwards compatibility, a tool that returns structured content SHOULD
  also return the serialized JSON in a TextContent block." Every client in
  existence at that moment read only `content`.
- `2026-07-28` carries that sentence verbatim and unchanged, while also
  documenting a tool whose `content[0].text` is a human-readable summary rather
  than a serialization. The specification is internally inconsistent on this
  point.

### Ecosystem evidence

The measurement Follow-up 010 proposed has already been performed publicly, and
its results are stronger than a two-client local observation would have been.

- Client behavior differs and is documented: Cursor prefers `content` as model
  input, VS Code favors `structuredContent`, and **most other clients ignore
  `structuredContent` entirely**
  ([SEP-1624](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1624)).
- The official Python SDK treats `content` as required and rejects a
  structured-only result, so the dominant server SDK cannot emit one even though
  the specification permits it
  ([python-sdk#1378](https://github.com/modelcontextprotocol/python-sdk/issues/1378),
  closed as not planned).
- The Go SDK serializes `structuredContent` into `content` for the same
  compatibility reason.
- At least one client library repairs the omission from the other side: the
  Vercel AI SDK adds a serialized text block itself when a server returns
  `structuredContent` without one
  ([AI SDK MCP tools](https://ai-sdk.dev/docs/ai-sdk-core/mcp-tools)).

### Attempts to change the guidance

- [SEP-1624](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1624)
  proposed a dual-purpose reading: `content` as model-oriented output optimized
  for readability and token efficiency, `structuredContent` as machine-oriented
  output for programmatic use and schema validation, with a **semantic
  equivalence** requirement — when both appear they must carry the same
  information in different presentation. It explicitly left the token-duplication
  tension unresolved.
- [SEP-2200](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/2200)
  proposed exactly the change this project was considering: `content` as
  model-optimized text rather than mandatory JSON duplication. Core Maintainers
  **declined it on 2026-05-25**, deferring in favor of a deeper fix — allowing
  polymorphic results (structured *or* unstructured) instead of forcing both
  fields at once.

The normative sentence therefore stands, a proposal to relax it was rejected
four months ago, and the ecosystem's dominant implementations duplicate.

## Decision

**Keep the current duplicating behavior as the default and only recommended
production value.** `content[0].text` continues to carry the serialized
structured object, byte-identical to today.

Add one startup flag, for diagnosis rather than production:

```
--text-fallback=full|none
```

`full` is the default and reproduces current behavior exactly.

`none` omits the text block, leaving `structuredContent` alone. It exists to
answer one question about one host: run semidx under `none` in a given client
and observe whether answers still arrive. If they do, that client reads
`structuredContent`. If they do not, it does not. This is the measurement
Follow-up 010 wanted, obtained for the cost of omitting a block.

`none` is documented as a diagnostic probe and **must not be presented as a
supported production configuration.** Given that most clients ignore
`structuredContent`, running `none` unknowingly would make semidx silently
useless.

The value is chosen once at process start. It is never a tool argument:
selecting it would fall to the model, which knows less about the host client
than the person configuring the server.

`isError` results are unaffected under both values. A failure already renders a
plain message rather than a serialized object.

**A `summary` value is explicitly rejected for now**, and this record's expiry
condition is tied to that. Revisit when either holds:

- the polymorphic-result work that displaced SEP-2200 lands in a protocol era
  `semidx-mcp` serves, giving a sanctioned way to return one representation; or
- `none` probing shows that every client semidx is actually used with reads
  `structuredContent`, making the text copy provably dead weight in practice.

Until one of those is recorded, the duplication is accepted as the cost of
working everywhere.

## Rationale

The duplication is real and measurable, and the structured budget from
[Plan 009](../plans/009_mcp_progressive_discovery_and_budgets.md) bounds only
half of what goes on the wire. That was the motivation to change it.

The ecosystem evidence inverts the conclusion. `content` is not a legacy channel
being kept alive out of politeness; in most clients it is **the only channel the
model sees**. Shortening or dropping it optimizes a cost that is invisible in
those clients while risking the answer itself.

A `summary` value was the attractive option and is what this project initially
chose. Two findings removed it:

- SEP-1624's semantic-equivalence requirement means a summary may not be a
  teaser. It must carry the same information in a cheaper presentation. For
  semidx that is a second complete renderer for every tool, held semantically
  equivalent to the structured one forever — not the small change it first
  appeared to be, and a third rendering surface alongside the existing
  `compact` and `full` detail levels.
- SEP-2200 asked for precisely this permission and was declined. Building it now
  means diverging from standing normative guidance in a direction the
  maintainers deliberately postponed, on a preview product whose actual
  bottleneck is language coverage rather than transport efficiency.

Keeping `full` costs bytes on a local pipe. Bytes on a local stdio pipe are not
a scarce resource. What is scarce is model context, and how much of it a result
consumes is decided by the client's forwarding choice, which semidx cannot
control and which differs per client by documented fact.

The `none` probe is kept because it converts the remaining open question into an
observation at near-zero cost, and because it is the only variant that needs no
renderer and no semantic-equivalence obligation.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Unaffected. This changes how one
   consumer serializes an answer, never what the answer is.
2. **Nodes as entities, not chunks.** Unaffected. No node, entity, or projection
   boundary changes.
3. **Facts, unresolved, and approximate distinct and attributable.** Preserved.
   Both values carry the complete structured object; `none` removes a duplicate,
   never a distinction. This is the clause that rejected `summary` on the terms
   above: a condensed rendering that dropped resolution categories or made a
   bounded list look complete would violate it.
4. **Stable identity across edits.** Not applicable. Identity is established
   during ingestion and analysis; result serialization neither reads nor produces
   identity evidence.
5. **Incremental maintenance and consistent observation.** Unaffected. The flag
   is read at startup and does not touch snapshots, revisions, or refresh.
6. **Language-specific meaning preserved in the common core.** Not applicable.
   No frontend, extension vocabulary, or core kind is involved.
7. **Consumers do not define the model.** Upheld, and this is the clause most at
   risk here. A protocol-era compatibility clause was shaping payload size;
   confining that question to a startup switch keeps it out of graph semantics.
   No tool result shape may become the reason a graph answer changes.
8. **Local operation without mandatory source transmission.** Unaffected.
   `--allow-evidence-text` continues to own whether source text may appear;
   `none` reduces what leaves the process and never increases it.

## Consequences

- `mcp.Options` gains one field; `src/mcp/main.zig` gains one branch and one
  usage line, following the existing `--allow-evidence-text` shape.
- The result writer branches once. `full` must remain byte-identical to current
  output, so the change is provably inert by default.
- No new renderer is written and no semantic-equivalence obligation is taken on.
- The behavior matrix grows to two values across two protocol eras, which the
  existing smoke tests already parameterize.
- [The local preview reference](../mcp/local_preview.md) documents `none` as a
  diagnostic probe with an explicit warning that most clients ignore
  `structuredContent`, and records the duplication as accepted cost rather than
  an open question.
- [Follow-up 010](../followups/010_mcp_text_fallback_client_measurement.md)
  closes against this record. Its client-measurement stages are dropped as
  redundant: the ecosystem published stronger evidence than a local two-client
  observation could produce.
- [The capability matrix](../spec/capability_matrix.md) states which result
  copies a client can rely on under each value.
- The project carries a known, quantified inefficiency by choice. That is
  recorded here so a later reader does not rediscover it as a defect.

## Verification Evidence And Planned Checks

Before this record moves to `accepted`:

- `./scripts/check-zig-version.sh`
- `zig fmt --check build.zig src tests`
- `zig build test-mcp --summary all`
- `zig build preview-gate --summary all`

Focused checks:

- `full` output is byte-identical to the pre-change result for a fixed request
  set in both `2026-07-28` and `2025-06-18`.
- `none` returns a valid `CallToolResult` with no text content block and an
  unchanged `structuredContent`, in both eras.
- An `isError` result is identical under both values.

Evidence for the expiry condition is operational: any `none` probe run, the
client it was run against, and its outcome are recorded in `MEMORY.md` until one
of the two resolution branches is taken.
