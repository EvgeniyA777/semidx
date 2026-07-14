---
title: "State Invariant Context For Retrieval"
doc_type: "idea"
lifecycle: "concept"
status: "draft"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-07-14"
---

# Idea: State Invariant Context For Retrieval

Source: observed retrieval gap while using semidx on the
`JobApplicationTracker` Google Sheets OAuth Stage 7 implementation.

Status: concept

## Summary

Improve semidx so stateful code changes produce an explicit "state invariant
packet": the entity/model fields involved, writer methods, lifecycle/status
transitions, timestamp/secret handling, persistence/schema context, test
assertions, and fixture helpers that define the invariants.

The goal is not just to retrieve the likely service/controller files. For
changes that affect persistent state, credentials, timestamps, status enums, or
disconnect/reconnect flows, semidx should help the agent understand which
invariants must be preserved before editing.

## Observed Finding

During Stage 7 in `JobApplicationTracker`, the task was to add Google Sheets
disconnect and reconnect-required handling. semidx correctly identified the main
blast radius around:

- `GoogleSheetsController`
- `GoogleSheetsConnectionService`
- `GoogleApiSheetsClient`
- the Sheets settings template
- related controller/service tests

However, the agent still had to manually read the tail of
`GoogleSheetsConnectionServiceTest` and the `GoogleSheetsConnection` entity to
avoid breaking invariants around `connectedAt` and `lastValidatedAt`.

The important details were not only in the selected service methods. They were
also encoded in:

- JPA entity fields and nullability/defaults;
- service test assertions about timestamp preservation and clearing;
- fixture helpers near the end of the test file, such as connected-row builders;
- previous decisions that generic `updateStatus(DISCONNECTED)` must preserve
  secrets until the explicit revoke-then-clear disconnect flow exists.

The retrieval result was useful, but it did not make the state invariants first
class. The agent had to infer that extra whole-file reads were necessary.

## Why This Matters

For stateful application code, a syntactically small change can violate an
important product or security invariant:

- clearing a token before remote revocation succeeds;
- erasing a spreadsheet target that should survive reconnect;
- resetting a first-connect timestamp that should be preserved;
- preserving a timestamp that should be cleared after disconnect;
- mapping an auth failure to a generic error instead of a reconnect state;
- leaking a raw provider error into UI or persisted status text.

These are not always visible from caller/callee relationships alone. They are
often distributed across entity definitions, status enums, persistence methods,
tests, fixtures, migrations, and progress-plan decisions.

## Proposed Improvement

Add a state-invariant retrieval mode or enrich existing `resolve_context`,
`impact_analysis`, and `expand_context` outputs when the task intent includes
terms such as:

- `disconnect`
- `reconnect`
- `status`
- `state`
- `lifecycle`
- `credential`
- `secret`
- `token`
- `timestamp`
- `connectedAt`
- `lastValidatedAt`
- `persist`
- `entity`

The result should include a compact packet with these sections.

## State Invariant Packet

### Entity / Model Fields

List fields likely affected by the change, including defaults, nullability,
annotations, enum types, and persistence column names where available.

Example:

- `GoogleSheetsConnection.authMode` nullable enum
- `GoogleSheetsConnection.status` non-null enum
- `oauthRefreshTokenEncrypted` encrypted ciphertext
- `spreadsheetId` target that may be preserved across credential changes
- `connectedAt` first-connect timestamp
- `lastValidatedAt` validation timestamp
- `lastErrorMessage` sanitized user-facing error

### Writers And Transitions

List methods that write the fields and summarize their transition intent.

Example:

- `saveOAuthConnection(...)` switches to OAuth, stores encrypted refresh token,
  clears service-account material, preserves target, preserves first-connect
  timestamp on reconnect.
- `saveServiceAccountConnection(...)` switches to service account, stores
  encrypted JSON, clears OAuth material, preserves target.
- `updateStatus(...)` preserves secrets and identity while stamping validation
  or failure status.
- `disconnectPreservingTarget()` should clear credentials/identity while keeping
  target fields.

### Assertion Tests

Pull tests that assert the affected fields, even when they live far from the
selected method span or in helper-heavy test tails.

Example:

- tests asserting `connectedAt` preservation;
- tests asserting `lastValidatedAt` stamping or clearing;
- tests asserting secret preservation in generic status updates;
- tests asserting secret clearing in explicit disconnect;
- tests asserting target preservation across credential changes.

### Fixture Helpers

Include helper methods that construct relevant state, even when they are not
directly selected by semantic ranking.

Example:

- `connectedOAuthRow()`
- `connectedServiceAccountSummary()`
- helper builders for status-specific summary records

### Schema / Migration Hints

When a persistent entity is involved, include schema or migration files that
define constraints and column behavior.

Example:

- single-row connection table constraint;
- nullable `auth_mode` for disconnected rows;
- status enum values;
- encrypted secret columns.

### Guardrail Recommendation

If semidx cannot confidently collect the packet, explicitly tell the agent:

> State invariants may be encoded outside the selected spans. Read the full
> entity file, primary service test, and relevant fixture helpers before editing.

This turns the current implicit best practice into an agent-facing retrieval
guardrail.

## Implementation Direction

### Java Lane

For Java projects, the indexer can extract useful state-invariant facts from:

- JPA annotations such as `@Entity`, `@Column`, `@Enumerated`, `@Id`;
- JavaBean setter/getter use around entity fields;
- enum fields used as status/lifecycle state;
- service methods that call multiple setters on the same entity;
- tests that call getters in assertions;
- fixture/helper methods returning entity or summary objects;
- Flyway/Liquibase migration files that mention the entity table or columns.

The first version can be heuristic. It does not need full dataflow precision to
be useful.

### Retrieval Ranking

Boost candidates when:

- an intent term suggests lifecycle/state work;
- a selected method writes entity fields;
- tests assert the same fields written by selected methods;
- helper methods construct objects of the affected entity/DTO type;
- migrations mention table/column names derived from the entity.

### Output Contract

This could be exposed as:

- an optional `state_invariants` section in `impact_analysis`;
- an optional `state_invariant_packet` in `expand_context`;
- a dedicated tool later, such as `state_invariant_context`.

The dedicated tool is probably premature. Enriching `impact_analysis` and
`expand_context` first would fit the existing staged retrieval model.

## Expected Agent Benefit

This improvement would help agents:

- avoid under-reading stateful services;
- preserve security-sensitive ordering such as revoke-before-clear;
- discover timestamp and target-preservation invariants before editing;
- pull fixture helpers that are otherwise easy to miss;
- explain why whole-file reads are required when semantic spans are not enough;
- reduce regressions that pass compile checks but violate lifecycle behavior.

## Acceptance Criteria For A Future Plan

- Given a Java task involving disconnect/reconnect/status/credential language,
  semidx surfaces the relevant entity/model file even when the initial selection
  focuses on service methods.
- `impact_analysis` or `expand_context` names fields whose setter calls appear
  in selected methods.
- Tests asserting those fields are included in related tests or risky neighbors.
- Fixture helpers returning the affected entity/summary type are included or
  explicitly recommended for whole-file reading.
- The result contains a guardrail when confidence is low instead of silently
  implying the selected spans are enough.

## Non-Goals

- Do not replace tests or human review.
- Do not attempt perfect interprocedural dataflow in the first iteration.
- Do not dump entire files by default; keep staged retrieval compact and make
  whole-file reads an explicit recommendation when needed.

