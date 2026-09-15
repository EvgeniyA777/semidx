---
title: "MCP preview release readiness progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 005: MCP Preview Release Readiness Progress

Companion log for
[docs/plans/005_mcp_preview_release_readiness.md](../plans/005_mcp_preview_release_readiness.md).

## Current Status

Execution started on 2026-09-14. Stages 1, 2, 2.5, 3, and 3.5 are complete; Stage 4 is next.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Product version and preview identity | Completed (`db7caa6`) | `0.1.0-preview.1` is defined once in `build.zig.zon` and reported by `semidx-mcp --version`, `serverInfo.version`, and `semidx_health.product_version`; `semantic_contract_version` stays `null`. |
| Stage 2: Install and local agent configuration | Completed (`7ad042a`) | README gives a four-step source-built path to a registered MCP server; a clean clone followed it to a first successful tool call. |
| Stage 2.5: Same-unit name resolution facts (Java and Clojure) | Completed (`f0bb778`) | Two confirmed false `CALLS` facts removed: a Java call to an overloaded method is no longer a fact about the first overload, and a Clojure symbol is no longer a fact where a local binding may shadow it. Both rules now leave uncertain cases unresolved with a reason. |
| Stage 3: Capability matrix and consent boundary | Completed (`bd0d7c6`) | `docs/spec/capability_matrix.md` states per-producer coverage, unresolved and unsupported cases, identity limits, and known overbroad and false-negative cases; README and the local preview reference carry hosted-client consent wording. |
| Stage 3.5: Refresh failure recovery | Completed | Failure injection confirmed that a failed reconciliation poisons the index. `semidx-mcp` now discards such an index and rebuilds it from the same scan above the old ids; at each of 87 injected failure points the published snapshot stays intact, the next refresh equals a fresh index, and no old id names a different entity. |
| Stage 4: Dogfood proofs and release gate | Pending | |
| Stage 5: Preview release candidate handoff | Pending | |

## Plan Readiness Gate

Checked by the implementing agent before Stage 1 on 2026-09-14 against the
current plan text (commit `0e0fbc6`). Scope, non-scope, stage outputs,
verification, and stop conditions are explicit; no hard fail. Two points are
left to execution and are decided in the stage that meets them:

- how Stage 4 induces a refresh failure on this repository, given that a
  mid-reconciliation failure can only be injected in a test;
- what "clean worktree" means for the Stage 5 release gate, given that pinned
  grammar sources are ignored by git and not part of a checkout.

## Environment

- The semidx MCP server failed to connect (connection timeout), so its tools
  were unavailable. Per
  [tooling policy](../agent-policy/tooling.md#mcp-failure-protocol), code was
  located by targeted direct reads of the files the plan names.
- Toolchain: Zig 0.16.0, tree-sitter runtime from `/opt/homebrew`.

## Toolchain Pin Addendum

On 2026-09-15 the target Zig version was made exact rather than open-ended:
Zig 0.16.0 is the only supported toolchain for this preview release path.

Changed files: `.zigversion`, `scripts/check-zig-version.sh`, `RULES.md`,
`README.md`, `docs/mcp/local_preview.md`, `docs/agent-policy/tooling.md`,
`.agents/skills/semidx-zig-implementation/SKILL.md`,
`docs/plans/005_mcp_preview_release_readiness.md`, `MEMORY.md`.

Decision:

- `.zigversion` records the target version.
- `build.zig.zon` already has `minimum_zig_version = "0.16.0"`; the check script
  verifies that it still agrees with `.zigversion`.
- The release gate now starts with `./scripts/check-zig-version.sh`.
- A build-time exact-version guard is intentionally deferred while `build.zig`
  has in-progress Stage 4 smoke-timeout changes. Add it in that coherent build
  change if the team wants the build itself to reject other Zig versions.

Verification:

| Command | Result |
| --- | --- |
| `zig version` | `0.16.0` |
| `./scripts/check-zig-version.sh` | Pass; `Zig version 0.16.0 matches semidx target` |

## Stage 1: Product Version And Preview Identity

Changed files: `build.zig.zon`, `build.zig`, `src/mcp/protocol.zig`,
`src/mcp/tools.zig`, `src/mcp/root.zig`, `src/mcp/main.zig`,
`tests/mcp_smoke_test.zig`, `docs/mcp/local_preview.md`, `MEMORY.md`.

Decisions taken inside the plan's boundary:

- **The one implementation-owned place is `build.zig.zon`'s `version`.**
  `build.zig` imports the manifest (verified to work in Zig 0.16 with a probe
  before use) and passes the version to the MCP module as a build option;
  `protocol.product_version` is the only code constant. The package manifest
  and the product therefore cannot disagree.
- `--version` prints `semidx-mcp 0.1.0-preview.1` to stdout and exits 0 without
  indexing. stdout carries protocol messages only while serving; a version
  printed where scripts read it does not break that. `--help` keeps stderr and
  gained only the `--version` line.
- `semidx_health` gains a top-level `product_version` beside the existing
  `server` identity, so the version is visible without knowing the identity
  object's shape.
- The smoke test pins the expected release literal (`0.1.0-preview.1`) in
  addition to comparing against the manifest value: the definition stays in one
  place, and the gate states which release this tree prepares.
- `semidx-dev` did not gain version output: it shares no version plumbing, and
  the plan limits it to that case.

Risk matrix:

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| One version, reported consistently (plan Stage 1) | Binary, identity, and health drift apart | Integration + runtime smoke | Manifest to build option to `protocol.product_version` | Manifest version changed | `the product version is reported in server identity and health ...`; smoke `--version` test; mutation below |
| Product version is not a contract version (plan decision) | A client reads the preview version as a semantic contract | Integration | `beginStructured` | Health result checked for `semantic_contract_version: null` | same tests |
| `--version` cannot pollute a serving stdout | Version text reaches a protocol stream | Runtime smoke | `main.zig` argument handling | `--version` runs without serving; stdio smoke unchanged | smoke tests |

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-mcp --summary all` | Pass, 16/16 |
| `zig build test --summary all` | Pass, 181/181 (179 before) |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass, 87/87 |
| `zig-out/bin/semidx-mcp --version` | Exit 0; stdout `semidx-mcp 0.1.0-preview.1`; stderr empty |
| `zig-out/bin/semidx-mcp --help` | Exit 0; stdout empty; usage on stderr with the added `--version` line |
| Mutation: manifest version set to `0.1.0-preview.2` | Smoke `--version` test fails; restored |

No document describes the semantic contract as published or stable: the local
preview reference states the product version is not a semantic contract
version.

## Stage 2: Install And Local Agent Configuration

Changed files: `README.md`, `docs/mcp/local_preview.md` (commit `7ad042a`);
this log and follow-up 007 in the next commit.

Decisions taken inside the plan's boundary:

- The README carries the whole first-call path in four numbered steps and one
  configuration example; `docs/mcp/local_preview.md` keeps exact prerequisites,
  options, tools, and fields, and gains a short "First Calls" sequence that
  follows the adoption strategy's agent habit loop.
- Runtime installation is stated only as far as it was verified: `zig build`
  searches `/opt/homebrew`, `/usr/local`, and `/usr` (read from `build.zig`), and
  Homebrew's `tree-sitter` 0.26.3 provides both required files (checked with
  `brew list tree-sitter`). No Linux package name is claimed.
- The configuration example stays in the command-and-arguments `mcpServers`
  shape already used by the reference; no separate sample file was needed.

Clean-clone proof (the DoD's fresh-agent check), run in a scratch directory:

| Step | Command | Result |
| --- | --- | --- |
| Clone | `git clone /path/to/semidx semidx` | HEAD `7ad042a` |
| Grammars | `./scripts/setup-tree-sitter-grammars.sh` | Exit 0 in 12 s (network); pinned refs for Java, Clojure, Zig, TypeScript; Elixir at `main` |
| Build | `zig build` | Exit 0 in 11 s; stderr empty |
| Version | `zig-out/bin/semidx-mcp --version` | `semidx-mcp 0.1.0-preview.1` |
| First call | A client script reading the README's JSON example literally, with the placeholder paths replaced, sending `semidx_health` for another local working copy | Response in 346 ms from process start: `isError: false`, 54 units (51 current), `product_version` `0.1.0-preview.1`; exit 0, no trailing stdout, stderr only startup and exit lines |

The clone took the Stage 1 and Stage 2 commits, so the proof covers the
documentation as committed rather than the working tree.

Finding filed: the setup script also clones `tree-sitter-typescript` and an
unpinned `tree-sitter-elixir` (`main`), neither compiled by `build.zig`. The
build stays reproducible; the setup step does not. Tracked as
[follow-up 007](../followups/007_grammar_setup_fetches_unused_unpinned_sources.md).

Verification:

| Command | Result |
| --- | --- |
| Clean-clone proof above | Pass |
| `./scripts/check-agent-attribution.sh --all` | Pass (exit 0) |
| `git diff --check` | Pass |

No Zig product code changed in Stage 2 before the addendum.

Stage 2 addendum:

- Added `scripts/semidx-mcp.sh` as the stable local MCP launcher for agent
  configuration. It locates the built `zig-out/bin/semidx-mcp`, passes explicit
  `--root`, `--help`, and `--version` through, and otherwise chooses
  `SEMIDX_ROOT` or the current Git root. If neither is available, it exits with
  a usage error instead of indexing an arbitrary directory.
- Added compatibility aliases `scripts/start-mcp-server.sh` and
  `scripts/mcp-stdio.sh` so older local configs that named those paths stop
  failing at process startup and now launch the preview server.
- `.mcp.json` in this repository now registers `semidx` with the launcher and
  an explicit `/Users/ae/workspaces/semidx` root.
- `README.md`, `docs/mcp/local_preview.md`, `docs/agent-policy/tooling.md`, and
  `.agents/skills/semidx-code-exploration/SKILL.md` now use the current preview
  tool flow: `semidx_health`, `semidx_repo_map`, `semidx_find_definitions`,
  `semidx_references`, `semidx_context`, and `semidx_refresh`.

Addendum verification:

| Command | Result |
| --- | --- |
| `sh -n scripts/semidx-mcp.sh && sh -n scripts/start-mcp-server.sh && sh -n scripts/mcp-stdio.sh` | Pass |
| `jq . .mcp.json /Users/ae/workspace/UniPlan/.mcp.json /Users/ae/workspace/JobApplicationTracker/.mcp.json /Users/ae/workspaces/Fleetix/.mcp.json /Users/ae/.claude.json >/dev/null` | Pass |
| TOML parse of `/Users/ae/.codex/config.toml` with Python `tomllib` | Pass |
| `semidx-mcp.sh --version` from `/Users/ae/workspace/UniPlan` | Exit 0; `semidx-mcp 0.1.0-preview.1` |
| Modern `semidx_health` through `semidx-mcp.sh` from `/Users/ae/workspace/UniPlan` without `--root` | Exit 0; root `/Users/ae/workspace/UniPlan`, 263 Java units, evidence text disabled |
| Modern `semidx_health` through `semidx-mcp.sh --root /Users/ae/workspaces/semidx` from `/Users/ae` | Exit 0; root `/Users/ae/workspaces/semidx`, product version `0.1.0-preview.1`, evidence text disabled |
| `semidx-mcp.sh` from `/tmp` with no `--root`, no `SEMIDX_ROOT`, and no Git root | Exit 2 with a usage error; no arbitrary directory indexed |
| `./scripts/check-agent-attribution.sh --all` | Pass |
| `./scripts/check-memory-freshness.sh` | Pass |
| `git diff --check` on the addendum-owned files | Pass |

Finding recorded while reading the addendum (not changed here): the launcher
treats `--root=/path` as an explicit root and passes it through, but
`semidx-mcp` accepts only `--root <dir>` as two arguments, so that spelling
exits 2 with "unknown argument".

## Stage 2.5: Same-Unit Name Resolution Facts (Java And Clojure)

Changed files: `src/frontends/java.zig`, `src/frontends/clojure.zig`,
`tests/vertical_slice_test.zig`, `docs/plans/005_mcp_preview_release_readiness.md`,
new `docs/followups/008_clojure_lexical_scope_coverage.md`,
`docs/followups/README.md`, `MEMORY.md`.

How it was found. While gathering capability-matrix facts, two probes through
`semidx-mcp` over scratch files showed wrong facts:

- `class Over { void greet() {} void greet(String n) {} void run() { greet("x"); } }`
  recorded `run CALLS greet()` (the no-argument overload) as a fact.
- `(defn helper [] 1) (defn run [] (let [helper (fn [] 2)] (helper)))` recorded
  `run CALLS helper` (the top-level `defn`) as a fact.

Both limitations were listed in report 001 as "no overload resolution" and "no
local bindings", but their consequence — a fact with the wrong target — was not
stated. The maintainer decided both are preview blockers for false precision;
the plan was amended (Plan-Level Decisions, Stage 2.5).

Decisions taken inside the plan's boundary:

- **Java.** An unqualified invocation is a fact only when the enclosing class
  declares exactly one method of that name, has no superclass or interfaces, and
  the call is not inside a class, interface, enum, or annotation body declared in
  the method (node shapes read with `tree-sitter parse` on the pinned grammar:
  anonymous and local classes both expose `class_body`). Lambdas keep the class
  scope. Unresolved explanations name overloads, supertypes, or a nested class
  body. The capability note was updated to say so.
- **Clojure.** A symbol is a fact only when it names the unit's one top-level
  declaration whose head starts with `def` (so a `defmacro` or second `defn` of
  the name blocks it), is not a parameter of the enclosing definition (parameter
  vector read at any destructuring depth), the definition has a single parameter
  vector, and every enclosing form is known to bind nothing: the body, `do`,
  `if`, collection literals, calls of the unit's own definitions, and
  applications with a non-symbol head (only a symbol can name a macro).
  Anything else — including `clojure.core` functions such as `str`, since a
  namespace may exclude or replace them — stays unresolved as "a form this
  frontend cannot rule out as a macro that binds the name locally". This is
  deliberately conservative; precise scope is follow-up 008.
- Fixture expectations changed in two Clojure tests, both because
  `(str greeting "!")` no longer yields a fact: the fixture test now asserts the
  unresolved reference and its explanation, and the rename test asserts the
  reference stays a designator for `salutation` and no reference targets either
  entity. Their intent — honest resolution and no silent retarget — is unchanged.

Risk matrix:

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Java facts only with one selectable method (constitution §3) | Overload, inherited method, or nested class method misattributed | Integration (frontend through reconcile) | `java.invocationTarget` | Overload, superclass, interface, anonymous class, local class; lambda and unique method stay facts | `a java invocation is a fact only when the class leaves one method to select`; three mutations |
| Clojure facts only where no binding is possible (constitution §3) | Parameter, `let`, macro, duplicate, or multi-arity binding misattributed | Integration | `clojure.decideSymbol`, `walkForm` trust | `let`, unknown macro, parameter, duplicate `defn`, `defmacro`, multi-arity; eight facts in known contexts | `a clojure symbol is a fact only where nothing may bind it locally`; three mutations |
| No regression elsewhere | Fixture and edit-history tests change meaning | Fixture | Existing tests | Two expectations updated with reasons above | Full lane |

Verification:

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test --summary all` | Pass, 183/183 (181 before the stage) |
| Mutation: Java overload count check disabled | Java test fails; restored |
| Mutation: Java nested-body check disabled | Java test fails; restored |
| Mutation: Java supertype check disabled | Java test fails; restored |
| Mutation: Clojure unknown-head trust removed (`inner = known or head_is_fact`) | Clojure scope, fixture, and rename tests fail; restored. A first attempt at this mutation did not compile and proved nothing; it was redone. |
| Mutation: Clojure parameter check disabled | Clojure scope test fails; restored |
| Mutation: Clojure duplicate-declaration check disabled | Clojure scope test fails; restored |

## Stage 3: Capability Matrix And Consent Boundary

Changed files: new `docs/spec/capability_matrix.md`; `SPEC.md`, `README.md`,
`docs/mcp/local_preview.md`, `docs/followups/005_mcp_source_derived_consent_boundary.md`,
`MEMORY.md`, this log.

Decisions taken inside the plan's boundary:

- The matrix lives at `docs/spec/capability_matrix.md`, the location the plan
  suggests, and `SPEC.md` names it as unversioned implementation guidance rather
  than the published coverage matrix its contract lifecycle requires. It carries
  no version and says every result reports `semantic_contract_version: null`.
- Every row was written from the implementation, not from earlier reports:
  frontend `capabilities`, the diagnostics each frontend emits, `resolveType`,
  `invocationTarget`, `decideSymbol`, discovery budgets and exclusions. Two
  behaviors were found while reading and are stated rather than fixed: Clojure
  ignores a second `ns` form without a diagnostic, and the Java same-package rule
  can record a fact across build modules that share a package name (follow-up
  003, an existing accepted semantic limitation).
- A legend maps each outcome (fact, unresolved, approximate, unsupported,
  unavailable, failed, confirmed absence, stale) to where it appears in results,
  as `CONFORMANCE.md` requires a matrix to distinguish them, and says that no
  current producer emits approximate assertions.
- Required statements are present: Zig references and calls are same-unit only
  (follow-up 006); Clojure calls are narrow and symbols under forms that may bind
  names are not facts (follow-up 008); the Java invocation rule as narrowed in
  Stage 2.5.
- Consent wording sits next to both configuration examples (README and the
  reference's new "Data Leaving The Server" section) and in the matrix's MCP
  section. It names source text and source-derived graph values separately,
  lists the values always returned, says a hosted client may forward them, says
  exactly what `--allow-evidence-text` adds, and says semidx cannot enforce the
  client's onward transmission. It implies no control over a third-party client.
- Follow-up 005 stays open: its release-notes privacy section is a Stage 5
  decision and the data-level allowlist question is unresolved. The follow-up
  records what Stage 3 did.
- `SPEC.md`'s older sentence "There is still no capability matrix" was corrected
  to "no published coverage matrix", which stays true.

Verification:

| Check | Result |
| --- | --- |
| Relative links in changed documents resolve | Pass |
| Stable-contract wording in the matrix | None: the matrix states it is unversioned and not a contract |
| `zig build test --summary all` (no code changed; default no-source-text tests) | Pass, 183/183 |
| `./scripts/check-agent-attribution.sh --all` | Pass |
| `git diff --check` | Pass |

## Stage 3.5: Refresh Failure Recovery

Changed files: `src/core/graph.zig` (`Graph.IdFloor`, `Graph.initAfter`,
`Graph.idFloor`, core test), `src/root.zig` (`Index.initAfter`),
`src/mcp/root.zig` (`Server.refresh`, `recoverFrom`, `rebuild`, tests),
`src/mcp/tools.zig` (`Recovery` in health), `docs/mcp/local_preview.md`,
`docs/spec/capability_matrix.md`, `MEMORY.md`.

### What a failure left behind (evidence before the fix)

`Index.applyScan`, its `Upkeep`, and `Graph.publish` were read first. Mutation
is spread across the graph's entity, assertion, diagnostic, and definition
tables, `unit_paths`, `dependencies`, and the analyzer's Java package hints
outside the graph; `setSourceUnitBytes` frees replaced contents; only the string
pool is append-only.

A temporary failure-injection test (not committed) built an index of a small
tree (a Java class other units resolve against, a Java dependent, two Zig
units), then applied a rescan that renames the class, edits one Zig unit,
removes the other, and adds one. For every allocation index `k` of that
`applyScan` it failed allocation `k`, retried the same scan on the same index,
published, and compared a content projection (units, entities, relationships,
diagnostics, with freshness and resolution, without ids) against a fresh index
of the new tree:

| Outcome over 86 failure points | Count |
| --- | --- |
| Retry converged to the fresh-index graph | 18 |
| Retry succeeded but `publish` refused the graph (invariant violation) | 45 |
| Retry published a graph different from the fresh index | 23 |

The first divergence (`k = 12`): the failure hit while removing `gone.zig`
after the unit was tombstoned but before its entities were removed. The retry no
longer saw the unit as known, so the graph kept a current `function gone`
definition and `DEFINES` fact for a file that no longer exists. The plan's
lost-invalidation hypothesis is therefore not the mechanism observed first, but
the broader claim is confirmed: a failed refresh poisons later refreshes, both
by blocking publication and by publishing wrong current facts.

### Strategy

Chosen: **rebuild after failure, above the old ids.** When `applyScan` or
`publish` fails during a refresh, the server treats the index as untrusted,
builds a fresh index from the same scan with `Index.initAfter`, and makes it the
index. The published snapshot is not touched; the index it borrows strings from
is kept as `retired` until the next successful refresh publishes the rebuilt
index and releases it. If the rebuild fails too, the server is `poisoned` and
the next refresh rebuilds before reconciling. A scan failure happens before any
mutation and triggers no rebuild.

`Graph.IdFloor` makes the unavoidable identity loss observable: a graph built
with a floor fills the lower entity and unit ids with tombstones (never live,
never published, never matched, carrying no assertion), starts assertion ids
above the old ones, and starts its revision after the old one. An id from an
earlier snapshot therefore names nothing in the rebuilt graph instead of a
different entity, and revisions never go backwards. The refresh that publishes a
rebuilt index reports `entity_ids_preserved: false`; `semidx_health` reports
`recovery` (rebuild count, rebuilt index awaiting publication, rebuild still
needed).

Rejected:

- Exact rollback (checkpoint before `applyScan`, restore on failure). It needs a
  transactional boundary across every graph table, `dependencies`, the analyzer's
  package hints, and deferred freeing of replaced unit contents; the 86-point
  experiment showed how many partial states exist, and a missed field would
  reintroduce silent poisoning. Rejected on risk.
- Reconciling every refresh into a staged copy and swapping on success. A fresh
  staged index on every refresh loses identity on successful refreshes too,
  which the plan forbids; a deep copy of the live index carries the same
  field-coverage risk as rollback.

Consequences within the plan's boundary: no persistence, storage layer, or
snapshot representation change; the success path of `applyScan` is unchanged, so
affected-region work bounds and the repository-scale tests are unaffected.
Identity is lost only for a refresh that failed, and that loss is observable.

### Tests

- `a graph built after another issues none of its ids and no earlier revision`
  (core): ids and revision above the floor, tombstones publish nothing, old ids
  resolve to nothing.
- `a refresh that fails at any allocation publishes nothing half-applied and the
  next refresh converges` (MCP): a one-shot allocation failure at every
  allocation of a refresh over the tree above. For each point: (1) the published
  snapshot is unchanged, or, when only the response was lost, equals the fresh
  index; (2) the next successful refresh equals a fresh index of the tree; (3)
  every entity id from the earlier snapshot names nothing when the refresh
  reports `entity_ids_preserved: false`, and otherwise names the same entity
  (kind, role, name, path).
- `when rebuilding after a failed refresh also fails, the next refresh rebuilds
  and converges` (MCP): the same with every allocation from the failure point on
  failing, so the rebuild fails as well and the next refresh must rebuild.

Both MCP tests covered 87 failure points each, 76 of which triggered a rebuild
(counted with a temporary print, removed).

Risk matrix:

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| A failed refresh changes no answer (plan Stage 3.5) | Half-applied state published | Integration with failure injection | `Server.refresh` | Every allocation point, one-shot and sticky | both MCP recovery tests |
| The next refresh equals a fresh index (plan Stage 3.5, constitution §5) | Poisoned index reconciled again | Integration against a fresh-index oracle | `Server.rebuild` | Rebuild itself failing | sticky-failure test |
| Identity loss is observable, never reassignment (plan Stage 3.5, constitution §4) | Old id names another entity after rebuild | Unit + integration | `Graph.initAfter` floor | Rebuild without a floor | core floor test; mutation below |
| Success path unchanged | Work bounds regress | Existing repository-scale tests | `Index.applyScan` untouched | — | full lane |

Verification:

| Command | Result |
| --- | --- |
| Failure-injection experiment before the fix (temporary test) | 86 points: 18 converge, 45 publish refused, 23 wrong graph |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | Pass, 88/88 |
| `zig build test-mcp --summary all` | Pass, 18/18 |
| `zig build test --summary all` | Pass, 186/186 |
| Mutation: refresh reports the failure without rebuilding (previous behavior) | Both MCP recovery tests fail; restored |
| Mutation: rebuild without the id floor (revision kept) | Both MCP recovery tests fail on guarantee 3; restored |

Mistakes made while proving this, recorded because they changed the evidence:

- The first no-floor mutation (`if (true) .{} else floor`) did not compile, so
  its failure proved nothing; it was replaced by a mutation that compiles.
- The next run failed guarantee 3 for the wrong reason: the test kept entity
  structs whose strings belonged to an index a successful refresh releases, and
  read freed memory. The test now copies what it compares.
- With that fixed, the no-floor mutation passed: the check compared kind, role,
  and unit scope, and a deterministic rebuild reproduces those for the same id.
  The check now requires that old ids name nothing whenever the refresh reports
  `entity_ids_preserved: false`, and otherwise compares kind, role, name, and
  path. The mutation then failed as intended.

Residual risk:

- Memory freed on allocation-failure paths is not checked: the injection tests
  run over the C allocator, because leak detection under injected failures is a
  separate property the plan does not require.
- A rebuild re-reads every unit, so recovery costs a full index build; it runs
  only after a failed refresh.
- Only allocation failures were injected. An analyzer or graph error surfaces
  through the same `applyScan` and `publish` error paths, so the same recovery
  applies, but no test injects one directly.
