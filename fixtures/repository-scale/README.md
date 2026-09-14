# Repository-scale fixtures

A small multi-unit source tree in both fixture languages. It exists to make
claims about *more than one unit* checkable: which unit a definition belongs to,
what happens to the rest of the tree when one unit changes, and what a reference
that leaves its own unit currently does.

The two languages now differ here on purpose. `Greeter` names the type `Helper`,
which exactly one other unit declares as a top-level class of the same explicit
package `demo`, so Java scoping establishes the reference: it is a fact about the
`Helper` class, with a dependency on `Helper.java`
([ADR 004](../../docs/adr/004_allow_java_same_package_type_resolution.md)).
`demo.greeter/greet` names `decorate`, and no Clojure namespace resolution has
been decided, so it stays a designator with a recorded explanation rather than
being matched across the tree
([ADR 003](../../docs/adr/003_reject_name_match_assertions.md)).

The tree is deliberately small. The large trees that make quadratic behavior
observable are generated inside the tests instead: a few dozen committed files
that differ only by a number would add noise without adding evidence.
