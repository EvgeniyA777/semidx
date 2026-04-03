---
file_type: guide
topic: architecture-decision-records
status: active
language: en
agent_summary: Read this file before creating or editing any ADR in this directory. Use TEMPLATE.md for new ADRs. Treat the rules here as the canonical ADR policy for this repository from this point forward.
---

# ADR Guide

This directory is the canonical decision log for architecture-significant choices in this repository.

From this point forward, ADRs in this directory should follow the rules in this file even if older ADRs use a different style.

## What Belongs Here

Create an ADR when you are recording a durable architecture or design decision such as:

- a public API boundary
- a persistence strategy
- a retrieval or ranking policy
- a protocol or wire contract
- a parser or runtime integration boundary
- a safety or governance rule that changes how the system may evolve

Do not use an ADR for:

- progress updates
- implementation notes
- bug reports
- exploratory notes
- task breakdowns
- meeting minutes

Those belong in other documentation.

## Canonical Rules

### 1. One ADR, one decision

An ADR should record a single decision.

If a document is trying to decide several unrelated things at once, split it.

This rule also applies to bundled implementation requests.

If an agent or engineer is asked to handle one task that actually contains multiple distinct problems, the ADR work must still be split by decision boundary.

Examples:

- 3 separate architectural problems -> 3 separate ADRs
- 5 separate design decisions -> 5 separate ADRs
- 1 broad initiative with 4 independent decision points -> 4 separate ADRs

Do not write one umbrella ADR just because the work arrived as one ticket, one prompt, or one planning session.

The unit of ADR documentation is the decision, not the task container.

### 2. Write the decision, not the whole project history

Keep the ADR focused on:

- the problem
- the constraints
- the options considered
- the decision
- the consequences

If a long design exploration is needed, write a separate design doc and link it from the ADR.

### 3. Capture why, not only what

An ADR is valuable because it explains why a decision was taken and what tradeoffs were accepted.

A reader should be able to answer:

- what problem were we solving
- what options were considered
- why this option won
- what costs or constraints come with it

### 4. Keep ADRs immutable once accepted

Do not silently rewrite decision history.

If the decision changes:

1. create a new ADR
2. mark the old ADR as `superseded`
3. link the old and new ADRs to each other

Minor typo fixes are fine. Decision rewrites are not.

### 5. Record negative consequences explicitly

Every ADR should state not only the benefits but also the costs, limitations, and operational burdens introduced by the decision.

### 6. Keep ADRs short and durable

Aim for a compact, high-signal document. In most cases, one to three pages is enough.

If the ADR becomes a full technical specification, split the detailed design into another document and keep the ADR as the decision summary.

### 7. Write in English

New ADRs should be written in English for consistency and easier cross-team and agent consumption.

### 8. Link ADRs to real artifacts

When available, link the ADR to:

- issue or ticket
- PR
- benchmark
- design doc
- relevant earlier or superseded ADRs

This keeps the decision traceable.

## Required Structure

Every new ADR should be created from [TEMPLATE.md](/Users/ae/workspaces/semidx/adr/TEMPLATE.md).

At minimum, keep these sections:

- `Context`
- `Decision Drivers`
- `Considered Options`
- `Decision`
- `Consequences`

Optional sections are allowed when useful, but do not remove the core ones.

## Frontmatter Policy

Each ADR should start with YAML frontmatter.

Purpose:

- provide lightweight metadata
- give agents a concise summary before they read the full document
- make status, links, and supersession easier to inspect mechanically

The most important frontmatter fields are:

- `decision_id`
- `title`
- `status`
- `date`
- `summary`
- `agent_summary`
- `supersedes`
- `superseded_by`

## File Naming

Use zero-padded numeric prefixes and kebab-case titles:

`NNN-short-kebab-case-title.md`

Examples:

- `031-tighten-retrieval-authority-resolution.md`
- `032-exclude-vendored-grammars-from-default-lexical-seeding.md`

Do not rename historical ADR files unless there is a compelling migration reason.

## Status Values

Use one of these statuses:

- `proposed`
- `accepted`
- `rejected`
- `deprecated`
- `superseded`

Suggested meaning:

- `proposed`: under review, not yet the repository rule
- `accepted`: current decision of record
- `rejected`: considered and explicitly not chosen
- `deprecated`: still historically relevant, but no longer preferred
- `superseded`: replaced by a later ADR

## Recommended Authoring Flow

1. Copy [TEMPLATE.md](/Users/ae/workspaces/semidx/adr/TEMPLATE.md) to a new numbered filename.
2. Fill in frontmatter first.
3. Write the `Decision` section in one clear paragraph before expanding the rest.
4. Fill `Context`, `Decision Drivers`, and `Considered Options`.
5. Add both positive and negative consequences.
6. Add links to issues, PRs, benchmarks, and superseded ADRs.
7. If the ADR replaces another one, update both documents.

## Review Checklist

Before merging a new ADR, verify:

- the ADR records one decision only
- the decision is explicit and unambiguous
- at least one alternative was considered
- negative consequences are documented
- status is correct
- links and supersession fields are correct
- the filename uses the next available number
- the frontmatter summary and agent summary are accurate

## Interpretation Guidance For Agents

When an agent reads an ADR in this directory:

- treat `Decision` and `Status` as the normative source
- treat `Context` as the problem framing
- treat `Consequences` as binding tradeoffs and follow-up burdens
- treat `agent_summary` as the quick-read entry point, not as a substitute for the document
- if an ADR is `superseded`, prefer the newer ADR
