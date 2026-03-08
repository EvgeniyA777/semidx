# ADR-003: Represent the Index as a Normalized Semantic Graph

**Status**: Accepted  
**Date**: 2026-03-07  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-001` зафиксировал, что semantic index должен существовать как injectable Clojure library.  
`ADR-002` зафиксировал, что библиотека должна иметь маленький public API и возвращать стандартный `context packet`.

Теперь нужно принять решение о внутреннем представлении индекса.

Если canonical representation выбрать неудачно, возникнут системные проблемы:

- parser-specific data начнёт протекать в core;
- incremental updates станут дорогими или хрупкими;
- `repo-map`, `skeletons`, `impact-analysis` и `resolve-context` будут строиться из разных несовместимых структур;
- storage adapter начнёт определять архитектуру core, а не наоборот.

Нужно выбрать такую внутреннюю модель, которая:

- поддерживает несколько parser adapters;
- подходит для incremental updates;
- удобна для query planning и ranking;
- не зависит от конкретной БД, parser runtime или vector layer.

---

## Decision Drivers

- Единая canonical model для всех query outputs
- Incremental reindex без полной перестройки по каждому изменению
- Независимость core от parser-specific AST/CST shapes
- Поддержка multi-language extraction
- Пригодность для impact analysis и context assembly
- Возможность хранить индекс in-memory и/или через persistence adapters
- Простота тестирования и инспекции

---

## Considered Options

### Option 1. Parser AST/CST as canonical index

Хранить parser trees или близкую к ним структуру как основную внутреннюю модель и строить все ответы прямо поверх неё.

### Option 2. Normalized semantic graph as canonical index

Преобразовывать parser facts в language-agnostic graph of entities and relations, а все внешние ответы строить как projections поверх этой модели.

### Option 3. Vector-first representation

Считать embeddings и vector storage основной формой индекса, а структурные данные хранить только как вспомогательный слой.

---

## Decision

Мы принимаем **Option 2: Normalized semantic graph as canonical index**.

Каноническое внутреннее представление semantic index должно быть **нормализованным semantic graph**, построенным из language-agnostic entities, relations и derived projections.

Parser trees, embeddings и storage-specific layouts не являются canonical model.

---

## Canonical Layers

Внутренняя модель должна состоять из четырёх логических слоёв.

### 1. Snapshot Layer

Фиксирует входное состояние проекта:

- file inventory;
- relative paths;
- content hashes;
- file language;
- optional revision id / snapshot id.

Этот слой нужен, чтобы:

- отслеживать, какие файлы изменились;
- определять scope incremental reindex;
- связывать semantic entities с конкретным snapshot.

### 2. Fact Layer

Parser adapters извлекают нормализованные факты:

- definitions;
- declarations;
- references;
- imports / requires / includes;
- call sites;
- docstrings/comments if available;
- spans and nesting hints.

Fact layer ещё не является canonical answer surface.  
Это нормализованный extraction output, но ещё не итоговая query model.

### 3. Semantic Graph Layer

Из facts строится canonical graph:

- entities;
- relations;
- adjacency/projection indexes.

Именно этот слой считается canonical internal representation.

### 4. Projection Layer

Из canonical graph строятся derived outputs:

- repo map;
- skeletons;
- impact hints;
- relevant units ranking;
- context packet;
- optional test and risk projections.

---

## Canonical Entity Kinds

Semantic graph должен поддерживать как минимум следующие kinds:

- `project`
- `file`
- `unit`
- `symbol`
- `reference`

### `file`

Представляет исходный файл как semantic container:

- relative path;
- language;
- hash;
- top-level metadata.

### `unit`

Представляет семантическую единицу кода или документа:

- namespace/module;
- class/type;
- function/method;
- protocol/interface;
- section/block for non-code documents where relevant.

### `symbol`

Представляет разрешаемую semantic identity:

- name;
- qualified name if available;
- kind;
- defining unit/file linkage.

### `reference`

Представляет usage site:

- symbol-like token or resolved target;
- source span;
- containing unit/file;
- resolution confidence if partial.

---

## Canonical Relation Kinds

Semantic graph должен поддерживать как минимум следующие relation kinds:

- `contains`
- `defines`
- `references`
- `calls`
- `imports`
- `depends_on`
- `related_to`

### Required semantics

- `contains`: file/unit containment
- `defines`: unit defines symbol
- `references`: unit/reference points to symbol or unresolved target
- `calls`: callable usage relation where detectable
- `imports`: module-level import/require/include relation
- `depends_on`: broader dependency relation used for impact analysis
- `related_to`: derived soft relation for ranking when strict resolution is unavailable

Не каждый parser обязан уметь идеально наполнять все relation kinds, но canonical graph shape должен быть единым.

---

## Representation Rules

### Graph first, rendered text second

`Skeletons`, summaries и repo map не должны храниться как единственная canonical truth в виде готовых strings.

Правильный порядок такой:

1. parser extracts facts  
2. facts become semantic graph  
3. graph renders projections such as skeletons and repo map

Это нужно, чтобы:

- можно было менять rendering policy без перестройки всей модели;
- context packet строился из одной и той же canonical structure;
- ranking и impact analysis работали поверх graph, а не поверх already-rendered text.

### Plain Clojure data in core

Core representation должна использовать plain Clojure data structures:

- maps;
- vectors;
- sets;
- indexed lookup maps where needed.

Core model **MUST NOT** требовать конкретную embedded DB или datalog engine как архитектурное ядро.

### Stable enough identities

Entity identifiers должны быть детерминируемыми в рамках одного snapshot и по возможности стабильными между incremental updates.

Identity policy должна опираться на комбинацию:

- snapshot/file identity;
- entity kind;
- qualified name where available;
- span or structural position where needed.

---

## What Is Not Canonical

Следующие вещи могут существовать в системе, но не являются canonical model:

- raw parser AST/CST dumps;
- tree-sitter node ids;
- `clj-kondo` internal analyzer objects;
- vector embeddings;
- rendered markdown/text summaries;
- storage-specific row ids;
- transport-specific DTOs.

Они могут использоваться как inputs, caches, adapters или projections, но не как core contract.

---

## Incremental Update Rule

Incremental update должен работать не как “полная перестройка всего индекса”, а как:

1. определить изменившиеся файлы в snapshot layer;
2. заново извлечь facts только для затронутых файлов;
3. пересобрать связанные graph fragments;
4. обновить affected projections.

Это значит, что graph model должна быть fragment-friendly и поддерживать targeted replacement.

---

## Why This Shape

Нормализованный semantic graph выбран потому, что он:

- лучше parser AST подходит для query use-cases;
- лучше vector-first модели подходит для structural reasoning;
- естественно поддерживает `repo-map`, `skeletons`, `impact-analysis` и `resolve-context`;
- позволяет менять parser adapters без смены core semantics;
- позволяет позже добавить persistence, ranking и vector augmentation как вторичные слои.

---

## Prohibitions

- Canonical model **MUST NOT** быть raw parser tree dump.
- Canonical model **MUST NOT** быть vector-first representation.
- Core graph **MUST NOT** зависеть от одного parser implementation.
- Projections **MUST NOT** жить как независимые truth stores, расходящиеся с graph layer.
- Storage adapter **MUST NOT** определять shape canonical entities and relations.

---

## Consequences

### Positive

- Все query outputs строятся из одной модели.
- Parser adapters становятся заменяемыми.
- Incremental updates получают естественную архитектурную основу.
- Core проще тестировать на plain data fixtures.
- Можно отдельно эволюционировать rendering, ranking и storage.

### Negative

- Появляется дополнительный normalization step между parser и answers.
- Нужно дисциплинированно удерживать entity/relation schema компактной.
- Для некоторых языков resolution quality будет частичной, и graph придётся строить с incomplete information.

### Tradeoff accepted

Мы сознательно принимаем стоимость normalization layer ради устойчивой canonical model и предсказуемых downstream projections.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Parser adapters отдают normalized facts, а не AST/CST как public core data.
2. Core index хранит canonical entities and relations в plain Clojure data.
3. `repo-map`, `skeletons`, `impact-analysis` и `resolve-context` строятся как projections из одной graph model.
4. Embeddings и vector search могут быть подключены позже без замены canonical representation.
5. Incremental update может заменить graph fragments для одного файла без обязательной полной перестройки индекса.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- parser adapter contract;
- ranking and relevance scoring strategy;
- persistence and cache adapters;
- raw code fetch policy after graph-based retrieval;
- confidence model for partial symbol resolution.
