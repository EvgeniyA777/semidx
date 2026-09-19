---
title: "Documentation Policy"
doc_type: "policy"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# Documentation Policy

## Canonical Ownership

- `RULES.md` owns repository-wide agent rules and is the source of truth for
  always-loaded instructions.
- `docs/agent-policy/` owns cross-cutting engineering policies that are too
  detailed for the always-loaded rule kernel.
- `MEMORY.md` owns current implementation reality, active assumptions, known
  gaps, and near-term priorities.
- `MEMORY.md` is a bounded operational index, not an append-only history. Prefer
  200-300 lines and keep it below 350 lines unless an active transition needs a
  temporary exception. Update it by replacing or compressing stale detail into
  links to ADRs, plans, reports, follow-ups, specs, or implementation files.
- `ARCHITECTURE_CONSTITUTION.md` owns architectural constraints that must not
  change, including the five terms whose distinctions are themselves
  constraints (entity, node, relationship, assertion, fact).
- `ARCHITECTURE_RATIONALE.md` owns explanatory design reasoning behind the
  constitutional constraints. It is not independently normative.
- `CONFORMANCE.md` owns reviewable and executable scenario families used to
  verify constitutional properties. It is strict when adopted by requirements,
  but its check mechanics are not immutable constitutional text.
- `GLOSSARY.md` owns the rest of the project vocabulary. It is descriptive, not
  normative, and must not restate the constitution's Defined Terms.
- When a plan, ADR, report, specification, or policy introduces durable project
  vocabulary outside the constitution's Defined Terms and outside CORE/SPEC-owned
  kind, schema, or contract definitions, update `GLOSSARY.md` in the same change
  or explicitly record which document owns the term.
- `SPEC.md` is the companion requirements document named by role in the
  constitution. It owns changing requirements, the language-extension catalogue,
  schema vocabulary, and semantic-contract publication and migration procedures.
  It may link to subordinate specifications as those areas grow.
- `CORE.md` owns the core roster named by role in the constitution. It owns
  candidate and accepted kind definitions and admission evidence. Its authority
  is derived from the constitution's shared-core boundary; its lifecycle follows
  `SPEC.md`. It cannot redefine architectural terms.
- ADRs own durable technical decisions.
- Plans own future staged execution.
- Reports own historical progress, evidence, and handoff records.
- Follow-up reports own accepted deferred findings that are not yet plans.
- Runtime behavior belongs in source and tests; documentation must not override
  committed implementation contracts silently.
- Give each rule or decision one canonical owner and link to it instead of
  copying the same normative text across multiple documents.

## Filenames

- New or renamed non-system working documents under `bugs/`, `ideas/`, `plans/`,
  `reports/`, `adr/`, `docs/adr/`, `docs/design/`, `docs/followups/`,
  `docs/ideas/`, and `docs/plans/` use a chronological prefix scoped to that
  directory: `NNN_slug.md`. Documents under `notes/` use a date prefix:
  `YYYY-MM-DD_slug.md`.
- Number sequences restart per directory. Choose the next number by scanning the
  target directory for the highest existing numeric prefix, then incrementing it.
- Do not reuse numbers and do not renumber existing prefixed documents casually.
- These filename rules apply prospectively from the commit that introduced them.
  An unnumbered or differently prefixed document found later is legacy until a
  dedicated documentation migration renames it. Do not opportunistically rename
  historical documents as part of unrelated feature work.
- A migration that renames legacy documents must update all Markdown links,
  `superseded_by` references, README indexes, and progress-log references in the
  same commit.

## README Stewardship

The root `README.md` is the public project presentation and routing entry point.
It should help search engines classify the project, help AI agents find the
right next document or MCP workflow, and help humans understand why the project
matters.

Do not use the README as a progress log, release gate, staged-plan checklist,
proof-command archive, or implementation evidence store. Update it only when
public positioning, quick start behavior, current preview status, user-facing
MCP setup, or canonical documentation routing changes.

Proof workflows, release-gate commands, stage evidence, and plan-specific
checklists belong in their owning reference, plan, report, release, or policy
document. The README may link to that owner, but must not accumulate a local
copy of the evidence.

`scripts/check-readme-stewardship.sh` guards the obvious drift markers for this
rule in the root README. It is a backstop, not a substitute for judgment.

Before editing the README, identify which presentation plane the change improves:
search classification, AI-agent onboarding, or human project comprehension. If a
change improves none of those, put it in the owning document instead.

## Frontmatter

- Non-system working documents under `bugs/`, `ideas/`, `notes/`, `plans/`,
  `reports/`, `adr/`, `docs/adr/`, `docs/agent-policy/`, `docs/design/`,
  `docs/followups/`, `docs/ideas/`, and `docs/plans/` carry YAML frontmatter
  when they are newly created, renamed, or materially revised.
- The root canonical documents carry the same frontmatter: `SPEC.md`, `CORE.md`,
  `CONFORMANCE.md`, `ARCHITECTURE_RATIONALE.md`, and `GLOSSARY.md`.
- `ARCHITECTURE_CONSTITUTION.md` is exempt and stays exempt. It is frozen and
  declares its state on its own status line; frontmatter must never restate it,
  because a second place to read the state is a second place for it to be wrong.
- System, index, source-intake, generated, and sample files need no frontmatter
  and no numbered filename: root `README.md`, directory index files such as
  `plans/README.md`, `RULES.md`, `AGENTS.md`, `CLAUDE.md`, `MEMORY.md`,
  `intake/*`, and sample `README.md` files.
- The fields are `title`, `doc_type`, `lifecycle`, `status`, `agent_action`, and
  `updated`.
- Keep `status` consistent with document type:
  - ADR: `proposed`, `accepted`, `rejected`, `deprecated`, `superseded`.
  - Plan: `draft`, `planned`, `in_progress`, `blocked`, `completed`, `cancelled`.
  - Progress log: `in_progress`, `blocked`, `completed`.
  - Review or assessment: `draft`, `final`, `snapshot_complete`.
  - Bug or follow-up report: `open`, `fixed`, `wont_fix`, `completed`.
  - Handoff: `ready`, `consumed`, `superseded`.
  - Idea or source-intake document: `draft`, `proposed`, `source_intake`,
    `historical`.
  - Specification, rationale, or reference: `draft` while the document is still
    being written, `active` once it is current and stable, `superseded` when
    another document replaces it.
  - Policy: `active` or `superseded`.
- `draft` describes the document, not the thing it describes. A specification is
  `active` when its own text is settled, even when the work it specifies has not
  started and no evidence exists yet.
- `lifecycle` describes whether a document is current; `status` describes the
  workflow state appropriate to its type. Do not use synonyms such as `done`,
  `delivered`, or `implemented`.
- Use `agent_action` to make stale or completed documents unambiguous to future
  agents. Executed plans and progress logs are marked historical, never left
  looking like active work queues.

## Architectural Decision Records

- The ADR procedure is active. The sequence starts at `001`, and
  [docs/adr/README.md](../adr/README.md) is its index.
- Records removed before the procedure was enabled do not reserve numbers, which
  is why `001` is free. From the first ADR written under this procedure the
  no-reuse rule applies strictly: a number is never reassigned, and a superseded
  record stays in place with its frontmatter updated rather than being deleted.
- Do not write an ADR about the drafting of the architecture documents
  themselves. That reasoning belongs in `ARCHITECTURE_RATIONALE.md`, and the
  drafting history belongs in `git log`.
- Record answers to every question in constitution section 11 in an ADR under
  `docs/adr/NNN_slug.md`, using the Filenames and Frontmatter rules above.
- Each record identifies the feature or dependency, applicable constitutional
  clauses, decision, rationale, consequences, and verification evidence or
  planned conformance checks. Use an explicit rationale for any question marked
  not applicable.
- Link the ADR from the change's PR or merge description, or from its commit
  message when there is no PR. A reviewer must be able to locate the answers
  from the merged change.
- A narrowly scoped implementation of an existing accepted decision may refer
  to that ADR when its answers still cover the change. A new major feature,
  dependency, or changed architectural answer requires a new or revised record.
- Follow the constitution's open-question and ratification rules for
  constitutional questions. An ADR records reasoning; it cannot reinterpret or
  override the constitution.

## Plan Readiness Gate

A staged implementation plan is ready when a fresh agent can execute it to an
accepted result without guessing product behavior, architectural intent, work
order, verification scope, or stop conditions.

Validate a plan against this gate before executing it. If a hard fail exists,
fix the plan first. If only cosmetic wording or small defensive clarifications
remain, move to execution instead of continuing review loops.

Hard fail conditions:

- Product or runtime behavior is unclear or conflicts with `RULES.md`,
  `MEMORY.md`, ADRs, current plans, contracts, fixtures, or implementation
  behavior.
- Scope boundaries are missing, vague, or allow unrelated refactoring or
  features.
- A key technical decision is implicit, unjustified, or depends on external
  approval without a documented stop and resume rule.
- Branches such as provider, profile, migration, policy, or execution variants
  are mentioned but not carried through stages, files, verification, and DoD.
- Stages depend on outcomes from later stages or lack concrete output
  artifacts.
- DoD cannot be verified through files, commands, tests, API behavior, contract
  examples, fixtures, docs, or committed artifacts.
- The test strategy does not cover the main behavioral, integration, security,
  provider-authority, freshness, or regression risks.
- Runtime constraints are ignored, including profiles, env vars, external
  services, local toolchains, generated artifacts, CI/offline behavior,
  persistence, or startup mode.
- Documentation targets contradict each other or contain stale bookkeeping that
  changes execution meaning.
- The plan requires guessing to decide what to implement, what to skip, what to
  test, or when to stop.

Ready criteria:

- Contract changes are explicit and tied to source-of-truth documents.
- Scope and non-scope are explicit.
- Key decisions and rationale are recorded.
- Drift control has checked the relevant source-of-truth documents for plan
  readiness and has an explicit closure check for keeping them aligned.
- Blockers and decision branches have precise stop and resume behavior.
- Each stage has a clear purpose, ordered dependencies, and concrete outputs.
- Verification commands and acceptance checks are named.
- DoD is observable and falsifiable.
- Risk-based tests are mapped to the behavior they prove.
- Runtime and environment traps have been considered.
- The document is internally consistent and not overloaded with irrelevant
  implementation detail.

## Drift Control

Use drift control when preparing, executing, or closing a staged plan; writing an
ADR; preparing a release handoff; or changing a source-of-truth document named by
`RULES.md`. Compare the proposed or completed work against the current owners:
the constitution, ADRs, `SPEC.md`, `CORE.md`, `CONFORMANCE.md`, `MEMORY.md`,
capability matrices, follow-ups, `GLOSSARY.md`, and the implementation where it
is the runtime authority.

The check is directional: no consumer or tool shape defines graph semantics; no
unresolved, approximate, stale, unsupported, or unavailable claim is presented as
a fact; no core kind, semantic contract, persistence, remote operation, language
coverage, release claim, or durable vocabulary appears without its owner being
updated or explicitly named.

For plan readiness and plan closure, record either that the relevant owners are
already aligned or the exact documents updated, deferred, or left as residual
risk. If this becomes a frequent standalone audit, promote the workflow into a
repo-local skill instead of growing this policy section.

## Language And Links

- Write repository documentation, code comments, agent instructions, and
  `AGENTS.md` files in English.
- Use repository-relative links inside committed documentation. Do not commit
  machine-specific absolute paths or `file://` links.
- Keep prose concise. Put behavior in source/tests, operational rules in
  `RULES.md` or `docs/agent-policy`, active state in `MEMORY.md`, and durable
  decision rationale in ADRs.

## Lifecycle

- Common `lifecycle` values are `active`, `concept`, `accepted`, `completed`,
  `superseded`, and `archived`. Common `agent_action` values are
  `reference_for_context`, `use_as_input_for_future_plan_only`,
  `historical_reference_only`, `do_not_implement_again`, and
  `do_not_use_for_current_work`.
- When searching documentation for implementation context, treat `active` or
  `accepted` documents whose `agent_action` is `reference_for_context` as current
  sources.
- Treat `completed`, `archived`, and `superseded` documents as historical unless
  their `agent_action` explicitly says otherwise. Do not use a historical
  document for an implementation decision unless the user asks for historical
  context.
- If a current and a historical document conflict, follow the current one. If two
  current documents conflict, ask for clarification before changing project
  behavior.
- When a document changes lifecycle state, update its frontmatter in the same
  commit. Mark executed plans and reports as historical in the commit that
  completes or supersedes them.
- Preserve useful evidence; do not leave completed checklists looking like
  pending work.

## Progress Logs

- When executing a documented plan, create or update a companion progress log
  before or during the first implementation stage. Store it under root
  `reports/` unless the plan names another location, with the standard
  frontmatter.
- If a plan is split into stages, update the log as each stage completes, and
  keep the update in the same commit as the stage implementation when practical.
- Record stage status, a meaningful summary of what changed, changed files or
  commit hash when available, verification commands and results, known blockers,
  skipped checks, and environment limitations.
- Record review findings in the same log, including whether each was accepted,
  rejected, deferred, or fixed. When fixing one, record the fix summary, changed
  files or commit hash, and verification results.
- Do not leave progress logs as stale checklists. Label backfilled entries as
  historical notes instead of pretending they were updated live.

## Follow-up Reports

- Store accepted deferred findings under `docs/followups/`; keep
  `docs/followups/README.md` as the index.
- Use follow-up reports for concrete future-plan inputs discovered during
  implementation or review: defects, coverage gaps, semantic limitations,
  upstream limitations, and process defects. Do not use them as a general
  wishlist.
- A follow-up report is not a staged implementation plan and does not authorize
  work by itself. Promote it into a plan, ADR, or direct implementation task
  before changing behavior.
- Each follow-up report records classification, source, current behavior,
  deferral reason, acceptance direction, required tests, and links back to the
  plan or report where it was found.
- When a follow-up is resolved, update its status to `fixed`, `wont_fix`, or
  `completed` and link the resolving plan, ADR, report, or commit.
