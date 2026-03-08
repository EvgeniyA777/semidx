# ADR-017: Gate Retrieval Releases on Contract, Quality, and Safety Regressions

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-014` зафиксировал benchmark and fixture governance.  
`ADR-015` зафиксировал host override and human-review policy.  
`ADR-016` зафиксировал canonical examples for contracts.

После этого нужен release-level decision: когда retrieval changes можно считать допустимыми к выпуску.

Без release gates быстро появятся проблемы:

- benchmark regressions будут замечены, но не останавливать релизы;
- contract drift пройдет в mainline без осмысленного решения;
- unsafe autonomy/guardrail regressions будут попадать в hosts;
- diagnostics schema changes будут выпускаться без compatibility discipline;
- “это же только retrieval” станет оправданием для unsafe changes.

Нужно принять решение:

- какие изменения должны быть release-gated;
- какие regressions считаются block-level;
- как учитывать expected improvements and expected tradeoffs;
- какие минимальные quality bars обязательны перед выпуском.

---

## Decision Drivers

- Защита host systems from unsafe retrieval regressions
- Enforceability of prior ADR decisions
- Controlled evolution of contracts, scoring and guardrails
- Predictable release quality
- Clear distinction between acceptable tradeoff and unsafe drift

---

## Considered Options

### Option 1. Release on passing unit tests only

Если код компилируется и базовые тесты проходят, retrieval changes можно выпускать.

### Option 2. Release gates based on contract, quality and safety checks

Retrieval release допускается только при прохождении bounded contract, benchmark and safety gates.

### Option 3. Manual judgment only

Каждый релиз решается вручную без formal quality gates.

---

## Decision

Мы принимаем **Option 2: Release gates based on contract, quality and safety checks**.

Retrieval subsystem changes должны проходить explicit release gates по трем группам:

- contract integrity
- retrieval quality
- safety behavior

---

## Gate Families

### Gate 1. Contract integrity

Должны проверяться:

- public contract compatibility
- diagnostics/event schema validity
- example corpus alignment
- versioning correctness for breaking changes

### Gate 2. Retrieval quality

Должны проверяться:

- fixture correctness
- benchmark suites
- no unreviewed ranking drift
- no uncontrolled parser regression

### Gate 3. Safety behavior

Должны проверяться:

- confidence band behavior
- guardrail posture behavior
- override/review semantics
- degraded/stale mode safety

---

## Blocking Regressions

Следующие regressions должны считаться release-blocking by default:

- strong authority target falls below expected authority band without approved tradeoff
- confidence becomes more permissive under weaker evidence
- `autonomy_blocked` or other safety posture weakens unexpectedly
- diagnostics/event schemas break without versioned change
- examples and schemas drift out of sync
- stale/fallback/partial conditions stop producing required warnings or degradations

---

## Allowed Tradeoff Rule

Не каждое ухудшение является automatic block, если оно:

- явно ожидаемое;
- локализованное;
- documented;
- benchmark-reviewed;
- accompanied by net improvement elsewhere.

### Required behavior

Expected tradeoff must be declared explicitly as such, not discovered accidentally after release.

---

## Improvement Rule

Expected improvements тоже требуют discipline.

### Required behavior

Если change claims improvement, it should show at least one of:

- benchmark improvement;
- reduced noise band intrusion;
- better confidence honesty;
- better guardrail safety;
- lower latency without semantic regression.

Иначе “improvement” остается утверждением без evidence.

---

## Release Decision Matrix

Минимальная логика выпуска должна быть такой:

- contract break without versioning -> block
- safety regression -> block
- benchmark regression without approved tradeoff -> block
- expected tradeoff with explicit approval -> allow
- no behavior change or expected improvement -> allow if gates green

---

## Manual Approval Rule

Некоторые changes требуют explicit manual approval even if most checks pass.

### Required approval cases

- breaking external contract change
- downgraded safety posture under previously green fixtures
- scoring calibration shifts that reorder authority bands materially
- changes to override/review semantics
- changes to diagnostics/event vocabularies

Это не отменяет automatic gates, а дополняет их.

---

## Evidence Rule

Release gating должно ссылаться на concrete evidence artifacts.

### Required evidence sources

- fixture results
- benchmark suite reports
- schema validation results
- example alignment checks
- diagnostics conformance checks

Release decision без таких artifacts считается insufficiently grounded.

---

## Safe Failure Rule

Если release gate infrastructure itself fails or unavailable:

- retrieval change should not be assumed safe by default;
- degraded release decision must be explicit;
- missing gate evidence should itself be visible.

Иначе gate bypass станет нормальным operational shortcut.

---

## Why This Shape

Такой release gating policy нужен, чтобы:

- реально enforce prior ADRs;
- удержать retrieval from silently regressing;
- поддержать host trust in the library;
- сделать safety changes first-class release concern.

---

## Prohibitions

- Retrieval releases **MUST NOT** опираться only на unit tests.
- Safety regressions **MUST NOT** трактоваться как acceptable noise by default.
- Breaking contract changes **MUST NOT** идти без versioning discipline.
- Missing benchmark evidence **MUST NOT** считаться нейтральным сигналом.
- “Only retrieval changed” **MUST NOT** использоваться как excuse to skip release gates.

---

## Consequences

### Positive

- Release quality становится гораздо более управляемым.
- Safety and contract integrity получают реальный enforcement.
- Tradeoffs становятся reviewable instead of accidental.
- Host systems получают более надежный component.

### Negative

- Release process становится строже и тяжелее.
- Понадобится поддерживать gate artifacts and reports.
- Некоторые быстрые iterations придется делать в non-release mode until gates are satisfied.

### Tradeoff accepted

Мы сознательно выбираем **explicit release quality gates for retrieval behavior** вместо более быстрых, но слабо контролируемых выпусков.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Retrieval release path checks contract integrity, quality and safety.
2. Blocking regressions clearly defined.
3. Expected tradeoffs require explicit declaration and approval.
4. Release evidence comes from fixtures, benchmarks, schemas and examples.
5. Missing gate evidence cannot silently pass as green.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- concrete release workflow and reports;
- exception handling policy for emergency fixes;
- integration policy with CI/release pipelines;
- long-term telemetry feedback into benchmark governance.
