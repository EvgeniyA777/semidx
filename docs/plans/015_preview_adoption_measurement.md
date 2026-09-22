---
title: "Preview adoption measurement"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-22"
---

# 015: Preview Adoption Measurement

## Goal

Prove whether `semidx-mcp` already helps agents on two or three real local
projects before choosing the next large implementation lane.

The proof is not a broader semantic-core expansion. It is local measurement:
how real MCP clients expose duplicated fallback output, whether the intended
agent habit loop is cheaper than manual exploration, and where the current
preview still creates friction.

This plan uses `v0.1.0-preview.4` as the measured preview. Its output is a
decision: keep the text fallback as-is, shorten it, make it configurable, or
defer a change with evidence; then decide whether a `v0.1.0-preview.5`
UX/tooling release is justified without widening graph semantics.

## Product Principle

1. **Evidence before product shape.** Follow-up 010 exists because changing the
   text fallback without client measurements would guess at protocol behavior.
2. **Local measurement only.** Measurement runs on local roots and does not
   transmit source-derived data. Committed evidence records derived counts,
   sizes, timings, client behavior, and pain points, not private transcripts or
   source excerpts.
3. **Client behavior is observation, not a hard gate.** A client may warn,
   truncate, hide structured content, duplicate text, or spill output. Record
   it as measured behavior for the client and version, not as a project-wide
   invariant.
4. **No semantic expansion.** Do not add language coverage, core kinds,
   persistence, a semantic contract version, or new graph authority as part of
   this plan.
5. **Pain chooses the next lane.** The next large plan comes from measured
   agent friction, not from which semantic rule looks tempting locally.

## Start Rule

Read before starting:

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) §1, §3,
  §7, and §8.
- [Product adoption strategy](../design/002_product_adoption_strategy.md),
  especially "Agent Habit Loop", "First Public Proofs", and "Success Metrics".
- [Project roadmap](../design/001_project_roadmap.md), especially the
  post-preview.4 direction.
- [Follow-up 010](../followups/010_mcp_text_fallback_client_measurement.md).
- [ADR 007](../adr/007_text_fallback_migration_flag.md), as a proposed input,
  not as an accepted decision.
- [Local MCP preview reference](../mcp/local_preview.md).
- [Plan 009](009_mcp_progressive_discovery_and_budgets.md) and
  [its progress log](../reports/009_mcp_progressive_discovery_and_budgets_progress.md),
  especially response budgets, cursors, and payload-copy evidence.
- [Plan 014 progress](../reports/014_java_receiver_coverage_progress.md) for
  the current release boundary and Java-scale evidence.

Create and maintain
[docs/reports/015_preview_adoption_measurement_progress.md](../reports/015_preview_adoption_measurement_progress.md)
before implementation work.

Stop and amend this plan if a stage needs source-derived data to leave the
local machine, a production fallback change before measurement, or semantic-core
changes. Those are different decisions.

## Scope

- Build local measurement tools or scripts that can launch or drive
  `semidx-mcp` against a chosen local root and record:
  - MCP protocol era;
  - tool name and arguments, excluding private source text;
  - structured payload byte size;
  - fallback text byte size;
  - whether fallback and structured content are both present on the wire;
  - latency and truncation/budget fields reported by the tool;
  - client-visible behavior when a real MCP client shows, hides, truncates,
    warns, or spills a result.
- Define two or three repeatable habit-loop scenarios:
  - orientation: `health -> outline -> scoped repo_map`;
  - focused lookup: `find_definitions -> references` or `context`;
  - edit loop: make a small local edit, run `refresh`, and verify a changed
    snapshot revision or stale/fresh behavior;
  - optional impact check: choose a symbol, inspect references/context, and
    record whether manual grep/read was still needed.
- Run the scenarios on two or three real local projects. One may be this
  repository; at least one should be outside semidx. Committed evidence uses
  stable aliases, repository characteristics, language mix, file counts, and
  measurements. Do not commit private paths, source snippets, or full client
  transcripts.
- Record pain points:
  - awkward query shapes;
  - missing documentation or confusing tool descriptions;
  - response-size problems;
  - excess JSON or fallback duplication;
  - cases where the agent still falls back to broad manual file reads.
- Close or narrow [Follow-up 010](../followups/010_mcp_text_fallback_client_measurement.md)
  based on the evidence.
- Accept, reject, or revise proposed
  [ADR 007](../adr/007_text_fallback_migration_flag.md) based on the evidence.
- Update [Product adoption strategy](../design/002_product_adoption_strategy.md),
  [Project roadmap](../design/001_project_roadmap.md), and `MEMORY.md` only
  with evidence-backed conclusions.
- Decide whether to cut a `v0.1.0-preview.5` UX/tooling release. A preview.5
  from this plan may improve measurement, docs, fallback UX, or launcher
  ergonomics, but must not widen semantic-core behavior.

## Non-Scope

- No new language coverage, Java rule, Zig rule, core kind, `IMPORTS`, `module`,
  persistence, daemon, HTTP transport, stable semantic contract, schema
  publication, or binary/package release.
- No remote telemetry, analytics endpoint, background upload, or collection of
  source-derived data outside the user's local machine.
- No committed raw transcripts from private client sessions.
- No fallback behavior change before Stage 1 and Stage 2 evidence exists.
- No claim that a client behavior is universal unless it was reproduced across
  every measured client version named in the report.

## Measurement Artifacts

The plan should create or update the smallest useful local artifacts:

- a maintained stdio probe for wire-level fallback and structured-content size;
- a habit-loop scenario file or report template that names the exact tool
  sequence, expected observations, and metrics to record;
- a redaction rule for evidence committed from non-public repositories;
- a progress-log evidence matrix that compares projects, clients, scenarios,
  payload sizes, latencies, and pain points.

The tools may be shell or Zig. Prefer a checked-in script when the measurement
can be repeated without private client integration; prefer a report template
when the observation depends on a human-visible client UI or proprietary client
logs.

## Stages

### Stage 0: Measurement Design And Project Selection

Purpose: make the evidence collection repeatable before running it.

Tasks:

- Select two or three local project roots and assign stable aliases such as
  `project-a`, `project-b`, and `semidx`. Record language mix, rough size, and
  whether the alias is public or private.
- Define the scenario pack for orientation, lookup, context/references, edit,
  and refresh.
- Define the measurement schema: tool call, client, protocol era, structured
  bytes, fallback bytes, total visible bytes when known, latency, truncation,
  warning/spill behavior, manual fallback, and notes.
- Decide what can be automated and what must be recorded manually from a real
  client.

Done when the progress log contains the selected aliases, scenario pack,
measurement schema, privacy rule, and any blocked client observations.

### Stage 1: Maintained Stdio Fallback Probe

Purpose: measure the wire-level truth independent of a real client UI.

Tasks:

- Add or update a local probe that drives `semidx-mcp` through the maintained
  stdio path for both supported protocol eras where practical.
- Record whether each successful result carries `structuredContent`, fallback
  text, or both.
- Exercise at least one small result and one budget-sized result.
- Record structured bytes, fallback bytes, response budget fields, and latency.

Done when the probe is repeatable from a clean checkout and its output is
recorded in the progress log.

### Stage 2: Real MCP Client Output Measurement

Purpose: answer Follow-up 010 for clients agents actually use.

Tasks:

- Measure at least two real MCP clients or client surfaces available locally.
- For each client, record whether the model-visible context includes the
  fallback text, structured content, both, neither, a warning, truncation, or a
  file/spill artifact.
- Use the same small and budget-sized calls as Stage 1 where possible.
- Record client name, version when discoverable, protocol era, and observation
  method.

Done when the progress log has at least two real-client observations or records
an exact blocker for each missing observation.

### Stage 3: Habit-Loop Runs On Real Projects

Purpose: prove whether the preview helps agents on real local codebases.

Tasks:

- Run the scenario pack on two or three local project aliases.
- For each run, record which semidx tool answered the question, latency/output
  size, whether the answer was enough to proceed, and where manual file reads
  or grep were still needed.
- Include one edit-and-refresh loop per project when safe. If editing a project
  is not safe, use a disposable copy or record the skip reason.
- Classify pain points as docs, query shape, response size, missing semantic
  coverage, client display, or launcher/setup friction.

Done when the progress log contains a scenario matrix and a short verdict for
each project.

### Stage 4: Decision And Documentation

Purpose: convert the measurements into the next product decision.

Tasks:

- Decide one of:
  - keep fallback behavior unchanged;
  - shorten fallback text;
  - add a production `--text-fallback` option;
  - keep only the diagnostic probe and defer production changes;
  - open a more specific follow-up because evidence is inconclusive.
- Update or close Follow-up 010 with the decision and evidence link.
- Accept, reject, or revise proposed ADR 007.
- Update the roadmap and product adoption strategy with measured conclusions,
  not preference.
- Update `MEMORY.md` if near-term priorities or active assumptions changed.
- Decide whether preview.5 is justified as a UX/tooling release and either
  create the release plan or record why not.

Done when source-of-truth documents agree, deferred findings are current, and
the next large lane is chosen or explicitly deferred pending a named blocker.

### Stage 5: Optional UX/Tooling Release Slice

Purpose: implement only the UX/tooling changes justified by Stage 4.

This stage is active only if Stage 4 chooses a preview.5 slice. Its plan must
name exact files, tests, release gate, release notes, and tag behavior before
execution. It must not widen semantic core behavior.

## Verification

Use the narrowest checks that match the files changed:

- Documentation-only stages: `git diff --check`,
  `./scripts/check-agent-attribution.sh --all`, and
  `./scripts/check-memory-freshness.sh` when `MEMORY.md` changes.
- Script or shell tooling stages: the script's own smoke command plus
  `shellcheck` only if the repository already has it available locally; do not
  add a dependency just for this plan.
- Zig tooling stages: `./scripts/check-zig-version.sh`, `zig fmt --check
  build.zig src tests`, and the focused build/test command named by the changed
  target. Run `zig build test-mcp` when MCP stdio behavior changes.
- Fallback-shape changes: smoke both supported protocol eras and record before
  and after transcript byte observations.

Skipped checks must be recorded with the reason.

## Definition Of Done

- A local measurement path exists for maintained stdio behavior.
- Two or more real client observations are recorded, or exact blockers are
  documented.
- Two or three real local project scenarios are recorded with aliases,
  measurements, and pain points.
- Follow-up 010 is closed, narrowed, or explicitly left open with a sharper
  blocker.
- ADR 007 is accepted, rejected, or revised.
- The roadmap, product adoption strategy, `MEMORY.md`, and progress log agree
  on the measured next direction.
- Any preview.5 decision is backed by the measurement, not by taste.
