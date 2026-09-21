---
title: "Resolve a Java call on a receiver whose declared type is known"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-21"
---

# 012: Resolve A Java Call On A Receiver Whose Declared Type Is Known

## Feature Or Dependency

The largest single family of unresolved Java claims is a call on a receiver that
is a value: `helper.run()`, where `helper` is a field, a parameter, or a local.
[ADR 009](009_java_static_calls.md) resolves a receiver that is a **class
name**, and declines a bound name on purpose — a variable obscures a type of the
same name (JLS 6.4.2), so the name is read as a value and the call stops there.

This record decides when that value's declared type may name the method. It is
[Plan 014](../plans/014_java_receiver_coverage.md) Stage 5, and it closes the
gap [Follow-up 014](../followups/014_java_instance_receiver_calls.md) records.

## Evidence

On `apache/dubbo` at `df9c5e1`, whole graph, 4,050 Java units:

| Measurement | Count |
| --- | ---: |
| Unresolved calls whose receiver is a simple name a binding declares | 55,565 |
| Unresolved calls whose receiver is not a simple name | 21,444 |
| All unresolved Java calls | 118,686 |

Plan 012 specified this rule in full and then declined to build it: its sample
predicted 63 addressable calls in 1,200 definitions, about 1,390 whole-graph,
which did not pay for a lexical type environment beside the 135 static calls
that needed none.

What changed is that the environment is no longer the cost. Plan 012 Stage 4
already built the lexical half — which names are bound where, with
declaration-order visibility and poisoning for every uncovered introducer — so
what was missing is one field per binding. And
[ADR 011](011_java_hierarchy_from_indexed_source.md) added the other
precondition Follow-up 014 named: a target type that declares supertypes can now
be asked whether anything above it declares the invoked name.

[Plan 014 Stage 4](../reports/014_java_receiver_coverage_progress.md#gate-c)
measured the result before it was built: **2,657** calls satisfy every condition
below, against a gate floor of 1,000.

## Decision

**D9 — A binding records the type its declaration writes, and nothing else
changes.** Plan 012's covered introducer list stands unchanged: a field
declaration (an interface's constants included), a formal parameter, and a local
variable declarator. Each records the simple type name its declaration writes.

Every other construct that binds a name records itself as **uncovered** and
poisons the name for the method: a varargs parameter, a `for`-each variable, a
`catch` parameter, a try-with-resources resource, a lambda parameter of any
spelling, a type pattern, a record pattern component. A declarator or parameter
carrying its own dimensions is uncovered, and so is a declared type that is not
a bare name — generic, array, qualified, primitive, or `var`.

Two rules decide which binding answers:

- **An uncovered binding wins over every covered one.** It is a poison, not a
  candidate: a name any uncovered construct binds anywhere in the method is not
  read as a value of a known type, whichever declaration is lexically nearer.
- **A covered binding inside a lambda or a nested type body is recorded
  uncovered.** Those bind inside their own subtree while this frontend reads
  bindings for the whole method, so a type read from one could give a name a
  meaning outside it — a wrong fact rather than a decline.

Declaration-order visibility is unchanged: a local binds from its declarator to
the end of its block, so a call written before it still sees the class.

**D10 — A value-receiver call is a fact only when every condition holds at
once.** In order, each with its own reason when it fails:

1. the receiver is a simple name, and the call is not inside a class body
   declared in the method;
2. a covered introducer binds that name;
3. its declared type is a simple name;
4. that name resolves through the unchanged `resolveType`, inside the
   [ADR 008](008_java_visibility_boundaries.md) boundary;
5. the target type declares no supertypes, or its chain is closed under
   ADR 011 D4 and **nothing above it** declares a method of the invoked name;
6. the target type declares exactly one method of that name;
7. access permits the call: the method is public, or the target is the
   enclosing type.

`this.m()` is admitted on the same terms from condition 5 onward, because the
enclosing type is known exactly and no binding is involved. `super.m()` is not:
naming the method it reaches is selecting an inherited member, which ADR 011 D6
forbids. Neither is any receiver that is not a simple name — a creation, a
chained call, a field access, a literal.

**A value receiver names no scope, so none of these claims carries a
qualifier.** The source wrote a variable and this frontend read its declared
type; that type is not a name the source put in front of the method, so the
designator stays the bare method name and the type is named in the words
instead. This is [ADR 010](010_designator_is_a_structured_name.md) D1 applied
exactly as written.

**D11 — No new category and no new authority.** No approximate assertion, no
ranking, no name matching, no normalization, and no dispatch. A method the
target inherits or overrides is never named.

## Rationale

**The declared type is a fact the source states, not an inference.** `Other x`
says what `x` is. This record reads that sentence and nothing else: it does not
infer a type from an initializer, from a cast, from a generic argument, or from
flow. Where the source does not say it plainly — `var`, a generic, an array —
the answer stays unresolved.

**Dispatch is the line, and overriding is where it bites.** A call on a value
reaches the method the runtime type has, which is why condition 5 asks about the
*inherited* set rather than the target's own. A target that declares `only()`
and inherits `only()` from its superclass is exactly the case where the source
names two methods and the call names neither statically; it declines. A target
that declares a name nothing above it declares has one method to select, and
that is the one the call names whatever the runtime type is, because nothing
above can override what is not there.

**An uncovered binding poisons rather than competes.** The alternative — take
the lexically nearest binding and let an uncovered one lose — is smaller and
wrong: this frontend collects a method's bindings for the whole method, so
"nearest" is not a scope. Poisoning is a decline, and a decline is never a wrong
fact.

**The rejected alternative is a type environment.** A real one — flow-sensitive,
generic-aware, with inference for `var` — resolves far more, and it is a
different project inside this one. It would need argument types for overloads,
type arguments for generics, and a model of assignment; each of those is a place
where an approximation becomes a fact. What this record builds instead is a
lookup from a name to the type its own declaration writes, which is exact or
absent.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. The binding table is read
   from the analyzed unit's own source; the target type and its methods come
   from graph facts through the existing projections. No answer comes from
   outside the graph, and no text match establishes one.
2. **Nodes as entities, not chunks.** Preserved. Nothing new becomes a node: a
   binding is not an entity, a declared type is not an entity, and the claim is
   an ordinary `calls` relationship between two definitions.
3. **Facts, unresolved and approximate stay distinct.** This is the clause D10
   serves. Seven conditions, each with its own explanation when it fails, and a
   fact only when all of them hold. No approximate assertion is introduced. A
   call this rule declines keeps its designator, its `missing` part, its
   producer and its freshness.
4. **Stable semantic identity.** Preserved. Nothing here creates or names an
   entity; it selects one the graph already holds, by the same identity
   evidence a class-qualified call uses.
5. **Incrementality and consistent observation.** A resolved value call declares
   a dependency on the unit that declares the target, and on every unit in the
   target's supertype chain when that chain was walked, so an edit to any of
   them reaches the caller. Where the call resolved to nothing there is no
   dependency to follow, so the analyzer records the reader by
   `<declared type>.<method>` in the same hint channel ADR 009 uses, and a
   provider that gains an overload or a supertype reaches its callers through
   it. Tests prove both directions: an overload appearing takes the fact away,
   and a supertype appearing does too.
6. **Language frontends preserve meaning.** Preserved. What a covered
   introducer is, what `var` means, what obscures a type name and what a method
   of an inherited name may do are Java's questions, answered in the Java
   frontend with its own vocabulary. No shared-core kind is added.
7. **Consumers do not define the model.** Preserved. No MCP tool's arguments,
   result shape, cursors or budgets change. More calls are facts because the
   frontend established them.
8. **Local operation without mandatory source-data transmission.** Preserved.
   Everything is read from the working copy by the same local parse and the same
   in-memory graph. No build descriptor, classpath, module, or jar is read.

## Consequences

- Java gains its largest single family of call facts. On the clone **3,294**
  calls became facts, and `receiver_bound` — 55,565 claims — reads zero,
  replaced by eleven families that say which condition failed.
- 445 of those are `this.m()`, which used to decline as a receiver this frontend
  does not resolve.
- A call on a value declines without a qualifier, where a class-qualified call
  declines with one. That difference is the point: one names a scope and the
  other does not.
- The analyzer's candidate table grows: it is now built for the
  `<declared type>.<method>` pairs a unit writes as well as the
  `<class name>.<method>` ones. The pre-pass that finds them is deliberately a
  superset and decides nothing.
- A typed lambda parameter now poisons a name it used to poison for a different
  reason. The answer does not move; the words do.

## What This Record Does Not Enable

- **No dispatch and no inherited target.** `super.m()` stays unresolved, and a
  method the target inherits is never named.
- **No inferred types.** `var`, generics, arrays, wildcards, and qualified type
  names leave the receiver unresolved, each with its own reason.
- **No overload resolution.** Two methods of one name on the target decline.
- **No flow.** An assignment, a cast, and an `instanceof` narrowing change
  nothing; only the declaration is read.
- **No approximate assertion, no core kind, no contract, no persistence, and no
  version bump.** `semantic_contract_version` stays `null`.

## Verification Evidence And Planned Checks

- A matrix pins every covered introducer resolving — field, parameter, local,
  and `this` — to the method the declared type declares, and never to the
  same-named static method a frontend reading the receiver as a class would
  have picked.
- A matrix pins every uncovered introducer poisoning the name: varargs,
  `for`-each, `catch`, resource, all three lambda spellings, type pattern,
  record pattern component.
- Tests pin each remaining condition with its own reason: an unresolvable
  declared type, an overloaded target, an inaccessible target, a missing
  method, a target whose chain is open, a target that overrides an inherited
  name, a nested class body, `super`, a creation, and a chained call.
- A test pins that two locals of one name in two blocks resolve to two types,
  and that a declaration after the invocation does not bind it.
- A test pins that no value-receiver decline carries a qualifier.
- An incremental test pins that a provider gaining an overload, and a provider
  gaining a supertype, each take the caller's fact away without the caller
  being edited.
- `zig build test-core`, `zig build test`, `zig build test-mcp`,
  `zig build dogfood`, `zig build preview-gate`, and
  `zig fmt --check build.zig src tests` all pass.
