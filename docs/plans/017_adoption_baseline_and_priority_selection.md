---
title: "Adoption baseline and priority selection"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-28"
---

# 017: Adoption Baseline And Priority Selection

## Goal And Boundary

Determine whether the current semidx preview reduces the work needed to answer
real code questions, identify the largest obstacle, and prepare one bounded
successor intervention. This implements L0 of the
[roadmap](../design/001_project_roadmap.md#adoption-levels), not L1-L4.

Deliverables are a reproducible measurement record and a successor plan, or an
evidence-backed decision that this sample justifies no intervention. This plan
does not promise a speedup or treat increased tool use as success.

In scope: two external Java repositories, three tasks per repository, paired
manual/semidx-assisted sessions, complete MCP timings, actual client output,
a bounded memory screen, and prioritization. semidx's own repository is a
control only. Java is an evaluation choice, not a new coverage promise.

Out of scope: runtime optimization, frontend expansion, parser upgrades,
installation artifacts, watchers, persistence, public contracts, ranking, new
services, and changing response compatibility. Do not remove the text fallback,
weaken preflight, or change a resolution rule during baseline collection.

## Authority And Start Conditions

Read `RULES.md`, the constitution, `MEMORY.md`, the adoption strategy,
[ADR 002](../adr/002_local_tree_sitter_parser_dependency.md),
[ADR 014](../adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md),
the [capability matrix](../spec/capability_matrix.md),
[MCP reference](../mcp/local_preview.md),
[gate specification](../mcp/habit_loop_gate.md), and Follow-ups
[010](../followups/010_mcp_text_fallback_client_measurement.md) and
[020](../followups/020_java_external_supertype_leaves_the_chain_open.md).

Before execution, apply the Plan Readiness Gate and record the semidx commit,
clean/dirty state, product version, OS, CPU, RAM, build mode, exact Zig 0.16.0,
parser prerequisites, client versions, and available external roots. Run
`./scripts/check-zig-version.sh`, `zig build -Doptimize=ReleaseFast`, and
`zig build preview-gate -Doptimize=ReleaseFast`. Capture full output and exits.
Keep this build mode fixed across baseline runs.

Create `docs/reports/017_adoption_baseline_and_priority_selection_progress.md`
at the start of execution, not at plan preparation. It owns the manifest,
procedure, measurements, stage status, exact replay commands, exclusions,
readiness assessment, limitations, and handoff. Never commit private paths,
credentials, source bodies, or raw session transcripts.

All edits used as probes happen on disposable repository copies. Do not switch
the working repository's branch or modify an external user's checkout.
Build/index/query remain local and require no service. Source text stays off;
Jev stays disabled. Hosted-client transmission requires the destination and
source-derived data to be explicitly authorized; public source is not consent.

## Stage 0: Freeze Inputs And Expected Answers

Select two locally available external Java repositories: one small enough to
inspect manually and one with at least 1,000 discovered Java units. Prefer the
previous apache/dubbo baseline for the larger repository when available, but
record the actual commit and do not treat old numbers as a new measurement.
For each record upstream identity, full commit, local modifications, source-unit
and byte counts, scan exclusions, and parser diagnostics. Do not add synthetic
duplicates to meet the size floor.

Before timed sessions, prepare three task cards per repository:

1. Locate the implementation of a behavior named in a repository test or issue;
   identify the relevant definition and source location.
2. Identify callers/references relevant to changing a named definition; separate
   established relationships, unresolved candidates, and uncovered constructs.
3. Make one prescribed body edit in a disposable copy, then identify the current
   location and relevant neighborhood after synchronization; check retained
   identity and distinguish it from a definition rename whose correspondence
   the current implementation cannot establish.

Choose targets from actual task needs, before checking whether semidx resolves
them. Include at least one known coverage limitation; never discard a card
because semidx fails it. Record rationale, edit instructions, and patch digests;
keep exact patches in local replay artifacts outside version control. Independently
read the source to record expected entities, locations, and relationships for
each bounded question. Do not use semidx output as its own correctness oracle
or claim complete repository-wide impact from this bounded assessment.

Choose three analogous replay-only cards on the semidx control, with its own
paths and edit instructions; do not apply external-repository patches to it.

DoD: six frozen task cards, source-grounded expected answers, two pinned roots,
and environment metadata in the report. Missing roots block this stage; record
the missing input and request an accessible root or permission to obtain a
specific public clone. A smaller control cannot satisfy the external-size lane.
If fresh isolated sessions or matching model settings cannot be provided, record
that prerequisite as blocked and resume when they are available; scripted MCP
replay can continue but cannot substitute for the paired task sessions.

## Stage 1: Paired Tasks And Complete MCP Cost

For every card run a manual-search session and a semidx-assisted session with
the same task, source state, model/settings, time allowance, and available
source-reading tools. The manual arm omits semidx; the assisted arm may fall
back to manual tools and counts that work. Use fresh sessions without the oracle
or the other arm's answers. Alternate arm order across cards. Repeat each pair
once: 24 task sessions total. This is a small comparative sample, not a claim
of statistical significance. Stop each session at 15 minutes and record timeout
as an outcome, not as a fast completion.

Record correctness against the frozen oracle, elapsed task time, manual search
and file-read counts, semidx call sequence, failed/retried calls, output bytes,
and the first useful answer. Record model-visible token counts only when the
client exposes them; bytes are not tokens. List each missing relationship that
forced manual work with its recorded resolution reason.

Separately replay each task's fixed MCP sequence without model reasoning on
both external roots and the control: five warmups, then 30 measured repetitions.
Report per-call and sequence p50/p95, sample count, errors, and total wire bytes.
Include `semidx_sync`, preflight, serialization, and transport in the measured
boundary. For the edit card restore the initial disposable state before every
repetition and apply the same patch; keep unchanged and changed sync separate.
Record startup/indexing in three fresh-process runs, separately from warm calls;
do not claim an OS-cold filesystem cache unless actually controlled.

Use the sync-first, task-directed workflow in the adoption strategy. Record
whether direct focused lookup or progressive discovery was needed. Never hide
preflight behind old in-process query-only timings. Attribute a sub-cost only
if profiling measures it; do not subtract unrelated benchmark medians.

DoD: every card has paired outcomes and replay measurements, with per-repository
results and failures visible. Improvement means a correct answer with reduced
time or manual work; a correctness loss cannot be offset by speed.

## Stage 2: Client Output And Early Memory Screen

These independent evidence lanes may be collected after Stage 0; Stage 3 needs
both plus Stage 1.

**Client output.** Observe the maintained stdio client and two real MCP clients
at recorded versions. Use compact definition lookup, a bounded context result,
and a deliberately budget-limited map. Record which text/structured copies are
on the wire, which reach the model when observable, and any warning, truncation,
spill, or follow-up read. Increase the existing response budget within its
documented bounds to probe a threshold; if none is observed, report the largest
tested result rather than inventing a threshold. Wire duplication does not
establish duplicate model context. Keep compatibility behavior unchanged.

**Memory.** On a disposable copy of the small root, fix the live source size and
run 1,000 edit/sync cycles in one server: alternate a body edit, create/remove a
temporary unit, and rename/restore a file in a written deterministic sequence.
Use fresh fixed-width names and equal-length edits across cycles, restoring
the original bytes after each cycle, so live input stays bounded while the
history introduces new internable values. Verify with full health that live
graph counts return to their baseline; report retained records separately when
they do not. Pin the sequence and replay commands before the first run.
Record RSS, live units/entities/assertions, and source-state identity at baseline
and every 100 cycles, plus after restoring the starting bytes and after a fresh
server indexes those same bytes. Repeat once; include a 1,000 unchanged-sync
control. Normalize growth against live graph size. RSS alone is a screening
signal, not proof of a leak or of which allocation owns retained bytes.

For process safety stop at 25% of host RAM or 2 GiB RSS, whichever is lower, or
on crash. Record the last successful cycle and label the run censored; do not
remove it from the report. Escalate a reproduced crash, exhaustion, or growth
that reaches the cap at bounded live size ahead of normal feature work.
If RSS trends upward without hitting the cap, price a focused allocation study
as a candidate instead of prescribing restarts or selecting reclamation design.

DoD: client observations meet Follow-up 010's client count, and memory history
has both repeated churn runs and the unchanged control. Unavailable clients,
unobservable model input, or missing consent remain named evidence gaps. Do not
claim model-token savings from transport inspection. Independent lanes may
continue; a blocked required lane prevents whole-plan completion.

## Stage 3: Select One Intervention And Close

Classify each failed or expensive task by measured dominant cause: obtaining
current context, missing semantic relationships, installation/client setup, or
session lifecycle. Rank candidates by correct task completions recovered first,
then repeated time/manual-work savings, then estimated implementation effort.
State uncertainty; when no cause dominates, choose the smallest focused
experiment that can distinguish the leading candidates, with one falsifiable
question and a stop rule. Do not expand the baseline indefinitely.

When an intervention is justified, prepare exactly one successor plan using
the next available number. Name its
affected files/modules, accepted ADR or required new decision, behavior,
non-scope, before/after replay cases, tests, and numerical improvement target
chosen from this baseline. Read the relevant source through semidx before
fixing the implementation scope. Apply the Plan Readiness Gate. A draft awaiting
an architectural decision must say so and cannot be reported executable.

For Java candidates use Follow-up 020's measurement and admission rules before
adding external shape evidence. For preflight candidates preserve ADR 014 or
explicitly prepare an admissible new decision before changing its mechanism.
For output candidates satisfy Follow-up 010 before proposing compatibility
changes. Memory remedies must account for existing snapshots borrowing strings.

DoD: ranked evidence, one bounded successor with its readiness state, and updated
roadmap/`MEMORY.md`; alternatively an explicit no-intervention decision supported
by all six cards. Mark this plan completed only when required evidence exists.
An unavailable input yields blocked status with an exact resume condition, not
a success claim. Implementing the successor is outside this plan.

## Verification And Tooling Boundaries

Apply `semidx-test-design` to any measurement code. Prefer existing developer
tools and MCP clients. A needed new reusable measurement tool must be Zig, must
have its procedure recorded in the report, and must not become a build, hook,
CI, or runtime prerequisite. No production instrumentation in this plan. Before
adding a helper, record its smallest interface and checks in the report.

| Risk | Sufficient evidence / verification |
| --- | --- |
| Biased tasks or incorrect oracle | Frozen cards, source-based expected answers, fresh paired sessions, retained failures. |
| Hidden preflight cost | Full stdio request/response timing, fixed build, unchanged/changed and startup/warm results separated. |
| Stale or false facts | Existing `zig build preview-gate -Doptimize=ReleaseFast` plus source-oracle assessment; any new reproduction gets a focused correctness follow-up before optimization. |
| Client compatibility/privacy | Two actual clients plus maintained stdio observations; explicit consent boundary; no source bodies, credentials, or private transcripts in artifacts. |
| Retained memory mistaken for live data or allocator noise | Repeated bounded-size churn, unchanged control, fresh-process comparison, visible cap and censored runs. |
| Faulty measurement helper | Small deterministic input with known counts/timing aggregation; malformed/timeout handling; `zig fmt --check build.zig src tests` and `zig build test` if source/build/fixtures change. |
| Documentation drift | `git diff --check`, relative-link target check, frontmatter review, Plan Readiness Gate, and staged attribution/constitution guards. |

If no source changes, do not add tests solely for documentation. Initial runtime
gates prove the measured build; repeat only after source changes or a relevant
failure. Record exact commands, complete exits, omissions, and environmental
limits. Follow git policy for explicit staging and coherent commits; no push is
part of this plan.

## Readiness And Ownership Review At Preparation

Scope is measurement and planning; no new core kind, semantic contract, frontend
rule, transport, runtime dependency, outbound destination, or persistence choice
is admitted. Constitution, SPEC, CORE, CONFORMANCE, capability matrix, and
GLOSSARY retain their current meanings. L0-L4 are roadmap-local priority labels,
not new model vocabulary. ADR 014 and proposed ADR 007 keep their statuses.

The roadmap, adoption strategy, and `MEMORY.md` are aligned in this preparation
change, including sync-first guidance. Plan 015 remains blocked under its own
resume conditions; Plan 016 remains completed. No measurement has run under
Plan 017 yet. External-root and client availability are execution prerequisites
with the stop/resume rules above, not evidence presumed present.

Preparation review: no unresolved hard failure in the plan's scope, order,
authority, or acceptance conditions. Review clarified the control's own replay
cards, isolated-session prerequisites, definition-rename limits, and memory
inputs that introduce new values at bounded live size. Runtime gates and task
measurements are intentionally pending execution, not reported as passed.
