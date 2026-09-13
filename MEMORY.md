# Project Memory

Current implementation reality: what exists in this repository right now and
why. This is not a changelog of what was removed — see `git log` for history.

## What exists and why

- `ARCHITECTURE_CONSTITUTION.md` — the WHY/WHAT layer (purpose, semantic
  layers, invariants, non-goals). Exists so a future implementation has a
  fixed target to conform to, decided before any code exists. It holds only
  what must not change; it is versioned (currently version 2) with an
  amendment log in §19, and is amended by standalone commits under §18 rather
  than edited alongside the change it permits.
- `RULES.md` — the single source of truth for agent process rules. Written
  language-agnostic on purpose: no implementation stack is chosen yet, so it
  states process (git workflow, doc lifecycle, tool-usage discipline)
  without assuming Clojure or any other language.
- `docs/agent-policy/{documentation,git,testing}.md` — the detailed policies
  `RULES.md` is too short to hold directly: doc lifecycle and the Plan
  Readiness Gate, git workflow specifics, risk-based test-level selection.
- `.agents/skills/` — repository-local task procedures (plan delivery,
  progress logs, code exploration, test design, code review, git delivery,
  rules maintenance), loaded only when their task matches.
- `README.md` — minimal human entry point: what semidx is, in one paragraph
  pointing at the constitution, plus the license. Deliberately not a status
  page or getting-started guide, since there is nothing to run yet.
- `scripts/` git-hygiene files (`check-agent-attribution.sh`,
  `check-memory-freshness.sh`, `install-git-hooks.sh`, `git-hooks/*`) —
  enforce process rules that hold regardless of implementation language: no
  AI attribution, this file staying current.
- `scripts/` toolchain installers (`setup-jdtls.sh`, `setup-scip-java.sh`,
  `setup-scip-typescript.sh`, `setup-tree-sitter-grammars.sh`,
  `setup-typescript-lsp.sh`, and their pinned `package.json` /
  `ScipJavaIndexer.java`) — install pinned external tools (Java LSP, SCIP
  indexers, tree-sitter grammars) that back the Language Frontends direction
  in `ARCHITECTURE_CONSTITUTION.md` §10. They install sources semidx will
  read, not semidx's own implementation, so they hold regardless of which
  language semidx itself ends up written in.
- `.github/workflows/agent-attribution.yml` — CI enforcement of the same
  no-attribution rule, independent of implementation language.

## What does not exist yet, and why that is expected

- No implementation (`src/`, `test/`, a build/dependency manifest): this is a
  from-scratch rebuild and no language or build tool is chosen yet.
- No `contracts/` layer (JSON Schema, examples, runtime mirrors): the public
  interface shape depends on the implementation stack. Do not add contracts
  speculatively before that decision.
- No `SPEC.md`. The constitution now declares it as the companion layer that
  owns concrete, drifting requirements (budgets, language coverage, fact
  schema, snapshot contract, frontend protocol, public surfaces, conformance),
  but the document itself has not been written yet. Until it exists, those
  concerns have no canonical owner — do not scatter them into plans or here.

## Active Constraints And Blockers

- `ARCHITECTURE_CONSTITUTION.md` §17 records two open constitutional questions.
  Per §15 question 9, work depending on either is blocked until the question is
  resolved by amendment, and neither may be settled implicitly by the first
  implementation that needs an answer:
  - **OQ-1** — how far the semantic model is unified across languages (one
    shared vocabulary vs per-language schemas with a shared query layer).
    Blocks the fact schema.
  - **OQ-2** — deployment shape (local-first with no required external service
    vs a shared service being a supported mode). Blocks the storage and process
    model, and therefore constrains the stack decision below.

## Near-Term Priorities

- Resolve OQ-2, then decide the implementation stack (language,
  build/dependency tool, source layout), then fill in `RULES.md`'s Project
  Context, Repository Shape, Editing Rules, Testing And Verification, and
  Services And Local Infrastructure sections with the real specifics.
- Resolve OQ-1, then write `SPEC.md` and design the contracts/schema layer.
- `scripts/check-memory-freshness.sh` does not list
  `ARCHITECTURE_CONSTITUTION.md` among its trigger files, so amending the
  highest-signal document in the repository does not by itself require a
  memory update. Known gap in the guard, not an intentional exemption.
