# Jev Protocol Fixtures

Committed by [Plan 015](../../docs/plans/015_optional_jev_ranking_projection.md)
Stage 0. These fixtures pin the request and response JSON shape the `Noul`
adapter (Stage 3, `src/mcp/jev.zig`) must produce and accept, so the offline
test lane never depends on network access or a live TypeSafe account.

The request shape and the valid-response shape were re-verified against the
official [API reference](https://docs.typesafe.ai/api) on 2026-09-26 (see the
[progress log](../../docs/reports/015_optional_jev_ranking_projection_progress.md)).
The malformed-response fixtures are not official TypeSafe examples — TypeSafe
does not publish a schema for these failure shapes — they encode the local
acceptance rules ADR 013 D4 requires the adapter to enforce itself:

- every expected question id present exactly once;
- no unexpected question id;
- every answer has `"type": "noul"` and a finite `noul` value in `[0, 1]`;
- the response `model` equals the requested `model` exactly.

## Files

| File | Purpose |
| --- | --- |
| `request_two_candidates.json` | A valid two-candidate ranking request: one `state` plus one `noul` question per candidate ordinal. |
| `response_valid.json` | A valid response answering both questions, usable to prove ordering and provenance recording. |
| `response_missing_answer.json` | Omits `candidate_1`; must be rejected, not defaulted. |
| `response_duplicate_or_unknown_answer.json` | Includes an answer for a question id that was never asked; must be rejected. |
| `response_wrong_type.json` | Answers `candidate_1` with `"type": "score"` instead of `"noul"`; must be rejected. |
| `response_out_of_range.json` | `candidate_1`'s `noul` is `1.4`, outside `[0, 1]`; must be rejected. |
| `response_non_finite.json` | `candidate_1`'s `noul` is not a finite number; must be rejected. |
| `response_model_mismatch.json` | Response `model` differs from the requested `model`; must be rejected even though every answer is otherwise valid. |

None of these fixtures contains a real API key, source evidence text, or a
byte range. `state` values are synthetic.
