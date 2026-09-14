# Repository-scale fixtures

A small multi-unit source tree in both fixture languages. It exists to make
claims about *more than one unit* checkable: which unit a definition belongs to,
what happens to the rest of the tree when one unit changes, and what a reference
that leaves its own unit currently does.

Every cross-unit reference here is unresolved, and that is the point rather than
a gap. `Greeter` names the type `Helper`, and `demo.greeter/greet` names
`decorate`, and neither frontend resolves beyond its own source unit — so both
stay designators with a recorded explanation. When cross-unit resolution is
decided, this tree is where the change becomes visible.

The tree is deliberately small. The large trees that make quadratic behavior
observable are generated inside the tests instead: a few dozen committed files
that differ only by a number would add noise without adding evidence.
