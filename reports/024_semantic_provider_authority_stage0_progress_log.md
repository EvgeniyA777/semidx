---
title: "Semantic Provider Authority Migration — Stage 0 Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-08-28"
---

# Progress Log: Semantic Provider Authority Migration (plans/018)

Companion log for
[`plans/018_semantic_provider_authority_migration_plan.md`](../plans/018_semantic_provider_authority_migration_plan.md).
This log opens with **Stage 0 — Independent Review And Compatibility Baseline**
and is appended by later stages.

## Execution Record

- **Executor**: Claude Code v2.1.212; lead reviewer with an independent review
  pass. Fable and the repository-prohibited Explore agent were **not** used. No
  sub-agents were spawned.
- **Model actually used**: **Claude Opus 4.8 Thinking, high effort.** This
  updates the plan's Stage 0 routing default (Claude Opus 4.6) with the owner's
  explicit authorization.
- **High-effort justification**: Stage 0 locks the provider-neutral
  `CanonicalFactKey` identity assumptions and challenges the migration before any
  source work. The plan's own routing table rates this row `high` because
  canonical identity is correctness-critical, and the plan explicitly allows a
  high-effort override without a separate exception when identity/arbitration
  risk justifies it. The review surfaced a High-severity identity finding (F1),
  confirming the risk was real.
- **Bootstrap performed**: read `RULES.md` in full; confirmed CCC artifacts
  (`docs/code-context.md`, `.ccc/state.edn`) exist and read the code-context
  layer; followed the MCP-first workflow (`create_index` → `repo_map` →
  `resolve_context` → `fetch_context_detail`) for all code discovery.

## Stage Status

| Stage | Status |
| --- | --- |
| 0 — Independent review and compatibility baseline | **completed** |
| 1 — Evidence model and arbitration kernel | **completed** 2026-08-28 — kernel, FactBatch, executable golden parity, and round-trip coverage all delivered |
| 2–7 | not started |

## Scope Executed (Stage 0)

Documentation, baseline, and test fixtures only. **No production
authority/default extraction was changed.** Confirmed: `src/semidx/runtime/`
source is byte-identical to the pre-Stage-0 tree; only new artifacts under
`fixtures/provider-authority/` and this report were added.

### Deliverables produced

1. Independent review of ADR-046, plan 018, ADR-047, ADR-036 supersession, and
   the plans/007 amendment/closure criteria (below).
2. Protected Java + TypeScript corpus:
   `fixtures/provider-authority/corpus/` (definitions, references, calls,
   overloads, re-exports).
3. Cross-provider `CanonicalFactKey` identity fixtures:
   `fixtures/provider-authority/identity/` (Java overload; TypeScript re-export)
   — regex/tree-sitter/SCIP/LSP spellings → one key; distinct overloads/aliases
   stay distinct.
4. Protected extraction baseline (ground truth) and degradation/freshness
   expectations: `fixtures/provider-authority/behavior/`.
5. Deterministic retrieval/callers-callees/impact/confidence/snapshot baseline:
   `fixtures/provider-authority/baseline/`.

`reports/022_latest_active_plans_architecture_review.md` was read **as input
only**; it is untracked and was not modified, staged, or claimed.

## Independent Review

Posture per the plan's brief: ADR-046 is the accepted decision of record and
plan 018 the approved direction. The review challenges implementation
readiness, hidden assumptions, and unsafe sequencing rather than reopening the
authority decision. Findings are ordered by severity below; the 11 required
review questions are answered after them.

### Findings

| ID | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| F1 | **High** | `CanonicalFactKey.overload_identity.signature_key` is underspecified and **not producible by the heuristic/structural tiers as written**. The plan's example uses fully-qualified, type-only `java.lang.String,int`. The current extractor (`java.clj` `java-normalized-params`, l.237–242; `java-method-unit-id`, l.254–262) emits **simple, parameter-name-inclusive** text: `handle(String order)` → `"Stringorder"` (ground truth via REPL). Regex/tree-sitter cannot resolve `String`→`java.lang.String` without import/classpath resolution, and they include the param name. SCIP/LSP emit `(java.lang.String)` type-only. Without a canonical signature form, the same overload gets **different keys per provider**, violating the Stage 1 exit criterion "same semantic fact from multiple providers produces one canonical fact key." | **Resolved — Variant C adopted** (owner decision, 2026-08-03). Residual same-arity ordinal rule tracked as **F1a**. See "F1 Resolution — Variant C" below. |
| F1a | Medium | Same-arity overloads (e.g. `handle(String)` vs `handle(int)`, both arity 1) cannot be individually attributed by the heuristic tier under Variant C, because the arity-only core key collides. A provider-neutral disambiguator (source-order ordinal) is deterministic but does not match SCIP's type-based identity. | **Open sub-decision** — Stage 1 must pick the same-arity arbitration rule (explicit ambiguity vs ordinal alignment); tracked below. |
| F2 | Medium | Source-identity granularity is unspecified: the plan requires a per-document digest or revision+verification, but not whether staleness invalidates a whole document's exact facts or only affected ranges. For overloads, a coarse per-document digest may over-invalidate (one edited method drops all SCIP facts) or, if mis-scoped, under-invalidate. | **Deferred to Stage 3 design** (SCIP slice); recorded as a named design question. |
| F3 | Medium | Stage 0 baseline captures dirty-file *expectations* but not an executed **incremental / `update-index` re-index** baseline over the corpus. The plan's verification gate names "incremental-index regressions," so a captured incremental baseline strengthens the Stage 1 kernel. | **Accepted gap** — add an incremental re-index baseline in Stage 1; dirty-file expectations already recorded in `behavior/degradation-expectations.json`. |
| F4 | Medium | Today both regex **and** tree-sitter emit `parser_mode: "full"` (ground truth). Structural (tree-sitter) and heuristic (regex) tiers are **output-indistinguishable**. ADR-046's authority ladder requires them separated. | **Named intentional future difference** — Stage 2 owns the structural/heuristic split; recorded so it is not mistaken for a regression. |
| F5 | Low | Residual code-vs-ADR-046 gap: regex facts still project `parser_mode: "full"` (not `heuristic`/`fallback`). This is expected — Stage 6 owns the switch — and there is **no active conflicting document-level rule** (see Q9). | **Resolved / no action.** Confirmed no conflicting active parser-authority rule remains across ADR-036/046/047 and plans/007. |
| F6 | Low (advisory) | Stages 1–2 introduce five new namespaces (catalog, planning, execution, arbitrator, freshness) before the first external provider. Consider collapsing catalog+planning until a second real provider exists (echoing plans/007 Decision 10 "data first, protocol later"). | **Deferred (advisory)** — the plan's data-first-registry defense is acceptable; not blocking. |

Supporting evidence for F1 (ground truth, current extractor, default opts):

- `example.OrderService#handle(String order)` → `method_signature_key
  "Stringorder"`, `unit_id … $arity1$sig5e75e42b`.
- `example.OrderService#handle(String order, int retries)` → `"Stringorder,intretries"`,
  `… $arity2$sig5902c043` (overloads correctly distinct).
- `example.Validator#validate(String order)` → `"Stringorder"`, `sig5e75e42b`
  — **byte-identical signature hash to `handle(String)`**. This confirms a
  hash-only merge key would be unsafe; the plan already mandates
  owner+symbol+path in the key, so the design is sound on this point and the
  fixture locks it in.

### F1 Resolution — Variant C (precision-aware overload identity)

Owner decision (2026-08-03): adopt **Variant C**. The `signature_key` stops
being one fixed string that every provider must reproduce. Instead
`overload_identity` becomes a precision-tagged value, and each tier commits only
to what it can honestly know.

```clojure
;; heuristic tier (regex / tree-sitter): knows arity only
{:arity 1 :signature_precision "arity_only" :signature_key nil}

;; exact tier (SCIP / LSP): knows precise parameter types
{:arity 1 :signature_precision "typed" :signature_key "java.lang.String"}
```

The canonical key splits into two layers:

- **core key** = `(language, path, fact_kind, owner, symbol, arity)` — every
  provider can produce it;
- **refinement** = the typed parameter signature — added only by the exact tier.

**Merge semantics.** Facts are grouped by core key.

1. *Common case (distinct arities, or a single method per arity — the whole
   protected corpus).* `handle(String)` = arity 1 and `handle(String, int)` =
   arity 2 have unique core keys. The regex arity-only fact and the SCIP typed
   fact land in the same group and merge trivially; no guessing occurs.
2. *Hard case (same-arity overloads, e.g. `handle(String)` vs `handle(int)`,
   both arity 1).* The core key collides. The exact tier still separates them by
   type; the heuristic tier cannot attribute its two arity-only facts to a
   specific typed overload. Arbitration must then apply an explicit rule (F1a):
   surface `arity_ambiguous` heuristic coverage rather than silently pick, or
   align by deterministic source-order ordinal. Variant C **isolates** this case
   and makes it explicit; it does not pretend a signature hash solved it.

**Why C over A/B.** Variant A (simple types, drop names) forces the exact tier
to *down-convert* `java.lang.String` → `String`, which itself collides
(`java.util.List` vs a local `List` → `List`), i.e. it degrades good data to
match weak data. Variant B (FQ + param names) cannot match SCIP/LSP monikers
(type-only, no names) and is unstable under parameter rename; FQ resolution at
the regex tier is heuristic (wildcard imports, implicit `java.lang`, type vars)
and would produce *wrong* keys, which the plan forbids ("reject/degrade when it
cannot produce a canonical key without guessing"). C keeps the exact tier at
full precision and lets the heuristic tier commit only to arity.

**Stage 1 consequence — unit identity re-anchoring.** Today `unit_id` embeds a
typed signature hash (`…$arity1$sig5e75e42b`). Under C a regex-only repository
has no typed hash, and later attaching SCIP must not change existing `unit_id`s
(that would break snapshots, retrieval refs, and relations). Therefore Stage 1
must anchor stable unit identity on the **core key** `(owner, symbol, arity[,
same-arity ordinal])` and treat the typed signature as **refining evidence**,
not as part of the primary id. This is cleaner than today's hash-in-id but is a
deliberate identity-schema change that the Stage 1 in-memory/PostgreSQL
round-trip gates must cover.

### Answers To The 11 Required Review Questions

1. **Per-operation authority vs whole-file?** Necessary. LSP can be exact for
   definitions/references yet lack a complete batch call hierarchy; SCIP can be
   exact for references yet miss a live-overlay operation. A single-winner
   whole-file model (plans/007 Decision 9 V1) cannot express "SCIP exact for
   refs + tree-sitter for call structure." Agree with the plan.
2. **SCIP and LSP as freshness/mode-dependent peers?** Yes; ADR-046's
   arbitration section models this correctly (batch-clean prefers SCIP; live/dirty
   matching version prefers LSP; agreement merges; equal+contradictory ⇒
   ambiguity). Agree.
3. **Is the source-identity rule sufficient to prevent stale exact facts?**
   Directionally yes, but granularity is unspecified — see F2.
4. **Does `CanonicalFactKey` normalize across spellings without collapsing
   distinct overloads/re-exports/dispatch?** Structurally yes for
   owner+symbol+path+arity; **not yet** for `signature_key` — see F1. Distinct
   overloads and the alias/origin re-export split are proven distinct by the
   identity fixtures.
5. **Does `FactEvidence` need a public contract now?** No. Keep it internal;
   `parser_mode` remains the compatibility projection through the shadow stages
   (ADR-024 additive discipline). Agree with the plan.
6. **Does LSP scope avoid a lifecycle manager / nondeterministic batch
   indexer?** Yes. Stage 5 + the High risk fix LSP as a source-validated live
   overlay, SCIP as the reproducible batch source, and "semidx does not
   implement an LSP server." Cancellation/timeout determinism is already a Stage
   5 deliverable.
7. **Are the Stage 0–6 gates sufficient?** Nearly; add an incremental re-index
   baseline (F3). Otherwise retrieval/confidence/storage/relation gates are
   present.
8. **TypeScript first, or reverse to Java?** Keep **TypeScript first**. Both
   lanes are regex-default today; TypeScript's confidence ceiling is lower
   (per-language ceiling: TS `low`, Java `medium`) and its regex brittleness is
   the most observable. Stage 0 toolchain evidence does **not** justify
   reversing. Requires explicit owner confirmation (owner decision #2).
9. **ADR-036 supersession / ADR-047 / plans/007 amendment — no conflicting
   rule?** Verified. ADR-036 is `superseded_by: [ADR-046, ADR-047]` with a clear
   supersession note; its regex-default text is historical only. ADR-046 amends
   plans/007 Decision 9, and plans/007 already reflects the bounded
   multi-provider plan (l.335–349, 73–75, 793–797). ADR-047 retains only the
   tree-sitter toolchain boundary. **No active document-level parser-authority
   rule conflicts.** The remaining gap is code-vs-target (F5), owned by Stage 6.
10. **Simpler design with less machinery?** The per-operation plan is close to
    minimal given exact-authority + deterministic fallback + explicit
    degradation. Only advisory simplification: F6 (defer catalog/planning split).
11. **Do provider ids / native payloads leak into plans/019 one-shot /
    rendering?** Not by design — the plan forbids branching on provider ids in
    the one-shot orchestrator/renderer and keeps provider-native detail out of
    the public retrieval contract. No implementation exists yet; this is a
    guardrail to enforce at the Stage 6 / plans-019 integration.

### Implementation-Readiness Recommendation

**Proceed after named revisions.** Specifically, Stage 1 must not begin until
owner decision #1 (canonical `signature_key` form, F1) and owner decision #2
(confirm TypeScript-first) are recorded, and the `CanonicalFactKey` contract +
identity fixtures are approved. Until then Stage 1 is **deferred**.

### Decisions Requiring Owner Approval

1. **Canonical `signature_key` form for Java overloads (F1).**
   **[RESOLVED 2026-08-03 → Variant C.]** Precision-aware `overload_identity`:
   heuristic tier commits `arity_only`, exact tier adds the `typed` signature;
   unit identity re-anchors on the core key. Residual **F1a** (same-arity
   arbitration rule) is delegated to Stage 1 design, not the owner.
2. **Confirm TypeScript as the first SCIP vertical slice** (plan Execution
   Admission; reports/022 gate).
3. **Approve the `CanonicalFactKey` normalization contract and the Stage 0
   identity fixtures** as the admission baseline.
4. **Accept the intentional `parser_mode`/confidence reduction** for regex-only
   repositories (F3/F4) as a planned Stage 6 change, subject to replay evidence.

## Verification

Stage 0 changed no production source (documentation, baseline, and test
fixtures only), so verification targets fixture integrity and the repo gate:

- **JSON validity** of all five new fixtures under
  `fixtures/provider-authority/`: **pass** (`python3 -m json.tool`).
- **`clojure -M:test`**: **289 tests, 1947 assertions, 0 failures, 0 errors** —
  unchanged from the reports/022 baseline; the new fixtures are not auto-consumed
  by any failing test.
- **`./scripts/validate-contracts.sh`**: **ok** (70 JSON files checked); no
  contract schema/example was touched.
- **`git diff --check`**: clean (no whitespace errors).
- **English-only scan** over the new/edited files: no Cyrillic.
- **Ground-truth capture** used the project nREPL (`clojure -M:nrepl`) driving
  `semidx.runtime.languages.{java,typescript}/parse-file`, and the semidx MCP
  retrieval/impact surfaces on a corpus index. All asserted identity/baseline
  values in the fixtures are captured from real runtime output, not guessed.
- **Not run (not applicable)**: full migration gate (semantic-quality report,
  protected retrieval replay, snapshot-diff parity, PostgreSQL round trips) —
  these gate later stages that change extraction; Stage 0 changes none.
- **Limitation**: SCIP/LSP provider spellings in the identity fixtures are
  representative, not verified against installed SCIP/LSP tools; Stage 3/5 must
  re-verify. Latency and snapshot size are recorded as observational, not
  deterministic gates.

## NextStageRoutingRecommendation

```text
completed_stage: 0 — Independent Review And Compatibility Baseline
recommended_next_stage: DEFER Stage 1 (Evidence Model And Arbitration Kernel)
recommended_executor: Claude Code team lead (Claude Code v2.1.212+), no Fable, no Explore agent
recommended_model: Claude Opus 4.8 Thinking (plan default Opus 4.6 is superseded by owner authorization)
effort: high
effort_justification: CanonicalFactKey normalization, same-key merge, ambiguity,
  and in-memory/PostgreSQL storage compatibility are correctness-critical
  contracts; Stage 0 surfaced a High-severity identity gap (F1) that Stage 1
  must encode carefully. Matches the plan's Stage 1 routing row.
rationale: Stage 0 is complete and deterministic. F1 (signature_key canonical
  form) is now RESOLVED as Variant C, but TypeScript-first is not yet
  owner-confirmed and the identity contract is not yet owner-approved. Starting
  Stage 1 before owner decision #2 would risk building the SCIP seam in the
  wrong lane.
prerequisites_or_blockers:
  - Owner decision #1: canonical signature_key form — RESOLVED 2026-08-03 (Variant C).
  - Owner decision #2: confirm TypeScript as first SCIP vertical slice (OPEN).
  - Owner approval of the CanonicalFactKey (Variant C) contract + identity fixtures (OPEN).
  - Stage 1 must encode: precision-aware overload_identity, core-key unit
    identity re-anchoring, and the F1a same-arity arbitration rule.
  - ADR-046 and ADR-047 accepted (DONE).
  - ADR-036 supersession + plans/007 amendment documented (DONE; verified, no conflict).
file_ownership_and_conflict_risk: LOW. Stage 0 touched only
  fixtures/provider-authority/** and reports/024. It did NOT touch SPEC.md,
  MEMORY.md, plans/020, reports/021, or reports/023 (plans/020 Stage 0 owned
  files), so there is no cross-plan file conflict.
fallback_executor_or_model: Claude Sonnet 5 for mechanical fixture upkeep only;
  NOT for the signature_key/arbitration identity decisions.
model_availability_checked_at: 2026-08-03
confidence: high (that Stage 1 must be deferred pending the two owner decisions)
```

Stage 0 recommended deferring Stage 1. The owner subsequently lifted the gate
(2026-08-03): TypeScript is confirmed as the first vertical slice and Variant C
+ the identity fixtures are approved as the admission baseline. Stage 1 then
started; its record follows.

---

# Stage 1 — Evidence Model And Arbitration Kernel

## Execution Record

- **Executor**: Claude Code team lead (v2.1.212), no Fable, no Explore agent.
- **Model**: Claude Opus 4.8 Thinking, high effort (matches the plan's Stage 1
  routing row: `CanonicalFactKey`, ambiguity, and identity are
  correctness-critical). Development was REPL-driven via the project nREPL.
- **Admission**: owner confirmed TypeScript-first and approved the Variant C
  `CanonicalFactKey` contract + Stage 0 identity fixtures.

## Scope

Additive and default-off. Commit boundary per the plan: **evidence contracts
and pure arbitration only.** No default extraction, storage schema, or transport
changed.

## Deliverables

New pure namespace `src/semidx/runtime/fact_arbitration.clj`:

- `fact-schema-version`, the ADR-046 authority ladder
  (`exact > structural > heuristic > fallback`), freshness vocabulary, and the
  fact-kind / signature-precision vocabularies.
- Provider-neutral **CanonicalFactKey** with the Variant C precision-aware
  overload identity. Unit identity anchors on the core key
  `(language, path, owner, symbol, dispatch_identity, arity, ordinal)`; the typed
  signature is a refinement, not part of the core key. Relation keys mirror
  ADR-039 / `semidx.runtime.relations` identity fields. Identity is a
  content-addressed hash (`canonical-fact-key-id`) using the same
  `canonical-value` + SHA-1 discipline as `relations.clj`.
- **FactEvidence** normalization + validation. Provider-native ids/symbols are
  retained as evidence only, never in the key. ADR-046 rule enforced:
  `exact` authority requires fresh source identity (`freshness=exact`), else a
  structured `:exact-without-fresh-identity` error.
- **Deterministic same-key arbitration** (`arbitrate-facts`): strongest
  authority wins; all evidence retained; lower authority never overwrites
  higher.
- **F1a same-arity rule** implemented: `<=1` distinct typed signature in a core
  group merges to one fact whose `fact_identity` equals the core key id (so a
  regex-only unit keeps its identity when SCIP/LSP attach later — the Variant C
  invariant); `>=2` distinct typed signatures split into distinct canonical
  facts, and any unattributable arity-only evidence surfaces an
  `:arity_ambiguous_heuristic` diagnostic instead of being silently merged.

## Verification

- **`clojure -M:test`**: **302 tests, 1997 assertions, 0 failures, 0 errors**
  (was 289/1947 at Stage 0; +13 tests in
  `test/semidx/runtime/fact_arbitration_test.clj`).
- **REPL** (`clojure -M:nrepl`) confirmed, before the suite run: 4-provider
  merge → one exact typed fact with all evidence retained; distinct arities and
  distinct owners never collide; same-arity typed overloads split; arity-only
  evidence under same-arity overloads yields the F1a diagnostic; the Variant C
  identity-stability invariant holds; arbitration is order-independent across
  reverse + 20+ shuffles; `exact+stale` evidence is rejected.
- **`git diff --check`**: clean. **English-only**: no Cyrillic.
- **Existing snapshots remain readable**: no storage schema changed; the full
  suite including `semidx.runtime.storage-test` is green.

## Deferred (named honestly)

- **FactEvidence → snapshot payload + PostgreSQL projection round-trip.** The
  kernel is pure and its output is plain serializable data, but nothing emits
  persisted FactEvidence yet. Wiring evidence into the snapshot payload belongs
  with the Stage 2 provider seam (when a provider first produces facts); adding
  an unused persistence path now would be speculative. Existing snapshot
  readability is already preserved (no schema change).
- **`FactBatch` framing** beyond "a collection of facts" — the per-provider
  batch envelope (source identity, coverage, diagnostics) lands with the Stage 2
  provider execution orchestrator that produces batches.

## NextStageRoutingRecommendation

```text
completed_stage: 1 — Evidence Model And Arbitration Kernel (pure kernel + tests)
recommended_next_stage: Stage 2 — Provider Plan And Legacy Adapter Shadow Path
recommended_executor: Claude Code team lead (v2.1.212+), no Fable, no Explore agent
recommended_model: Claude Sonnet 5 (plan default Sonnet 4.6, updated), with the
  FactEvidence-persistence sub-task escalated to Opus 4.8 if identity/round-trip
  parity proves tricky
effort: medium
effort_justification: Stage 2 is a bounded implementation behind a default-off
  seam (data-first catalog, ProviderPlan, execution orchestrator, tree-sitter +
  regex adapters wrapping the existing parse-file facade). It reuses the Stage 1
  kernel rather than designing new correctness-critical identity contracts. The
  one careful sub-task — persisting FactEvidence in the snapshot payload with
  in-memory + PostgreSQL round-trip parity — may warrant a high-effort spike.
rationale: The pure kernel and identity contract are proven and tested. Stage 2
  wires providers through the seam in shadow mode without changing default
  output, which is lower correctness risk than Stage 1.
prerequisites_or_blockers:
  - Stage 1 kernel merged (this commit).
  - Stage 2 must keep default output byte-identical (shadow only) and classify
    regex evidence as heuristic, never exact (ADR-046).
  - Carry forward the FactEvidence→snapshot persistence + PG round-trip
    deliverable listed under "Deferred" above.
file_ownership_and_conflict_risk: LOW-MEDIUM. Stage 1 touched only
  src/semidx/runtime/fact_arbitration.clj and its test. Stage 2 will touch the
  provider seam and the file-indexing path (index.clj / adapters.clj); no
  overlap with plans/020-owned files.
fallback_executor_or_model: Claude Opus 4.8 for the persistence/identity
  round-trip sub-task; Sonnet 5 for the bounded orchestrator/adapters.
model_availability_checked_at: 2026-08-03
confidence: high (kernel is solid; Stage 2 is a bounded seam over it)
```

---

# Stage 1 Completion (2026-08-28)

## Why this section exists

Stage 1 was recorded as delivered on 2026-08-03, but three of the plan's own
Stage 1 deliverables were not met. This session closed them rather than carrying
them into Stage 2 as the earlier handoff proposed.

| Plan deliverable | State on 2026-08-03 | Now |
| --- | --- | --- |
| "Additive FactEvidence and **FactBatch** normalization" | FactEvidence only; FactBatch deferred to Stage 2 | delivered |
| "**In-memory and PostgreSQL round-trip coverage**" | deferred to Stage 2 | delivered |
| Exit criterion: cross-provider golden parity for Java overloads and TypeScript re-exports | fixtures existed but no test read them; the test data was a hand copy | fixtures are executed as goldens |
| "Property-style tests proving registration and completion order do not change merged output" | delivered (`arbitration-is-order-independent`) | unchanged |
| "Additive multi-source relation evidence compatible with ADR-039" | delivered | extended with the fixture's re-export relation |

The parity gap was the sharpest of the three: `fact_arbitration_test.clj`
mirrored the Stage 0 identity fixtures as inline literals, so a correction to a
fixture could not fail a test. Parity that cannot be executed is not parity, and
the plan gates the first external provider slice on it.

## Delivered

- **FactBatch** in `src/semidx/runtime/fact_arbitration.clj`:
  `normalize-fact-batch`, `fact-batch-errors`, and `arbitrate-batches`. A batch
  is the provenance envelope around one provider run — provider identity, source
  identity, freshness, coverage, diagnostics — and fills in a fact's provenance
  only where the fact left it unset, so an envelope can never restate a fact's
  authority. Batch errors name the offending fact and evidence index; an invalid
  batch contributes no facts but stays visible in the result, so a provider that
  failed is distinguishable from one that legitimately found nothing.
- **Executable golden parity**: the tests now read
  `fixtures/provider-authority/identity/*.json` and assert the kernel against
  them — one merged fact per provider set, core key equal field by field, the
  exact tier's typed refinement winning without changing identity, every
  provider's evidence retained, and each fixture's distinct facts keeping
  distinct keys. The TypeScript fixture is checked in its own shape: every
  provider's native re-export moniker resolves to the one origin key, the
  re-export relation keys on ADR-039 identity, and an alias export never
  collapses into the origin unit.
- **Round-trip coverage**: EDN round trip of the arbitration output, a JSON round
  trip proving serialization does not change what facts identify, and a
  PostgreSQL `jsonb` round trip gated on `SEMIDX_TEST_POSTGRES_URL`.

## Fixture change (additive, claims unchanged)

The `distinct_facts_must_not_merge` entries in both identity fixtures carried
their claim in prose only (`fact`, `reason`), with no structured owner, symbol,
or path, so they could not be executed. Each entry gained an
`expected_canonical_key` that restates the same claim in machine-readable form,
and both fixtures record the change in their `notes`. No claim was altered and
no expectation was weakened. Their `status` moved from
`specification_for_stage_1` to `golden_executed_by_stage_1_tests`.

## Verification

- `clojure -M:test`: **456 tests, 2636 assertions, 0 failures, 0 errors**
  (was 447 / 2579 before this session's Stage 1 work; the arbitration namespace
  went from 15 to 22 tests).
- `clojure -M:test` with `SEMIDX_TEST_POSTGRES_URL` against a throwaway
  PostgreSQL 17.7 cluster: 456 tests, 2652 assertions, 1 failure — the
  pre-existing `semidx.integration.runtime-test/postgres-storage-roundtrip-test`
  documented in `reports/021`, which reproduces on a clean tree and is unrelated
  to this work. The new fact round-trip test passed: identities, authorities,
  and evidence counts survive `jsonb` unchanged.
- `./scripts/validate-contracts.sh`: `contracts_validation=ok`, 72 JSON files.
- Both identity fixtures re-validated as JSON. `git diff --check`: clean.
  English-only scan: no Cyrillic.

## Exit criteria check (plan Stage 1)

- Same semantic fact from multiple providers produces one canonical key and one
  identity; provider-native ids remain evidence — **checked against the
  fixtures**, not only against inline test data.
- Java overloads, TypeScript re-exports, and dispatch-sensitive identities have
  cross-provider golden parity before any external provider slice — **met**.
- Lower authority cannot overwrite higher authority — covered.
- Equal-authority contradictions are observable — covered by the F1a
  `:arity_ambiguous_heuristic` diagnostic.
- Existing snapshots remain readable — no storage schema changed; the full suite
  including the storage tests is green.

Commit boundary respected: evidence contracts and pure arbitration only. No
default extraction, storage schema, or transport changed.

## NextStageRoutingRecommendation

```text
completed_stage: 1 — Evidence Model And Arbitration Kernel (now complete against
  the plan's own deliverables, including FactBatch and round-trip coverage)
recommended_next_stage: Stage 2 — Provider Plan And Legacy Adapter Shadow Path
recommended_executor: Claude Code team lead, no Fable, no Explore agent
recommended_model: Claude Sonnet 5, escalating to Opus 4.8 for the snapshot
  persistence sub-task if identity parity proves tricky
effort: medium
effort_justification: Stage 2 is bounded implementation behind a default-off
  seam (data-first catalog, ProviderPlan, execution orchestrator, tree-sitter and
  regex adapters wrapping the existing parse-file facade). It consumes the Stage 1
  kernel instead of designing new identity contracts. The care is in keeping
  default output byte-identical and classifying regex evidence as heuristic.
rationale: The identity contract is now proven against the committed goldens and
  survives serialization, so the seam can be wired without the risk that
  persistence or provider spelling changes what a fact identifies.
prerequisites_or_blockers:
  - Stage 2 must keep default output byte-identical (shadow only) and never
    classify regex evidence as exact (ADR-046).
  - The FactEvidence-in-snapshot-payload wiring is now unblocked: the kernel's
    output is proven round-trippable through jsonb, so the remaining work is the
    payload shape, not the identity question.
  - Stage 2 owns FactBatch production; the normalization and validation it must
    satisfy already exist here.
file_ownership_and_conflict_risk: MEDIUM. Stage 2 touches the provider seam and
  the file-indexing path (index.clj / adapters.clj). No overlap with the paused
  plans/020 files.
fallback_executor_or_model: Sonnet 5 for the orchestrator and adapters; not for
  the shadow-parity gate.
model_availability_checked_at: not checked in this session.
confidence: high
```
