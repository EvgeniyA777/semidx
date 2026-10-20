---
title: "Python cross-unit, attribute, and module-level calls"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-10-20"
---

# Python Cross-Unit, Attribute, And Module-Level Calls

## Classification

`coverage_gap`

## Source

Left out on purpose by [ADR 015](../adr/015_add_minimal_python_frontend.md),
the operator's choice of a minimal first Python slice, and recorded as residual
risk in the
[Plan 018 progress log](../reports/018_minimal_python_frontend_progress.md).

## Current Behavior

The Python frontend resolves only a bare call to a same-unit, undecorated,
module-level definition whose name the module binds once. Honest but incomplete:

- A call to another module — `from app.util import shared; shared()` or
  `util.shared()` — is unresolved. `semidx_references` for `shared` lists no
  caller in another file; the bare-name form appears only as an unresolved
  mention.
- A method call through `self` or any value — `self.save()`,
  `client.get()` — is unresolved with its last name, so a method's callers are
  never listed.
- A call to a decorated function is unresolved, which covers most framework
  entry points (`@app.route`, `@pytest.fixture`, `@functools.cache`).
- Calls in module-level code, class bodies, decorators, default values, and
  base-class lists are not recorded at all, and are reported only as uncovered
  statement kinds.

## Deferral Reason

Resolving imports needs a Python package-resolution model — which directories
are import roots, namespace packages, relative imports, `__init__.py`
re-exports, `sys.path` — and the dependency declarations that keep a
cross-unit fact current, much as ADR 006 needed for Zig's relative `@import`.
`self.m()` needs the enclosing class's method set and a rule for inheritance
and overriding. Decorators need a rule for which wrappers preserve the bound
definition. Each is its own decision, and none was needed to make a Python
repository visible at all.

## Acceptance Direction

A future ADR and plan may admit, each under exact evidence:

- `from <module> import <name>` and `import <module>` naming one indexed Python
  unit under an explicit import-root rule, with a provider dependency, resolving
  a bare or `module.name(...)` call to that unit's one module-level binding;
- `self.m()` inside a method of a class with no base classes, resolving to the
  class's one method of that name; and
- module-level code as a source of calls, attributed to the unit's container.

Each must keep the run-time rebinding boundary ADR 015 states visible.

## Required Tests

- Cross-unit facts appear only through the admitted import forms, declare a
  provider dependency, and go stale when the provider changes.
- Ambiguous or missing providers, star imports, and shadowed imports stay
  unresolved with their own reasons.
- `self.m()` stays unresolved in any class with a base class, and for a name the
  class declares more than once.
