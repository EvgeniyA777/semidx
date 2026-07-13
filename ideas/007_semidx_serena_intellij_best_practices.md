---
title: "semidx Serena and IntelliJ Best Practices"
doc_type: "idea"
lifecycle: "archived"
status: "historical"
agent_action: "historical_reference_only"
updated: "2026-07-13"
---

# semidx: лучшие практики Serena и IntelliJ

**Date:** 2026-06-09
**Status:** Archived
**Purpose:** размышления для последующего переноса в репозиторий `semidx`.

> Архивный документ. Идеи проверены относительно текущей реализации и включены
> в актуальную концептуальную точку опоры:
> [План работ: расширение `semidx`](../notes/2026-06-09-1015-95e50b0e-5dfa-4033-bc2b-db6db47ffda4.md).

## Главный вывод

`semidx` не следует развивать как ещё одну собственную IDE или пытаться
самостоятельно реализовать полноценный semantic analyzer для каждого языка.

Его сильная позиция:

> Единый semantic-слой над несколькими источниками понимания проекта, который
> объединяет исходный код, бизнес-контракты, документацию, тесты и зависимости.

Serena показывает полезную модель подключаемых semantic-backend и
agent-oriented инструментов. IntelliJ/Junie показывает сильную модель проекта,
точный индекс и управление жизненным циклом анализа.

`semidx` может объединить эти подходы и добавить уникальную возможность:
строить единый граф связей между кодом и другими артефактами продукта.

## Что взять из Serena

### Подключаемые semantic-backend

Serena может использовать language servers либо JetBrains IDE. Аналогичную
границу стоит ввести в `semidx`:

```text
SemanticProvider
├── NativeParserProvider
├── LspProvider
├── JetBrainsProvider
├── StructuredDocumentProvider
└── TextFallbackProvider
```

Для каждого языка или формата выбирается лучший доступный источник:

```text
Java/Kotlin → JetBrains или LSP
Swift       → SourceKit-LSP
Clojure     → clojure-lsp или существующий parser
YAML/MD     → собственный structured indexer
unknown     → text fallback
```

Это позволит быстро расширять языковую поддержку без написания собственных
компиляторов и глубоких semantic analyzers.

### Capability negotiation

Нельзя считать, что каждый backend предоставляет одинаковые возможности.
Language server одного языка может корректно находить definitions, но неполно
находить cross-file references или не поддерживать call hierarchy.

Каждый provider должен явно сообщать capabilities:

```text
ProviderCapabilities {
  document_symbols
  definitions
  references
  implementations
  call_hierarchy
  rename
  diagnostics
  dependency_graph
}
```

Пользователь и агент должны видеть качество доступного анализа:

```text
Kotlin:
  symbols: exact
  references: exact
  call_hierarchy: exact

YAML:
  symbols: structural
  references: convention-based

Markdown:
  symbols: sections
  references: links only
```

### Agent-oriented semantic tools

Serena предоставляет высокоуровневые операции над символами вместо работы
только с файлами, строками и grep.

Для `semidx` полезны инструменты:

```text
find_symbol
find_definitions
find_references
find_implementations
find_callers
find_callees
find_related_tests
explain_symbol
```

Semantic editing, rename и refactoring лучше сначала делегировать IDE/LSP.
Первым приоритетом `semidx` должен быть надёжный retrieval и impact analysis.

## Что взять из IntelliJ и Junie

### Полноценная модель проекта

IntelliJ анализирует не просто набор файлов. Он понимает проекты, модули,
source roots, test roots, generated code, SDK и внешние зависимости.

`semidx` следует добавить нормализованную project model:

```text
Project
├── Module
├── SourceRoot
├── TestRoot
├── GeneratedRoot
├── Dependency
└── ExternalLibrary
```

Это позволит:

- отделять production-код от тестов;
- исключать generated-файлы;
- понимать межмодульные зависимости;
- находить реализации из внешних библиотек;
- корректно определять blast radius.

### Scopes

Каждый semantic-запрос должен принимать область поиска:

```text
current_file
module
project_sources
tests
dependencies
contract
documentation
all
```

Scopes уменьшают шум и позволяют агенту явно выбирать нужную область.

### Состояние готовности индекса

IntelliJ различает период анализа и готовый smart mode. `semidx` тоже должен
показывать состояние:

```text
index_status:
  discovering
  indexing
  resolving_references
  ready
  degraded
  failed
```

Если индекс готов частично, запрос может выполняться, но результат должен явно
сообщать о неполноте и недоступных capabilities.

### Persistent, incremental и shared indexes

Локальный индекс должен сохраняться и обновляться инкрементально:

```text
create_index(root)
→ переиспользовать неизменившиеся indexed documents
→ переиндексировать только изменённые файлы
→ повторно разрешить только затронутые references
→ атомарно опубликовать новый snapshot
```

После появления надёжного локального incremental indexing можно добавить shared
indexes:

```text
repository_commit
+ semidx_version
+ provider_versions
+ configuration_hash
→ reusable index artifact
```

Shared indexes полезны для больших проектов и нескольких агентов, но не должны
реализовываться раньше корректного локального кэша и инвалидации.

## Что должно остаться уникальным преимуществом semidx

### Единый нормализованный semantic graph

Разные providers должны отдавать данные в одну модель:

```text
LSP / JetBrains / parsers / YAML policies / Markdown
                    ↓
          Normalized Semantic Graph
                    ↓
 repo_map / resolve_context / impact_analysis / snapshot_diff
```

Каждый semantic-факт должен хранить происхождение и качество:

```text
SemanticFact {
  source_provider
  confidence
  support_level
  snapshot_id
  evidence_location
}
```

Это позволяет отличать:

- точную ссылку, подтверждённую IDE или LSP;
- структурную связь из YAML;
- convention-based связь;
- текстовую или embedding-гипотезу.

### Бизнес-связи поверх исходного кода

Обычные IDE и LSP хорошо понимают код, но обычно не понимают предметные связи
между кодом, контрактом и документацией.

Пример полезного графа AutoParts:

```text
OperationType.location_assigned
→ state-machine transition
→ putaway workflow
→ contract fixture
→ Kotlin implementation
→ Android test
```

Это делает `impact_analysis` полезным для всего продукта, а не только для одного
языка программирования.

### Гибридный retrieval

Следует комбинировать несколько механизмов:

1. точные symbols и references;
2. обход semantic graph;
3. BM25 или другой lexical search;
4. embeddings как дополнительное ранжирование.

Embeddings не являются доказательством связи. Они должны только помогать
находить кандидатов и улучшать ranking.

## Предлагаемая архитектура

```text
Repository Discovery
        ↓
Project Model Builder
        ↓
Provider Selection / Capability Negotiation
        ↓
┌──────────────────────────────────────────────┐
│ Native Parser │ LSP │ JetBrains │ Documents │
└──────────────────────────────────────────────┘
        ↓
Normalized Semantic Graph
        ↓
Reference Resolver + Provenance + Confidence
        ↓
Persistent Incremental Snapshots
        ↓
Agent-oriented MCP tools
```

## Рекомендуемый порядок реализации

1. Persistent incremental index и atomic snapshots.
2. `SemanticProvider` contract и capability negotiation.
3. Project model, modules, source roots и scopes.
4. LSP provider для первого языка, вероятно Kotlin.
5. Structured YAML и Markdown providers.
6. Нормализованный semantic graph с provenance и confidence.
7. Agent-oriented symbol tools.
8. JetBrains provider.
9. Shared indexes.
10. Hybrid retrieval и embedding reranking.

## Что не следует делать

- Не писать собственный Kotlin или Swift semantic analyzer без веской причины.
- Не делать LSP единственным источником истины.
- Не скрывать неполные или degraded результаты.
- Не смешивать точные и эвристические связи без provenance и confidence.
- Не строить shared indexes до корректного incremental indexing.
- Не превращать `semidx` в редактор или полноценную IDE.
- Не использовать embeddings как замену точным symbol relationships.
- Не заставлять orchestrator знать детали каждого языка и формата.

## Обоснованная позиция semidx

Serena уже хорошо решает задачу предоставления IDE-подобных symbol tools через
LSP и JetBrains backend. IntelliJ уже хорошо решает глубокий semantic analysis
поддерживаемых языков и проектов.

Поэтому `semidx` должен использовать эти возможности как providers там, где они
доступны, а собственные усилия направлять на то, что они обычно не покрывают:

- объединение разных semantic-источников;
- единый межъязыковой граф;
- документы и бизнес-контракты;
- provenance и confidence;
- компактный agent-oriented context;
- impact analysis и snapshot diff на уровне всего продукта.
