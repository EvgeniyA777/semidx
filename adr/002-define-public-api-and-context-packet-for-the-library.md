# ADR-002: Define a Small Public API and a Standard Context Packet for the Library

**Status**: Accepted  
**Date**: 2026-03-07  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-001` зафиксировал, что semantic index должен существовать как injectable Clojure library.

После этого остаётся следующий риск: библиотека может получить слишком широкий и размытый public API.
Если это произойдёт, то:

- host systems начнут вызывать внутренние детали напрямую;
- adapters, storage и graph internals протекут в host code;
- разные интеграции начнут запрашивать данные в несовместимых формах;
- library перестанет быть стабильным модулем и превратится в набор внутренних утилит.

Кроме того, нужен единый формат результата, который можно безопасно передавать AI-агентам,
оркестраторам и другим automation consumers, не раскрывая весь внутренний индекс.

Нужно принять решение:

- каким должен быть минимальный public API библиотеки;
- какой стандартный `context packet` библиотека должна отдавать наружу.

---

## Decision Drivers

- Небольшая и стабильная public surface
- Минимальная связанность host code с internal representation
- Единый формат для AI/context consumers
- Поддержка incremental indexing
- Поддержка нескольких use-cases без API explosion
- Возможность thin wrappers поверх того же API
- Контроль token budget и context size на boundary уровня API

---

## Considered Options

### Option 1. Expose graph/storage primitives directly

Библиотека отдаёт наружу internal graph, storage handles, symbol tables и low-level query API.

### Option 2. Small task-oriented API plus standard context packet

Библиотека отдаёт наружу только несколько high-level entrypoints и стандартизованный
результат для downstream consumers.

### Option 3. One endpoint per use-case

Библиотека предоставляет много специализированных entrypoints:
`get-repo-map`, `get-file-skeletons`, `find-symbol`, `find-callers`, `find-tests`,
`explain-impact`, `get-ranking`, `get-module-summary`, и так далее.

---

## Decision

Мы принимаем **Option 2: Small task-oriented API plus standard context packet**.

Public API библиотеки должен быть **маленьким, стабильным и task-oriented**.
Внешним потребителям не должны раскрываться graph/storage internals как контракт.

---

## Public API

Библиотека должна поддерживать следующий минимальный public API.

### 1. `create-index`

Назначение:
- создать новый индекс из project snapshot или file inventory.

Ожидаемая роль:
- первичная индексация;
- подготовка in-memory/on-disk representation;
- возврат host-owned index handle.

### 2. `update-index`

Назначение:
- инкрементально обновить индекс по списку изменённых файлов, diff units или snapshot delta.

Ожидаемая роль:
- дешёвый reindex только затронутых частей;
- сохранение graph consistency без полной перестройки.

### 3. `repo-map`

Назначение:
- вернуть компактную map-level representation репозитория.

Ожидаемая роль:
- дать host system или AI consumer high-level structural overview;
- использоваться как cheap first-pass context.

### 4. `resolve-context`

Назначение:
- вернуть стандартный `context packet` по задаче, символу, пути, diff или query intent.

Ожидаемая роль:
- основной retrieval entrypoint;
- точка, через которую host systems получают релевантный контекст для AI tasks.

### 5. `impact-analysis`

Назначение:
- вернуть impact hints по изменяемым путям, symbols или semantic units.

Ожидаемая роль:
- оценка downstream effect;
- поиск затрагиваемых модулей, callers, tests и risky neighbors.

### 6. `skeletons`

Назначение:
- вернуть skeleton representation для выбранных units/files/modules.

Ожидаемая роль:
- контекстная компрессия для LLM/automation use-cases.

---

## API Boundaries

Public API должен удовлетворять следующим ограничениям:

- Host не должен зависеть от internal graph schema.
- Host не должен знать, как именно хранятся edges, symbol tables или ranking internals.
- Public API должен принимать plain data structures и возвращать plain data structures.
- Все результаты должны быть deterministic enough для тестов при одинаковом snapshot/config.
- Token-aware shaping должен происходить на уровне `resolve-context`, а не руками каждого host.

---

## Standard Context Packet

Библиотека должна возвращать наружу единый `context packet`.

Этот пакет является **основным контрактом между semantic index и host system**.

### Required top-level sections

`context packet` должен содержать:

- `query`
- `repo_map`
- `relevant_units`
- `skeletons`
- `impact_hints`
- `evidence`
- `budget`
- `confidence`

### Section semantics

#### `query`

Описывает, что именно было запрошено:

- task intent;
- target paths;
- target symbols;
- optional diff summary;
- optional host hints.

#### `repo_map`

Компактный обзор релевантной части репозитория:

- top modules/files;
- namespace/module summaries;
- structural grouping only at useful granularity.

#### `relevant_units`

Список наиболее релевантных semantic units:

- files;
- classes/types;
- functions/methods;
- spans;
- symbol identities;
- ranking score or priority order.

#### `skeletons`

Сжатое представление релевантных units:

- signatures;
- docstrings/comments if useful;
- structural nesting;
- no long raw implementation by default.

#### `impact_hints`

Указатели на вероятные последствия изменения:

- callers/callees;
- imports/dependents;
- related tests;
- risky neighbors;
- likely breakage surface.

#### `evidence`

Короткая трасса того, почему эти units были выбраны:

- matched symbols;
- graph relations;
- path relevance;
- diff overlap;
- ranking reasons.

#### `budget`

Информация о context shaping:

- requested token budget if provided;
- actual packet size estimate;
- truncation/compression flags.

#### `confidence`

Оценка качества retrieval result:

- high / medium / low or numeric score;
- optional missing-data hints;
- explicit note when full semantic certainty is unavailable.

---

## Excluded from the Context Packet

`context packet` **MUST NOT** по умолчанию содержать:

- весь raw source code релевантных файлов;
- весь internal dependency graph;
- storage-specific ids and persistence internals;
- parser-specific node dumps;
- host-specific orchestration metadata unrelated to retrieval.

Full raw code может догружаться отдельно и точечно, но не должен быть default payload.

---

## Why This Shape

Такой API и такой packet shape нужны, чтобы:

- разделить retrieval от orchestration;
- дать AI consumer'у сжатый, доказательный и ограниченный контекст;
- не раскрывать implementation details индекса;
- избежать explosion of special-purpose endpoints;
- позволить CLI, HTTP wrapper, batch worker и host applications использовать один и тот же core contract.

---

## Prohibitions

- Public API **MUST NOT** раскрываться как thin wrapper над internal storage schema.
- Public API **MUST NOT** требовать от host понимания parser-specific internals.
- `resolve-context` **MUST NOT** возвращать unlimited payload без budget shaping.
- `context packet` **MUST NOT** быть завязан на единственный use-case вроде только code review.
- New use-cases **MUST NOT** приводить к бесконтрольному росту числа top-level API functions.

---

## Consequences

### Positive

- Библиотека получает небольшую и понятную public surface.
- Интеграции становятся унифицированными.
- AI consumers получают одинаковый retrieval contract.
- Wrappers и host systems могут меняться без изменения core semantics.

### Negative

- Некоторым интеграциям может не хватать low-level access, и для них придётся отдельно решать extension path.
- Придётся дисциплинированно защищать packet shape от расползания.
- Некоторые продвинутые use-cases будут реализовываться через дополнительные query hints, а не через прямой low-level доступ.

### Tradeoff accepted

Мы сознательно выбираем **меньше API и больше стандартизации результата**, даже если это ограничивает часть низкоуровневой гибкости.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. У библиотеки есть ограниченный public API с шестью canonical entrypoints:
   - `create-index`
   - `update-index`
   - `repo-map`
   - `resolve-context`
   - `impact-analysis`
   - `skeletons`
2. Ни один host integration path не требует knowledge of internal graph/storage representation.
3. `resolve-context` возвращает единый `context packet`, а не host-specific ad hoc structures.
4. `context packet` содержит evidence, budget и confidence, а не только “полезные куски кода”.
5. Full raw code остаётся отдельным retrieval step, а не базовой формой ответа.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- internal representation of the index;
- parser adapter contract;
- ranking strategy and relevance scoring;
- raw code fetch policy after context packet generation;
- wrapper API for HTTP/CLI/LSP surfaces.
