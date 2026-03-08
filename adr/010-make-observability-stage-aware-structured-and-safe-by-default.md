# ADR-010: Make Observability Stage-Aware, Structured, and Safe by Default

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-002` зафиксировал `context packet` как основной внешний результат retrieval.  
`ADR-005` зафиксировал structural-first ranking.  
`ADR-006` зафиксировал late raw-code fetch.  
`ADR-008` зафиксировал evidence-aware confidence model.  
`ADR-009` зафиксировал structured host query contract.

После этого системе нужна каноническая observability and diagnostics model.

Без такого решения быстро появятся проблемы:

- retrieval будет сложно дебажить;
- host systems не поймут, почему выбраны именно эти units;
- partial parser/fallback/stale conditions будут плохо видны;
- performance regressions и cache pathologies нельзя будет локализовать;
- autonomous AI consumers начнут действовать по результатам, чью историю получения нельзя восстановить.

Нужно принять решение:

- какие diagnostics библиотека обязана выдавать;
- как должна выглядеть observability across retrieval stages;
- где проходит граница между useful diagnostics и опасной утечкой внутренностей.

---

## Decision Drivers

- Explainability of retrieval behavior
- Debuggability across all retrieval stages
- Correlation with host tasks and sessions
- Safety for AI/autonomous consumers
- Minimal leakage of internals and secrets
- Consistent observability across in-memory and persisted modes
- Возможность работать без обязательного external telemetry backend

---

## Considered Options

### Option 1. Logging only

Библиотека просто пишет текстовые или JSON logs, а host systems сами решают, как это интерпретировать.

### Option 2. Stage-aware structured diagnostics plus telemetry hooks

Библиотека формирует structured diagnostics/events across retrieval stages и умеет отправлять их через optional telemetry adapters.

### Option 3. Minimal observability

Библиотека выдает только итоговый `context packet`, а все промежуточные стадии остаются непрозрачными.

---

## Decision

Мы принимаем **Option 2: Stage-aware structured diagnostics plus telemetry hooks**.

Observability должна быть:

- `stage-aware`
- `structured`
- `safe by default`
- usable even without external telemetry backend

Библиотека должна формировать **канонический diagnostics trace** для retrieval flow и, при наличии adapters, публиковать telemetry events.

---

## Core Rule

Каждый retrieval flow должен быть наблюдаем как последовательность stages, а не как одна непрозрачная функция.

Минимальный stage model:

1. query accepted
2. candidate generation
3. ranking
4. context packet assembly
5. optional raw-code escalation
6. final result emitted

Если в конкретном flow есть дополнительные стадии, они допустимы, но базовые стадии должны оставаться распознаваемыми.

---

## Required Observability Surfaces

Система должна поддерживать две отдельные, но совместимые observability surfaces.

### 1. Diagnostics surface

Возвращаемая или доступная host system structured diagnostics information:

- validation outcomes;
- stage outcomes;
- evidence summary;
- warnings;
- confidence drivers;
- degradation reasons.

### 2. Telemetry surface

Optional event/log emission through adapters:

- timings;
- cache hit/miss;
- parser mode;
- degraded/stale markers;
- retrieval stage completion/failure.

Diagnostics surface нужна для reasoning and API-facing explainability.  
Telemetry surface нужна для operations and debugging.

---

## Required Correlation Fields

Любой diagnostics/telemetry record должен быть correlation-friendly.

Минимальный набор correlation fields:

- `trace_id`
- `request_id` or equivalent
- `snapshot_id` or revision reference if available
- `query_intent`
- `stage`
- `timestamp`

При наличии host metadata также допустимы:

- `task_id`
- `session_id`
- `actor_id`
- `host_id`

Эти поля должны использоваться consistently across stages.

---

## Structured Diagnostics Contract

Каждый retrieval flow должен иметь structured diagnostics trace.

### Required sections

Минимально diagnostics trace должен содержать:

- `query_validation`
- `stage_summaries`
- `warnings`
- `degradations`
- `evidence_trace`
- `performance_summary`

### `query_validation`

Фиксирует:

- query accepted/rejected;
- invalid combinations;
- normalized query shape;
- ignored or transformed hints/options where relevant.

### `stage_summaries`

Для каждой стадии:

- stage name;
- status;
- short outcome;
- important counts or bounded metrics.

### `warnings`

Короткие сигналы о non-fatal issues:

- partial parse;
- stale-sensitive cache use;
- fallback retrieval;
- over-broad target scope;
- explicit override applied.

### `degradations`

Явная фиксация degraded behavior:

- parser fallback;
- no-cache mode;
- stale projection dropped;
- no raw-code escalation allowed by constraints;
- reduced recall due to budget.

### `evidence_trace`

Должна объяснять:

- почему были выбраны candidates;
- какие hints повлияли;
- где structural evidence было strong/weak;
- какие reasons drove confidence level.

### `performance_summary`

Минимально:

- total retrieval duration;
- per-stage duration when available;
- cache hits/misses summary;
- fetch expansion summary.

---

## Stage-Aware Event Model

Telemetry должна отражать stage transitions.

### Required stage event semantics

Для каждой стадии желательно уметь зафиксировать:

- started
- completed
- degraded
- failed

### Examples

- `candidate_generation.completed`
- `ranking.degraded`
- `context_packet.completed`
- `raw_code_fetch.skipped`
- `query_validation.failed`

Это должно давать host and operators возможность понять, где именно retrieval пошел не так.

---

## Safety Rule

Observability должна быть безопасной по умолчанию.

### Required default behavior

По умолчанию diagnostics/telemetry **не должны** включать:

- full raw source code bodies;
- secrets or credentials from host query;
- parser-native giant dumps;
- full internal graph serialization;
- unbounded prompt payloads;
- entire diff/file contents unless host explicitly enables and policy permits it.

### Allowed default content

По умолчанию допустимы:

- ids;
- bounded spans;
- counts;
- stage names;
- degradation flags;
- evidence summaries;
- small redacted snippets only if policy explicitly allows.

---

## Redaction Rule

Diagnostics and telemetry должны быть redaction-aware.

### Required behavior

Если host query или retrieved content потенциально содержат sensitive data:

- diagnostics должны использовать redacted or summarized representation;
- raw payloads не должны писатьcя в observability sinks by default;
- adapters могут поддерживать stricter redaction policy than core default.

Это особенно важно для:

- diffs with secrets;
- proprietary code;
- generated configs;
- embedded credentials or URLs.

---

## No-Backend Rule

Библиотека должна сохранять useful observability even without external logging/metrics/tracing system.

### Required behavior

Если telemetry adapter не подключен:

- diagnostics trace все равно должен существовать;
- host должен иметь доступ хотя бы к bounded structured diagnostics;
- behavior библиотеки не должен деградировать до “черного ящика”.

Это поддерживает in-process, test and local development workflows.

---

## Failure Rule

Observability не должна становиться источником семантического отказа retrieval.

### Required behavior

Если telemetry adapter падает:

- retrieval result должен по возможности продолжаться;
- diagnostics должны зафиксировать telemetry failure;
- correctness retrieval не должна зависеть от успешной отправки observability events.

Иначе observability начнет ломать primary function of the library.

---

## Explainability Rule

Diagnostics contract должен быть пригоден не только для ops, но и для reasoning-level explanation.

### Required rule

Host system должна быть в состоянии ответить:

- что система приняла на вход;
- какие stages были пройдены;
- почему confidence такой, какой есть;
- где были fallback/degraded/stale conditions;
- почему raw-code escalation произошла или не произошла;
- какие constraints/hints materially affected result.

Если на эти вопросы нельзя ответить из diagnostics trace, observability contract недостаточен.

---

## Why This Shape

Такой observability contract нужен, чтобы:

- делать retrieval explainable and debuggable;
- безопасно использовать систему в automation-heavy workflows;
- сохранять parity между local, in-memory и persistent modes;
- не превращать logs в единственный источник понимания;
- не утекать в небезопасное full-payload tracing by default.

---

## Prohibitions

- Observability **MUST NOT** сводиться только к свободным лог-строкам.
- Telemetry **MUST NOT** быть обязательным условием корректной работы retrieval.
- Diagnostics **MUST NOT** по умолчанию содержать full raw code or full graph dumps.
- Stage failures **MUST NOT** теряться без structured trace.
- Host systems **MUST NOT** быть вынуждены восстанавливать retrieval history только по внешним логам.

---

## Consequences

### Positive

- Retrieval становится гораздо легче дебажить.
- Host systems получают explainable diagnostics, а не только конечный пакет.
- Partial/stale/degraded modes становятся видимыми и управляемыми.
- Observability работает и в local/in-process сценариях.

### Negative

- Нужно поддерживать отдельный diagnostics contract и telemetry hooks.
- Появляется риск разрастания diagnostics surface, если не удерживать ее bounded.
- Придется отдельно проектировать redaction policy and event schemas.

### Tradeoff accepted

Мы сознательно выбираем **structured stage-aware observability** вместо более простого, но непрозрачного logging-only подхода.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Каждый retrieval flow имеет structured diagnostics trace.
2. Stage transitions наблюдаемы как минимум для candidate generation, ranking, context assembly и raw-code escalation.
3. Diagnostics доступны even without external telemetry backend.
4. Telemetry failures не ломают retrieval correctness.
5. Default observability safe by default and redaction-aware.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- concrete event schema and diagnostics schema;
- autonomous-action guardrails for AI consumers;
- retention/persistence policy for diagnostics traces;
- metrics and SLI/SLO definitions for retrieval quality and latency.
