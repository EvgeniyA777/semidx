# Source-State Identity Vectors — Frozen Inputs

Frozen by [Plan 016](../../docs/plans/016_trustworthy_working_copy_sync.md)
Stage 0, for [ADR 014](../../docs/adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md)
D2 and Plan 016's "Source-State Identity Encoding" contract, ahead of Stage 1
implementing `semidx-source-state-v1`; this file fixes the *inputs* first, so
the encoding is built to match a frozen case rather than a case invented next
to convenient code.

**Stage 1 update:** implemented in `src/source/identity.zig`. The seven cases
below are proven as unit tests there, built directly against small in-memory
`ScannedUnit`/`ScanDiagnostic` values with the same shape as this file
describes, rather than against `units/unit_01.zig`..`unit_09.zig` file by
file — the nine-unit fixture stays the shared input for the Stage 3 gate
regression test and is not duplicated here. The two-independent-processes
property (case matters most for) is proven separately by scanning the same
temporary tree twice and comparing identities. Committed hashes are not
pinned in this document: the identity is proven by equality/inequality
between computed values in the test file, per the plan's Stage 1 "Done when"
(fixed vectors pass; two independently built equivalent scans match), not by
a third-party reference hash.

Every case names: the discovery budgets and exclusion policy in force, the
scanned units (path, language, content), and the scan diagnostics (kind, path,
message), in the order Stage 1's `SourceScan` will hold them before
normalization. "Default policy" means the discovery budgets and excluded
directories `src/source/discovery.zig` already applies with no fixture-local
override.

## 1. Empty

- Policy: default.
- Units: none.
- Diagnostics: none.

## 2. One Unit

- Policy: default.
- Units: `units/unit_01.zig` (Zig, content = the file's current bytes).
- Diagnostics: none.

## 3. Reordered Input

Same visible source state as the nine-unit set below, discovered in two
different host directory-iteration orders (for example, forward and reverse
`readdir` order simulated by feeding the scanner the same unit set built in
each order). The identity must be identical in both orders — this is the
input-order independence Stage 1 proves, not a second distinct source state.

- Policy: default.
- Units: `units/unit_01.zig` .. `units/unit_09.zig`, presented to the hasher
  in two different pre-sort orders.
- Diagnostics: none.

## 4. Byte Change

The nine-unit set with `units/unit_03.zig`'s bytes replaced by
`units/unit_03_edited.zig`'s bytes at the same path. Must differ from the
unedited nine-unit identity.

- Policy: default.
- Units: `units/unit_01.zig`, `units/unit_02.zig`,
  `units/unit_03_edited.zig` (presented at path `unit_03.zig`),
  `units/unit_04.zig` .. `units/unit_09.zig`.
- Diagnostics: none.

## 5. Path Change

The nine-unit set with `units/unit_03.zig`'s unedited content presented under
path `renamed_unit_03.zig` instead of `unit_03.zig`. Must differ from the
unedited nine-unit identity even though every unit's language and content
digest is otherwise identical.

- Policy: default.
- Units: `units/unit_01.zig`, `units/unit_02.zig`,
  `units/unit_03.zig`'s content at path `renamed_unit_03.zig`,
  `units/unit_04.zig` .. `units/unit_09.zig`.
- Diagnostics: none.

## 6. Diagnostic Change

The nine-unit set with one added scan diagnostic that carries no unit content
change. Must differ from the unedited nine-unit identity.

- Policy: default.
- Units: `units/unit_01.zig` .. `units/unit_09.zig`, unchanged.
- Diagnostics: one, `kind: unsupported_construct`,
  `path: unit_03.zig`, `message: "synthetic fixture diagnostic for Stage 1
  vector 6"`. This exact diagnostic is fabricated for the vector; it does not
  need to be one `unit_03.zig`'s real content produces, because this vector
  proves diagnostic inclusion, not diagnostic accuracy.

## 7. Policy Change

The nine-unit set scanned under a different, still-valid discovery policy
(Stage 1 must pick one concrete difference when it implements this vector —
for example an additional excluded directory name that matches nothing under
this fixture, so the visible unit set stays identical while the recorded
policy differs). Must differ from the unedited nine-unit identity because the
policy is hashed, even though no unit or diagnostic changed.

- Policy: default plus one additional excluded-directory entry not present
  under `units/` (Stage 1 names the exact entry when it implements this
  vector).
- Units: `units/unit_01.zig` .. `units/unit_09.zig`, unchanged.
- Diagnostics: none.
