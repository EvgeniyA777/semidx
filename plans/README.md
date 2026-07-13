# Plans

This directory holds execution-oriented plans in a single flat chronological sequence.

Plan filenames use `NNN_slug.md`, where `NNN` is unique within this directory and increases over time. Do not create plan subdirectories for lifecycle or intent. Use frontmatter instead:

- `doc_type` distinguishes architecture plans from implementation plans.
- `lifecycle` distinguishes active, completed, superseded, and archived plans.
- `agent_action` tells agents whether a plan is current context or historical reference.

Use `plans/` when the document is primarily about sequencing work.

Do not put these here:

- durable API or product reference docs
- architecture decisions of record
- dated research notes or reviews

Those belong in `docs/`, `adr/`, or `notes/` respectively.
