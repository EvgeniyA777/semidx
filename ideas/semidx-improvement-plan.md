# План улучшения Semantic Code Indexing (`semidx`)

**Версия:** 1.0
**Дата:** 2026-06-09
**Статус:** Archived
**Цель документа:** дать разработчикам пошаговую спецификацию для расширения
`semidx`, чтобы он мог полноценно индексировать документационные,
контрактные и нативные мобильные проекты наподобие AutoParts.

> Архивный документ. Предложения сопоставлены с текущей реализацией `semidx`.
> Актуальная концептуальная точка опоры:
> [План работ: расширение `semidx`](../notes/2026-06-09-1015-95e50b0e-5dfa-4033-bc2b-db6db47ffda4.md).

---

## 1. Проблема

Сейчас `semidx` не может построить индекс AutoParts, потому что в проекте пока
нет исходников на поддерживаемых языках.

Текущие поддерживаемые языки:

- Clojure;
- Java;
- Elixir;
- Python;
- TypeScript;
- Lua.

AutoParts сейчас состоит преимущественно из:

- YAML-контрактов;
- Markdown-спецификаций и ADR;
- в дальнейшем — Kotlin/Jetpack Compose;
- в дальнейшем — Swift/SwiftUI;
- вспомогательных SQL, JSON, XML, Gradle Kotlin DSL и shell-файлов.

Из-за отсутствия поддерживаемого языка `create_index` завершает работу ошибкой
`no_supported_languages_found`. Это делает недоступными `repo_map`,
`resolve_context`, `impact_analysis` и другие semantic-инструменты даже для
структурированных YAML и Markdown документов.

## 2. Желаемый результат

После реализации этого плана `semidx` должен:

1. Строить индекс для репозитория, содержащего только YAML и Markdown.
2. Понимать структуру YAML-контрактов, а не индексировать их только как текст.
3. Понимать структуру Markdown-документов по секциям.
4. Индексировать Kotlin и Swift как полноценные языки исходного кода.
5. Индексировать неизвестные текстовые форматы через безопасный fallback.
6. Находить связи между схемами, enum, workflow, state machine и fixtures.
7. Не отказываться от индексации всего репозитория из-за отсутствия
   AST-поддержки для части файлов.
8. Показывать пользователю, какие файлы проиндексированы полноценно, структурно
   или только через текстовый fallback.
9. Повторно использовать существующий индекс и переиндексировать только
   изменившиеся или затронутые файлы.

## 3. Границы работ

### Предположения

- План основан на наблюдаемом публичном поведении MCP-инструментов `semidx`, а
  не на анализе его текущей внутренней реализации.
- Названия внутренних модулей и типов в реализации могут отличаться от
  предложенных в документе.
- Существующие AST-indexers уже используют или могут быть адаптированы к общей
  нормализованной модели без полной переработки.
- Каждый этап должен сохранять обратную совместимость существующих MCP-команд.
- Реализацию выполняет небольшая команда, поэтому задачи разбиты на небольшие
  независимые pull requests с проверяемыми критериями приёмки.

### Входит в план

- универсальная модель индексируемых документов;
- структурная поддержка YAML;
- структурная поддержка Markdown;
- поддержка Kotlin;
- поддержка Swift;
- универсальный текстовый fallback;
- поддержка дополнительных конфигурационных форматов;
- межфайловые ссылки;
- диагностика качества индекса;
- кэширование и инкрементальная переиндексация;
- тестовые fixtures и критерии приёмки.

### Не входит в первую реализацию

- полноценная семантическая проверка бизнес-контрактов;
- генерация кода из YAML;
- компиляция Kotlin или Swift;
- глубокий data-flow analysis;
- автоматическое исправление найденных противоречий;
- поддержка всех существующих языков и форматов одновременно.

## 4. Приоритеты

### Обязательный минимум для AutoParts сейчас

1. YAML.
2. Markdown.
3. Универсальный текстовый fallback.

### Обязательный минимум до активной Android-разработки

4. Kotlin.
5. Gradle Kotlin DSL (`.gradle.kts`).

### Следующий приоритет

6. Swift.
7. SQL.
8. JSON.
9. XML.
10. TOML и `.properties`.
11. Shell.

## 5. Основной архитектурный принцип

`semidx` не должен определять возможность индексирования репозитория только по
наличию поддерживаемого программного языка.

Любой подходящий текстовый файл должен индексироваться на одном из трёх уровней:

| Уровень | Название | Описание |
|---|---|---|
| 1 | AST | Полноценный parser языка, символы и связи |
| 2 | Structured document | Структура документа без полного AST языка |
| 3 | Text fallback | Безопасные смысловые chunks и текстовые ссылки |

Репозиторий считается индексируемым, если найден хотя бы один файл,
поддерживаемый на любом из этих уровней.

## 6. Архитектурные границы

### 6.1 File Discovery

**Ответственность:** найти потенциально индексируемые файлы.

**Знает о:**

- путях;
- расширениях;
- ignore-правилах;
- ограничениях размера;
- binary/text detection.

**Не знает о:**

- AST;
- YAML-схемах;
- Markdown-заголовках;
- semantic references.

**Результат:**

```text
DiscoveredFile {
  path
  extension
  media_type
  size_bytes
  content_hash
}
```

### 6.2 Language and Format Detection

**Ответственность:** определить подходящий индексатор и уровень качества.

**Вход:** `DiscoveredFile`.

**Результат:**

```text
DetectedFormat {
  format_id
  indexer_id
  support_level: ast | structured | fallback
  confidence
}
```

Определение должно учитывать не только расширение, но и имя файла:

- `build.gradle.kts` → Gradle Kotlin DSL;
- `settings.gradle.kts` → Gradle Kotlin DSL;
- `*.md` → Markdown;
- `*.yaml`, `*.yml` → YAML;
- неизвестный текстовый файл → fallback.

### 6.3 Format Indexer

**Ответственность:** преобразовать один файл в нормализованные units и
references.

Минимальный контракт:

```text
FormatIndexer {
  supports(file): boolean
  index(file_content, file_metadata): IndexedDocument
}
```

Каждый индексатор должен быть независимым адаптером. Добавление нового формата
не должно требовать изменения логики существующих индексаторов.

### 6.4 Normalized Index Model

**Ответственность:** хранить единое представление кода и документов независимо
от исходного формата.

Минимальная модель:

```text
IndexedDocument {
  path
  format_id
  support_level
  units[]
  references[]
  diagnostics[]
}

IndexUnit {
  id
  path
  kind
  name
  qualified_name?
  parent_id?
  start_line
  end_line
  summary?
  attributes{}
}

Reference {
  source_unit_id
  target_name
  target_kind?
  relation_type
  line
  resolution_status: resolved | unresolved | ambiguous
}

Diagnostic {
  severity: info | warning | error
  code
  message
  line?
}
```

### 6.5 Reference Resolver

**Ответственность:** связывать references с units после индексирования файлов.

Resolver должен работать независимо от конкретного формата. Форматный индексатор
только сообщает:

```text
source workflow step references target "location_assigned"
```

Resolver определяет, соответствует ли это:

```text
OperationType.location_assigned
DomainEvent.location_assigned
другому символу
```

### 6.6 Repository Index Orchestrator

**Ответственность:** координировать discovery, detection, indexing, resolution и
сохранение snapshot.

Оркестратор не должен содержать правила YAML, Markdown, Kotlin или Swift.

### 6.7 Snapshot Cache and Incremental Indexer

**Ответственность:** повторно использовать неизменившиеся части существующего
индекса и вычислять минимальный набор необходимой работы.

Для каждого проиндексированного файла необходимо хранить:

```text
IndexedFileState {
  path
  content_hash
  size_bytes
  modified_at
  format_id
  indexer_version
  reference_policy_version
  indexed_document_id
}
```

`modified_at + size_bytes` можно использовать для быстрой предварительной
проверки. Окончательным критерием изменения содержимого должен быть
`content_hash`.

Кэш должен инвалидироваться для конкретного файла, если изменилось хотя бы одно:

- содержимое файла;
- путь файла;
- format detection result;
- версия его indexer;
- версия применяемой reference policy;
- версия нормализованной модели, несовместимая с сохранённым документом.

Полный rebuild требуется только когда:

- индекс создаётся впервые;
- пользователь явно передал `force_rebuild`;
- изменился несовместимый формат snapshot;
- повреждён сохранённый индекс;
- глобальное изменение конфигурации нельзя безопасно применить инкрементально.

Если репозиторий и конфигурация не изменились, `create_index` должен вернуть
существующие `index_id` и `snapshot_id` без повторного parsing.

### 6.8 Reverse Reference Index

**Ответственность:** определять, какие ранее проиндексированные units могут быть
затронуты изменением symbol или reference.

Минимальная структура:

```text
target_symbol_key
→ referencing_unit_ids[]
```

При изменении файла система должна:

1. переиндексировать изменённый файл;
2. удалить units и references удалённого файла;
3. определить добавленные, изменённые и удалённые symbol keys;
4. повторно разрешить references, направленные на затронутые symbol keys;
5. повторно проверить unresolved и ambiguous references, которые теперь могут
   разрешиться иначе;
6. сохранить новый snapshot.

Инкрементальная переиндексация не должна означать повторный parsing всех
неизменившихся файлов.

### 6.9 Atomic Snapshot Publication

**Ответственность:** не позволять читателям увидеть частично обновлённый или
повреждённый индекс.

Обновление должно строить новый snapshot отдельно от текущего активного
snapshot:

```text
active snapshot N
→ построить candidate snapshot N+1
→ проверить внутреннюю целостность
→ атомарно назначить N+1 активным
→ оставить N доступным для чтения до переключения
```

Если процесс завершился с ошибкой до публикации, активным остаётся предыдущий
корректный snapshot.

Одновременные вызовы для одного repository root должны:

- использовать один writer lock;
- разрешать чтение последнего опубликованного snapshot;
- не создавать два конкурирующих incremental update;
- возвращать понятный статус ожидания, reuse или конфликта.

Ключ кэша должен включать canonical repository root и существенную
конфигурацию индексирования. Индексы разных репозиториев или разных
несовместимых конфигураций не должны случайно переиспользоваться.

## 7. Поддержка YAML

### 7.1 Цель

YAML должен индексироваться как структурированный документ. Для AutoParts YAML
является исполняемым бизнес-контрактом.

### 7.2 Обязательные units

Индексатор должен создавать units для:

- YAML document;
- top-level definition;
- mapping section;
- named mapping entry;
- sequence item с устойчивым именем;
- entity;
- entity field;
- enum;
- enum value;
- workflow;
- workflow step;
- state machine;
- state;
- transition;
- fixture scenario.

### 7.3 Правила формирования имён

Примеры:

```yaml
PartStatus:
  - created
  - inventoried
```

Должны создать units:

```text
enum PartStatus
enum_value PartStatus.created
enum_value PartStatus.inventoried
```

Пример:

```yaml
steps:
  10_complete_inventory:
    action: mark part as inventoried
```

Должен создать unit:

```text
workflow_step add_new_part.10_complete_inventory
```

Пример:

```yaml
transitions:
  - from: unassigned
    to: assigned
    "on": location_assigned
```

Должен создать unit и references:

```text
transition unassigned -> assigned
reference relation_type=trigger_event target=location_assigned
reference relation_type=source_state target=unassigned
reference relation_type=target_state target=assigned
```

### 7.4 YAML references для AutoParts

На первом этапе поддержать следующие convention-based references:

| Поле | Целевой тип |
|---|---|
| `on` | `DomainEvent` |
| `log_operation` | `OperationType` |
| `log_operations` | `OperationType` |
| `rule` | путь к файлу или named rule |
| `type` в entity field | enum или primitive type |
| `condition` | `Condition` enum value |
| `part_status` | `PartStatus` enum value |
| `location_status` | `LocationStatus` enum value |
| `identification_status` | `IdentificationStatus` enum value |
| `identification_decision` | `IdentificationDecision` enum value |
| `disposition` | `Disposition` enum value |
| `acquisition_source` | `AcquisitionSource` enum value |

Эти правила должны быть реализованы как настраиваемая reference policy, а не
зашиты в общий YAML parser.

### 7.5 Обязательные YAML diagnostics

- синтаксическая ошибка;
- duplicate mapping key;
- неразрешённая ссылка;
- неоднозначная ссылка;
- неизвестное enum-значение, если reference policy определяет целевой enum;
- файл успешно индексирован только через fallback.

### 7.6 Ограничения первой версии

- YAML anchors и aliases можно сохранять как текст без полной semantic resolution.
- Произвольные пользовательские схемы не требуется угадывать.
- Достаточно convention-based recognition и настраиваемых policies.

## 8. Поддержка Markdown

### 8.1 Цель

Markdown должен индексироваться по смысловым секциям, чтобы `resolve_context`
мог вернуть конкретное архитектурное решение или часть спецификации, а не весь
документ.

### 8.2 Обязательные units

- document;
- heading section;
- subsection;
- table;
- fenced code block;
- list block;
- ADR decision section;
- link target.

### 8.3 Иерархия

Заголовки формируют дерево:

```markdown
# Architecture
## Principles
### Mobile applications are native
```

Units:

```text
document Architecture
section Architecture.Principles
section Architecture.Principles.Mobile applications are native
```

### 8.4 Markdown references

Поддержать:

- относительные ссылки на файлы;
- anchor links;
- пути внутри inline-code;
- упоминания известных symbols из индекса;
- fenced blocks с указанием языка.

Fenced block с известным языком должен передаваться соответствующему language
indexer, если это возможно.

### 8.5 Chunking

Одна секция заголовка является базовым chunk. Если секция слишком большая:

1. делить по дочерним заголовкам;
2. затем по абзацам, таблицам и code blocks;
3. сохранять parent section;
4. не разрывать таблицу или fenced code block посередине.

## 9. Универсальный текстовый fallback

### 9.1 Цель

Не исключать полезные текстовые файлы только потому, что для них нет parser.

### 9.2 Когда применять

- неизвестное расширение, но файл является текстовым;
- parser известного формата завершился контролируемой ошибкой;
- формат поддерживается частично;
- пользователь явно разрешил fallback.

### 9.3 Поведение

Fallback должен:

- определять строки и базовые блоки;
- выделять простые headings;
- выделять key-value блоки;
- выделять fenced или delimiter blocks;
- извлекать похожие на symbol токены;
- создавать diagnostic `indexed_with_text_fallback`.

Fallback не должен:

- утверждать, что понимает AST;
- создавать ложные точные связи;
- индексировать binary-файлы;
- индексировать секреты и явно исключённые файлы.

## 10. Поддержка Kotlin

### 10.1 Обязательные units

- package;
- import;
- class;
- data class;
- sealed class/interface;
- interface;
- object;
- enum и enum entry;
- function;
- property;
- constructor;
- annotation;
- Compose function;
- Room entity;
- DAO;
- migration;
- test.

### 10.2 Обязательные references

- type usage;
- function call;
- interface implementation;
- class inheritance;
- annotation usage;
- Room entity/DAO relation;
- Compose caller/callee;
- test-to-target relation;
- enum usage.

### 10.3 Gradle Kotlin DSL

`.gradle.kts` должен определяться отдельно от обычного Kotlin-кода.

Минимальные units:

- plugin declaration;
- dependency declaration;
- module include;
- build task;
- Android configuration block.

Минимальные references:

- module dependency;
- plugin id;
- library/version catalog alias;
- task dependency.

### 10.4 Рекомендуемый parser

Предпочтительно использовать стабильный Kotlin parser или tree-sitter grammar.
Parser должен быть скрыт за `FormatIndexer`; остальная система не должна
зависеть от конкретной parser-библиотеки.

## 11. Поддержка Swift

### 11.1 Обязательные units

- module;
- import;
- struct;
- class;
- enum и case;
- protocol;
- extension;
- function;
- property;
- SwiftUI View;
- persistence model;
- test.

### 11.2 Обязательные references

- protocol conformance;
- type usage;
- function call;
- extension target;
- SwiftUI composition;
- test-to-target relation;
- enum usage.

### 11.3 Рекомендуемый parser

Использовать SwiftSyntax или стабильную tree-sitter grammar за интерфейсом
`FormatIndexer`.

## 12. Дополнительные форматы

После основного этапа добавить облегчённые structured indexers:

| Формат | Минимальная структура |
|---|---|
| SQL | statement, table, column, query reference, migration |
| JSON | document, named object, schema property |
| XML | element, named resource, manifest component |
| TOML | table, key, dependency declaration |
| `.properties` | key-value entry |
| Shell | function, variable, command invocation |

Эти indexers не должны блокировать выпуск YAML, Markdown и Kotlin.

## 13. Изменения пользовательского поведения

### 13.1 `create_index`

Текущее нежелательное поведение:

```text
Нет поддерживаемого программного языка
→ ошибка
→ индекс не создаётся
```

Новое поведение:

```text
Есть хотя бы один AST, structured или fallback файл
→ существующий snapshot проверяется
→ неизменившиеся indexed documents переиспользуются
→ изменившиеся файлы переиндексируются
→ затронутые references повторно разрешаются
→ индекс создаётся или обновляется
→ результат содержит coverage summary
```

Пример результата:

```json
{
  "index_id": "...",
  "snapshot_id": "...",
  "cache": {
    "status": "incremental_update",
    "files_reused": 21,
    "files_reindexed": 3,
    "files_deleted": 0,
    "references_reresolved": 12
  },
  "coverage": {
    "ast_files": 0,
    "structured_files": 24,
    "fallback_files": 3,
    "ignored_files": 5,
    "failed_files": 0
  },
  "formats": {
    "yaml": 18,
    "markdown": 6,
    "text_fallback": 3
  },
  "warnings": [
    "No AST-supported programming languages detected; structured document index created."
  ]
}
```

Допустимые значения `cache.status`:

- `new_index`;
- `cache_hit`;
- `incremental_update`;
- `full_rebuild`;
- `cache_recovered_after_corruption`.

Если файловые данные, конфигурация и версии индексаторов не изменились:

```text
create_index(root)
→ cache.status = cache_hit
→ files_reindexed = 0
→ вернуть существующий snapshot_id
```

`force_rebuild = true` должен оставаться явным способом полностью перестроить
индекс.

### 13.2 `repo_map`

Должен показывать не только модули исходного кода, но и документные области:

```text
contract/
  schemas/
  state-machines/
  workflows/
  test-fixtures/
Doc/
  adr/
  specs/
```

### 13.3 `resolve_context`

Должен уметь находить:

- определение enum;
- workflow step;
- state transition;
- fixture scenario;
- архитектурную секцию Markdown;
- связанные references.

### 13.4 `impact_analysis`

Для YAML-контракта должен показывать минимум:

```text
Изменение OperationType.location_assigned
→ используется в location state machine
→ используется в putaway workflow
→ проверяется putaway fixture
```

## 14. Конфигурация проекта

Добавить необязательный конфигурационный файл, например:

```text
.semidx.yaml
```

Пример:

```yaml
formats:
  yaml:
    enabled: true
    reference_policies:
      - auto-parts-contract
  markdown:
    enabled: true
  fallback:
    enabled: true
    max_file_size_kb: 512

paths:
  include:
    - contract/**
    - Doc/specs/**
    - Doc/adr/**
    - mobile/**
  exclude:
    - Doc/sessions/**
    - build/**
    - .gradle/**

cache:
  enabled: true
  verify_content_hash: true
  retain_snapshots: 2
```

Конфигурация не должна быть обязательной. Без неё используются безопасные
defaults.

## 15. Реализационная последовательность

### Этап 0. Зафиксировать нормализованный контракт

**Цель:** подготовить расширяемую основу.

Задачи:

- определить `IndexedDocument`, `IndexUnit`, `Reference`, `Diagnostic`;
- определить `FormatIndexer`;
- отделить detection от indexing;
- добавить `support_level`;
- добавить coverage summary.

Критерий приёмки:

- существующие языковые indexers продолжают работать;
- новый mock structured indexer подключается без изменения orchestrator.

### Этап 1. Snapshot reuse и инкрементальный foundation

**Цель:** прекратить полную переиндексацию при каждом вызове `create_index`.

Задачи:

- сохранить `IndexedFileState`;
- добавить cache hit для полностью неизменившегося репозитория;
- сравнивать файлы по metadata и content hash;
- переиндексировать только изменённые файлы;
- удалять units удалённых файлов;
- добавить `indexer_version` и `reference_policy_version`;
- возвращать cache statistics;
- сохранить `force_rebuild`.
- публиковать новый snapshot атомарно;
- добавить один writer lock на repository root.

Критерий приёмки:

- повторный `create_index` без изменений не запускает parser;
- изменение одного файла переиндексирует только этот файл;
- удаление файла удаляет только его units и references;
- `force_rebuild` перестраивает весь индекс.
- ошибка во время update оставляет предыдущий snapshot активным;
- два одновременных вызова не повреждают индекс.

### Этап 2. Markdown vertical slice

**Цель:** доказать structured-document indexing на простом формате.

Задачи:

- определить Markdown files;
- создать units по headings;
- сохранить иерархию секций;
- индексировать links и fenced blocks;
- показать секции в `repo_map` и `resolve_context`.

Критерий приёмки:

- запрос о native mobile decision возвращает соответствующую секцию ADR или
  architecture document, а не весь файл.

### Этап 3. YAML vertical slice

**Цель:** индексировать AutoParts contract.

Задачи:

- parser YAML с duplicate-key detection;
- units для top-level definitions, fields, steps, states и transitions;
- references для `on`, `log_operation`, `rule`;
- diagnostics для unresolved references;
- AutoParts reference policy.

Критерий приёмки:

- `create_index` успешно индексирует AutoParts без исходного кода;
- запрос `location_assigned` возвращает enum operation, state transition,
  putaway workflow и fixture.

### Этап 4. Инкрементальный reference resolution

**Цель:** повторно разрешать только связи, затронутые изменениями symbols.

Задачи:

- добавить reverse-reference index;
- вычислять добавленные, изменённые и удалённые symbol keys;
- повторно разрешать references на затронутые symbols;
- повторно проверять потенциально затронутые unresolved и ambiguous references;
- показывать `references_reresolved` в статистике.

Критерий приёмки:

- изменение `OperationType.location_assigned` не вызывает parsing остальных
  YAML-файлов, но повторно проверяет связанные workflow, transition и fixture;
- добавление определения разрешает ранее unresolved reference;
- удаление определения переводит связанные references в unresolved.

### Этап 5. Универсальный fallback

**Цель:** не терять остальные полезные текстовые файлы.

Задачи:

- text/binary detection;
- безопасный chunking;
- fallback diagnostics;
- coverage reporting.

Критерий приёмки:

- репозиторий с неизвестными текстовыми форматами индексируется с честным
  указанием уровня качества.

### Этап 6. Kotlin и Gradle Kotlin DSL

**Цель:** поддержать Android-разработку.

Задачи:

- Kotlin parser adapter;
- Kotlin units и references;
- отдельный detector для `.gradle.kts`;
- module dependency references;
- Kotlin fixture repository.

Критерий приёмки:

- `resolve_context` находит Room entity, DAO, repository и связанные tests;
- `impact_analysis` показывает использования изменённого enum или interface.

### Этап 7. Swift

**Цель:** поддержать будущую iOS-разработку.

Задачи:

- Swift parser adapter;
- Swift units и references;
- SwiftUI и protocol conformance;
- Swift fixture repository.

### Этап 8. Дополнительные форматы

Добавлять SQL, JSON, XML, TOML, properties и shell независимо, по одному
индексатору за изменение.

## 16. Разбиение задач для разработчиков

Каждая задача должна быть достаточно маленькой для отдельного pull request.

### Foundation

- [ ] Ввести `support_level`.
- [ ] Ввести `FormatIndexer`.
- [ ] Отделить format detection от parser selection.
- [ ] Добавить `IndexedDocument`.
- [ ] Добавить coverage summary.
- [ ] Разрешить создание индекса без AST-языков.

### Incremental indexing

- [ ] Сохранить `IndexedFileState`.
- [ ] Добавить быстрый metadata check и подтверждение через content hash.
- [ ] Добавить cache hit без запуска parser.
- [ ] Переиндексировать только изменённые файлы.
- [ ] Удалять units и references удалённых файлов.
- [ ] Инвалидировать файл при изменении версии indexer или policy.
- [ ] Добавить reverse-reference index.
- [ ] Добавить инкрементальный reference resolution.
- [ ] Добавить cache statistics в `create_index`.
- [ ] Сохранить явный `force_rebuild`.
- [ ] Добавить atomic snapshot publication.
- [ ] Добавить writer lock на repository root.
- [ ] Добавить восстановление после незавершённого update.

### Markdown

- [ ] Создать Markdown detector.
- [ ] Создать heading units.
- [ ] Добавить parent-child hierarchy.
- [ ] Добавить link references.
- [ ] Добавить fenced block units.
- [ ] Добавить Markdown tests.

### YAML

- [ ] Создать YAML detector.
- [ ] Подключить parser с duplicate-key detection.
- [ ] Создать generic mapping и sequence units.
- [ ] Добавить named top-level units.
- [ ] Добавить workflow step recognition.
- [ ] Добавить state/transition recognition.
- [ ] Добавить configurable reference policy.
- [ ] Добавить unresolved-reference diagnostics.
- [ ] Добавить AutoParts contract tests.

### Fallback

- [ ] Реализовать binary/text detection.
- [ ] Реализовать безопасный generic chunking.
- [ ] Добавить fallback diagnostic.
- [ ] Добавить ограничения размера.

### Kotlin

- [ ] Выбрать parser.
- [ ] Реализовать Kotlin adapter.
- [ ] Добавить основные declarations.
- [ ] Добавить references.
- [ ] Добавить Compose-specific classification.
- [ ] Добавить Room-specific classification.
- [ ] Добавить Gradle Kotlin DSL detector и indexer.

### Swift

- [ ] Выбрать parser.
- [ ] Реализовать Swift adapter.
- [ ] Добавить declarations и references.
- [ ] Добавить SwiftUI-specific classification.

## 17. Стратегия тестирования

### 17.1 Unit tests

Для каждого indexer:

- входной файл;
- ожидаемые units;
- ожидаемые references;
- ожидаемые diagnostics;
- корректные line ranges;
- устойчивые unit IDs.

### 17.2 Golden repository tests

Создать небольшие fixture repositories:

```text
fixtures/
  markdown-only/
  yaml-contract/
  kotlin-android/
  swift-ios/
  mixed-repository/
  unknown-text-only/
```

### 17.3 Обязательные AutoParts acceptance tests

1. `create_index` успешно работает на AutoParts.
2. `repo_map` показывает `contract/schemas`, `state-machines`, `workflows`,
   `test-fixtures`, `Doc/specs` и `Doc/adr`.
3. Поиск `location_assigned` возвращает:
   - `OperationType.location_assigned`;
   - location state transition;
   - putaway workflow;
   - putaway fixture.
4. Поиск `source_donor_vehicle_id` возвращает schema field, workflow corrections
   и связанные fixtures.
5. Изменение enum value отражается в `impact_analysis`.
6. Duplicate YAML key создаёт error diagnostic.
7. Неразрешённый `log_operation` создаёт warning или error diagnostic.
8. Markdown-запрос о native architecture возвращает конкретную секцию.
9. Повторный `create_index` без изменений возвращает cache hit и не запускает
   parser.
10. Изменение одного YAML workflow переиндексирует только этот файл и повторно
    разрешает только затронутые references.
11. Удаление enum value не требует parsing неизменившихся файлов, но переводит
    связанные references в unresolved.
12. `force_rebuild` полностью перестраивает индекс и даёт тот же semantic
    результат, что инкрементально обновлённый индекс.
13. Искусственное падение во время update оставляет предыдущий snapshot
    доступным и корректным.
14. Два одновременных `create_index` для одного root не создают повреждённый или
    частично опубликованный snapshot.

### 17.4 Regression tests

Новые document indexers не должны менять результаты существующих AST-indexers,
если соответствующие файлы не изменились.

Инкрементально обновлённый индекс должен быть семантически эквивалентен индексу,
полученному полным rebuild на том же состоянии репозитория.

## 18. Definition of Done

Функция считается завершённой, если:

- реализована через отдельный `FormatIndexer` или отдельную policy;
- имеет unit tests;
- имеет минимум один golden fixture;
- возвращает корректные line ranges;
- не создаёт ложное впечатление AST-поддержки при fallback;
- отображается в coverage summary;
- корректно инвалидирует только затронутые cached documents;
- даёт тот же semantic result при incremental update и full rebuild;
- документирована;
- не ломает существующие языковые indexers;
- проходит AutoParts acceptance scenario, если относится к YAML, Markdown,
  fallback или Kotlin.

## 19. Основные риски

### Высокий: общий индексатор превращается в набор специальных правил

**Риск:** AutoParts-specific conventions попадут в YAML parser.

**Митигация:** YAML parser создаёт общую структуру; AutoParts-ссылки реализуются
отдельной configurable reference policy.

### Высокий: fallback создаёт ложные semantic relationships

**Риск:** пользователь принимает приблизительный текстовый результат за точную
связь.

**Митигация:** fallback создаёт только unresolved textual references и всегда
указывает `support_level = fallback`.

### Высокий: устаревший кэш возвращает неверный semantic result

**Риск:** изменился parser, policy или symbol, но зависимые части индекса не
были инвалидированы.

**Митигация:** хранить версии indexer и policy, использовать reverse-reference
index и постоянно проверять эквивалентность incremental update полному rebuild.

### Средний: слишком ранняя универсализация

**Риск:** команда строит сложную plugin framework до первого работающего slice.

**Митигация:** сначала один узкий `FormatIndexer` contract и Markdown vertical
slice, затем YAML.

### Средний: разные YAML parser трактуют ключи по-разному

**Риск:** YAML 1.1 может трактовать `on`, `yes`, `no` как boolean.

**Митигация:** зафиксировать версию/поведение parser, сохранять исходный текст
ключей и обязательно проверять duplicate keys.

### Средний: нестабильные unit IDs

**Риск:** небольшое изменение файла полностью перестраивает связи и snapshot
diff.

**Митигация:** unit ID строится из пути, kind, qualified name и устойчивого
локального discriminator, а не только из номера строки.

### Средний: content hashing делает каждый запуск дорогим

**Риск:** вычисление hash всех больших файлов нивелирует выигрыш кэша.

**Митигация:** сначала сравнивать `modified_at + size_bytes`, вычислять hash
только для потенциально изменившихся файлов и всегда исключать generated,
binary и oversized files по настройкам.

## 20. Зависимости и направление связей

Правильное направление:

```text
Repository Orchestrator
  → FormatIndexer contract
      ← Markdown adapter
      ← YAML adapter
      ← Kotlin adapter
      ← Swift adapter
      ← Text fallback adapter

Reference Resolver
  → Normalized Index Model

Snapshot Cache / Incremental Indexer
  → Normalized Index Model
  → FormatIndexer contract

repo_map / resolve_context / impact_analysis
  → Normalized Index Model
```

Неправильное направление:

```text
Repository Orchestrator
  → знает YAML steps, Markdown headings и Kotlin classes напрямую
```

## 21. Рекомендуемый первый pull request

Первый PR не должен пытаться добавить все форматы.

Состав первого PR:

1. Ввести `support_level`.
2. Ввести минимальный `FormatIndexer`.
3. Ввести `IndexedFileState`.
4. Добавить cache hit для неизменившегося репозитория.
5. Добавить переиндексацию только изменённых файлов.
6. Добавить cache statistics и сохранить `force_rebuild`.
7. Добавить atomic snapshot publication и writer lock.
8. Добавить regression test: incremental result равен full rebuild result.

После принятия этого PR второй PR добавляет Markdown structured indexer и
разрешает structured-only индекс. Третий PR добавляет YAML и AutoParts
acceptance tests.

Такой порядок сначала делает повторные вызовы `create_index` дешёвыми и
предсказуемыми, затем доказывает новую архитектурную границу на простом формате
и только после этого применяет её к более сложному YAML-контракту.
