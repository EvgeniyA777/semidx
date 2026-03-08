# ADR-013: Define a Concrete Diagnostics and Event Schema for Retrieval Traces

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-010` зафиксировал, что observability должна быть stage-aware, structured и safe by default.  
`ADR-008` зафиксировал evidence-aware confidence model.  
`ADR-009` зафиксировал host query contract.  
`ADR-011` зафиксировал autonomy guardrails.

После этого нужен следующий шаг: конкретный schema-level contract для diagnostics trace и telemetry events.

Без него быстро возникнут проблемы:

- каждый host будет логировать retrieval по-своему;
- diagnostics trace расползется в ad hoc maps;
- невозможно будет стабильно тестировать observability;
- AI/host consumers не смогут надежно читать warnings, degradations, confidence и guardrail outputs;
- telemetry adapters будут получать несовместимые payloads.

Нужно принять решение:

- каким должен быть canonical diagnostics object;
- каким должен быть canonical stage event object;
- какие поля обязательны;
- как удержать schema bounded и safe by default.

---

## Decision Drivers

- Совместимость между host integrations
- Стабильный contract для diagnostics surface и telemetry surface
- Explainability and machine-readability
- Безопасность и bounded payload size
- Поддержка regression tests и fixtures
- Ясная связь между query, stages, confidence, guardrails и result

---

## Considered Options

### Option 1. Free-form structured maps

Разрешить diagnostics и events быть просто “какими удобно maps”, лишь бы они были JSON/EDN-serializable.

### Option 2. Canonical bounded schema for diagnostics traces and stage events

Зафиксировать единый schema-level contract с обязательными top-level sections, required fields и bounded nested structures.

### Option 3. Telemetry-only schema

Стандартизовать только events/logs, а host-facing diagnostics object не фиксировать.

---

## Decision

Мы принимаем **Option 2: Canonical bounded schema for diagnostics traces and stage events**.

Retrieval subsystem должен иметь:

- один canonical diagnostics trace schema;
- один canonical stage event schema;
- одну bounded naming scheme for stage/event names.

Эти схемы должны быть пригодны:

- для host-facing diagnostics;
- для telemetry adapters;
- для tests and fixtures;
- для later persistence if desired.

---

## Canonical Diagnostics Trace Schema

Каждый retrieval flow должен иметь один canonical diagnostics trace object.

### Required top-level sections

Diagnostics trace должен содержать:

- `schema_version`
- `trace`
- `query`
- `stages`
- `result`
- `warnings`
- `degradations`
- `confidence`
- `guardrails`
- `performance`

### `schema_version`

Нужен для:

- controlled evolution;
- backwards compatibility;
- fixture stability.

### `trace`

Минимально должен содержать:

- `trace_id`
- `request_id`
- `timestamp_start`
- `timestamp_end`
- `host_metadata` as bounded optional object

### `query`

Нормализованная форма входного retrieval query:

- `intent`
- `targets_summary`
- `constraints_summary`
- `hints_summary`
- `options_summary`
- `validation_status`

Здесь должны храниться summaries, а не full raw host payload by default.

### `stages`

Упорядоченный список stage summaries.

Каждый stage summary должен содержать:

- `name`
- `status`
- `summary`
- `counters`
- `warnings`
- `degradation_flags`
- `duration_ms`

### `result`

Bounded summary of retrieval output:

- `selected_units_count`
- `selected_files_count`
- `raw_fetch_level_reached`
- `packet_size_estimate`
- `top_authority_targets`
- `result_status`

### `warnings`

Top-level aggregated warnings across all stages.

### `degradations`

Top-level aggregated degraded conditions across all stages.

### `confidence`

Must mirror canonical confidence contract from `ADR-008`:

- `level`
- `reasons`
- `warnings`
- `missing_evidence`

### `guardrails`

Must mirror canonical guardrail contract from `ADR-011`:

- `autonomy_posture`
- `blocking_reasons`
- `required_next_steps`
- `allowed_action_scope`
- `risk_flags`

### `performance`

Bounded performance summary:

- `total_duration_ms`
- `cache_summary`
- `parser_summary`
- `fetch_summary`
- `budget_summary`

---

## Canonical Stage Event Schema

Telemetry/event surface должен использовать один canonical event object.

### Required fields

Каждый event должен содержать:

- `schema_version`
- `event_name`
- `timestamp`
- `trace_id`
- `request_id`
- `stage`
- `status`
- `summary`
- `counters`

### Optional bounded fields

Допустимы:

- `task_id`
- `session_id`
- `snapshot_id`
- `query_intent`
- `warning_codes`
- `degradation_codes`
- `duration_ms`
- `budget_summary`
- `redaction_level`

### Disallowed event shape

Event не должен по умолчанию содержать:

- full `context packet`
- full raw code payload
- full graph dump
- full host query object
- parser-native dumps

---

## Stage Naming Scheme

Stage names должны быть каноническими и ограниченными.

### Required stage names

Минимальный vocabulary:

- `query_validation`
- `candidate_generation`
- `ranking`
- `context_packet_assembly`
- `raw_code_fetch`
- `result_finalization`

Если какая-то стадия не выполнялась, это должно отражаться в status/summary, а не через произвольные stage names.

---

## Event Naming Scheme

Event names должны строиться как:

`<stage>.<status>`

### Allowed statuses

- `started`
- `completed`
- `degraded`
- `failed`
- `skipped`

### Examples

- `query_validation.completed`
- `candidate_generation.degraded`
- `ranking.completed`
- `raw_code_fetch.skipped`
- `result_finalization.completed`

Это удерживает event vocabulary small and analyzable.

---

## Code and Flag Vocabulary

Warnings and degradations не должны жить как свободный текст only.

### Required rule

Нужны bounded code lists for:

- warning codes
- degradation codes
- blocking reason codes
- risk flag codes

Human-readable text допустим как companion field, но canonical machine contract должен опираться на bounded codes.

### Example categories

- `parser_partial`
- `parser_fallback`
- `symbol_unresolved`
- `stale_projection`
- `budget_restricted`
- `raw_fetch_skipped`
- `impact_broad`
- `target_ambiguous`

---

## Summary vs Payload Rule

Diagnostics trace и events должны содержать summaries, не полные payloads.

### Required behavior

По умолчанию нужно хранить:

- counts;
- ids;
- bounded labels;
- reason codes;
- summarized targets;
- small structural summaries.

Нельзя по умолчанию хранить:

- full diff;
- full prompt-like host query;
- full raw source;
- unbounded evidence lists.

Это удерживает diagnostics safe and portable.

---

## Boundedness Rule

Каждый schema section должен быть bounded in size by design.

### Required behavior

Нужно ограничивать:

- количество top warnings;
- количество degradation entries;
- длину free-text summaries;
- количество top authority targets listed;
- число event-attached codes.

Если полная детализация нужна, она должна идти через separate debug path, а не через default schema expansion.

---

## Redaction Field Rule

Diagnostics and events должны явно указывать redaction posture.

### Required field

Каждый event или trace summary может содержать:

- `redaction_level`

Минимальный vocabulary:

- `default_safe`
- `strict`
- `debug_expanded`

По умолчанию должен использоваться `default_safe`.

---

## Validation Rule

Diagnostics trace и stage events должны валидироваться как contracts.

### Required behavior

Нужно иметь:

- stable schema definition;
- fixture examples;
- validation in tests for canonical outputs;
- explicit schema version bumps for breaking changes.

Иначе observability contract превратится в informal convention.

---

## Why This Shape

Такой schema-level contract нужен, чтобы:

- сделать observability реально reusable;
- поддержать AI/host consumers machine-readable diagnostics;
- упростить telemetry adapters;
- стабилизировать tests and fixtures;
- не дать observability surface расползтись в свободный JSON.

---

## Prohibitions

- Diagnostics trace **MUST NOT** быть ad hoc map without canonical sections.
- Events **MUST NOT** использовать произвольные stage names as default pattern.
- Warnings/degradations **MUST NOT** полагаться only on free-form prose.
- Default diagnostics **MUST NOT** включать full raw code or full query payloads.
- Breaking schema changes **MUST NOT** вноситься без schema version change.

---

## Consequences

### Positive

- Host systems получают стабильный diagnostics contract.
- Telemetry становится проще агрегировать и анализировать.
- Tests and fixtures для observability становятся реалистичными.
- Redaction and boundedness становятся встроенными свойствами, а не пожеланиями.

### Negative

- Понадобится поддерживать schemas and code vocabularies.
- Нужно будет управлять schema evolution дисциплинированно.
- Некоторым integration paths захочется more verbose debug payloads.

### Tradeoff accepted

Мы сознательно выбираем **строгий bounded schema contract для diagnostics/events** вместо более свободного, но быстро деградирующего ad hoc observability layer.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Есть canonical diagnostics trace schema с fixed top-level sections.
2. Есть canonical stage event schema с bounded field set.
3. Stage/event naming follows one small vocabulary.
4. Warning/degradation/guardrail outputs опираются на bounded codes плюс optional readable summaries.
5. Schemas versioned and test-validated.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- retrieval benchmark and fixture policy;
- concrete schema definitions and examples;
- retention/persistence policy for diagnostics traces;
- host override and human-review event semantics.
