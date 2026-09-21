---
title: "A designator may carry source expression text, ungated"
doc_type: "follow_up"
lifecycle: "completed"
status: "fixed"
agent_action: "historical_reference_only"
updated: "2026-09-20"
---

# A Designator May Carry Source Expression Text, Ungated

## Classification

`bug`

## Source

[Plan 013](../plans/013_unresolved_mentions_from_the_callee_anchor.md) readiness
review, 2026-09-20, while checking what the designator field is defined to hold.

## Current Behavior

The Java frontend stores the whole invocation text as the designator of a
qualified call:

```zig
const designator = if (receiver != null) try builder.dupe(node.text(source)) else name;
```

([java.zig:1269](../../src/frontends/java.zig#L1269)). For
`config.load(user.password, 42)` the recorded designator is that entire
expression, arguments included. The same string is then handed to `evidenceOf`
([java.zig:1284](../../src/frontends/java.zig#L1284)), so the designator and the
evidence text are one value, not two.

A designator renders with no opt-in
([tools.zig:1073-1075](../../src/mcp/tools.zig#L1073-L1075)), while evidence text
is gated behind `--allow-evidence-text`
([tools.zig:907](../../src/mcp/tools.zig#L907)). Expression text copied verbatim
from a source file therefore reaches default MCP output.

Three documents state a boundary this crosses:

- `src/mcp/tools.zig`'s own header: "`SourceEvidence.text` is the only
  source-text field a snapshot carries"
  ([tools.zig:10-13](../../src/mcp/tools.zig#L10-L13)).
- The [capability matrix](../spec/capability_matrix.md): source text "off by
  default", and evidence text holding "a name or callee ... not a body".
- [Follow-up 005](005_mcp_source_derived_consent_boundary.md), whose resolution
  separates source text from source-derived graph values and lists designators
  among the latter.

Zig and Clojure are narrower cases, not the same defect: they store a callee
path ([zig.zig:802](../../src/frontends/zig.zig#L802)) and a symbol
([clojure.zig:448](../../src/frontends/clojure.zig#L448)), which are names,
although a Zig callee over a value (`self.bucket`) is a path rooted in a value.

Scale: on apache/dubbo at `df9c5e1` the graph holds 118,349 unresolved calls
([Plan 012 progress](../reports/012_java_semantic_quality_without_query_regression_progress.md)),
and Java qualified invocations are the dominant family. This is not a corner.

## Why Deferred

[Plan 013](../plans/013_unresolved_mentions_from_the_callee_anchor.md) rewrites
this exact field: D1 makes a designator a structured name, D10 feeds the written
form to the evidence explicitly, D11 states that default output then carries
names and qualifiers only, and Stage 5 corrects the three documents above.
Fixing it separately would be the same frontend rewrite performed twice.

This entry exists so the defect is recorded as current behavior instead of
living only inside a plan that has not been executed.

## Acceptance Direction

- A designator carries names, never expression text.
- No default MCP result carries text a source file wrote, beyond names.
- The `tools.zig` header, the capability matrix, and Follow-up 005's boundary
  wording state what is true once that holds.

## Required Tests

- An MCP test proving a qualified Java call's default rendering carries no
  receiver or argument text.
- A frontend test proving expression text reaches `SourceEvidence.text` only.

## Resolution

**Fixed** by [Plan 013](../plans/013_unresolved_mentions_from_the_callee_anchor.md)
Stages 1, 3 and 5, and recorded as a decision in
[ADR 010](../adr/010_designator_is_a_structured_name.md).

A designator is a name in parts: the identifier a producer read, plus the scope
the source wrote in front of it where the producer knows the prefix names one.
The Java frontend records the invocation's name and hands the invocation text to
`evidenceOf` explicitly, so the expression that used to be the designator is now
evidence and reaches a result only under `--allow-evidence-text`.

Measured on apache/dubbo at `df9c5e1`, the clone this entry cited for scale:
every one of the **118,471** unresolved Java call designators is a name, where
99,103 of them were invocation text
([Plan 013 Stage 2](../reports/013_unresolved_mentions_from_the_callee_anchor_progress.md#the-index-after-stage-1)).

The three documents that stated the boundary now state what is true: the
`src/mcp/tools.zig` header, the [capability matrix](../spec/capability_matrix.md)
source-text and source-derived rows, and
[docs/mcp/local_preview.md](../mcp/local_preview.md). Both required tests exist:
an MCP test proves a qualified Java call's default rendering carries no receiver
or argument text, and a frontend test proves the expression reaches
`SourceEvidence.text` only.

Java **type** designators are deliberately untouched: generic and qualified type
syntax such as `List<String>` is still recorded as written, which ADR 010 D2
records as a separate decision with its own evidence rather than a leftover.
