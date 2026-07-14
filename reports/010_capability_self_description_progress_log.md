---
title: "Capability Self-Description Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-07-13"
---

# Capability Self-Description Progress Log

## Stage 1 — Single Source of Truth for Language Strength

- **Status:** Done
- **Summary:** Added `:strength` to each language lane in `language_registry.clj`. Created `language-strength-profile` and `strength-for-language` accessors in the registry. Removed the duplicate `language-strength-profile` map from `retrieval_policy.clj` and updated it to consume the registry's map.
- **Review Findings:**
  - *Missing MEMORY.md single-source-of-truth update (Medium):* Accepted. Added a bullet point under "Hard Invariants" in `MEMORY.md`.
  - *retrieval_policy.clj bypasses the new registry accessor (Low):* Accepted. Moved normalization into the accessor and updated `retrieval_policy.clj` to call it.
- **Verification:** 
  - `clojure -M:test` passed (0 failures, 0 errors).
  - Benchmarks and semantic quality reports matched the baseline perfectly. `run-mvp-gates.sh` ran successfully.
- **Changed Files:**
  - `src/semidx/runtime/language_registry.clj`
  - `src/semidx/runtime/retrieval_policy.clj`
  - `MEMORY.md`

## Stage 2 — Versioned Capability Contract + Projection

- **Status:** Done
- **Summary:** Authored `capabilities.schema.json`, added `malli` mirror, defined example payload, and created `semidx.runtime.capabilities` to project the registry into the contract shape.
- **Review Findings:**
  - *language_policy exposed as a string array instead of a strict enum (High):* Accepted. Added `languagePolicyOption` enum to `common.schema.json` and updated `capabilities.schema.json` and `schemas.clj` to validate against it.
- **Verification:**
  - `./scripts/validate-contracts.sh` passed.
  - `clojure -M:test` passed.
- **Changed Files:**
  - `contracts/schemas/capabilities.schema.json`
  - `contracts/schemas/common.schema.json`
  - `src/semidx/contracts/schemas.clj`
  - `src/semidx/runtime/capabilities.clj`
  - `contracts/examples/capabilities.json`
  - `test/semidx/runtime/capabilities_test.clj`
  - `src/semidx/contracts/validator.clj`
  - `contracts/examples/catalog.json`
  - `MEMORY.md`

## Stage 3 — MCP Self-Description

- **Status:** Done
- **Summary:** Wired `capabilities-payload` into MCP `initialize` response. Restricted `language_policy` in `create_index` tool to use `registry/supported-language-order`. Updated roadmap status.
- **Verification:**
  - `clojure -M:test` passed.
- **Changed Files:**
  - `src/semidx/mcp/core.clj`
  - `docs/roadmap-status.md`

## Stage 4 — Cross-Surface Parity

- **Status:** Done
- **Summary:** Added `capabilities_json` to gRPC `HealthResponse` protobuf definition. Updated HTTP and gRPC `handle-health` endpoints to emit capabilities payload. Refined `MEMORY.md`.
- **Verification:**
  - `clojure -M:test` passed.
- **Changed Files:**
  - `proto/semidx/runtime/grpc/v1/runtime.proto`
  - `src/semidx/runtime/grpc_proto.clj`
  - `src/semidx/runtime/http.clj`
  - `src/semidx/runtime/grpc.clj`
  - `MEMORY.md`

## Stage 5 — Docs & Finalization

- **Status:** Done
- **Summary:** Wrote ADR-025 documenting the capabilities self-description contract. Marked all stages complete.
- **Verification:** N/A (Documentation only)
- **Changed Files:**
  - `adr/025-expose-versioned-capability-self-description-contract.md`
