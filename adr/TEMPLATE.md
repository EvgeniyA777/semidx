---
file_type: adr
decision_id: ADR-XXX
title: Short Decision Title
status: proposed
date: YYYY-MM-DD
deciders:
  - project owner
tags:
  - architecture
summary: One-sentence summary of the decision and its scope.
agent_summary: Read this ADR to understand the current decision of record for this topic. Treat the Decision and Status sections as normative, and read Consequences for required tradeoffs and downstream obligations.
supersedes: []
superseded_by: null
links: []
---

# ADR-XXX: Short Decision Title

**Status**: Proposed  
**Date**: YYYY-MM-DD  
**Deciders**: project owner

---

## Context

State the problem and the surrounding constraints.

Keep this section factual.

Answer questions like:

- what changed or became painful
- what forces or limits shaped the choice
- what decision now needs to be made

If there is a relevant earlier ADR, design doc, benchmark, or incident, reference it here.

## Decision Drivers

List the factors that matter most for choosing an option.

Examples:

- API stability
- operational simplicity
- retrieval precision
- performance under bounded token budgets
- migration cost
- safety or governance constraints

## Considered Options

### Option 1. Name of option

Short neutral description.

### Option 2. Name of option

Short neutral description.

### Option 3. Name of option

Short neutral description.

Include only real options that were considered.

## Decision

State the chosen option directly and unambiguously.

Recommended pattern:

`We accept Option N: <name>.`

Then explain:

- why it was chosen
- why the other options lost
- what the system must do differently after this decision

## Consequences

### Positive

- Describe the main benefits.
- Keep them concrete.

### Negative

- Describe the real costs.
- Include complexity, migration burden, risk, lock-in, or operational burden.

### Follow-Up

- List required downstream work, if any.
- If there is no follow-up, say so explicitly.

## Status Changes

Use this section only when relevant.

Examples:

- `Supersedes ADR-018`
- `Superseded by ADR-031`
- `Deprecated after runtime edge consolidation`

## References

Link supporting material when useful:

- issue or task
- PR
- benchmark or report
- design doc
- older ADRs

## Definition Of Done

Describe the repository-level condition that would make this decision fully implemented or fully enforced.
