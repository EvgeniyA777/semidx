# Project Memory

Current implementation reality: what exists in this repository right now and
why. This is not a changelog of what was removed — see `git log` for history.

## What exists and why

- `ARCHITECTURE_CONSTITUTION.md` — the WHY/WHAT layer (purpose, semantic
  layers, invariants, non-goals). Exists so a future implementation has a
  fixed target to conform to, decided before any code exists. It holds only
  what must not change. It has exactly two states: DRAFT (now) and RATIFIED.
  **It is currently a draft and is being finished; once ratified it never
  changes at all** — no amendments, no versions, no log. A constraint that
  turns out to be wrong is not a document error to correct but a discovery
  that a different product needs to exist, and the mechanism for that is a
  fork of the repository (§18). Ratification requires §17 to be empty, so
  closing OQ-1 and OQ-2 is what unblocks it. Its Normative Language section
  makes `must`/`may` RFC 2119 keywords, declares `should` unused, and bans
  discretionary qualifiers from normative statements. Its Defined Terms
  section holds exactly five terms — entity, node, relationship, assertion,
  fact — because each states a distinction an invariant turns on; in
  particular **assertion** (anything the graph records) is not a synonym for
  **fact** (a resolved, frontend-confirmed assertion). Everything else is in
  `GLOSSARY.md`. Its thirteen invariants each carry Statement, Rationale,
  Implications, and Detection. The Detection entries are the intended
  conformance checks and mostly presuppose an implementation; derive the real
  checks from them rather than inventing checks to match whatever gets built.
  Invariants 10 and 12 are detectable today, being process properties.
- Enforcement of the §18 freeze is deliberately deferred: the script that
  blocks changes to a ratified constitution is to be written **after**
  ratification, not before. Until then §18 holds by discipline. Do not add it
  early.
- Known inconsistency, to be cleared when that script is written:
  `scripts/check-constitution-amendment.sh` still exists and is wired into
  `pre-commit`. What it does is useful and still true — it stops a
  constitution change from being bundled with unrelated files — but its name
  and its message describe a §18 "amendment procedure" that the constitution
  no longer has. Leave it working; fix the wording as part of the post-freeze
  script work.
- `GLOSSARY.md` — the project vocabulary, explicitly descriptive rather than
  normative: no version, no amendment procedure, expected to drift. It exists
  so the constitution can keep only the five terms whose distinctions are
  themselves constraints (entity, node, relationship, assertion, fact) and
  hand the rest somewhere with a real owner. It must not restate those five.
  Schema-level vocabulary (field names, resolution-level values, the
  catalogue of entity and relationship kinds) moves to `SPEC.md` when that
  document exists; conceptual vocabulary stays in `GLOSSARY.md`.
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
  `check-memory-freshness.sh`, `check-constitution-amendment.sh`,
  `install-git-hooks.sh`, `git-hooks/*`) — enforce process rules that hold
  regardless of implementation language: no AI attribution, this file staying
  current, and constitutional amendments staying standalone. The freshness
  trigger list includes `ARCHITECTURE_CONSTITUTION.md` and `SPEC.md`, so a
  change to either requires a memory update in the same pushed range. The
  pre-commit amendment check blocks any commit touching
  `ARCHITECTURE_CONSTITUTION.md` alongside a file other than `MEMORY.md`;
  that pairing is allowed precisely because the freshness guard demands it.
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
