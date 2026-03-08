# ADR-007: Treat Persistence and Cache as Optional Adapters, Not Core Truth

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-001` зафиксировал, что semantic index должен быть injectable Clojure library.  
`ADR-003` зафиксировал canonical internal representation как normalized semantic graph.  
`ADR-006` зафиксировал, что retrieval идет через staged context shaping, а raw code fetch не является default mode.

После этого остаётся важный архитектурный вопрос: как библиотека должна работать с persistence и caching.

Если storage and caching не нормировать, быстро появятся системные проблемы:

- конкретная БД начнет определять архитектуру core;
- cache начнет жить как неявный источник истины;
- разные host systems будут получать разное поведение в зависимости от storage choice;
- in-process use-case станет слишком дорогим из-за обязательной внешней инфраструктуры;
- incremental updates и retrieval latency будут смешаны с persistence concerns.

Нужно принять решение:

- должна ли persistence быть обязательной;
- что именно можно сохранять и кэшировать;
- что считается canonical truth, а что только acceleration layer.

---

## Decision Drivers

- Сохранение library-first архитектуры
- Возможность запускать core in-process без обязательной внешней БД
- Поддержка быстрых повторных запросов и incremental updates
- Изоляция canonical graph model от storage engine choices
- Переносимость между host systems
- Простота тестирования и локальной разработки
- Контроль над stale data и cache invalidation

---

## Considered Options

### Option 1. Mandatory persistent store

Библиотека требует обязательное persistent backend storage с самого начала, и core всегда работает через него.

### Option 2. Optional persistence and cache via adapters

Core работает in-memory по умолчанию, а persistence и cache подключаются как опциональные adapters.

### Option 3. No persistence or cache in the library

Библиотека всегда полностью ephemeral, а caching/persistence — исключительно забота host system.

---

## Decision

Мы принимаем **Option 2: Optional persistence and cache via adapters**.

Persistence и cache должны существовать как **подключаемые adapters**, а не как обязательный runtime dependency и не как canonical truth source.

Core обязан уметь:

- работать полностью in-memory;
- использовать persistence adapter, если host его предоставляет;
- использовать cache adapters для ускорения parsing, graph assembly и retrieval;
- сохранять одинаковую semantic behavior независимо от наличия storage/cache, кроме performance characteristics.

---

## Canonical Truth Rule

Canonical truth в системе определяется не persistence layer и не cache layer.

### Canonical truth

Канонической истиной являются:

- project snapshot input;
- normalized facts derived from that snapshot;
- canonical semantic graph and its deterministic projections.

### Not canonical truth

Не являются canonical truth:

- cache entries;
- rendered skeleton cache;
- raw-code fetch cache;
- storage row ids;
- query result caches;
- vector stores;
- transport DTO caches.

Persistence может сохранять canonical structures, но не определяет их форму и semantics.

---

## Required Adapter Split

Persistence и cache должны быть разведены концептуально, даже если физически используют одну и ту же технологию.

### Persistence adapter

Отвечает за более долгоживущие данные:

- snapshot metadata;
- normalized facts;
- graph fragments;
- derived projections where useful;
- revision markers and invalidation metadata.

### Cache adapter

Отвечает за ускорение, а не за truth:

- parser result cache;
- rendered skeleton cache;
- ranking/query cache;
- fetched-span cache;
- memoized graph projections.

Одно и то же physical store может использоваться для обеих ролей, но логические контракты должны быть разными.

---

## Core Requirements

Core должен удовлетворять следующим правилам:

- запускаться и проходить основные use-cases без обязательного persistence backend;
- не импортировать storage engine semantics в canonical model;
- не связывать public API с storage ids или database handles;
- уметь пересобрать state из snapshot + extraction без cache dependency;
- корректно работать при полном отсутствии cache.

### Why this matters

Иначе библиотека перестанет быть reusable embedding-friendly module и превратится в service-shaped subsystem.

---

## Persistence Scope

Persistence adapter может хранить несколько категорий данных, но только как materialization of canonical model.

### Allowed persisted artifacts

- file inventory and snapshot metadata;
- normalized extraction results;
- graph fragments by file or snapshot;
- repo-map projections;
- invalidation metadata;
- optional retrieval diagnostics history.

### Conditionally allowed persisted artifacts

- ranked context packets;
- raw-code span fetch records;
- pre-rendered skeleton text;
- query traces for observability/debugging.

Эти данные допустимы, если они трактуются как derived artifacts, которые можно перестроить.

---

## Cache Scope

Cache adapter нужен для speed, а не для correctness.

### Allowed cache categories

- parser output cache by file hash;
- normalized fact cache by adapter fingerprint;
- graph fragment cache by snapshot/file hash;
- projection cache for repo map and skeletons;
- query result cache keyed by snapshot + query + budget;
- raw span cache keyed by file hash + span.

### Required rule

Каждый cache key должен быть привязан к:

- snapshot identity or file hash;
- adapter fingerprint or rendering fingerprint where relevant;
- query/budget shape where relevant.

Это нужно, чтобы stale data не выглядела как valid truth.

---

## Invalidation Rule

Persistence и cache architecture должны быть explicitly invalidation-aware.

### Required behavior

При изменении файла или snapshot:

- затронутые parser caches invalidated;
- normalized facts recomputed;
- affected graph fragments replaced;
- affected projections refreshed or invalidated;
- unrelated cached artifacts preserved where safely reusable.

### Required principle

Invalidate by structural dependency, not by “drop everything” as default behavior, except where host chooses brute-force rebuild explicitly.

---

## Failure and Degradation Rule

Storage and cache failures не должны ломать semantic correctness там, где возможен safe fallback.

### Required behavior

Если cache недоступен:

- система должна продолжить работу без него;
- latency может ухудшиться;
- correctness не должна нарушаться.

Если persistence adapter недоступен:

- in-process/in-memory mode должен оставаться возможным, если host так настроен;
- host может выбрать degraded mode;
- library не должна silently invent persisted state.

---

## Consistency Rule

Библиотека должна сохранять одно и то же смысловое поведение при:

- cold run without persistence;
- warm run with persistence;
- warm run with cache hits;
- partial cache invalidation.

Различаться должна в первую очередь производительность, а не retrieval semantics.

---

## Why This Shape

Такой подход нужен, чтобы:

- сохранить `library-first` nature системы;
- не навязать потребителям лишнюю инфраструктуру;
- дать host systems freedom of deployment;
- всё равно получить ускорение через caching and optional persistence;
- удержать canonical truth внутри graph model, а не в storage engine.

Это делает persistence and cache operational concerns, а не архитектурным ядром.

---

## Prohibitions

- Persistence **MUST NOT** быть обязательным prerequisite для базового in-process use-case.
- Cache **MUST NOT** считаться canonical truth source.
- Core **MUST NOT** зависеть от конкретной СУБД, KV store, datalog engine или vector DB.
- Public API **MUST NOT** возвращать storage-specific handles or ids as primary contract.
- Cache hit/miss **MUST NOT** менять retrieval semantics, кроме допустимого stale-detection/degraded-mode поведения.
- Derived artifacts **MUST NOT** жить как единственная восстанавливаемая форма индекса.

---

## Consequences

### Positive

- Библиотека сохраняет embedding-friendly форму.
- Local and test workflows не требуют внешней инфраструктуры.
- Host systems могут выбирать подходящий persistence/cache backend.
- Производительность можно наращивать без изменения core semantics.
- Incremental indexing получает естественную базу для reuse и invalidation.

### Negative

- Появляется больше adapter surface area.
- Нужно дисциплинированно проектировать invalidation strategy.
- Некоторые hosts захотят persistent-first mode, который потребует дополнительной operational tuning.

### Tradeoff accepted

Мы сознательно выбираем **optional persistence and cache with strict truth boundaries** вместо более простого, но архитектурно связывающего mandatory-store design.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Core может создать индекс, обновить его и ответить на retrieval queries без обязательного persistence backend.
2. Persistence adapter можно подключить без изменения canonical graph shape.
3. Cache adapter ускоряет extraction/projection/query steps, но не становится truth source.
4. Cache keys и invalidation привязаны к snapshot/hash/fingerprint semantics.
5. При отключении cache correctness сохраняется, а меняется только performance profile.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- confidence model under stale/partial conditions;
- host query contract and override semantics;
- observability and diagnostics persistence policy;
- concrete adapter interfaces for persistence and caching backends.
