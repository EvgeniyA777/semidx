---
title: "Graph decision model: typed probabilistic decisions over graph candidates"
doc_type: "idea"
lifecycle: "concept"
status: "draft"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-29"
---

# 003: Graph Decision Model

## Source

An external conversation, reviewed on 2026-09-29, about TypeSafe Jev and the
emerging family of "decision models" (models that return typed probabilities for
a closed set of candidates instead of generating text). The conversation is kept
as local source intake and is not committed. Its claims about third-party
projects were partly checked later; see [External Claims](#external-claims).

This idea records what from that conversation is compatible with semidx, what
is not, and what would have to be measured first. It is not a plan and
authorizes no work. "Graph decision model" and "decision model" are terms local
to this idea, not project vocabulary.

## The Idea As Proposed

1. A decision model receives graph state and a closed candidate set (for
   example, possible targets of an unresolved call) and returns a probability
   per candidate plus `UNKNOWN`.
2. A policy maps the probability to a graph action: accept the edge above a
   high threshold, record a "speculative" edge in a middle band, leave the claim
   unresolved otherwise.
3. A model-agnostic layer wraps providers (hosted Jev, a local runtime such as
   Ollaya, a locally trained model such as Jeff): a neutral request/result
   contract, providers as configuration, run modes `SINGLE`, `SHADOW`
   (log-only comparison), and `COMPARE`, per-task calibration, a policy kept
   outside providers, and a decision journal for replay and model selection.
4. Training data comes for free from call sites the symbolic resolver already
   resolves: hide part of the deterministic context and train the model to
   recover the known target.

## Constitutional Assessment

| Proposal | Governing text | Assessment |
| --- | --- | --- |
| Accept a model-selected edge as a relationship above a threshold | [Constitution](../../ARCHITECTURE_CONSTITUTION.md) §1: an approximate mechanism "must never establish a program relationship"; §3: confidence-based knowledge is approximate and must never become indistinguishable from a fact | **Not admissible.** No ADR can admit it; §18 requires a fork. |
| Model as "resolver" of ambiguity while the graph stays the source of truth | §1, §7 | Contradictory: the component that decides which relationship exists is the authority. Not admissible in that role. |
| "Speculative edge" recorded in the graph | §3 permits approximate assertions that stay distinct and attributed; [ADR 013](../adr/013_optional_jev_ranking_projection.md) Consequences state that unresolved-target resolution is not permitted by that record | **Open.** Whether any model output may be written as an `approximate` assertion needs its own ADR answering §11. Not decided here. |
| Hosted model called during indexing or reanalysis | §8: building and updating the graph must not require transmitting source-derived data | Not admissible on the write path. Consumer-side use only, with explicit consent. |
| Model results inside reconciliation | §5, and the principle in [Follow-up 020](../followups/020_java_external_supertype_leaves_the_chain_open.md) that a result must not depend silently on the machine that ran the index | Graph content would depend on model, version, and network availability. |
| Identity correspondence (`ENTITY_SAME_AS`) decided by a model | §4: heuristic identity evidence must not be presented as an established fact | Approximate only, and only after a decision record. |
| Decision journal storing inputs | [MEMORY.md](../../MEMORY.md): no persistence; ADR 013: no persistent audit store; inputs are source-derived | Needs its own storage and consent decision. |
| Moving model alias (`jev-latest`) | ADR 013 D2 rejects moving aliases | Conflicts with the accepted direction of ADR 013. |
| Local runtime over plain `http://localhost` | ADR 013 D2 requires an operator-named HTTPS endpoint for the TypeSafe service | Needs a revised or new decision record. |

## What Is Compatible

- **Consumer-side ranking over graph candidates.** ADR 013 already defines
  this shape: a provider-neutral `rank(query, candidate_cards)` contract, a
  deterministic fake provider, request-local ordinals (`candidate_0`) instead of
  entity ids, results labelled `approximate_projection`, and no write access to
  the graph. A generalized request/provider/engine layer is justified only when
  a second real task exists, not in advance.
- **`UNKNOWN` in every candidate set, and "symbolic wins".** A model is asked
  only where the graph has no established answer, and it may always decline.
- **Policy separate from provider; shadow and compare runs; per-task
  calibration.** Confidence values from different models are not comparable
  until calibrated on the same task.
- **A local model runtime.** It avoids outbound transmission (§8) and does not
  depend on TypeSafe access. On 2026-09-29 the operator folded local
  consumer-side ranking into
  [Plan 015](../plans/015_optional_jev_ranking_projection.md) (Stages 4A-4C,
  ADR 013 D2 revised). That covers ranking only; a graph-native decision model
  still needs its own ADR and plan.

## Measurement Before Any Model Work

The proposed training scheme has a distribution problem. Call sites the
resolver already answers are not the cases it leaves unresolved. In Java, the
unresolved remainder is dominated by receiver- and class-qualified calls and by
classes whose supertypes have no indexed source (Plan 013/014 evidence,
Follow-up 020). For many of those, the correct target is not in the graph at
all, so no candidate set can contain it and the only honest answer is
`UNKNOWN`. Accuracy on resolved calls with hidden context does not predict
accuracy on genuinely unresolved calls.

The first question is therefore graph-only and needs no model:

> On a pinned external corpus (apache/dubbo at `df9c5e1`, 118,471 unresolved
> calls in the current baseline), for what fraction of unresolved calls does a
> candidate set the graph can produce contain the true target, established
> independently from source?

If that fraction is small, no decision model can recover useful relationships,
whatever its accuracy.

## Relation To Current Priorities

- By operator decision on 2026-09-29, consumer-side ranking on local open
  models runs first, as [Plan 015](../plans/015_optional_jev_ranking_projection.md)
  Stages 4A-4C, ahead of
  [Plan 017](../plans/017_adoption_baseline_and_priority_selection.md). Its
  evaluation is also the first evidence of whether local decision models order
  graph candidates usefully at all.
- This idea does not fit L2 of the
  [roadmap](../design/001_project_roadmap.md#adoption-levels): L2 exits only
  when previously blocked answers become established relationships, which a
  model output cannot be.
- Plan 017 evidence remains the other entry point: if paired sessions show
  agents repeatedly triaging `unresolved_mentions` candidates, ranking those
  candidates under ADR 013's projection rules becomes a candidate successor.
- Beyond ranking this stays a concept. Promotion requires the measurement
  above, an ADR answering constitution §11, and a plan.

## External Claims

Checked against primary sources on 2026-09-29 (project repositories and
announcements); benchmark numbers are the projects' own and were not reproduced:

- Jeff 1 (Gestalt Lab, [repository](https://github.com/Gestalt-Lab/jeff)):
  Apache-2.0 code and adapter, a LoRA on `Qwen3-4B-Instruct-2507`, local server
  on `http://127.0.0.1:8079` with `POST /v1/systemone`; its README reports
  accuracy 0.8183 versus Jev 1.13.0 at 0.8283 on 9,730 examples.
- Ollaya ([repository](https://github.com/ollaya-dev/ollaya)): Apache-2.0
  local daemon serving open decision models by `name:tag` behind a
  TypeSafe-compatible `/v1/systemone`, default port 11435.
- Decision 1.0 ([announcement](https://vllm-sr.ai/blog/decision-models/)):
  six open-weight models (0.6B-9B), Apache-2.0; no ready System One server.

Not checked: the `winnow:e4b` 0.722 versus Jev 0.738 figure, and the Jev launch
date and "two years in stealth". The Jev API primitives (`Noul`, `Choice`,
`Score`) and the model id `jev-1.13.0` match what ADR 013 already records.
