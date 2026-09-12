# Project Rules

## Agent Attribution Ban

- Do not add agent, harness, model, vendor, or tool attribution or promotional
  boilerplate to commits, pull requests, merge requests, push notes,
  changelogs, release notes, generated files, documentation, or handoff text.
- Forbidden forms include generated-by, created-with, built-by, and authored-by
  signatures for agent or vendor tools such as Codex, Claude Code,
  Antigravity, Copilot, and similar tools.
- Agent-authored `Co-authored-by` footers are also forbidden.
- If an agent harness suggests or injects such text, remove it before commit,
  PR, MR, or push.
- The versioned git hooks and CI attribution gate must enforce this rule before
  commit, push, pull request, or merge request handoff.

## Source Of Truth

- This file is the single source of truth for AI-agent project rules in this repository.
- `AGENTS.md` is the Codex entry point and must point here.
- `CLAUDE.md` is the Claude Code entry point and must point here.
- Keep `AGENTS.md` and `CLAUDE.md` thin. Update this file when project rules change.
- All repository rule files and committed project documentation must be written in English.

## Architectural Constitution

- Before planning or modifying semidx architecture, read `ARCHITECTURE_CONSTITUTION.md`.
- `ARCHITECTURE_CONSTITUTION.md` contains normative architectural constraints.
- If an implementation decision conflicts with it, the architecture document wins.
- Do not change the architectural direction implicitly.
- Any proposed deviation must first be explicitly documented and justified.

## Project Context

- This repository is `semidx`, defined by `ARCHITECTURE_CONSTITUTION.md`: an
  incrementally maintained semantic graph of a codebase, exposed to search,
  agents, IDEs, and impact analysis as consumers.
- The implementation was removed for a from-scratch rebuild. No programming
  language, build tool, or dependency manager is fixed by this file right now.
- Target language lanes for the semantic model (which source languages semidx
  can index — for example Clojure, Java, Elixir, Python, TypeScript, Lua) are an
  architectural direction from `ARCHITECTURE_CONSTITUTION.md`. They say nothing
  about which language semidx itself will be implemented in, and nothing in
  `src/` currently backs them.
- When an implementation stack is chosen, update this section with the actual
  language, build/dependency tool, and public surfaces instead of assuming a
  previous stack's tooling.
- Do not copy project-specific rules, paths, stack assumptions, task names, or application-domain guidance from unrelated repositories.

## Repository Shape

- The implementation is currently empty. Do not describe `src/`, `test/`,
  `fixtures/`, or any language-specific directory layout as existing until a
  stack is chosen and this section is updated to match.
- `docs/agent-policy/` contains active cross-cutting engineering policies that
  are too detailed for this always-loaded rule file.
- `.agents/skills/` contains repository-local task procedures that load only
  when relevant.

## Skill And Mode Activation

- Activating a skill or mode (`/skill-name`, `/plan`, etc.) is not a task.
- Do not run tools, including `create_index`, until the user has explicitly stated what they want done.
- If built-in mode instructions conflict with rules in this file, do not resolve the conflict silently. State the conflict and ask which instruction takes priority before proceeding.
- After any Explore agent or sub-agent is rejected, switch immediately to semidx MCP (`create_index` -> `repo_map` -> `resolve_context`). Do not fall back to manual file reads, grep, glob, or shell crawling unless MCP fails or returns an error.

## Project Memory Freshness

- `MEMORY.md` is the lightweight operational memory for current implementation reality, key non-ADR decisions, active assumptions, constraints, known gaps, and near-term priorities.
- Update `MEMORY.md` when runtime behavior materially changes, new invariants are introduced, priorities or known gaps change, or integration assumptions change.
- The versioned pre-push hook runs `scripts/check-memory-freshness.sh` and blocks pushes that change high-signal project files without a `MEMORY.md` update.
- If a high-signal change is intentionally memory-neutral, bypass the hook only after checking the update rule: `SCI_SKIP_MEMORY_FRESHNESS=1 git push`.
- Install versioned hooks with `./scripts/install-git-hooks.sh`; the tracked hook source lives under `scripts/git-hooks/`.

## Agent Policy Documents

- `docs/agent-policy/documentation.md` owns cross-cutting documentation policy,
  canonical document ownership, lifecycle rules, and the Plan Readiness Gate.
- `docs/agent-policy/git.md` owns detailed git workflow policy, including branch
  discipline, concurrent-agent safety, commit boundaries, push rules, and
  recovery rules.
- `docs/agent-policy/testing.md` owns risk-based test and verification policy.
- Before executing a staged implementation plan, apply the Plan Readiness Gate
  from `docs/agent-policy/documentation.md`.
- A hard fail in that gate blocks execution until the plan is corrected.
- If only cosmetic wording or small defensive clarifications remain, stop
  reviewing and execute the plan.
- Give every rule or decision exactly one canonical owner and link to it instead
  of copying normative text across documents, skills, and reports.

## Repository Skills

Use repository-local skills from `.agents/skills/` when their descriptions match
the task:

| Task | Skill |
| --- | --- |
| Execute or prepare a staged implementation plan | `semidx-plan-delivery` |
| Maintain a staged-plan progress log or handoff | `semidx-progress-log` |
| Locate code, callers, tests, or blast radius | `semidx-code-exploration` |
| Design risk-based verification coverage | `semidx-test-design` |
| Review a diff, plan output, or verification coverage | `semidx-code-review` |
| Commit, branch, push, or recover git state | `semidx-git-delivery` |
| Add or reorganize standing agent rules | `semidx-rules-maintenance` |

## MCP-First Workflow

- If the `semidx` MCP server is available, do not begin codebase exploration with directory listing, wildcard search, grep, broad file reads, or shell crawling.
- Use MCP before manual file crawling.
- When implementation work requires reading code before edits, use semidx retrieval first instead of manual file reads.
- First-pass flow is strict:
  1. `create_index`
  2. `repo_map`
  3. `resolve_context`
  4. optional `expand_context`
  5. optional `fetch_context_detail`
- A successful `create_index` is not a reason to switch to filesystem browsing. Continue with `repo_map` and semantic retrieval.
- Use `resolve_context`, `expand_context`, `fetch_context_detail`, and `skeletons` to read code shape and details before patching source files.
- Use manual file reads only as a fallback when semidx MCP fails, when the target is outside indexed source files, or when exact patch-safe line context is still needed after MCP retrieval.
- Do not silently fall back to manual inspection if MCP fails. State that MCP failed, then continue manually if needed.

## MCP Query And Wire Shape

- `initialize.params.clientInfo` must be an object, not a string.
- `tools/call.arguments` must be a JSON object, not a JSON-encoded string.
- `resolve_context` accepts a flat top-level `intent` string, a `query.intent` shorthand, or the full structured `query` object.
- The simplest `resolve_context` shape is `{"index_id": "...", "intent": "your task"}`.
- After a successful `resolve_context`, keep context compact by continuing with `selection_id` and `snapshot_id` for `expand_context` or `fetch_context_detail`.
- Do not expand prompts manually when a selection artifact is available.
- Canonical MCP client prompts, once documented, belong in `docs/`; no such
  document exists yet.

## MCP Failure Protocol

- Treat `no_supported_languages_found` as a user-guidance path: ask for the core language and suggest activating other languages later.
- Treat `language_refresh_required` as a signal to rerun `create_index`.
- Treat `language_activation_in_progress` as a wait-and-retry signal for the same request.
- If MCP returns an error or timeout after two attempts, say `SCI MCP unavailable, switching to manual` and proceed with filesystem tools.

## Preferred Tool Boundaries

- Use semidx MCP for high-level project mapping, code retrieval, dependency context, impact analysis, and staged context expansion.
- Once relevant context is resolved, prefer a structure-aware editing or REPL/eval
  tool for the active implementation language when one is configured for this
  repository; fall back to generic file edits otherwise.
- Use semidx for retrieval only; do not use it as a replacement for a REPL, a formatter, or a file reader.

## Code Reading Rules

Choose the reading tool by the question being answered, not by file type.
semidx and a language-specific reader answer different questions and do not
compete: semidx finds which code matters, a language-specific reader shows a
file that has already been identified.

| Question | Tool |
| --- | --- |
| Which code is relevant? Who calls this? What is the blast radius? | semidx (`resolve_context`, `impact_analysis`) — always first |
| What is the shape of one already-identified file? | A structure-aware reader for the active language (collapsed view), if one is configured |
| Which exact lines am I about to patch? | `Read` with `offset`/`limit` |
| What is the body of one symbol from an existing selection? | semidx `fetch_context_detail` with `selection_id` |

- **A language-specific reader never substitutes for the first semidx call.** If
  it is not yet known which file is needed, that is semidx's job. Opening files
  one after another to get oriented is prohibited, however cheap each
  individual read looks. This is the failure mode semidx exists to prevent.
- Do not route narrow reads through semidx. `fetch_context_detail` wraps the
  code in a full retrieval envelope (stage events, capabilities, guardrails,
  diagnostics), so it is the wrong tool for "show me the lines I am about to
  edit". Use `Read` with `offset`/`limit` there.
- Prefer a language-specific structure-aware reader over a full `Read` when
  orienting inside a single large known file: a collapsed, structure-aware view
  costs less than dumping the whole file and is more reliable than guessing
  line ranges.
- Language-specific MCP tools are commonly path-contained to the repository
  root or a configured directory set. When a target lies outside that set,
  fall back to `Read` plus whatever verification probe applies to that
  language.
- No hook enforces any of this. The `semidx-first` guard matches only `Grep`,
  `Glob`, and `Bash`, and has no visibility into MCP tool calls. These rules
  hold by discipline alone.

## Editing Rules

Choose the editing tool by the risk of the edit, not by file extension. Every
edit carries a required safety step. The safety step is not optional.

| Situation | Tool | Required follow-up |
| --- | --- | --- |
| New file written in full | `Write` or heredoc | Compile/typecheck/lint probe for the language, or a read-back check for non-code files |
| Structural edit to a whole function or definition | A structure-aware editor for the active language, when one is configured | Confirm the returned diff |
| Narrow edit inside a large existing file | `Edit` | Compile/typecheck/lint probe |
| Markdown, scripts, and other non-code files | `Edit` | Normal review |

- **A verification probe after any code edit is mandatory, not advisory.**
  What counts as a probe (compile, typecheck, lint, or a REPL/eval smoke) is
  determined by the implementation language chosen for the affected code; this
  file does not fix one right now.
- Prefer a structure-aware editor whenever one is configured for the active
  language and the unit of change is a whole function or definition — such
  tools typically validate syntax on the way in, so a rewrite cannot land
  unbalanced or malformed.
- Keep patches scoped to one logical unit (function, definition, form) where
  possible, and avoid large rewrites of deeply nested code when a narrower
  edit will work.
- Once an implementation language is chosen, add a language-specific addendum
  here or in `docs/agent-policy/` naming the exact probe command, the
  structure-aware editor, and the REPL/eval workflow for that language.

## Contracts And Runtime Invariants

- The `contracts/schemas/` JSON Schema files, `contracts/examples/` fixtures, and their Clojure `malli` mirrors were removed with the legacy codebase and are pending a from-scratch redesign. Do not describe them as existing until that redesign lands.
- Staged retrieval is the canonical public contract: compact selection first, optional widening, then detail fetch.
- Keep MCP, library, HTTP, and gRPC behavior aligned when changing shared retrieval contracts, error shapes, or usage metrics semantics.
- When changing MCP tool schemas, verify both machine-readable `tools/list` output and runtime handler behavior.

## Testing And Verification

- Verify changes with the narrowest meaningful command first.
- For non-trivial staged plans, use the risk-based matrix in
  `docs/agent-policy/testing.md` to map requirements and invariants to the
  lowest sufficient verification level.
- No implementation language, test runner, or verification script is fixed
  yet. Once a stack is chosen, record the actual commands here (test runner
  invocation, benchmark script, MCP/runtime smoke commands) instead of
  assuming a previous stack's tooling.
- Whatever test runner is chosen, keep tests order-independent — they must not
  rely on run order or shared mutable state between test units.
- If a verification command cannot be run, report that clearly.

## Services And Local Infrastructure

- No local service dependency (database or otherwise) is fixed yet. When one
  is chosen, record it here along with how tests should detect and reuse a
  running instance instead of restarting it needlessly.
- Before running integration tests that depend on a local service, check
  whether an instance is already running.
- If a local service must be restarted for a test, stop the existing instance
  cleanly, start a fresh instance with the required test configuration, and
  run tests only after the clean restart.
- Do not commit secrets, tokens, private credentials, or environment files.

## Git Workflow

- Follow the detailed Git Workflow Policy in `docs/agent-policy/git.md`.
- Never run dependent git commands in parallel.
- `git commit` and `git push` must always run sequentially.
- Use parallel tool execution only for independent reads or checks, never for
  state-changing commands that depend on each other.
- Stay on the current branch by default. Do not create, switch, delete, merge,
  reset, rewrite, or push branches unless the user explicitly asks for that git
  operation.
- Use versioned git hook sources under `scripts/git-hooks/`; install them into `.git/hooks` with `./scripts/install-git-hooks.sh`.
- The versioned hooks include `pre-commit`, `commit-msg`, and `pre-push`; keep
  `scripts/check-agent-attribution.sh` wired into all three.
- If uncommitted files remain in the repo from previous agent runs, explicitly surface them and offer to commit and push them separately.
- Commit changes every time code or documentation is touched (for example, automatically after completing each implementation stage of a project).
- Group related changes into coherent commits during an implementation stage, but always ensure the stage ends with a commit.
- Before risky or multi-file changes, surface the dirty working tree and ask whether to checkpoint it first.
- Do not revert existing user changes unless explicitly requested.

## Documentation Rules

- Keep repository documentation, project rule files, and agent instruction files in English.
- Agents may answer the user in Russian by default when the user writes in Russian, but committed documentation remains English.
- Keep root entrypoint docs limited to stable project onboarding and repo-wide controls.
- Keep detailed cross-cutting engineering policies under `docs/agent-policy/`
  and link to them from this file.
- New or renamed non-system working documents under `bugs/`, `ideas/`, `plans/`, `reports/`, `adr/`, `docs/adr/`, `docs/design/`, `docs/ideas/`, and `docs/plans/` must use a chronological filename prefix scoped to that directory: `NNN_slug.md`.
- New or renamed non-system working documents under `notes/` must use a date prefix: `YYYY-MM-DD_slug.md`.
- Number sequences restart per numbered-document directory. Choose the next number by scanning the target directory for the highest existing numeric prefix, then incrementing it.
- Do not reuse numbers and do not renumber existing prefixed documents casually.
- These filename rules apply prospectively from the commit that introduces them.
- If an unnumbered or differently prefixed working document is discovered later, treat it as legacy until a dedicated documentation migration renames it.
- Do not opportunistically rename historical or legacy documents as part of unrelated feature work.
- A documentation migration that renames legacy documents must update all Markdown links, `superseded_by` references, README indexes, and progress-log references in the same commit.
- Non-system working documents under `bugs/`, `ideas/`, `notes/`, `plans/`, `reports/`, `adr/`, `docs/adr/`, `docs/agent-policy/`, `docs/design/`, `docs/ideas/`, and `docs/plans/` must use YAML frontmatter when they are newly created, renamed, or materially revised.
- System, index, source-intake, generated, and sample files do not require frontmatter or numbered working-document filenames. Examples include root `README.md`, directory index files such as `plans/README.md` or `docs/README.md`, `RULES.md`, `AGENTS.md`, `CLAUDE.md`, `intake/*`, and sample `README.md` files.
- Preferred frontmatter fields are `title`, `doc_type`, `lifecycle`, `status`, `agent_action`, and `updated`.
- Use `agent_action` to make stale or completed documents unambiguous to future agents. Executed plans and progress logs must be marked as historical, not as active work queues.
- When searching project documentation for implementation context, treat documents with `lifecycle: "active"` or `lifecycle: "accepted"` and `agent_action: "reference_for_context"` as current sources.
- Treat documents with `lifecycle: "completed"`, `lifecycle: "archived"`, or `lifecycle: "superseded"` as historical records unless their `agent_action` explicitly says otherwise.
- Do not use historical documents for implementation decisions unless the user explicitly asks for historical context.
- If current and historical documents conflict, follow the current document. If multiple current documents conflict, ask for clarification before changing project behavior.
- Common `lifecycle` values are `active`, `concept`, `accepted`, `completed`, `superseded`, and `archived`.
- Common `agent_action` values are `reference_for_context`, `use_as_input_for_future_plan_only`, `historical_reference_only`, `do_not_implement_again`, and `do_not_use_for_current_work`.
- Keep `status` values consistent with document type:
  - ADR: `proposed`, `accepted`, `rejected`, `deprecated`, `superseded`.
  - Plan: `draft`, `planned`, `in_progress`, `blocked`, `completed`, `cancelled`.
  - Progress log: `in_progress`, `blocked`, `completed`.
  - Review or assessment: `draft`, `final`, `snapshot_complete`.
  - Bug or follow-up report: `open`, `fixed`, `wont_fix`, `completed`.
  - Handoff: `ready`, `consumed`, `superseded`.
  - Idea or source-intake document: `draft`, `proposed`, `source_intake`, `historical`.
- `lifecycle` describes whether a document is current; `status` describes the
  workflow state appropriate to its document type. Do not use synonyms such as
  `done`, `delivered`, or `implemented` in new or materially revised frontmatter.
- When a document changes lifecycle state, update its frontmatter in the same commit.

## Plan Execution Progress Logs

- When executing a documented plan, create or update a companion progress log before or during the first implementation stage.
- Store progress logs under root `reports/` unless the plan explicitly names another location.
- Progress logs should use the standard documentation frontmatter described in this file.
- If a plan is split into stages, update the progress log as each stage is completed.
- Record stage status, meaningful summary of what changed, changed files or commit hash when available, verification commands and results, known blockers, skipped checks, and environment limitations.
- Record review findings in the same progress log, including whether each finding was accepted, rejected, deferred, or fixed.
- When fixing findings, record the fix summary, changed files or commit hash, and verification results.
- Do not leave progress logs as stale checklists. If historical entries are backfilled, label them as historical notes instead of pretending they were updated live.
- Keep progress-log updates in the same commit as the stage implementation when practical.

## Review Response Format

- When asked to review code, lead with findings ordered by severity.
- Each finding should include severity, issue title, why it matters, evidence with a file/line link, and the smallest reasonable suggested fix.
- After findings, include open questions or assumptions only when they affect correctness.
- Include verification commands run and whether they passed, failed, or were skipped.
- If no issues are found, say that clearly and mention meaningful test coverage gaps or verification limits.
