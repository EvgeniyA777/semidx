# ADR-009: Define a Structured Host Query Contract with Soft Hints by Default

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-002` зафиксировал внешний output contract в виде `context packet`.  
`ADR-005` зафиксировал structural-first ranking.  
`ADR-006` зафиксировал late raw-code fetch.  
`ADR-008` зафиксировал confidence model, которую host systems должны уметь интерпретировать.

После этого остается вторая половина boundary: как именно host system должна запрашивать retrieval.

Если входящий query contract не стандартизовать, быстро появятся проблемы:

- разные hosts начнут по-разному кодировать intent;
- retrieval hints будут передаваться в ad hoc форме;
- host-specific logic начнет протекать в core;
- одни hosts будут слишком жестко форсировать результаты, ломая ranking policy;
- другие будут передавать слишком мало сигнала, и retrieval станет шумным.

Нужно принять решение:

- какой должна быть каноническая форма retrieval query;
- какие части запроса обязательны;
- как должны работать hints, constraints и explicit overrides.

---

## Decision Drivers

- Единый входной boundary для всех host systems
- Минимальная связанность host logic с internal retrieval mechanics
- Поддержка разных use-cases без API explosion
- Возможность передавать explicit intent и constraints
- Сохранение контроля библиотеки над ranking/fetch policy
- Объяснимость того, как host hints повлияли на результат
- Безопасность для автономных AI consumers

---

## Considered Options

### Option 1. Free-form host query

Host передает произвольный map/string prompt, а библиотека сама пытается догадаться, что с этим делать.

### Option 2. Structured host query with soft hints by default

Host передает явную структуру запроса: intent, targets, constraints, hints и optional overrides.
Hints по умолчанию мягкие, а hard override — отдельный явный механизм.

### Option 3. One host-specific query shape per integration

Каждая интеграция сама определяет свой входной contract и адаптирует библиотеку под себя.

---

## Decision

Мы принимаем **Option 2: Structured host query with soft hints by default**.

Библиотека должна принимать **канонический структурированный retrieval query**.

### Core rule

- Host обязан передавать retrieval intent как structured data, а не как свободную строку.
- Hints по умолчанию трактуются как **soft guidance**, а не как приказ.
- Hard constraints и explicit overrides должны быть отдельными и редкими полями.

---

## Canonical Query Shape

Host query должен быть plain data structure с такими top-level sections:

- `intent`
- `targets`
- `constraints`
- `hints`
- `options`
- `trace`

Все секции не обязаны быть непустыми, но общая форма должна быть стабильной.

---

## Required Sections

### `intent`

Описывает, зачем нужен retrieval.

Минимальная роль:

- code understanding
- change impact
- edit preparation
- test targeting
- review support
- bug investigation

Это не internal implementation knob, а business-level retrieval purpose.

### `targets`

Описывает, что именно считается центром запроса.

Допустимые target categories:

- paths
- symbols
- changed spans
- diff summary
- module/namespace identifiers
- tests or production units explicitly named by host

Если target не задан совсем, host должен по крайней мере передать meaningful intent и some initial scope hint.

### `constraints`

Описывает жёсткие ограничения, которые retrieval должен уважать.

Примеры:

- token budget
- snapshot or revision id
- language boundary
- allowed path prefix
- maximum raw-code expansion level
- freshness requirement

Constraints являются hard boundary, а не suggestion.

---

## Optional Sections

### `hints`

Hints — это мягкие предпочтения host system.

Примеры:

- likely important paths
- preferred namespaces
- suspected edit area
- preferred test proximity
- prefer definitions over callers
- prefer breadth over depth

### `options`

Опциональные retrieval mode knobs.

Примеры:

- include tests
- include impact hints
- include raw-code escalation eligibility
- favor compact packet
- favor higher recall

`Options` не должны позволять host напрямую обойти core architecture.

### `trace`

Operational metadata for observability.

Примеры:

- trace id
- host request id
- actor id
- task id
- session id

`Trace` нужен для correlation, а не для retrieval semantics.

---

## Soft Hints Rule

`Hints` по умолчанию должны быть soft.

### Meaning

Если host передает:

- `preferred_paths`
- `suspected_symbols`
- `focus_on_tests`

то библиотека должна воспринимать это как signal to boost or narrow candidates, но не как приказ подменить ranking truth.

### Required behavior

Hints могут:

- повышать приоритет кандидатов;
- сузить candidate generation;
- влиять на tie-breaking;
- включаться в evidence.

Hints не должны:

- вытеснять stronger structural evidence;
- превращать `low` confidence retrieval в `high`;
- заставлять систему игнорировать conflicting signals.

---

## Hard Constraint Rule

`Constraints` должны быть явными и отличаться от hints.

### Allowed hard constraints

- strict token budget
- exact snapshot/revision pin
- path allowlist
- no raw code
- max raw-code level
- language restriction

### Required behavior

Если constraint задан, библиотека должна либо:

- его уважить;
- либо явно вернуть, что запрос в заданных границах не может быть выполнен качественно.

Нельзя silently игнорировать hard constraints.

---

## Explicit Override Rule

Host override допустим, но только как отдельный явный механизм.

### Why this exists

Иногда host действительно хочет:

- форсировать full-file fetch;
- форсировать path-only retrieval;
- отключить tests;
- запросить higher-recall degraded mode.

### Required rule

Такие случаи должны идти через explicit override semantics, а не через обычные hints/options.

Override должен:

- быть явным;
- оставлять trace в diagnostics/evidence;
- по возможности понижать confidence, если ломает canonical retrieval policy;
- считаться exceptional path, а не default integration mode.

---

## Query Semantics Rule

Host query должен описывать **что нужно получить**, а не **как внутри библиотеки это вычислить**.

### Allowed query language

Host может задавать:

- intent;
- targets;
- constraints;
- preferences.

### Disallowed query language

Host не должен задавать parser-/graph-internal instructions вроде:

- “используй `related_to`, но игнорируй `imports`”
- “дай parser nodes from tree-sitter”
- “сделай ranking only by lexical overlap”
- “обойди candidate generation и возьми весь file set”

Внутренний retrieval plan остается под контролем библиотеки.

---

## Explainability Rule

Результат должен уметь показать, как host query повлиял на retrieval.

### Required evidence categories

В `evidence` или diagnostics должна быть возможность показать:

- какие targets были explicit;
- какие hints повлияли на ranking;
- какие constraints ограничили пакет;
- какие overrides были применены;
- где retrieval проигнорировал hint, потому что structural evidence stronger.

Это нужно, чтобы host systems и люди могли дебажить retrieval behavior.

---

## Query Validation Rule

Библиотека должна валидировать query shape на boundary.

### Required validation

Нужно уметь ловить:

- missing intent with no usable targets;
- contradictory constraints;
- unsupported override;
- invalid budget values;
- malformed path/symbol lists;
- impossible combinations вроде `no raw code` + `require full file`.

### Required behavior

Validation failures должны быть явными retrieval errors, а не тихими implicit fallbacks.

---

## Why This Shape

Такой query contract нужен, чтобы:

- сделать все host integrations совместимыми;
- отделить host intent от library internals;
- сохранить canonical retrieval policy under library control;
- всё же дать host systems достаточно сигнала для high-quality retrieval;
- поддержать explainable and safe autonomous use.

---

## Prohibitions

- Host query **MUST NOT** быть free-form primary contract.
- Hints **MUST NOT** трактоваться как hard command by default.
- Host **MUST NOT** управлять parser internals, graph internals or ranking internals напрямую.
- Overrides **MUST NOT** прятаться в обычных hints.
- Invalid or contradictory query shapes **MUST NOT** silently degrade into arbitrary retrieval behavior.

---

## Consequences

### Positive

- Все host systems получают единый retrieval boundary.
- Интеграции становятся предсказуемее и проще.
- Retrieval behavior легче объяснять и тестировать.
- AI consumers могут передавать intent without taking over internal policy.

### Negative

- Появляется отдельный input contract, который нужно поддерживать и валидировать.
- Некоторым host systems захочется более низкоуровневый контроль.
- Нужно будет отдельно продумать concrete schema and examples for the query contract.

### Tradeoff accepted

Мы сознательно выбираем **жесткий structured boundary with soft hints by default** вместо более гибкого, но размывающего архитектуру free-form integration.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Библиотека принимает canonical structured retrieval query.
2. `intent`, `targets`, `constraints`, `hints`, `options`, `trace` различаются семантически.
3. Hints по умолчанию soft и не могут ломать structural-first retrieval policy.
4. Hard constraints валидируются и явно уважаются или явно отклоняются.
5. Overrides трассируются как exceptional path и не маскируются под обычные hints.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- observability and diagnostics contract;
- concrete query schema/examples;
- host override policy and safety guardrails;
- autonomous-action guardrails for AI consumers.
