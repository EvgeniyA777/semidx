---
title: "Markdown Document Intelligence"
doc_type: "architecture_idea"
lifecycle: "concept"
status: "proposed"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-08-01"
---

# Markdown Document Intelligence

## Problem

semidx indexes source and template languages but does not currently model
Markdown project documentation. In a typical project, specifications, design
documents, implementation plans, progress logs, and current-status documents
are part of the operating system for the codebase. Treating them as ordinary
text chunks would introduce stale-plan noise, contradictory historical state,
and irrelevant context into code-oriented retrieval.

## Proposal

Add Markdown through a dedicated document provider rather than as a generic
text-language lane.

The provider should:

1. Split documents by headings while preserving heading paths and source-line
   spans.
2. Parse YAML frontmatter, including `lifecycle`, `status`, `agent_action`, and
   `updated`.
3. Rank current or active documents above completed, archived, and superseded
   material by default.
4. Expose document sections as distinct retrieval units that can participate in
   relationships with specifications, code, plans, and reports.
5. Retain deterministic tools for exact values, broken links, document status,
   and test-count assertions.

## Value

The goal is not to replace exact search. It is to make semantic retrieval aware
of project intent and document freshness, enabling queries such as:

- Which current documents define a feature or requirement?
- Which design, plan, and status artifacts govern a proposed code change?
- Does a change affect a specification, architecture decision, or active plan?

This would also make it possible to detect semantic disagreement between
current project documents while keeping exact validation deterministic.

## Architectural Constraint

Markdown must enter through the provider catalog and emit the same typed
relation facts as other providers. It must not be introduced through a special
case in the language adapters or by indiscriminately indexing all textual
files.
