---
title: "Optional decision-model ranking projection"
doc_type: "plan"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-29"
---

# 015: Optional Decision-Model Ranking Projection

## Goal

Add one explicitly enabled, read-only decision-model integration that reranks a
bounded `semidx_context`-shaped candidate set for a user query while preserving
the semantic graph as the only authority for entities and relationships. The
integration speaks the System One wire protocol published by TypeSafe: the
hosted Jev service is one destination, and open decision models served on the
local machine behind the same protocol are another.

The integration succeeds only if all existing local indexing and query paths
remain unchanged without configuration, the destination, model, and data
categories are named at startup, provider failure degrades to visible local
ordering, and no model result can enter the graph write path.

The file name keeps its original `jev` slug; the plan number and links stay
stable. Code identifiers such as `JevProvider` and the `--jev-*` flags name the
System One protocol family, not only the hosted Jev model; renaming them is
outside this plan.

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

## Execution State

Stages 0-3 are complete. On 2026-09-27 the original Stage 4 was blocked because
direct TypeSafe onboarding yielded no account or API credential, and the
operator declined a gateway, proxy, or alternate provider route.

**Revision of 2026-09-29.** The operator reversed that decision for one case
only: open decision models served on the local machine behind the System One
protocol. Hosted gateways and proxies remain out of scope. The original Stage 4
is replaced by Stages 4A-4D below:

- **4A** admits a loopback destination class with pinned model weights;
- **4B** replaces the evaluation fixture, which cannot measure improvement (see
  [Evaluation Fixture Defect](#evaluation-fixture-defect));
- **4C** evaluates local open models against graph order;
- **4D** is the hosted Jev live evaluation, still blocked on a direct TypeSafe
  credential and no longer required for closure.

Priority: the operator placed Stages 4A-4C ahead of
[Plan 017](017_adoption_baseline_and_priority_selection.md). Plan 017 stays
planned and unchanged; it starts after this plan closes or blocks.

This plan remains a consumer-side ranking experiment. A model that selects graph
targets, writes assertions, or resolves unresolved designators is
[Idea 003](../ideas/003_graph_decision_model.md), which needs its own
measurement, ADR, and plan; nothing here admits it.

If the operator cancels the experiment, revise this plan and remove the
default-off runtime integration without claiming a measured quality verdict
that never occurred.

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

Before Stage 4A, additionally re-check the primary sources for each local
runtime named in [Sources Of Truth](#sources-of-truth) and apply the Plan
Readiness Gate to Stages 4A-4C. If no local runtime still serves
`POST /v1/systemone` with `noul` questions on the operator's machine, stop and
record that; do not write a second wire protocol inside this plan.

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
  that any model improves semidx context.
- Admit a loopback destination class for System One models served on the local
  machine, with operator-attested weight digests (Stage 4A).
- Replace the degenerate evaluation fixture with graph-produced candidate sets
  over a committed synthetic repository (Stage 4B).
- Evaluate a frozen set of at most three local open models (Stage 4C).

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
- No hosted gateway, proxy, or third-party relay for Jev. No non-loopback
  plain-HTTP destination.
- semidx does not install, start, download, or supervise a model runtime or
  weights. The operator provides the runtime outside the repository; no build,
  test, or gate depends on it.
- No new wire protocol: a runtime that does not serve System One `noul`
  questions is out of scope. No `choice` or `score` questions in this plan.
- No model training, fine-tuning, or prompt tuning against the evaluation
  fixture.

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
- Local runtimes, primary sources reviewed on 2026-09-29:
  - [Ollaya](https://github.com/ollaya-dev/ollaya) (Apache-2.0): a local
    daemon serving open decision models by `name:tag`, with `POST
    /v1/systemone` and `GET /v1/models` described as wire-identical to
    TypeSafe; examples use `http://localhost:11435`; weights are fetched from
    Hugging Face pinned to a commit and verified by SHA-256. Whether its
    responses echo `model` and `usage` exactly like TypeSafe is not stated and
    is checked in Stage 4A.
  - [Jeff 1](https://github.com/Gestalt-Lab/jeff) (Apache-2.0 code and
    adapter): a LoRA on `Qwen3-4B-Instruct-2507` served by
    `uv run python -m scripts.jev_clf_server` at `http://127.0.0.1:8079` with
    `POST /v1/systemone`, reporting model id `GestaltLabs/Jeff-1`; Apple
    Silicon MPS is supported; no weight revision pinning is documented.
  - [Decision 1.0](https://vllm-sr.ai/blog/decision-models/) (vLLM Semantic
    Router, Apache-2.0): six open-weight models; no ready System One server is
    provided, so it is eligible only through a runtime that serves it.
  Benchmark numbers these projects publish are their claims, not evidence for
  semidx ranking.

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

### A7: Two Destination Classes And Pinned Local Weights

Added by the 2026-09-29 revision; [ADR 013](../adr/013_optional_jev_ranking_projection.md)
D2 is revised with it.

- **Remote** (unchanged): an `https://` endpoint, `TYPESAFE_API_KEY` required,
  a versioned model id, aliases rejected.
- **Loopback** (new): `http://127.0.0.1:<port>/<path>` or
  `http://[::1]:<port>/<path>` exactly. IP literals only; the name `localhost`
  is rejected because name resolution is outside the consent boundary. No
  userinfo, query, or fragment; redirects stay rejected. `TYPESAFE_API_KEY` is
  not read and no `Authorization` header is sent. Any other `http://` host is
  rejected.
- **Model pinning.** `--jev-model` stays required in both classes; `jev-latest`,
  `jev-preview`, and any `:latest` tag are rejected. A loopback destination
  additionally requires `--jev-model-sha256 <64 lowercase hex>`: the
  operator-attested SHA-256 of the served weights. For weights stored as
  several files it is the SHA-256 of the `sha256sum`-style manifest of those
  files (`<hex>  <relative path>\n` per file, sorted by path). semidx cannot
  read the runtime's files, so it records the digest as attested, never as
  verified. The flag is rejected for a remote destination, whose weights the
  operator cannot observe.
- **Response model.** Exact equality between requested and response `model`
  stays mandatory. If a runtime echoes a different string, Stage 4A stops with
  that finding; the rule is not relaxed silently.
- **Data categories.** The complete pair `query-text,graph-metadata` stays
  required for loopback. The data does not leave the machine, but it reaches
  another process that may log it; the flag keeps that boundary explicit.
- **Provenance.** The `ranking` block and the enabled-profile
  `outbound_projection` health summary add `destination_class`
  (`remote`/`loopback`) and, for loopback, `model_sha256_attested`.
- **Deadline.** The 2,000 ms retry budget is unchanged in both classes. It does
  not cut an in-flight attempt (see the Stage 3 progress log), so slow local
  inference completes and its latency is recorded; no hard deadline is added
  here.

## Evaluation Fixture Defect

Found in the 2026-09-29 review. The committed `fixtures/jev/ranking_eval.json`
cannot measure improvement:

- all 24 cases have exactly three candidates, and in all 24 the first listed
  candidate is acceptable, so the listed order already scores top-1 24/24 and
  mean NDCG@5 1.000; the original gate "NDCG@5 improves" could never pass for
  any model, including Jev;
- Recall@10 is 1.0 for every ordering of three candidates, so the recall guard
  tests nothing;
- no `storefront` source exists, only an entity list, so "original graph order"
  is not produced by the graph at all.

Stage 4B replaces it. The file stays in history; its protocol fixtures beside it
remain valid.

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

### Stage 4A: Loopback Destination Class And Pinned Weights

Purpose: admit local System One runtimes without widening the remote consent
boundary.

Likely files: `src/mcp/main.zig`, `src/mcp/root.zig`, `src/mcp/jev.zig`,
`src/mcp/ranking.zig`, `tests/mcp_smoke_test.zig`, `docs/mcp/local_preview.md`,
ADR 013, `SPEC.md`.

Required behavior (A7):

- Parse and classify the endpoint as remote or loopback. Add
  `--jev-model-sha256`, required for loopback and rejected for remote.
- For loopback, never read `TYPESAFE_API_KEY` and never send `Authorization`.
- Reject `:latest` tags in addition to the existing aliases.
- Add `destination_class` and `model_sha256_attested` to ranking provenance and
  to the enabled-profile health summary. The disabled profile stays byte and
  shape compatible.
- Add an offline loopback transport test with an in-process `std.http.Server`
  fake on `127.0.0.1` and an ephemeral port: a valid ranking, a redirect
  (rejected, not followed), a body above the response ceiling, `429` with and
  without a fitting `Retry-After`, and proof that no `Authorization` header
  arrives. This closes the Stage 3 gap "no automated test exercises the full
  transport path". It opens no external connection and needs no credential.

Negative matrix additions: `http://localhost:…`, `http://10.0.0.1:…`,
`http://127.0.0.1` with userinfo/query/fragment, loopback without digest,
malformed digest (length, case, non-hex), digest with a remote endpoint,
`name:latest`, and a key present in the environment with a loopback endpoint
(must not be read).

Then, manually and outside every lane, point a rebuilt server at each chosen
runtime's loopback endpoint on a synthetic root, call `semidx_rank_context`
once, and record whether the response `model` string equals the requested one
and whether `usage` is present. A mismatch stops 4A (A7).

Stop rule: stop if A7 cannot be implemented without touching `src/core/`, a
frontend, or an existing tool's result, or if no runtime passes the manual
compatibility check.

Done when: the negative matrix and loopback transport tests pass offline, the
default profile is unchanged, and the manual compatibility result per runtime
is in the progress log.

Verification: `zig fmt --check build.zig src tests`, `zig build test-mcp`,
`zig build test`, `zig build preview-gate`.

### Stage 4B: Rebuild The Evaluation Fixture

Purpose: make "better than graph order" measurable, with labels fixed before
any model runs.

Required work:

- Commit a synthetic Java repository under `fixtures/ranking_eval/storefront/`
  that realizes the existing `storefront` entity list, extended so focused
  context neighborhoods are larger: at least 40 named types or members, all
  fictional, no copied third-party source. Index it with the unchanged product.
- Freeze 24 queries, eight per category (`definition`, `caller_reference`,
  `impact_context`), before looking at any ranking. For each, freeze the focus
  and fixed tool arguments: `direction: both`, `depth: 2`,
  `candidate_limit: 20`.
- Produce each candidate set by calling `semidx_rank_context` with complete
  loopback consent pointed at a closed local port, so every result is the
  visible `unavailable` fallback in graph order, and record that order. It is
  the baseline. The focus entity is not a candidate, so write each query so
  that its answer lies in the focus's neighborhood (for example "which type
  validates an Order before payment?" rather than "where is Order defined?").
- A case is eligible only with at least 8 candidates. Replace an ineligible
  case by the next query from a pre-written reserve list of 12 (4 per
  category), in list order; record every replacement and why.
- Label every candidate `2` (answers the query), `1` (useful context), or `0`,
  from the synthetic source and the query text alone, before any model sees the
  fixture. Commit labels, reserve list, and replacements in one commit whose
  hash is recorded as the frozen fixture.
- Do not reorder, reword, or relabel after a model run. A labelling error
  found later is recorded, fixed in a new fixture version, and every model is
  re-run on that version.
- Record the baseline's metrics on the frozen fixture. A baseline that is
  already perfect on most cases is a valid finding that limits what ranking can
  add; queries are not replaced to make the baseline worse.

Metrics (fixed now): top-1 = the first candidate has label 2; Recall@k = the
share of label-2 candidates within the first k; MRR over the first label-2
candidate; NDCG@5 and NDCG@10 with gain = label.

The evaluator is built here: a developer-only Zig step, `zig build
ranking-eval`, that no lane, hook, or launcher depends on. It starts the built
server over the fixture root with a given consent, calls `semidx_rank_context`
per case, and computes the metrics for graph order and, when a provider
answers, for the model order. Its metric arithmetic is unit-tested on
hand-computed cases. Add it to the developer-tools row of
[tooling.md](../agent-policy/tooling.md) and to the command list in
`MEMORY.md`.

Done when: the synthetic repository, 24 eligible cases, labels, reserve list,
frozen commit hash, the evaluator with passing unit tests, and baseline metrics
are recorded.

Verification: `zig build test` and `zig build preview-gate` (the new fixture
files are also source units of this repository, so the `repository-copy`
profile indexes them), the evaluator's unit tests, and a JSON parse of the
fixture.

### Stage 4C: Local Open-Model Evaluation

Purpose: measure whether any local decision model orders graph candidates
better than the graph's own order.

Depends on: 4A and 4B complete; the operator has installed and started the
chosen runtime(s) outside the repository and explicitly authorizes the run. No
agent installs a runtime, downloads weights, or runs a remote installer script.

Required work:

- Run the 4B evaluator with complete loopback consent for each model.
- Freeze the model set before the first run: at most three
  (`runtime`, `model`, `sha256`) entries, chosen from the runtimes that passed
  4A and from what `GET /v1/models` lists. Record runtime version, OS, CPU/GPU,
  RAM, and acceleration mode. Do not add or swap a model after seeing results;
  a new model is a new, separately labelled run. Record the exact command the
  operator used to compute each attested digest.
- Run every model twice over all 24 cases. Report run-to-run differences in
  order; a model whose two runs disagree is reported as non-deterministic, and
  both runs count.
- Record per request: latency, status, request bytes, `unavailable` reasons.
  Latency and failures are observations, not gates.

Gate, per model, predeclared:

- **Keep** (experimental, default-off, documented as evaluated) only if, on the
  frozen fixture, mean NDCG@5 improves over graph order by at least 0.05, the
  model's order wins on more cases than it loses (per-case NDCG@5), Recall@10 is
  not lower, and no run has more than 2 of 24 `unavailable` results.
- Otherwise the model is **declined** for this fixture.
- If every model is declined and 4D stays blocked, close the plan as
  measured-and-declined: a follow-up commit removes the tool, flags, adapter,
  and product documentation, keeps fixtures and evidence, and marks ADR 013
  `rejected`. Do not retain dead runtime integration.
- If at least one model is kept, `semidx_rank_context` stays experimental and
  default-off; documentation names only the kept model(s), their digests, and
  the fixture version. No quality claim beyond this fixture.

Done when: all runs, metrics, per-model verdicts, and the environment record
are in the progress log.

Verification: `zig build ranking-eval` (operator-run), `zig build test-mcp` and
`zig build preview-gate` afterwards to prove the default path is unchanged.

### Stage 4D: Hosted Jev Evaluation (Optional, Blocked)

The original live Jev evaluation, unchanged in substance: the same 4B fixture
and 4C gate against `https://api.typesafe.ai/v1/systemone` with `jev-1.13.0`.
It stays blocked until direct TypeSafe onboarding yields a credential and the
operator explicitly resumes it; no gateway or proxy. It is not required for
closure. If it never runs, Stage 5 records Jev as unmeasured, not declined.

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
  the operator's account. For loopback, state that the data stays on the machine
  but reaches the operator's runtime process, which semidx does not control.
- Record each evaluated model's verdict (kept, declined, or unmeasured) with
  its digest and fixture version.
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
| Consent names destination and data | A partial flag set sends more or elsewhere | Pure config tests | Exact HTTPS or IP-literal loopback endpoint, versioned model, complete category set | Missing flag, alias, non-loopback HTTP URL, redirect, unknown category | Stages 1, 3, and 4A |
| Secrets do not leak | Key appears in argv, logs, MCP errors, crash text, or fixtures | Adapter unit plus output scan | Environment-only key and sanitized error mapping | Provider echoes authorization or request in an error body | Stage 3 fixtures and review |
| Outbound payload is closed | Source text or an unapproved graph field leaves the machine | Serializer unit test | Exact allowlisted key set and 32 KB state ceiling | Evidence text enabled; long name/path/query; unexpected extension label | Stage 2 serializer tests |
| Graph remains authoritative | A score becomes a fact or changes an existing answer | Integration test over one snapshot | Pre/post graph counts and existing tool responses are identical | High score for an unresolved designator or stale candidate | Stage 2 immutability test |
| One consistent snapshot is used | Provider latency or a later refresh makes the response claim the wrong revision | MCP integration test | Candidate set and result revision come from the immutable snapshot captured for the call | A refresh after the ranked response publishes a later revision without changing the completed response | Stage 2 controlled provider test |
| Fallback is honest | Provider failure looks like a successful ranking | Policy unit and MCP result test | `unavailable` status, no probabilities, original order | Timeout, 401, 422, 429/529 exhaustion, malformed JSON | Stages 2-3 |
| Ordering is deterministic | Equal or missing scores produce unstable results | Pure policy unit | Probability descending, original position tie-break | Equal scores, negative zero, NaN, missing candidate | Stage 2 tests |
| Required lanes remain offline | CI or dogfood unexpectedly needs DNS, key, or service | Build/runtime gates with network trap or fake provider | No enabled configuration in gates; no key read | Key absent, DNS unavailable, provider down | Stages 1-3 and all gates |
| Vendor drift is attributable | Alias or response version changes behavior silently | Config and response validation | Versioned request id plus recorded response model | Response names a different version | Stages 0 and 3 |
| Ranking is useful | Integration adds latency and leakage without better context | Labelled evaluation | Before/after metrics on the same 24 frozen cases | NDCG@5 gain below 0.05, more losses than wins, or Recall@10 falls | Stage 4C gate |
| Evaluation can show improvement | Baseline is perfect by construction or labels follow model output | Fixture review | Graph-produced candidates (≥8 per case), labels frozen before any run | Reordering or relabelling after a run; replacing hard cases | Stage 4B |
| Loopback stays loopback | A plain-HTTP destination off the machine, or a name that resolves elsewhere | Pure config tests | IP-literal `127.0.0.1`/`[::1]` only | `http://localhost`, private-network IP, userinfo | Stage 4A |
| No key reaches a local runtime | Bearer token sent to the local process | Loopback transport test | Key unread and header absent for loopback | Key present in environment | Stage 4A |
| Local weights are attributable | Results cannot be tied to the weights that produced them | Config and provenance tests | Required attested digest recorded in every ranked result | Missing or malformed digest, `:latest` tag | Stage 4A |
| Existing MCP clients do not regress | Conditional list logic changes normal discovery or calls | Real stdio smoke, dogfood, preview gate | Disabled profile remains byte/shape compatible | Enabled-only tool accidentally appears by default | Stages 1-5 |

## Definition Of Done

- ADR 013 is accepted with its revised D2, or `rejected` on a
  measured-and-declined close; `SPEC.md` owns the optional outbound requirement.
- No Jev flag preserves the current seven-tool MCP surface and makes zero
  outbound attempts even when `TYPESAFE_API_KEY` exists.
- Complete startup consent names an HTTPS or IP-literal loopback endpoint, a
  versioned model (plus an attested weight digest for loopback), and the exact
  `query-text,graph-metadata` categories; every partial or invalid form fails
  before serving.
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
- The loopback class accepts only IP-literal loopback endpoints with an attested
  weight digest, never reads the API key for them, and is covered offline by the
  loopback transport test.
- At least one local runtime passed the manual compatibility check, or the plan
  records why none did.
- The rebuilt 24-case fixture (graph-produced candidates, frozen labels) and its
  baseline metrics are committed.
- Every frozen local model has a recorded 4C verdict; at least one is kept, or
  the integration is closed as measured-and-declined and is not advertised.
  Hosted Jev is recorded as measured (4D) or unmeasured, never as declined
  without a run.
- Documentation, implementation, tests, plan status, progress log, and
  `MEMORY.md` agree; no release or version bump was made.
