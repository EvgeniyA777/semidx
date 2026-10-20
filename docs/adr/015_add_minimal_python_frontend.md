---
title: "Add a minimal Python frontend"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-10-20"
---

# 015: Add A Minimal Python Frontend

## Feature Or Dependency

A repository the operator indexes with the local MCP preview now contains Python
source. semidx has no Python frontend, so every `.py` file is invisible: it is
not a source unit, produces no diagnostic, and no tool can say anything about
it. The operator chose, on 2026-10-20, a minimal first slice in the shape of the
first Zig slice ([ADR 005](005_add_zig_frontend_and_local_mcp_preview.md)):
definitions, containment, and same-unit bare calls, with everything else
reported as unsupported or unresolved.

This record decides that slice and its dependency: the pinned
`tree-sitter/tree-sitter-python` grammar, compiled from local C sources under
[ADR 002](002_local_tree_sitter_parser_dependency.md). Unlike the grammars
already compiled, this one ships an external scanner (`src/scanner.c`, which
tracks indentation), so the build compiles a grammar's scanner when the pinned
checkout has one.

The implementation plan is
[018: Minimal Python Frontend](../plans/018_minimal_python_frontend.md).

## Decision

### Source units and parsing

- A file whose name ends in `.py` is a Python source unit. Stub files (`.pyi`),
  notebooks, and files without that extension are not.
- The parser is `tree-sitter-python` pinned by full commit id in
  `scripts/setup-tree-sitter-grammars.sh`, listed in `build.zig`'s
  `grammar_checkouts`, compiled with its external scanner, and reached only
  through `src/frontend/tree_sitter.zig`. Build and index never fetch it.
- The scan's default excluded directories gain the directories a Python
  toolchain fills with third-party source: `.venv`, `venv`, `.tox`, and `.nox`.
  This is scan policy, not degradation, exactly as `node_modules` and `target`
  already are, and it changes every source-state identity computed under the
  default policy.

### Definitions

The Python frontend (producer `frontend.python`) records, as `definition` facts:

- a `def` or `async def` statement that is a direct child of the module, with
  or without decorators (role `function`);
- a `class` statement that is a direct child of the module, with or without
  decorators (role `class`); and
- a `def` or `async def` statement that is a direct child of such a class's
  body, with or without decorators (role `method`, `container_path` naming the
  class).

Identity is unit scope, language, role, name, and containment, with no
signature: Python has no overloading, so a parameter edit keeps the definition,
and a rename is identity loss. Two statements with the same identity (for
example a property getter and its setter) are two entities and correspond in
source order, as duplicates already do for every frontend.

Python vocabulary stays in the `python` extension namespace:
`python.construct` (`function`, `class`), `python.async = true`, and
`python.decorated = true`. No shared-core kind is admitted. A module is the
source unit's own container: no `module` entity, no `IMPORTS`.

Relationships: `file DEFINES function|class` and `class DEFINES method`.

### Calls

Inside the body of every covered function and method, every `call` whose callee
is written as a bare identifier `name(...)` is a `CALLS` fact only when Python's
scoping rules give that name exactly one possible meaning, a covered definition
of the same unit:

1. No binding anywhere in the enclosing covered definition — its parameters,
   and any assignment, augmented or annotated assignment target, `for` or
   comprehension target, `with ... as`, `except ... as`, `:=` name, `import`,
   `del`, `global`, `nonlocal`, `match` pattern, `type` statement, type
   parameter, nested `def`, `class`, or `lambda` parameter in its whole
   subtree — has that name. Scope is ignored on purpose: treating a binding as
   visible throughout the definition can only leave more calls unresolved.
2. The unit has no `from ... import *`, which can bind any module-level name.
3. The module-level scope binds the name exactly once. Every binding form above
   counts when it occurs in module scope outside function, lambda, and class
   bodies, including inside module-level `if`, `try`, `for`, `while`, `with`,
   and `match` blocks; so does every `global` declaration of the name and every
   `:=` binding of it anywhere in the unit.
4. That one binding is a covered top-level `def` or `class` without decorators.
   A decorator binds the name to whatever the decorator returns, which this
   frontend does not evaluate.

A class's own scope is never consulted: Python does not make a class body's
names visible inside its methods, so `helper()` inside a method means the
module-level `helper`, and a method named `helper` does not hide it.

Calls inside nested `def` and `lambda` bodies, comprehensions, and decorators or
defaults written inside the covered body are attributed to the enclosing covered
definition, which is the entity whose source contains them. A `class` statement
nested inside a covered body is not walked and is reported as unsupported.

Every other call is recorded as an unresolved `CALLS` relationship with its
reason. Its designator is the identifier the source wrote: the bare name, or the
last attribute name of `a.b.c(...)`, with no qualifier, because this slice does
not establish that any prefix names a module ([ADR 010](010_designator_is_a_structured_name.md)).
A callee that is not a name or an attribute — a call result, a subscript, a
parenthesized expression — records an empty name.

### Not covered

Module-level statements other than covered definitions (imports, assignments,
expression statements, `if __name__ == "__main__":` blocks, and so on) are
reported as unsupported constructs per kind and are not walked, so their calls
are not recorded. So are class body statements other than covered methods, and
definitions nested inside module-level blocks. Docstrings, `pass`, and comments
are skipped without a diagnostic, because they carry nothing this frontend could
claim. A unit that parses with errors yields `analysis_failed`, and a unit that
parses and has no covered definition yields `confirmed_absence`.

Nothing in this slice resolves imports, attributes, receivers (`self.m()`),
inheritance, dispatch, builtins, decorators, or cross-unit names. No `REFERENCES`
are recorded: a name that is read but not called is not recorded.

### The boundary of exactness

A fact under rule 3 means the source of the analyzed unit binds the name once,
to the covered definition. Python also lets other code rebind a module's
globals at run time — `module.helper = other` from another module,
`globals()["helper"] = ...`, `exec`, `setattr` on the module — and no static
reading of one unit can rule that out. The fact is a claim about the program the
source states, which is the same boundary the Clojure frontend's same-unit facts
already have against `alter-var-root` and `intern`. Runtime rebinding is not a
construct of the analyzed source; it is outside what this or any static frontend
observes, and capability documentation must say so.

## Rationale

Python is the operator's actual need, so this is adoption work, not dogfood
coverage. The smallest slice that makes a Python repository navigable —
definitions, containment, and the calls Python's own scoping decides — is the
one the Zig frontend started from, and it keeps every unresolved case visible
rather than guessing.

Python's scoping makes a bare-name call exact only after every way the name
could be rebound has been ruled out. The rules above do that by
over-approximating bindings: an extra binding can only turn a fact into an
unresolved claim, never the reverse. Decorators are excluded for the same
reason: `@functools.cache` and `@app.route` both rebind the name, and the
frontend cannot tell which wrappers preserve identity.

Leaving imports out keeps this slice from becoming an implicit `module` or
`IMPORTS` admission and from requiring a Python package-resolution model
(`sys.path`, namespace packages, relative imports, `__init__.py` re-exports),
which deserves its own decision.

The directory exclusions are part of making a Python repository indexable at
all: a virtual environment under the root holds thousands of third-party units
that would crowd out the repository's own code and can exhaust the scan's unit
budget.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. Facts come only from the
   Python frontend reading covered syntax under the rules above; no text search
   or name matching establishes a relationship.
2. **Nodes as entities, not chunks.** Preserved. Functions, classes, and methods
   are `definition` entities; ranges stay evidence.
3. **Facts, unresolved, and approximate stay distinct.** Preserved. A call is a
   fact only under the four rules; every other call is unresolved with its
   reason, uncovered constructs are diagnostics, and no approximate assertion is
   created. The run-time rebinding boundary is stated rather than hidden.
4. **Stable semantic identity.** Preserved. Identity is unit scope, language,
   role, name, and containment, never ranges or parse node ids. Body and
   parameter edits keep identity; renames are observable identity loss, with a
   renamed class's methods reported through the existing same-name fallback.
5. **Incrementality and consistent observation.** Preserved. Every fact is
   decided from the analyzed unit alone, so the frontend declares no
   dependencies, and an edit reanalyzes only that unit through the existing
   reconcile path. Consumers keep reading published snapshots.
6. **Language frontends preserve meaning.** Preserved. Python's constructs,
   async-ness, and decoration stay in the `python` extension namespace; the
   shared core gains a language, not a kind.
7. **Consumers do not define the model.** Preserved. The MCP tools gain a
   language value derived from the model enum; no tool shape decides what the
   graph records.
8. **Local operation without mandatory source-data transmission.** Preserved.
   The grammar is fetched once by the setup script, like every other grammar;
   build, index, and query stay local.

## Consequences

- `.py` files under the root become source units in every scan, and MCP
  `language` filters accept `python`.
- The default exclusion list changes, so every source-state identity computed
  under the default policy changes once; the pinned identity vectors are
  recomputed and recommitted with that change.
- Building requires the Python grammar checkout: a machine that has not rerun
  `./scripts/setup-tree-sitter-grammars.sh` gets the build's existing "parser
  dependencies were not found" message, not a silent Python-less build.
- Capability documentation states the Python subset, its unresolved cases, and
  the run-time rebinding boundary.
- This decision does not admit imports, cross-unit resolution, attribute or
  receiver calls, inheritance, `REFERENCES`, `module`, `IMPORTS`, `.pyi` stubs,
  persistence, stable schemas, or a semantic contract version.

## Verification Evidence And Planned Checks

Plan 018 must add tests proving:

- `.py` maps to Python and `.pyi` does not; the excluded directories are not
  entered;
- the grammar loads through the adapter at the runtime's ABI and parses
  indentation-sensitive source, which exercises the external scanner;
- covered functions, classes, and methods become `definition` facts with the
  stated roles, containment, labels, and `DEFINES`, and uncovered constructs
  become diagnostics rather than silence;
- a bare call resolves to the one undecorated covered definition of that name,
  and stays unresolved, with its own reason, when the name is a parameter or
  local binding of any listed kind, bound more than once at module level,
  declared `global`, bound by `:=`, decorated, not a covered definition, absent
  from the unit, or in a unit with `from ... import *`;
- a method's bare call resolves past a same-named method of its class;
- attribute and computed callees stay unresolved with the designators above;
- body edits preserve identity, renames report identity loss, a broken parse
  leaves previous claims stale, and an edit reanalyzes one unit; and
- no result introduces `module`, `IMPORTS`, `REFERENCES` from Python,
  approximate assertions, or a non-null semantic contract version.
