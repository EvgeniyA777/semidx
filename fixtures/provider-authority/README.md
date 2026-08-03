# Provider-Authority Fixtures (plans/018 Stage 0)

Protected fixtures and baselines for the Semantic Provider Authority Migration
([`plans/018`](../../plans/018_semantic_provider_authority_migration_plan.md),
[`ADR-046`](../../adr/046-prefer-semantic-evidence-providers-over-structural-and-lexical-fallbacks.md),
[`ADR-047`](../../adr/047-retain-repo-managed-tree-sitter-toolchain-for-structural-providers.md)).

These fixtures exist so later stages can prove additive, non-regressing
behavior and correct cross-provider fact identity **before** any SCIP/LSP
provider work begins. Stage 0 does not change production extraction.

## Layout

- `corpus/` — a small protected Java + TypeScript mini-repo exercising
  definitions, references, calls, method overloads, and re-exports.
- `identity/` — cross-provider `CanonicalFactKey` fixtures. Each proves that
  regex / tree-sitter / SCIP / LSP spellings of the SAME fact must normalize to
  one provider-neutral key, while distinct overloads / aliases stay distinct.
- `behavior/` — protected extraction baseline (ground truth) plus degradation
  and freshness expectations (dirty files, provider unavailability).
- `baseline/` — deterministic retrieval, callers/callees, impact, and snapshot
  identity baseline over the corpus; reusable by `plans/020`.

## Ground truth vs specification

- Fields marked `ground_truth: true` were captured from the current extractor
  (`semidx.runtime.languages.{java,typescript}/parse-file`) and from the semidx
  MCP retrieval/impact surfaces. They must stay stable or change only via an
  approved, recorded semantic improvement.
- SCIP and LSP provider spellings are **representative**, not verified tool
  output. Stage 3 (SCIP) and Stage 5 (LSP) must re-verify them against real
  provider payloads.
- `signature_key` canonical values in the identity fixtures are **decision
  placeholders**. The current extractor cannot produce a provider-neutral
  signature key (see `reports/024`, finding F1); an owner decision on the
  canonical signature form is an execution-admission prerequisite for Stage 1.
