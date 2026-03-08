# ADR-011: Emit Autonomy Guardrails for AI Consumers, with Host Retaining Final Control

**Status**: Accepted  
**Date**: 2026-03-08  
**Deciders**: project owner

---

## Context and Problem Statement

`ADR-002` зафиксировал `context packet` как основной retrieval output.  
`ADR-006` зафиксировал late raw-code escalation.  
`ADR-008` зафиксировал evidence-aware confidence model.  
`ADR-009` зафиксировал structured host query contract.  
`ADR-010` зафиксировал structured diagnostics and observability.

После этого нужен ответ на следующий вопрос: как retrieval library должна взаимодействовать с автономными AI consumers.

Проблема в том, что AI consumer может использовать retrieval result для разных уровней действия:

- просто читать и рассуждать;
- готовить план изменений;
- писать черновой патч;
- предлагать уверенное изменение;
- в некоторых системах даже автоматически применять изменение.

Если библиотека не задаст guardrail model, появятся системные риски:

- low-confidence retrieval будет использоваться как будто он пригоден для patching;
- partial/fallback/stale results будут приводить к слишком смелым агентным действиям;
- host systems начнут изобретать несовместимые safety policies;
- библиотека станет полезной для чтения, но опасной как компонент autonomous coding loop.

Нужно принять решение:

- должна ли библиотека возвращать автономные guardrail signals;
- что они должны означать;
- где заканчивается ответственность библиотеки и начинается ответственность host/orchestrator.

---

## Decision Drivers

- Безопасность autonomous and semi-autonomous AI workflows
- Совместимость с `confidence` и diagnostics model
- Сохранение host control over actual execution
- Возможность предотвратить overconfident patch generation
- Единые semantics для разных host systems
- Explainability of why action is allowed, limited or blocked

---

## Considered Options

### Option 1. No autonomy guardrails in the library

Библиотека только возвращает retrieval results, а все решения о допустимых действиях принимает host from scratch.

### Option 2. Emit structured guardrail assessment, but keep final action control in the host

Библиотека возвращает structured autonomy posture and blocking reasons, а host/orchestrator принимает окончательное решение о действии.

### Option 3. Library directly decides allowed/forbidden actions

Библиотека сама определяет и навязывает, может ли AI consumer редактировать, применять патч или действовать автономно.

---

## Decision

Мы принимаем **Option 2: Emit structured guardrail assessment, but keep final action control in the host**.

Библиотека должна возвращать **structured autonomy guardrail assessment** для retrieval result.

При этом:

- библиотека оценивает retrieval readiness and risk posture;
- host/orchestrator принимает окончательное решение о действии;
- библиотека не становится policy engine for full agent orchestration.

---

## Core Rule

Retrieval library не должна отвечать на вопрос “что агент будет делать дальше” во всей полноте.  
Она должна отвечать на более узкий вопрос:

> насколько retrieval result пригоден для следующего класса действий

То есть библиотека оценивает **retrieval suitability for action**, а не полную business/workflow policy.

---

## Required Guardrail Output

Каждый retrieval result должен иметь companion `guardrail_assessment`.

Этот assessment может возвращаться:

- в diagnostics surface;
- как companion metadata рядом с `context packet`;
- в telemetry/diagnostics traces;

но не должен теряться.

### Required fields

Минимально `guardrail_assessment` должен содержать:

- `autonomy_posture`
- `blocking_reasons`
- `required_next_steps`
- `allowed_action_scope`
- `risk_flags`

---

## `autonomy_posture`

Минимальная каноническая шкала должна быть такой:

- `read_safe`
- `plan_safe`
- `draft_patch_safe`
- `autonomy_blocked`

### `read_safe`

Результат пригоден для:

- чтения;
- объяснения;
- initial reasoning;
- broad analysis.

Но не обязательно пригоден для patch drafting.

### `plan_safe`

Результат пригоден для:

- построения change plan;
- outlining impact;
- selecting additional fetches or tests;
- proposing candidate edit locations.

Но patch drafting может быть преждевременным.

### `draft_patch_safe`

Результат достаточно хорош для:

- подготовки чернового патча;
- локального edit reasoning;
- generation of candidate change set;

при условии, что host policy допускает это.

### `autonomy_blocked`

Результат не должен использоваться для автономного продвижения без дополнительного retrieval, clarification или human review.

---

## `blocking_reasons`

Если posture ограничен или заблокирован, система должна уметь перечислить причины.

Примеры:

- `target not localized`
- `symbol resolution partial`
- `fallback parser only`
- `retrieval relies on stale-sensitive artifacts`
- `impact surface too broad`
- `raw code still missing for edit target`
- `multiple plausible edit locations remain`

Эти причины должны быть machine-readable enough and human-readable enough.

---

## `required_next_steps`

Guardrail assessment должен не только блокировать, но и подсказывать безопасное продолжение.

Примеры:

- `fetch enclosing unit body`
- `fetch nearest tests`
- `narrow to explicit target symbol`
- `refresh stale snapshot`
- `run higher-quality parser adapter`
- `request human confirmation`

Это не orchestration plan в полном смысле, а bounded safe-next-step guidance.

---

## `allowed_action_scope`

Если posture не blocked, библиотека должна уметь ограничить допустимый scope действия.

Примеры:

- `analysis_only`
- `plan_only`
- `draft_patch_on_selected_unit_only`
- `no_multi_file_edit`
- `no_apply_without_human_review`

Это позволяет host systems не трактовать `draft_patch_safe` как license for unrestricted autonomy.

---

## `risk_flags`

Дополнительные bounded risk signals:

- `broad_impact_surface`
- `test_coverage_unclear`
- `cross_file_change_likely`
- `behavior_hidden_in_runtime_logic`
- `stale_or_partial_evidence`
- `raw_fetch_budget_insufficient`

Flags не обязаны блокировать действие сами по себе, но должны понижать допустимую автономность or trigger host caution.

---

## Posture Derivation Rule

`autonomy_posture` должен выводиться из already accepted retrieval signals, а не из отдельной магии.

Главные inputs:

- confidence level and reasons
- target localization quality
- parser/extraction quality
- raw-code availability for target
- impact breadth
- stale/degraded conditions
- explicit host constraints

### Required rule

Высокая autonomy posture невозможна, если:

- confidence low;
- target not localized;
- evidence mostly soft;
- stale-sensitive artifacts unresolved;
- retrieval scope broad and ambiguous.

---

## Non-Escalation Rule

Guardrails не должны автоматически становиться более permissive только из-за:

- большого объема retrieved text;
- наличия vector similarity;
- большого числа related units;
- aggressive host hints.

То есть autonomy posture, как и confidence, должна быть non-compensating with respect to weak evidence.

---

## Raw-Code Interaction Rule

Late raw-code fetch может изменить guardrail posture, но только при реальном снятии неопределенности.

### Allowed upgrade examples

- `plan_safe -> draft_patch_safe`, если target body fetched and ambiguity removed
- `autonomy_blocked -> plan_safe`, если stale snapshot refreshed and target localized

### Disallowed upgrade examples

- `read_safe -> draft_patch_safe`, только потому что fetched whole file
- `autonomy_blocked -> draft_patch_safe`, если multiple edit locations still remain

---

## Host Control Rule

Host retains final control.

### Meaning

Библиотека не должна:

- применять патчи;
- запускать workflow gates;
- принимать окончательное решение о merge/apply;
- определять business-critical approval policy.

Это остаётся задачей host/orchestrator.

### Required host integration expectation

Host должен использовать `guardrail_assessment` как:

- safety signal;
- default posture recommendation;
- reason trace for action gating.

Но host может применять более строгую policy.

Host не должен silently делать policy более permissive, игнорируя blocking reasons, без явного override path.

---

## Override Rule

Если host всё-таки хочет действовать вопреки guardrail recommendation, это должно быть явным.

### Required behavior

Override должен:

- быть явно отражён в host side;
- фиксироваться в diagnostics/telemetry if integrated;
- не скрывать original library posture;
- считаться exceptional path.

Библиотека не блокирует override физически, но обязана clearly state recommended posture and risks.

---

## Explainability Rule

Guardrail assessment должен быть explainable через retrieval evidence.

На вопрос “почему patch drafting не разрешен” система должна уметь ответить, например:

- target not localized to one unit;
- confidence only medium because parser fallback used;
- no body-level fetch for selected unit;
- impact likely crosses file boundary;
- stale cache warning unresolved.

Если guardrail output нельзя объяснить из diagnostics/evidence, он не годится.

---

## Why This Shape

Такой подход нужен, чтобы:

- сделать retrieval library безопасным компонентом autonomous tooling;
- не превращать библиотеку в full orchestrator;
- дать host systems единый safety-oriented contract;
- удержать связь между confidence, diagnostics и allowed actions;
- предотвратить overconfident downstream behavior.

---

## Prohibitions

- Библиотека **MUST NOT** silently imply that any successful retrieval is patch-safe.
- `draft_patch_safe` **MUST NOT** выдаваться при unresolved target ambiguity.
- Guardrail assessment **MUST NOT** заменять host approval policy.
- Host hints **MUST NOT** автоматически повышать autonomy posture.
- Overrides **MUST NOT** стирать original blocking reasons from diagnostics.

---

## Consequences

### Positive

- Retrieval становится гораздо пригоднее для semi-auto and full-auto systems.
- Host systems получают единый safety contract.
- Confidence and diagnostics начинают напрямую поддерживать action gating.
- Снижается риск слишком смелых действий на partial evidence.

### Negative

- Появляется еще один companion contract besides `context packet` and diagnostics.
- Нужно будет отдельно калибровать posture derivation rules.
- Некоторые hosts предпочтут полностью свою safety policy и будут воспринимать это как дополнительную сложность.

### Tradeoff accepted

Мы сознательно выбираем **retrieval-scoped autonomy guardrails with host-retained final control** вместо либо полной анархии, либо чрезмерно умной библиотеки, которая пытается оркестрировать весь workflow.

---

## Definition of Done

Решение считается реализованным корректно, когда одновременно выполнены все условия:

1. Каждый retrieval result имеет `guardrail_assessment`.
2. `autonomy_posture` выводится из evidence/confidence/retrieval state, а не из host wishful thinking.
3. `autonomy_blocked` и ограниченные posture states сопровождаются `blocking_reasons` и `required_next_steps`.
4. Host retains final control but cannot lose visibility into original library recommendation.
5. Raw-code escalation может улучшить posture только при реальном снятии ambiguity.

---

## Consequences for Next ADRs

Следующие решения должны опираться на это ADR:

- concrete diagnostics/event schemas for guardrail outputs;
- score calibration and threshold policy;
- examples for host integration patterns;
- human-review and override policy in orchestrators.
