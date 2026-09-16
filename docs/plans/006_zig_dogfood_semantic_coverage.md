---
title: "Zig dogfood semantic coverage"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "ready_for_execution"
updated: "2026-09-16"
---

# 006: Zig Dogfood Semantic Coverage

## Goal

Make semidx materially better at explaining its own Zig implementation while
preserving the product promise: exact when it knows, honest when it does not.

The plan extends the Zig frontend only where the current source tree and
fixtures provide exact evidence. It is not a general Zig language-support push.
The intended user value is that a local agent can ask semidx about `src/root.zig`
and `src/mcp/` and get useful definition, caller, and context answers before
falling back to direct file reads.

## Start Rule

Start this plan only after Plan 005 is completed or explicitly superseded. Plan
005 owns `v0.1.0-preview.1` release readiness; this plan is the next semantic
coverage step after that preview lane.

## Scope

- Add dogfood-driven Zig frontend coverage for semidx's own code patterns.
- Cover top-level container member functions as definitions when identity can
  be established without position-derived ids.
- Add exact same-repository Zig call facts for the smallest safe qualified-call
  subset.
- Preserve unresolved designators and diagnostics for every call shape outside
  the new exact rules.
- Update fixtures, tests, capability matrix text, and MCP dogfood expectations
  to show the new coverage and its remaining limits.

## Non-Scope

Do not add `module` or `IMPORTS`, publish a semantic contract version, introduce
package/build.zig import semantics, implement dispatch, resolve arbitrary field
or method calls, analyze local variables as definitions, add persistence, change
MCP transport, or make MCP decide graph semantics.

Do not treat textual name matches, path similarity, import string similarity, or
tree-sitter node ids as semantic facts. If a qualified call cannot be traced to
a graph-established definition through declared frontend evidence, keep it
unresolved.

Do not fix broad Zig grammar gaps opportunistically unless the fix is required
for the stages below. Logical-negation calls and empty-container parser behavior
remain follow-up inputs unless a stage explicitly adopts them with tests.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  sections 1, 3, 4, 5, 6, 7, and 8.
- [SPEC.md](../../SPEC.md), especially coverage, public-contract lifecycle, and
  unresolved/public-surface distinction.
- [CORE.md](../../CORE.md), for the accepted unversioned meanings of
  `definition`, `DEFINES`, `REFERENCES`, and `CALLS`.
- [CONFORMANCE.md](../../CONFORMANCE.md), especially graph authority, stable
  identity, incremental maintenance, and honest degradation scenario families.
- [Product adoption strategy](../design/002_product_adoption_strategy.md),
  especially dogfood proofs and the agent habit loop.
- [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md), which admits
  the current Zig frontend and local MCP preview.
- [Preview capability matrix](../spec/capability_matrix.md), for current
  producer behavior and limitation language.
- [Follow-up 001](../followups/001_zig_logical_negation_calls.md).
- [Follow-up 002](../followups/002_zig_empty_container_grammar.md).
- [Follow-up 006](../followups/006_zig_cross_unit_and_member_calls.md).

## Current Evidence

Current MCP health over this repository reports product version
`0.1.0-preview.1`, `semantic_contract_version: null`, 56 source units, 37 Zig
units, 395 definition entities, 1,154 current fact assertions, 1,541 current
unresolved assertions, and 160 unsupported-construct diagnostics. The Zig
producer declares only top-level `fn` and top-level container definitions plus
same-unit bare calls; container members and cross-unit qualified calls are
unsupported or unresolved.

That is honest and constitutionally healthy, but it limits the first audience:
coding agents working on semidx mostly need `src/root.zig`, `src/mcp/root.zig`,
`src/mcp/tools.zig`, and the frontend modules, where useful behavior is often
inside containers or behind qualified names.

## Plan-Level Decisions

**Dogfood coverage leads breadth.** Add Zig rules only when they improve
semidx-on-semidx workflows and can be tested on representative fixtures.

**Container member functions may become definitions.** A function declared
inside a covered top-level container may be a `definition` with Zig extension
vocabulary and a `container_path`, provided identity evidence is based on
allocated unit scope, language, role, name/signature if present, and containment
names, never on byte ranges.

**Qualified cross-unit calls start with local file imports only.** A call like
`alias.foo(...)` may become a fact only when `alias` is a top-level `const`
directly bound to `@import("relative/path.zig")`, the imported unit is indexed,
and `foo` resolves to exactly one covered callable definition exported by that
unit under the implemented visibility rule. All other qualified calls stay
unresolved designators.

**Dependencies are mandatory for external targets.** Every resolved cross-unit
call declares the provider unit dependency, and integration must continue to
reject external targets that are not current graph-established definition
facts.

**No new core kinds.** Zig import aliases, container names, visibility, and
construct kinds remain extension labels, diagnostics, dependencies, or
frontend-local analysis context.

## Architecture Boundaries

1. `frontends/zig`
Responsibility: translate covered Zig syntax into frontend batches, extension
labels, diagnostics, and declared dependencies.
Does not know about: MCP rendering, filesystem scans beyond the source unit and
analysis context, storage layout, or public contract publication.

2. `frontends/root` and `Index`
Responsibility: provide graph-backed analysis context and integrate declared
dependencies through the existing frontend contract.
Does not know about: Zig grammar details beyond frontend capabilities.

3. `core/contract` and `core/reconcile`
Responsibility: enforce that external targets are graph-established facts and
that dependencies accompany them.
Does not know about: Zig import syntax or MCP tool convenience.

4. `mcp`
Responsibility: render the improved graph assertions as existing tool results.
Does not know about: why a Zig frontend rule resolved a call.

5. `fixtures` and `tests`
Responsibility: prove exact facts, unresolved cases, identity behavior,
invalidation, and dogfood usefulness.

## Stages

### Stage 1: Coverage Probes And Fixture Design

Purpose: turn semidx's real Zig patterns into bounded test fixtures before
changing behavior.

Likely files:

- `fixtures/vertical-slice/zig/*.zig`
- `fixtures/vertical-slice/zig/edits/*.zig`
- `tests/vertical_slice_test.zig`
- optionally a focused helper under `tests/`
- `docs/reports/006_zig_dogfood_semantic_coverage_progress.md`

Required behavior:

- Add fixtures for top-level container member functions, nested containers that
  remain unsupported, top-level `@import` aliases, qualified calls through a
  resolvable import, qualified calls through unresolved values, and ambiguous
  targets.
- Record expected facts and unresolved assertions in tests before or with the
  first implementation slice.
- Capture at least one representative semidx source pattern from `src/mcp/` or
  `src/root.zig` in dogfood expectations.

Done when:

- The fixtures distinguish exact facts from unresolved designators and
  unsupported constructs.
- The baseline test expectations describe the intended new coverage and fail on
  the current implementation for the behavior this plan will add.

### Stage 2: Container Member Function Definitions

Purpose: let repository maps and context tools see the functions where semidx's
own implementation actually lives.

Likely files:

- `src/frontends/zig.zig`
- `tests/vertical_slice_test.zig`
- `docs/spec/capability_matrix.md`

Required behavior:

- Emit definition facts for functions declared directly inside covered
  top-level containers.
- Attach `container_path` and Zig extension labels without widening the shared
  core.
- Emit `DEFINES` from the container definition to the member function when the
  container is covered and current.
- Preserve body-edit identity for member functions and observable identity loss
  for renames or containment changes.
- Continue reporting unsupported nested declarations rather than silently
  dropping them as confirmed absence.

Done when:

- `semidx_repo_map` or `semidx_context` can expose member functions in focused
  source units without making container members top-level definitions.
- Fixture tests prove identity preservation and loss cases.
- Existing Java and Clojure tests still pass unchanged.

### Stage 3: Local Zig Import Alias Context

Purpose: prepare exact cross-unit call resolution without adding a module model.

Likely files:

- `src/frontends/zig.zig`
- `src/frontends/root.zig`
- `src/core/contract.zig` only if the existing external-target contract needs a
  narrow reusable helper
- `tests/vertical_slice_test.zig`

Required behavior:

- Detect top-level `const alias = @import("relative/path.zig");` declarations
  when the string names one indexed Zig source unit under the same root.
- Make that alias available only as frontend analysis context for the current
  unit.
- Record no `IMPORTS` or `module` core relationship.
- Keep missing, non-relative, package, builtin, dynamic, duplicate, or otherwise
  ambiguous imports unresolved or unsupported with actionable diagnostics.

Done when:

- A fixture can distinguish a resolvable local import alias from import shapes
  this plan declines to resolve.
- No public result claims an import relationship as a fact.

### Stage 4: Exact Qualified Call Facts

Purpose: add the smallest high-value cross-unit Zig `CALLS` facts.

Likely files:

- `src/frontends/zig.zig`
- `src/core/reconcile.zig` only if needed to preserve existing external-target
  validation clarity
- `tests/vertical_slice_test.zig`
- `tests/mcp_dogfood_test.zig`

Required behavior:

- Resolve `alias.foo(...)` as a `CALLS` fact only when Stage 3 established
  `alias`, the provider unit has exactly one current covered callable
  definition named `foo`, and every required visibility/coverage condition is
  satisfied.
- Declare the provider dependency for each external target.
- Reanalyze dependents when the provider adds, removes, renames, or changes the
  relevant exported callable.
- Keep member calls, value receiver calls, package imports, duplicate names,
  unsupported visibility, and uncertain call shapes unresolved.

Done when:

- A cross-unit Zig call fixture produces a current fact with producer,
  resolution, freshness, evidence, and provider dependency.
- A provider rename or removal updates the dependent without editing it.
- A provider body edit preserves identities and does not force unrelated units
  to reanalyze.

### Stage 5: Dogfood And Documentation

Purpose: prove the new coverage on semidx itself and make the limits visible.

Likely files:

- `tests/mcp_dogfood_test.zig`
- `docs/spec/capability_matrix.md`
- `docs/mcp/local_preview.md`
- `MEMORY.md`
- `docs/reports/006_zig_dogfood_semantic_coverage_progress.md`

Required behavior:

- Add dogfood checks showing at least one useful semidx-internal Zig definition
  or call now appears where it was previously unsupported or unresolved.
- Record output-size and latency observations, but do not turn them into
  product benchmarks.
- Update capability and local preview docs to state the exact new Zig subset and
  the remaining false negatives.
- Update follow-up statuses only for the portions actually resolved.

Done when:

- `zig build dogfood` demonstrates the new coverage on a copy of this
  repository.
- The docs still state `semantic_contract_version: null`.
- The plan's progress log records exact verification, residual risks, and any
  deferred cases.

## Verification Strategy

Run focused checks first, then the full lane required by the stage:

- `./scripts/check-zig-version.sh`
- `zig build test-core`
- `zig build test`
- `zig build test-mcp`
- `zig build dogfood`

Use mutation-style sanity checks when practical: a deliberately ambiguous import
or duplicate target must fail to become a fact, and a provider change must
reanalyze only the affected dependent region.

## Definition Of Done

- New Zig facts are graph-established and carry resolution, freshness, producer,
  and evidence.
- Unimplemented Zig semantics remain unresolved or unsupported, not absent or
  approximate.
- Identity behavior is tested for member functions and cross-unit call targets.
- Dependency invalidation is tested for provider edits that affect dependents.
- MCP tools expose the new graph values without adding source text by default.
- Capability docs and `MEMORY.md` reflect only implemented behavior.
