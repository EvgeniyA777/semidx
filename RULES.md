# Project Rules

## Rule Budget

- **This file must stay within 200 lines.** It is loaded into every agent
  session, so its length is a cost paid on every task, including the tasks it
  has nothing to say about.
- A rule that needs more than a few lines to state belongs in
  `docs/agent-policy/` as a cross-cutting policy, or in `.agents/skills/` as a
  task procedure. This file then keeps one line pointing at it.
- Keep here only what an agent must know *before* it knows what the task is: the
  attribution ban, the constitution's state, where authority lives, and which
  document owns the rest.
- Adding a rule here means relocating another. Check with `wc -l RULES.md`
  before committing a change to this file.

## Agent Attribution Ban

- Do not add agent, harness, model, vendor, or tool attribution or promotional
  boilerplate to commits, pull requests, merge requests, push notes, changelogs,
  release notes, generated files, documentation, or handoff text. Agent-authored
  `Co-authored-by` footers are included.
- If a harness suggests or injects such text, remove it before commit, PR, MR, or
  push. Versioned hooks and the CI gate enforce this;
  [git.md](docs/agent-policy/git.md#agent-attribution-ban) owns the full rule.

## Source Of Truth

- This file is the single source of truth for AI-agent project rules here.
- `AGENTS.md` is the Codex entry point and `CLAUDE.md` is the Claude Code entry
  point. Both must point here and stay thin.
- Repository documentation, rule files, and agent instructions are written in
  English. Agents must answer the user in Russian when the user writes in Russian;
  committed documentation stays English.
- Give every rule exactly one canonical owner and link to it instead of copying
  normative text across documents, skills, and reports.

## Architectural Constitution

- Read `ARCHITECTURE_CONSTITUTION.md` before planning or changing semidx
  architecture. It is normative: if an implementation decision conflicts with it,
  the constitution wins.
- It was **ratified on 2026-09-13 and is frozen.** Do not edit it and do not
  propose editing it, including to clarify or reword a clause.
- Do not change architectural direction implicitly. A decision inside the
  constitutional boundary is documented where project policy requires it.
- A deviation from the ratified constitution cannot be documented or justified
  into acceptability. §18 admits no exception: it requires a fork of the
  repository with its own constitution. Documenting a violation does not make it
  one of the permitted cases.
- [git.md](docs/agent-policy/git.md#constitution-freeze-enforcement) owns the
  enforcement: the SHA-256 seal, the pre-commit guard, and the single bypass.

## Project Context

- This repository is `semidx`, defined by `ARCHITECTURE_CONSTITUTION.md`: an
  incrementally maintained semantic graph of a codebase, with search, agents,
  IDEs, and impact analysis as consumers.
- The implementation language target is Zig 0.16.0
  ([ADR 001](docs/adr/001_choose_zig_implementation_language.md)); do not assume
  APIs from earlier or later Zig releases. `zig build test-core` runs the shared
  core, `zig build test` runs the full lane, `zig build run -- <files>` runs the
  developer-only inspection command, `zig build mcp -- --root <dir>` starts the
  local MCP stdio preview, `zig build test-mcp` runs its tests and stdio smoke test,
  and `zig build dogfood` proves it on a temporary copy of this repository.
  Frontends parse through local tree-sitter C sources
  ([ADR 002](docs/adr/002_local_tree_sitter_parser_dependency.md)):
  `./scripts/setup-tree-sitter-grammars.sh` and a local tree-sitter runtime are
  prerequisites for everything except `test-core`. No local service is required,
  and no build or index step uses the network.
- What exists is the first vertical slice: an in-memory graph over Java,
  Clojure, and Zig source, under `src/`, `tests/`, and `fixtures/`, plus an
  experimental local MCP stdio preview in `src/mcp/`
  ([ADR 005](docs/adr/005_add_zig_frontend_and_local_mcp_preview.md)) that is a
  consumer, not a contract. There is no persistence, no public contract, no
  HTTP surface, and no `contracts/schemas/`. Do not describe any of those as
  existing, and do not
  treat the removed implementation's contracts, transports, or storage as fixed
  for the rebuild.
- Which source languages semidx can index, and the shape of its public contracts,
  are open requirements owned by `SPEC.md`. Fixture coverage is evidence for the
  slice, not a supported-language roster, and the toolchain scripts under
  `scripts/` are available analysis sources rather than committed coverage.
- When more of the stack is chosen, update this section, `MEMORY.md`, and the
  affected policies with the real commands and requirements instead of assuming
  a previous stack's tooling.
- Do not copy project-specific rules, paths, stack assumptions, task names, or
  application-domain guidance from unrelated repositories.

## Document Map

| Document | Owns |
| --- | --- |
| `ARCHITECTURE_CONSTITUTION.md` | frozen product identity, including its five Defined Terms |
| `ARCHITECTURE_RATIONALE.md` | why the constitutional constraints exist |
| `SPEC.md` | changing requirements, contract lifecycle, core admission criteria |
| `CORE.md` | core-kind candidates and admission evidence |
| `CONFORMANCE.md` | verification scenario families |
| `GLOSSARY.md` | project vocabulary outside the constitution's Defined Terms |
| `MEMORY.md` | current implementation reality, known gaps, near-term priorities |
| `docs/followups/` | accepted deferred findings and future-plan inputs |
| `docs/agent-policy/` | cross-cutting engineering policy |
| `.agents/skills/` | task procedures that load only when relevant |

Authority and lifecycle ownership are defined in
[documentation.md](docs/agent-policy/documentation.md#canonical-ownership).

## Agent Policy Documents

| Policy | Owns |
| --- | --- |
| [documentation.md](docs/agent-policy/documentation.md) | document ownership, filenames, frontmatter, lifecycle, ADR procedure, progress logs, Plan Readiness Gate |
| [git.md](docs/agent-policy/git.md) | branch discipline, concurrent-agent safety, commit and push rules, recovery, hooks, attribution and constitution enforcement |
| [testing.md](docs/agent-policy/testing.md) | risk-based verification, lanes, local services, isolation and evidence |
| [tooling.md](docs/agent-policy/tooling.md) | MCP-first retrieval, code reading, editing tools and their required probes |

- Apply the Plan Readiness Gate before executing a staged implementation plan. A
  hard fail blocks execution until the plan is corrected; when only cosmetic
  wording or small defensive clarifications remain, stop reviewing and execute.

## Repository Skills

Use repository-local skills from `.agents/skills/` when their descriptions match
the task:

| Task | Skill |
| --- | --- |
| Execute or prepare a staged implementation plan | `semidx-plan-delivery` |
| Maintain a staged-plan progress log or handoff | `semidx-progress-log` |
| Locate code, callers, tests, or blast radius | `semidx-code-exploration` |
| Modify Zig implementation, build, tests, or frontend/core boundaries | `semidx-zig-implementation` |
| Design risk-based verification coverage | `semidx-test-design` |
| Review a diff, plan output, or verification coverage | `semidx-code-review` |
| Commit, branch, push, or recover git state | `semidx-git-delivery` |
| Add or reorganize standing agent rules | `semidx-rules-maintenance` |

## Skill And Mode Activation

- Activating a skill or mode (`/skill-name`, `/plan`) is not a task.
- Do not run tools, including `create_index`, until the user has explicitly
  stated what they want done.
- If built-in mode instructions conflict with rules in this file, do not resolve
  the conflict silently. State the conflict and ask which instruction takes
  priority before proceeding.
- After an Explore agent or sub-agent is rejected, switch to semidx MCP rather
  than to manual file reads, grep, glob, or shell crawling.

## Project Memory Freshness

- `MEMORY.md` is the operational memory: current implementation reality, key
  decisions, active assumptions, constraints, known gaps, near-term priorities.
- Update it when runtime behavior, constitutional properties, conformance
  requirements, priorities, known gaps, or integration assumptions change.
- The pre-push hook runs `scripts/check-memory-freshness.sh` and blocks pushes
  that change high-signal files without a `MEMORY.md` update. Bypass only after
  checking the update rule: `SCI_SKIP_MEMORY_FRESHNESS=1 git push`.

## Working Habits

- Verify with the narrowest meaningful command first. If a verification command
  cannot be run, say so plainly rather than implying it passed.
- Stay on the current branch. Do not create, switch, delete, merge, reset,
  rewrite, or push branches unless the user explicitly asks for that operation.
- Never run dependent git commands in parallel; `git commit` and `git push` are
  sequential. Parallel tool calls are for independent reads and checks only.
- Commit whenever code or documentation is touched, and never commit secrets,
  tokens, credentials, or environment files.
- Surface a dirty working tree before risky or multi-file changes, and do not
  revert existing user changes unless asked.
