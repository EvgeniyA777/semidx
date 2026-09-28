---
title: "Optional Jev ranking projection progress"
doc_type: "progress_log"
lifecycle: "active"
status: "blocked"
agent_action: "reference_for_context"
updated: "2026-09-27"
---

# 015: Optional Jev Ranking Projection Progress

Companion log for
[docs/plans/015_optional_jev_ranking_projection.md](../plans/015_optional_jev_ranking_projection.md).

## Current Status

**Stages 0-3 are complete. Stage 4 is blocked by direct TypeSafe vendor
onboarding.** The plan remains incomplete, Jev remains default-off, and no
ranking usefulness claim is justified.

## Stage 0: Accept The Boundary And Freeze The Testable Contract

### Environment record

- Branch: `dev`. Working tree clean at start (`git status --short` empty).
- Last commit before this stage: `feda2e4 docs: plan optional Jev ranking
  projection (ADR 013)`.
- Toolchain: `./scripts/check-zig-version.sh` reported "Zig version 0.16.0
  matches semidx target" (2026-09-26).
- Snapshot health referenced by the plan: revision 102, product
  `0.1.0-preview.4`, 77 units, 1,136 definitions, 3,444 current facts, 4,630
  current unresolved assertions, zero approximate assertions, three units with
  failed analysis (as recorded in the plan; not independently re-measured in
  this stage).

### Primary-source review (2026-09-26)

Re-checked against current TypeSafe documentation via live fetch:

- `https://docs.typesafe.ai/api`: confirms endpoint
  `POST https://api.typesafe.ai/v1/systemone`, request shape `state` +
  `questions`, and the three question types `Noul`, `Choice`, `Score`. `Noul`
  is a yes/no question returning the probability the answer is yes, matching
  ADR 013 D4.
- `https://docs.typesafe.ai/models`: confirms `jev-1.13.0` is a valid,
  explicitly versioned model id, and that `jev-latest` / `jev-preview` are
  aliases currently pointing at it. The plan's rejection of moving aliases in
  favor of `jev-1.13.0` is consistent with current docs.
- `https://docs.typesafe.ai/model-jaggedness/jev-1.13`: confirms documented
  limitations relevant to ranking — literal interpretation of criteria, weak
  numeric comparison, accuracy loss as irrelevant state grows, weak multi-hop
  indirection, and no guaranteed structural relationship between related
  questions (e.g. a score and its negation need not sum to 1.0). These support
  the plan's choices to keep candidate cards minimal (A3), use one flat `Noul`
  per candidate rather than a single multi-candidate comparison (D4), and avoid
  threshold automation on raw scores (A5).

No divergence found between the official API/model/limitations pages and the
shapes recorded in ADR 013 and Plan 015. The Stage 0 stop rule ("official
endpoint no longer accepts the recorded shape, or `jev-1.13.0` unavailable")
does not trigger.

### ADR 013 constitutional review

Checked ADR 013's "Constitutional Decision Test" against
`ARCHITECTURE_CONSTITUTION.md` §11's eight questions directly (not only against
ADR 013's own restatement):

1. Semantic graph as source of truth — preserved (D1: no write path).
2. Nodes as entities, not chunks — preserved (D1, D3: cards describe existing
   graph entities, never become nodes).
3. Facts/unresolved/approximate stay distinct — preserved (D1, D6: ranking is
   `approximate_projection`, never a graph resolution category).
4. Stable semantic identity — preserved (D3 excludes process-local ids; D1
   forbids identity correspondence decisions).
5. Incrementality and consistent observation — preserved (one immutable
   published snapshot per call, per the plan's Architecture Decisions and Risk
   Matrix row "One consistent snapshot is used").
6. Language frontends preserve meaning — preserved (no frontend or core kind
   changes; D3 renders recorded language metadata without reinterpreting it).
7. Consumers do not define the model — preserved (D1, Architecture Boundaries
   §4: existing graph/frontends know nothing about Jev).
8. Local operation without mandatory source-data transmission — preserved (D2:
   disabled by default, complete explicit consent required for destination and
   data categories; constitution §8's exact wording matches D2's mechanism).

No hard-fail condition from the Plan Readiness Gate applies to ADR 013 or Plan
015: scope/non-scope are explicit, stages have concrete outputs and ordered
dependencies, DoD is falsifiable via named commands/fixtures, and stop/resume
rules are stated for every branch (rejected ADR, unavailable model, failed
gate, missing credential).

**Verdict: ADR 013's design is not disputed.** All eight constitutional
questions check out and the primary-source review found no drift, so Stage 0
proceeds unchanged. ADR 013 itself gates its own `status: accepted` transition
on the "Verification Evidence And Planned Checks" list, which requires proof
from Stages 1-4 (offline consent/fallback tests, closed-payload tests,
credential-free lanes, live smoke). The ADR therefore stays `status: proposed`
until that evidence exists; this stage does not flip it prematurely.

### Stage 0 work completed

- [x] Updated `SPEC.md`'s "Optional outbound data" row
      ([SPEC.md:192](../../SPEC.md)) with the consent rule (explicit HTTPS
      destination, versioned identifier, closed category set, fail-fast on any
      partial/invalid input), default-off behavior, consumer-only authority
      boundary, and separate projection provenance, pointing at ADR 013 and
      this plan.
- [x] Committed JSON request/response fixtures under `fixtures/jev/`:
      `request_two_candidates.json`, `response_valid.json`,
      `response_missing_answer.json`,
      `response_duplicate_or_unknown_answer.json`, `response_wrong_type.json`,
      `response_out_of_range.json`, `response_non_finite.json`,
      `response_model_mismatch.json`. Field names (`state`, `model`,
      `questions.<id>.{type,instructions,criteria}`,
      `answers.<id>.{type,noul}`, `usage.{input_tokens,output_tokens}`) were
      taken from the live `docs.typesafe.ai/api` fetch above, not invented.
      All eight files parse as JSON (`python3 -m json.load` per file).
- [x] Committed `fixtures/jev/ranking_eval.json`: 24 labelled queries over one
      synthetic "storefront" Java repository (25 fictional entities), split
      8/8/8 across `definition`, `caller_reference`, and `impact_context`
      categories as the plan requires. Verified programmatically: exactly 24
      cases, exact 8/8/8 split, every `candidates` and `acceptable_top` entry
      resolves to a declared entity.
- [x] Recorded the 2,000 ms deadline / at-most-one bounded `429`/`529` retry
      rationale: ADR 013 D5 and this plan's Stage 0 section already state and
      justify the exact value. Stage 3 turns it into a named Zig constant in
      `src/mcp/jev.zig`; no code exists yet, so there is nothing to name in
      this stage beyond the recorded decision.

### Stage 0 Plan Readiness Gate re-check

Re-applied the gate from `docs/agent-policy/documentation.md` against the
current repository state (plan, ADR 013, this log, `SPEC.md`, and the new
fixtures):

- No hard-fail condition triggers. Product/runtime behavior, scope boundaries,
  stage dependencies, DoD verifiability, test-strategy coverage, and
  documentation consistency all check out against `RULES.md`, `MEMORY.md`,
  the constitution, and the now-updated `SPEC.md`.
- Ready criteria are met: contract changes are explicit (`SPEC.md`, ADR 013
  D3/D4/D6), scope/non-scope are explicit in the plan, decisions are recorded
  with rationale, drift control found no conflicting source of truth, stop/
  resume rules are precise per stage, and verification commands are named per
  stage.

**Stage 0 verdict: ready to proceed to Stage 1.** ADR 013 stays
`status: proposed` until Stages 1-4 supply the evidence it names; that is
expected, not a blocker to starting Stage 1's structurally-offline work.

## Stage 1: Default-Off Consent And Capability Plumbing

**Stage 1 is complete.**

### What shipped

- New `src/mcp/jev_consent.zig`: a pure, allocation-free validator
  (`validate(endpoint_raw, model_raw, send_raw, key_present)`) with a fixed
  check order (endpoint, then model, then send, then key presence) and a
  `describe(err)` that names the offending item without ever touching a secret
  value. 21 unit tests cover the accept path, category-order normalization,
  and every rejection: missing endpoint/model/send/key, non-HTTPS, userinfo,
  query, fragment, malformed URL, `jev-latest`/`jev-preview` aliases, a bare or
  two-part model id, an unknown category, a duplicated category, and a partial
  category set.
- `src/mcp/root.zig`: `Options.jev: ?jev_consent.Consent`. Never stores the
  secret; `main.zig` checks its presence and discards the value. `status()`
  populates a new optional `outbound_projection` field only when consent is
  present.
- `src/mcp/tools.zig`: `Status.outbound_projection` and `OutboundProjection`
  (`destination_origin`, `model`, `categories` in the documented
  `query-text,graph-metadata` order). `health()` renders the block only when
  present; the disabled shape is unchanged.
- `src/mcp/main.zig`: parses `--enable-jev-ranking`, `--jev-endpoint`,
  `--jev-model`, `--jev-send`; reads `TYPESAFE_API_KEY` only when the enable
  flag was seen; validates before `Server.init` (before any indexing); fails
  with `jev_consent.describe(err)` on the first violation; logs destination and
  model (never the key) once enabled; usage text documents all four inputs.
- `docs/mcp/local_preview.md`: documents the four flags, the current
  Stage-1-only behavior (validated and reported, no tool advertised yet), and
  the read-only-when-enabled key handling.
- `MEMORY.md`: Plan 015 entry updated from "planned" to "Stages 0-1 done,
  Stages 2-3 pending".
- Tests: `tests/mcp_stdio_client.zig` gained
  `Client.startWithEnviron(..., environ_map)` (refactored out of `start`) so a
  test can control which environment the child sees, needed to exercise
  `TYPESAFE_API_KEY` deterministically instead of depending on the host
  environment. `tests/mcp_smoke_test.zig` gained five tests:
  - enable flag alone fails before serving (no stdout, exit 2);
  - a complete-but-for-`--jev-send` consent fails naming `--jev-send`, proving
    the fixed check order;
  - an invalid model alias fails even with the key present, and the key value
    never appears in stderr;
  - with the key present but no enable flag: still exactly 7 tools, no
    `outbound_projection` in health, a direct `semidx_rank_context` call
    returns the same "Unknown tool" class as any unrecognized name, and stderr
    never mentions Jev or the key;
  - with complete consent and the key present: still exactly 7 tools (the tool
    itself is Stage 2's job), `outbound_projection` reports the right origin,
    model, and category order, and stderr logs the enabled destination/model
    but never the key.

### Why `semidx_rank_context` still does not exist

Stage 1's own file list (`main.zig`, `root.zig`, `tools.zig`, tests) does not
include `ranking.zig`, and Stage 2 is titled "Pure Candidate Projection And
Deterministic Ranking Policy." Reading those together: Stage 1 builds and
proves the consent/capability *plumbing*; Stage 2 is where
`semidx_rank_context` is added to the `Tool` enum, `tools.definitions`, and
`callTool`'s dispatch, together with the capability gate that decides whether
`byName`/`writeToolList` expose it. Building a stub tool now, only to give it
real behavior in Stage 2, would mean touching the same dispatch switch twice
and risking exactly the kind of accidental exposure gap A1 exists to prevent.
Until Stage 2, "disabled direct call to `semidx_rank_context`" and "enabled
direct call to `semidx_rank_context`" are indistinguishable and both correctly
return "Unknown tool" — which is what the five tests above prove.

### Verification run

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-mcp`: 59 tests, 57 passed, 1 pre-existing intentional skip,
  0 failed (after fixing two test bugs found while writing them: a
  `--jev-send`-order assumption that didn't match the validator's actual fixed
  order, and a `tools/call` request missing `_meta` that hit the legacy-era
  path instead of the unknown-tool path).
- `zig build test-core`: passed.
- `zig fmt --check` and `test-core`/`test-mcp` re-run clean after the doc and
  `MEMORY.md` edits.
- Manual stdio checks (not part of the committed suite, used only to shape the
  automated tests before writing them): enable-alone fails with
  "--jev-endpoint is required"; full consent plus a real-shaped dummy key logs
  "Jev ranking is enabled; destination https://api.typesafe.ai, model
  jev-1.13.0" and never the key; default profile has no `outbound_projection`
  key at all.
- `mcp__semidx__semidx_refresh` run after the edits; revision 118, no new
  analysis failures beyond the three pre-existing ones.

### Stage 1 Plan Readiness re-check

No hard-fail condition applies going into Stage 2. Stage 2's required behavior,
likely files, and DoD are concrete and depend only on artifacts that now exist
(`Options.jev`, the validated `Consent`, `OutboundProjection` health
rendering). No decision here needs revisiting before Stage 2 starts.

## Stage 2: Pure Candidate Projection And Deterministic Ranking Policy

**Stage 2 is complete.**

### What shipped

- New `src/mcp/ranking.zig`, deliberately graph-agnostic: `Card` (the exact
  closed field set from ADR 013 D3: `language`, `role`, `name`,
  `container_path`, `source_unit_path`, `relationship` (`kind`+`direction`),
  `resolution`, `freshness`, `producer`, `diagnostics`, keyed by a
  request-local `candidate_N` ordinal, never a process-local id);
  `serializeState` (appends whole cards until the next one would cross a
  caller-supplied byte ceiling, so tests can force truncation without a
  32,000-byte fixture, while production uses `default_state_ceiling_bytes =
  32_000`; rejects a too-large query locally, per A3, without ever building a
  partial request); `Provider` (the narrow `rank(query, cards) ->
  probabilities + provenance` contract); `FakeProvider` (configurable: fixed
  scores, simulated unavailability, and four ways to simulate a malformed
  response); and `decide`, which runs a provider (or reports "no ranking
  provider is configured" when there is none), validates its answer against
  every ADR 013 D4 rule (exactly the sent ordinals, no duplicates, finite
  `[0, 1]`), and sorts validated results descending with a stable tie-break on
  original order. `request_ceiling_bytes`, `response_ceiling_bytes`, and
  `provider_deadline_ms` are recorded here as named constants for Stage 3 to
  enforce; nothing in this stage reads them yet. 11 unit tests, run both
  standalone (`zig test src/mcp/ranking.zig`) and as part of `test-mcp`.
- `src/mcp/tools.zig`: `.semidx_rank_context` added to `Tool` and
  `definitions` (schema: `query` plus `semidx_context`'s focus/traversal
  controls, `candidate_limit` default 20 max 32); `byName`/`writeToolList` now
  take a `jev_ranking_enabled: bool` and gate this one tool identically in
  both places, so a disabled direct call gets the exact same "Unknown tool"
  text as a name the process never recognized (ADR 013 A1) — proven by
  comparing the two error strings, not by asserting a different error class
  exists. `pub fn rankContext` selects candidates using the same
  `selectTargets`, `relationshipPasses`, and `reach` primitives
  `semidx_context` already uses (no second resolver), builds one `Card` per
  candidate, calls `ranking.serializeState`/`ranking.decide`, and renders a
  result with `focus`, `candidates` (graph fields via the existing
  `writeEntity`/existence rendering, plus `source_unit_path`, `relationship`,
  `diagnostics`, and a `ranking` sub-object with `original_position` and
  `probability`), and a top-level `ranking` block (`kind`,`status`, provider,
  requested/response model, destination origin, categories, token usage,
  reason). Candidates beyond the byte ceiling keep their original relative
  order after the ranked ones; every candidate is always present.
- `src/mcp/root.zig`: `Server.rank_provider: ?tools.ranking.Provider = null`
  (doc-commented as production-always-null before Stage 3; tests set it
  directly, the same pattern the existing `Harness`/fault-injection tests
  already use for white-box control). `callTool` passes
  `.{ .provider = self.rank_provider, .destination_origin = ...,
  .categories = ... }` to `rankContext`; the origin always comes from the
  already-validated consent, never recomputed.
- `docs/mcp/local_preview.md` and `MEMORY.md` updated: the tool is documented,
  and the Stage-1-era "does not yet advertise or serve any tool" sentence is
  corrected now that it does.
- Tests: `tests/mcp_smoke_test.zig`'s Stage 1 test asserting "still 7 tools
  under complete consent" is renamed and extended to assert 8 tools, that
  `semidx_rank_context` is among them, and that calling it returns a
  well-formed `unavailable` fallback naming the right destination. Two
  existing `src/mcp/root.zig` in-module tests that iterate `tools.definitions`
  or compare list length against it needed updates: the generic dispatcher
  test now subtracts the one consent-gated tool from its expected count
  instead of enabling consent it has no other reason to carry, and the
  generic per-argument-schema fuzz test now enables a fake consent (no
  provider) so `semidx_rank_context`'s schema is fuzzed like every other
  tool's, with tool-specific base-argument handling for its two-part focus
  (`query` plus `name`/`entity_id`/`path`) added to that shared harness.

### Known Stage 2 simplifications, recorded rather than hidden

- The MCP *response* budget (`max_response_bytes`) is accepted and reported in
  `budget`, but unlike `semidx_context` this tool does not yet truncate its
  response incrementally against it. `candidate_limit` (max 32) keeps results
  small enough that this has not been observed to matter, but it is a real gap
  against full parity with `semidx_context`'s budget discipline and should be
  named explicitly if a future stage tightens it.
- `decide`'s tie-break sorts only the cards actually sent (a prefix of the
  full candidate list); any candidate cut by the 32,000-byte state ceiling
  (not observed on real data — see the manual check below) keeps its original
  position appended after the ranked ones rather than being interleaved by a
  synthetic score. This is a documented policy choice, not an oversight: no
  probability exists for an unsent candidate, so nothing was available to sort
  it by.

### Verification run

- `zig test src/mcp/ranking.zig`: 11/11 passed standalone.
- `zig fmt --check build.zig src tests`: clean.
- `zig build test-mcp`: passed (fixed two pre-existing in-module tests that
  hard-coded the tool count/list against the newly consent-gated tool).
- `zig build test-core`: passed.
- `zig build test`: passed.
- `zig build preview-gate`: both the fixture and the dogfood-over-this-repository
  profiles passed every hard-pass check; no regression in existing tool output.
- Manual verification against this repository's own snapshot (not part of the
  committed suite, used to sanity-check real data before trusting the unit
  tests): `semidx_rank_context` on `health`/`src/mcp/tools.zig` with
  `candidate_limit: 5` returned `candidates_total: 8`, `candidates_sent: 5`,
  `candidates_truncated: true`, graph fields identical in shape to
  `semidx_context`'s, and `ranking.status: "unavailable"` with
  `reason: "no ranking provider is configured"` and the correct
  `destination_origin`; no source text, no key, and (checked via
  `semidx_health` before and after the call) identical entity/assertion
  counts, proving graph immutability by direct observation, not only by unit
  test.
- `mcp__semidx__semidx_refresh` run after the edits; revision 127, no new
  analysis failures beyond the three pre-existing ones.

## Stage 3: Jev HTTP Adapter

**Stage 3 is complete, with one deliberate, documented scope reduction on the
deadline guarantee — see below.**

### What shipped

- New `src/mcp/jev.zig`, implementing `ranking.Provider` with Zig 0.16's
  standard-library `std.http.Client` only (no SDK, no extra dependency,
  confirmed by reading `build.zig`: no new package was added). `JevProvider`
  owns one `http.Client` and the API key; `provider()` returns the vtable
  `ranking.decide` calls exactly like the fake.
  - **Request**: `buildRequestBody` embeds `ranking.serializeState`'s output
    verbatim under `"state"`, plus `"model"` and one `"noul"` question per
    sent candidate under `"questions"`, using the exact fixed English rubric
    from `fixtures/jev/request_two_candidates.json` (`instructions`,
    `criteria.true`, `criteria.false` are the same string constants, tested
    against that fixture's shape). Refuses locally (no outbound attempt) when
    the built request would exceed `ranking.request_ceiling_bytes` (64 KiB).
  - **Transport**: `client.request(.POST, uri, .{ .redirect_behavior =
    .not_allowed, ... })` — a redirect is a rejected error, never followed,
    so the bearer header can never reach a second origin. The bearer key is
    added as a per-request `extra_headers` entry and never touches `Options`,
    a log line, or a diagnostic.
  - **Response**: `429`/`529` are read for a numeric `Retry-After` and treated
    as `retry_after_seconds`; anything else non-`200` is an immediate
    `unavailable`, no retry. The body is read through
    `reader.allocRemaining(arena, .limited(ranking.response_ceiling_bytes))`
    (256 KiB), which errors before a larger body is ever fully buffered.
  - **Response validation** (`parseResponse`): accepts only a JSON object
    naming `model` (a string, checked byte-for-byte against the requested
    model — D4's "exact equality... record both values separately" is
    satisfied because a match is what lets `ranking.decide` set both
    `requested_model` and `response_model` on the successful result) and
    `answers` (an object of `{"type":"noul","noul":<number>}`); anything else
    at the JSON-shape/type level is a sanitized `unavailable`.
    Ordinal-uniqueness, completeness, and numeric range/finiteness are left to
    `ranking.decide`, which every provider (fake or real) already goes
    through — division of labor confirmed by the fixture tests below, several
    of which show `parseResponse` accepting a shape that only `decide` (tested
    separately, Stage 2) actually rejects.
  - **Retry/deadline**: one bounded retry for `429`/`529`, only when
    `elapsed_so_far + Retry-After` fits inside `ranking.provider_deadline_ms`
    (2,000 ms), measured with `Io.Timestamp`/`Clock.Duration`. See the scope
    note below for exactly what this does and does not guarantee.
  - **Error sanitization**: `sanitizeTransportError` maps every transport
    `anyerror` to one of a handful of fixed, non-dynamic strings ("could not
    reach the provider", "TLS to the provider failed", etc.); no header
    value, URL, or body fragment can reach a result or a log through this
    path.
- `build.zig`: new `semidx_jev_fixtures` options module
  (`b.pathFromRoot("fixtures/jev")`) imported by the `semidx_mcp` module, so
  `jev.zig`'s tests read the committed Stage 0 fixtures at runtime (outside
  `src/mcp/`'s package path, so `@embedFile` does not apply) instead of
  inlining them.
- `src/mcp/root.zig`: `Server.jev_adapter: ?jev.JevProvider`, constructed in
  `init` from `options.jev` and the now-forwarded `jev_api_key` parameter, and
  `Server.wireJevProvider()`, which points `rank_provider` at it. Split into
  two steps because `Provider.ptr` captures `&self.jev_adapter.?`, which would
  dangle if taken before `Server.init`'s return value reaches its final
  address; `wireJevProvider` must run after the caller's `var server = try
  Server.init(...)`. `deinit` now closes the adapter's `http.Client`.
- `src/mcp/main.zig`: the API key, read only when `--enable-jev-ranking` is
  present, is now forwarded to `Server.init` instead of being discarded after
  the presence check (Stage 1's original design, superseded now that Stage 3
  gives the key an owner). `server.wireJevProvider()` is called once, right
  after `Server.init`, before serving.
- `docs/mcp/local_preview.md` and `MEMORY.md` updated: a real adapter exists;
  its usefulness is still unmeasured (Stage 4), so a `"ranked"` result is
  documented as an unproven ordering, not a recommendation.

### Scope note: what the 2,000 ms deadline actually guarantees today

Investigated `std.http.Client`'s Zig 0.16 API in depth (via the installed
stdlib source, not from memory) looking for a way to bound an entire
request/response round trip by a wall-clock deadline. Findings, checked
against the actual source:

- `Client.fetch` and `Client.request` accept no timeout parameter at all.
- `Client.connectTcpOptions` accepts a per-connect `Io.Timeout`, but the
  convenience `request()`/`fetch()` path this adapter uses calls the
  plain, timeout-less `connect()` internally; using the timeout would require
  hand-rolling the connection and request construction `request()` normally
  does, which this stage did not do.
- `std.Io`'s structured-concurrency primitives (`Io.async`, `Future.await`,
  `Future.cancel`) provide no "await with a timeout, whichever finishes
  first" combinator for an arbitrary function; `Batch.awaitConcurrent(io,
  timeout)` is the only timeout-aware wait, and it operates on raw
  `Io.Operation`s (socket-level primitives), not on a `Future` wrapping a
  higher-level call like `Client.fetch`.

Given that, this adapter enforces the deadline as a **retry-eligibility
budget**, not a preemptive abort: it measures elapsed time and will not start
a retry that would not fit inside 2,000 ms, but a single in-flight attempt
against an unresponsive-but-connected peer is not forcibly cut off. This is a
real, honest gap against "enforce the 2,000 ms total deadline" read as a hard
wall-clock ceiling on every call. It is recorded here rather than papered over
because Stage 4's live smoke is the first point this project can observe real
network latency at all, and because retrofitting the manual
`connectTcpOptions` + hand-built `Request` path to add real preemptive
cancellation is a bounded, well-scoped follow-up rather than something to
guess at without a way to verify it.

### Verification run

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-mcp`: passed, 80 tests (1 pre-existing intentional skip).
  `jev.zig`'s own tests cover: `buildRequestBody`'s shape and fixed rubric;
  `parseResponse` against all eight Stage 0 fixtures (valid, missing answer,
  duplicate/unknown answer, wrong type, out-of-range, non-finite — rejected
  earlier than expected, at the JSON-shape level, because `1e400` parses as
  `std.json.Value.number_string` rather than a float, which this function
  already treats as untrusted — model mismatch, and `sanitizeTransportError`).
  All of these run with no network access.
- `zig build test-core`, `zig build test`, `zig build dogfood`, `zig build
  preview-gate`: all passed; no regression in existing tool output.
- Manual, local-only verification (not part of the committed suite, and
  deliberately never contacts `api.typesafe.ai` or any real third party,
  consistent with Stage 4 being the only stage authorized to do that): pointed
  a rebuilt binary's `--jev-endpoint` at `https://127.0.0.1:1/v1/systemone`
  (a reserved, always-refused local port) with a dummy key. Result:
  `ranking.status: "unavailable"`, `reason: "could not reach the provider"`,
  correct `destination_origin`, no hang, exit 0, and the dummy key did not
  appear anywhere in stdout or stderr. This is the first real (if local-only)
  exercise of the transport code path outside a unit test.
- `mcp__semidx__semidx_refresh` run after the edits; revision 135, no new
  analysis failures beyond the three pre-existing ones.

### Known Stage 3 gaps, recorded rather than hidden

- No automated, offline test exercises `JevProvider.rank`'s full transport
  path (retry-after handling, redirect rejection, response-size ceiling) end
  to end; only its pure JSON-building/parsing halves are unit-tested, and the
  transport path itself was checked once by hand (above). A loopback
  `std.http.Server`-based test would close this gap and is a reasonable
  follow-up before leaning on retry/redirect behavior in production.
- The 2,000 ms deadline is a retry budget, not a hard per-call ceiling — see
  the scope note above.

## Stage 4 Blocker And Handoff

On 2026-09-27 the operator recorded that direct TypeSafe registration did not
yield an account or API key and chose not to add Vercel, OpenRouter, another
gateway, a proxy, or another credential surface as a workaround. This keeps the
experiment's consented destination and evidence standard unchanged instead of
silently changing the provider boundary to finish a checklist.

Current disposition:

- Stage 4 is blocked, not skipped, completed, or measured-and-declined.
- Jev stays disabled by default. The runtime integration is not advertised as
  useful, and a `ranking.status: "ranked"` result remains an unproven ordering.
- Existing `FakeProvider` tests and committed fixtures remain the required
  provider evidence; all required lanes remain credential-free and offline.
- No gateway, proxy, alternate model, or live-smoke code is planned while this
  blocker remains.
- [Plan 016](../plans/016_trustworthy_working_copy_sync.md) is the next active
  implementation priority. A later graph-native decision-model proposal must
  receive its own authority analysis, ADR, plan, labels, and calibration gates.

Resume rule: Stage 4 resumes only after direct TypeSafe onboarding provides a
credential, the operator explicitly supplies the endpoint/model/categories and
authorizes the live synthetic smoke, and the primary API/model sources still
match the frozen fixtures. Then run the committed 24-query fixture against
original graph order and Jev order and compute top-1, Recall@5, Recall@10, MRR,
and NDCG@5. If the operator cancels instead, use Plan 015's existing removal
path and record the experiment as measured-and-declined only if the required
measurement actually occurred.
