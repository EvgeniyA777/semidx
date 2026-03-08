# ADR-016: Publish Concrete Query and Diagnostics Examples as Canonical Reference

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-009` зафиксировал structured host query contract.  
`ADR-013` зафиксировал concrete diagnostics and event schema.  
`ADR-015` зафиксировал override and human-review policy.

После этого нужен следующий шаг: не только описать contracts словами, но и зафиксировать canonical examples.

Без этого появятся проблемы:

- разные implementers будут по-разному читать одну и ту же prose-form decision;
- schema contracts будут “понятны в целом”, но не operationally unambiguous;
- fixture authors и integration authors начнут придумывать свой формат примеров;
- hosts будут сериализовать query и diagnostics slightly differently, пока расхождения не накопятся.

Нужно принять решение:

- должны ли canonical examples считаться частью архитектурного контракта;
- какие примеры обязательны;
- как соотнести examples с prose ADRs and future schemas.

---

## Decision Drivers

- Decision completeness for implementers
- Shared understanding across host integrations
- Faster onboarding and contract adoption
- Lower ambiguity in tests, fixtures and docs
- Better alignment between prose ADRs and actual payload shapes

---

## Considered Options

### Option 1. Prose ADRs only

Ограничиться текстовыми ADR без canonical examples.

### Option 2. Canonical examples as reference artifacts

Поддерживать curated example set for host queries, diagnostics traces, events, confidence and guardrail outputs.

### Option 3. Schemas only, no examples

Зафиксировать только formal schemas, без reference examples.

---

## Decision

Мы принимаем **Option 2: Canonical examples as reference artifacts**.

Concrete examples должны считаться частью архитектурного reference layer наряду с ADR prose.

### Core rule

Если ADR задает внешний contract, то должен существовать хотя бы один canonical example showing intended shape and semantics.

---

## Required Example Families

Минимальный canonical example set должен включать:

- host query examples
- context packet examples
- diagnostics trace examples
- stage event examples
- confidence examples
- guardrail examples
- override/review examples

---

## Host Query Examples

Нужны как минимум examples для:

- symbol-target retrieval
- diff-centered retrieval
- bug investigation query
- test-targeting query
- soft-hint usage
- hard-constraint usage
- explicit override request

Examples должны показывать:

- minimal valid query
- rich query with hints/options
- invalid or contradictory query cases for validation docs

---

## Diagnostics Trace Examples

Нужны как минимум examples для:

- successful high-confidence retrieval
- partial-parser degraded retrieval
- stale-sensitive retrieval
- raw-code escalation path
- blocked autonomy posture
- override + human review flow

Эти examples должны быть bounded and redacted-safe by default.

---

## Event Examples

Нужны examples для canonical stage events:

- `query_validation.completed`
- `candidate_generation.degraded`
- `ranking.completed`
- `raw_code_fetch.skipped`
- `result_finalization.completed`
- `override.requested`
- `human_review.required`

Это зафиксирует intended event vocabulary operationally.

---

## Confidence and Guardrail Examples

Нужны at least paired examples:

- `high` confidence + `draft_patch_safe`
- `medium` confidence + `plan_safe`
- `low` confidence + `autonomy_blocked`
- partial/fallback retrieval with downgrade reasons
- stale retrieval with warning/degradation examples

Примеры должны показывать, как `reasons`, `warnings`, `missing_evidence`, `blocking_reasons` and `risk_flags` реально выглядят.

---

## Example Governance Rule

Examples не должны быть случайными snippets.

### Required metadata

Каждый canonical example должен иметь:

- example id
- purpose
- contract family
- schema/ADR references
- expected interpretation notes

### Required principle

Examples должны иллюстрировать intended semantics, а не случайную implementation artifact shape.

---

## Relationship to Formal Schemas

Examples не заменяют schemas, а дополняют их.

### Required rule

- ADR prose explains intent and boundaries
- schemas validate structure
- examples show intended practical usage

Ни один из этих трех слоев не должен считаться достаточным в одиночку.

---

## Stability Rule

Canonical examples должны эволюционировать дисциплинированно.

### Required behavior

Если breaking contract change меняет intended payload meaning or shape:

- example set must be updated;
- affected example ids or versions must be changed where needed;
- benchmark/fixture expectations should reference updated examples.

Examples не должны silently drift from prose ADR meaning.

---

## Boundedness and Safety Rule

Examples должны следовать safety defaults.

### Required behavior

По умолчанию examples должны быть:

- redacted-safe
- bounded in size
- free of real secrets or proprietary payloads
- representative without full code dumps

Debug-expanded examples допустимы как отдельная category, but never as only examples.

---

## Why This Shape

Такой reference layer нужен, чтобы:

- превратить prose ADRs в implementable contracts;
- снизить ambiguity between teams and hosts;
- упростить создание fixtures and docs;
- сделать contract evolution measurable and reviewable.

---

## Prohibitions

- External contract ADRs **MUST NOT** жить only as prose if examples are needed for interpretation.
- Examples **MUST NOT** silently diverge from current ADR meaning.
- Canonical examples **MUST NOT** contain unsafe default payloads.
- Implementers **MUST NOT** be forced to infer intended payloads from schemas alone.

---

## Consequences

### Positive

- Integrations become easier and less ambiguous.
- Schemas and benchmarks gain better grounding.
- Contract review becomes faster.
- Host developers get copy-near references instead of prose-only guidance.

### Negative

- Example corpus requires maintenance.
- Breaking changes now touch prose + schema + examples.
- Teams may initially underinvest in example quality.

### Tradeoff accepted

Мы сознательно выбираем **examples as first-class reference artifacts** вместо более дешевого, но неоднозначного prose-only contract model.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Each major external contract family has canonical examples.
2. Examples cover normal, degraded and override/review scenarios.
3. Examples are bounded, safe and redacted by default.
4. Examples are version-aligned with ADR/schemas.
5. Implementers can infer intended payload semantics without guessing.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- release quality gates;
- concrete schema files and example corpus layout;
- documentation generation and contract review workflow.

