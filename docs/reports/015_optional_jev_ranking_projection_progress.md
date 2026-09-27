---
title: "Optional Jev ranking projection progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-26"
---

# 015: Optional Jev Ranking Projection Progress

Companion log for
[docs/plans/015_optional_jev_ranking_projection.md](../plans/015_optional_jev_ranking_projection.md).

## Current Status

**Stage 0 is in progress.**

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

## Next Stage

Stage 3 (Jev HTTP adapter): new `src/mcp/jev.zig` implementing
`ranking.Provider` over Zig's standard-library HTTP/JSON, using the
`fixtures/jev/*.json` fixtures from Stage 0, enforcing the named
`provider_deadline_ms`/`request_ceiling_bytes`/`response_ceiling_bytes`
constants from `ranking.zig`, rejecting redirects, and never reusing the
authorization header for another origin. `Server` wires a real
`JevProvider` into `rank_provider` only when `options.jev` is present; the
default binary must still make no network attempt.
