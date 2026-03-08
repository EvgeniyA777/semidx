# ADR-005: Rank Context Using Structural Signals First and Semantic Signals Second

**Status**: Accepted  
**Date**: 2026-03-07  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-002` зафиксировал, что библиотека должна отдавать стандартный `context packet`.  
`ADR-003` зафиксировал canonical model как normalized semantic graph.  
`ADR-004` зафиксировал parser adapters как capability-based fact extractors.

После этого возникает следующий ключевой вопрос: как выбирать, какие units, files и relations попадут в `context packet`, если потенциально релевантных кандидатов много.

Если ranking strategy выбрать неудачно, будут системные дефекты:

- в `context packet` начнут попадать шумные, но текстово похожие фрагменты;
- structural authority symbols будут уступать место случайным lexical matches;
- token budget будет расходоваться на нерелевантный код;
- multi-language and partial-parser scenarios станут нестабильными;
- vector similarity начнёт подменять собой structural reasoning.

Нужно принять решение о ranking policy для retrieval.

---

## Decision Drivers

- Высокая precision при ограниченном token budget
- Приоритет структурно значимого контекста над текстовым шумом
- Устойчивость к partial parsing и incomplete symbol resolution
- Поддержка impact-oriented retrieval
- Возможность добавлять semantic/vector signals без превращения системы в vector-first RAG
- Объяснимость ranking результата
- Детерминируемость enough для тестов и отладки

---

## Considered Options

### Option 1. Lexical/vector relevance first

Сначала ранжировать по textual similarity, embeddings и keyword overlap, а structural signals использовать как вторичное улучшение.

### Option 2. Structural relevance first, semantic/vector signals second

Сначала ранжировать по graph- and structure-derived signals, а lexical/vector signals использовать как secondary reranking and recall enhancement.

### Option 3. Equal-weight blended scoring

Сразу смешивать все доступные signals в одном общем scoring without explicit precedence.

---

## Decision

Мы принимаем **Option 2: Structural relevance first, semantic/vector signals second**.

Ranking policy должна быть устроена так:

1. сначала определить candidate set через structural signals;
2. затем упорядочить его преимущественно structural scoring;
3. semantic/vector signals использовать только как secondary reranking, tie-breaking или recall assistance.

Система **не** должна быть vector-first retrieval engine.

---

## Primary Ranking Signals

Structural ranking должен опираться прежде всего на следующие signals:

- symbol match
- graph proximity
- containment relevance
- import/dependency relevance
- call/reference relevance
- diff overlap
- path/namespace relevance
- test adjacency

### `symbol match`

Высокий приоритет должны получать units, которые:

- определяют target symbol;
- содержат reference to target symbol;
- являются authority location для symbol identity.

### `graph proximity`

Высокий приоритет должны получать units, которые находятся близко в semantic graph к target files/symbols.

### `containment relevance`

Если релевантен unit, его container file/module обычно тоже важен, но с более низким весом, чем authority unit.

### `import/dependency relevance`

Modules/files, связанные через `imports` и `depends_on`, должны повышать приоритет при impact-oriented retrieval.

### `call/reference relevance`

Callers, callees и reference-heavy neighbors должны повышаться в ранге для change-impact analysis.

### `diff overlap`

Если retrieval запущен по diff или changed paths, пересечение с этими изменениями должно быть сильным сигналом.

### `path/namespace relevance`

Если host или query указывает конкретные path/module hints, ranking должен уважать их как explicit user/system intent.

### `test adjacency`

Тестовые units, близкие к changed production units, должны включаться в candidate set для impact/usefulness reasons.

---

## Secondary Ranking Signals

Secondary signals допустимы, но не должны ломать precedence of structural relevance.

К ним относятся:

- lexical keyword overlap;
- docstring/comment overlap;
- embedding similarity;
- historical popularity or recency signals;
- host-supplied soft boosts.

### Allowed uses

Эти signals можно использовать для:

- reranking внутри уже релевантного structural candidate set;
- recall enhancement, когда structural evidence weak or partial;
- tie-breaking between near-equal structural candidates.

### Disallowed use

Эти signals не должны сами по себе вытеснять authority structural units из top context.

---

## Candidate Selection Policy

Ranking должен быть двухстадийным.

### Stage 1. Candidate generation

Система собирает candidate set из:

- directly matched files/symbols;
- graph neighbors;
- containers;
- affected tests;
- diff-adjacent units;
- explicit path/module hints.

### Stage 2. Candidate ranking

Система ранжирует только этот bounded candidate set, а не весь репозиторий одинаково.

Это нужно, чтобы:

- сократить шум;
- ускорить retrieval;
- сохранить explainability;
- не позволить embeddings перетянуть слишком далекие, но текстово похожие участки.

---

## Explainability Rule

Ranking result должен быть объяснимым.

Для каждого high-priority candidate система должна быть способна назвать короткую reason trace:

- defines requested symbol;
- calls changed unit;
- imported by affected module;
- overlaps changed file;
- nearest test for affected namespace;
- boosted by host hint;
- reranked by semantic similarity after structural match.

Эти reason traces должны попадать в `evidence` секцию `context packet`.

---

## Partial Information Rule

Parser quality и resolution quality могут быть неполными.  
Ranking policy должна учитывать это явно.

### Required rule

Когда symbol resolution incomplete:

- strict graph relations должны использоваться там, где есть;
- soft relations and lexical signals могут временно усиливаться;
- confidence результата должен снижаться;
- evidence должна явно указывать, что ranking partial.

### Why this matters

Иначе система будет симулировать ложную точность на partial extraction.

---

## Token Budget Rule

Ranking не существует отдельно от context shaping.  
Он должен работать совместно с token budget policy.

### Required behavior

Если budget маленький:

- приоритет получают authority units;
- containers и broad neighbors режутся раньше;
- test adjacency и secondary evidence могут сокращаться первыми;
- full raw code не должен вытеснять skeleton-level coverage.

Если budget расширяется:

- можно добавить neighboring units;
- можно повысить coverage of impact hints;
- можно включать дополнительные tests and soft matches.

---

## Use of Embeddings and Vectors

Embeddings допустимы, но только как secondary layer.

### Permitted roles

- semantic reranking;
- recall expansion for natural-language queries;
- grouping of semantically similar units after structural anchoring;
- recovery path when graph evidence sparse.

### Prohibited role

Embeddings **MUST NOT** становиться основной truth source для context selection в code-understanding workflow.

---

## Determinism and Stability

Ranking не обязан быть математически идеально стабильным, но должен быть stable enough for:

- regression tests;
- reproducible retrieval behavior under same snapshot;
- explainable debugging.

### Required rule

При равных or near-equal scores ranking должен иметь deterministic tie-breakers:

- stronger structural relation;
- closer graph distance;
- same-file precedence;
- lexical/path tie-break;
- stable entity id ordering as final fallback.

---

## Prohibitions

- Ranking **MUST NOT** быть vector-first.
- Text similarity **MUST NOT** вытеснять authority structural matches.
- `context packet` **MUST NOT** заполняться purely by lexical overlap.
- Partial parser output **MUST NOT** трактоваться как full-confidence graph truth.
- Ranking **MUST NOT** зависеть от opaque scoring, который нельзя объяснить через `evidence`.

---

## Consequences

### Positive

- Retrieval лучше соответствует структуре кода, а не только тексту.
- `context packet` становится полезнее для AI coding tasks.
- Vector layer можно добавлять без захвата архитектуры.
- Ranking легче дебажить и тестировать.

### Negative

- Structural ranking потребует больше graph-aware logic, чем простой text/vector search.
- Для слабых parser environments recall может временно страдать без secondary signals.
- Нужно будет отдельно продумать concrete weighting policy и calibration.

### Tradeoff accepted

Мы сознательно предпочитаем **explainable structure-aware retrieval** вместо более простого, но шумного vector-first или text-first ranking.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Candidate set сначала собирается structural means, а не global lexical/vector scan only.
2. Top-ranked units explainable через structural evidence.
3. Embeddings используются только как reranking / recall-assist layer.
4. Partial graph knowledge снижает confidence и отражается в evidence.
5. Token budget shaping preserves authority context before broad noisy expansion.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- concrete score composition and calibration;
- raw code fetch policy after ranking;
- confidence model for `context packet`;
- persistence/caching of ranking-friendly projections;
- host hint contract for retrieval queries.
