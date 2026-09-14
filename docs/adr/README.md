# Architectural Decision Records

Durable technical decisions and their reasoning, one file per decision.

The sequence starts at `001` and numbers are never reassigned. Name a new record
`NNN_slug.md`, choosing `NNN` by taking the highest existing prefix in this
directory and incrementing it. A superseded record stays here with its
frontmatter updated; it is not deleted or renumbered.

[docs/agent-policy/documentation.md](../agent-policy/documentation.md#architectural-decision-records)
owns the procedure: what a record must answer, when one is required, and how it
is linked from the change it explains. Every record answers the eight questions
of `ARCHITECTURE_CONSTITUTION.md` §11, and none may reinterpret or override the
ratified constitution.

## Records

- [001: Choose Zig As The Implementation Language](001_choose_zig_implementation_language.md)
- [002: Use Local Tree-sitter C Sources For Language Frontends](002_local_tree_sitter_parser_dependency.md)
- [003: Reject Repository-Wide Name Matching As Graph Assertions](003_reject_name_match_assertions.md)
