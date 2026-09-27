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

## Next Stage

Stage 1 (default-off consent and capability plumbing) is next: parse the four
`--enable-jev-ranking` / `--jev-endpoint` / `--jev-model` / `--jev-send`
startup flags plus `TYPESAFE_API_KEY`, validate them, store a redacted
configuration on `Server`, and make tool discovery and call authorization read
the same capability bit, all without adding an HTTP adapter yet.
