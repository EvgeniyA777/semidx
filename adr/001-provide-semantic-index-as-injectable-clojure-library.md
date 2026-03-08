# ADR-001: Provide Semantic Index as an Injectable Clojure Library

**Status**: Accepted  
**Date**: 2026-03-07  
**Deciders**: project owner

---

## Context and Problem Statement

Проекту нужен semantic indexing слой, который:

- строит структурное представление кодовой базы;
- извлекает `symbols`, `definitions`, `references`, `skeletons`, dependency hints и context packets;
- может встраиваться в разные хост-системы без навязывания им отдельного runtime или deployment model.

Если реализовать этот слой как отдельный сервис с самого начала, то интеграция усложнится:

- каждому потребителю понадобится отдельный процесс, конфигурация и transport layer;
- жизненный цикл индекса окажется отделён от жизненного цикла хост-системы;
- library use-case станет вторичным, хотя именно он нужен для гибкой интеграции.

Если реализовать его как код, который копируется в каждый продукт, то быстро появятся:

- drift между интеграциями;
- несогласованные API;
- дублирование логики индексации, graph-building и context packaging.

Нужно принять архитектурное решение о том, в какой форме должен существовать semantic indexing модуль по умолчанию.

---

## Decision Drivers

- Минимальная стоимость интеграции в разные системы
- Чёткие границы ответственности между host system и indexing module
- Возможность reuse без форка кода
- Тестируемость и детерминированность
- Возможность добавлять host-specific adapters без изменения core
- Отсутствие обязательного network hop для локального использования
- Совместимость с Clojure/JVM ecosystem

---

## Considered Options

### Option 1. Standalone service first

Semantic index существует как отдельный HTTP/gRPC сервис, а все системы интегрируются с ним по сети.

### Option 2. Injectable Clojure library first

Semantic index существует как отдельный Clojure/JVM module, подключаемый как библиотека.  
Хост-система встраивает его в свой процесс и передаёт зависимости через конфигурацию и protocols/interfaces.

### Option 3. Product-local implementation

Каждая система реализует semantic indexing у себя локально, без общего library module.

---

## Decision

Мы принимаем **Option 2: Injectable Clojure library first**.

Semantic indexing subsystem должен существовать как **отдельный модуль-библиотека на Clojure/JVM**, который можно подключить в любую хост-систему как зависимость.

### Primary form

Основная форма поставки:

- отдельный Clojure module;
- подключение как library dependency;
- публичный API из небольшого набора стабильных entrypoints;
- host-owned lifecycle;
- host-owned storage wiring;
- host-owned telemetry wiring.

### Public responsibility of the library

Библиотека отвечает за:

- построение и обновление structural index;
- извлечение `definitions`, `references`, `docstrings`, `imports/requires`, `call sites`;
- генерацию `skeletons`;
- построение symbol/dependency graph;
- формирование query-oriented outputs:
  - repo map;
  - relevant symbol set;
  - impact hints;
  - minimal context packet для AI/automation consumers.

### Host responsibility

Хост-система отвечает за:

- запуск процесса и lifecycle management;
- orchestration и task routing;
- выбор transport layer;
- секреты, auth, tenancy;
- durable storage policy;
- observability sinks и deployment model.

### Required architecture shape

Модуль должен быть разделён на два слоя:

1. **Core**  
   Чистая или почти чистая логика:
   - normalization;
   - skeletonization;
   - symbol graph assembly;
   - ranking and query planning;
   - context packet generation.

2. **Adapters**  
   Подключаемые integration points:
   - file system reader;
   - parser adapter (`tree-sitter`, `clj-kondo`, future analyzers);
   - storage adapter;
   - cache adapter;
   - telemetry adapter.

### Injection model

Библиотека не должна жёстко зависеть от конкретной host system.  
Все внешние зависимости должны передаваться через:

- configuration map;
- Clojure protocols / multimethods / explicit adapter fns;
- host-provided callbacks where necessary.

### Optional wrappers

Поверх библиотеки позже **могут** появиться:

- CLI wrapper;
- HTTP service wrapper;
- batch indexing worker;
- IDE/LSP integration.

Но эти обёртки не являются primary architecture.  
Они не должны определять API core-модуля.

---

## Decision Details

### Packaging

- Базовый артефакт: Clojure/JVM library
- Separate namespace boundary for public API and internal implementation
- Host-facing API должен быть меньше, чем internal implementation surface

### API expectations

Публичный API должен поддерживать как минимум:

- создание индекса;
- инкрементальное обновление индекса;
- запрос repo map;
- запрос relevant context по задаче/символу/пути;
- получение impact hints;
- получение skeleton representation выбранных units.

### Data expectations

Библиотека должна работать с хост-передаваемым project snapshot / file inventory, а не требовать обязательный собственный daemon.

### Portability expectation

Primary portability target:

- любая Clojure/JVM система;
- любая polyglot system, в которой можно встроить JVM-based library layer.

Для non-JVM consumers preferred path — thin wrapper around the library, а не отдельная reimplementation core logic.

---

## Prohibitions

- Core library **MUST NOT** требовать обязательный HTTP server для локального использования.
- Core library **MUST NOT** владеть orchestration logic хост-системы.
- Core library **MUST NOT** навязывать конкретную СУБД, vector store или event bus.
- Core library **MUST NOT** смешивать host-specific business rules с core indexing logic.
- Core library **MUST NOT** требовать Docker, отдельный daemon или sidecar как prerequisite.
- Core library **MUST NOT** раскрывать наружу весь internal graph/storage model как public API.

---

## Consequences

### Positive

- Интеграция в host systems становится дешёвой и быстрой.
- Один canonical implementation заменяет product-local копии.
- Тестирование core возможно без поднятия внешней инфраструктуры.
- Хост-системы сохраняют контроль над lifecycle, transport и storage.
- Позже можно строить wrappers без переписывания ядра.

### Negative

- Нужно очень аккуратно держать public API маленьким и стабильным.
- Нужно заранее продумать adapter boundaries, иначе core быстро протечёт host-specific assumptions.
- Non-JVM systems не смогут использовать модуль напрямую без wrapper layer.

### Tradeoff accepted

Мы сознательно оптимизируемся под **library reuse и host embedding**, а не под service-first deployment.

---

## Definition of Done

Архитектурное решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Semantic index существует как отдельный Clojure module с собственным public API.
2. Core logic запускается in-process без обязательного HTTP/server wrapper.
3. Parser, storage, cache и telemetry подключаются как adapters, а не прошиваются в core.
4. Хотя бы одна host system может получить:
   - repo map;
   - relevant context packet;
   - skeletons;
   - impact hints
   без форка library code.
5. Service/CLI wrappers, если появляются, используют тот же core API, а не дублируют логику.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- public API shape for the library;
- adapter model for parsers and storage;
- on-disk / in-memory index representation;
- context packet contract for host systems;
- wrapper strategy for HTTP/CLI/LSP consumers.
