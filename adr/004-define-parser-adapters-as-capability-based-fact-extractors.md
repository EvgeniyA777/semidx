# ADR-004: Define Parser Adapters as Capability-Based Fact Extractors

**Status**: Accepted  
**Date**: 2026-03-07  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-001` зафиксировал library-first архитектуру.  
`ADR-002` зафиксировал маленький public API и `context packet`.  
`ADR-003` зафиксировал canonical internal representation как normalized semantic graph.

Теперь нужно определить, как parser layer должен подключаться к core.

Система должна уметь работать с несколькими источниками структурных фактов:

- `tree-sitter`
- `clj-kondo`
- language-specific analyzers in the future
- lightweight lexical fallback where richer parsing is unavailable

Если parser adapters не стандартизовать, появятся системные проблемы:

- core начнёт зависеть от конкретных parser internals;
- разные языки будут отдавать несовместимые структуры;
- fallback path окажется ad hoc и непредсказуемым;
- incremental indexing станет ломаться на языках с неполным анализом;
- graph layer начнёт заполняться parser-specific мусором.

Нужно принять решение, каким должен быть контракт parser adapters.

---

## Decision Drivers

- Изоляция core от parser-specific internals
- Возможность поддерживать несколько parsers без переписывания core
- Поддержка частичного и неполного анализа
- Единый normalization boundary
- Поддержка multi-language extraction
- Возможность quality-aware fallback
- Простота тестирования adapters независимо от graph layer

---

## Considered Options

### Option 1. Direct parser integration in core

Core напрямую вызывает `tree-sitter`, `clj-kondo` и другие analyzers, а parser-specific logic живёт внутри core namespaces.

### Option 2. Capability-based parser adapter contract

Каждый parser реализует внутренний adapter contract, объявляет свои capabilities и возвращает normalized facts plus diagnostics.

### Option 3. Single universal parser abstraction with identical guarantees

Все parsers обязаны выдавать полный набор relations и одинаковую quality level, иначе parser не допускается в систему.

---

## Decision

Мы принимаем **Option 2: Capability-based parser adapter contract**.

Parser layer должен быть устроен как набор подключаемых adapters, каждый из которых:

- объявляет поддерживаемые language/capability combinations;
- извлекает normalized facts;
- возвращает diagnostics и confidence metadata;
- может работать с partial quality, не ломая core.

Core не должен знать parser internals.  
Core должен знать только adapter contract и normalized fact shape.

---

## Required Adapter Responsibilities

Каждый parser adapter должен уметь:

- определить, поддерживает ли он данный file/language;
- извлечь normalized facts из одного файла;
- вернуть extraction diagnostics;
- явно объявить, какие fact categories он умеет извлекать качественно, а какие нет.

Parser adapter **не** отвечает за:

- построение canonical semantic graph;
- ranking;
- repo-map assembly;
- context packet shaping;
- host-specific orchestration.

---

## Adapter Contract

Внутренний contract parser adapter должен быть capability-based.

### Required adapter metadata

Каждый adapter должен иметь декларативное описание:

- adapter id;
- supported languages;
- supported file kinds;
- capability set;
- quality hints;
- version or implementation fingerprint.

### Minimum capability vocabulary

Capability set должен уметь выражать как минимум:

- `definitions`
- `references`
- `imports`
- `calls`
- `docstrings`
- `nesting`
- `spans`

Adapter может поддерживать не все capabilities.  
Отсутствие capability должно быть explicit, а не неявным.

### Required extraction entrypoint

Каждый adapter должен иметь canonical extraction entrypoint, который получает:

- file identity;
- file content or host-provided reader result;
- optional language hint;
- optional extraction options.

И возвращает:

- normalized facts;
- diagnostics;
- extraction metadata.

---

## Required Output Shape

Parser adapter не должен возвращать AST/CST как canonical output.

Он должен возвращать **normalized extraction result** из трёх частей:

### 1. `facts`

Список нормализованных фактов:

- definitions;
- references;
- imports;
- calls;
- docstrings/comments;
- spans;
- nesting hints.

### 2. `diagnostics`

Информация о проблемах анализа:

- parse failure;
- partial parse;
- unsupported construct;
- timeout;
- adapter-specific degradation reason.

### 3. `meta`

Метаданные извлечения:

- adapter id;
- language;
- capability set;
- quality/confidence hints;
- source fingerprint;
- extraction mode (`full`, `partial`, `fallback`).

---

## Fact Quality Model

Не все parsers будут одинаково точными.  
Это должно быть встроено в архитектуру, а не скрываться.

### Required rule

Parser adapter должен иметь право возвращать:

- high-confidence facts;
- partial facts;
- unresolved references;
- no facts for unsupported categories.

Core обязан уметь жить с неполнотой и не считать отсутствие relation равным доказанному отсутствию relation.

### Why this matters

Это особенно важно для:

- динамических языков;
- macro-heavy ecosystems;
- generated code;
- mixed-quality parser pipelines;
- fallback extraction paths.

---

## Fallback Policy

Система должна поддерживать fallback path, но fallback не должен притворяться полноценным semantic parser.

### Required fallback rule

Если primary parser не может извлечь часть facts, допустимы:

- secondary parser/enricher;
- lightweight lexical extractor;
- definitions-only mode;
- references-with-low-confidence mode.

### Required fallback semantics

Fallback result должен:

- явно помечаться как `partial` или `fallback`;
- не маскироваться под full semantic extraction;
- не повышать confidence искусственно;
- оставаться пригодным для graph enrichment и ranking with caveats.

---

## Composition Model

Для одного языка может существовать больше одного adapter.

Примеры:

- `tree-sitter` как structural parser;
- `clj-kondo` как richer Clojure-aware enricher;
- lexical fallback as last resort.

### Required rule

Core должен поддерживать adapter composition по схеме:

1. выбрать primary adapter по language/file kind;
2. при необходимости применить zero or more enrichers;
3. объединить normalized facts;
4. сохранить diagnostics и provenance.

Это означает, что parser adapters не обязаны быть mutually exclusive.

---

## Provenance Rule

Каждый normalized fact должен быть traceable back to extraction source.

Минимальная provenance information:

- source adapter id;
- source file;
- source span;
- optional confidence / extraction mode.

Это нужно, чтобы:

- дебажить bad retrieval;
- различать strict facts и soft facts;
- улучшать ranking и confidence model позже;
- сравнивать parser quality между adapters.

---

## What Core Must Not Assume

Core **MUST NOT** предполагать, что любой adapter:

- умеет perfect symbol resolution;
- умеет complete call graph extraction;
- умеет одинаково хорошо работать на всех языках;
- возвращает parser nodes, пригодные как stable ids;
- может безошибочно разбирать broken or incomplete files.

Core должен проектироваться на partial-truth model.

---

## Prohibitions

- Core **MUST NOT** импортировать parser-specific object models как canonical internal representation.
- Adapter contract **MUST NOT** требовать полного semantic fidelity на каждом языке.
- Fallback extractor **MUST NOT** маркироваться как full parser.
- Parser adapter **MUST NOT** строить final `context packet` напрямую.
- Parser adapter **MUST NOT** напрямую писать в canonical graph storage, обходя normalization boundary.

---

## Consequences

### Positive

- Parsers становятся заменяемыми и composable.
- Multi-language support эволюционирует через adapters, а не через разрастание core.
- Core может быть устойчивым к partial extraction.
- Легче сравнивать качество adapters и добавлять новые языки.

### Negative

- Появляется отдельный normalization contract, который надо дисциплинированно поддерживать.
- Нужен quality-aware merge path для composed adapters.
- Некоторые сложные языковые особенности останутся неполно покрытыми без richer analyzers.

### Tradeoff accepted

Мы сознательно предпочитаем **явную неполноту с provenance и diagnostics** вместо ложной видимости “полной семантики” от каждого parser.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. `tree-sitter`, `clj-kondo` и future analyzers могут быть подключены через один adapter contract.
2. Каждый adapter возвращает `facts`, `diagnostics` и `meta`, а не parser-native trees как core output.
3. Capability support declared explicitly, а не угадывается по adapter type.
4. Fallback results помечаются как `partial`/`fallback` и не маскируются под full extraction.
5. Core graph builder может принять extraction result без знания parser internals.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- graph merge rules for multi-adapter extraction;
- ranking and relevance scoring with partial facts;
- confidence model for retrieval outputs;
- persistence/caching strategy for extraction artifacts;
- raw code fetch policy after graph-based context selection.
