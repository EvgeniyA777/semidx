# Post-Roadmap Semantic Deepening Plan

Execution plan for the next semantic tranche after the main roadmap phases (`Phase 3` through `Phase 5`) were closed.

## Goal

Push the language adapters beyond the delivered roadmap scope toward more compiler-grade ownership, dispatch, inheritance, decorator, and parser-strength behavior, while keeping every slice independently shippable.

## Stage Checklist

- `[x]` Stage 1 Clojure lexical + destructuring deepening
- `[ ]` Stage 2 Clojure multimethod / protocol / dispatch deepening
- `[ ]` Stage 3 Java inheritance / lambda / method-reference deepening
- `[ ]` Stage 4 Python decorator / class-scope deepening
- `[ ]` Stage 5 Elixir pipelines / `with` / nested-module deepening
- `[ ]` Stage 6 TypeScript parser-strengthening tranche
- `[ ]` Stage 7 Cross-language confidence recalibration
- `[ ]` Stage 8 Post-roadmap closure

## Delivery Rule

Every stage ends with:

1. code + tests
2. docs/status update
3. full `clojure -M:test`
4. one `git commit`
5. one `git push`

No batching of multiple stages into one commit.

## Current Active Stage

`Stage 2` is now the active slice.

## Stage Notes

### Stage 1

Delivered scope:

- Clojure fallback/tree-sitter call extraction now respects lexical local bindings more accurately.
- Local params, `let` bindings, destructured locals, `when-let` locals, comprehension bindings, `as->` bindings, and `letfn` helper names now suppress false global caller edges.
- Regression coverage now proves local lexical ownership beats same-name namespace vars in the regex fallback lane.

### Stage 2

Planned scope:

- stronger `defmulti` / `defmethod` targeting
- protocol / `extend-type` / `reify` / `deftype` ownership where statically provable
- conservative suppression for unresolved dynamic dispatch
