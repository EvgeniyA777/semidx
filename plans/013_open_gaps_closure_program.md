---
title: "Open Semantic and Ops Gaps Closure Program"
doc_type: "implementation_plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-07-13"
---

# Implementation Plan: Open Semantic and Ops Gaps Closure Program

This plan sequences the seven currently-open post-roadmap gaps recorded in
`MEMORY.md` → *Known Gaps* and `docs/roadmap-status.md` → *Current Focus* into a
single staged program. Each stage is a self-contained delivery loop:

> **implement → verify → commit → review → fixes → docs update → push**

Uncommitted working-tree changes at program start (memory-freshness hook
tooling: `scripts/check-memory-freshness.sh`, `scripts/git-hooks/`,
`scripts/install-git-hooks.sh`, plus `MEMORY.md` / `RULES.md` edits) were
produced by a previous agent and are assumed already committed and pushed before
Stage 1 begins. If they are still dirty, checkpoint them in a dedicated
`chore:` commit first (do **not** fold them into Stage 1).

## Companion Progress Log

Before or during Stage 1, create `reports/010_open_gaps_closure_program_progress_log.md`
with standard documentation frontmatter and update it as each stage completes
(stage status, changed files / commit hash, verification commands + results,
review findings and their disposition, blockers, skipped checks).

## Ordering Rationale (dependency-first, not gap-number order)

1. **Stage 1 — Split `runtime/adapters.clj`** (gap 2). Structural prerequisite.
   `adapters.clj` is 3029 lines with ~492 per-language references; the language
   modules for Clojure/Java/Python/Lua are still 5-6 line stubs while TypeScript
   is already fully extracted. A clean lane/shared-helper base must exist before
   deeper semantics land, and `plans/012` already prepared the mirrored test
   suite for exactly this refactor.
2. **Stage 2 — Remove tree-sitter external-CLI runtime dependency** (gap 6).
   Parsing lands cleanly in the freshly extracted lane modules.
3. **Stage 3 — Interprocedural / dataflow-sensitive resolution v1** (gap 1). The
   major semantic tranche, built on the clean adapter base from Stage 1.
4. **Stage 4 — Semantic graph query surface** (gap 7). Builds on the stabilized
   semantic model and edge storage from Stage 3.
5. **Stage 5 — gRPC generated stubs** (gap 3). Independent ops hardening.
6. **Stage 6 — Online policy control-plane API** (gap 4). Independent ops.
7. **Stage 7 — Runtime-edge rate limiting** (gap 5). Independent ops.

Stages 5-7 are order-independent among themselves and may be reprioritized, but
should follow the semantic stages so runtime-edge churn does not collide with
resolver changes.

## Per-Stage Delivery Loop (applies to every stage)

Each stage MUST run this loop and record it in the progress log:

1. **Map before implementing.** Use semidx MCP first
   (`create_index` → `repo_map` → `resolve_context` → `fetch_context_detail`) to
   read the exact code shape before editing. Fall back to `Read`/`Grep` only if
   MCP fails (and say so).
2. **Implement** the stage scope with narrow, form-aware Clojure edits. Keep
   patches scoped to one top-level form where possible; run a syntax/compile
   probe after each structural edit.
3. **Verify — narrowest meaningful command first**, then widen:
   - `clojure -M:test` (auto-discovers every `*-test` ns)
   - `./scripts/validate-contracts.sh` when contract/schema surfaces change
   - `./scripts/run-mvp-gates.sh` before declaring a stage green
   - `./scripts/run-benchmarks.sh` and
     `./scripts/run-semantic-quality-report.sh` for any stage touching
     extraction, ranking, resolution, or confidence
   - `./scripts/validate-language-onboarding.sh <lang>` for lane-affecting work
4. **Commit** — group the stage's related changes into coherent commits, staging
   only explicit paths (`git add <file> ...`, never `git add .`/`-A`). Branch off
   first if on `main`. Commit only after verification is green.
5. **Review** — run the stage-gated external reviewer loop captured in
   `notes/2026-07-13_stage-gated-external-reviewer-loop.md` and/or
   `/code-review` on the stage diff. Record every finding.
6. **Fixes** — address accepted findings; re-verify; record fix summary +
   changed files/commit hash + verification results in the progress log. Mark
   rejected/deferred findings explicitly with rationale.
7. **Docs update** — in the same stage:
   - `MEMORY.md` (Current State / Known Gaps / Next Execution Priorities)
   - `docs/roadmap-status.md` (flip the relevant gap and Current Focus)
   - a new ADR under `adr/` (next number **033+**) when the stage sets a
     durable architectural decision
   - refresh CCC artifacts (`docs/code-context.md`, `.ccc/state.edn`) only when
     the stage materially changes architecture: `clojure -M:ccc check --root .`
     then regenerate if stale
   - relevant surface docs (`docs/runtime-api.md`, `docs/mcp-api.md`)
8. **Push** — sequential with commit, never parallel. The pre-push hook runs CCC
   freshness + `scripts/check-memory-freshness.sh`; because every stage updates
   `MEMORY.md`, the freshness gate should pass without bypass. Only use
   `SCI_SKIP_MEMORY_FRESHNESS=1 git push` for a genuinely memory-neutral commit,
   and only after re-checking the update rule.

Do not proceed to the next stage until the current stage's loop is fully closed
and its progress-log entry is written.

---

## Stage 1 — Split `runtime/adapters.clj` (gap 2)

**Goal:** Reduce the adapter hotspot to a thin facade over per-language lane
modules plus one shared-helper namespace, with zero behavior change.

**Current shape:**
- `src/semidx/runtime/adapters.clj` (3029 lines) still owns Clojure, Java,
  Python, and Lua regexes, scanning, and semantic-core logic.
- `src/semidx/runtime/languages/{clojure,java,python,lua,javascript}.clj` are
  5-6 line stubs; `typescript.clj` (668) is the reference for a completed lane
  extraction; `elixir.clj` (126), `css.clj` (173), `html.clj` (128) are real.
- `language_registry.clj` centralizes lane metadata (from `plans/011`).

**Sub-steps (each a commit inside the stage):**
1. Extract shared scanning/line/token utilities used by multiple lanes
   (`slurp-lines`, `unit-end-lines`, `trim-signature`, tail-token,
   call-stop-token handling, tree-sitter availability/config cache) into
   `src/semidx/runtime/languages/shared.clj`. Point existing lanes at it.
2. Move Clojure lane logic (`clj-*` regexes + semantic-core) out of `adapters`
   into `languages/clojure.clj`, mirroring the TypeScript module structure.
3. Repeat for Java, Python, Lua lanes into their modules.
4. Collapse `adapters.clj` into a thin dispatch facade over `language_registry`
   + lane modules; keep `runtime/adapters` as the canonical public facade
   (external callers unchanged).

**Verification focus:** `clojure -M:test` after every sub-step (mirrored suite
from `plans/012` guards behavior), then `./scripts/run-mvp-gates.sh`,
`./scripts/run-benchmarks.sh`, `./scripts/run-semantic-quality-report.sh`, and
`./scripts/validate-language-onboarding.sh` for each moved lane — outputs must be
byte-identical to pre-split baselines (capture baselines before Stage 1).

**Docs:** ADR-033 "Split language-lane extraction out of the adapter facade";
update `MEMORY.md` (facade now thin), `docs/roadmap-status.md` (drop
"split `runtime/adapters.clj`" from Current Focus); refresh CCC.

**Risk:** highest blast radius. Mitigation: pure move, no logic change per
sub-step; benchmark/quality parity is the gate.

---

## Stage 2 — Remove tree-sitter external-CLI runtime dependency (gap 6)

**Goal:** Make tree-sitter extraction work without a runtime dependency on an
externally-installed tree-sitter CLI; keep pinned-grammar reproducibility.

**Current shape:** `scripts/setup-tree-sitter-grammars.sh` pins grammar refs
(Clojure/Java/TypeScript); `tree-sitter-available?` / `tree-sitter-cst` in the
lane layer shell out to the external CLI; `.tree-sitter-grammars/` holds
bootstrapped grammars.

**Sub-steps:**
1. Decide and record the strategy in ADR-034: bundle grammars + invoke via an
   embeddable binding, or vendor a self-contained CLI, or formalize graceful
   regex-fallback as the guaranteed default with tree-sitter as an explicit
   opt-in. Prefer the option that removes the *hard* external dependency while
   keeping regex fallback as the safety net.
2. Implement the chosen path in `languages/shared.clj` tree-sitter helpers.
3. Ensure clean degradation + a diagnostic when the accelerated path is
   unavailable (no silent fallback — surface it).

**Verification:** run the suite with tree-sitter path both available and forced
unavailable; parser-mode parity (regex vs tree-sitter) must hold for TS/Java/Clj.
`./scripts/run-semantic-quality-report.sh` for extraction parity.

**Docs:** ADR-034; `MEMORY.md` Known Gaps (tree-sitter dependency line);
`docs/roadmap-status.md`; update the grammar-bootstrap section of surface docs.

---

## Stage 3 — Interprocedural / dataflow-sensitive resolution v1 (gap 1)

**Goal:** First layer of interprocedural, dataflow-sensitive ownership beyond the
current single-hop, import/owner-aware resolution — built on the clean lane base.

**Current shape:** `runtime/semantic_ir.clj` is the IR between extraction and
resolver narrowing; per-lane semantic-cores do import/owner-aware single-hop
disambiguation; `related_tests` already does one helper-namespace hop.

**Sub-steps:**
1. Define the v1 dataflow scope in ADR-035: which flows (e.g. local variable →
   call-target propagation, return-value threading, parameter-to-call binding)
   and which lanes ship first (Clojure high-confidence lane as reference, then
   at least one non-Clojure lane).
2. Extend `semantic_ir.clj` with the interprocedural edge/flow representation.
3. Implement resolver narrowing that consumes the new IR, keeping ambiguous
   flows conservative (no over-linking) — mirror the existing "conservative
   branch" discipline in the Clojure/Java cores.
4. Recalibrate confidence ceilings only if evidence supports it; otherwise keep
   ceilings unchanged and document the non-bump (as done previously).

**Verification:** new mirrored `*-test` namespaces per lane; new
replay/benchmark ambiguity fixtures under `fixtures/`;
`./scripts/run-benchmarks.sh` and `./scripts/run-semantic-quality-report.sh`
must show no regression and a measurable gain on the new interprocedural cases.
Consider protected replay-case promotion for the hardest new cases.

**Docs:** ADR-035; `MEMORY.md` Current State + Known Gaps (compiler-grade line);
`docs/roadmap-status.md`; refresh CCC.

**Risk:** highest semantic risk. Mitigation: land per-lane behind conservative
defaults; benchmark/replay parity is the gate; split into multiple commits/PRs
per lane if the diff grows.

---

## Stage 4 — Semantic graph query surface (gap 7)

**Goal:** Move persistence graph access beyond the current retrieval-oriented
`query-callers`/`query-callees`/`query-units` toward a small, bounded semantic
graph query capability (multi-hop traversal with contract-valid bounded output).

**Current shape:** `storage.clj` (453 lines) exposes single-hop caller/callee/
unit queries over `semantic_index_call_edges` (in-memory + PostgreSQL).

**Sub-steps:**
1. Specify the query surface + bounds in ADR-036 (traversal depth cap, result
   caps, contract shape). Keep outputs bounded and contract-valid.
2. Add JSON Schema under `contracts/schemas/` + `malli` mirror in
   `src/semidx/contracts/` for the new query request/response.
3. Implement bounded multi-hop traversal in `storage.clj` for both in-memory and
   PostgreSQL backends (parity required).
4. Expose it on the public surfaces only where it fits the staged-retrieval
   contract; keep MCP/library/HTTP/gRPC aligned.

**Verification:** `./scripts/validate-contracts.sh`; storage parity tests
(in-memory vs PostgreSQL, `SCI_TEST_POSTGRES_URL`) — detect/stop/fresh-start the
PostgreSQL instance before running; `clojure -M:test`.

**Docs:** ADR-036; `contracts/` updates; `docs/runtime-api.md` + `docs/mcp-api.md`
if surfaced there; `MEMORY.md` Known Gaps (graph-query line);
`docs/roadmap-status.md`.

---

## Stage 5 — gRPC generated stubs (gap 3)

**Goal:** Replace runtime descriptor-built gRPC messages with generated
Java/Kotlin stubs from `proto/semidx/runtime/grpc/v1/runtime.proto`.

**Current shape:** `grpc_proto.clj` (431 lines) builds messages from descriptors
at runtime; `grpc.clj` is the edge; parity tests are `semidx.runtime-grpc-test`.

**Sub-steps:**
1. Add a protobuf codegen path (build alias in `deps.edn`) producing stubs from
   the pinned `.proto`; record the toolchain decision in ADR-037.
2. Wire `grpc_proto.clj` / `grpc.clj` to the generated stubs while preserving the
   dedicated runtime envelope messages and error-trailer taxonomy
   (`x-sci-error-code` / `x-sci-error-category`).
3. Keep a descriptor fallback only if it does not add silent divergence.

**Verification:** `semidx.runtime-grpc-test` parity; `clojure -M:runtime-grpc`
smoke; error-taxonomy trailers unchanged.

**Docs:** ADR-037; `MEMORY.md` Known Gaps (gRPC stubs line);
`docs/roadmap-status.md`; `docs/runtime-api.md` gRPC section.

---

## Stage 6 — Online policy control-plane API (gap 4)

**Goal:** Add a bounded online policy-management/control-plane surface on top of
the existing server-configured registries + selector-based `resolve_context`
policy lookup, keeping offline governance authoritative.

**Current shape:** `authz.clj` (165 lines) is local file/callback authz;
registries are server-configured; broader online policy-management APIs are
intentionally absent; governance lifecycle (`draft/shadow/active/retired`) is
offline via `clojure -M:eval`.

**Sub-steps:**
1. ADR-038: scope the control-plane (read/introspect registry + guarded
   promote/retire hooks) and its authz boundary; do not bypass promotion gates,
   protected-case checks, or approval tiers.
2. Contract-first: JSON Schema + `malli` mirror for control-plane requests.
3. Implement on HTTP (and mirror on gRPC/MCP as applicable), reusing existing
   governance-tier enforcement and error taxonomy.

**Verification:** `./scripts/validate-contracts.sh`; HTTP/gRPC conformance tests;
governance-gate regression tests (promotion still refuses blocked/regressing
candidates).

**Docs:** ADR-038; `contracts/`; `MEMORY.md` Known Gaps (control-plane line);
`docs/roadmap-status.md`; `docs/runtime-api.md` + `docs/mcp-api.md`.

---

## Stage 7 — Runtime-edge rate limiting (gap 5)

**Goal:** Add optional in-runtime rate limiting on HTTP/gRPC edges as defense in
depth, without displacing ingress/proxy responsibility.

**Current shape:** rate limiting is delegated to ingress/proxy/host; runtime
edges (`http.clj`, `grpc.clj`) have tenant/correlation context but no limiter.

**Sub-steps:**
1. ADR-039: scope an optional, config-gated limiter (per-tenant / per-actor),
   default off, emitting the unified error taxonomy on rejection.
2. Implement as edge middleware on HTTP and gRPC, fed by existing
   tenant/correlation context; surface limiter decisions in usage metrics.
3. Keep it opt-in so the default in-memory/local path is unchanged.

**Verification:** edge conformance tests with limiter on/off; usage-metrics
rollup includes limiter rejections; error taxonomy on 429-equivalent responses.

**Docs:** ADR-039; `MEMORY.md` Known Gaps (rate-limiting line);
`docs/roadmap-status.md`; `docs/runtime-api.md`.

---

## Program Exit Criteria

- All seven Known-Gaps lines in `MEMORY.md` are resolved or explicitly
  reclassified, and `docs/roadmap-status.md` Current Focus reflects the new
  frontier.
- `reports/010_open_gaps_closure_program_progress_log.md` records every stage's
  status, commits, verification, and review disposition.
- ADRs 033-039 (as applicable) capture the durable decisions.
- `clojure -M:test`, `./scripts/run-mvp-gates.sh`, `./scripts/run-benchmarks.sh`,
  and `./scripts/run-semantic-quality-report.sh` are green on the final state.
