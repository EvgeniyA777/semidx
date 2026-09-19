---
title: "Document and config graph frontend"
doc_type: "idea"
lifecycle: "active"
status: "proposed"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-18"
---

# Document And Config Graph Frontend

## Thought

Markdown, YAML, and JSON may be valuable semidx inputs when they contribute
exact document or configuration structure to the graph, not retrieval chunks.

The useful direction is a document/config graph, not document retrieval.

## Useful Direction

A future frontend could extract exact claims such as:

- Markdown document sections and anchors;
- YAML frontmatter fields;
- Markdown links and unresolved link targets;
- JSON and YAML object paths;
- schema references where a schema is known;
- lifecycle and status relationships between plans, reports, follow-ups,
  releases, roadmap documents, and policy documents;
- config references to scripts, source files, tools, or local commands when the
  format gives exact evidence.

This could make project memory queryable through the graph. For example, an
agent asking for the next project stage could navigate from the roadmap to open
follow-ups, completed plans, release notes, and progress logs without relying
on broad Markdown search.

## Boundary

The graph must not create arbitrary paragraph, text-window, or embedding-chunk
nodes. Prose interpretation, similarity, inferred dependencies, and LLM guesses
may support search, ranking, or projections, but they must not become graph
facts.

Document/config extraction is compatible with semidx only when nodes are
semantic entities or source containers, every relationship keeps producer
provenance, and fact, unresolved, and approximate assertions remain distinct.

## Not Yet Decided

- Which document/config entity kinds belong in the shared core, in extensions,
  or in neither.
- Whether Markdown, YAML, and JSON should share one frontend or have separate
  frontends.
- Which relationships are exact enough to admit.
- Which schemas, if any, are required before YAML or JSON domain meanings can be
  facts.
- Whether this should happen before or after deeper Zig dogfood coverage.

## Promotion Criteria

Turn this idea into a plan only when there is a concrete workflow, such as:

- answering project-stage questions from roadmap, follow-up, report, and release
  links;
- detecting stale lifecycle, frontmatter, anchor, or document-link drift;
- mapping config references to scripts, source files, or local commands;
- improving local agent orientation without broad Markdown text search;
- measuring whether the extracted structure gives better answers than current
  shell-based document search.
