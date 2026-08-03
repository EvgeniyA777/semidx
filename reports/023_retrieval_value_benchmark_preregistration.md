---
title: "Retrieval Value Benchmark Pre-registration (Stage 0)"
doc_type: "report"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-08-03"
---

# Retrieval Value Benchmark Pre-registration (Stage 0)

This document satisfies the pre-registration sub-gate of Stage 0 for `plans/020_retrieval_value_benchmark_harness_plan.md`. It formally freezes the benchmark experimental design and schemas before the calibration pilot begins. The final threshold lock will occur after the pilot.

## 1. Arm Definitions

| Arm | Name | Versioned Policy / Tooling | Verdict Role |
| --- | --- | --- | --- |
| **A** | semidx staged | Canonical staged semidx flow (`v1`). One-shot adapters (`plans/019`) may be registered as `A2` in future runs. | Candidate |
| **B** | Competent lexical | `rg` (ripgrep) queries plus bounded targeted file reading. No semantic tools. | Primary comparator |
| **C** | Language navigation | Arm B tools plus LSP/SCIP definition/reference navigation where available. | Diagnostic control |
| **D** | Native no-index | The agent's native repository-browsing policy (e.g., full shell/filesystem access). *Forbidden:* `semidx` CLI, any LSP/SCIP tool call (`lsp_*`, `scip_*`), or any other external semantic-navigation service invocation. Audited via tool-call log scan: attempt is voided if any forbidden tool appears. | Ecological control |

*Rule:* Arm B is the primary comparator. C and D cannot be silently folded into B or used to rescue a primary verdict. For Arm C, if LSP/SCIP is unavailable on the target repo, the attempt outcome must be recorded as `not_applicable` and a `not_applicable_reason` string is required.

## 2. Experimental Controls and Cache Protocol

These policy IDs represent the immutable definitions for the `v1` benchmark suite.

- **Task Prompt Policy (`task_prompt_policy_id: agent_default_v1`)**:
  ```text
  You are an autonomous AI agent assigned to resolve an issue in this repository.
  Use your available tools to explore the codebase, analyze the problem, and implement a solution.
  ```

- **Arm Policy Bundle (`arm_policy_bundle_id: harness_v1`)**:
  - Arm A tools: `resolve_context`, `expand_context`, `fetch_context_detail`.
  - Arm B tools: `grep_search`, `list_dir`, `view_file`.
  - Arm C tools: Arm B tools + `lsp_definition`, `lsp_references`.
  - Arm D tools: Native unconstrained shell environment. *Audit Rule:* Execution fails if `semidx` CLI or `lsp_*` tools are invoked.

- **Execution Budget (`execution_budget_policy_id: budget_v1`)**:
  - Max wall-clock time per task attempt: 300 seconds.
  - Max tool calls per task attempt: 30.
- **Cache Protocol (`cache_protocol_id: cold_start_v1`)**: Every task attempt begins with a completely cold context cache (no leaked tokens from previous attempts).

## 3. Schemas (Run and Attempt Identity)

```text
BenchmarkRun {
  benchmark_run_id: string
  suite_version: string
  started_at: timestamp
  repo_key: string
  repo_revision: string
  dirty_state: boolean
  task_prompt_policy_id: string
  arm_policy_bundle_id: string
  execution_budget_policy_id: string
  cache_protocol_id: string
  price_schedule_id: string
  harness_version: string
}

TaskAttempt {
  benchmark_run_id: string
  task_id: string
  task_attempt_id: string
  arm: string ("A" | "B" | "C" | "D")
  arm_policy_id: string
  sequence_index: int
  seed: int
  agent_id: string
  agent_build_id: string
  provider: string
  api_surface: string
  model: string
  model_revision: string
  service_tier: string
  outcome: string ("success" | "failure" | "error" | "not_applicable")
  not_applicable_reason: string | null  ; required when outcome = "not_applicable"; null otherwise
}
```

Aggregation keys on `task_attempt_id` first, then rolls up to `(benchmark_run_id, task_id, arm)`.

## 4. Usage Adapters and Price Schedule

**Price Schedule ID:** `2026-08-03-anthropic-openai-gemini-v1`
**Currency:** USD
**Token Unit:** Per 1,000,000 tokens (1M tokens)
**Capture Time:** 2026-08-03T01:02:00Z

### 4.1. Price Table (Locked as of 2026-08-03)

*(Model revision must exactly match this table; otherwise `pricing_status: unresolved` applies.
For Google: Cache Read is billed separately from Cache Storage; both must be recorded.)*

| Provider | API Surface | Model Revision | Service Tier | Context Tier | Input (Uncached) | Input (Cache Read) | Cache Write / Storage | Output (Visible+Reasoning) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Anthropic | `messages` | `claude-3-5-sonnet-20240620` | `on-demand` | `default` | $3.00 / 1M | $0.30 / 1M | $3.75 (5m TTL) / $6.00 (1h TTL) per 1M | $15.00 / 1M |
| OpenAI | `chat` | `gpt-4o-2024-05-13` | `on-demand` | `default` | $5.00 / 1M | $2.50 / 1M | N/A — OpenAI caches automatically; no explicit write charge | $15.00 / 1M |
| OpenAI | `responses` | `gpt-4o-2024-05-13` | `on-demand` | `default` | $5.00 / 1M | $2.50 / 1M | N/A — same as `chat` | $15.00 / 1M |
| Google | `generate-content` | `gemini-2.5-pro` | `on-demand` | `<= 200k` | $1.25 / 1M | $0.125 / 1M | $4.50 / 1M·hr (storage) | $10.00 / 1M (thinking included) |
| Google | `generate-content` | `gemini-2.5-pro` | `on-demand` | `> 200k` | $2.50 / 1M | $0.25 / 1M | $4.50 / 1M·hr (storage) | $15.00 / 1M (thinking included) |
| Google | `generate-content` | `gemini-2.5-flash` | `on-demand` | `any` | $0.30 / 1M | $0.03 / 1M (text/image/video) | $1.00 / 1M·hr (storage) | $2.50 / 1M (thinking included) |

*(Official Source Links: [Anthropic](https://docs.anthropic.com/en/docs/about-claude/pricing), [OpenAI](https://openai.com/api/pricing/), [Google](https://ai.google.dev/gemini-api/docs/pricing) — fetched 2026-08-03)*

**Gemini cache billing rule:** An attempt using Gemini explicit caching must record both `cache_read_tokens` (billed at Cache Read rate) and `cache_storage_token_hours` (billed at Storage rate per 1M·hr). Both are required to compute `cost_usd` correctly. An attempt that cannot separate these emits `pricing_status: unresolved`.

### 4.2. Usage Adapter Mapping (`adapter_version: v1`)

| Adapter / Provider | Uncached | Cache Read | Cache Write (5m/1h) | Visible Output | Reasoning | Unclassified |
| --- | --- | --- | --- | --- | --- | --- |
| `anthropic-messages` | `input_tokens` | `cache_read_input_tokens` | `cache_creation_input_tokens` | Provider split | Provider split | `output_tokens` (if no split) |
| `openai-chat` | `prompt_tokens` - cached | `prompt_tokens_details.cached_tokens` | `0` (implied) | `completion_tokens` - reasoning | `completion_tokens_details.reasoning_tokens` | `0` |
| `openai-responses` | `input_tokens` - cached | `input_tokens_details.cached_tokens` | `0` | `output_tokens` - reasoning | `output_tokens_details.reasoning_tokens` | `0` |
| `gemini-generate-content`| `promptTokenCount` - cached | `cachedContentTokenCount` | `0` | `candidatesTokenCount` | `thoughtsTokenCount` | `0` |

*Rule:* If the raw response cannot distinguish a billing-relevant class, the adapter emits `pricing_status: unresolved` and the attempt is excluded from the cost verdict until resolved.

## 5. Pilot and Final Lock Rule

Before the actual scoring run, a **Calibration Pilot** will be conducted:
- **Scope:** 5–10 tasks.
- **Measurements:** Cost of the competent baseline (Arm B) and the success-metric noise floor.
- **Action:** No verdict is produced here. The pilot exists solely to calibrate the "noise" and "baseline cost".

**Final Lock Rule:**
Immediately after the pilot and *before* scoring, the final threshold must be locked. It will be defined as:
> *Arm A is cheaper than Arm B by more than the measured noise floor at parity success.*
(Provisionally: ≥50% lower cost, success within 5 percentage points, wall-clock ≤ 1.5×).
