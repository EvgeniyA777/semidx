---
title: "MCP preview release readiness"
doc_type: "plan"
lifecycle: "active"
status: "in_progress"
agent_action: "ready_for_execution"
updated: "2026-09-15"
---

# 005: MCP Preview Release Readiness

## Goal

Prepare `semidx` for the first product preview release:
`v0.1.0-preview.1`.

The release is a local MCP preview usable by the maintainer and local coding
agents. It does not publish a stable semantic contract. Its purpose is adoption
readiness: a fresh agent can connect to one installed binary, point it at a
local repository with `--root`, ask graph-backed questions, and understand the
coverage and privacy boundaries without reading the implementation.

The companion progress log is
[docs/reports/005_mcp_preview_release_readiness_progress.md](../reports/005_mcp_preview_release_readiness_progress.md).

## Scope

- Add product-version reporting for the local CLI/MCP preview.
- Define the `v0.1.0-preview.1` release gate and release-note shape.
- Make setup from a clean checkout clear enough for local agent use.
- Keep one built `semidx-mcp` binary usable against many local repository roots
  through `--root`.
- Add or update a visible capability matrix for Java, Clojure, Zig, source
  ingestion, and MCP output.
- Document the source-derived data consent boundary for hosted MCP clients.
- Add reproducible dogfood proof commands over this repository:
  - health;
  - repository map;
  - definition lookup;
  - references/context;
  - refresh and snapshot revision change;
  - unresolved or unsupported diagnostics.
- Record preview limitations and residual risks without turning them into
  stable promises.

## Non-Scope

Do not publish a semantic contract version, create `contracts/` schemas, add
HTTP, persistence, daemon file watching, subscriptions, prompts, resources,
remote services, package managers, installers, CI release automation, or binary
distribution for multiple platforms.

Do not widen language semantics merely to make the preview look better. Zig
logical-negation calls, Zig container/member coverage, Java classpath
boundaries, imports, namespace resolution, method dispatch, fields, and
cross-unit Zig calls remain follow-up work unless a planned proof cannot run
without a narrow fix. Zig cross-unit and member calls are tracked in
[follow-up 006](../followups/006_zig_cross_unit_and_member_calls.md).

Do not make MCP define graph semantics. MCP remains a consumer over published
snapshots.

Do not return source text by default. Do not imply that semidx can control what
a hosted MCP client does after receiving graph values.

Do not create or push a Git tag unless the user explicitly asks to cut the
release after the release gate passes.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  §1, §3, §5, §6, §7, and §8.
- [SPEC.md](../../SPEC.md), especially public contract lifecycle, capability
  matrix ownership, and optional outbound data.
- [CORE.md](../../CORE.md), for the current unversioned shared-core roster.
- [CONFORMANCE.md](../../CONFORMANCE.md), for scenario families this preview
  may cite as evidence without claiming an executable conformance suite.
- [MEMORY.md](../../MEMORY.md), for current implementation reality.
- [Product roadmap](../design/001_project_roadmap.md), especially M5.
- [Product adoption strategy](../design/002_product_adoption_strategy.md),
  especially the agent habit loop, adoption requirements, first public proofs,
  and release story.
- [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md), which admits
  the Zig frontend and local MCP preview.
- [Local MCP preview](../mcp/local_preview.md), which documents the current
  experimental server.
- [Follow-up 004](../followups/004_release_discipline_for_mcp_preview.md), the
  release-discipline input.
- [Follow-up 005](../followups/005_mcp_source_derived_consent_boundary.md), the
  hosted-client consent-boundary input.
- [Follow-up 006](../followups/006_zig_cross_unit_and_member_calls.md), the Zig
  call coverage gap the capability matrix must state.
- [Plan 004 Stage 4 residual risk](../reports/004_zig_frontend_and_mcp_preview_progress.md#residual-risk),
  the source of the refresh-recovery and smoke-timeout requirements.

## Current Implementation Context

- Plan 004 is completed and reviewed. `semidx-mcp` exists under `src/mcp/` and
  is built by `zig build`.
- `zig build mcp -- --root <dir>` starts the local stdio preview.
- `zig build test-mcp` runs MCP tests and a stdio smoke test.
- The server supports `semidx_health`, `semidx_repo_map`,
  `semidx_find_definitions`, `semidx_references`, `semidx_context`, and
  `semidx_refresh`.
- Results carry graph values, resolution, freshness, producer, bounded-list
  truncation metadata, and `semantic_contract_version: null`.
- Source evidence text is excluded unless `--allow-evidence-text` is used.
- There is no persistence, no public schema set, no stable semantic contract,
  and no release procedure.
- `semidx_refresh` replaces the published snapshot only after a successful
  publish, but `Index.applyScan` is not transactional: a failure part-way
  through leaves the in-memory graph partly mutated. Whether a later refresh
  converges or keeps wrong state is not verified. A plausible poisoning path is
  lost invalidation: dependency seeds are computed before mutation, so a retry
  over an already partly applied graph may not reanalyze dependents, and a later
  publish may refuse or misreport state.
- The MCP stdio smoke test reads the child's stdout with no timeout: a server
  that stops answering hangs the test instead of failing it.
- Zig `semidx_references` results are same-unit only; see follow-up 006.

Semantic Code Indexing is required by repository policy when available. If
callable semidx MCP tools are unavailable in the implementation environment,
record that fallback in the progress log and use targeted direct inspection.

## Preliminary Session Evidence

`ccbox` review of real ReaderLens agent sessions suggests that the refactored
local MCP preview improves both successful-call latency and practical
availability, but the evidence is preliminary and must not be treated as a
release benchmark or stable performance promise.

Observed pre-refactor failure modes included `CONNECT_TIMEOUT`, classpath
failure around `semidx/runtime/index_lifecycle`, and semidx-first guard
friction where manual search was blocked before the MCP path produced useful
answers. In those sessions, the effective time to first useful graph-backed
answer was often an error or timeout followed by manual `rg`, `sed`, or file
reading.

Observed post-refactor Codex sessions used the current preview tool loop:
`semidx_health`, `semidx_repo_map`, `semidx_find_definitions`,
`semidx_context`, `semidx_references`, and `semidx_refresh`. Successful-call
latency in the sampled sessions improved from about 105 ms median and 205 ms
p90 to about 26 ms median and 63 ms p90. The practical improvement is larger
than the latency numbers alone suggest because the newer sessions received
usable root, snapshot, definition, context, reference, and refresh answers
instead of falling back after connection or classpath failures.

The same evidence also highlights preview limits that Stage 3 and Stage 4 must
state rather than hide:

- Coverage is uneven across project surfaces. Java navigation is already useful,
  while Docker, YAML, Markdown, README, and plan work still require targeted
  direct inspection.
- The Java graph is intentionally narrow. A recent health result showed many
  more unresolved assertions than fact relationships, and context output still
  exposes unresolved imports, unsupported constructs, fields, comments, and
  type details outside current coverage.
- Old and new MCP tool names can confuse agents. Historical sessions used
  `create_index`, `resolve_context`, `expand_context`, and
  `fetch_context_detail`; the current preview uses the `semidx_*` tools listed
  above. Release documentation and examples must not mix the two loops.
- Claude integration evidence is weaker than Codex integration evidence:
  sessions showed connection timeouts, the classpath failure, and guard friction
  while newer Codex sessions used the current preview cleanly.
- The semidx-first guard needs a smoother unavailable-tool fallback. The rule is
  valuable when MCP answers are available, but it should not force an agent
  through a blocked-command cycle before targeted direct inspection.
- Default MCP output remains a map and navigation layer, not a replacement for
  exact file reads. Source text is absent by default, so editing still requires
  reading the relevant files.
- Agents need an explicit answer-quality cue for mixed tasks. Results expose
  `fact`, `unresolved`, and unsupported states, but the preview should make it
  easier to decide when the graph is sufficient and when direct inspection is
  required.

## Plan-Level Decisions

**The first preview is source-built, not a packaged binary release.**
`v0.1.0-preview.1` is a product tag over the repository and documentation. The
user builds the binary locally with the pinned grammar sources and local
tree-sitter runtime already required by the project.

**Product version and semantic contract version stay separate.** The binary and
MCP server must report `0.1.0-preview.1` as the product version. MCP structured
results must continue to report `semantic_contract_version: null`.

**The preview targets Zig 0.16.0 exactly.** Release work, examples, build
scripts, and generated changes must be verified against Zig 0.16.0. Do not use
Zig APIs from earlier or later releases unless they are checked against that
target.

**The public promise is local, bounded, honest context.** The preview should
optimize for installability, trust, visible limits, and reproducible dogfood
proofs, not for more language breadth.

**Capability claims must be matrix-backed.** README and release notes may point
to supported preview behavior only after a capability matrix states exact
coverage, unsupported constructs, unresolved cases, and known limitations.

**Consent language distinguishes source text from source-derived graph values.**
Default MCP output excludes source text, but graph values such as paths, names,
designators, ranges, diagnostics, and ids are still derived from local source.
Hosted-client examples must say that those values may be forwarded by the
client after the user configures that client.

**A failed refresh must not poison later answers. This is a release blocker.**
`semidx_refresh` is part of the agent habit loop, so trust in it is part of the
preview's promise, not a later improvement. Stage 3.5 chooses the smallest
recovery strategy that makes the guarantee testable; it does not require a
transactional storage layer.

**The release gate must not be able to hang.** The MCP smoke test gets a
bounded timeout and kills its child on expiry.

**Known coverage gaps ship visible, not fixed.** Same-unit-only Zig references
and calls do not block the preview; the capability matrix and release notes
must name them.

**False facts found during this plan are decided one by one.** Probes while
preparing the capability matrix confirmed two same-unit name-resolution rules
that record a `CALLS` fact with the wrong target. The maintainer decided on
2026-09-14, and clarified the same day that incompleteness is acceptable and
false precision is not:

- Java: an unqualified invocation resolves to the first method of that name in
  the enclosing class, so a call to an overloaded method can be a fact about the
  wrong overload. This is fixed in Stage 2.5 and blocks the preview.
- Clojure: a symbol resolves to a same-unit `def`/`defn` of that name even when a
  local binding (for example `let`) shadows it. The frontend must stop producing
  such facts before the preview. Because macros may bind names with any syntax,
  the preview rule suppresses facts wherever a binding cannot be ruled out
  (Stage 2.5). Precise lexical scope for `let`, `fn`, and core macros is deferred
  as coverage work in follow-up 008.

## Stages

### Stage 1: Product Version And Preview Identity

Purpose: make the binary identify the preview release without implying a stable
semantic contract.

Likely files:

- `build.zig`
- `src/mcp/`
- `src/main.zig` only if the developer inspection binary already shares version
  plumbing cleanly
- focused MCP or CLI tests
- `docs/reports/005_mcp_preview_release_readiness_progress.md`

Required behavior:

- Define the product version as `0.1.0-preview.1` in one implementation-owned
  place.
- Expose the product version through `semidx-mcp --version`.
- Include the product version in MCP server identity and `semidx_health`.
- Keep every MCP tool result's `semantic_contract_version` equal to `null`.
- Keep `--help` and existing usage errors unchanged except for any version text
  intentionally added.

Done when:

- A test or smoke check proves `semidx-mcp --version` reports
  `0.1.0-preview.1`.
- MCP health reports the same product version.
- Existing MCP compatibility and no-source-text checks still pass.
- No document describes the semantic contract as published or stable.

### Stage 2: Install And Local Agent Configuration

Purpose: make a fresh local setup path short, explicit, and agent-friendly.

Likely files:

- `README.md`
- `docs/mcp/local_preview.md`
- optional sample config under `docs/mcp/` if the example becomes too large for
  prose

Required behavior:

- Document the clean-checkout path:
  - install Zig 0.16.0;
  - install or point at a local tree-sitter runtime;
  - run `./scripts/setup-tree-sitter-grammars.sh`;
  - run `./scripts/check-zig-version.sh`;
  - run `zig build`;
  - start `zig-out/bin/semidx-mcp --root /path/to/repository`.
- State that the indexed root is the user's local working copy, not the remote
  repository that supplied semidx.
- Provide a minimal MCP client configuration example using absolute paths.
- Explain that the same binary can be reused for different repositories by
  changing `--root`.
- Keep the README concise; put detailed tool behavior in `docs/mcp/local_preview.md`.

Done when:

- A fresh agent can follow the README to a first MCP call without reading
  source files.
- The local preview reference still owns full tool and field details.
- Documentation does not promise binary packages, package-manager installs, CI
  release artifacts, persistence, or stable schemas.

### Stage 2.5: Same-Unit Name Resolution Facts (Java And Clojure)

Purpose: stop the Java and Clojure frontends from recording a fact whose target
the language would not select. Release blocker.

Likely files:

- `src/frontends/java.zig` (`emitInvocations`, `emitInvocation`, `findMethod`)
- `src/frontends/clojure.zig` (`walkForm`, `emitDesignation`, `findDef`)
- `tests/vertical_slice_test.zig` or frontend tests
- `docs/reports/005_mcp_preview_release_readiness_progress.md`

Required behavior:

- An unqualified invocation in a covered method body is a `CALLS` fact only
  when the enclosing top-level class declares exactly one method of that name,
  the class declares no superclass and no interfaces, and the invocation is not
  inside a class, interface, enum, or record body nested in the method (an
  anonymous or local class).
- Every other unqualified invocation stays an unresolved `CALLS` whose
  explanation names the reason: overloads, possible inherited methods, or a
  nested class body. Qualified invocations keep their current behavior.
- Invocations inside lambdas keep the enclosing class's scope and follow the
  rule above.
- The rule narrows facts; it adds no new fact and no approximate assertion.
- Clojure: a symbol is a fact only when it names the unit's one top-level
  `def`-like declaration of that name, it is not a parameter of the enclosing
  definition, the definition has a single parameter vector, and every form
  enclosing the symbol in the body is known to bind nothing. Every other symbol
  stays unresolved with its reason.

Done when:

- A test covers an overloaded name, a class with a superclass, a class with
  interfaces, an anonymous class body, a local class, a lambda, and the unique
  same-class method that stays a fact.
- Mutations restoring the first-by-name lookup and removing the nested-body
  check each make a test fail.
- A Clojure test covers `let` shadowing, a parameter, an unknown macro, a
  duplicate or `defmacro` declaration, a multi-arity definition, and the known
  contexts that keep facts; mutations removing each check make it fail.
- The Java fixture and edit-history tests still pass, or any changed expectation
  is explained in the progress log.

### Stage 3: Capability Matrix And Consent Boundary

Purpose: make trust boundaries visible before the preview is promoted.

Likely files:

- `SPEC.md`
- new SPEC-owned child capability matrix, for example
  `docs/spec/capability_matrix.md`
- `docs/mcp/local_preview.md`
- `docs/followups/004_release_discipline_for_mcp_preview.md`
- `docs/followups/005_mcp_source_derived_consent_boundary.md`
- `MEMORY.md`

Required behavior:

- Add a capability matrix covering:
  - source ingestion;
  - Java;
  - Clojure;
  - Zig;
  - MCP tools and output boundaries.
- For each language or producer, distinguish:
  - facts currently produced;
  - unresolved assertions currently surfaced;
  - unsupported or unavailable coverage;
  - identity limitations;
  - major known false-negative or overbroad cases.
- The Zig row must state that references and calls are same-unit only: calls
  through a namespace, a value, or an `@import` binding stay unresolved
  designators, container members are not definitions and their bodies are not
  walked, so `semidx_references` never lists a caller from another unit. Link
  follow-up 006.
- Link the matrix from `SPEC.md`, README or MCP docs where appropriate.
- Add hosted-client consent wording near MCP configuration examples:
  - semidx itself is local and does not contact the network;
  - a hosted MCP client may forward returned graph values to its service;
  - default output excludes source text;
  - `--allow-evidence-text` adds only recorded evidence text, bounded per claim;
  - semidx cannot enforce a hosted client's onward transmission policy.
- Keep follow-up 005 open unless this stage fully resolves its required
  decisions and tests.

Done when:

- Capability claims in README and MCP docs are backed by the matrix.
- The matrix names same-unit-only Zig references and calls.
- The matrix states the Java and Clojure rules as narrowed in Stage 2.5: Clojure
  calls are narrow, and a symbol under a form that may bind names is not
  resolved as a fact; precise lexical scope is follow-up 008.
- The matrix avoids stable-contract wording.
- Consent wording names both source text and source-derived graph values.
- Default no-source-text tests still pass.

### Stage 3.5: Refresh Failure Recovery

Purpose: make a failed `semidx_refresh` unable to poison later MCP answers or
later refreshes. Release blocker.

Likely files:

- `src/root.zig` (`Index.applyScan` and its upkeep)
- `src/mcp/root.zig` (`Server.refresh`)
- `src/core/graph.zig` only if the chosen strategy needs a graph-level boundary
- focused tests beside the changed modules
- `docs/mcp/local_preview.md` (replace the partial-update limit)
- `docs/reports/005_mcp_preview_release_readiness_progress.md`

Required behavior:

- Before choosing a strategy, read `Index.applyScan`, `Upkeep`, and
  `Graph.publish` and record in the progress log where a failure can leave
  partial state and what that state does to a later refresh and publish. Confirm
  or refute the lost-invalidation hypothesis above with a test, not by argument.
- Choose the smallest local strategy that establishes the guarantee, for
  example staging the scan into a separate index and swapping on success,
  rebuilding the index from a fresh scan after a failure, or another bounded
  rollback boundary. Record the choice and rejected alternatives in the progress
  log. Persistence, a transactional storage layer, and a change to what a
  snapshot is are out of scope.
- After any failed refresh:
  - the published snapshot and every answer from it are unchanged;
  - the next successful refresh publishes a graph equal in facts, unresolved
    assertions, diagnostics, freshness, and unit analysis states to a fresh
    index built from the same tree;
  - no claim about contents the failed refresh half-applied is reported as
    current.
- Identity preservation across a successful refresh keeps its current behavior.
  If the strategy cannot preserve entity identities across a failed-then-retried
  refresh, the result must be observable identity loss, never silent
  reassignment, and the limit must be documented.
- `semidx_refresh` reports the failure as a tool execution error that says
  whether recovery completed.

Done when:

- A failure-injection test fails allocation or analysis at several points inside
  refresh (for example with `std.testing.FailingAllocator` over each allocation
  index, or an injected analyzer error) and, for each point, proves the three
  guarantees above against a fresh-index oracle.
- The test fails when the recovery is disabled (recorded as a mutation in the
  progress log).
- Existing refresh, incrementality, and repository-scale tests still pass,
  including affected-region work bounds on the success path.
- `docs/mcp/local_preview.md` describes the recovery behavior instead of the
  partial-update limit.

### Stage 4: Dogfood Proofs And Release Gate

Purpose: prove the preview's adoption loop on the real semidx repository.

Likely files:

- `docs/reports/005_mcp_preview_release_readiness_progress.md`
- optional script under `scripts/` if repeated manual JSON-RPC commands become
  fragile
- `tests/mcp_smoke_test.zig` (timeout)
- MCP tests only if a proof exposes an untested runtime invariant

Required behavior:

- Give the MCP stdio smoke test a bounded timeout for each response and for
  process exit. On expiry it must kill the child, fail with a message naming the
  request it was waiting for, and still report captured stderr. The bound must
  be generous enough not to flake on a cold Debug build; record the chosen value.

- Record reproducible commands and observed results for:
  - `semidx_health`;
  - `semidx_repo_map` over this repository;
  - `semidx_find_definitions` for at least one Zig definition;
  - `semidx_references` or `semidx_context` around that definition;
  - an edit plus `semidx_refresh` where the snapshot revision changes;
  - at least one unresolved or unsupported diagnostic.
- Capture timing or size notes for the key MCP calls when practical, without
  turning them into release promises.
- Verify stdout contains only protocol messages and no trailing data after EOF.
- Verify default MCP output does not include source evidence text.
- Verify `--allow-evidence-text` remains bounded and accurately described.

Done when:

- The progress log contains enough evidence for a reviewer to reproduce the
  preview's agent habit loop.
- The proof uses this repository, not only tiny fixtures.
- A mutation that makes the server stop answering (for example, never writing
  one response) makes the smoke test fail within its timeout instead of hanging,
  and the child process is gone afterwards.
- The dogfood proof includes a refresh after an injected or induced failure,
  showing the Stage 3.5 guarantee on this repository.
- Any found semantic gap is either fixed by a focused change covered by this
  plan or filed as a follow-up.

### Stage 5: Preview Release Candidate Handoff

Purpose: leave a clean release candidate ready for an explicit tag request.

Likely files:

- `docs/releases/v0.1.0-preview.1.md`
- `docs/reports/005_mcp_preview_release_readiness_progress.md`
- `docs/design/001_project_roadmap.md`
- `docs/followups/README.md`
- `MEMORY.md`

Required behavior:

- Add preview release notes that clearly say:
  - `v0.1.0-preview.1` is a local MCP preview;
  - it is usable by local agents and the maintainer;
  - it does not promise a stable semantic contract;
  - the current install path is source-built;
  - source text is off by default;
  - known limitations are expected and visible, including same-unit-only Zig
    references and calls (follow-up 006) and Clojure symbols left unresolved
    wherever a local binding cannot be ruled out (follow-up 008).
- Run the full release gate from a clean worktree:
  - `./scripts/check-zig-version.sh`;
  - `zig build test-core -Dgrammars-dir=/nonexistent --summary all`;
  - `zig build test --summary all`;
  - `zig build test-mcp --summary all`, with the smoke timeout in place;
  - the Stage 3.5 failure-injection test (part of `zig build test`);
  - `zig fmt --check build.zig src tests`;
  - `zig build run -- src`;
  - full-output MCP dogfood smoke over `--root .`;
  - `./scripts/check-agent-attribution.sh --all`;
  - `./scripts/check-memory-freshness.sh`;
  - `git diff --check`.
- Update the roadmap so M5 reflects the actual final state.
- Mark follow-up 004 completed only if release discipline is now documented and
  evidenced. Mark follow-up 005 completed only if the consent boundary is
  documented and tested to the acceptance direction above.
- Do not create or push the Git tag as part of this plan unless the user gives a
  separate explicit release-cut instruction.

Done when:

- A reviewer can decide whether to cut `v0.1.0-preview.1` from the final commit.
- The progress log records exact commands, results, skipped checks, and residual
  risks.
- The worktree is clean and the final commit is coherent.

## Verification Strategy

- Use narrow tests for version reporting, health output, and source-text
  opt-in behavior.
- Use failure injection against a fresh-index oracle for refresh recovery.
- Use a bounded timeout in the stdio smoke test so the gate fails rather than
  hangs.
- Use existing MCP smoke tests for stdio protocol discipline.
- Use dogfood commands over this repository for adoption proof.
- Use parser-free core tests to preserve the local dependency boundary.
- Use the full test lane to preserve frontend behavior.
- Use documentation gates for attribution, memory freshness, and whitespace.

## Stop Conditions

Stop and update the progress log before continuing if:

- product version reporting requires a broader public CLI contract than this
  plan describes;
- a capability matrix would need to declare a stable semantic contract version;
- a proof can pass only by hiding unresolved, unsupported, stale, approximate,
  or unavailable states;
- hosted-client consent wording would imply semidx controls a third-party
  client's onward transmission;
- release packaging requires platform-specific artifacts, installers, signing,
  package-manager publication, or CI automation;
- refresh recovery can be established only by persistence, a transactional
  storage layer, or a change to what a snapshot is (owned by `SPEC.md`), or it
  would break affected-region work bounds on the success path. Record the
  finding; the preview release stays blocked until a decision is recorded;
- the smoke timeout cannot be implemented without flakiness on the supported
  toolchain.

## Execution Recommendations

- Use Claude Opus 5 or an equivalently strong code-review-capable model for the
  whole plan.
- Keep the stages in order. Stage 2.5 removes known false facts before the
  matrix describes Java and Clojure. Stages 1-3 make the preview legible; Stage 3.5 makes
  refresh trustworthy; Stage 4 proves it; Stage 5 packages the release-candidate
  handoff.
- Review after Stage 3 if the capability matrix or consent language changes
  public claims substantially.
- Review after Stage 3.5: it is the only stage that changes ingestion code.
- Review again before any release tag is created.
