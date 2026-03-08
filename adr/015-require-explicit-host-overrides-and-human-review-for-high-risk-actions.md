# ADR-015: Require Explicit Host Overrides and Human Review for High-Risk Actions

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-009` зафиксировал structured host query contract with soft hints by default.  
`ADR-011` зафиксировал autonomy guardrails with host-retained final control.  
`ADR-014` зафиксировал benchmark governance for retrieval behavior.

После этого нужен следующий policy-level boundary: как host systems должны обращаться с override paths и human review.

Без такого решения быстро появятся проблемы:

- host systems начнут тихо обходить retrieval guardrails;
- `autonomy_blocked` будет фактически игнорироваться без следа;
- разные интеграции будут по-разному трактовать high-risk actions;
- human review будет то обязательным, то необязательным без явной логики;
- diagnostics потеряют смысл как safety contract, если overrides не формализованы.

Нужно принять решение:

- когда override должен быть явным;
- когда host обязан требовать human review;
- какие действия считаются high-risk;
- как сохранять видимость original library recommendation.

---

## Decision Drivers

- Безопасность semi-auto and full-auto workflows
- Сохранение host control without silent policy bypass
- Совместимость с confidence and guardrail contracts
- Explainability of risky actions
- Auditability of override decisions
- Единое поведение across host systems

---

## Considered Options

### Option 1. Host freedom without formal override policy

Каждый host сам решает, когда игнорировать retrieval guardrails и когда просить human review.

### Option 2. Explicit override path plus required human review for high-risk actions

Host retains control, but risky deviations from library guidance must be explicit, traceable, and subject to human review where required.

### Option 3. Library-enforced hard blocks

Библиотека сама технически запрещает risky actions regardless of host policy.

---

## Decision

Мы принимаем **Option 2: Explicit override path plus required human review for high-risk actions**.

### Core rule

- Host retains final execution control.
- But any material deviation from library safety posture must be explicit.
- High-risk action classes must require human review by default.

Библиотека не hard-blocks workflow physically, но architecture требует, чтобы host systems не обходили risk signals silently.

---

## High-Risk Action Classes

Host systems должны считать high-risk как минимум следующие action classes:

- applying multi-file code changes
- applying changes under `autonomy_blocked`
- applying changes with `low` confidence
- applying changes under stale/degraded retrieval conditions
- applying changes when target localization remains ambiguous
- applying changes after full-file fallback retrieval without strong structural anchoring

### Why this matters

Не любой patch drafting равен одинаковому риску.  
Нужна минимальная canonical classification, чтобы host systems не делали unsafe equivalence.

---

## Human Review Rule

Human review должен быть required by default для high-risk actions.

### Required default cases

Human review обязателен, если одновременно верно хотя бы одно из условий:

- `autonomy_posture = autonomy_blocked`
- confidence = `low`
- `allowed_action_scope` excludes autonomous apply
- `risk_flags` contain broad-impact or ambiguity signals
- host override weakens library recommendation for a risky action

### Permissible lower-risk path

Host может не требовать human review для narrower cases only if:

- `autonomy_posture = draft_patch_safe`
- confidence not downgraded by major warnings
- action scope remains bounded to selected target
- host policy explicitly allows such autonomy

---

## Explicit Override Rule

Override должен быть first-class policy event, а не скрытый implementation detail.

### Required fields for an override record

Минимально override record должен содержать:

- `override_id`
- `trace_id`
- `original_autonomy_posture`
- `original_blocking_reasons`
- `requested_action`
- `override_reason`
- `actor_id` or initiating principal
- `human_review_status`
- `timestamp`

### Meaning

Override record нужен даже если host ultimately proceeds.  
Он фиксирует, что host пошел против baseline recommendation knowingly.

---

## No Silent Promotion Rule

Host system не должен silently повышать allowed autonomy.

### Disallowed behavior

Нельзя неявно делать:

- `autonomy_blocked -> draft_patch_safe`
- `plan_safe -> auto-apply`
- `low confidence -> proceed as if high confidence`

без explicit override semantics and trace.

### Required behavior

Если host усиливает permissiveness, это должно:

- отражаться в diagnostics/telemetry;
- сохранять original library posture visible;
- при high-risk action trigger human review requirement by default.

---

## Original Recommendation Preservation Rule

Library recommendation must remain visible even after override.

### Required rule

Host system может принять другое решение, но:

- original `confidence`
- original `guardrail_assessment`
- original `blocking_reasons`

не должны исчезать из diagnostics history or event traces.

Иначе override размывает auditability и делает postmortem impossible.

---

## Scope-Limited Override Rule

Override должен быть scoped, not blanket.

### Allowed scope examples

- allow raw-code escalation to enclosing unit only
- allow draft patch on selected unit only
- waive test-adjacency requirement for this request
- allow degraded retrieval for exploratory planning only

### Disallowed scope examples

- “ignore all guardrails for this session”
- “always auto-apply when any patch exists”
- blanket disablement of human review for all ambiguous cases

Architecture должна поощрять narrow exceptions, а не global bypasses.

---

## Human Review Outcome Rule

Human review itself должен быть represented clearly if host tracks it.

### Minimum review states

- `required_pending`
- `approved`
- `rejected`
- `waived_by_policy`

### Required behavior

Если risky action executed without human review, system должна уметь объяснить why:

- approved exception path;
- lower-risk classification by policy;
- explicit waiver.

---

## Integration with Diagnostics and Telemetry

Override and review events должны встраиваться в observability contract.

### Required diagnostics visibility

Diagnostics should show:

- original posture
- override applied or not
- review required or not
- review status
- rationale summary

### Required event examples

- `override.requested`
- `override.approved`
- `override.rejected`
- `human_review.required`
- `human_review.approved`
- `human_review.rejected`

These events complement, not replace, retrieval stage events.

---

## Host Policy Rule

Библиотека не определяет всю business policy, но хост-политика должна быть at least as strict as baseline safety semantics unless explicitly documented otherwise.

### Required rule

Host systems may be stricter than the library recommendation.

Host systems should not be more permissive than the library recommendation for high-risk actions without:

- explicit override;
- visibility;
- review path where required.

---

## Why This Shape

Такой policy boundary нужен, чтобы:

- сохранить host control;
- не дать overrides silently destroy safety semantics;
- сделать human review a deliberate architectural tool;
- удержать связь между retrieval quality and downstream action safety.

---

## Prohibitions

- High-risk actions **MUST NOT** silently bypass `autonomy_blocked` or `low confidence`.
- Overrides **MUST NOT** erase original library recommendation.
- Blanket “disable all guardrails” behavior **MUST NOT** be the default integration mode.
- Human review requirements **MUST NOT** оставаться implicit for high-risk actions.
- Hosts **MUST NOT** treat successful patch generation as sufficient proof that review is unnecessary.

---

## Consequences

### Positive

- Safety semantics become enforceable at integration level.
- Postmortems and audits become realistic.
- Human review becomes targeted instead of vague.
- Host-specific policy remains possible without chaos.

### Negative

- Integrations need extra policy plumbing.
- Some hosts may consider explicit override tracking cumbersome.
- Human review logic must be maintained consistently.

### Tradeoff accepted

Мы сознательно выбираем **explicit override governance and targeted human review** вместо более удобной, но dangerously silent permissive behavior.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. High-risk actions classified canonically.
2. Risky deviations from library posture require explicit override records.
3. Original retrieval recommendation remains visible after override.
4. Human review is required by default for high-risk permissive actions.
5. Override and review outcomes are observable through diagnostics/events.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- concrete query/examples schema;
- release quality gates and policy exceptions;
- integration examples for human-review workflows;
- retention policy for override and review traces.

