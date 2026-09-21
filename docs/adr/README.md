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
- [004: Allow Java Same-Package Type Resolution](004_allow_java_same_package_type_resolution.md)
- [005: Add Zig Frontend And Local MCP Preview](005_add_zig_frontend_and_local_mcp_preview.md)
- [006: Allow Narrow Zig Member Definitions And Local-Import Calls](006_allow_narrow_zig_member_definitions_and_local_import_calls.md)
- [007: Keep The MCP Text Fallback And Add A Diagnostic Probe Flag](007_text_fallback_migration_flag.md)
- [008: Bound Java Same-Package Resolution To A Derived Source Root](008_java_visibility_boundaries.md)
- [009: Allow Java Static Calls Through A Class-Name Receiver](009_java_static_calls.md)
- [010: Record A Designator As A Structured Name](010_designator_is_a_structured_name.md)
- [011: Establish The Java Type Hierarchy From Indexed Source](011_java_hierarchy_from_indexed_source.md)
