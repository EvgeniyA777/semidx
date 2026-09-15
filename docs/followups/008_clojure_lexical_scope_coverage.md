---
title: "Clojure lexical scope coverage"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-14"
---

# Clojure Lexical Scope Coverage

## Classification

`coverage_gap`

## Source

Found while preparing the Plan 005 capability matrix. A probe showed the Clojure
frontend recording `(helper)` inside `(let [helper (fn [] 2)] ...)` as a `CALLS`
fact about the unit's top-level `defn helper`. Plan 005 Stage 2.5 removed that
false fact by suppression; this entry keeps the lost coverage visible.

See
[Plan 005 progress, Stage 2.5](../reports/005_mcp_preview_release_readiness_progress.md#stage-25-same-unit-name-resolution-facts-java-and-clojure).

## Current Behavior

A Clojure symbol is a fact only when it names the unit's one top-level
`def`-like declaration, is not a parameter of the enclosing definition, sits in
a definition with a single parameter vector, and every form enclosing it in the
body is known to bind nothing: the body itself, `do`, `if`, collection literals,
calls of the unit's own definitions, and applications whose head is not a
symbol.

Everything under any other form — `let`, `fn`, `loop`, `for`, threading macros,
`clojure.core` functions such as `str`, and macros from other namespaces — stays
unresolved with the explanation that the form may be a macro binding the name.
Multi-arity definitions and duplicate declarations stay unresolved too. No
false fact is produced, but most real Clojure references are unresolved.

## Why Deferred

Macros may bind names with any syntax, so precise scope needs knowledge of the
forms in play: `clojure.core` binding forms and whether a namespace excludes or
replaces them. That is language coverage work, which Plan 005 excludes. The
suppression rule is exact for the preview's promise: incompleteness is
acceptable, false precision is not.

## Acceptance Direction

- Model `clojure.core` special forms and binding macros (`let`, `letfn`, `loop`,
  `fn`, `for`, `doseq`, `dotimes`, `if-let`, `when-let`, `if-some`,
  `when-some`, `with-open`, `binding`, `catch`, named `fn`, destructuring) with
  their exact scope, and trust `clojure.core` functions only when the `ns` form
  neither excludes nor replaces them.
- Read per-arity parameter vectors of multi-arity definitions.
- Keep unknown macros conservative: a form whose head does not resolve to a
  known non-binding function or special form still leaves its contents
  unresolved.

## Required Tests

- A `let`, `loop`, `fn`, and destructuring binding shadows a same-unit name only
  inside its scope, and the name resolves again after it.
- `(:refer-clojure :exclude [let])` with a same-unit or referred `let` makes
  forms under it unresolved.
- A multi-arity parameter shadows only within its arity.
- An unknown macro still leaves its contents unresolved.
- The Plan 005 Stage 2.5 scope test keeps passing for cases the model does not
  cover.
