# ADR-006: Fetch Raw Code Late and Only for Ranked Spans

**Status**: Accepted  
**Date**: 2026-03-07  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-002` зафиксировал, что основным внешним контрактом библиотеки является `context packet`, а full raw code не должен быть default payload.  
`ADR-005` зафиксировал, что контекст должен ранжироваться structural-first.

После этого остаётся следующий критический вопрос: когда именно система имеет право догружать raw code.

Если raw code fetch не нормировать, быстро появятся системные проблемы:

- token budget будет сгорать на целых файлах вместо точечных implementation details;
- structural retrieval будет обесценен, потому что consumers снова начнут просить “дай весь файл”;
- разные hosts начнут по-разному догружать код и терять единое поведение;
- noisy context будет вытеснять authority units and impact hints;
- система фактически скатится обратно к large-context code dumping.

С другой стороны, полностью запретить raw code нельзя, потому что часть задач действительно требует видеть реализацию:

- bug fixing in control flow;
- side effects and state changes;
- SQL/HTTP/IO behavior;
- exact edit target before patching;
- test and regression reasoning.

Нужно принять решение о raw-code fetch policy.

---

## Decision Drivers

- Экономия token budget
- Высокая precision контекста
- Сохранение преимуществ structural retrieval
- Поддержка edit-oriented and bug-oriented workflows
- Единое поведение для разных host systems
- Объяснимость того, почему конкретный raw code был догружен
- Минимизация full-file dumping

---

## Considered Options

### Option 1. Full-file fetch by default

После ranking система догружает целые релевантные файлы, чтобы downstream consumer сам разбирался.

### Option 2. Late targeted raw-code fetch after ranking

Сначала система возвращает `context packet` со структурой и skeletons, а затем при необходимости
догружает только top-ranked spans or enclosing units.

### Option 3. No raw code in the library

Библиотека вообще не занимается raw code retrieval и отдаёт только structure-level outputs.

---

## Decision

Мы принимаем **Option 2: Late targeted raw-code fetch after ranking**.

Raw code должен догружаться **только после structural candidate selection и ranking**.

Raw code retrieval не является первичным retrieval mode.  
Он является **вторым, управляемым и budget-aware шагом**, который применяется только к уже выбранным top-ranked targets.

---

## Core Rule

Правильная последовательность такая:

1. project snapshot and indexing
2. structural candidate generation
3. ranking
4. `context packet`
5. selective raw-code fetch if needed

Нельзя перепрыгивать сразу к raw code, минуя structural narrowing.

---

## Default Retrieval Shape

По умолчанию downstream consumer должен получать:

- repo map;
- relevant units;
- skeletons;
- impact hints;
- evidence;
- confidence;
- budget information.

Raw code по умолчанию не включается.

---

## When Raw Code Is Allowed

Raw code fetch допустим только при наличии одной или нескольких причин.

### Allowed triggers

- target unit identified as likely edit location;
- behavior cannot be understood from skeleton/docstring/signature only;
- impact analysis указывает на sensitive implementation path;
- host explicitly requests implementation detail;
- ranking confidence medium/low and more evidence is needed;
- exact patch preparation requires body-level context;
- nearest relevant test body is needed for change validation.

### Disallowed triggers

Нельзя догружать raw code только потому, что:

- файл вообще попал в candidate set;
- у consumer “есть свободные токены”;
- lexical similarity высокая, но structural relevance weak;
- host хочет “на всякий случай побольше контекста”.

---

## Fetch Granularity Policy

Raw code должен догружаться не whole-file first, а от меньшего к большему.

### Level 1. Target span

Минимальный предпочтительный уровень:

- конкретный span;
- changed hunk;
- exact symbol body region;
- selected test body region.

### Level 2. Enclosing unit

Если span недостаточен, допускается догрузка enclosing unit:

- function/method body;
- class member block;
- namespace/module fragment;
- document section block.

### Level 3. Local neighborhood

Если этого всё ещё недостаточно, допускается ограниченное расширение:

- preceding and following sibling units;
- small surrounding context window;
- directly related helper bodies.

### Level 4. Whole file

Whole-file fetch допускается только как исключение, когда:

- файл маленький;
- relevant behavior genuinely distributed across the file;
- language/file type makes unit-level slicing unreliable;
- host explicitly asks for full file and budget allows it.

Whole-file fetch не должен быть обычным путем.

---

## Budget Policy

Raw code retrieval должен иметь собственную budget discipline.

### Required rule

Сначала нужно сохранить coverage of:

- authority units;
- structural evidence;
- impact hints;
- skeletons.

Только после этого budget может тратиться на raw code expansion.

### Required behavior

Если budget ограничен:

- one or few highest-ranked bodies лучше, чем many partial noisy files;
- raw code не должен вытеснять `evidence`, `impact_hints` и authority skeletons;
- whole-file expansion режется раньше, чем targeted span fetch.

---

## Evidence Rule

Каждый raw-code fetch должен быть explainable.

Система должна уметь ответить:

- какой target вызвал fetch;
- какой ranking reason привёл к этому;
- почему skeleton оказался недостаточен;
- какой fetch level был выбран;
- что было отброшено по budget limits.

Эта информация должна быть доступна host system и при необходимости попадать в diagnostics/evidence trace.

---

## Confidence Rule

Raw code fetch не должен скрывать uncertainty.

### Required behavior

Если system retrieval confidence низкий:

- raw code fetch может быть расширен для уточнения;
- но confidence должен оставаться низким, пока structural ambiguity не снята;
- extra code не должен автоматически трактоваться как stronger semantic certainty.

Иначе система начнёт путать “больше текста” с “лучше понимание”.

---

## Interaction with `context packet`

`Context packet` остаётся primary retrieval product.

Raw code должен рассматриваться как:

- optional attachment;
- second-stage retrieval result;
- targeted implementation supplement.

Он не должен разрушать базовую contract shape `context packet`.

### Required integration rule

Host system сначала работает с `context packet`, и только затем:

- запрашивает raw bodies for selected units;
- или вызывает helper path, который делает late fetch controlled by library policy.

---

## Host Integration Rule

Host systems не должны самостоятельно реализовывать свои несовместимые raw-code fetch strategies, если они используют библиотеку как canonical retrieval layer.

### Required rule

Если host использует library retrieval API, то policy выбора:

- target spans;
- expansion level;
- budget-aware fetch scope

должна идти через canonical library mechanism, а не через ad hoc host logic по умолчанию.

Host может передавать hints, но не должен ломать canonical policy без явного override.

---

## Why This Shape

Такой подход нужен, чтобы одновременно:

- сохранить преимущества structural retrieval;
- не лишать систему доступа к implementation detail;
- не вернуться к full-file dumping;
- сделать поведение retrieval предсказуемым и одинаковым across hosts.

Это делает raw code не “основным продуктом”, а controlled escalation path.

---

## Prohibitions

- Raw code **MUST NOT** входить в `context packet` по умолчанию.
- Whole-file fetch **MUST NOT** быть первым fetch level.
- Budget growth **MUST NOT** автоматически означать “добавь больше файлов целиком”.
- Host **MUST NOT** обходить canonical retrieval narrowing как default integration pattern.
- Extra raw code **MUST NOT** интерпретироваться как автоматическое повышение confidence.

---

## Consequences

### Positive

- Token budget расходуется точнее.
- Structural retrieval остаётся основным механизмом.
- Edit-oriented workflows получают implementation detail без code dump.
- Поведение системы становится более единым и explainable.

### Negative

- Появляется ещё один retrieval stage, который нужно отдельно реализовать и тестировать.
- Некоторым host workflows захочется более агрессивный fetch, и для этого потребуется явный override path.
- Нужно аккуратно решать slicing policy по разным языкам и file types.

### Tradeoff accepted

Мы сознательно предпочитаем **late targeted escalation to raw code** вместо простого, но шумного whole-file retrieval.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. `context packet` формируется без обязательного raw code.
2. Raw code fetch запускается только после ranking and target selection.
3. Fetch granularity идёт от `span` к `enclosing unit`, потом к `local neighborhood`, и только потом к `whole file`.
4. Каждый raw-code fetch объясним через evidence/reasons.
5. Budget policy сохраняет authority structure before raw expansion.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- confidence model for multi-stage retrieval;
- persistence/caching of fetched spans and rendered skeletons;
- host override policy for raw-code escalation;
- edit-target contract for patch-generation workflows.
