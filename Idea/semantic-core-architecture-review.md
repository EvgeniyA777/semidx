# Architecture Review: Semantic Core

> Target: `Idea/semantic-core-architecture.md`
> Reference: `Idea/semantic-code-manifesto.md`
> Focus: all (SRP, OCP, LSP, ISP, DIP + structural integrity)
> Mode: review + refactoring directions
> Posture: adversarial — find everything that collapses under implementation pressure

---

## Findings

### 1. [Critical] The S-Quant is a god object disguised as a schema

**Principle:** SRP
**Evidence:** The S-Quant schema contains:
- identity (`id`, `parent-id`)
- intent (declarative description)
- contract (inputs, outputs, invariants)
- embedding (vector, model-id, dimensions)
- source code (language, path, span, text)
- authority state (valid/drift/outdated/conflict)
- timestamps

This is not an "atomic unit" — it is **every concern in the system packed into one map**. It is a god object wearing a `:map` costume.

**Why it matters:** Every module in the system "depends on S-Quant schema" (the plan says this explicitly). That means every module depends on every other module's data. The Parser needs `:source`, the Embedding Pipeline needs `:embedding`, the Arbiter needs `:authority`, the Diff Engine needs `:embedding` + `:contract` + `:id`. When the Contract Engine evolves (and the plan says it's the most unstable piece), **every module that touches S-Quant must be retested**.

**Likely cost:** A change in contract formalization forces ripple through Normalizer, Diff Engine, Authority Arbiter, Ledger storage, and Query Interface. That is the opposite of localized change.

**Recommended direction:** S-Quant should not be one schema. It should be decomposed into:
- **Identity envelope** (id, parent-id, created-at, schema-version) — truly stable
- **Source record** (language, path, span, text) — owned by Parser
- **Contract record** (inputs, outputs, invariants) — owned by Contract Engine, nullable/optional
- **Embedding record** (vector, model-id, dimensions) — owned by Embedding Pipeline, nullable/pending
- **Authority state** — owned by Arbiter, separate lifecycle

The ledger stores **references between these**, not one fat row. Each module reads only the slice it owns.

**Confidence:** High

---

### 2. [Critical] The logical hash algorithm is load-bearing but undefined

**Principle:** Cross-cutting (foundational correctness)
**Evidence:** The plan says "Hash is computed from normalized AST structure (not text). Renaming a variable does not change the hash. Reordering independent let-bindings does not change the hash." The risk section calls this "underspecified" and proposes "start with normalized S-expression hash." But the plan then builds Semantic Diff, Authority arbitration, and the entire ledger identity on top of this hash.

**Why it matters:** This is not a risk — it is a **missing foundation**. The hash algorithm defines what "same meaning" means. Everything else is downstream. If two implementations disagree on what constitutes a non-semantic change, the Diff Engine produces contradictory results, Authority states become incoherent, and the ledger accumulates garbage.

The plan proposes "iterate the algorithm" — but the S-Quant ID *is* the hash. You cannot iterate the identity function of your primary key after you have data in the ledger. Every hash change is a full data migration.

**Likely cost:** Ship slice 1 with a naive hash. Ship slice 2 with a better hash. Every existing ledger entry is now orphaned or needs remapping. The "immutable append-only" guarantee dies on the first algorithm change.

**Recommended direction:** Do not defer this. The hash algorithm is **the first thing to design and stabilize**, not a thing to iterate. Build a golden test suite of 50+ pairs (same-meaning, different-meaning) across at least 2 languages. Freeze the algorithm before storing a single S-Quant. If the algorithm must change later, design a versioned hash scheme from day one (`hash-algo: v1`) with explicit migration protocol.

**Confidence:** High

---

### 3. [High] SemanticLedger protocol has mixed responsibilities

**Principle:** ISP, SRP
**Evidence:** The SemanticLedger protocol has 6 methods:
- `append!` — write
- `resolve-quant` — read by ID
- `history` — read history chain
- `search-by-vector` — vector similarity search
- `search-by-intent` — text search
- `diff` — semantic comparison

**Why it matters:** `diff` is a **pure computation** (compare two S-Quants). It has nothing to do with storage. Putting it on the storage protocol forces the InMemoryLedger and PostgresLedger to both implement diff logic, duplicating the Semantic Diff Engine or awkwardly delegating to it. This is a textbook ISP violation: the storage protocol forces clients to depend on a method that belongs to a different boundary.

Similarly, `search-by-vector` and `search-by-intent` are **query strategies**, not storage primitives. A storage layer that knows how to do semantic similarity search is a storage layer that knows about embeddings, distances, and ranking — i.e., it knows about AI concerns.

**Likely cost:** Adding a new search strategy (e.g., hybrid vector+text, or graph-based traversal) requires modifying the protocol, which forces changes in all implementations.

**Recommended direction:** Split into:
- **LedgerWriter** — `append!`
- **LedgerReader** — `resolve-quant`, `history`
- **SemanticSearch** — `search-by-vector`, `search-by-intent` (can have Postgres-backed and in-memory implementations independently)
- **SemanticDiff** stays a pure function, not on any protocol

**Confidence:** High

---

### 4. [High] The Authority Arbiter solves a problem that doesn't exist in slices 1-4

**Principle:** OCP (speculative abstraction)
**Evidence:** The plan defines a full state machine (VALID → DRIFT → OUTDATED → CONFLICT) with hierarchy `CONSENSUS > HUMAN > MACHINE > AI`. But:
- Slice 1: one-way ingest (Human → AI). No conflict possible.
- Slice 2: append to ledger + diff. Still one-way. No conflict.
- Slice 3: authority + contract engine. First time authority is relevant.
- Slice 4: MCP + multi-language. No new conflict vectors.
- Slice 5: AI → Human feedback. **First real two-way flow.**

The OUTDATED state requires Machine projection (JIT optimizations), which is slice 6+. The DRIFT state requires AI proposing changes, which is slice 5. The CONFLICT state requires Machine + Human disagreement.

**Why it matters:** The state machine is designed for a system that will exist in 2+ years, but it is planned as slice 3. This means you build and maintain a conflict resolution system for 2 slices where no conflicts can occur, then discover the real conflict patterns are different from what you predicted. The most likely outcome: the state machine gets redesigned when slice 5 reveals actual conflict patterns.

**Likely cost:** Wasted implementation effort in slice 3. Redesign cost in slice 5.

**Recommended direction:** Defer the Authority Arbiter entirely until slice 5. In slices 1-4, authority is always HUMAN (the only source of truth). When real two-way flows exist, **observe actual conflict patterns first**, then design the state machine from evidence. The plan's own advice in the Change Model says "arbitration rules evolve as we understand real conflict patterns" — so don't freeze a state machine before you have patterns.

**Confidence:** High

---

### 5. [High] The Contract Engine is a boundary without content

**Principle:** SRP, OCP (premature boundary)
**Evidence:** The plan says: "contract formalization is the hardest unsolved piece." The risk section says: "Contract is optional in slice 1. S-Quant has `:contract nil` until explicitly provided." The manifesto says: "Contract — too vague. Spec? Malli? Property-based tests? Must be executable, not docstring."

The Contract Engine is defined as a separate module with its own boundary, axis of change, and protocol. But **nobody knows what it does yet.** The inputs are "malli schemas, function signatures, docstrings, test results" — four completely different data sources with different reliability levels and different extraction methods. This is not one module; it is an entire research problem.

**Why it matters:** You cannot draw a stable boundary around something you don't understand. The boundary will either be too narrow (forcing constant expansion) or too wide (becoming a dumping ground for "anything contract-related"). Most likely: the Contract Engine becomes a god module that absorbs type inference, spec extraction, test analysis, and AI-assisted contract generation — exactly the mixed-responsibility problem the plan claims to avoid.

**Likely cost:** The boundary is wrong from day one. Redesign when you understand what "contract" actually means in practice.

**Recommended direction:** Do not create a Contract Engine boundary yet. In slice 1-2, a contract is a simple nullable map attached to the Normalizer output (function signature → `:contract`). When you know what contract inference looks like (slice 3+), create the boundary around **the actual responsibilities that emerged**. Let the design emerge from the problem, not from a placeholder name.

**Confidence:** High

---

### 6. [High] LanguageAdapter protocol conflates parsing and normalization

**Principle:** SRP
**Evidence:** The protocol has:
```clojure
(parse-file [adapter file-path source-text])      ;; parsing
(normalize-units [adapter ast-nodes file-path])    ;; normalization
(supported-extensions [adapter])                   ;; metadata
```

**Why it matters:** The plan defines Parser (boundary 1) and Normalizer (boundary 2) as separate modules with different axes of change. Then it puts both responsibilities on the same protocol. A new language must implement both parsing AND normalization in one object. But the plan says normalization rules "evolve as we learn what 'meaning' looks like" — that is a different rate of change than grammar versions. Coupling them means grammar updates force normalization retesting and vice versa.

**Likely cost:** Every normalization algorithm change requires touching every LanguageAdapter. Every new language must solve normalization on day one instead of reusing shared heuristics.

**Recommended direction:** Split into `LanguageParser` (parse-file, supported-extensions) and a separate normalization layer that can apply shared heuristics across languages, with per-language overrides only where needed.

**Confidence:** High

---

### 7. [Medium] "Append-only immutable ledger" + "Postgres" = silent complexity bomb

**Principle:** Cross-cutting (operational risk)
**Evidence:** The plan says: "Immutable append-only storage of S-Quants with their projections. Time travel via parent_id chain." The schema stores `payload` as `JSONB/Bytea` with `projection_type` enum (HUMAN, MACHINE, AI) per entry.

**Why it matters:** An append-only ledger in Postgres is not Datomic. You are building:
- Your own temporal query layer (history via parent_id traversal — recursive CTE or application-level loop)
- Your own conflict resolution on top of MVCC that already exists in Postgres
- Your own compaction/GC strategy (acknowledged in risks as "deferred")
- Your own consistency guarantees for vector search across time-traveling data

Postgres is great at mutable rows with transactional consistency. Using it as an immutable log fights its strengths and demands constant custom engineering. Datomic, XTDB, or even a simple event-sourcing table with snapshot materialization would be more natural fits.

**Likely cost:** Months of custom temporal query optimization. Slow history queries as the ledger grows. Complex GC that risks breaking parent_id chains. Vector search that must filter by "latest version" on every query, degrading pgvector performance.

**Recommended direction:** Either:
(a) Use Postgres as a **mutable store with audit log** — the main table holds current state, a separate `_history` table holds previous versions. Standard pattern, well-understood.
(b) Use XTDB or Datomic which are designed for bitemporal immutable storage.
(c) If you insist on append-only in Postgres, design the materialized view strategy NOW, not "deferred." You need a `current_quants` view from day one.

**Confidence:** Medium (depends on query patterns that don't exist yet)

---

### 8. [Medium] Embedding on the EmbeddingProvider protocol: `similarity` doesn't belong

**Principle:** ISP
**Evidence:** The protocol includes:
```clojure
(similarity [provider v1 v2] "Cosine similarity between two vectors")
```

**Why it matters:** Cosine similarity is a pure math function. It does not depend on the embedding model, Ollama, OpenAI, or any provider. Putting it on the provider forces every implementation to include a copy of `(dot v1 v2) / (norm v1 * norm v2)`. The Semantic Diff Engine needs similarity but should not need an embedding provider — it works on already-computed vectors.

**Likely cost:** Small, but it reveals a pattern: the plan stuffs related operations onto the nearest protocol instead of asking "who actually needs this?"

**Recommended direction:** `similarity` is a standalone function in a `semantic-core.math` namespace. Not on any protocol.

**Confidence:** High

---

### 9. [Medium] The Projection Engine (boundary 8) has no clear responsibilities

**Principle:** SRP (vacuous boundary)
**Evidence:** "Render an S-Quant for a specific consumer (Human text, Machine IR, AI vector + metadata)." But:
- The Human projection is just... the source code. Which the Parser already extracted.
- The AI projection is the embedding. Which the Embedding Pipeline already produced.
- The Machine projection doesn't exist until slice 6+.

**Why it matters:** This module is a pass-through. It takes data that already exists on the S-Quant and reformats it. In Clojure, that is a `select-keys` call, not a boundary.

**Likely cost:** Low. But it clutters the architecture with a module that has no real logic until far-future slices.

**Recommended direction:** Delete this boundary. If rendering becomes complex (e.g., interactive diagrams in slice 5+), create the boundary then, shaped by actual requirements.

**Confidence:** Medium

---

### 10. [Medium] The plan's SOLID self-check is a rubber stamp

**Principle:** Cross-cutting (review integrity)
**Evidence:** The SOLID Check section at the bottom:
- "SRP: Each boundary owns one axis of change." — Finding 1 shows S-Quant is a shared god schema. Finding 6 shows LanguageAdapter mixes two axes.
- "OCP: New languages attach via LanguageAdapter protocol." — Finding 6 shows this protocol couples parsing and normalization.
- "ISP: EmbeddingProvider has 3 methods, not 30." — Finding 8 shows one of those methods doesn't belong on the protocol.
- "LSP: InMemoryLedger and PostgresLedger honor the same contract." — Finding 3 shows `diff` on the ledger protocol will be inconsistently implemented.

**Why it matters:** A self-check that confirms the plan without challenging it provides false confidence. Every claim in the SOLID Check section has a counterexample in the plan itself.

**Likely cost:** Proceeding with confidence into implementation without noticing structural issues.

**Recommended direction:** Delete the self-congratulatory SOLID check. Replace with a "Known SOLID tensions" section that honestly lists where the plan makes compromises and why.

**Confidence:** High

---

### 11. [Medium] Slice 1 is not thin enough

**Principle:** Sequencing
**Evidence:** Slice 1 activates: Parser, Normalizer, Embedding Pipeline, Semantic Ledger, Query Interface (CLI). That is **5 out of 10 boundaries** including the two protocols (EmbeddingProvider, SemanticLedger) and an external dependency (Ollama).

**Why it matters:** A "thin vertical slice" that requires standing up a tree-sitter pipeline, a normalized AST with logical hashing, an embedding model integration, a storage layer, AND a CLI query interface is not thin. It is the entire read path of the system. If any one piece is wrong (especially the hash algorithm — finding 2), the whole slice is invalid.

**Likely cost:** Months before first useful output. High risk of discovering a foundational issue (hash algorithm, embedding quality, normalization approach) after building the full pipeline.

**Recommended direction:** True slice 0:
1. **Hash algorithm only.** Parse one Clojure file, normalize, compute hash. Golden test suite. No embeddings, no storage, no CLI.
2. **Hash + embedding.** Add Ollama. Compare: do similar functions get similar vectors? Is the hash boundary correct?
3. **Storage + query.** Now add Postgres and CLI.

Each sub-slice validates one assumption before the next builds on it.

**Confidence:** High

---

### 12. [Low] The Orchestrator is labeled "policy" but it's coordination

**Principle:** DIP (mislabeling)
**Evidence:** The dependency diagram labels the Orchestrator as "(policy)". But the plan says: "Wire the pipeline: parse → normalize → attach contract → embed → store in ledger → update authority. Coordinate the sync loop." That is orchestration — sequencing and error handling — not domain policy.

**Why it matters:** If the Orchestrator is treated as policy, it becomes the place where domain rules accumulate ("when should we re-embed? when is a contract stale? what constitutes a meaningful change?"). The plan explicitly says Diff Engine and Arbiter own those rules, but labeling the Orchestrator as "policy" creates ambiguity about where rules live.

**Likely cost:** Low in early slices. In later slices, risk of the Orchestrator absorbing domain logic because its "policy" label gives implicit permission.

**Recommended direction:** Relabel as "coordination" or "workflow." Explicitly state: the Orchestrator makes no domain decisions. It sequences calls and handles errors. All domain rules live in Diff Engine, Arbiter, and Contract Engine.

**Confidence:** Medium

---

## Open Questions

1. **What does "intent" actually mean?** The S-Quant has `:intent :string` — "Declarative description." Who writes this string? The developer? The AI? Is it extracted from docstrings? Generated from function names? This is the core concept of the manifesto ("code is intent") and it is a `:string` field with no source, no generation strategy, and no validation.

2. **How does the system handle a function with no meaningful contract?** In Clojure, many functions are polymorphic, accept arbitrary maps, and return arbitrary maps. `:contract {:inputs [:vector :any] :outputs :any}` is vacuous — it tells you nothing. What percentage of real Clojure code will have vacuous contracts? If it's >50%, the Contract Engine produces noise, not signal.

3. **What happens when embedding model quality is bad?** The Semantic Diff falls back to hash + embedding distance. If the model is mediocre (and local Ollama models are), the "non-semantic" vs "semantic" boundary is unreliable. The system will produce confident-looking diff results based on unreliable vector distances. Is that worse than no diff at all?

4. **Who is the user?** The manifesto says "developer." The plan says "AI agents via MCP." The CLI says "human at terminal." These are different users with different needs. The plan does not prioritize.

---

## Refactoring Sequence

If proceeding with this architecture:

1. **Decompose S-Quant** into identity envelope + attached records. This is structural and affects everything downstream — do it before writing any code.

2. **Stabilize the hash algorithm** with a golden test suite before building anything on top of it. This is the foundation. No hash, no system.

3. **Split SemanticLedger protocol** into Writer, Reader, and Search. Move `diff` to a standalone function.

4. **Merge Parser + Normalizer boundaries initially.** Split LanguageAdapter into parser and normalizer only when normalization rules actually diverge from parsing.

5. **Delete Contract Engine, Projection Engine, Authority Arbiter** from the initial plan. They are boundaries around problems that don't exist yet. Re-introduce when real requirements emerge.

6. **Redefine Slice 1** as three sub-slices: hash validation → embedding validation → storage + query.

7. **Replace the SOLID self-check** with an honest tensions list.

**Stop condition:** After slice 0 (hash + embedding validation), evaluate: does semantic search over a Clojure codebase produce results that are meaningfully better than grep + tree-sitter structural search (what semidx already does)? If not, the entire premise needs revisiting before building the ledger, diff, and authority layers.
