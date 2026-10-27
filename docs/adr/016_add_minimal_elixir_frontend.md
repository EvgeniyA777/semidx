---
title: "Add a minimal Elixir frontend"
doc_type: "adr"
lifecycle: "active"
status: "proposed"
agent_action: "reference_for_context"
updated: "2026-10-27"
---

# 016: Add A Minimal Elixir Frontend

## Feature Or Dependency

The operator asked on 2026-10-27 for Elixir onboarding and chose a minimal
first slice in the shape of the Python slice
([ADR 015](015_add_minimal_python_frontend.md)): modules, function and macro
definitions, containment, and same-module local calls, with everything else
reported as unsupported or unresolved. semidx has no Elixir frontend today, so
every `.ex` and `.exs` file is invisible: it is not a source unit, produces no
diagnostic, and no tool can say anything about it.

This record decides that slice and its dependency: the pinned
`elixir-lang/tree-sitter-elixir` grammar, compiled from local C sources under
[ADR 002](002_local_tree_sitter_parser_dependency.md). The grammar ships an
external scanner (`src/scanner.c`, C only), which the build already compiles for
any checkout that has one since Plan 018.

The implementation plan is
[019: Minimal Elixir Frontend](../plans/019_minimal_elixir_frontend.md).

## Decision

### Source units and parsing

- A file whose name ends in `.ex` or `.exs` is an Elixir source unit. Templates
  (`.eex`, `.heex`, `.leex`) and files without those extensions are not. Build
  scripts, configuration, and tests written as `.exs` (`mix.exs`,
  `config/*.exs`, `test/**/*_test.exs`) are ordinary units; what they contain
  outside a module is reported like any other uncovered form.
- The parser is `tree-sitter-elixir` pinned by full commit id in
  `scripts/setup-tree-sitter-grammars.sh`, listed in `build.zig`'s
  `grammar_checkouts`, compiled with its external scanner, and reached only
  through `src/frontend/tree_sitter.zig`. Build and index never fetch it.
- The scan's default excluded directories gain the two directories a Mix
  project fills with code that is not the repository's own: `deps` (fetched
  dependency source) and `_build` (compilation output). This is scan policy,
  not degradation, exactly as `node_modules`, `target`, and `.venv` already
  are. It changes every source-state identity computed under the default
  policy, and, because exclusion is by directory name, it also hides a
  directory named `deps` in a repository that is not a Mix project.

### Definitions

The Elixir frontend (producer `frontend.elixir`) records, as `definition`
facts:

- a `defmodule` call whose first argument is an alias (`defmodule Foo.Bar do
  ... end`), placed directly at the top level of the unit or directly in the
  `do` block of another covered module (role `defmodule`);
- a run of clauses of one function or macro placed directly in the `do` block
  of a covered module (role `function` for `def` and `defp`, role `macro` for
  `defmacro` and `defmacrop`).

The module role is named after the form, `defmodule`, so that nobody reads it
as the shared-core `module` kind, which stays a blocked candidate in
[CORE.md](../../CORE.md). Function and macro roles reuse the role vocabulary
the Python and Zig frontends already use for callables.

A function clause is covered when its head is a call whose target is an
identifier (`foo(a, b)` or `foo a, b`) or a bare identifier (`foo`), optionally
followed by a `when` guard. Its body is a `do` block, a `do:` keyword, or absent
(a bodiless head that declares defaults). Any other head — an operator
definition (`def a + b`), a name produced by `unquote`, a pattern that is not a
call — is unsupported.

The **arity** of a clause is the number of its head arguments. A head argument
written `arg \\ default` declares a default, and the clause group then also
answers every arity from the count of arguments without defaults up to the
full arity.

**Clause runs.** Elixir defines one function per module, name, and arity, from
all clauses with that name and arity. The frontend records one entity per
*run*: consecutive clauses in the module's `do` block with the same name, arity,
and construct, where only module attributes and comments may sit between them.
The entity's range spans the run from its first clause to its last. When the
same name and arity appear again later in the module, with the same construct
(a split run, which Elixir warns about) or another one (which it rejects), the
first run stays the definition, every later clause is reported as an
unsupported construct, and no call to that name and arity in the module becomes
a fact. Two runs whose arity ranges overlap through defaults, which Elixir also
rejects, are both recorded, and calls in the overlap are not facts.

Identity is unit scope, language, role, name, signature, and containment. The
signature is `name/arity`, as the Clojure frontend already records for `defn`,
because an Elixir function is its name and arity: `foo/1` and `foo/2` are two
entities, and changing a function's arity is identity loss. Switching `def` to
`defp` keeps identity, because visibility is a label, not a role. A module's
identity is its name as written and its enclosing modules' names; renaming a
module is identity loss for the module and for each definition in it, reported
through the existing same-slot fallback.

Elixir vocabulary stays in the `elixir` extension namespace:

- `elixir.construct` — `defmodule`, `def`, `defp`, `defmacro`, `defmacrop`;
- `elixir.module` — the full module name: for a top-level module, its alias
  as written; for a nested one, the enclosing module's full name, a dot, and
  its alias, which is how Elixir names a nested module; on a function or macro,
  the full name of the module that defines it;
- `elixir.min_arity` — on a function or macro whose head declares defaults, the
  smallest arity it answers.

No shared-core kind is admitted, and no `IMPORTS` is recorded.

Relationships: `file DEFINES defmodule` for a top-level module,
`defmodule DEFINES defmodule` for a nested one, and
`defmodule DEFINES function|macro` for its clause runs.

### Calls

The frontend walks every covered clause of every covered function and macro:
its guard, its default-value expressions, and its body. Calls inside anonymous
functions (`fn ... end`) and captures (`&foo(&1, 2)`) are attributed to the
enclosing definition, whose source contains them.

A **local call** is a call whose target is an identifier: `foo(a)`, `foo a`,
`foo a do ... end`, or the right side of a pipe. Its arity is the number of
arguments, where a trailing keyword list counts as one, a `do` block (with any
`else`, `after`, `rescue`, or `catch`) counts as one, and a pipe adds one for
the value piped in. A bare identifier on the right side of `|>` is a local call
of arity 1. A bare identifier anywhere else is not recorded: Elixir reads it as
a variable when one is bound, and this slice does not track bindings.

A local call is a `CALLS` fact when the innermost covered module enclosing it
has exactly one recorded clause run whose arity range covers the call's arity,
and that name and arity is not split. Elixir decides local calls this way: a
local definition takes precedence, and an import of the same name and arity,
including from `Kernel`, is a compile-time conflict rather than another meaning.
A variable cannot be called by writing `foo(...)`, so no local binding can
shadow the name, and no binding analysis is needed.

Kernel special forms are not calls of the module. `quote` blocks are not walked,
because their calls belong to the code a macro produces in its caller, and each
is reported as an unsupported construct. `super(...)` is an unresolved call with
its own reason. Other special forms (`case`, `cond`, `with`, `for`, `try`,
`receive`, `import`, `alias`, `require`, and the `__MODULE__`-style forms) are
not recorded, and their arguments are walked.

Every other call is recorded as an unresolved `CALLS` relationship with its
reason:

- a local call with no recorded run covering its arity in the enclosing module
  (it may be imported, including from `Kernel`, injected by `use`, or defined
  by a construct this slice does not cover, such as `defdelegate`);
- a local call whose name and arity is split, or covered by more than one run;
- a remote call `Alias.fun(...)`, whose designator is `fun` qualified by the
  alias as written, because an alias always names a module but this slice
  resolves no aliases and no other units
  ([ADR 010](010_designator_is_a_structured_name.md));
- a remote call through anything else (`mod.fun()`, `:erlang.fun()`,
  `__MODULE__.fun()`), whose designator is `fun` with no qualifier;
- an anonymous call `f.(x)` or a callee that is not an identifier, whose
  designator has an empty name.

### Not covered

Forms in a module's `do` block other than covered definitions and nested
modules — `use`, `import`, `alias`, `require`, `defstruct`, `defexception`,
`defdelegate`, `defguard`, `defoverridable`, module attributes other than
documentation, and any other macro call — are reported as unsupported constructs
per kind and are not walked. `@moduledoc`, `@doc`, and `@typedoc` carry nothing
this frontend could claim and are skipped without a diagnostic, as Python
docstrings are. Top-level forms other than covered modules (`defprotocol`,
`defimpl`, scripts, configuration calls) and modules nested anywhere but
directly in a covered module's `do` block are unsupported. A unit that parses
with errors yields `analysis_failed`, and a unit that parses and has no covered
module yields `confirmed_absence`.

Nothing in this slice resolves aliases, imports, `use`, remote calls,
protocols, behaviours, or cross-unit names. No `REFERENCES` are recorded:
captures such as `&foo/1` and names that are read but not called are not
recorded.

### The boundary of exactness

A local-call fact means the analyzed module's own source defines a function or
macro with that name and an arity range covering the call, and Elixir's
local-call rule sends the call there. Macros that the module invokes — `use`,
`@before_compile` hooks, any custom macro — can add clauses to that same
function, or replace it after marking it `defoverridable`, and no reading of
one unit observes what a macro expands to. The fact names the definition the
source writes; capability documentation must say that macro expansion is
outside what this frontend observes.

## Rationale

The smallest slice that makes an Elixir repository navigable is the one the
Python and Zig frontends started from: what is defined where, and the calls the
language itself decides from one unit. Elixir's local-call rule is simpler than
Python's scoping, because a variable can never stand in a call position, so the
exact subset is decided by name and arity alone.

Arity belongs in identity because it is part of the function's name in Elixir:
the language, its tooling, and its documentation all write `foo/2`. Treating
arities as one entity would merge functions Elixir keeps apart, and calls of
one arity would be reported as calls of the other.

A split run is reported instead of merged because the frontend would otherwise
have to choose which run is "the" entity and which range is its evidence; the
first-run rule keeps identity stable and the call rule stays exact by declining
every call of that name and arity.

Leaving aliases, imports, and remote calls out keeps this slice from becoming an
implicit `module` or `IMPORTS` admission and from needing a cross-unit module
model, which deserves its own decision, as it did for Python.

The two directory exclusions are what make a Mix project indexable at all:
`deps` holds the full source of every dependency and would outnumber the
repository's own units.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. Facts come only from the
   Elixir frontend reading covered syntax under the rules above; no text search
   or name matching across units establishes a relationship.
2. **Nodes as entities, not chunks.** Preserved. Modules, functions, and macros
   are `definition` entities; a clause run's range is evidence, not identity.
3. **Facts, unresolved, and approximate stay distinct.** Preserved. A call is a
   fact only under the local-call rule; every other call is unresolved with its
   reason, uncovered forms are diagnostics, and no approximate assertion is
   created. The macro-expansion boundary is stated rather than hidden.
4. **Stable semantic identity.** Preserved. Identity is unit scope, language,
   role, name, `name/arity`, and containment, never ranges or parse node ids.
   Body edits, clause additions, and `def`/`defp` switches keep identity; an
   arity change or a rename is observable identity loss.
5. **Incrementality and consistent observation.** Preserved. Every fact is
   decided from the analyzed unit alone, so the frontend declares no
   dependencies, and an edit reanalyzes only that unit through the existing
   reconcile path. Consumers keep reading published snapshots.
6. **Language frontends preserve meaning.** Preserved. Elixir's constructs,
   module names, and default-argument arities stay in the `elixir` extension
   namespace; the shared core gains a language, not a kind.
7. **Consumers do not define the model.** Preserved. The MCP tools gain a
   language value derived from the model enum; no tool shape decides what the
   graph records.
8. **Local operation without mandatory source-data transmission.** Preserved.
   The grammar is fetched once by the setup script, like every other grammar;
   build, index, and query stay local.

## Consequences

- `.ex` and `.exs` files under the root become source units in every scan, and
  MCP `language` filters accept `elixir`.
- The default exclusion list changes, so every source-state identity computed
  under the default policy changes once; the pinned identity vectors are
  recomputed and recommitted with that change. A non-Mix repository's own
  `deps` directory is no longer scanned.
- Building requires the Elixir grammar checkout: a machine that has not rerun
  `./scripts/setup-tree-sitter-grammars.sh` gets the build's existing "parser
  dependencies were not found" message, not a silent Elixir-less build.
- Capability documentation states the Elixir subset, its unresolved cases, and
  the macro-expansion boundary.
- This decision does not admit aliases, imports, `use` expansion, remote or
  cross-unit calls, protocols, behaviours, `REFERENCES`, `module`, `IMPORTS`,
  templates, persistence, stable schemas, or a semantic contract version.

## Verification Evidence And Planned Checks

Plan 019 must add tests proving:

- `.ex` and `.exs` map to Elixir and `.eex`/`.heex` do not; `deps` and
  `_build` are not entered;
- the grammar loads through the adapter at the runtime's ABI and parses source
  that exercises the external scanner (heredocs, sigils);
- covered modules (top-level and nested), functions, and macros become
  `definition` facts with the stated roles, `name/arity` signatures,
  containment, labels, and `DEFINES`; multi-clause functions are one entity;
  defaults set `elixir.min_arity`; uncovered forms become diagnostics rather
  than silence;
- a local call resolves to the one run covering its arity in the innermost
  module, including through a pipe, a `do` block, a keyword list, an anonymous
  function, a capture body, and a default-argument range; and stays unresolved,
  with its own reason, when no run covers the arity, the run is split, or two
  runs cover it;
- a call in a nested module resolves inside that module and never to a
  same-named function of the enclosing one;
- `quote` bodies are not walked; `super` is unresolved; other special forms are
  not recorded; remote, value, and anonymous callees stay unresolved with the
  designators above;
- body edits and clause additions preserve identity, arity changes and renames
  report identity loss, a broken parse leaves previous claims stale, and an edit
  reanalyzes one unit; and
- no result introduces `module`, `IMPORTS`, `REFERENCES` from Elixir,
  approximate assertions, or a non-null semantic contract version.
