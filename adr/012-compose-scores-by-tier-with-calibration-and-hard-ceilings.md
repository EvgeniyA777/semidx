# ADR-012: Compose Scores by Tier, with Calibration and Hard Ceilings

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-005` зафиксировал, что ranking должен быть structural-first, а semantic/vector signals — secondary.  
`ADR-008` зафиксировал evidence-aware and non-compensating confidence model.  
`ADR-011` зафиксировал autonomy guardrails, зависящие от retrieval quality.

После этого нужен более конкретный ответ на вопрос: как practically composing scores and thresholds должно работать внутри retrieval pipeline.

Если score composition не зафиксировать, появятся системные проблемы:

- разные реализации будут считать ranking по-разному;
- weak signals начнут незаметно компенсировать отсутствие strong structural evidence;
- score drift между версиями сделает regressions трудноуловимыми;
- confidence bands и guardrail posture станут непредсказуемыми;
- хосты начнут полагаться на случайные numeric differences, у которых нет стабильного смысла.

Нужно принять решение:

- как группировать сигналы в scoring tiers;
- как комбинировать эти tiers;
- где нужны hard ceilings и calibration;
- как не превратить scoring в одну opaque formula.

---

## Decision Drivers

- Сохранение structural-first retrieval policy
- Предсказуемость ranking behavior across versions
- Совместимость with non-compensating confidence model
- Explainability of why one candidate outranks another
- Возможность incremental calibration without rewriting architecture
- Protection against vector/text-first drift

---

## Considered Options

### Option 1. Single blended score

Все сигналы складываются в одну формулу без явного tier precedence.

### Option 2. Tiered scoring with hard ceilings and calibration

Signals grouped into ordered tiers. Higher tiers dominate. Lower tiers can rerank within ceilings but cannot erase missing strong evidence.

### Option 3. Rule-only ranking without numeric composition

Ranking строится только на discrete rules and precedence lists, без numeric scoring.

---

## Decision

Мы принимаем **Option 2: Tiered scoring with hard ceilings and calibration**.

Scoring model должен быть:

- `tiered`
- `calibrated`
- `hard-ceiling aware`
- explainable enough for debugging

Numeric scores допустимы, но они должны вычисляться по ordered tiers, а не по flat blended formula.

---

## Scoring Tiers

Сигналы должны быть сгруппированы в четыре tiers.

### Tier 1. Strong structural signals

Это highest-authority signals:

- exact symbol resolution
- authority definition match
- direct changed-span overlap
- direct call/reference relation with resolved target
- exact path target match under constrained scope

### Tier 2. Strong contextual structural signals

Это still structural, but one step weaker:

- enclosing unit or container relevance
- import/dependency adjacency
- graph-neighbor proximity
- nearest test adjacency
- namespace/module proximity

### Tier 3. Soft structural and lexical support

Signals useful for reranking and recall assistance:

- unresolved but plausible `related_to`
- lexical keyword overlap
- docstring/comment overlap
- naming similarity
- file/path naming heuristics

### Tier 4. Semantic/vector support

Last-tier signals:

- embedding similarity
- semantic clustering
- natural-language query affinity
- recency/popularity soft boosts

Tier 4 может помогать, но не должен стать dominant source of authority.

---

## Hard Ceiling Rule

Lower tiers не должны полностью компенсировать отсутствие higher-tier evidence.

### Required rule

Если candidate не имеет Tier 1 structural support и только слабо поддержан Tier 2, то:

- Tier 3 and Tier 4 не могут поднять его above a candidate with strong Tier 1 authority match;
- confidence ceiling для такого candidate остается ограниченным;
- autonomy posture cannot be upgraded by weak-tier accumulation alone.

### Meaning

Много lexical matches + high embedding similarity не могут заменить:

- exact authority definition;
- resolved changed target;
- strong direct structural relation.

---

## Tier Composition Rule

Скоринг должен строиться как staged composition:

1. collect structural candidate set
2. compute Tier 1 evidence
3. compute Tier 2 evidence
4. apply Tier 3 refinements
5. apply Tier 4 reranking only within allowed ceiling bands

### Required behavior

- Tier 1 может radically shape the top set.
- Tier 2 может reorder and expand among structurally plausible candidates.
- Tier 3 может fine-tune and break ties.
- Tier 4 может rerank near-equals or recover sparse-query scenarios, but only within bounded guardrails.

---

## Calibration Rule

Scoring weights and thresholds должны калиброваться, а не считаться постоянной истиной.

### Required calibration targets

Калибровка должна опираться на:

- representative retrieval fixtures;
- expected top-k authority units;
- diff-based change tasks;
- bug investigation tasks;
- plan/prep workflows;
- multi-language and partial-parser scenarios.

### Required principle

Calibration должна улучшать:

- ranking precision;
- stability;
- confidence band alignment;

но не должна ломать tier precedence.

---

## Threshold Bands

Система должна иметь не только raw scores, но и meaningful bands.

### Required bands

Минимально нужны:

- top authority band
- useful support band
- exploratory band
- below-threshold noise band

### Meaning

- `top authority band`: primary candidates for `context packet`
- `useful support band`: neighbors/tests/helpers that may be included if budget allows
- `exploratory band`: low-confidence adjuncts, mostly for extended investigation
- `below-threshold noise band`: should not enter default packet

Это делает score usable for packet shaping and guardrails.

---

## Confidence Linkage Rule

Scores и confidence связаны, но не тождественны.

### Required rule

High score не означает автоматически `high` confidence.

Confidence также зависит от:

- parser quality
- stale/degraded conditions
- ambiguity
- breadth of retrieval scope
- whether target was actually localized

### Meaning

Candidate может иметь хороший ranking score relative to peers, но retrieval result в целом всё ещё может быть only `medium` confidence.

---

## Guardrail Linkage Rule

Autonomy guardrails не должны строиться напрямую из raw score alone.

### Required rule

`draft_patch_safe` и более permissive postures допустимы только если одновременно выполнены:

- score in authority-worthy band;
- target localized;
- confidence not downgraded by major warnings;
- no unresolved major ambiguity remains.

Это предотвращает dangerous overreliance on numeric ranking.

---

## Sparse Evidence Rule

При sparse structural evidence scoring должен уметь работать, но честно.

### Required behavior

Когда Tier 1 weak or absent:

- Tier 2/3/4 могут использоваться для exploratory retrieval;
- candidates могут попадать в exploratory or support bands;
- confidence ceiling должен понижаться;
- diagnostics должны явно показывать weak-evidence composition.

### Why this matters

Иначе система будет выглядеть уверенной в режимах, где она по сути лишь “угадывает лучше, чем случайно”.

---

## Deterministic Tie-Breaking Rule

При близких scores должны использоваться stable tie-breakers.

Порядок tie-breakers должен быть:

1. stronger higher-tier evidence
2. more direct target anchoring
3. smaller and more localized scope
4. same-file or same-unit precedence where relevant
5. stable id ordering as final fallback

Это нужно для reproducibility and regression testing.

---

## Versioning and Drift Rule

Scoring model должен считаться versioned component.

### Required rule

Изменения в:

- tiers,
- weights,
- thresholds,
- ceilings,
- tie-break behavior

должны быть versioned and regression-tested.

### Why this matters

Scoring drift — это архитектурное изменение retrieval behavior, а не мелкая внутренняя оптимизация.

---

## Explainability Rule

Любой top-ranked candidate должен быть explainable не только через evidence categories, но и через tier contribution summary.

### Required explanation shape

Минимально система должна уметь сказать:

- which tier made this candidate viable;
- which tier promoted it above peers;
- whether lower-tier signals only refined or materially rescued the result;
- whether any ceiling prevented further promotion.

---

## Why This Shape

Такой scoring policy нужна, чтобы:

- удержать structural-first architecture не только на словах, но и в numeric behavior;
- сделать ranking стабильным и explainable;
- не позволить low-authority signals quietly захватить top results;
- связать ranking, confidence и guardrails в одну coherent retrieval stack.

---

## Prohibitions

- Flat blended scoring **MUST NOT** становиться canonical model.
- Tier 3/4 signals **MUST NOT** outrank strong Tier 1 authority by accumulation alone.
- Confidence **MUST NOT** вычисляться как simple monotonic transform of ranking score.
- Guardrail posture **MUST NOT** зависеть only from raw ranking score.
- Calibration **MUST NOT** ломать declared tier precedence for benchmark gains.

---

## Consequences

### Positive

- Ranking становится гораздо более стабильным и предсказуемым.
- Retrieval лучше соответствует архитектурным принципам.
- Confidence и guardrails получают надежную опору.
- Regressions легче ловить через fixtures and versioned calibration.

### Negative

- Модель становится сложнее простой blended formula.
- Потребуются retrieval fixtures and calibration discipline.
- Нужно будет поддерживать score versioning and threshold docs.

### Tradeoff accepted

Мы сознательно выбираем **tiered calibrated scoring with hard ceilings** вместо более простой, но архитектурно размывающей single-score formula.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Ranking signals grouped into explicit tiers with ordered precedence.
2. Lower tiers cannot fully compensate for missing strong structural evidence.
3. Score bands usable for packet shaping exist and are stable enough for tests.
4. Confidence and guardrails consume score information but are not reducible to it.
5. Scoring changes are versioned and regression-tested.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- concrete diagnostics/event schema for score and tier traces;
- retrieval fixture and benchmark policy;
- human-review and override thresholds in host systems;
- long-term evaluation and quality metrics.
