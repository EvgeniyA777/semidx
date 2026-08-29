# Real SCIP reference artifacts (plans/018 Stage 3)

`typescript-corpus.observed.json` is the decoded output of running
`@sourcegraph/scip-typescript` over
`fixtures/provider-authority/corpus/typescript/`. It replaces the
*representative* SCIP spellings that the Stage 0 identity fixtures were seeded
with (see `../identity/`), which the plan required Stage 3 to re-verify against
real tool output.

## Regenerating

```sh
./scripts/setup-scip-typescript.sh          # repo-managed, pinned CLI
./scripts/scip-typescript-corpus-snapshot.sh # writes typescript-corpus.observed.json
```

The decoder (`scripts/lib/decode-scip.js`) uses scip-typescript's own bundled
protobuf module, so the preflight needs no separate protobuf toolchain. The
Stage 3 provider adapter reads SCIP in the JVM and does not depend on these
scripts.

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
