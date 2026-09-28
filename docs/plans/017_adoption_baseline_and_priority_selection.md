---
title: "Adoption baseline and priority selection"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-28"
---

# 017: Adoption Baseline And Priority Selection

## Goal, Scope, And Authority

Measure whether semidx helps with bounded code tasks, separate correctness from
coverage and operational cost, and prepare one justified successor intervention.
This is L0 of the [roadmap](../design/001_project_roadmap.md#adoption-levels).
A complete negative result is evidence; a missing prerequisite is not a result.

Scope: six paired task cards (three each on Petclinic and Dubbo), six additional
scripted cards (three each on Camel and the semidx control), a required local Zig
measurement driver, two actual MCP clients, and bounded memory history. There
are 24 agent sessions: six cards x two variants x two repetitions. Camel adds
no agent sessions. Existing fixtures check current semantic guarantees.

Non-scope: production optimizations, changing discovery budgets or exclusions,
semantic expansion, parser upgrades, installation artifacts, ranking, watchers,
persistence, new transports, or public contracts. The developer driver may add
an opt-in build step; it must not change server behavior or ordinary lane inputs.

Read RULES, the frozen constitution, MEMORY, SPEC, capability matrix,
[tooling policy](../agent-policy/tooling.md),
[testing policy](../agent-policy/testing.md),
[ADR 002](../adr/002_local_tree_sitter_parser_dependency.md),
[ADR 014](../adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md),
[MCP reference](../mcp/local_preview.md), and Follow-ups
[010](../followups/010_mcp_text_fallback_client_measurement.md),
[017](../followups/017_plan_012_external_evidence_reproducibility.md), and
[020](../followups/020_java_external_supertype_leaves_the_chain_open.md).
Apply the Plan Readiness Gate before execution and after a scope revision.

Here only, a **card** is a frozen question with a bounded source scope;
**variant** (or arm) means manual or semidx-assisted; **source oracle** is the
independently checked answer; **tool expectation** is the current preview's
expected output; **replay** is a fixed local call/edit sequence. These are
plan-local measurement terms, not additions to graph vocabulary.

## Corpus Manifest And Roles

| Corpus | Required role | Later use |
| --- | --- | --- |
| Existing Java fixtures | Inventory positive, negative, unresolved, and edit-history checks; run their current test lane. | Minimal regressions for a selected extension. |
| Petclinic | Three paired tasks, replay, and initial client-output samples. | L3 installation example, not installation evidence here. |
| Dubbo | Three paired tasks, replay, previous-scale comparison, memory screen. | L1/L2/L4 regression evidence. |
| Camel | Whole-root capacity probe, then three scripted replay cards only if the index is complete. | Larger scale profile; no partial-index speed claims. |
| semidx | Frozen source copy for three Zig replay cards only. | Detect transport/driver regressions; not a matched Java-quality comparison. |

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

## Stages And Durable Artifacts

Execute in order: Stage 0 prerequisites/cards -> Stage 1 driver -> Stage 2
paired tasks and replay -> Stage 4 decision. Stage 3 client/memory evidence can
run after Stage 1, independently of Stage 2. Every stage has its own status.
Do not mix results across changed manifests or binaries.

At execution start create
`docs/reports/017_adoption_baseline_and_priority_selection_progress.md` and
`docs/reports/017_adoption_baseline/README.md`. The report owns results and
review dispositions; the artifact directory owns reproducible inputs:

- `manifest.json`: corpus commits, build commit/hash, platform, budgets, model,
  client versions, protocol era, configuration hashes, and lane readiness;
- `cards.json`: selection seed, candidates/rejections, scopes, required answers,
  forbidden targets, unresolved expectations, and complete replay parameters;
- `edits.json`: root-relative file, initial SHA-256, byte offset and delete length,
  replacement UTF-8 bytes or an exact deterministic generation recipe, final
  SHA-256, and inverse operation for every edit;
- `prompts.md`, `client_profiles.md`: exact shared/task/variant prompts, launch
  commands, instruction discovery, tool lists, hooks, and verified isolation;
- `runs.jsonl`, `scores.csv`, `summary.md`: sanitized per-run evidence,
  classifications, aggregates, exclusions, and decision.

Commit these inputs before timed runs. Hashes alone are insufficient: another
executor must reconstruct edits and calls from the pinned repositories plus
committed artifacts. Keep full source trees, credentials, raw session logs,
and private host paths outside version control; public names, paths, answer
locations, and minimal edit literals are allowed. Preserve relevant upstream
licensing for copied snippets. Local root substitutions belong in an untracked
mapping; record placeholders in committed commands. Reports never need secrets.

## Stage 0: Establish An Executable Experiment

### Build, Roots, And Consent

Record the clean source commit to measure, product version, exact Zig 0.16.0,
OS/architecture, RAM, parser inputs, and client versions. Product version is
informational: preview.4 also labels post-Plan-016 source. The build identity is
full source commit + SHA-256 of the executable + build mode + parser inputs.

Run `./scripts/check-zig-version.sh`, `zig build -Doptimize=ReleaseFast`,
`zig build test -Doptimize=ReleaseFast`, and
`zig build preview-gate -Doptimize=ReleaseFast`; capture full output and exits.
Copy that `zig-out/bin/semidx-mcp` to an immutable local artifact path. Both agent
sessions and replay use this exact binary with explicit `--root`. Do not point
the experiment at a mutable `scripts/semidx-mcp.sh`: it resolves the current
`zig-out/bin/semidx-mcp`, which a later build can replace. Recheck the binary
hash before each run; a mismatch invalidates the run before timing starts.

Create disposable corpus copies from the pinned commits, without executing their
build scripts. Freeze the semidx control once from the measured source commit,
before writing logs or adding the driver. Inventory source bytes/exclusions and
verify copy hashes. Documentation-only commits made during execution do not
change that copy. A new measured binary starts a new dataset.

The user operating this evaluation supplies any needed transmission consent.
Before either paired variant or a real hosted-client probe, record an explicit
user authorization reference naming provider/destination, model, corpora, and
allowed data: source excerpts from manual reads, graph values, and prompts/tool
results. Authorization for graph metadata alone does not authorize source reads.
Public repositories and prior planning approval do not imply consent. Local
models need no outbound consent, but both paired variants must use the same
model and settings; never compare local versus hosted as the treatment.

If consent, model access, corpus access, or an isolated runner is missing, mark
only dependent lanes blocked, request the exact missing input, and resume them
when supplied. Local driver/replay work may continue. Never provision paid
services or alter global client policy as an implicit setup step.

### Isolation And Frozen Prompts

Use the same client/model for all paired sessions. Default paired client is
Claude Code; Stage 3 compares Claude Code and Codex CLI. Presence checked during
plan review: `claude --version` returned 2.1.267 and `codex --version` returned
0.154.0. This proves executables exist, not authentication, isolation, or model
visibility. Freeze actual versions/settings at execution, including model id,
reasoning effort, temperature where exposed, and cache/session settings.

Run in disposable client profiles under a dedicated evaluation account or an
already isolated runner. Do not redefine HOME/CODEX_HOME in the active session,
edit user/global instructions, or disable the user's hooks in place. Before
measurement, export effective configuration and loaded instruction/tool lists
from the chosen runner. If the client cannot exclude inherited semidx mandates
and blocking hooks, that runner is ineligible; dependent sessions stay blocked
until a genuinely isolated runner is available. Do not silently override rules.

Both variants get identical base instructions, task text, shell/file tools,
working-copy bytes, and 15-minute time allowance. No other code-index, web,
network, or cross-session memory tools are available. Corpus instruction files
are source data, not loaded experimental instructions, in both variants. Record
exact launcher/configuration proving this; do not assume that a new chat alone
achieves isolation. Leave source bytes unchanged in the indexed copy.

Shared prompt, followed by the committed task question:

> Answer the bounded source question using the available local tools. Return a
> list of conclusions with root-relative path and current line evidence. Label
> uncertain candidates separately; do not infer runtime targets without evidence.
> Stay within the named answer scope. Do not modify files except as the task says.

Manual suffix:

> Use the available text-search and file-reading tools. No semantic index tool
> is available in this session.

Assisted suffix:

> semidx is available. Start with semidx_sync. For unfamiliar structure use
> semidx_outline then a scoped semidx_repo_map; locate named definitions and use
> semidx_references or semidx_context as appropriate. After edits sync again.
> Unresolved results are candidates, not facts. Use source reads when needed.

This measures an instructed workflow, not spontaneous tool adoption. Record
non-use and misuse separately as workflow/discoverability evidence. The suffix
and additional MCP tool set are the only intended treatment differences.

Before each variant's first session, run an untimed disposable probe: a Java
file read and text search both succeed; manual tool inventory has no semidx and
no hook requests it; assisted sync/context succeed; neither profile loads global
semidx policy or an earlier answer. Archive sanitized traces/config hashes. A
failed probe blocks that variant. Fresh sessions never see source oracles,
other answers, preselected tool ids, or review notes. Alternate manual-first and
assisted-first by card ordinal; reverse that order on the second repetition.

### Deterministic Task Selection And Scope

Select without consulting semidx results. For each external corpus enumerate
tracked Java files under `src/main/java`, lexicographically sorted; for the
semidx control use `src/**/*.zig`. Order candidate paths by
`(sha256("017-v1\n" + repo + "\n" + path), path)`. Inspect candidates in that
order and declarations in increasing source-byte order. Stop after 50 files per
corpus if no eligible target is found: record selection blocked and revise the
selection rule explicitly, not by hand-picking a favorable example.

Within a candidate file choose the first named, concrete top-level-class method
(or top-level Zig function) with a body and at least one direct source caller in
the same parent-directory subtree. The answer scope is that subtree's first 20
Java/Zig files in lexical path order; include the target file or reject the
candidate. Accept only 1-10 independently provable direct call/reference
occurrences inside that scope. Cap its combined source at 64 KiB; reject larger
scopes, ambiguous overload targets, and unprovable runtime dispatch for the main
card, recording why. Search outside scope is allowed for disambiguation but
answers are scored only inside scope. This is a bounded task sample, not random
coverage of the repository. Freeze candidates, rejection reasons, chosen scope,
and source proof; a human choice is not hidden behind the hash seed.

Use the selected target to define each corpus's three cards:

1. Locate the method implementing a described behavior. Derive the description
   from that method and a test when one exists; omit its path and symbol name
   from the question. Required answer: definition and correct current location.
2. Given the definition, list direct source calls/references inside the frozen
   scope. Required answer: every in-scope occurrence and its declared target;
   do not require the runtime implementation selected by DI or dispatch.
3. Given the definition and scope, report its current location and the same
   relevant neighborhood after an externally applied body-only edit. Insert the
   fixed line `// semidx evaluation body edit` immediately inside its body,
   preserving its signature. The runner applies the committed edit after the
   initial untimed server sync and before releasing the question to either
   variant. Both variants see the same edited bytes. No rename is in this card.

Freeze a second, tool-only boundary probe per Java corpus if source inspection
finds an unsupported construct in the first 50 candidate files: choose the first
by the same ordering and cite the capability-matrix rule. Its expected decline
is not an agent score and is not one of the six paired cards. If absent, record
absence and use the existing negative fixtures; do not pretend a known limitation
requires observing semidx output before selection.

Record two separate oracles: source truth for both agents, and expected tool
behavior under the measured producer/capability matrix. Honest unresolved output
can pass the tool check while the agent still has an incomplete task answer.
Inventory existing fixture/test paths for required, forbidden, and unresolved
outcomes. Definition-rename identity loss and retained body-edit identity are
checked only in existing fixtures or the tool-only replay, never in manual scores.

DoD: pinned roots, consent/isolation status, six paired cards and six scripted
cards with reconstructible edits/calls, source and tool oracles, frozen prompts,
and fixture inventory committed. Maintain sub-statuses for local inputs and
agent/client readiness: Stage 1 needs local inputs and may proceed while only
hosted consent or client readiness is blocked. Missing inputs block dependent work.

## Stage 1: Build The Required Local Driver

The current `tests/mcp_stdio_client.zig` uses `std.testing.io`, a fixed 30-second
response deadline, and retains transcript allocations. It has no external-root
CLI. It is evidence for protocol behavior, not the long-run measurement driver.

Implement `src/adoption_measure.zig` (CLI), `src/adoption/stdio.zig` (bounded
subprocess I/O), and `src/adoption/measure.zig` (replay, edit validation, counters,
RSS sampling, and summaries). Add opt-in `adoption-measure` and
`test-adoption-measure` steps to `build.zig`; neither default install, ordinary
tests, hooks, nor MCP launchers may depend on them. The driver uses Zig 0.16.0
and existing OS interfaces only. First measurement target is macOS; RSS comes
from process information for the child pid, in bytes, sampled every 250 ms.
Unsupported platforms or unavailable RSS fail the memory lane explicitly; do
not introduce another runtime or external command dependency silently.

The driver owns local process observation, not graph meaning. Keep production
core/frontends/MCP untouched. Reuse protocol knowledge from the test client,
but do not import `std.testing.io` into the executable or retain unbounded
transcripts. Stream raw local evidence to files and release each parsed response.
Monitor driver and server memory separately; sample the server for product RSS.
Stop if driver RSS grows 256 MiB beyond its post-initialization baseline, and
classify that as a measurement-tool failure rather than a semidx memory result.
If implementation would require production instrumentation, stop and revise
this scope before adding it. This is an existing consumer pattern under ADRs
005/014, not a new graph or public-interface decision.

Required interface (planned, not an existing command):

```text
zig build adoption-measure -Doptimize=ReleaseFast -- \
  --manifest <manifest.json> --roots <local-roots.json> \
  --server <immutable-semidx-mcp> --mode probe|replay|memory --output <directory>
zig build test-adoption-measure -Doptimize=ReleaseFast
```

Manifest v1 must supply corpus ids/hashes, card parameters, edits, binary hash,
protocol era, and the fixed budgets below. Reject missing fields, unknown mode,
out-of-root paths, wrong initial/final hashes, non-disposable writable roots,
or a different binary before a mutation. Use canonical MCP templates below,
not transcripts captured from successful agent sessions. Resolve entity ids
fresh by `(path, name)` in each process; reject ambiguity. Scripts never feed
an agent's answer into the tool oracle.

Output one record per operation: corpus/card/block/repetition, initial/final
source state, monotonic duration in ns, request/response wire bytes, tool error
category, sampled server/driver RSS, process exit, and complete/censored reason.
No source body is returned by MCP. Keep complete local stdout/stderr, validate
protocol and consume both streams through exit, with a five-second shutdown
deadline then kill and reap. Summary uses nearest-rank quantiles on sorted
successful durations: index `ceil(p*n)-1`; report n and all failures beside them.
Never replace timeouts by their limit in latency percentiles.

Verify malformed JSON, unexpected EOF, late crash, hung child, wrong edit hash,
root escape, missing RSS, binary mismatch, and bounded transcript retention with
small synthetic subprocess inputs. Pin p50/p95 expected values on known numeric
samples. Then replay a real fixture root, including edit/mismatch/sync, over
both supported MCP eras. Run `zig fmt --check build.zig src tests`, driver tests,
`zig build test -Doptimize=ReleaseFast`, and the preview gate after build edits.
Record that ordinary lanes do not depend on the driver. Freeze driver commit
and executable hash; its build must not overwrite the measured server artifact.

DoD: committed driver and tests, interface/format v1 implemented, exact commands
and passing checks in the report. No external timed runs before this stage passes.

## Stage 2: Paired Sessions, Capacity Probe, And Replay

### Common Resource Limits

Budgets are measurement safety limits, not product guarantees. Run one server
profile at a time. For every root, including Camel: startup/first response at
most 180 seconds; each later request at most 30 seconds; shutdown at most five
seconds; each replay card at most 20 minutes including resets/startup; all replay
cards at most four hours. Each agent session has 15 minutes total including tool
waits. Initial RSS ceiling is `H = min(25% of physical RAM, 8 GiB)` for a server;
record physical RAM and H before launch. Stop/reap on limit, crash, protocol
failure, or unmeasurable RSS. Preserve the last result and label censored.

Probe each root before full replay: initialize, sync, full health, and inspect
source diagnostics. The current `src/source/scan.zig` defaults include 20,000
units, 4 MiB per file, and depth 64. Camel's 27,326 tracked Java files exceed the
unit budget before exclusions; completeness must be measured, not assumed.
Compare discovered paths/counts and diagnostics with the frozen Git inventory
and default exclusions. `in_sync` alone does not prove an untruncated repository.
Enumerate admitted paths through paged repo_map results during the untimed probe,
keeping scan diagnostics separate from frontend analysis diagnostics.

A capacity limit or incomplete Camel index is a valid capacity result. Stop its
normal replay and report `capacity_limited` with admitted/omitted counts and
reason, not full-root timings or a smaller replacement root. Do not raise server
limits here. Repeat a failure once on the same input to confirm it, then stop
that profile; do not repeat 35 failed initializations. A missing dependency or
input is instead `environment_blocked`, not a product failure. Independent roots
continue. A reproducible product limit can complete the attempted capacity lane
but forbids the final no-intervention verdict. Incomplete Petclinic/Dubbo tool
results stay labeled; paired sessions may fall back to manual work.

### Canonical Replay

Freeze protocol era, compact detail, `max_response_bytes=32000`, and all path/name
arguments in cards.json before timing. Initialize outside each warm sequence.
Use these three templates for each root, binding its own target and scope:

| Card | Timed operations in order |
| --- | --- |
| Locate | sync; outline(scope); repo_map(target file); find_definitions(path, name). |
| Impact | sync; find_definitions(path, name); references(entity_id, incoming, limit=100, mention_limit=50); context(entity_id, depth=2, relationship_limit=50). |
| Edit | Apply the card's edit outside timing after baseline sync; context(old entity_id) must refuse mismatched state; sync; find_definitions(path, name); context(newly resolved entity_id, depth=2, relationship_limit=50). |

Perform an untimed baseline sync and target lookup before each edit block so
the old entity id is defined. An expected mismatched-state tool rejection is a
successful negative check whose duration is retained. An unexpected tool/RPC
error makes that sequence incomplete and is excluded from success percentiles.
All results include errors and truncation. A truncated result is not complete
impact evidence; report its flags rather than adding unplanned pages. Scope
filtering for source scores is done by the evaluator, never by silently changing
the server's visibility rules. Tool-only edit checks compare body-edit entity
identity and source state; these do not enter manual-versus-assisted scores.

Per card run two independent server blocks. Each block has five warmups then
15 measured repetitions (30 measured, ten warmups total). Before every edit
repetition, restore original bytes and sync in the same server outside timing;
verify the baseline source identity, then apply the same fixed edit. Use no new
names in latency replay. Restart only between blocks; report RSS and the first
and last five timings so accumulated state is visible. Do not claim repeats are
independent fresh indexes. Three separate fresh processes per root measure
startup alone. Startup includes spawn through first successful full health.
OS-cold cache is not claimed. Report per-call/sequence p50/p95 and wall time,
with reset/startup overhead separately and a censoring reason where needed.

### Agent Scoring And Symmetric Accounting

Run the six cards x two variants x two repetitions, using Stage 0's isolated
profiles. No hindsight changes to prompts, target, time allowance, or oracle.
After a terminal answer, the evaluator marks every required source item present,
missing, or wrong. Deduplicate by `(source path, occurrence byte range, declared
target)` for calls; report TP, FP, FN, precision, and recall for card 2. Forbidden
or unproven targets asserted as facts count as FP; a clearly labeled uncertain
candidate is not FP and does not satisfy a required fact. Out-of-scope facts do
not earn credit and count toward bytes. Empty-result metrics use explicit n/a.

A fully correct answer contains all required items, correct current locations,
and no false definite claim. An incomplete but honest answer is `partial`;
any false definite claim is `incorrect`, even with high recall. Timeout is its
own outcome. Source-oracle uncertainty blocks scoring, rather than crediting the
tool. Label tool expectation separately: correct fact, honest decline, false
fact, stale-as-synchronized, or unobserved. An agent's wrong claim is not
attributed to semidx unless the recorded tool response actually made it.

First useful answer is the earliest user-visible answer containing one required
item with valid location evidence and no false definite claim in that answer;
raw search/tool output is not an answer. Record its timestamp or absent.
Final task completion time ends at the fully correct terminal answer; retain
elapsed-to-stop for partial/incorrect/timeouts without calling it completion.

For BOTH variants count search operations, file-read operations, source bytes
returned to the model including repeated reads, all tool-result bytes, and
actual input/output tokens when exposed. Keep wire bytes separate from
model-visible bytes. If model visibility is unavailable, mark that metric unknown
and do not use it to claim context savings. Assisted records additionally include
MCP calls, retries, manual fallbacks, and no-use/misuse episodes. Compare per card
and per corpus; never combine byte counts with token counts or hide task failures
behind a mean. This sample cannot establish statistical significance or universal
adoption benefit. A manual win on Petclinic is a valid corpus-specific result,
not evidence that semidx has no value everywhere.

DoD: all 24 sessions scored or explicitly blocked; completed/censored replay
records for all eligible roots and capacity outcomes for ineligible roots. A
blocked required lane prevents whole-plan completion; an observed product failure
does not disappear from the denominator.

## Stage 3: Client Visibility And Bounded Memory History

These lanes require Stage 1 and applicable Stage 0 inputs, not Stage 2 completion.

**Clients.** Use the maintained stdio fixture client as transport control and
Claude Code plus Codex CLI at frozen versions as the real clients. For each,
record effective protocol/tool configuration and show whether the model receives
text, structured content, or both using a sanitized model-input trace where
available. UI display or a model's assertion is not proof of its input. Record
unobservable separately; it does not satisfy Follow-up 010's visibility question.
Unavailable clients or consent block that lane; do not substitute a mock.

Use the same pinned Petclinic lookup/context/map calls for all clients; if its
results are too small use the same Dubbo call for size probes. Test response
budgets 4,000, 16,000, and 32,000 bytes within existing schema bounds. Record actual
wire/visible sizes, warnings, truncation, spill and follow-up reads. If no threshold
is hit report the largest observed size. Lack of model-input visibility prevents
fallback changes and leaves Follow-up 010 open. It may be reported as a completed
observation of the limit of observability for this plan, but no-intervention and
model-context-savings claims remain unavailable. Installing a second client or
changing authentication requires its own explicit authorization if not already
provided; current binary presence does not prove readiness.

**Memory.** Use Dubbo in a fresh server for each of two churn runs and one control
run. After startup and five unchanged syncs, take five 250-ms RSS samples; their
median is B. Record live and retained counts as exposed by full health, separately
from RSS; if health cannot distinguish them do not invent a live-only count.
Memory run cap is `min(H, B + max(B, 512 MiB))`. If headroom under H is below
128 MiB, mark the run capacity-limited before churn. An absolute host safety cap
remains necessary even though the growth allowance is baseline-relative.

One cycle has exactly six syncs, each after one mutation: (1) apply a fixed-size
body edit; (2) restore; (3) create a temporary unit with a fresh six-digit name;
(4) remove it; (5) move an existing file to a fresh equal-length name unchanged;
(6) move it back. The manifest supplies valid source/path generation recipes and
all pre/post hashes. End every cycle at the initial byte/path state. Fresh names
exercise retained history at bounded live size. Control runs six unchanged syncs
per cycle, using the same observation schedule and no mutations.

Run at most 1,000 cycles per run, 45 minutes per run and 135 minutes for the lane;
all request/RSS limits still apply. Full health at baseline and every 100 cycles
is outside the six-sync count; record its own cost. Restore before shutdown and
compare with a fresh server on the identical starting tree. Stop on cap/crash or
time limit, preserve counts, and mark censored; do not restart to hide growth.
Compare churn growth with control and fresh-process RSS. Repeated excess growth
above `max(25% of B, 128 MiB)` in both churn runs, after subtracting the control's
end-minus-baseline growth from each churn run's end-minus-baseline growth,
triggers an allocation-study candidate, not a claim that RSS proves a leak.

DoD: per-client wire and model-visibility evidence or explicit unobservable status;
all three memory runs complete or documented product censoring; environment
blockers stay open. Never claim a long-session pass from an early censored run.

## Stage 4: Numerical Decision Rules And Closure

The following are predeclared practical selection rules, not statistically
significant effects, product SLOs, or measured facts. Do not tune thresholds after
seeing results; a changed threshold starts a separately labeled experiment.

1. A source-proven false tool fact, stale answer labeled synchronized, or
   reproducible crash interrupts normal ranking. Preserve the reproduction,
   stop relying on affected answers, and select correctness/recovery first.
   Do not confuse an agent FP with a false graph fact.
2. A repeated capacity limit, failed complete Camel probe, or memory cap selects
   capacity/lifecycle investigation ahead of ordinary semantic expansion.
3. For a card, a task-level gain/loss is repeatable when BOTH repetitions show
   the same direction and either: full completion is gained/lost; completion
   time differs by at least 20% AND 30 seconds; or visible source/tool bytes
   differ by at least 25% AND 16 KiB without worse completion. Never mix metrics
   to satisfy a threshold. Unknown bytes cannot earn byte savings. Count avoided
   searches/reads as secondary evidence, not a hidden alternate success rule.
4. Prioritize missing source relationships by repeated completion failures or
   fallback cost; distinguish coverage, latency/output, and workflow misuse.
   Installation is not measured here and cannot be selected on claimed install
   improvement. Setup blockers may motivate a provisional setup experiment only.
5. Operational investigation is eligible when any complete root has startup
   over 60 s, a graph-read p95 over 1 s, an unchanged sequence p95 over 3 s, or
   changed-sync p95 over 3 s. The repeated memory-growth rule is in Stage 3.
   Attribution requires actual profile evidence; without it select a bounded
   diagnostic experiment, not a guessed watcher or string-pool rewrite.

Rank qualifying candidates by reproduced correctness/capacity severity, then
number of cards whose completion is recovered, then repeated time/byte savings,
then estimated effort. Ties or contradictory repetitions produce one bounded
experiment with an explicit competing hypothesis and stop rule, not an indefinite
baseline extension. Repeated lack of semidx use is workflow evidence even if the
agent solved the question manually.

A no-intervention decision is allowed ONLY when all required lanes have evidence,
all six assisted cards are fully correct in both repetitions, there is no
repeatable regression, at least two cards show repeatable gains under rule 3,
all eligible roots meet rule 5's budgets, Camel is complete, the memory runs
complete without the growth trigger, and client visibility has no unresolved
compatibility issue. Otherwise select a corrective/diagnostic successor, or
report blocked/inconclusive rather than declaring that nothing needs work.

Prepare one successor with affected files, authority/ADR needs, required and
forbidden behavior, replay cases, numerical target, verification, and readiness
state. A provisional draft may be prepared from completed lanes while others
are blocked, but it cannot authorize fallback changes, launch implementation,
or close this plan without the missing evidence. With an observed product
capacity failure the plan can close with that corrective successor; with missing
inputs it remains blocked. Unobservable client input can close only with a
bounded visibility experiment, not with a fallback change or no-intervention.

For a semantic successor use: observed task gap -> minimal fixture -> required,
forbidden, and unknown outcomes -> accepted decision if needed -> narrow change
-> original task replay -> scale regression. Follow-up 020 still governs external
shape admission. JUnit/Spring enter only for a named question current corpora do
not exercise; JabRef needs a distinct task. Pin their commits and expected
answers before use. They are not extra work in this plan. Large external runs
remain stage evidence, not mandatory network-dependent build gates.

Closure: update report, roadmap and MEMORY with one supported next action; mark
plan completed/historical only when its evidence lanes have valid outcomes.
Record exact command exits, censored runs, missing metrics, remaining follow-ups,
and coherent commits. No push is part of execution. No source runtime work or
measurement has been performed by this plan revision.

## Review Disposition And Verification Of This Revision

The previous readiness claim was withdrawn: it omitted executable procedures.
The following dispositions address the external review, not completed runtime
measurements. Plan readiness now covers the procedure; environment readiness
and the new driver's implementation remain Stage 0/1 outputs.

| Review item | Disposition and correction |
| --- | --- |
| 1: No thresholds | Accepted. Stage 4 fixes practical gain/loss, resource, and no-intervention rules; two repeats never imply statistical significance. |
| 2: No scoring / mixed oracles | Accepted. Source truth scores both agents; tool expectations are separate, with FP/FN, partial, and first-useful definitions. |
| 3: Asymmetric edit | Accepted. One body-only external edit for both agents; identity and rename checks are tool-only. |
| 4: Consent | Accepted gap. Applies before both variants and client probes. Hosted execution is not mandatory; local matching models remain possible. |
| 5: Isolation | Accepted. Frozen prompts/configs, disposable profiles, effective-policy probes, and a blocked state if inherited policy cannot be excluded. No global settings edited. |
| 6: Camel limits | Accepted, with additional discovered 20,000-unit budget. Probe completeness first; capacity failures cannot masquerade as full-root timings. |
| 7: Driver | Accepted. Required Stage 1, named Zig files/build steps, interface, replay templates, RSS, output schema and tests. |
| 8: Three/six | Accepted. Three card types on each of two task corpora = six paired cards = 24 sessions; six more cards are replay-only. |
| 9: Lost artifacts | Accepted. Commit reconstruction recipes and exact calls/prompts, not just digests; keep raw/private logs local. |
| 10: Selection | Accepted. Fixed candidate ordering, finite search, explicit rejection rules; separate tool-only coverage probe. |
| 11: Impact scope | Accepted. 20 files, 64 KiB, 1-10 proven in-scope occurrences; no completeness claim beyond that scope. |
| 12: Unmeasured installation / misuse | Accepted. Remove installation from measured benefit categories; record workflow non-use/misuse. |
| 13: Correctness escalation | Accepted. First rule of Stage 4, distinguished from agent hallucination. |
| 14: RSS / cycles | Accepted in part. Baseline-relative growth plus host safety cap; six syncs per cycle and a lane time cap. An absolute safety limit is still required. |
| 15: Edit process lifetime | Accepted. Same server within blocks, two fresh blocks, fixed edits, explicit reset/RSS/drift records. |
| 16: Build identity | Accepted. Full commit, parser inputs, mode and executable hash; immutable binary shared across variants. |
| 17: Control snapshot | Accepted. One frozen starting source copy, transport/driver control only, no Java-quality equivalence claim. |
| Client visibility, byte asymmetry, provisional successor | Accepted. Named clients, observed versus unobservable model input, symmetric bytes, and explicit partial-evidence drafting rules. |
| Plan vocabulary and launcher | Accepted. Plan-local terms; bypass mutable launcher via the pinned artifact path. |
| Petclinic will almost certainly favor manual | Not established. Keep either outcome; report by corpus without predicting the winner. |

Source checks in preparation: semidx located the test client and scan budget;
exact reads confirmed test-only I/O, retained transcripts, fixed timeout, mutable
launcher resolution, and discovery defaults. Global semidx-first instructions
were observed; the reviewer's two hook rejections were not independently replayed.
They are not needed to justify an explicit isolation preflight. Client version
commands proved binary presence only. No hosted session or external indexing ran.

Review verification: relative links/frontmatter, arithmetic and lane/stop-state
consistency, `git diff --check`, staged guards, and source-of-truth alignment.
SPEC/CORE/CONFORMANCE/capability matrix keep their existing semantics; no new kind,
contract, coverage, persistence, or outbound permission is admitted. The developer
driver remains an opt-in consumer. At implementation use `semidx-test-design`
for its lifecycle, malformed-input, timeout, edit and quantile checks, then the
Stage 1 commands. Follow-up 010/017 are not closed by writing this plan.
