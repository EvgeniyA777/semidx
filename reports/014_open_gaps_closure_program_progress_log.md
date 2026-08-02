---
title: "Open Gaps Closure Program Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-08-02"
---

# Open Gaps Closure Program Progress Log

Tracks execution of `plans/013_open_gaps_closure_program.md`.

## Prerequisite Baseline Unblock

- Status: completed.
- Summary: Removed stale demonstration `constraints.snapshot_id` pins from runnable query examples so `scripts/run-mvp-gates.sh` can execute examples against the current worktree index without weakening runtime snapshot-bound validation.
- Commit: `cbb3782 test: unpin runnable query examples`.
- Verification:
  - `./scripts/validate-contracts.sh` passed (`checked_json_files=61`, `contracts_validation=ok`).
  - `./scripts/run-mvp-gates.sh` passed with local socket permissions (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, `mvp_gates=ok`).
- Notes: The non-escalated sandbox run failed with `java.net.SocketException: Operation not permitted` while binding local HTTP/MCP test sockets; the same gate passed when rerun with local socket permissions.

## Stage 1.1 - Shared Language Helpers

- Status: completed.
- Scope: Extract shared scanning, signature, token, unit-boundary, and tree-sitter CLI/config/CST helpers into `semidx.runtime.languages.shared` while preserving existing private helper names in callers through wrappers.
- Architecture plan:
  - Goal: reduce duplicated language-lane infrastructure without changing parser behavior.
  - Boundary: `semidx.runtime.languages.shared` owns generic line/token/tree-sitter helper mechanics; language lanes keep language-specific regexes, parsing policy, AST interpretation, and semantic-core logic.
  - Contract direction: lane modules depend on the shared helper namespace; shared helpers do not depend on lane modules.
  - Sequencing: keep adapters and extracted lanes on wrapper functions first, then move full Clojure/Java/Python/Lua lane bodies in later sub-steps.
- Changed files:
  - `src/semidx/runtime/languages/shared.clj`
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/typescript.clj`
  - `src/semidx/runtime/languages/elixir.clj`
  - `src/semidx/runtime/languages/elixir/shared.clj`
  - `src/semidx/runtime/languages/css.clj`
  - `src/semidx/runtime/languages/html.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for all touched namespaces.
  - Shared tree-sitter config path smoke passed for default and TypeScript-prefixed filenames.
  - `clojure -M:test -n semidx.integration.typescript-onboarding-test` passed (`3 tests / 11 assertions`).
  - `clojure -M:test -n semidx.integration.css-onboarding-test` passed (`2 tests / 16 assertions`).
  - `clojure -M:test -n semidx.integration.html-onboarding-test` passed (`2 tests / 16 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/validate-language-onboarding.sh typescript --skip-gates` passed structural checks.
  - `./scripts/validate-language-onboarding.sh html --skip-gates` passed structural checks.
  - `./scripts/validate-language-onboarding.sh css --skip-gates` passed structural checks.
  - `./scripts/run-mvp-gates.sh` passed with local socket permissions (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing CCC artifacts.
- Skipped / limitations:
  - `./scripts/validate-language-onboarding.sh elixir --skip-gates` failed because the validator expects legacy `elixir-happy-path.json` / `elixir-ambiguity.json` fixtures and old adapter-branch patterns; current Elixir coverage is through existing Elixir benchmark fixtures and full test gates.
- Known blockers: none.

## Stage 1.2 - Clojure Lane Extraction

- Status: completed.
- Scope: Move the Clojure parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.clojure`, including regex fallback, clj-kondo primary parsing, optional tree-sitter extraction, Clojure call extraction, multimethod/protocol handling, and parser diagnostics.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.clojure` the real Clojure lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Clojure-specific parsing internals live in the Clojure lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-clojure-file` facade and updated tests to redefine `clj-language/parse-file` directly.
  - Shared helper follow-up: centralized `safe-line` implementation in `semidx.runtime.languages.shared` because current non-Clojure adapter paths, including TypeScript tree-sitter extraction, still use the same line-signature behavior.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/clojure.clj`
  - `src/semidx/runtime/languages/shared.clj`
  - `test/semidx/integration/runtime_test.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.shared`, `semidx.runtime.languages.clojure`, and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.3 - Java Lane Extraction

- Status: completed.
- Scope: Move the Java parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.java`, including Java regex parsing, optional tree-sitter extraction, overload/constructor unit identity, superclass metadata, static-import ownership, method references, and call arity indexing.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.java` the real Java lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Java-specific regexes, call extraction, parser policy, and tree-sitter interpretation live in the Java lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-java-file` facade and dispatches directly to `java-language/parse-file`.
  - Dependency cleanup: removed Java-only `edn`, `sh`, and `set` namespace requirements from `semidx.runtime.adapters` after the move.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/java.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.java` and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.4 - Python Lane Extraction

- Status: completed.
- Scope: Move the Python parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.python`, including Python module normalization, import and relative-import expansion, class/method ownership, self/class call expansion, local symbol collision handling, nested-scope suppression, and test-target module linkage.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.python` the real Python lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Python-specific regexes, import state, call extraction, parser policy, and semantic ownership logic live in the Python lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-python-file` facade and dispatches directly to `py-language/parse-file`.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/python.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.python` and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.5 - Lua Lane Extraction

- Status: completed.
- Scope: Move the Lua parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.lua`, including Lua module normalization, `require` import tracking, table/function/method ownership, returned-module owner detection, local call suppression, and test-target module linkage.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.lua` the real Lua lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Lua-specific regexes, import state, call extraction, parser policy, and module ownership logic live in the Lua lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-lua-file` facade and dispatches directly to `lua-language/parse-file`.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/lua.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.lua` and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.lua-onboarding-test` passed (`2 tests / 7 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`230 tests / 1614 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`230 tests / 1614 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing CCC artifacts.
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.6 - TypeScript Legacy Adapter Cleanup

- Status: completed.
- Scope: Remove the remaining legacy TypeScript parser block from `semidx.runtime.adapters` after the TypeScript lane already owned the implementation, and route TypeScript/JavaScript dispatch directly to their language namespaces.
- Architecture plan:
  - Goal: keep adapters as a cross-language dispatcher only, without carrying duplicate TypeScript regex/tree-sitter parsing or compatibility fallbacks.
  - Boundary: `semidx.runtime.languages.typescript` owns TypeScript regex parsing, optional tree-sitter parsing, import/call expansion, object-literal/class-field/default-export/re-export extraction, and parser diagnostics; `semidx.runtime.languages.javascript` owns JavaScript parse dispatch and language tagging.
  - Cleanup: removed adapter-level TypeScript regexes, tree-sitter helpers, `parse-typescript-legacy`, `parse-typescript`, and the private `parse-javascript` wrapper.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.adapters`, `semidx.runtime.languages.typescript`, and `semidx.runtime.languages.javascript`.
  - `clojure -M:test -n semidx.integration.typescript-onboarding-test` passed (`3 tests / 11 assertions`).
  - `clojure -M:test -n semidx.integration.javascript-onboarding-test` passed (`4 tests / 34 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`230 tests / 1614 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`230 tests / 1614 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1 Closure - Adapter Facade Boundary

- Status: completed.
- Summary: Stage 1 is closed. `semidx.runtime.adapters` is now a thin public dispatch facade over per-language lane namespaces plus shared language helpers, and the remaining adapter-private TypeScript compatibility block has been removed instead of carried forward.
- Decision record: `ADR-035 Split Language Lanes Out Of The Adapter Facade`.
- Completed stage commits:
  - `bc9117f refactor: extract shared language helpers`.
  - `7d3f4ae refactor: move clojure lane out of adapters`.
  - `06201dd refactor: move java lane out of adapters`.
  - `12c2605 refactor: move python lane out of adapters`.
  - `0b4d630 refactor: move lua lane out of adapters`.
  - `29188ef refactor: remove typescript legacy adapter block`.
- Verification baseline at closure:
  - Compile probes passed for touched parser namespaces during each sub-stage.
  - Focused language/runtime suites passed during each sub-stage.
  - Latest full gate set passed: `clojure -M:test` (`230 tests / 1614 assertions`), `./scripts/run-benchmarks.sh` (`21/21` fixtures), `./scripts/run-semantic-quality-report.sh` (`advisory_failure` with unchanged baseline metrics), `./scripts/run-mvp-gates.sh` (`mvp_gates=ok`), and `clojure -M:ccc check --root .`.
- Next stage: Stage 2 - remove the hard runtime dependency on an externally installed tree-sitter CLI.
- Skipped / limitations: external reviewer loop was not run inside this documentation-only closure commit; implementation sub-stage verification is recorded above.
- Known blockers: none.

## Stage 2.1 - Tree-Sitter Toolchain Strategy ADR

- Status: completed.
- Scope: Decide and record the Stage 2 strategy for removing the hard runtime dependency on an externally installed `tree-sitter` CLI, and repair stale ADR placeholder references in `plans/013`.
- Decision record: `ADR-036 Use A Repo-Managed Tree-Sitter Toolchain`.
- Summary:
  - Regex parsing remains the guaranteed default.
  - Tree-sitter remains an optional accelerated parser path.
  - Runtime acceleration must resolve through explicit parser options, environment configuration, and a repository-managed toolchain provisioned by the grammar bootstrap path, with ambient `PATH` only as a developer fallback.
  - `plans/013` now references real accepted ADRs for Stage 1 (`ADR-035`) and Stage 2 (`ADR-036`), points Stage 3 at the accepted relation-first fork (`ADR-034`) plus a future scoping ADR, and avoids reusing occupied ADR numbers for later stages.
- Changed files:
  - `adr/036-use-a-repo-managed-tree-sitter-toolchain.md`
  - `plans/013_open_gaps_closure_program.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapping completed for shared tree-sitter helpers and Clojure/Java/TypeScript lane callers.
  - `git diff --check` passed.
  - `clojure -M:ccc check --root .` passed.
- Skipped / limitations: runtime tests and gates are deferred to the implementation sub-step because this commit records the strategy and plan repair only.
- Known blockers: none.

## Stage 2.2 - Repo-Managed Tree-Sitter Toolchain Resolution

- Status: completed.
- Scope: Implement `ADR-036` in runtime helpers and bootstrap tooling without changing the default parser path.
- Summary:
  - Regex parsing remains the guaranteed default.
  - Tree-sitter acceleration now resolves the CLI through explicit parser options, environment configuration, the repo-managed `.tree-sitter-grammars/bin/tree-sitter` link, then ambient `PATH` as a developer fallback.
  - Language lanes pass parser opts through tree-sitter availability probes and CST calls, so explicit missing CLI paths degrade through the existing unavailable-acceleration diagnostics instead of silently using an unrelated global executable.
  - The grammar bootstrap script now verifies/provisions a managed CLI link and can emit `SEMIDX_TREE_SITTER_CLI_PATH` alongside pinned grammar env vars.
- Changed files:
  - `src/semidx/runtime/languages/shared.clj`
  - `src/semidx/runtime/languages/clojure.clj`
  - `src/semidx/runtime/languages/elixir.clj`
  - `src/semidx/runtime/languages/java.clj`
  - `src/semidx/runtime/languages/typescript.clj`
  - `test/semidx/integration/runtime_test.clj`
  - `scripts/setup-tree-sitter-grammars.sh`
  - `docs/runtime-api.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - `bash -n scripts/setup-tree-sitter-grammars.sh` passed.
  - Compile probe passed for `semidx.runtime.languages.shared`, `semidx.runtime.languages.clojure`, `semidx.runtime.languages.java`, `semidx.runtime.languages.typescript`, and `semidx.runtime.languages.elixir`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`104 tests / 472 assertions`).
  - `clojure -M:test -n semidx.integration.typescript-onboarding-test` passed (`3 tests / 11 assertions`).
  - `clojure -M:test` passed (`231 tests / 1618 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`237 tests / 1638 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing `docs/code-context.md`.
  - `git diff --check` passed.
- Skipped / limitations: the bootstrap script syntax was verified locally, but the networked grammar clone/fetch path was not rerun during this sub-step.
- Known blockers: none.

## Stage 3.1 - Interprocedural Dataflow V1 Scoping ADR

- Status: completed.
- Scope: Define the Stage 3 v1 dataflow scope required by `ADR-034` before implementation begins.
- Decision record: `ADR-037 Scope Interprocedural Dataflow V1`.
- Summary:
  - Stage 3 starts by adding a typed-relation schema/index boundary rather than adding ad-hoc dataflow keys to `semantic-ir`.
  - V1 relation types are `dataflow/local-binding-call-result`, `dataflow/returns-call-result`, and `dataflow/passes-argument`.
  - Lane order is Clojure first, Python second; TypeScript, Java, and Elixir producers are deferred until the first slice is measured.
  - Retrieval and impact may consume relations only through bounded relation-index projections; no public `query_relations` API, context-packet relation array, caller/callee replacement, or `calls`/`imports` dual-write lands in Stage 3.
- Changed files:
  - `adr/037-scope-interprocedural-dataflow-v1.md`
  - `plans/013_open_gaps_closure_program.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapping completed for existing Semantic IR, index graph, retrieval, storage, and evaluation seams.
  - Documentation cross-reference checks passed for Stage 3 / ADR links.
  - `git diff --check` passed.
- Skipped / limitations: runtime tests and gates are deferred to the implementation sub-step because this commit records the Stage 3 architecture scope only.
- Known blockers: none.

## Stage 3.2 - Relation Substrate And Empty Snapshot Indexes

- Status: completed.
- Scope: Add the typed-relation substrate from `ADR-037` without producing dataflow facts or changing retrieval behavior.
- Summary:
  - Added `semidx.runtime.relations` for relation normalization, deterministic `relation_id` generation, schema versioning, validation, and forward/reverse relation index construction.
  - `semidx.runtime.index/build-index-state` now attaches `:relations`, `:relation_forward_index`, and `:relation_reverse_index` to every snapshot.
  - Existing `:callers_index` / `:callees_index` behavior remains unchanged; no producers, retrieval projections, public graph API, or `calls`/`imports` migration are included in this sub-step.
- Changed files:
  - `src/semidx/runtime/relations.clj`
  - `src/semidx/runtime/index.clj`
  - `test/semidx/runtime/relations_test.clj`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapping completed for `semantic-ir`, index graph, storage, retrieval, and runtime test seams.
  - clojure-mcp REPL smoke passed for `semidx.runtime.relations/normalize-relation` and `valid-relation?`.
  - Compile probe passed for `semidx.runtime.relations`, `semidx.runtime.index`, and `semidx.runtime.storage`.
  - `clojure -M:test -n semidx.runtime.relations-test` passed (`3 tests / 16 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`104 tests / 472 assertions`).
  - `clojure -M:test` passed (`240 tests / 1654 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`240 tests / 1654 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing `docs/code-context.md`.
  - `git diff --check` passed.
- Skipped / limitations: no dataflow producers or retrieval projections were implemented in this sub-step by design.
- Known blockers: none.

## Stage 3.3 - Clojure Dataflow Relation Producer

- Status: completed.
- Scope: Emit the accepted `ADR-037` v1 dataflow relation facts from the Clojure lane and resolve relation targets during index construction.
- Summary:
  - Clojure regex, clj-kondo, and tree-sitter parsing now detach per-unit producer facts into top-level parsed-file `:relations` without adding ad-hoc flow keys to `semantic_ir.clj`.
  - The Clojure producer emits `dataflow/local-binding-call-result`, `dataflow/returns-call-result`, and `dataflow/passes-argument` facts with `target_key`, local/argument payload where relevant, medium evidence quality, and producer provenance.
  - `semidx.runtime.index/build-index-state` resolves relation `target_key` values through the existing call-token resolver into `target_unit_ids` and marks facts `resolved`, `ambiguous`, or `unresolved`.
  - Relation IDs now include argument payload fields such as `:local_name` and `:arg_index`, preventing same-call argument-flow facts from collapsing into one relation.
  - Existing `:callers_index` / `:callees_index` behavior remains unchanged; no Python producer, retrieval projection, public graph API, or `calls`/`imports` migration is included in this sub-step.
- Changed files:
  - `src/semidx/runtime/languages/clojure.clj`
  - `src/semidx/runtime/index.clj`
  - `src/semidx/runtime/relations.clj`
  - `test/semidx/integration/runtime_test.clj`
  - `test/semidx/runtime/relations_test.clj`
  - `plans/013_open_gaps_closure_program.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapping completed for the Clojure lane, semantic IR finalization, index graph, relation substrate, and runtime test seams before implementation.
  - clojure-mcp REPL reload passed for `semidx.runtime.languages.clojure`, `semidx.runtime.index`, and `semidx.runtime.relations`.
  - `clojure -M:test -n semidx.runtime.relations-test` passed (`4 tests / 17 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`105 tests / 477 assertions`).
  - `clojure -M:test` passed (`242 tests / 1660 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`242 tests / 1660 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing `docs/code-context.md`.
  - `git diff --check` passed.
- Skipped / limitations: Python producer and relation-backed retrieval/impact projections are deferred to later Stage 3 sub-steps by design.
- Known blockers: none.

## Stage 3.4 - Python Dataflow Relation Producer

- Status: completed.
- Scope: Emit the accepted `ADR-037` v1 dataflow relation facts from the Python lane on the same relation contract as the Clojure producer.
- Summary:
  - Python parsing now detaches per-unit producer facts into top-level parsed-file `:relations` without adding ad-hoc flow keys to `semantic_ir.clj`.
  - The Python producer emits `dataflow/local-binding-call-result`, `dataflow/returns-call-result`, and `dataflow/passes-argument` facts for direct assignment, return-call, and argument-passing shapes.
  - Relation target keys reuse the Python lane's existing alias/import/self/class-name expansion helpers so `semidx.runtime.index/build-index-state` can resolve them through the shared relation resolver.
  - Nested local defs/classes remain conservative through the existing Python body-local suppression sets.
  - Existing `:callers_index` / `:callees_index` behavior remains unchanged; no retrieval projection, public graph API, or `calls`/`imports` migration is included in this sub-step.
- Changed files:
  - `src/semidx/runtime/languages/python.clj`
  - `test/semidx/integration/runtime_test.clj`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapping completed for the Python lane, index relation resolver, relation substrate, and runtime test seams before implementation.
  - clojure-mcp REPL reload passed for `semidx.runtime.languages.python`, `semidx.runtime.index`, and `semidx.runtime.relations`.
  - clojure-mcp REPL smoke confirmed Python parsed-file `:relations` for a wrapper function with local binding, return-call, and argument-pass facts.
  - `clojure -M:test -n semidx.runtime.relations-test` passed (`4 tests / 17 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`106 tests / 483 assertions`).
  - `clojure -M:test` passed (`243 tests / 1666 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`243 tests / 1666 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing `docs/code-context.md`.
  - `git diff --check` passed.
- Skipped / limitations: relation-backed retrieval/impact projections are deferred to the next Stage 3 sub-step by design.
- Known blockers: none.

## Stage 3 Architecture Re-review - 2026-08-01

- Status: completed.
- Scope: Reconcile the accepted relation-first direction from ADR-034,
  ADR-037, and ADR-038 with the current relation substrate, retrieval/storage
  boundaries, and the agreed provider/product sequence.
- Verification performed:
  - semidx MCP `create_index -> repo_map -> resolve_context -> expand_context -> fetch_context_detail` completed against the current repository.
  - Exact snapshot-bound slices confirmed that relation indexes exist while
    `build-impact-hints` still consumes legacy caller/module/test indexes.
  - `git diff --check` passed after documentation corrections.
  - Full runtime tests were not rerun because this review changed planning and
    progress documentation only.

### Findings And Disposition

1. **High - semantic relation identity includes mutable evidence and resolution.**
   - Evidence: `relation-id-input` includes `target_unit_ids`,
     `resolution_status`, `evidence_quality`, `provenance`, and
     `evidence_location`.
   - Impact: unresolved-to-resolved transitions and additional SCIP/compiler
     evidence create replacement or duplicate semantic edges instead of
     enriching one fact.
   - Disposition: accepted; implementation required before relation-backed
     consumers. Record the durable identity/evidence split in the next ADR.

2. **High - Stage 3 and Stage 4 both implied ownership of traversal semantics.**
   - Evidence: Stage 3 required bounded retrieval projections while Stage 4
     placed bounded traversal directly in storage.
   - Impact: duplicate in-memory and storage-specific graph semantics could
     diverge.
   - Disposition: accepted; planning fixed. Stage 3 now owns the pure bounded
     traversal kernel and internal consumers; Stage 4 productizes that contract
     and adds persistent execution parity.

3. **High - the agreed Protobuf/OpenAPI vertical slice was absent from the
   executable sequence.**
   - Impact: ADR-038 named future providers but no active stage delivered the
     cross-language contract trace.
   - Disposition: accepted; planning fixed by adding the post-Stage-4 product
     sequence. A dedicated implementation plan is still required before work.

4. **Medium - relation validation is permissive and silently drops invalid
   facts.**
   - Evidence: `valid-relation?` checks only basic presence and
     `normalize-relations` filters invalid facts without diagnostics.
   - Disposition: accepted; schema hardening and structured diagnostics are a
     Stage 3 prerequisite.

5. **Medium - v1 unit-centric endpoints are insufficient for contract and
   document providers.**
   - Disposition: accepted and deferred to the provider tranche; additive
     endpoint/entity references must land before Protobuf/OpenAPI/SCIP emitters.

6. **Medium - PostgreSQL Stage 4 lacked an explicit typed-relation physical
   projection.**
   - Evidence: current storage has snapshot, unit, and legacy call-edge tables,
     but no `semantic_index_relations` table.
   - Disposition: accepted; planning fixed to require snapshot/repository scope,
     relation/evidence indexes, migration policy, and parity with the pure
     traversal kernel.

7. **Medium - active planning metadata and references were stale.**
   - Evidence: the program remained `planned`, referenced a nonexistent
     `reports/010_open_gaps_closure_program_progress_log.md`, and the
     architecture assessment still described Stage 1 as incomplete.
   - Disposition: fixed in planning documentation on 2026-08-01; implementation
     status remains Stage 3 in progress.

### Follow-up Sequence

1. Write the relation identity/evidence ADR and implement schema hardening.
2. Implement and verify the pure bounded traversal kernel.
3. Wire reason-coded relation support into retrieval and impact analysis.
4. Complete Stage 4 persistence/public contract work.
5. Create the provider/contract-linking implementation plan.

### Out-of-scope Observation

The review also found stale `repo_identity` metadata when a source snapshot is
reused after documentation-only commits. The independent reproduction is in
`notes/2026-08-01-reused-index-stale-repo-identity.md`; no runtime fix was made
as part of this planning review.

## Stage 3.5 - Relation Identity/Evidence Split And Validation Hardening

- Status: completed.
- Scope: Implement the re-review Follow-up Sequence steps 1 and the schema-hardening
  half of Stage 3 sub-steps 3-4: separate semantic relation identity from mutable
  resolution/evidence and replace permissive validation plus silent invalid-fact
  filtering with an explicit internal schema and structured diagnostics. This is
  the prerequisite for the bounded traversal kernel and relation-backed consumers.
- Decision record: `ADR-039 Separate Relation Identity From Resolution And Evidence`.
- Summary:
  - `relation-id-input` (and therefore `relation_id`) now derives only from
    `relation_type`, `source_unit_id`, `target_key`, and flow payload
    (`local_name` / `arg_index`) scoped by `relation_schema_version`. Mutable
    `target_unit_ids`, `resolution_status`, `evidence_quality`, `provenance`, and
    `evidence_location` are excluded, so resolving an unresolved fact or attaching
    richer evidence enriches one semantic edge instead of minting a second one.
  - Added `relation-types`, `resolution-statuses`, and `evidence-qualities` value
    sets plus `relation-errors`, the explicit internal schema returning structured
    `{:code :field :message}` errors. It rejects non-map facts, missing
    `relation_id`/`source_unit_id`, unknown relation type/status/evidence quality,
    schema-version mismatch, resolved-without-targets, and non-map
    `evidence_location`/`provenance`. Ambiguous/unresolved facts stay conservative.
  - `valid-relation?` is now an empty `relation-errors`;
    `normalize-relations-with-diagnostics` partitions valid relations from
    diagnostics; `index-relations` and `build-index-state` surface invalid facts as
    snapshot `:relation_diagnostics` instead of dropping them silently.
- Changed files:
  - `src/semidx/runtime/relations.clj`
  - `src/semidx/runtime/index.clj`
  - `test/semidx/runtime/relations_test.clj`
  - `adr/039-separate-relation-identity-from-resolution-and-evidence.md`
  - `plans/013_open_gaps_closure_program.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP `create_index -> resolve_context` mapping located the relation
    substrate and index resolution seams before editing.
  - clojure-mcp REPL smoke confirmed `relation_id` stability across
    unresolved->resolved with growing evidence, structured diagnostics for invalid
    facts, and a real Clojure index build emitting 4 resolved relations with zero
    false diagnostics.
  - `clojure -M:test -n semidx.runtime.relations-test` passed (`7 tests / 29 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`106 tests / 483 assertions`).
  - `clojure -M:test` passed (`246 tests / 1678 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`mvp_gates=ok`, `21/21` retrieval benchmarks, all query smokes).
- Review findings (`/code-review high` on the stage diff, `HEAD~1`):
  - No correctness regressions. New validation is a strict superset of the old
    presence checks; the only narrowing (unknown `relation_type` now rejected)
    is safe because every producer emits one of the three known v1 types.
  - Low - identity derives from `target_key` and excludes resolved
    `target_unit_ids`, so a future provider emitting resolved unit ids without a
    symbolic `target_key` could collapse distinct edges into one `relation_id`.
    Disposition: accepted/deferred - no current producer hits this (Clojure and
    Python emit `target_key`; index resolution fills `target_unit_ids`), and it
    is already tracked by the 2026-08-01 re-review Finding #5 (provider endpoint
    tranche).
  - Low - `relation-errors` is computed twice for invalid relations
    (group-by predicate plus `relation-diagnostic`). Disposition: rejected;
    cold path only (real pipeline yields zero invalid facts) and current form is
    more readable.
- Skipped / limitations: bounded traversal kernel and relation-backed retrieval/impact projections remain deferred to the next Stage 3 sub-step by design.
- Known blockers: none.

## Stage 3.6 - Bounded Relation Traversal Kernel

- Status: completed.
- Scope: Implement Stage 3 sub-step 5, the pure, storage-independent bounded
  traversal kernel over the relation indexes. No consumer is wired to it and no
  public graph-query API is exposed (deferred to later Stage 3 / Stage 4).
- Summary:
  - Added `semidx.runtime.relations/traverse-relations`, a breadth-first walk
    over `:relations` / `:relation_forward_index` / `:relation_reverse_index`.
  - Requests specify `:direction` (`:downstream` source->target /
    `:upstream` target->source), `:start_nodes`, a `:relation_types` allow-list,
    `:resolved_only` (default true, so ambiguous/unresolved edges are skipped),
    and `:max_depth`/`:max_nodes`/`:max_paths` clamped to
    `default-traversal-bounds` (depth 4 / 200 nodes / 50 paths). Requested
    budgets may lower but not exceed the ceiling.
  - Traversal is cycle-safe (each node discovered once at its shortest depth,
    cross/back edges recorded without re-expansion) and deterministic (neighbors
    sorted by `[relation_id to]`, FIFO queue, ordered accumulators), so output
    does not depend on set iteration order.
  - Returns `{:direction :start_nodes :relation_types :budgets :nodes :edges
    :paths :truncated}`; `:truncated` flags `:max_depth`/`:max_nodes`/`:max_paths`
    budget hits. An unknown direction throws `ex-info` with
    `:error_code :invalid_traversal_request`.
- Changed files:
  - `src/semidx/runtime/relations.clj`
  - `test/semidx/runtime/relations_test.clj`
  - `plans/013_open_gaps_closure_program.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `docs/code-context.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - clojure-mcp REPL smoke confirmed downstream/upstream direction, depth
    ceiling clamping, relation-type filtering, `:resolved_only` conservatism
    (ambiguous excluded by default, fanned out only when disabled), 2-node cycle
    termination, node/path budget truncation flags, and run-to-run determinism.
  - `clojure -M:test -n semidx.runtime.relations-test` passed (`13 tests / 46 assertions`).
  - `clojure -M:test` passed (`252 tests / 1695 assertions`).
  - `./scripts/run-mvp-gates.sh` passed (`mvp_gates=ok`, `21/21` retrieval benchmarks, all query smokes).
- Review findings (`/code-review high` on the stage diff, `HEAD~1`):
  - Low (fixed) - the budget clamp treated any non-positive requested value as
    "unspecified" and substituted the ceiling default, so an explicit
    `:max_depth`/`:max_nodes`/`:max_paths` of 0 was silently widened to the
    maximum, contradicting the "may lower but not exceed" contract. Fixed to
    honor non-negative budgets and clamp to `[0, ceil]` (`(max 0 (min req ceil))`),
    with a regression test asserting `:max_depth 0` yields only the start node and
    flags `:max_depth` truncation. Re-verified: `relations-test`
    (`13 tests / 49 assertions`) and `clojure -M:test` (`252 tests`) green.
  - Low (rejected) - `node-neighbors` is materialized for a node already at
    `max_depth` solely to flag `:max_depth` truncation via `(seq neighbors)`.
    Disposition: rejected; cost is bounded by `max_nodes`, and a dedicated
    existence helper adds surface for negligible savings.
- Design notes (accepted as-is): requested budgets are clamped into
  `[0, default-traversal-bounds]` (lower allowed, ceiling enforced); `:paths`
  records the breadth-first discovery path per node (bounded by `:max_paths`),
  not an exhaustive enumeration of alternative simple paths.
- Skipped / limitations: benchmarks/semantic-quality were not treated as gating
  because the kernel is an unused pure function that does not touch extraction,
  ranking, resolution, or confidence; `run-mvp-gates.sh` (which includes the
  benchmark suite) still passed. Relation-backed retrieval/impact projections
  remain the next Stage 3 sub-step.
- Known blockers: none.

## Stage 3.7 - Relation-Backed Impact Projection

- Status: completed.
- Scope: Implement Stage 3 sub-step 6, the last coding sub-step of Stage 3:
  bounded, reason-coded retrieval/impact projections that consume the
  `traverse-relations` kernel, keeping ambiguous flows conservative, preserving
  existing caller/callee/dependent/test outputs, and adding no public
  graph-query API.
- Summary:
  - `semidx.runtime.retrieval/build-impact-hints` now consumes
    `relations/traverse-relations` and attaches an optional, reason-coded
    `:relation_support` field to `impact_hints` (shared by `impact_analysis`,
    detail, and expansion packets). From the selected units it runs the bounded,
    `:resolved_only true` kernel under a conservative local sub-ceiling
    (`relation-projection-bounds`: depth 2 / 24 nodes / 12 paths) in both
    directions: `:downstream` dataflow dependencies and `:upstream` dataflow
    dependents, returned as distinct `path::symbol` strings excluding the
    selected units, plus `:reasons` codes (`relation_downstream_dataflow`,
    `relation_upstream_dataflow`, `relation_traversal_truncated`).
  - The field is omitted entirely when no resolved relation-backed unit is
    found, so the legacy `:callers`/`:dependents`/`:related_tests`/
    `:risky_neighbors` outputs stay byte-identical when there is no
    interprocedural dataflow signal. Ambiguous and unresolved relations are
    never surfaced (the kernel and the projection both default to
    `:resolved_only true`).
  - The `context_packet` and `expansion-result` `impact_hints` contracts gained
    an optional `relation_support` object (`{downstream, upstream, reasons}`) in
    both the JSON schema (`contracts/schemas/context-packet.schema.json`) and
    the malli mirror (`semidx.contracts.schemas/relation-support`). Existing
    examples remain valid because the field is optional.
  - No public graph-query API was added and no `calls`/`imports` migration was
    performed. Confidence ceilings are unchanged (documented non-bump: the
    projection is additive low-weight support, not a ranking/resolution change).
- Changed files:
  - `src/semidx/runtime/retrieval.clj`
  - `src/semidx/contracts/schemas.clj`
  - `contracts/schemas/context-packet.schema.json`
  - `test/semidx/integration/runtime_test.clj`
  - `plans/013_open_gaps_closure_program.md` (sub-step 6 marked delivered)
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `docs/code-context.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP `create_index -> resolve_context -> fetch_context_detail` mapped
    `build-impact-hints`, the detail/expansion packet assembly, and the
    `traverse-relations` kernel before editing.
  - clojure-mcp REPL smoke confirmed: upstream selection surfaces the resolved
    dataflow dependent; downstream selection surfaces resolved dependencies;
    ambiguous targets and no-relation fixtures omit `:relation_support`; the
    whole-graph selection omits it; and the display cap flags
    `relation_traversal_truncated`.
  - `./scripts/validate-contracts.sh` passed (`checked_json_files=61`,
    `contracts_validation=ok`).
  - `clojure -M:test` passed (`256 tests / 1712 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the baseline
    advisory state unchanged (`expected_change_match_rate=0.8333333333333334`,
    `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`,
    `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`).
  - `./scripts/run-mvp-gates.sh` passed (`mvp_gates=ok`, `21/21` retrieval
    benchmarks, all query smokes).
  - `clojure -M:ccc check --root .` passed after refreshing `docs/code-context.md`.
- New test coverage (`test/semidx/integration/runtime_test.clj`):
  - `impact-relation-support-surfaces-resolved-dataflow-neighbors-test` -
    upstream/downstream surfacing plus reason codes and additive legacy keys.
  - `impact-relation-support-omitted-without-resolved-dataflow-test` - omitted
    for a no-relation fixture and for whole-graph selection, legacy 4-key output
    unchanged.
  - `impact-relation-support-skips-ambiguous-targets-test` - ambiguous dataflow
    relations never surfaced.
  - `impact-relation-support-flags-and-bounds-truncation-test` - display cap and
    `relation_traversal_truncated` flag.
- Review findings (`/code-review high` on the working diff):
  - Low (fixed) - post-`(take relation-support-limit)` truncation was not
    reflected in `:truncated?`: the kernel can return up to `max_nodes` (24)
    non-start units without hitting its own budget, then the projection displayed
    only 12 and dropped the rest with no `relation_traversal_truncated` reason.
    Fixed to OR the display-cap drop into `:truncated?`; added
    `impact-relation-support-flags-and-bounds-truncation-test`.
  - Low (fixed) - `:start_nodes` were passed as `(vec selected-ids)` from a set,
    an unspecified iteration order. Changed to `(sort selected-ids)` for a
    canonical, stable, explainable start ordering that matches the kernel's
    determinism ethos.
  - No correctness regressions: legacy caller/callee/dependent/test outputs are
    preserved (new key is additive and omitted without signal), and the
    `path::symbol` display / `bounded-string` / `code` bounds match existing
    impact-hint conventions.
- Skipped / limitations: confidence-ceiling recalibration is intentionally a
  documented non-bump; PostgreSQL relation projection and the public graph-query
  surface are Stage 4 scope.
- Known blockers: none.

## Stage 4.1 - Relation Traversal Decision And Contract

- Status: completed.
- Scope: Record the bounded public relation-traversal decision and establish the
  external JSON plus runtime malli request/response contract before persistence
  and public handler implementation.
- Decision record: `ADR-040 Expose Bounded Relation Traversal As A Public Query
  Surface`.
- Current decision:
  - Reuse the Stage 3 traversal kernel and bounds; do not add a second graph walk.
  - Expose library + MCP in Stage 4; report HTTP/gRPC as `not_exposed` and defer
    those transport handlers.
  - Keep traversal semantics in the pure kernel through a batched frontier
    provider; PostgreSQL only optimizes neighbor retrieval.
  - Make the PostgreSQL relation projection forward-only; do not perform an
    implicit historical backfill in `init-storage!`.
- Worktree files in progress:
  - `adr/040-expose-bounded-relation-traversal-as-a-public-query-surface.md`
  - `contracts/schemas/relation-traversal-query.schema.json`
  - `contracts/schemas/relation-traversal-result.schema.json`
  - `contracts/examples/relation-queries/`
  - `contracts/examples/relation-results/`
  - `src/semidx/contracts/schemas.clj`
  - `src/semidx/contracts/validator.clj`
  - `contracts/examples/catalog.json`
- Commit: `81ad582 feat: define bounded relation traversal contract`.
- Verification:
  - Compile probe for `semidx.contracts.validator` passed.
  - `./scripts/validate-contracts.sh` passed
    (`checked_json_files=65`, `contracts_validation=ok`).
  - Documentation frontmatter, lifecycle/action combinations, ADR-ID uniqueness,
    local Markdown links, and `git diff --check` passed during the companion
    documentation lifecycle cleanup.
- Known blockers: none.

## Stage 4.2a - Batched Frontier Provider Kernel Seam

- Status: completed.
- Scope: Refactor the Stage 3 traversal kernel onto a batched, per-level frontier
  provider seam (ADR-040) so a PostgreSQL execution backend can later plug in
  without owning traversal semantics, while keeping the in-memory output
  byte-identical. This is the kernel-refactor part of Stage 4.2; the public
  library API and MCP `traverse_relations` tool remain follow-up work.
- Summary:
  - `semidx.runtime.relations/traverse-relations-with` now drives the bounded
    walk level by level and obtains neighbors through a provider
    `(fn [frontier-nodes direction] -> {node -> (seq relations)})`, called once
    per depth level (no N+1). All traversal policy - eligibility
    (`relation_types`, `resolved_only`), direction fan-out, deterministic
    ordering, cycle handling, and `max_depth`/`max_nodes`/`max_paths` budgets -
    stays in the kernel. The former `node-neighbors` was split into a pure
    `relations->steps` (eligibility + fan-out + deterministic sort) plus the
    `in-memory-neighbor-provider` (batched relation lookup over the snapshot
    forward/reverse indexes, no semantics).
  - `traverse-relations` is now a thin wrapper:
    `(traverse-relations-with (in-memory-neighbor-provider indexes) request)`.
    Because a whole depth level is contiguous in the original FIFO queue, level
    batching preserves the exact node/edge/path ordering, truncation flags, and
    budgets of the Stage 3 kernel.
- Changed files:
  - `src/semidx/runtime/relations.clj`
  - `test/semidx/runtime/relations_test.clj`
  - `MEMORY.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP `create_index -> resolve_context -> fetch_context_detail` mapped
    the kernel and the retrieval/impact consumers before editing.
  - REPL parity check: on a fixture with cycles, multi-target fan-out, ambiguous
    edges, node/path budget truncation, and multi-start relation-type filtering,
    the refactored `traverse-relations` output is `=` to the pre-refactor
    reference across all five cases (byte-identical).
  - New `traverse-relations-with-batched-frontier-provider-parity-test` asserts
    the provider seam equals the pure kernel and that neighbors are fetched once
    per depth level (`[#{A} #{B C} #{D E}]`), proving batched (no N+1) lookup.
  - `clojure -M:test` passed (`257 tests / 1716 assertions`).
  - `./scripts/run-mvp-gates.sh` passed (`mvp_gates=ok`, retrieval smokes green).
  - `./scripts/run-benchmarks.sh` passed (`21/21`).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the baseline
    advisory state unchanged (`expected_change_match_rate=0.8333333333333334`,
    `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`,
    `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`).
- Skipped / limitations: no PostgreSQL provider yet (Stage 4.3); no public
  library/MCP handler yet (rest of Stage 4.2).
- Known blockers: none.

## Stage 4.2b - Public Relation Traversal Surface (library + MCP)

- Status: completed.
- Scope: Expose the bounded relation traversal on the library and MCP surfaces
  (ADR-040 phased exposure: library + MCP supported; HTTP/gRPC not_exposed),
  returning the compact contract result plus a staged-retrieval selection_id.
- Summary:
  - `semidx.runtime.retrieval/relation-traversal` runs the pure kernel on a
    loaded snapshot index, validates direction/start_nodes, maps the contract
    request (`:direction`, `:start_nodes`, `:relation_types`, `:resolved_only`,
    `:budgets`) to the kernel, and returns the compact contract result
    (`schema_version`, `snapshot_id`, `direction`, `start_nodes`,
    `relation_types`, `budgets`, `nodes`, `edges`, `paths`, `truncated`).
  - `store-traversal-selection!` builds and stores a selection artifact over the
    discovered units (reusing `stage-budgets`, `fit-focus`, `build-confidence`,
    `capability-summary`, `snapshot-bound-index`, `snapshot-file-lines`,
    `put-selection!`), so the returned `selection_id` is reusable by the existing
    `expand-context` / `fetch-context-detail` flow rather than a parallel
    code-delivery mechanism.
  - `semidx.core/relation-traversal` wraps it with usage metrics (operation
    `traverse_relations`), mirroring `impact-analysis`.
  - MCP tool `traverse_relations` is registered in `tool-definitions` /
    `tool-handlers` (`semidx.mcp.core/tool-traverse-relations`) and returns the
    compact result plus `index_id` and `selection_id`.
  - `usage-operation` gained `traverse_relations` in both the JSON common schema
    and the malli mirror.
- Changed files:
  - `src/semidx/runtime/retrieval.clj`
  - `src/semidx/core.clj`
  - `src/semidx/mcp/core.clj`
  - `src/semidx/contracts/schemas.clj`
  - `contracts/schemas/common.schema.json`
  - `test/semidx/integration/runtime_test.clj`
  - `test/semidx/mcp/server_test.clj`
  - `MEMORY.md`
  - `docs/mcp-api.md`
  - `docs/code-context.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapped the selection store (`build-selection-result`,
    `put-selection!`, `ensure-selection!`), the MCP tool registration/dispatch,
    and the core/retrieval public API before editing.
  - REPL end-to-end: `sci/relation-traversal` returns a contract-valid result
    (validated against `contracts/relation-traversal-{query,result}` malli), the
    selection_id is reusable by `expand-context` (skeletons) and
    `fetch-context-detail` (raw_context), and the snapshot-mismatch guard fires.
  - REPL MCP end-to-end via `handle-tools-call`: create_index ->
    traverse_relations -> expand_context succeeds; result serializes to JSON.
  - `clojure -M:test` passed (`258 tests / 1735 assertions`), including a new
    `relation-traversal-public-surface-test` (integration) and a
    `traverse_relations` case plus updated tool-name sets in the MCP server
    conformance test.
  - `./scripts/validate-contracts.sh` passed (`checked_json_files=65`,
    `contracts_validation=ok`).
  - `./scripts/run-mvp-gates.sh` passed; `./scripts/run-benchmarks.sh` `21/21`.
- Skipped / limitations: HTTP/gRPC exposure is intentionally deferred
  (`not_exposed` per ADR-040). No new capability-contract surface-matrix field
  was added; exposure is reflected by tool presence in `tools/list` + the library
  API and documented in ADR-040. PostgreSQL projection/provider is Stage 4.3.
- Known blockers: none.

## Stage 4.3 - PostgreSQL Relation Projection And Execution Adapter

- Status: completed.
- Scope: Add the forward-only PostgreSQL `semantic_index_relations` projection and
  a PostgreSQL execution adapter for the canonical traversal contract, proven at
  parity with the pure in-memory kernel (ADR-040). Storage optimizes neighbor
  fetch; it does not own traversal semantics.
- Summary:
  - `semidx.runtime.storage` `init-storage!` now migrates a
    `semantic_index_relations` table (root_path, snapshot_id, relation_id,
    relation_type, resolution_status, source_unit_id, target_unit_id, target_key,
    evidence_quality) plus `(root_path, snapshot_id, source_unit_id)` and
    `(root_path, snapshot_id, target_unit_id)` frontier indexes. The migration
    only creates the table/indexes; it performs no historical backfill.
  - `save-index-tx!` rewrites the projection forward-only per snapshot: a scoped
    delete + one flattened row per (relation, target_unit_id) via `relation-rows`.
    Unresolved relations (no target unit ids) produce no rows, matching in-memory
    traversal semantics for unit-id nodes.
  - `storage/pg-relation-neighbor-provider` is the execution adapter: given a
    frontier and direction it issues one query per depth level
    (`source_unit_id = any(?)` downstream, `target_unit_id = any(?)` upstream) and
    returns `{node -> (seq relations)}` shaped for
    `relations/traverse-relations-with`, reconstructing `target_unit_ids` by
    grouping. No N+1. Eligibility, fan-out, ordering, cycles, and budgets stay in
    the kernel.
- Changed files:
  - `src/semidx/runtime/storage.clj`
  - `test/semidx/runtime/storage_test.clj`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `docs/code-context.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapped `storage.clj` (protocol, `PostgresStorage`,
    `save-index-tx!`, `init-storage!`) and the kernel seam before editing.
  - `postgres-init-storage-creates-relations-projection-test` and
    `save-index-tx-writes-relation-projection-rows-test` assert the migration and
    forward-only projection SQL via `with-redefs jdbc/execute!` capture.
  - `pg-relation-neighbor-provider-parity-test` (always-run) drives the kernel
    through the PG provider over `with-redefs`-served flattened rows and asserts
    byte-identical output vs the pure in-memory kernel across downstream,
    upstream, depth-capped, and node-capped requests, plus one batched query per
    depth level (no N+1).
  - `postgres-relation-traversal-roundtrip-parity-test` (gated on
    `SEMIDX_TEST_POSTGRES_URL`) proves real round-trip parity. Verified locally by
    spinning an ephemeral PostgreSQL 17 cluster (fresh initdb on a free port,
    TCP-only, unrelated project containers untouched), running the suite with the
    env set (`9 tests / 50 assertions`, 0 failures), then stopping and removing
    the cluster.
  - `clojure -M:test` passed (`262 tests / 1752 assertions`);
    `./scripts/validate-contracts.sh` `contracts_validation=ok`;
    `./scripts/run-mvp-gates.sh` `mvp_gates=ok`. CCC refreshed.
  - Benchmarks / semantic-quality were intentionally not re-run: Stage 4.3 is a
    storage/infra change with no extraction, ranking, resolution, or confidence
    impact (per the plan's delivery-loop scoping).
- Env note: the real-PostgreSQL parity env var is `SEMIDX_TEST_POSTGRES_URL`
  (the handoff/RULES wording `SCI_TEST_POSTGRES_URL` is stale; the code uses
  `SEMIDX_TEST_POSTGRES_URL`, matching `postgres-storage-roundtrip-test`).
- Skipped / limitations: HTTP/gRPC exposure remains an ADR-040 follow-up; an
  explicit reprojection command for pre-projection historical snapshots is a
  possible future addition (older snapshots have no projection rows until
  re-saved).
- Known blockers: none.
