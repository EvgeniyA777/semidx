---
title: "Optional Jev ranking projection"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-26"
---

# 015: Optional Jev Ranking Projection

## Goal

Add one explicitly enabled, read-only Jev integration that reranks a bounded
`semidx_context`-shaped candidate set for a user query while preserving the
semantic graph as the only authority for entities and relationships.

The integration succeeds only if all existing local indexing and query paths
remain unchanged without configuration, the outbound destination and data
categories are named at startup, provider failure degrades to visible local
ordering, and no Jev result can enter the graph write path.

## Product Principle

The graph answers **what exists and how it is related**. Jev may answer only
**which already-selected candidate is probably more useful for this query**.
The former is semantic authority; the latter is an optional approximate
projection.

When a choice appears during execution, decide in this order:

1. Local operation and graph authority beat ranking quality.
2. Data minimization beats convenience.
3. Visible fallback beats a plausible-looking remote answer.
4. A versioned, measured model beats a moving alias.
5. Existing MCP tools stay exact and network-free; optional behavior gets a
   separate surface.

## Start Rule

Before Stage 0:

- read `RULES.md`, `ARCHITECTURE_CONSTITUTION.md`, `MEMORY.md`, `SPEC.md`,
  [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md), and
  [proposed ADR 013](../adr/013_optional_jev_ranking_projection.md);
- re-check the official [API reference](https://docs.typesafe.ai/api),
  [models page](https://docs.typesafe.ai/models), and
  [Jev limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13);
- run `./scripts/check-zig-version.sh` and record the exact Zig 0.16.0 result;
- create `docs/reports/015_optional_jev_ranking_projection_progress.md` with
  standard progress-log frontmatter; and
- apply the Plan Readiness Gate again against the then-current repository.

If the official endpoint no longer accepts the request/response shape recorded
in ADR 013, or `jev-1.13.0` is unavailable, stop Stage 0. Update the proposed
ADR and this plan from current primary sources, review them, and resume only
after the decision and fixtures agree. Do not silently substitute a moving
alias or a new model.

If ADR 013 is rejected or cannot answer all eight constitutional questions as
written, stop the plan. Documentation cannot make a conflicting integration
acceptable.

## Scope

- Accept complete Jev consent only at MCP server startup.
- Add a conditional `semidx_rank_context` MCP tool over one published snapshot.
- Select a bounded graph candidate set using existing context traversal rules.
- Serialize only consented query text and graph metadata into Jev state.
- Ask one fixed `Noul` relevance question per candidate in one request.
- Return all candidates, ordered by relevance probability with deterministic
  ties and complete graph provenance.
- Record ranking provenance separately from graph provenance.
- Fall back visibly to original graph order on every provider failure.
- Provide offline fake-provider coverage and an explicit, non-gating live smoke
  over a synthetic fixture.
- Measure ranking quality on a committed labelled query fixture before claiming
  that Jev improves semidx context.

## Non-Scope

- Jev does not create, resolve, promote, merge, invalidate, or delete any graph
  assertion.
- Jev does not establish entity or source-unit identity, including move-plus-edit
  correspondence.
- Jev does not choose a language frontend, decide an invalidation closure,
  resolve an unresolved designator, or identify a call target.
- No source bodies, evidence text, snippets, byte ranges, absolute roots, VCS
  data, or filesystem reads outside the snapshot are sent.
- No candidate is dropped by a score threshold in the first slice.
- No change is made to `semidx_context`, `semidx_references`, or any other
  existing tool's schema or result.
- No public semantic contract, persistence, daemon, HTTP server, telemetry
  service, provider plugin framework, SDK dependency, new implementation
  language, or release is introduced.
- Identity alignment, unresolved-claim triage, test selection, and agent tool
  routing are deferred until ranking proves useful and each use case receives
  its own authority analysis.

## Sources Of Truth

- `ARCHITECTURE_CONSTITUTION.md`: §1 graph authority, §3 resolution separation,
  §5 consistent snapshots, §7 consumer independence, §8 local operation and
  explicit outbound consent, and §11 the decision test.
- [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md): the MCP
  preview remains a local consumer over published snapshots.
- [ADR 013](../adr/013_optional_jev_ranking_projection.md): proposed opt-in,
  data boundary, provider boundary, fallback, and provenance decision.
- `SPEC.md`: optional outbound data requirements and the absence of a public
  semantic contract.
- `MEMORY.md`: current in-memory graph, MCP preview, graph-authority boundary,
  and adoption-first direction.
- [Local MCP preview reference](../mcp/local_preview.md): current startup flags,
  tools, data boundary, and habit loop.
- [Documentation policy](../agent-policy/documentation.md),
  [testing policy](../agent-policy/testing.md), and
  [tooling policy](../agent-policy/tooling.md).
- Official TypeSafe [API](https://docs.typesafe.ai/api),
  [models](https://docs.typesafe.ai/models),
  [state](https://docs.typesafe.ai/concepts/state), and
  [limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13) pages.

## Current Evidence And Integration Points

The semidx snapshot used for planning was revision 102, product
`0.1.0-preview.4`: 77 units, 1,136 definitions, 3,444 current facts, 4,630
current unresolved assertions, and zero approximate assertions. Three units
reported failed analysis; the plan does not hide or reinterpret them.

The relevant current boundaries are:

- `src/mcp/main.zig` parses process-start options. It currently owns `--root`
  and the default-off `--allow-evidence-text` switch.
- `src/mcp/root.zig` owns `Options`, the server lifetime, conditional runtime
  state, tool dispatch, and the immutable published `Snapshot` queried by each
  call.
- `src/mcp/tools.zig` owns tool definitions, schemas, validation, candidate
  traversal, and rendering. Its header explicitly forbids tools from resolving
  or promoting graph claims.
- `tools.writeToolList` and `tools.byName` are currently static. Conditional
  discovery and call authorization must be added together so a disabled tool
  cannot be invoked by name after being omitted from discovery.
- `tests/mcp_smoke_test.zig`, `tests/mcp_gate.zig`,
  `tests/mcp_fixture_gate_test.zig`, and `tests/mcp_dogfood_test.zig` own the
  real stdio and habit-loop seams. Existing expected tool lists make accidental
  default exposure observable.
- `scripts/semidx-mcp.sh` passes arguments through and needs no secret handling;
  the API key remains an environment value read by the binary.

Semantic exploration found `Options`, `Server`, `writeToolList`, `byName`, and
the context projection as the direct ownership boundary. The current Zig
frontend cannot resolve many method-style calls inside that implementation;
those unresolved edges are a preview limitation, not evidence that another
module owns the behavior.

## Architecture Decisions

### A1: Separate Tool, Conditional Capability

`semidx_rank_context` is advertised in `server/discover` and `tools/list` only
when startup consent is complete. Direct calls while disabled return the same
unknown/unavailable tool class used for a tool not in the process capability
set. The capability set remains fixed for the process lifetime, preserving the
current tool-list cache assumption.

### A2: Exact Candidate Selection Before Approximate Ranking

The tool accepts `query` plus the same focus and traversal controls needed to
produce a bounded context neighborhood: one of `entity_id`, exact `name`, or
exact `path`; `language`, `direction`, `depth`, `freshness`,
`relationship_limit`, `candidate_limit`, and `max_response_bytes` where
applicable. `candidate_limit` defaults to 20 and is capped at 32.

Existing graph logic determines focus entities and traverses recorded
relationships. Ambiguous focus, unsupported analysis, stale claims, unresolved
designators, truncation, and diagnostics stay visible exactly as graph state.
The provider sees only entity candidates selected from that result; an
unresolved designator is never converted into a target candidate by its name.

### A3: Closed Outbound Projection

Add a pure candidate-card builder whose output is independently byte-bounded.
The permitted fields are exactly ADR 013 D3. The builder receives graph values,
not a filesystem handle, so it cannot read source opportunistically.

The initial request-state ceiling is 32,000 serialized bytes. The implementation
must measure the final JSON bytes, append whole cards only, and report candidate
totals and truncation. No token estimate is treated as exact arithmetic.
The complete serialized request is capped at 64 KiB and the response body at
256 KiB. A query that cannot fit inside the state ceiling fails locally without
truncation and without an outbound attempt.

The serialized state has one fixed shape:

```text
{ query: <query text>, candidates: { candidate_0: <card>, ... } }
```

Each `Noul` instruction names exactly one candidate key and asks whether that
card is useful for answering `query`; question-map keys are correlation ids,
not instructions. The exact English rubric and its true/false criteria are
committed in Stage 0 fixtures before the adapter exists.

### A4: Client-Owned Provider Seam

Add one narrow provider role under the MCP projection, sufficient to submit a
query and candidate cards and receive probabilities plus provider provenance.
Do not mirror the full TypeSafe API and do not add a general plugin registry.

The production implementation is `JevProvider`; tests inject
`FakeRankingProvider`. The policy layer owns ordering, tie-breaking, fallback,
and result shape. The vendor adapter owns HTTP, authorization, Jev JSON, model
validation, deadlines, retryable status handling, and error sanitization.

### A5: No Threshold Automation

Jev's `Noul` value is used as a relevance probability and ordering key. It is
not called graph confidence and is not converted into a fact. The first slice
returns every bounded candidate, including low-scoring ones. Evaluation may
recommend a later pruning policy, but implementing one requires another plan
because it changes recall and failure semantics.

### A6: Offline Gates, Explicit Live Evidence

No required build or test reads `TYPESAFE_API_KEY`, resolves the TypeSafe host,
or accesses external network. Request serialization and response parsing use
fixtures; orchestration uses a fake provider. A separate live smoke is invoked
manually with explicit flags and a synthetic repository fixture. Its absence
blocks claims of live interoperability, not the offline test lane.

## Architecture Boundaries

1. **MCP ranking policy**
   - Responsibility: choose graph candidates, build the closed outbound view,
     sort results, and render ranking/fallback provenance.
   - Knows about: immutable `Snapshot`, the narrow provider role, MCP budgets.
   - Does not know about: HTTP, bearer tokens, TypeSafe error bodies, graph
     mutation, source files.
   - Change contained: ranking rubric, tie policy, request budget, result shape.

2. **Jev adapter**
   - Responsibility: translate the provider role to the TypeSafe HTTP API.
   - Knows about: endpoint, versioned model, API key, Jev request/response JSON,
     deadline and retry policy.
   - Does not know about: graph entities, snapshot traversal, MCP protocol,
     semantic resolution, identity.
   - Change contained: vendor API and transport evolution.

3. **Outbound consent configuration**
   - Responsibility: validate complete process-start permission and expose a
     redacted immutable configuration.
   - Knows about: endpoint, model, data-category set, secret availability.
   - Does not know about: query contents or graph candidates.
   - Change contained: allowed destinations, categories, and startup UX.

4. **Existing graph and frontends**
   - Responsibility: unchanged semantic authority and incremental maintenance.
   - Knows about Jev: nothing.
   - Change contained: none; any required core or frontend edit is a scope
     violation and stops the stage.

## Contracts And Dependency Direction

The ranking policy owns the minimum provider contract; `JevProvider` and the
fake plug into it. `Server` owns an optional provider capability and passes the
current snapshot to ranking policy. `tools/list` reads only the capability bit.

Dependency direction:

```text
Graph/Snapshot -> MCP candidate projection -> ranking policy -> Provider role
                                                        ^
                                                        |
                                             Jev HTTP adapter / test fake
```

No dependency points from `src/core/`, `src/frontend/`, or `src/frontends/`
toward MCP, ranking, HTTP, or TypeSafe.

The result contract is an experimental MCP projection, not a semantic contract.
It contains:

- snapshot revision and `semantic_contract_version: null`;
- graph focus, diagnostics, counts, truncation, and candidate records;
- `ranking.kind = "approximate_projection"`;
- `ranking.status = "ranked" | "unavailable"`;
- provider, requested model, response model when present, destination origin,
  consented categories, request byte count, and provider-reported input/output
  token usage;
- per-candidate relevance probability only when validated; and
- original and ranked positions, with original order retained on fallback.

Graph claim fields remain graph claim fields. Ranking fields are nested under
`ranking` and never use `resolution`, `fact`, or graph `producer` terminology.

## Implementation Stages

### Stage 0: Accept The Boundary And Freeze The Testable Contract

Purpose: resolve every decision that could otherwise leak into code as an
implicit default.

Required work:

- Create the progress log and record current branch, worktree state, snapshot
  health, toolchain result, and primary-source review date.
- Review ADR 013 against all eight constitutional questions. Accept it unchanged
  or revise it and this plan together; do not start source work while it remains
  disputed.
- Update `SPEC.md`'s optional-outbound-data requirement with the accepted
  destination/data consent rule, default-off behavior, and consumer-only
  authority boundary. Do not publish a semantic contract.
- Confirm the exact official endpoint and a supported versioned model id. Keep
  aliases rejected.
- Set the initial overall provider deadline to **2,000 ms** and a maximum of one
  retry for `429` or `529` only when `Retry-After` fits inside that deadline.
  Record the rationale and make the value a named MCP-runtime constant, not a
  graph or public-contract field.
- Commit JSON request and response fixtures derived from the official API docs,
  including valid `Noul`, missing answer, duplicate/unknown answer, wrong type,
  non-finite/out-of-range value, and changed response model cases.
- Define a labelled ranking fixture with at least 24 queries: eight definition
  lookup, eight caller/reference, and eight impact/context questions. Each case
  names the focus, the bounded candidates, and acceptable top candidates. The
  fixture contains only synthetic repository content.

Stop rule:

- Stop if the API, model, consent boundary, or result authority cannot be
  represented without changing `src/core/`, a frontend, or an existing tool.
- Stop if accepting ADR 013 would conflict with the constitution. Resume only
  with a compliant consumer-only design, never with an exception.

Done when: ADR 013 is accepted, `SPEC.md` owns the outbound requirement, JSON
fixtures and the labelled ranking fixture exist, and the progress log records
the readiness verdict.

Verification: documentation drift review, fixture JSON parse test, and
`./scripts/check-zig-version.sh`.

### Stage 1: Default-Off Consent And Capability Plumbing

Purpose: make accidental network use structurally impossible before adding a
network adapter.

Likely files:

- `src/mcp/main.zig`, `src/mcp/root.zig`, `src/mcp/tools.zig`
- focused tests in `src/mcp/root.zig` and `tests/mcp_smoke_test.zig`
- `docs/mcp/local_preview.md`

Required behavior:

- Parse the four startup flags and read `TYPESAFE_API_KEY` only after
  `--enable-jev-ranking` is present.
- Validate HTTPS endpoint, versioned model id, the exact two-category consent
  set, and secret presence. Reject redirects by policy before transport exists.
- Store only a redacted immutable configuration in `Server`; secret memory is
  owned by the eventual adapter and zeroed on deinit where the Zig API permits.
- Make tool discovery and call authorization read the same capability set.
- With no enable flag, preserve the exact seven-tool discovery order and every
  existing response. Do not read the key and do not log Jev.
- Extend health only in the enabled profile with an `outbound_projection`
  summary naming destination origin, versioned model, and consented categories.
  Disabled health remains byte/shape compatible, and no secret appears.

Negative matrix:

- enable flag alone;
- each missing companion flag;
- missing key;
- `http://`, malformed URL, credentials in URL, query/fragment in endpoint;
- `jev-latest` and other aliases;
- unknown, partial, or duplicated category spellings; order is normalized as a
  set and the documented order is used in output;
- a disabled direct call to `semidx_rank_context`.

Done when: default startup is behaviorally unchanged, every incomplete consent
combination fails before serving, and the conditional tool cannot be called
when absent from discovery.

Verification: `zig fmt --check build.zig src tests`, `zig build test-mcp`.

### Stage 2: Pure Candidate Projection And Deterministic Ranking Policy

Purpose: prove the complete MCP behavior without HTTP or a credential.

Likely files:

- new `src/mcp/ranking.zig`
- `src/mcp/root.zig`, `src/mcp/tools.zig`
- focused unit tests and synthetic fixtures

Required behavior:

- Add the client-owned provider role and a deterministic fake provider.
- Reuse existing focus selection and context traversal semantics without
  changing existing renderers. Do not create a second semantic resolver.
- Build whole candidate cards from one snapshot under the 32,000-byte outbound
  state ceiling, 64 KiB request ceiling, 256 KiB response ceiling, and
  32-candidate cap. Report total, sent, omitted, and truncation.
- Prove the closed field allowlist by comparing serialized keys, not by checking
  only for known forbidden strings.
- Generate stable request-local candidate ordinals and questions; do not send
  process-local graph ids.
- Sort validated probabilities descending and tie by original graph order.
- Return all candidates with graph provenance intact and ranking provenance in
  its separate namespace.
- On fake timeout, unavailable, malformed, or partial results, return original
  order with visible `unavailable` status and sanitized diagnostics.

Done when: all tool behavior, serialization, ordering, fallback, budgets, and
graph immutability are proved with no network implementation present.

Verification: `zig fmt --check build.zig src tests`, `zig build test-core`,
`zig build test-mcp`, `zig build preview-gate`.

### Stage 3: Jev HTTP Adapter

Purpose: attach the one external detail behind the proven provider seam.

Likely files:

- new `src/mcp/jev.zig`
- `src/mcp/root.zig`, `build.zig`
- JSON fixtures and adapter-focused tests

Required behavior:

- Use Zig 0.16.0 standard-library HTTP and JSON facilities; add no SDK, package,
  runtime, or build-time fetch.
- POST the exact `state`, versioned `model`, and `questions` shape to the
  explicitly configured HTTPS endpoint with the bearer key.
- Reject redirects. Never reuse the authorization header for another origin.
- Enforce the 2,000 ms total deadline, body-size limits, at most one bounded
  `429`/`529` retry, and no retry for `401`, `422`, malformed data, or other
  permanent failures.
- Strictly validate question ids, answer types, probability range, finite
  numbers, and exact equality between requested and response model. Record both
  values separately even though a valid response makes them equal.
- Sanitize errors before they cross into MCP or logs. Raw provider response
  bodies are never logged or returned.
- Make every required test use a fixture or fake transport. The normal build,
  index, test, dogfood, and preview gate remain offline.

Done when: the adapter satisfies the provider role, all official response and
failure fixtures pass, secrets cannot appear in observable output, and the
default binary still makes no network attempt.

Verification: `zig fmt --check build.zig src tests`, `zig build test-mcp`,
`zig build dogfood`, `zig build preview-gate`.

### Stage 4: Live Synthetic Smoke And Ranking Evaluation

Purpose: distinguish protocol correctness from demonstrated usefulness.

Depends on: an operator explicitly supplies a TypeSafe key, endpoint, model,
and the two data categories. No agent may infer or recover a credential.

Required work:

- Add a developer-only Zig live-smoke step that starts the built MCP server on
  a temporary synthetic fixture, invokes `semidx_rank_context`, and verifies a
  complete response. No required lane depends on it.
- Record endpoint origin, requested/response model, categories, request bytes,
  provider-reported token usage, candidate count, latency, and status. Compute
  a dated cost observation from the then-current official price; do not make
  that price a runtime constant. Do not record the key or payload.
- Run the committed 24-query fixture first against original graph order, then
  against Jev order. Record top-1 success, Recall@5, Recall@10, MRR, and NDCG@5.
- Record latency and provider failures as observations, not flaky hard gates.

Gate:

- Jev ranking is allowed to remain an experimental opt-in only if NDCG@5
  improves over original graph order and Recall@10 does not decrease on the
  committed fixture.
- If the gate fails, add a normal follow-up commit that removes the tool, flags,
  provider adapter, and product documentation while retaining the synthetic
  fixture and progress evidence. Mark ADR 013 `rejected` and close this plan as
  completed but measured-and-declined. Do not advertise or retain dead runtime
  integration code.
- If no credential is available, stop before claiming live interoperability or
  ranking improvement. The implementation may be committed as default-off, but
  this stage and the plan remain incomplete until explicit live evidence exists
  or the user cancels the experiment.

Done when: live protocol evidence and before/after quality measurements are in
the progress log, with an explicit gate verdict.

Verification: the opt-in live smoke plus `zig build test-mcp` to prove the
credential-free path still passes afterwards.

### Stage 5: Canon, Security Review, And Closure

Purpose: make documentation say exactly what shipped and no more.

Likely files:

- `docs/mcp/local_preview.md`, `SPEC.md`, `MEMORY.md`
- ADR 013, this plan, and the progress log
- `README.md` only if the experimental opt-in is intentionally made part of the
  public quick start; otherwise do not add it there

Required work:

- Document every startup input, the exact outbound fields, destination, model
  pinning, default-off behavior, conditional tool discovery, fallback, and the
  fact that repository-relative paths and names are source-derived data.
- State plainly that TypeSafe receives the consented data and that semidx makes
  no claim about provider retention beyond the provider agreement applicable to
  the operator's account.
- Update `MEMORY.md` with actual runtime behavior and measured usefulness,
  compressing it below the policy bound.
- Run drift control across constitution, ADRs, `SPEC.md`, `CONFORMANCE.md`,
  `MEMORY.md`, capability matrix, MCP reference, implementation, and tests.
- Perform a security review of secret lifetime, redirect handling, endpoint
  parsing, logs, error bodies, request allowlist, model provenance, timeouts,
  and disabled behavior.
- Mark the plan and progress log historical only after the quality gate and all
  required checks pass. No release or version bump is part of this plan.

Done when: all owners agree, the consent boundary is inspectable from CLI help
and docs, no existing path depends on Jev, and the progress log records exact
checks, live evidence, residual risks, and commits.

Verification: `./scripts/check-zig-version.sh`,
`zig fmt --check build.zig src tests`, `zig build test-core`, `zig build test`,
`zig build test-mcp`, `zig build dogfood`, `zig build preview-gate`, plus
repository documentation guards.

## Risk Matrix

| Guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Jev is off by default | Startup or tool discovery activates a remote path implicitly | MCP unit plus real stdio smoke | Seven existing tools and no provider construction without the enable flag | Key is present in the environment but enable flag is absent | Stage 1 tests and `test-mcp` |
| Consent names destination and data | A partial flag set sends more or elsewhere | Pure config tests | Exact HTTPS endpoint, versioned model, complete category set | Missing flag, alias, HTTP URL, redirect, unknown category | Stages 1 and 3 |
| Secrets do not leak | Key appears in argv, logs, MCP errors, crash text, or fixtures | Adapter unit plus output scan | Environment-only key and sanitized error mapping | Provider echoes authorization or request in an error body | Stage 3 fixtures and review |
| Outbound payload is closed | Source text or an unapproved graph field leaves the machine | Serializer unit test | Exact allowlisted key set and 32 KB state ceiling | Evidence text enabled; long name/path/query; unexpected extension label | Stage 2 serializer tests |
| Graph remains authoritative | A score becomes a fact or changes an existing answer | Integration test over one snapshot | Pre/post graph counts and existing tool responses are identical | High score for an unresolved designator or stale candidate | Stage 2 immutability test |
| One consistent snapshot is used | Provider latency or a later refresh makes the response claim the wrong revision | MCP integration test | Candidate set and result revision come from the immutable snapshot captured for the call | A refresh after the ranked response publishes a later revision without changing the completed response | Stage 2 controlled provider test |
| Fallback is honest | Provider failure looks like a successful ranking | Policy unit and MCP result test | `unavailable` status, no probabilities, original order | Timeout, 401, 422, 429/529 exhaustion, malformed JSON | Stages 2-3 |
| Ordering is deterministic | Equal or missing scores produce unstable results | Pure policy unit | Probability descending, original position tie-break | Equal scores, negative zero, NaN, missing candidate | Stage 2 tests |
| Required lanes remain offline | CI or dogfood unexpectedly needs DNS, key, or service | Build/runtime gates with network trap or fake provider | No enabled configuration in gates; no key read | Key absent, DNS unavailable, provider down | Stages 1-3 and all gates |
| Vendor drift is attributable | Alias or response version changes behavior silently | Config and response validation | Versioned request id plus recorded response model | Response names a different version | Stages 0 and 3 |
| Ranking is useful | Integration adds latency and leakage without better context | Labelled evaluation | Before/after metrics on the same 24 cases | NDCG does not improve or Recall@10 falls | Stage 4 gate |
| Existing MCP clients do not regress | Conditional list logic changes normal discovery or calls | Real stdio smoke, dogfood, preview gate | Disabled profile remains byte/shape compatible | Enabled-only tool accidentally appears by default | Stages 1-5 |

## Definition Of Done

- ADR 013 is accepted and `SPEC.md` owns the optional outbound requirement.
- No Jev flag preserves the current seven-tool MCP surface and makes zero
  outbound attempts even when `TYPESAFE_API_KEY` exists.
- Complete startup consent names an HTTPS endpoint, a versioned model, and the
  exact `query-text,graph-metadata` categories; every partial or invalid form
  fails before serving.
- `semidx_rank_context` is advertised and callable only in the enabled profile.
- Its candidate set comes from one published snapshot through existing graph
  semantics; no name match, model answer, or consumer field creates a target.
- The payload allowlist, 32-candidate cap, 32,000-byte state ceiling, 64 KiB
  request ceiling, and 256 KiB response ceiling are fixture-tested, and evidence
  text cannot cross the outbound boundary.
- Every ranked result is labelled an approximate projection with endpoint,
  model, category, provider-reported token usage, probability, truncation, and
  status provenance separate from graph claims.
- All candidates remain present; ranking changes order only, with deterministic
  ties.
- Every provider failure returns visible unavailable status and original graph
  order while all existing tools continue to work.
- Required tests and gates run without a credential or external network.
- The opt-in live smoke over synthetic data records successful request/response
  model compatibility without recording secrets or payload.
- The 24-query evaluation improves NDCG@5 without decreasing Recall@10, or the
  integration is closed as measured-and-declined and is not advertised.
- Documentation, implementation, tests, plan status, progress log, and
  `MEMORY.md` agree; no release or version bump was made.
