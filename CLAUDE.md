# Claude Code Entry Point

`RULES.md` is the single source of truth for AI-agent project rules in this repository.

## Architectural Constitution

Before planning or modifying semidx architecture, read `ARCHITECTURE_CONSTITUTION.md`.

`ARCHITECTURE_CONSTITUTION.md` contains normative architectural constraints.
If an implementation decision conflicts with it, the architecture document wins.

Do not change the architectural direction implicitly.
Any proposed deviation must first be explicitly documented and justified.

Before doing task work:

1. Read `RULES.md`.
2. Follow its Skill And Mode Activation rules. Activating a skill or mode is not itself a task.
3. Read `ARCHITECTURE_CONSTITUTION.md` before planning or making architectural changes.

Keep this file thin. Update `RULES.md` when project rules change.
