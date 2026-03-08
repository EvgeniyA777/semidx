# ADR-014: Govern Retrieval Quality with Versioned Fixtures and Benchmarks

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-012` зафиксировал tiered scoring with calibration and hard ceilings.  
`ADR-013` зафиксировал canonical diagnostics/event schemas.  
Ранее ADR уже зафиксировали:

- normalized semantic graph;
- parser adapter contract;
- structural-first ranking;
- confidence model;
- guardrails.

После этого нужен ответ на вопрос: как управлять качеством retrieval со временем.

Без explicit benchmark and fixture policy возникнут проблемы:

- scoring drift будет незаметно ломать ranking quality;
- parser changes будут менять retrieval behavior без контролируемой оценки;
- diagnostics contract будет эволюционировать без regression checks;
- новые языки и host use-cases будут добавляться без понятного quality bar;
- “кажется стало лучше” заменит воспроизводимую оценку качества.

Нужно принять решение:

- как фиксировать retrieval expectations;
- какие fixtures нужны;
- как измерять regressions и improvements;
- что считается допустимым изменением retrieval behavior.

---

## Decision Drivers

- Предсказуемая эволюция retrieval behavior
- Контроль score/calibration drift
- Сравнимость parser strategies and ranking changes
- Поддержка multi-language and partial-parser scenarios
- Связь между architecture decisions and measurable quality
- Удобство локального и CI-based regression testing

---

## Considered Options

### Option 1. Ad hoc manual testing

Изменения в retrieval проверяются вручную на отдельных примерах без фиксированного benchmark set.

### Option 2. Versioned fixtures and benchmark suites

Retrieval behavior управляется через versioned fixtures, canonical expectations and benchmark policies.

### Option 3. Metrics only in production-like hosts

Качество retrieval оценивается только через later integration telemetry and runtime feedback.

---

## Decision

Мы принимаем **Option 2: Versioned fixtures and benchmark suites**.

Retrieval subsystem должен иметь **versioned fixture corpus** и **несколько benchmark suites**, которые используются для:

- regression detection;
- calibration;
- parser comparison;
- retrieval-quality governance.

Architecture changes without benchmark discipline считаются недостаточно управляемыми.

---

## Core Rule

Каждое существенное изменение в:

- parser adapters;
- graph normalization;
- ranking tiers;
- confidence derivation;
- raw-code fetch policy;
- diagnostics schema

должно оцениваться не только рассуждением, но и against versioned fixtures and benchmark expectations.

---

## Fixture Categories

Fixture corpus должен быть разложен по категориям use-cases, а не быть случайной коллекцией файлов.

### 1. Symbol-target fixtures

Проверяют:

- exact symbol lookup;
- authority definition retrieval;
- caller/callee retrieval;
- namespace/module localization.

### 2. Diff-centered fixtures

Проверяют:

- changed-span anchoring;
- impact hints;
- nearest tests;
- edit-target localization.

### 3. Bug-investigation fixtures

Проверяют:

- ability to find implementation-critical units;
- avoidance of superficial lexical false positives;
- escalation to raw code only where justified.

### 4. Multi-file change fixtures

Проверяют:

- broad impact surfaces;
- cross-file ambiguity;
- guardrail posture under multi-file uncertainty.

### 5. Partial-parser fixtures

Проверяют:

- fallback behavior;
- degraded confidence;
- non-compensating ranking under incomplete evidence.

### 6. Host-query fixtures

Проверяют:

- structured query handling;
- soft hints;
- hard constraints;
- override semantics.

### 7. Diagnostics fixtures

Проверяют:

- canonical diagnostics trace shape;
- event vocabulary;
- bounded warnings/degradations/codes.

---

## Fixture Design Rule

Fixtures должны быть designed, not accidental.

### Required fixture ingredients

Каждый meaningful fixture должен включать:

- fixture id;
- fixture purpose;
- input snapshot or compact fixture repo;
- retrieval query;
- expected qualitative outcome;
- expected top candidates or candidate bands;
- expected confidence/guardrail posture where relevant.

### Required principle

Fixtures должны проверять behavior, а не implementation accident.

Например:

- не “score must equal 0.734”
- а “target definition must remain in top authority band”

---

## Benchmark Suites

Нужны разные suites для разных слоев качества.

### Suite 1. Retrieval correctness

Проверяет:

- authority target found or not;
- top-k quality;
- false-positive containment;
- structural relevance over lexical noise.

### Suite 2. Confidence and guardrails

Проверяет:

- high/medium/low confidence alignment;
- blocked vs plan-safe vs draft-patch-safe behavior;
- downgraded behavior under partial/stale conditions.

### Suite 3. Diagnostics conformance

Проверяет:

- schema validity;
- stage/event naming;
- code vocabulary usage;
- boundedness and redaction defaults.

### Suite 4. Performance/latency smoke

Проверяет:

- no catastrophic regression in retrieval latency;
- cache hit/miss behavior;
- bounded cost of ranking and raw-code escalation.

Эта suite не обязана быть full performance lab, но должна ловить грубые деградации.

---

## Golden Expectations Rule

Некоторые benchmark expectations должны быть golden and versioned.

### Allowed golden expectations

- expected top authority candidate ids;
- expected confidence band;
- expected guardrail posture;
- expected warning/degradation codes;
- expected stage presence.

### Disallowed brittle goldens

Нельзя по умолчанию goldens делать на:

- exact floating-point scores;
- full diagnostics text blobs;
- unstable ordering среди равнозначных support candidates without tie-break stability.

Это удерживает test suite useful instead of flaky.

---

## Benchmark Interpretation Rule

Benchmarks должны оценивать не только precision, но и retrieval safety.

### Required evaluation dimensions

- correctness
- precision/noise ratio
- confidence honesty
- guardrail safety
- diagnostics conformance
- cost/latency sanity

Иначе система может “улучшать top-k” ценой опасного роста ложной уверенности.

---

## Change Classification Rule

Не все retrieval changes одинаковы.

### Required classification

Изменения должны классифицироваться как:

- `no_behavior_change`
- `expected_improvement`
- `expected_tradeoff`
- `breaking_retrieval_change`

### Required behavior

Если benchmark results показывают visible retrieval change, change author должен явно указать, к какой категории это относится.

Это делает retrieval evolution reviewable.

---

## Versioning Rule

Fixtures and benchmark suites должны versionироваться.

### Required rule

Versioning must cover:

- fixture corpus version;
- benchmark suite version;
- scoring model version where relevant;
- schema version for diagnostics-based expectations.

### Why this matters

Иначе невозможно честно сравнивать “улучшение” между разными этапами развития системы.

---

## Multi-Language Rule

Benchmark policy должна явно учитывать multi-language support.

### Required behavior

Suites должны иметь cases для:

- strong-parser languages;
- partial-parser languages;
- mixed-quality retrieval paths.

Нельзя валидировать систему только на одном “удобном” языке и потом считать архитектуру подтвержденной.

---

## CI and Local Rule

Benchmark discipline должна работать и локально, и в automation.

### Required split

Нужно поддерживать:

- fast local fixture checks;
- medium regression suite;
- heavier benchmark suite for CI/nightly/release gates.

Это позволяет не убить локальную скорость, но сохранить governance.

---

## Why This Shape

Такой benchmark policy нужен, чтобы:

- сделать retrieval architecture operationally governable;
- удержать scoring/calibration под контролем;
- ловить regressions до того, как они попадут в hosts;
- поддержать safe evolution across parsers, languages and host workflows.

---

## Prohibitions

- Retrieval changes **MUST NOT** проверяться only ad hoc examples.
- Benchmark quality **MUST NOT** оцениваться only by mean score without safety dimensions.
- Golden fixtures **MUST NOT** опираться на fragile floating-point exactness by default.
- Parser/ranking changes **MUST NOT** считаться harmless without fixture impact review.
- Multi-language system **MUST NOT** benchmark itself only on easiest supported language.

---

## Consequences

### Positive

- Retrieval regressions становятся видимыми.
- Calibration and scoring drift проще контролировать.
- Confidence and guardrail behavior можно реально стабилизировать.
- Архитектурные решения получают measurable enforcement.

### Negative

- Понадобится отдельная fixture/benchmark maintenance discipline.
- Придется курировать golden expectations and benchmark versions.
- Некоторые полезные improvements будут требовать benchmark updates, что увеличит change cost.

### Tradeoff accepted

Мы сознательно выбираем **versioned benchmark governance** вместо более быстрой, но неуправляемой эволюции retrieval behavior.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Есть versioned fixture corpus covering core retrieval scenarios.
2. Есть benchmark suites как минимум для correctness, confidence/guardrails, diagnostics and latency sanity.
3. Golden expectations проверяют stable behavior bands, а не brittle exact internals.
4. Retrieval behavior changes классифицируются и reviewable against fixtures.
5. Benchmark policy применима и локально, и в CI/release workflows.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- human-review and override policy for host systems;
- concrete query and diagnostics schema examples;
- quality gates for releases;
- long-term telemetry feedback loop into calibration.
