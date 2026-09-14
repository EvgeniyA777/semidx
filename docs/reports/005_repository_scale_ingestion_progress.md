---
title: "Repository-scale ingestion progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 005: Repository-Scale Ingestion Progress

Companion log for
[docs/plans/002_repository_scale_ingestion.md](../plans/002_repository_scale_ingestion.md).

## Current Status

Planning is complete and the Plan Readiness Gate has been applied. Implementation
has not started.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created the staged plan and this log. Gate applied; findings below. |
| Stage 1: Source discovery | Not started | Awaiting implementation. |
| Stage 2: Unit identity independent of path | Not started | Awaiting Stage 1. |
| Stage 3: Scan reconciliation | Not started | Awaiting Stage 2. |
| Stage 4: Affected-region proof at scale | Not started | Awaiting Stage 3. |
| Stage 5: Cross-unit dependency tracking | Not started | Awaiting Stage 3. Opens with an ADR. |
| Stage 6: Closure and documentation | Not started | Awaiting Stage 5. |

## Plan Readiness Gate

Applied against
[documentation.md](../agent-policy/documentation.md#plan-readiness-gate) before
any implementation.

### Hard Fail Conditions

| Condition | Result |
| --- | --- |
| Product or runtime behavior unclear, or conflicting with sources of truth | Pass. The plan was written after reports 003 and 004, so it uses the accepted roster including the `CONTAINS`/`DEFINES` split, and changes no accepted meaning. |
| Scope boundaries missing, vague, or allowing unrelated refactoring | Pass. Non-Scope names persistence, public surfaces, ignore-file parsing, language import semantics, snapshot redesign, and performance work explicitly. |
| A key technical decision implicit, unjustified, or externally gated without a stop rule | Pass after correction; see finding 1. |
| Branches mentioned but not carried through stages, files, verification, and DoD | Pass after correction; see finding 1. |
| Stages depending on later stages, or lacking concrete outputs | Pass. Each stage names files or artifacts. Stage 5 depends on Stage 3, not on Stage 4, and the gate records that ordering. |
| DoD not verifiable through files, commands, tests, or artifacts | Pass. Every DoD item is a test, a command, or a document state. |
| Test strategy missing main risks | Pass. The risk matrix covers discovery correctness, core/environment separation, rename identity, identity-loss visibility, affected-region measurement, quadratic behavior, invalidation, approximate-versus-fact, freshness at scale, privacy, and documentation truthfulness. |
| Runtime constraints ignored | Pass. Budgets, symlink handling, temporary-tree isolation, and the no-network constraint are named. |
| Documentation targets contradicting each other or carrying stale bookkeeping | Pass after correction; see finding 2. |
| Requires guessing what to implement, skip, test, or when to stop | Pass. Four stop conditions are stated with resume behavior. |

### Findings Raised And Fixed Before Execution

1. **Stage 5 was an unresolved branch.** The first draft left "record cross-unit
   name matches as approximate assertions" as a good idea without saying what
   happens if it turns out to conflict with
   [§1](../../ARCHITECTURE_CONSTITUTION.md#1-semantic-graph-is-the-product).
   That is two hard-fail conditions at once: an externally gated decision with no
   stop rule, and a branch not carried through DoD. Fixed by opening the stage
   with an ADR and giving both outcomes a complete DoD, so the plan completes
   either way.

2. **The plan had to be rewritten against a roster that changed while it was
   being written.** Reports 003 and 004 admitted `repository`, `file`,
   `definition`, `CONTAINS`, `DEFINES`, `REFERENCES`, and `CALLS`, and split
   containment from definition introduction. An earlier draft still described
   `repository DEFINES file`. Corrected throughout.

### Ready Criteria

| Criterion | Result |
| --- | --- |
| Contract changes explicit and tied to sources of truth | Pass. The one model change — identity scope becoming unit identity rather than a path — is stated as a plan-level decision and tied to §4. |
| Scope and non-scope explicit | Pass. |
| Key decisions and rationale recorded | Pass. Seven plan-level decisions, each with its reason. |
| Blockers and branches have precise stop and resume behavior | Pass. |
| Each stage has purpose, ordered dependencies, and concrete outputs | Pass. |
| Verification commands and acceptance checks named | Pass. The lanes are the ones [testing.md](../agent-policy/testing.md#verification-lanes) already records. |
| DoD observable and falsifiable | Pass. The load-bearing one is a frontend invocation count, which fails if a rescan does more work than it should. |
| Risk-based tests mapped to behavior | Pass. |
| Runtime and environment traps considered | Pass. |
| Internally consistent, not overloaded with irrelevant detail | Pass. |

**Gate result: ready for execution.**

## Open Questions Carried Into Execution

These are decided inside the plan but are the ones most likely to need revisiting
once code exists:

- Whether exact-content-only rename correspondence is too narrow to be useful in
  practice. The plan chooses it deliberately over a similarity heuristic; if real
  use shows it almost never fires, the answer is a stronger *evidence* rule, not
  a guess presented as a fact.
- Whether unit identity should survive a root change, not only a path change. The
  plan scopes identity to one root; multi-root indexing is not in scope and would
  be a `SPEC.md` source-identity question.
- What `publish` costs once a repository-scale tree exists. Stage 4 measures it
  and records it as risk; the plan explicitly does not act on the number.

## Blockers

None for plan creation.

Potential Stage 1 blockers:

- `std.Io.Dir` directory walking in Zig 0.16 may not expose what the walk needs
  without more plumbing than expected; the filesystem API moved in this release.
- Symlink semantics differ enough across platforms that the confinement test may
  need to be platform-scoped.

## Residual Risk

The plan's largest assumption is that unit identity can be made path-independent
without touching an accepted core definition. `file` is accepted with "Location
is a property, not an identity derived from byte or line position", which reads
as supporting the change rather than blocking it — but if implementation shows
otherwise, the plan's third stop condition applies and the work pauses for a
requirements change rather than proceeding.

## Next Handoff

Start with Stage 1. Read the plan, reports 001 to 004, and the current
`MEMORY.md`, then check the working tree before creating `src/source/`.
