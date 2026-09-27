---
title: "Add Jev as an optional outbound ranking projection"
doc_type: "adr"
lifecycle: "active"
status: "proposed"
agent_action: "reference_for_context"
updated: "2026-09-26"
---

# 013: Add Jev As An Optional Outbound Ranking Projection

## Feature Or Dependency

The local MCP preview can return an exact graph neighborhood, but it does not
judge which members of that neighborhood are most useful for a user's current
question. A bounded decision model can improve the order in which an agent sees
those candidates without changing what the graph says.

This record proposes one optional outbound integration with TypeSafe Jev. Jev
accepts structured state and typed questions at
`POST https://api.typesafe.ai/v1/systemone` and returns typed probabilistic
answers. The current API exposes `Noul`, `Choice`, and `Score`; the first slice
uses one `Noul` relevance question per candidate in a single request. See the
[TypeSafe API reference](https://docs.typesafe.ai/api) and
[model reference](https://docs.typesafe.ai/models).

The implementation plan is
[015: Optional Jev Ranking Projection](../plans/015_optional_jev_ranking_projection.md).

## Decision

### D1: Jev Is A Consumer-Side Projection

Jev does not enter source discovery, a language frontend, reconciliation,
identity correspondence, dependency invalidation, graph publication, or any
other write path. It reads a bounded candidate set from one immutable published
snapshot and returns ranking decisions. No Jev answer creates or modifies an
entity, relationship, assertion, resolution category, producer, freshness
value, or diagnostic.

The first surface is a separate experimental MCP tool,
`semidx_rank_context`. `semidx_context` remains the exact graph projection it is
today. The new tool returns every selected graph candidate and may only change
their order.

### D2: Outbound Operation Requires Complete Startup Consent

Jev ranking is disabled by default. The tool is not advertised and no outbound
client is constructed unless all of these startup inputs are present and valid:

```text
--enable-jev-ranking
--jev-endpoint https://api.typesafe.ai/v1/systemone
--jev-model jev-1.13.0
--jev-send query-text,graph-metadata
TYPESAFE_API_KEY=<secret environment value>
```

The endpoint and version above describe the current official service on
2026-09-26; they are examples, not compiled defaults. The operator must name an
HTTPS endpoint and a versioned model id explicitly. Moving aliases such as
`jev-latest` are rejected in the first slice because calibrated thresholds and
evaluation evidence must stay attributable to one model version.

The only accepted first-slice data categories are the complete pair
`query-text,graph-metadata`. Missing, partial, duplicated, or unknown consent
values fail startup before indexing or serving. The API key is read only from
the environment, never from an argument, result, diagnostic, or log.

The configured endpoint is the consented destination. Redirects are rejected;
the authorization header and source-derived data are never forwarded to a
second origin. Startup and per-call logs may record endpoint origin, model,
category names, byte counts, timing, and status class, but never the key, query,
entity names, paths, or response body.

### D3: The First Outbound Data Shape Is Closed And Minimal

`query-text` contains the tool caller's query exactly as supplied.

`graph-metadata` contains bounded candidate cards derived from the same current
snapshot. A card may contain:

- a request-local ordinal such as `candidate_0`;
- language, entity role, name, and container path;
- repository-relative source-unit path;
- the relationship kind and direction by which traversal reached it;
- the recorded resolution category, freshness, producer name, and diagnostic
  categories relevant to the candidate.

It excludes the absolute repository root, process-local entity and source-unit
ids, byte offsets, source ranges, evidence text, source bodies, snippets, VCS
metadata, environment values, and filesystem content read outside the
snapshot. `--allow-evidence-text` affects existing MCP rendering only and must
never widen the Jev payload. Adding an outbound category or field family
requires a revised decision and explicit consent spelling before implementation.

The serialized state is bounded independently of the MCP response budget. The
initial request-state ceiling is 32,000 bytes. Whole candidate cards are
appended until the next card would exceed the ceiling; truncation and counts are
reported locally. The question rubric is fixed in code and treats source-derived
state as data, never as instructions.

The first slice ranks 20 candidates by default and accepts at most 32. The full
serialized HTTP request is capped at 64 KiB and the provider response at 256
KiB. A query that cannot fit in the state ceiling is rejected locally without
truncation and without an outbound attempt.

### D4: The Client Owns A Narrow Ranking Contract

The MCP projection owns a small provider-neutral contract:

```text
rank(query, candidate_cards) -> per-candidate relevance probability
                               + provider/model provenance
```

The TypeSafe HTTP client implements that contract. Tests use a deterministic
fake implementation. Vendor request fields, authentication, status codes,
retry behavior, and response parsing do not leak into graph or MCP candidate
selection code.

The Jev adapter sends one shared structured state and one `Noul` question per
candidate. It accepts a response only when every expected question id is
present exactly once, no unexpected question id is present, every answer is a
`Noul`, every value is finite and in `[0, 1]`, and the response model equals the
versioned model requested. Candidates are sorted by descending probability with
original graph order as the deterministic tie break. No candidate is removed
by a model threshold in the first slice.

### D5: Failure Is Visible And Local Behavior Survives

Authentication failure, timeout, rate limiting, overload, malformed responses,
or other provider failure never changes the graph and never affects existing
tools. `semidx_rank_context` returns the complete bounded candidate set in its
original deterministic order with `ranking.status = "unavailable"` and a
sanitized diagnostic. It does not silently present fallback order as a Jev
decision.

The adapter has one bounded overall deadline. It may retry only the official
retryable `429` and `529` responses, at most once, only when the retry delay fits
inside that deadline. It never retries authentication or validation failures.
The exact initial deadline is settled and fixture-tested in Plan 015 Stage 0;
changing it later is runtime policy, not a graph-semantic decision.

### D6: Ranking Provenance Is Not Graph Provenance

The result identifies itself as an `approximate_projection` and records the
provider, requested model, response model, destination origin, consented data
categories, provider-reported input/output token usage, probability per
candidate, truncation, and fallback status. These fields describe a consumer
decision. They must not reuse graph `resolution` or `producer` fields in a way
that makes a ranking look like a graph assertion. Dollar cost is not a runtime
contract because provider pricing can change; dated evaluations compute it from
recorded token usage and the then-current official price.

## Rationale

The graph is good at producing a trustworthy candidate set; Jev is shaped for a
narrow judgment over that set. Keeping those jobs separate makes the useful
failure mode cheap: if Jev is absent or wrong, semidx still returns the same
entities and relationships and merely loses a proposed ordering.

A separate tool is safer than a `ranking=jev` option on `semidx_context`. It
keeps an exact existing tool free of network, credentials, vendor latency, and
probabilistic fallback semantics. It also makes tool discovery an honest
capability report: a process that did not receive outbound consent advertises no
outbound tool.

The provider seam is justified immediately rather than speculatively. Tests
must prove consent and ranking without a secret or network, and the external
model and endpoint are expected to change independently of MCP projection
policy.

Requiring explicit endpoint, model, and data categories is intentionally more
verbose than using SDK defaults. Constitution §8 requires consent for both
destination and data. A moving alias would also make evaluation and regression
evidence drift without a repository change.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. The graph alone supplies
   candidates and semantic claims; Jev only orders a consumer projection.
2. **Nodes as entities, not chunks.** Preserved. Candidate cards describe graph
   entities. They do not become nodes, chunks, or graph records.
3. **Facts, unresolved, and approximate stay distinct.** Preserved. Ranking is
   labelled `approximate_projection`, remains outside graph assertions, and
   carries separate provider/model provenance.
4. **Stable semantic identity.** Preserved. Jev neither selects nor establishes
   identity correspondence, and process-local ids are not sent.
5. **Incrementality and consistent observation.** Preserved. Every candidate
   set comes from one immutable snapshot; provider latency cannot expose a
   partially updated graph.
6. **Language frontends preserve meaning.** Preserved. No frontend, core kind,
   extension label, or language mapping changes. Recorded language-specific
   metadata is rendered, not reinterpreted.
7. **Consumers do not define the model.** Preserved. Jev and MCP remain
   consumers. A decision cannot create a relationship or alter graph meaning.
8. **Local operation without mandatory source-data transmission.** Preserved.
   All existing local paths work unchanged and without network. Outbound use is
   disabled by default and requires explicit destination and data consent.

## Consequences

- The MCP preview gains an optional runtime network path but no build-time or
  indexing dependency on a service.
- The project must implement HTTP and JSON handling in Zig; no TypeSafe SDK or
  additional language runtime enters the repository.
- `tools/list` becomes configuration-sensitive while remaining fixed for one
  server process. Existing tools and their shapes remain unchanged.
- Tests and required gates remain offline and credential-free. A separate
  opt-in live smoke provides interoperability evidence when a credential is
  available.
- Repository-relative paths and entity names are source-derived data. Enabling
  `graph-metadata` explicitly consents to sending them to the named endpoint.
- Jev errors and scores add observability obligations, but no persistent audit
  store or telemetry service is introduced.
- The first slice is ranking only. Identity matching, unresolved-target
  resolution, test selection, and frontend-work classification remain possible
  later use cases, not permissions granted by this record.

## Verification Evidence And Planned Checks

Before this record moves to `accepted`, Plan 015 must specify and then prove:

- no flag means identical tool discovery, identical existing responses, no API
  key read, and zero outbound attempts;
- incomplete or malformed consent fails startup with a message naming the
  missing or invalid item but no secret;
- redirects, non-HTTPS destinations, moving model aliases, and unknown data
  categories are rejected;
- the outbound serializer contains only the fields D3 permits, under both
  evidence-text modes;
- the provider fake proves deterministic ordering, ties, truncation, malformed
  responses, timeout, rate-limit fallback, and provider unavailability;
- a ranking call reads one snapshot and never mutates graph counts, assertions,
  freshness, identity, or the results of any existing tool;
- required test lanes complete without a credential and without external
  network access; and
- an explicitly invoked live smoke over a synthetic fixture records endpoint,
  requested and response model, status, latency, and transmitted categories,
  but no source-derived payload or secret.
