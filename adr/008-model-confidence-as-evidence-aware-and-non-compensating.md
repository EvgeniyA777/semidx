# ADR-008: Model Confidence as Evidence-Aware and Non-Compensating

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-002` зафиксировал, что `context packet` должен содержать `confidence`.  
`ADR-004` зафиксировал, что parser adapters могут возвращать partial facts и unresolved references.  
`ADR-005` зафиксировал structural-first ranking с explainable evidence.  
`ADR-006` зафиксировал late raw-code fetch.  
`ADR-007` зафиксировал, что persistence/cache могут работать в degraded or stale-sensitive modes.

После этого нужен отдельный архитектурный ответ на вопрос: что именно означает `confidence` в retrieval result.

Если confidence не нормировать, быстро появятся системные дефекты:

- система начнет путать “много текста” с “хорошее понимание”;
- vector similarity и lexical overlap будут искусственно завышать уверенность;
- partial parser output будет выглядеть как полная semantic truth;
- host systems начнут трактовать любые результаты как одинаково надежные;
- AI consumers будут действовать слишком уверенно в ситуациях, где evidence weak or incomplete.

Нужно принять решение:

- как именно считать confidence;
- какие виды evidence должны его повышать или понижать;
- как confidence должен вести себя при partial, stale и degraded conditions.

---

## Decision Drivers

- Избежать ложной уверенности
- Сделать retrieval result usable for automation and AI agents
- Сохранить explainability
- Учитывать partial parsing, weak symbol resolution и stale artifacts
- Не позволить слабым сигналам компенсировать отсутствие сильных сигналов
- Поддержать deterministic enough testing and diagnostics

---

## Considered Options

### Option 1. Single opaque score

Возвращать один numeric score без явной reason model.

### Option 2. Evidence-aware, non-compensating confidence model

Возвращать confidence level, assembled from explicit evidence categories, with downgrade rules and reason trace.

### Option 3. Host-defined confidence only

Библиотека вообще не считает confidence, а host systems сами интерпретируют retrieval quality.

---

## Decision

Мы принимаем **Option 2: Evidence-aware, non-compensating confidence model**.

Confidence должен вычисляться как **объяснимый результат оценки качества evidence**, а не как косметический score.

### Core principles

- confidence должен быть evidence-aware;
- confidence должен быть non-compensating;
- confidence должен понижаться при partial/stale/degraded conditions;
- extra text or extra weak signals не должны автоматически поднимать confidence.

---

## Confidence Output Shape

Каждый retrieval result и `context packet` должен содержать confidence section как минимум с четырьмя частями:

- `level`
- `reasons`
- `warnings`
- `missing_evidence`

### `level`

Минимально допустимая шкала:

- `high`
- `medium`
- `low`

Numeric score может существовать дополнительно, но canonical contract должен быть readable banded confidence.

### `reasons`

Короткие положительные evidence claims:

- `target symbol resolved to authority definition`
- `graph proximity strong`
- `changed span overlaps selected unit`
- `multiple independent structural signals agree`

### `warnings`

Короткие downgrade claims:

- `symbol resolution partial`
- `fallback parser used`
- `ranking relied on soft relations`
- `cache artifact stale-sensitive`
- `raw-code expansion did not remove ambiguity`

### `missing_evidence`

Явное перечисление того, чего системе не хватило:

- `no resolved callers found`
- `no test adjacency available`
- `parser lacks call extraction for this language`
- `target likely distributed across multiple files`

---

## Non-Compensating Rule

Confidence не должен работать как простая сумма слабых сигналов.

### Required rule

Отсутствие сильного structural evidence **нельзя** полноценно компенсировать:

- большим количеством lexical matches;
- высокой embedding similarity;
- большим объемом raw code;
- большим числом soft graph relations.

### Meaning

Например:

- если target symbol не разрешен;
- если parser only partial;
- если ranking mostly lexical;

то confidence не должен становиться `high` только потому, что найдено много похожего текста.

---

## Positive Evidence Categories

Confidence может повышаться при наличии сильного evidence из следующих категорий:

- exact target resolution
- strong graph agreement
- direct diff anchoring
- bounded retrieval scope
- consistent multi-signal support

### `exact target resolution`

Высокий positive signal:

- symbol resolved to authority definition;
- exact unit identified as edit/reasoning target.

### `strong graph agreement`

Высокий positive signal:

- selected candidates confirmed by `defines`, `references`, `calls`, `imports`, `depends_on`.

### `direct diff anchoring`

Сильный positive signal:

- changed paths/spans directly overlap retrieved units.

### `bounded retrieval scope`

Сильный positive signal:

- система смогла сузить ответ до небольшого числа high-authority units.

### `consistent multi-signal support`

Позитивно, когда:

- structural signals согласованы;
- lexical/vector signals лишь подтверждают уже найденное, а не заменяют его.

---

## Negative Evidence Categories

Confidence должен понижаться при наличии следующих факторов:

- partial parsing
- unresolved symbols
- soft-only ranking
- stale-sensitive artifacts
- oversized retrieval scope
- contradictory evidence

### `partial parsing`

Понижение обязательно, если:

- parser не поддерживает часть capability set;
- extraction mode = `partial` or `fallback`.

### `unresolved symbols`

Понижение обязательно, если:

- target symbol only approximate;
- references unresolved or weakly linked.

### `soft-only ranking`

Понижение обязательно, если ranking опирался в основном на:

- lexical overlap;
- embedding similarity;
- `related_to` edges without stronger structural proof.

### `stale-sensitive artifacts`

Понижение обязательно, если retrieval опирается на данные, которые:

- не подтверждены against current snapshot;
- зависят от potentially stale cache;
- могли быть получены от outdated adapter fingerprint.

### `oversized retrieval scope`

Понижение обязательно, если системе пришлось:

- тащить много соседних units;
- переходить к broad file-level retrieval;
- расширять raw-code fetch, не локализовав цель.

### `contradictory evidence`

Понижение обязательно, если:

- разные signals указывают на разные authority units;
- impact surface шире, чем ожидалось;
- multiple candidate edit locations remain plausible.

---

## Stage-Aware Confidence

Confidence должен учитывать стадию retrieval.

### Stage 1. Structural retrieval

Первичный confidence строится из:

- parser quality;
- graph evidence;
- ranking quality;
- target localization quality.

### Stage 2. Raw-code escalation

Late raw-code fetch может:

- уточнить reasoning;
- повысить confidence в behavior understanding;
- но не должен автоматически снимать unresolved structural ambiguity.

### Required rule

Raw-code fetch может повышать confidence только если он:

- подтверждает already-ranked authority target;
- снимает конкретную ambiguity;
- не противоречит existing structural evidence.

---

## Freshness and Staleness Rule

Confidence должен быть freshness-aware.

### Required rule

Если retrieval result построен на:

- outdated snapshot metadata;
- stale projection cache;
- invalidated parser artifacts;

то confidence должен быть downgraded, даже если содержимое выглядит полезным.

### Why this matters

Иначе система будет выдавать “уверенный” ответ по неактуальному состоянию проекта.

---

## Host Behavior Rule

Host systems должны уметь реагировать на confidence levels по-разному.

### Intended behavior

- `high`: можно использовать для focused reasoning and patch preparation
- `medium`: желательно осторожное продолжение, возможно с дополнительным fetch
- `low`: желательно запрашивать дополнительное уточнение, не делать aggressive autonomous action

Библиотека не оркестрирует host behavior, но confidence contract должен позволять такой policy.

---

## Why This Shape

Такой confidence model нужен, чтобы:

- не превращать retrieval в certainty theater;
- дать host systems usable quality signal;
- удержать приоритет strong structural evidence;
- честно отражать partial/stale/degraded modes;
- поддержать безопасную работу AI coding consumers.

---

## Prohibitions

- Confidence **MUST NOT** быть чисто cosmetic numeric score without reasons.
- Weak signals **MUST NOT** полностью компенсировать отсутствие strong structural evidence.
- Extra raw code **MUST NOT** автоматически повышать confidence.
- Stale artifacts **MUST NOT** сохранять прежний confidence level без downgrade.
- `high` confidence **MUST NOT** выдаваться при partial/fallback-only retrieval without strong supporting evidence.

---

## Consequences

### Positive

- Retrieval становится безопаснее для автономных consumers.
- Confidence легко читать и дебажить.
- Partial-parser and fallback modes становятся честными, а не скрытыми.
- Host systems могут строить policy around quality bands.

### Negative

- Появляется отдельная logic layer для confidence assembly.
- Нужно будет калибровать downgrade/upgrade rules.
- Некоторые users захотят single score, и его придется строить как secondary presentation.

### Tradeoff accepted

Мы сознательно выбираем **честную quality signaling model** вместо красивого, но вводящего в заблуждение aggregated score.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Каждый `context packet` содержит `level`, `reasons`, `warnings`, `missing_evidence`.
2. Partial/fallback/stale conditions всегда могут понизить confidence.
3. Weak signals не могут самостоятельно поднять confidence до `high`.
4. Raw-code escalation повышает confidence только when ambiguity is actually reduced.
5. Host systems могут принимать осторожные policy decisions по banded confidence output.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- host query contract and retrieval hints;
- observability/diagnostics contract;
- calibration and scoring internals;
- autonomous-action guardrails for AI consumers.
