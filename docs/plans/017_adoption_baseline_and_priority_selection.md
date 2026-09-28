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

In scope: paired manual/semidx-assisted sessions on Petclinic and Dubbo,
scripted scale measurements on Dubbo and Camel, existing semantic fixtures,
actual client output, a bounded memory screen, and prioritization. semidx's own
repository is a replay control only. Java is an evaluation choice, not a new
coverage promise. Camel does not add paired agent sessions.

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
`./scripts/check-zig-version.sh`, `zig build -Doptimize=ReleaseFast`,
`zig build test -Doptimize=ReleaseFast`, and
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

Use three external roots with separate roles. Petclinic and Dubbo provide six
bounded task cards for paired agent sessions. Dubbo and Camel provide the scale
comparison; Camel needs only scripted replay cards. Index each whole root and
report discovery exclusions; manual answer checking remains task-bounded.

| Corpus | Required role in Plan 017 | Later use |
| --- | --- | --- |
| Existing Java fixtures | Verify current positive, negative, unresolved, and edit-history guarantees; map relevant tests to each task's semantic assumptions. | Minimal regression cases for selected semantic extensions. |
| Petclinic | Small application tasks and client-output observations. | First-install example in L3; no packaging work in this plan. |
| Dubbo | Paired tasks, previous-scale baseline, and retained-memory screen. | Replay for L1/L2/L4 changes. |
| Camel | Larger whole-root latency/startup profile with scripted lookup, impact, and edit/sync replay. | Scale regression profile; no extra paired agent sessions. |

| Repository | Pinned commit | Tracked Java files | Java bytes | `pom.xml` files |
| --- | --- | --- | --- | --- |
| [spring-projects/spring-petclinic](https://github.com/spring-projects/spring-petclinic/tree/818c4136ea971c21674525f9053de0d9c7ad8cfe) | `818c4136ea971c21674525f9053de0d9c7ad8cfe` | 50 | 138,117 | 1 |
| [apache/dubbo](https://github.com/apache/dubbo/tree/df9c5e13bc014ef492ec20824f8623a5e092a5b1) | `df9c5e13bc014ef492ec20824f8623a5e092a5b1` | 4,050 | 18,446,742 | 119 |
| [apache/camel](https://github.com/apache/camel/tree/3ebbf2fd4b7d3a2231f36afc45d831e9c75953d8) | `3ebbf2fd4b7d3a2231f36afc45d831e9c75953d8` | 27,326 | 165,655,631 | 716 |

Selection evidence collected on 2026-09-28 from GitHub's Git Trees API, not a
semidx index run. Resolve `GET /repos/{owner}/{repo}/commits/{commit}` to its
`commit.tree.sha`, then read `GET /repos/{owner}/{repo}/git/trees/{tree}?recursive=1`.
When `truncated` is true (as for Camel's root), discard that partial response,
list that tree non-recursively, and recursively collect each child tree instead.
Continue splitting until every collected response is complete. Count blob paths
ending in `.java`, sum their `size`, and count paths whose basename is `pom.xml`.
Git submodule contents and generated files absent from Git are not traversed.

Camel has 10,515 files under `src/main/java` and 13,902 under `src/test/java`;
Dubbo has 2,469 and 1,581 respectively. Other Java paths remain in the totals.
`pom.xml` count is a descriptor count, not a resolved Maven reactor/module count.
Camel is approximately 6.7 times larger than Dubbo by Java files, 9.0 by Java bytes,
and 6.0 by POM descriptors. Actual semidx-discovered units, analysis coverage,
latency, and memory remain unmeasured. Local clone availability is unverified.

Camel is an integration framework with many connectors and external APIs, so
it exercises scan size and modularity as well as the current Java visibility
and external-supertype limitations. Those unresolved answers stay visible;
the evaluation does not assume full Camel semantics are supported. Hadoop was
also checked (12,624 tracked Java files and 121 POM descriptors at
`8545d5e3a949746f5f23a9587d5cad8e72d2e741`); Camel provides the larger increase
on both selected dimensions.

For each record upstream identity, full commit, local modifications, source-unit
and byte counts, scan exclusions, and parser diagnostics. Recheck the pinned
trees after obtaining the clones; do not substitute branch heads or synthetic
duplicates. If a pinned input is unavailable, record the blocker before choosing
a replacement and update this manifest explicitly.

Before timed sessions, prepare three task cards each for Petclinic and Dubbo:

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

For each oracle list required established relationships, forbidden targets,
and expected unresolved/unsupported outcomes under the current capability
matrix. Distinguish a declared interface relationship, a statically selected
method, and runtime dispatch or DI selection. An annotation or the only visible
implementation does not establish a runtime target. Do not introduce a new
`IMPLEMENTS` kind, Spring DI model, or overload resolver through the oracle.

Inventory the existing Java fixtures through semidx and record the relevant
paths/test names and gaps in the report. The initial full test lane establishes
their baseline. This stage does not add a comprehensive synthetic application
or expand fixture semantics; new reproductions belong to the selected successor.

Choose three analogous replay-only cards each on Camel and the semidx control,
with their own paths, expected bounded results, and edit instructions. Do not
apply another repository's patches to either root.

DoD: six paired-task cards plus six replay-only cards, source-grounded expected
answers, the fixture inventory, three pinned external roots, and environment
metadata in the report. Missing roots block this stage; record
the missing input and request an accessible root or permission to obtain a
specific public clone. A smaller control cannot satisfy the external-size lane.
If fresh isolated sessions or matching model settings cannot be provided, record
that prerequisite as blocked and resume when they are available; scripted MCP
replay can continue but cannot substitute for the paired task sessions.

## Stage 1: Paired Tasks And Complete MCP Cost

For each of the six Petclinic/Dubbo task cards run a manual-search session and
a semidx-assisted session with the same task, source state, model/settings,
time allowance, and available
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

Separately replay the three cards for each of Petclinic, Dubbo, Camel, and the
semidx control without model reasoning: five warmups, then 30 measured repetitions.
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

DoD: all six Petclinic/Dubbo cards have paired outcomes; all twelve cards have
replay measurements, with results and failures separated by corpus and role.
Improvement means a correct answer with reduced
time or manual work; a correctness loss cannot be offset by speed.

## Stage 2: Client Output And Early Memory Screen

These independent evidence lanes may be collected after Stage 0; Stage 3 needs
both plus Stage 1.

**Client output.** Observe the maintained stdio client and two real MCP clients
at recorded versions against pinned Petclinic. Use compact definition lookup,
a bounded context result,
and a deliberately budget-limited map. Record which text/structured copies are
on the wire, which reach the model when observable, and any warning, truncation,
spill, or follow-up read. Increase the existing response budget within its
documented bounds to probe a threshold; if none is observed, report the largest
tested result rather than inventing a threshold. Wire duplication does not
establish duplicate model context. Keep compatibility behavior unchanged.
If Petclinic exhausts its available results before reaching a client-size
boundary, use the pinned Dubbo replay result in all clients for that size probe
and record the change of corpus. This adds no paired agent sessions.

**Memory.** On a disposable copy of the Dubbo root, fix the live source size and
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
by all six paired-task cards and the required scale, client, and memory evidence.
Mark this plan completed only when required evidence exists.
An unavailable input yields blocked status with an exact resume condition, not
a success claim. Implementing the successor is outside this plan.

For a semantic successor, carry one observed missing relationship through a
minimal fixture, explicit required/forbidden/unknown outcomes, an accepted
decision where needed, narrow implementation, replay of the original task,
and scale regression checks. Extend existing `fixtures/` instead of introducing
a separate all-features application. Include identity and invalidation cases
when the new rule changes dependency tracking.

JUnit or Spring Framework may enter that successor only for a named semantic
question not adequately exercised by the current corpora. JabRef remains a
candidate only if it contributes a distinct task. Before use, pin the commit,
state the role, freeze expected answers, and specify admission/exit checks.
These candidates are not prerequisites or extra work in Plan 017. Small
deterministic checks belong in normal test lanes; large external replay remains
stage evidence and does not become a mandatory build/network dependency.

## Verification And Tooling Boundaries

Apply `semidx-test-design` to any measurement code. Prefer existing developer
tools and MCP clients. A needed new reusable measurement tool must be Zig, must
have its procedure recorded in the report, and must not become a build, hook,
CI, or runtime prerequisite. No production instrumentation in this plan. Before
adding a helper, record its smallest interface and checks in the report.

| Risk | Sufficient evidence / verification |
| --- | --- |
| Biased tasks or incorrect oracle | Six Petclinic/Dubbo cards, separate Camel/control replays, source-based required/forbidden/unknown outcomes, fresh paired sessions, retained failures. |
| Mistaking unsupported semantics for false facts | Existing Java fixture baseline and capability matrix; explicit distinction between source declarations, static targets, and runtime dispatch/DI. |
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
change, including sync-first guidance. Petclinic/Dubbo own paired task evidence;
Dubbo/Camel own the scale comparison. Tree counts are selection evidence only.
Plan 015 remains
blocked under its own resume conditions; Plan 016 remains completed. No runtime
measurement has run under Plan 017 yet. External-root and client availability
are execution prerequisites
with the stop/resume rules above, not evidence presumed present.

Preparation review: no unresolved hard failure in the plan's scope, order,
authority, or acceptance conditions. Review clarified the control's own replay
cards, isolated-session prerequisites, definition-rename limits, and memory
inputs that introduce new values at bounded live size. Runtime gates and task
measurements are intentionally pending execution, not reported as passed.
The corpus-role revision preserves 24 paired sessions, specifies twelve replay
cards across four roots, and keeps future semantic corpora outside this plan.
