# Repository Agent Notes

- Never run dependent git commands in parallel.
- `git commit` and `git push` must always run sequentially.
- Use parallel tool execution only for independent reads or checks, never for state-changing commands that depend on each other.
- If uncommitted files remain in the repo from previous agent runs, explicitly surface them and offer to commit and push them separately; only do that after user approval.
- For `.clj`, `.cljc`, `.cljs`, and `.edn` structural edits, prefer form-aware Clojure editing tools when available; avoid large raw `apply_patch` rewrites of deeply nested forms when a narrower edit will work.
- After any manual `apply_patch` that changes Clojure forms, run an immediate syntax or compile probe before continuing with more edits.
- If Clojure reports `Unmatched delimiter`, `EOF while reading`, or `defn` spec errors after an edit, inspect the just-edited form tail first and repair delimiters before making additional changes.
- Keep Clojure patches scoped to one top-level form where possible; session history shows multi-form raw patches are the recurring source of delimiter regressions.
