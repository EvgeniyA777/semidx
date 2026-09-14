---
title: "Zig frontend and MCP preview progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-14"
---

# 004: Zig Frontend And MCP Preview Progress

Companion log for
[docs/plans/004_zig_frontend_and_mcp_preview.md](../plans/004_zig_frontend_and_mcp_preview.md).

## Current Status

Plan 004 is complete. Session A (Stages 1–3, the Zig frontend) was reviewed,
Stage 3.5 fixed the review blocker, and Session B implemented Stages 4–5. The
final review of Stages 4–5 found no blocking defects for the local MCP preview
boundary; the remaining source-derived-data consent question is tracked as
[follow-up 005](../followups/005_mcp_source_derived_consent_boundary.md).

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Zig grammar and language registration | Completed (`6bcbbd7`) | `.zig` is discovered as `model.Language.zig`; a pinned `tree-sitter-zig` is fetched by the setup script and compiled in the full lane only; a skeletal Zig frontend reports failed, unsupported, or confirmed-empty analysis and emits no facts. |
| Stage 2: Zig definition facts | Completed (`575bf92`) | Named top-level `fn` declarations and top-level `const` declarations bound directly to a struct/enum/union/opaque expression are current `definition` facts with `DEFINES` from the file. Container members and every other declaration are reported as unsupported. A body edit preserves identity; a rename is identity loss. |
| Stage 3: Zig same-unit simple calls | Completed (`50d68c4`) | Every call expression in a covered function body is recorded as `CALLS`. A bare callee is a fact only when the unit's top level declares that name exactly once, as a covered function, and no parameter, local binding, capture, or `usingnamespace` could give it another meaning; every other callee stays unresolved with its reason. No `REFERENCES` are emitted. |
| Stage 3.5: Graph-owned relationship designators | Completed (`211a529`) | Fixes the review blocker: `Graph.addAssertion` now interns an unresolved target's designator, so no relationship keeps a slice of the frontend batch that produced it. `zig build run -- src` completes. |
| Stage 4: Local MCP stdio preview | Completed (`effbbb7`) | `semidx-mcp` scans a root, publishes a snapshot, and serves six graph-backed tools over stdio to both `2026-07-28` (per-request `_meta`, `server/discover`) and `2025-06-18` (`initialize`) clients through one dispatcher. Evidence text is off by default; refresh swaps in a fully published snapshot or keeps the old one. |
| Stage 5: Dogfood, documentation, and handoff | Completed (`cf04f95`) | `docs/mcp/local_preview.md` documents building, starting, client configuration, both protocol versions, tools, result fields, source-text rules, errors, and limits; `README.md`, `SPEC.md`, `MEMORY.md`, and the roadmap describe what now exists. A client following the document found Zig definitions in `src/` under both protocol versions. |

## Plan Readiness Gate

Re-checked by the implementing agent before Stage 1 on 2026-09-14. The plan
names scope, non-scope, stage outputs, verification commands, and stop
conditions; no hard fail. Result: ready for execution.

## Environment

- The semidx MCP server did not connect in the implementing session
  (connection timeout), so its tools were unavailable. Per
  [tooling policy](../agent-policy/tooling.md#mcp-failure-protocol), code was
  located by targeted direct reads of the files the plan names instead.
- `./scripts/setup-tree-sitter-grammars.sh` needed network access once to clone
  `tree-sitter-zig`. Build and test steps ran offline against the local
  checkout.
- Toolchain: Zig 0.16.0, tree-sitter runtime from `/opt/homebrew` (parser ABI
  15), tree-sitter CLI 0.26.3 (used only to inspect parse trees).

## Risk Matrix (Stages 1–3)

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| `.zig` files become source units (plan Stage 1) | Zig files silently invisible, or build outputs ingested | Unit (discovery) | `source/languages` table read by the walk | Mapping removed; `.zig-cache`/`zig-out` contents; `build.zig.zon` | `a scan finds zig units and skips zig build outputs` |
| Core stays parser-free (ADR 002, ADR 005) | New grammar leaks into `test-core` | Build lane | `zig build test-core -Dgrammars-dir=/nonexistent` | Grammar directory absent | lane command |
| Zig grammar reaches the adapter (ADR 002) | ABI mismatch or missing symbol | Unit (adapter) | `tree_sitter.zig` only | ABI newer than runtime | `the local zig grammar parses through the adapter`, ABI test |
| Degradation stays distinguishable (constitution §3, plan Stage 1) | Uncovered or broken Zig reads as empty | Integration (analyzer + reconcile) | `frontends/root` routing into `frontends/zig` | Unparsable source; only-uncovered source; empty source | `frontends/root.zig` Zig tests |
| Only exact declaration shapes become definitions (ADR 005, plan Stage 2) | A `var`, alias, call, conditional, error set, or container member becomes a definition | Integration (frontend through reconcile) | `frontends/zig.containerDeclaration` token reading | Each non-covered shape listed; mutation dropping the `const` requirement | `only exact zig declaration shapes become definitions`, `declarations inside a zig container are not top-level definitions` |
| Zig identity follows graph evidence, not ranges (constitution §4, plan Stage 2) | Body edit breaks ids, or rename silently retargets | Fixture / edit history | Reconciliation over `IdentityEvidence` | Rename; unparsable edit then repair | `zig/edits/01`, `02`, `03`, `05` tests in `tests/vertical_slice_test.zig` |
| Same-unit calls are exact only under the narrow rule (ADR 003, ADR 005, plan Stage 3) | A name match becomes a fact: member, namespace, builtin, shadowed, duplicated, aliased, or imported names | Integration (frontend through reconcile) | `frontends/zig.decideName` | Field, namespace, and computed callees; parameter, `const`, destructuring, capture, nested fn-type parameter; duplicate; alias; container; import; `usingnamespace`; calls in tests, `comptime`, and nested containers; mutations disabling resolution and shadowing | `a bare zig call resolves only to ...`, `usingnamespace leaves ...`, `a destructuring binding shadows ...` |
| Calls specialize references (CORE.md, plan Stage 3) | One occurrence answers a reference query twice | Fixture | Snapshot reference query | Unresolved calls counted too | `same-unit zig calls are current facts ...` |
| Call freshness and identity under edits (constitution §4, §5, plan Stage 3) | Callee body edit stales callers; callee rename silently retargets | Fixture / edit history | Reconciliation | Callee-only rename (`06`); joint rename (`03`); target appears (`04`) | Zig call edit-history tests in `tests/vertical_slice_test.zig` |
| Java and Clojure unchanged (plan Stage 3) | A shared change alters other frontends | Fixture + full lane | Producer-scoped assertion counts | Zig unit added beside both | `adding a zig unit leaves java and clojure analysis unchanged`, full lane |
| Grammar defects surface as failure, not facts (plan stop condition) | A parse tree repaired with `MISSING` nodes yields guessed declarations | Integration | `root.hasError()` gate | `const Empty = struct {};` | `an empty zig container fails the unit's analysis rather than yielding a guess` |

## Stage 1: Zig Grammar And Language Registration

Changed files: `scripts/setup-tree-sitter-grammars.sh`, `build.zig`,
`src/core/model.zig`, `src/source/languages.zig`, `src/source/discovery.zig`,
`src/frontend/tree_sitter.zig`, `src/frontends/root.zig`, new
`src/frontends/zig.zig`, `tests/vertical_slice_test.zig`.

Decisions taken inside the plan's boundary:

- Grammar source: `https://github.com/tree-sitter-grammars/tree-sitter-zig`,
  pinned to `6479aa13f32f701c383083d8b28360ebd682fb7d` (the `master` head on
  2026-09-14, newer than tag `v1.1.2`). Inspection found no stop-condition
  blocker: MIT license, generated `src/parser.c` committed, no external scanner,
  and `LANGUAGE_VERSION 15`, equal to the runtime's
  `TREE_SITTER_LANGUAGE_VERSION`.
- `build.zig` now keeps one `grammar_checkouts` list for both the prerequisite
  check and compilation, so a grammar cannot be compiled without being checked
  or checked without being compiled.
- The skeletal frontend covers nothing yet, so it never claims confirmed
  absence for a unit that declares something: every top-level construct is
  reported as `unsupported_construct`. Diagnostics are aggregated per node kind
  per unit ("N top-level `variable_declaration` ...") rather than emitted per
  occurrence, because Zig units routinely open with many imports and a
  per-line diagnostic would bury the ones that matter. A unit with no
  top-level constructs (comments only, or empty) reports `confirmed_absence`.
- `build.zig` itself is a `.zig` source unit and is discovered like any other.

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass (61 + 24 tests) |
| `zig build test-core --summary all` | Pass |
| `zig build test --summary all` | Pass, 145/145 (baseline before the plan: 140/140) |
| `zig build run -- src` | Runs; 20 Zig units, 0 definitions, only unsupported-construct diagnostics |
| Negative: `.zig` mapping removed from `src/source/languages.zig` | `zig build test-core` fails; mapping restored |

## Stage 2: Zig Definition Facts

Changed files: `src/frontend/tree_sitter.zig`, `src/frontends/zig.zig`,
`src/frontends/root.zig`, `tests/vertical_slice_test.zig`, new
`fixtures/vertical-slice/zig/greeter.zig` and
`fixtures/vertical-slice/zig/edits/0{1..5}_*.zig`.

Node shapes were read from the pinned grammar before extraction was written
(`tree-sitter parse` on probe files and `grammar.js`), then pinned by tests:

- `function_declaration` exposes its name as the `name` field. A missing name
  is left uncovered.
- `variable_declaration` exposes neither its name nor its value as a field. The
  grammar rule is `[pub] [export | extern [string]] [threadlocal] (const | var)
  identifier [: type] ... [= expression] ;`, so the frontend reads the node's
  tokens in order: the `const` keyword, the first `identifier` child, then the
  first node after `=`. Only when that node is itself a `struct_declaration`,
  `enum_declaration`, `union_declaration`, or `opaque_declaration` is the
  declaration a container. To read the anonymous `const` and `=` tokens the
  adapter gained `Node.childCount` and `Node.childAt`; a test pins the exact
  token sequence of `pub const Greeter = struct {};`.

Decisions taken inside the plan's boundary:

- Roles are `function` and `container`; Zig vocabulary is in the extension
  payload as `zig.construct` (`function` or `container`) and `zig.container`
  (`struct`, `enum`, `union`, `opaque`). No shared-core kind was added.
- Identity evidence carries no signature. Zig has no overloading, so a name is
  unique among one container's declarations; a parameter edit therefore keeps
  the definition's identity. `container_path` is empty because the file is the
  only enclosing namespace covered.
- `extern fn` prototypes without a body and `inline` functions are covered:
  each is a named top-level function declaration.
- Error sets (`error{...}`) are not covered: they are types but not containers,
  and the plan's coverage names containers.
- Declarations inside a top-level container are reported once per node kind as
  "declared inside a top-level container". In Zig they live in the container's
  namespace, which nothing here resolves, so a method named like a top-level
  function is not a second definition of that name.
- `confirmed_absence` is now scoped to covered declarations ("declares no
  top-level function or container") and can stand beside unsupported-construct
  diagnostics, as in the Clojure frontend.

Grammar limitation found (residual risk, not a workaround):

- The pinned grammar parses an empty container body such as `struct {}` or
  `opaque {}` as a `container_field` whose name is a `MISSING` identifier. The
  tree therefore has an error, and the whole unit reports `analysis_failed`.
  The `tree-sitter parse` CLI shows the same tree but exits successfully,
  because it does not count `MISSING` nodes as errors. No later upstream commit
  was available. Per the plan's stop conditions the tree is not repaired by
  guessing; the behavior is pinned by a test so a grammar update that fixes it
  is noticed. None of the 20 Zig units under `src/` hits it today.

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test --summary all` | Pass, 154/154 |
| `zig build run -- src` | 20 Zig units, all current; 173 definitions; 0 unresolved, 0 approximate |
| Mutation: `const` requirement removed from `containerDeclaration` | `only exact zig declaration shapes become definitions` fails; restored |

## Stage 3: Zig Same-Unit Simple Calls

Changed files: `src/frontends/zig.zig`, `src/frontends/root.zig`,
`tests/vertical_slice_test.zig`, new
`fixtures/vertical-slice/zig/edits/06_callee_renamed.zig`.

Node shapes read before extraction (probe files under `tree-sitter parse`):
`call_expression` has `function` and `arguments` fields; a bare callee is an
`identifier`, while `x.foo()` and `ns.foo()` are `field_expression` callees and
`@builtin(...)` is a separate `builtin_function` node. Captures are `payload`
nodes of identifiers; parameters are `parameter` nodes with a `name` field, in
function declarations and in nested `function_signature` types; `const a, var b
= ...` destructuring puts each keyword directly before its identifier in one
`variable_declaration`.

Decisions taken inside the plan's boundary:

- The resolution rule, in order: a parameter or any `const`/`var`/capture
  binding of the name anywhere in the function body leaves the call unresolved;
  a top-level `usingnamespace` leaves every bare call unresolved; otherwise the
  call is a fact only when exactly one top-level declaration of that name
  exists and it is a covered function. Every top-level `const`/`var` counts
  toward that uniqueness, covered or not, so an alias, import, or container of
  the name is not skipped over to reach a function.
- Shadowing is decided without block scoping: a binding anywhere in the body
  counts everywhere in it. Zig rejects locals that shadow container
  declarations, so for code that compiles this loses nothing; for source that
  parses but does not compile, it can only leave more calls unresolved.
- Every call expression in a covered body is recorded, not only resolved ones:
  non-bare callees become unresolved `CALLS` whose designator is the callee's
  source text (`std.debug.print`, `greeter.greet`), as the Java frontend does
  for qualified invocations. Builtin calls record nothing, but their arguments
  are walked, so `@as(u8, helper())` still records `helper`.
- A container expression inside a function body is not walked, and is reported
  once per kind ("inside a function body, whose calls were not analyzed"),
  because inside it a bare name may mean one of its own members. Bodies of
  tests, `comptime` blocks, and container members are not walked at all; they
  are already reported as unsupported declarations.
- The Zig frontend emits no `REFERENCES`: the plan's Stage 3 covers calls only,
  and non-call uses of a name include locals and fields this frontend does not
  model.
- Depth beyond 64 nodes stops the walk and is reported once per unit as an
  unsupported construct. The binding collector stops at the same depth; a
  binding below that depth can only shadow calls that are not recorded either.

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass (61 + 24 tests) |
| `zig build test-core --summary all` | Pass |
| `zig build test --summary all` | Pass, 163/163 |
| `zig build run -- src` | Recorded at the time as passing with 20 current units, 185 definitions, 515 facts, 536 unresolved. **Correction (Stage 3.5):** only the first lines of output were inspected; the command crashed after the summary, as the review below found. The counts were right; "passing" was not. |
| `zig build run -- .` | Recorded at the time as running to completion. **Correction (Stage 3.5):** not actually observed, for the same reason. |
| `./scripts/check-agent-attribution.sh --all` | Pass (exit 0) |
| `./scripts/check-memory-freshness.sh` | Pass (exit 0) |
| `git diff --check` | Pass |
| Mutation: the unique-function branch of `decideName` returns unresolved | 5 tests fail (1 frontend, 4 fixture); restored |
| Mutation: local-binding check disabled | 2 frontend tests fail; restored |

## Session A Handoff

Commits: Stage 1 `6bcbbd7`, Stage 2 `575bf92`, Stage 3 `50d68c4`.

For the review of Stages 1–3:

- Review focus from the plan applies: resolution honesty (no name match as a
  fact), identity from graph evidence, and no new shared-core kind. The places
  to read are `containerDeclaration`, `collectBindings`, and `decideName` in
  `src/frontends/zig.zig`.
- Deliberate choices a reviewer may disagree with: per-kind aggregation of
  unsupported-construct diagnostics; no signature in Zig identity evidence;
  error sets outside container coverage; unresolved `CALLS` recorded for
  non-bare callees; no `REFERENCES`.

Residual risk:

- The pinned grammar turns an empty container body (`struct {}`) into a parse
  error, so such a unit reports `analysis_failed` and contributes nothing
  (see Stage 2).
- Coverage stops at the file namespace. Methods and nested declarations are
  invisible as definitions, and calls made inside them are not recorded, so
  "who calls X" undercounts for code organized in containers, which is most
  Zig. Queries still see the unsupported-construct diagnostics that say so.
- `RULES.md` Project Context and `README.md` still describe the slice as Java
  and Clojure only, and `SPEC.md` does not mention Zig. The plan assigns those
  updates to Stage 5; `MEMORY.md` was updated for Stages 1–3 now.

Next: review Stages 1–3, then Session B runs Stage 4 (local MCP stdio preview)
and Stage 5 from this log. Session B must read the `2026-07-28` MCP
specification from the plan's link rather than implement `server/discover`
from memory, as the plan's Execution Recommendations require.

## Review: Stages 1-3

Reviewer pass recorded on 2026-09-14.

Semantic Code Indexing was required by policy, but no callable semidx tools were
available through tool discovery in the review environment; only unrelated MCP
tools were exposed. The review used targeted direct inspection of the changed
files named by the plan.

### Confirmed Finding: Dangling Relationship Designators

Status: fixed in Stage 3.5 (see below). Severity: blocker before Stage 4.

`zig build run -- src` does not complete in the review environment. It prints
the expected summary counts first (`20` Zig units, `185` definitions, `515`
facts, `536` unresolved, `0` approximate, `0` stale), then aborts while printing
unresolved call targets:

```text
Segmentation fault at address ...
src/main.zig:114:48: ... in printSummary
    .designator => |name| try out.print("  {s} -> {s} ({s})\n", .{
```

The storage path explains the crash. `src/frontends/zig.zig` creates unresolved
call targets from `BatchBuilder` arena memory:

- `emitCall` duplicates the callee into `designator`;
- unresolved calls store `.target = .{ .designator = designator }`.

`src/frontends/root.zig` then destroys that arena after integration:

- `Analyzer.indexUnit` initializes a `BatchBuilder`;
- `defer builder.deinit()` runs after `core.reconcile.integrate`.

`src/core/graph.zig` interns producer, evidence, and resolution strings in
`addAssertion`, but stores `.claim = claim` unchanged. For a relationship whose
target is `.designator`, the graph therefore retains a slice owned by the
frontend batch arena. Published snapshots can later read freed memory. The
larger Zig dogfood run exposes it deterministically; smaller tests can pass by
accident because the freed arena contents have not yet been overwritten.

Smallest reasonable fix: intern claim-owned strings when storing assertions.
Add an `internClaim`/`internTarget` helper in `Graph` and call it from
`addAssertion` before appending the assertion, so relationship designators live
in `StringPool` just like evidence text and resolution explanations. Add a test
that publishes and reads an unresolved relationship after its `BatchBuilder`
has been destroyed, then keep `zig build run -- src` as verification evidence.

Do not start Stage 4 until this is fixed. The MCP preview will expose
relationship designators through snapshot-backed tools, so it would inherit the
same dangling-string defect.

### Verification Run By Reviewer

| Command | Result |
| --- | --- |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass, 85/85 |
| `zig build test-core --summary all` | Pass, 85/85 |
| `zig build test --summary all` | Pass, 163/163 |
| `zig fmt --check build.zig src tests` | Pass |
| `./scripts/check-agent-attribution.sh --all` | Pass |
| `./scripts/check-memory-freshness.sh` | Pass |
| `git diff --check` | Pass |
| `zig build run -- fixtures/vertical-slice/zig` | Pass |
| `zig build run -- src/frontends/zig.zig` | Pass |
| `zig build run -- src` | Fail: abort while printing unresolved designators |

## Stage 3.5: Graph-Owned Relationship Designators

Fix for the review's confirmed finding. Changed files: `src/core/graph.zig`,
`src/core/reconcile.zig`.

- The defect was in the shared core, not in the Zig frontend: every assertion
  field that holds a string was interned except `model.Target.designator`, so
  the Java and Clojure frontends handed over borrowed designators too. Their
  fixtures were small enough that the freed arena was not reused before it was
  read.
- `Graph.internClaim` copies a relationship's designator into the graph's
  string pool; `addAssertion` stores the interned claim after validation. A
  designator is the only string a `model.Claim` can carry.
- Regression tests do not rely on reading freed memory. Each overwrites the
  producer's bytes after handing the claim over and then reads the graph:
  `an unresolved designator is owned by the graph, not by its producer`
  (graph level) and `an unresolved designator outlives the batch that produced
  it` (through `reconcile.integrate` and a `BatchBuilder`).

Finding recorded while verifying the fix (open, not a correctness defect):

- The pinned grammar parses a logical negation applied to a call, `!helper()`
  or `!a.b()`, as a call whose callee is an `error_union_type` (`!helper`), the
  shape of the type `!T`. Such a call is recorded as unresolved with designator
  `!helper` ("the callee is not a bare name"), never as a fact, so bare calls
  under `!` are undercounted. Unary minus parses correctly. Reinterpreting that
  node as a negated call would repair the tree by assumption, which the plan's
  stop conditions rule out, so this is left as residual risk pending a decision.

Disposition: defer to a Zig frontend follow-up, not Stage 4. The current
behavior is incomplete but honest: it records unresolved `CALLS` rather than a
false fact, so the MCP preview can expose it with resolution metadata. Do not
add an ad hoc `!` rewrite while implementing MCP. The future-plan input is
tracked in
[follow-up 001](../followups/001_zig_logical_negation_calls.md).

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass, 87/87 |
| `zig build test-core --summary all` | Pass, 87/87 |
| `zig build test --summary all` | Pass, 165/165 |
| `zig build run -- src` | Exit 0, full output (838 lines): 20 units, 185 definitions, 515 facts, 536 unresolved, 0 approximate, 0 stale; no non-printable bytes in output |
| `zig build run -- .` | Exit 0, full output (1255 lines) |
| Mutation: `addAssertion` stores `.claim = claim` again | Both regression tests fail; restored |
| `./scripts/check-agent-attribution.sh --all` | Pass (exit 0) |
| `git diff --check` | Pass |

## Stage 4: Local MCP Stdio Preview

Changed files: `build.zig`, `src/frontends/root.zig` (`Analyzer.probeParser`),
new `src/mcp/{root,protocol,stdio,tools,main}.zig`, new
`tests/mcp_smoke_test.zig`; documentation: `RULES.md` Project Context,
`MEMORY.md`, `docs/agent-policy/testing.md` (MCP lane),
`docs/agent-policy/tooling.md` (the development-tooling MCP sections do not
describe `semidx-mcp`).

### Environment

- The semidx MCP server again failed to connect (connection timeout), so its
  tools were unavailable. Per
  [tooling policy](../agent-policy/tooling.md#mcp-failure-protocol), code was
  located by targeted direct reads of the files the plan names.
- Plan Readiness Gate re-checked before Stage 4: no hard fail.
- The MCP specification was read from its source repository
  (`modelcontextprotocol/modelcontextprotocol`, `main` at `2997f33b`, fetched
  2026-09-14), not from model memory: for `2026-07-28` the base protocol,
  versioning, stdio transport, `server/discover`, tools, changelog, and the
  `schema.ts` definitions and examples for discovery, tool listing and calls,
  and errors; for `2025-06-18` the lifecycle, transports, and tools pages.
- Zig 0.16 standard-library APIs used here (`std.json.Stringify`,
  `std.Io.Reader.takeDelimiter`, `std.process.spawn`) were checked against the
  installed library sources rather than assumed.
- During the session two unrelated commits landed on `dev` (`05383a4` follow-up
  004, `e59552c` roadmap). They touch no file this stage changes.

### Decisions taken inside the plan's boundary

- **Both protocol shapes share one dispatcher, so no stop condition applied.**
  The era is decided per request: a request whose `params._meta` carries
  `io.modelcontextprotocol/protocolVersion` is modern and served statelessly;
  one without it is legacy. A modern version other than `2026-07-28` gets
  `-32022` with `data.supported` and `data.requested`; a modern request missing
  `io.modelcontextprotocol/clientCapabilities` gets `-32602`. A legacy
  `tools/list` or `tools/call` before `initialize` gets `-32602` naming both
  ways in. This matches the `2026-07-28` dual-era server rules: modern `_meta`
  selects stateless handling, `initialize` selects legacy semantics scoped to
  the stdio process.
- **Modern responses advertise only `2026-07-28`** in
  `DiscoverResult.supportedVersions` and in `-32022` data. Listing
  `2025-06-18` there would invite a per-request `_meta` of `2025-06-18`, which
  is not how that version works; it is reachable through `initialize`, which
  answers `2025-06-18` whatever version the client proposed, as the
  `2025-06-18` lifecycle prescribes.
- Modern results carry `resultType: "complete"` and
  `_meta["io.modelcontextprotocol/serverInfo"]`; `server/discover` and
  `tools/list` carry `ttlMs` and `cacheScope: "public"` (the tool set is fixed
  per binary). Legacy results carry none of these. `ping` is answered only for
  legacy clients; `2026-07-28` removed it.
- Tool results return `structuredContent` plus a text block holding the same
  JSON serialized, which both versions recommend. No `outputSchema` is
  declared, so no unverified schema promise is made.
- Unknown tool, missing `name`, and non-object `arguments` are protocol errors
  (`-32602`); invalid argument values and unknown argument names are tool
  execution errors (`isError: true`), which the `2026-07-28` tools page assigns
  to input validation.
- JSON-RPC batches are refused (`-32600`); invalid JSON gets `-32700` without an
  id, as the `2026-07-28` schema allows. A notification is never answered, even
  with malformed params. A line over 1 MiB is refused with `-32600` and the next
  line is still served. No `cursor` is ever issued, so any cursor is `-32602`.
- Strings rendered from paths, names, and designators are written as UTF-8 with
  invalid sequences replaced by U+FFFD: `std.json.Stringify` would otherwise
  render non-UTF-8 bytes as a number array, changing the field's type.
- **The source-text opt-in names its data shape: `--allow-evidence-text`.** The
  plan and ADR 005 speak of snippets; reading the snapshot showed that its only
  source-text field is `SourceEvidence.text`, and that every current frontend
  records a name or designator there, not a body. The server therefore never
  reads unit contents into a result, and the opt-in adds exactly the recorded
  evidence text, capped at 400 bytes per claim with a `truncated` flag. A
  range-based snippet reader would be a new data path and was not added.
- Tools render graph values and select by exact name, path, language, and role;
  nothing resolves a name, and an unresolved relationship is shown with its
  designator and no target entity. `semidx_references` lists `REFERENCES`/`CALLS`
  by the snapshot's reference query, so a call is listed once, and a recursive
  call that is both incoming and outgoing is listed once. Every structured
  result carries `snapshot.revision` and `semantic_contract_version: null`.
- `semidx_health` reports parser availability through the new
  `Analyzer.probeParser`, so the MCP layer never reaches past the frontends to
  the tree-sitter adapter.
- `semidx_refresh` rescans, calls `Index.applyScan`, publishes, and only then
  replaces the published snapshot; a scan, reconcile, or publish failure returns
  a tool execution error and the previous snapshot stays published. Requests
  are answered one at a time, so no response can observe two snapshots.
  `semidx_refresh` is annotated `readOnlyHint: false`, `destructiveHint: false`,
  `idempotentHint: true`; the schema's default `destructiveHint` is `true`.

### Risk Matrix (Stage 4)

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| stdout carries only MCP messages (stdio spec, plan Stage 4) | A log line or late write corrupts the stream | Runtime smoke | Real subprocess stdout | Log line before serving; write after end of input | `mcp_smoke_test`; mutations below |
| Message classification (JSON-RPC, both eras) | Wrong error code, answering a notification, null id accepted | Unit | `protocol.parse`, `checkMeta` | Invalid JSON, batch, null id, wrong `jsonrpc`, non-object params, malformed notification | `protocol.zig` tests |
| Era selection per request (`2026-07-28` versioning) | Modern request depends on connection state; legacy served without `initialize` | Integration | `Server.handleLine` | Modern request before and after `initialize`; unsupported version; missing capabilities; legacy call before `initialize`; modern `ping` | `one dispatcher serves ...`, smoke |
| Framing bounds | Unbounded buffering or desynchronized stream after a long line | Unit | `stdio.serve` | Oversized line then a valid one; oversized final line | `stdio.zig` tests |
| Graph authority and knowledge categories (constitution §1, §3, §7) | A tool relabels or resolves a claim | Integration | `tools.zig` rendering | Unresolved designators, facts, and existence claims read back with resolution, producer, freshness | `tool results carry ...`, smoke `semidx_context` |
| No source text by default (ADR 005, constitution §8) | Evidence text or unit contents reach a result | Integration | `writeEvidence` is the only reader of `SourceEvidence.text` | All read tools with the opt-in off and on; 600-byte evidence text | `no tool result carries source text ...`; mutation below; smoke transcript check |
| Bounded output | Unbounded lists | Integration | Limits and truncation markers | `limit: 1` of 2; invalid limit | `tool results carry ...`, `one dispatcher ...` |
| Refresh consistency (constitution §5) | A response mixes states, or a failed refresh loses the snapshot | Integration + runtime smoke | `Server.refresh` swap | Calls before refresh still see the old snapshot; added and edited units after; root deleted | `refresh publishes ...`; smoke refresh; mutation below |
| Invalid UTF-8 in graph strings | Non-UTF-8 stdout or a type change | Unit | `protocol.writeString` | Invalid and truncated sequences | `invalid utf-8 is replaced ...` |
| Startup and exit | Silent failure or protocol output on a failed start | Runtime | `main.zig` | `--help`, unknown argument, missing `--root` value, nonexistent root | Manual runs below |

### Verification

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass (exit 0) |
| `zig build test-core --summary all` | Pass (exit 0) |
| `zig build test --summary all` | Pass, 179/179 (165 before the stage), exit 0 |
| `zig build test-mcp --summary all` | Pass, 14/14 (13 module tests, 1 stdio smoke), exit 0 |
| `zig build run -- src` | Exit 0, full output consumed (1483 lines, no non-printable bytes): 25 units, 248 definitions |
| `./scripts/check-agent-attribution.sh --all` | Pass (exit 0) |
| `git diff --check` | Pass |
| `./scripts/check-memory-freshness.sh` | Failed before `MEMORY.md` was updated in this stage (trigger: `src/frontends/root.zig`); `MEMORY.md` is updated in the same commit |
| Mutation: write `semidx-mcp: serving` to stdout before serving | Smoke fails: "non-protocol stdout line"; restored |
| Mutation: write `bye` to stdout after end of input | Smoke fails on trailing stdout; restored |
| Mutation: render evidence text regardless of the opt-in | `no tool result carries source text ...` fails; restored |
| Mutation: refresh publishes but does not swap the snapshot | In-process refresh test and smoke fail; restored |
| `semidx-mcp --help` / `--bogus` / `--root` / `--root /nonexistent/...` | Exit 0 / 2 / 2 / 1; stdout empty in every case; message on stderr |

Dogfood run (`zig build mcp -- --root .`, driven by a local script over
stdio, all streams read to the end): `server/discover`, `tools/list`, and all
six tools answered with valid JSON-RPC; exit 0; no trailing stdout; stderr was
the startup and exit lines only. The graph held 54 units (35 Zig, 10 Java, 9
Clojure; 3 `analysis_failed` fixtures), 363 definitions, 1061 current facts, and
1339 unresolved assertions. `semidx_find_definitions` over
`src/mcp/protocol.zig` returned its 18 top-level definitions, all facts;
`semidx_references` for `writeString` returned its three same-unit callers. The
largest response, `semidx_repo_map` over `src/mcp/`, was 42 KB.

### Residual Risk

- The preview is only as deep as the frontends. Zig coverage stops at the file
  namespace: methods such as `Server.handleLine` are not definitions, and calls
  through a namespace (`protocol.writeString(...)`) stay unresolved designators,
  so `semidx_references` undercounts callers in container-organized Zig. The
  results say so through resolution and diagnostics, not through omission.
- `semidx_refresh` without source changes publishes the same revision, because
  nothing mutated the graph.
- `Index.applyScan` is not transactional: an allocation failure part-way through
  a refresh leaves the graph partly updated while the previous snapshot stays
  published, and a later successful refresh publishes whatever the graph then
  holds.
- Output is bounded per list but not per response; a `semidx_context` focus of
  10 entities with 500 relationships each can produce a large message.
- The smoke test has no timeout: a server that stops answering hangs the test
  rather than failing it.
- `serverInfo.version` is `0.0.0`; follow-up 004 owns runtime product
  versioning.
- Client configuration and use are documented in Stage 5.

## Stage 5: Dogfood, Documentation, And Handoff

Changed files: new `docs/mcp/local_preview.md`; `README.md`, `SPEC.md`,
`MEMORY.md`, `docs/design/001_project_roadmap.md` (current position only), and
this log.

Decisions taken inside the plan's boundary:

- `docs/mcp/local_preview.md` is one reference-and-how-to page, as the plan
  names one file. It follows the workspace documentation guide's pattern of
  stating what the tool does and does not do and what a reader may and must not
  infer, and every statement was checked against the implementation; two
  statements were corrected in that check (the full `-32602` list, and entity
  ids being meaningful only within one process).
- Client configuration is shown in the `mcpServers` command-and-arguments shape
  and described as such, without claiming any particular client's behavior
  beyond launching a stdio command.
- `SPEC.md` gained a paragraph recording the Zig frontend and the MCP preview
  as implementation guidance, not coverage or contract claims, and two table
  notes: packaging and product versioning point to follow-up 004, and the MCP
  tool shapes are not answers to the public-contract requirements.
- The roadmap's current-position text said the MCP preview was in progress; only
  that text was brought up to date.

Dogfood evidence (the DoD's fresh-agent check), following the document: after
`zig build`, a script started `zig-out/bin/semidx-mcp --root .`, initialized as
a `2025-06-18` client, and called `semidx_find_definitions` for `src/root.zig`
(containers `Index` at line 29 and `Upkeep` at line 299, both facts); as a
`2026-07-28` client it found `serve` in `src/mcp/stdio.zig` and mapped
`src/core/` with truncated per-file definition lists. Exit status 0, no stdout
after end of input, stderr only the startup and exit lines. `Server.serve`, a
container member, is correctly absent.

Verification:

| Command | Result |
| --- | --- |
| Dogfood script above | Pass (exit 0, streams read to the end) |
| `./scripts/check-agent-attribution.sh --all` | Pass (exit 0) |
| `./scripts/check-memory-freshness.sh` | Pass (exit 0) after the Stage 4 commit |
| `git diff --check` | Pass |

No code changed in Stage 5, so the build and test lanes recorded for Stage 4
stand; they were not rerun.

## Final Review

Reviewer: Codex, 2026-09-14.

Reviewed scope: Stage 4 commit `effbbb7` and Stage 5 commit `cf04f95`, with the
already-reviewed Zig frontend and Stage 3.5 blocker fix as context.

Semantic Code Indexing (semidx MCP) was not available in the review environment
through tool discovery, so the review used the policy fallback: targeted source
reads plus runtime checks. The review also re-read `RULES.md`,
`ARCHITECTURE_CONSTITUTION.md`, ADR 005, this plan, the progress log, and the
official MCP `2026-07-28` markdown pages for versioning, discovery, stdio, tools,
and schema fields.

Findings:

- **No blocking defects found for the local MCP preview boundary.** The MCP layer
  reads published snapshots and renders graph values; it does not establish,
  resolve, or relabel assertions. Tool results preserve resolution, freshness,
  producer, diagnostics, snapshot revision, and `semantic_contract_version: null`.
  stdout/stderr separation, newline stdio framing, modern per-request `_meta`,
  legacy initialization, and structured tool results match the plan's preview
  requirements.
- **The source-derived-data question is accepted as non-blocking for this local
  preview and tracked before release.** `semidx-mcp` itself is local stdio and
  performs no outbound transmission; source text remains disabled by default.
  Paths, names, designators, ranges, and diagnostics are graph values returned to
  the launching client, but hosted-client onward transmission still needs an
  explicit product consent story before a preview release. Tracked as
  [follow-up 005](../followups/005_mcp_source_derived_consent_boundary.md).

Review verification:

| Command | Result |
| --- | --- |
| `zig build test-mcp --summary all` | Pass, 14/14 |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass, 87/87 |
| `zig build test --summary all` | Pass, 179/179 |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build run -- src` | Exit 0, full output consumed: 1487 lines, no non-printable bytes |
| `./scripts/check-agent-attribution.sh --all` | Pass |
| `./scripts/check-memory-freshness.sh` | Pass |
| `git diff --check` | Pass |
| `zig build` plus two real `semidx-mcp --root .` modern requests | Exit 0, two JSON-RPC stdout lines, stderr startup and exit lines only |

Plan 004 is accepted and closed. Future work should start from the residual risks
above and the open follow-ups, especially release discipline, hosted-client
consent wording, and Zig frontend coverage gaps.

## Session B Handoff

Commits: Stage 4 `effbbb7`; Stage 5 is the commit that adds this section.

For the review of Stages 4–5:

- Review focus from the plan applies: MCP must not establish or relabel
  assertions, refresh must publish complete snapshots, stdio framing and both
  protocol versions must match the specification, and source text must stay off
  by default. The places to read are `Server.respond`, `dispatchModern`,
  `dispatchLegacy`, `callTool`, and `refresh` in `src/mcp/root.zig`;
  `parse` and `checkMeta` in `src/mcp/protocol.zig`; `writeEvidence`,
  `writeRelationship`, and `selectTargets` in `src/mcp/tools.zig`; and
  `tests/mcp_smoke_test.zig`.
- Deliberate choices a reviewer may disagree with: modern responses advertise
  only `2026-07-28`; `initialize` always answers `2025-06-18`; invalid argument
  values are tool execution errors rather than `-32602`; no `outputSchema` is
  declared; the opt-in exposes recorded evidence text (`--allow-evidence-text`)
  rather than range snippets read from unit contents; names, designators, paths,
  and diagnostic messages are returned by default as graph values.

Open question for review:

- ADR 005 disables source text by default. Paths, entity names, designators,
  and diagnostic messages are still source-derived data, and a client may send
  a tool result to a hosted model. The implementation and documentation treat
  those as graph values delivered only to the client process that launched the
  server, and leave onward transmission to that client. Whether that reading
  satisfies constitution §8's opt-in requirement for source-derived data sent
  outside the machine is not settled by ADR 005's text and should be decided in
  review rather than assumed here.

Residual risk: see [Stage 4 Residual Risk](#residual-risk). Stage 5 adds none.

This handoff was consumed by the final review above.
