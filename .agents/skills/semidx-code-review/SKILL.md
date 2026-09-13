---
name: semidx-code-review
description: "Review semidx diffs with findings-first, evidence-backed analysis across semantic identity, provenance and resolution, incremental maintenance, public contracts, language frontend coverage, storage/runtime edges, and tests."
---

# semidx Code Review

Lead with findings ordered by severity. Do not begin with an implementation
summary when defects exist.

## Evidence Standard

Each finding includes severity, practical impact, exact file/line evidence, and
the smallest reasonable fix. Classify uncertain items as:

- `Confirmed finding` - reproduced or proven by an unambiguous code path;
- `Hypothesis needing verification` - runtime/tool behavior needs proof;
- `Open question` - the plan, ADR, contract, or architecture source is
  insufficient;
- `Rejected / false positive` - evidence disproved the concern;
- `Fixed` - correction and verification are present.

Do not upgrade frontend, parser, database, transport, or toolchain speculation
into a confirmed defect without code evidence, committed contract evidence, or a
focused repro.

## Review Workflow

1. Read the applicable plan, ADRs, `MEMORY.md`, progress log, policy documents,
   contracts, fixtures, and final diff.
2. Use `semidx-code-exploration` to inspect changed symbols, callers,
   dependents, and related tests before broad manual search.
3. Check semantic identity: correspondence that survives edits, identity loss
   that is observable as identity loss, must-merge and must-not-merge fixtures,
   and deterministic ordering where order is part of the contract.
4. Check knowledge categories: every assertion carries what produced it and how
   far it was resolved; facts, unresolved assertions, approximate evidence, and
   confirmed absence stay distinguishable on every public surface.
5. Check incremental maintenance: affected-region reanalysis, invalidation, and
   results that correspond to one consistent published graph state.
6. Check language frontends against the contracts `SPEC.md` and `CORE.md` own:
   declared coverage, honest reporting of unavailable analysis, and
   language-specific meaning kept in extensions instead of flattened into core
   approximations.
7. Check public surfaces and runtime edges when touched: schema and example
   agreement, error shapes, parity across whichever surfaces exist, storage
   paths, startup, cleanup, and error reporting.
8. Check whether tests prove behavior at the lowest sufficient level and whether
   higher-level checks add distinct evidence.

## Response Shape

1. Findings, highest severity first.
2. Open questions or assumptions that affect correctness.
3. Verification commands and results.
4. Residual risk or missing tests.

If no finding remains, say so plainly and still state verification limits.
