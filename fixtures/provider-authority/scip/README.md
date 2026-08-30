# Real SCIP reference artifacts (plans/018 Stage 3)

Two committed artifacts, both produced by the pinned `@sourcegraph/scip-typescript`
over `fixtures/provider-authority/corpus/typescript/`:

- `typescript-corpus.observed.json` — the decoded index as reviewable JSON. It
  replaces the *representative* SCIP spellings the Stage 0 identity fixtures were
  seeded with (see `../identity/`), which the plan required Stage 3 to re-verify
  against real tool output.
- `typescript-corpus.scrubbed.scip` — the raw protobuf index, with
  `metadata.project_root` cleared. This is the binary fixture the JVM SCIP
  reader tests (`semidx.runtime.scip-test`) read. `project_root` is an absolute
  `file://` path on the indexing machine, so it must not be committed verbatim;
  everything else (documents, symbols, occurrences) is byte-preserved.

## Regenerating

```sh
./scripts/setup-scip-typescript.sh           # npm ci from scripts/scip-toolchain/package-lock.json
./scripts/scip-typescript-corpus-snapshot.sh # writes both typescript-corpus.observed.json and .scrubbed.scip
```

The pin is the committed lockfile `scripts/scip-toolchain/package-lock.json`, so
both `scip-typescript` (0.4.0) and its transitive `typescript` (5.9.3) are fixed
on a clean checkout. Both scripts fail closed on version drift.

The decoder (`scripts/lib/decode-scip.js`) and the scrubber
(`scripts/lib/scrub-scip.js`) use scip-typescript's own bundled protobuf module,
so regenerating these artifacts needs no separate protobuf toolchain. The JVM
SCIP reader (`semidx.runtime.scip`) instead parses `.scip` with Java stubs
generated from `proto/scip/scip.proto` by the repo-managed protoc toolchain
(ADR-042); it does not depend on these scripts or on the bundled JS module.

## What real scip-typescript@0.4.0 does with the corpus

- **Symbol grammar**: `scip-typescript npm <name> <version> <descriptor>` where
  a local project has `.` `.` for name/version and file components are wrapped
  in backticks, e.g. `scip-typescript npm . . src/\`orders.ts\`/normalize().`.
  Params get their own symbol (`normalize().(value)`), constructors are
  `OrderService#\`<constructor>\`().`, fields are `OrderService#validator.`.
- **`src/index.ts` re-export surface**: the only symbol emitted for `index.ts`
  is the module itself. `export { normalize as canonicalize } from './orders'`
  produces **no** `canonicalize` symbol and **no** SCIP `Relationship`. Both the
  `normalize` and the `canonicalize` tokens are non-definition occurrences that
  resolve to the origin symbol `src/\`orders.ts\`/normalize().`. The re-export
  edge is recoverable only from occurrence resolution on the export statement.
- **External symbols**: `index.external_symbols` is empty; stdlib references
  appear inline as occurrences
  (`scip-typescript npm typescript 5.9.3 lib/\`lib.es5.d.ts\`/String#trim().`).

Field-level captures are host-stripped: `metadata.project_root` (an absolute
`file://` URI) is dropped by the decoder so the artifact is machine-independent.
