# Architecture Plan: Semantic Core

> Multidimensional code representation engine.
> Code is not text — it is a multidimensional object with three simultaneous projections:
> Human (intent), Machine (execution), AI (embedding).

---

## Goal

Build a system where the atomic unit of code is an **S-Quant** (Intent + Contract + Embedding + logical hash), stored in an immutable **semantic ledger**, with formal **Semantic Diff** (implementation change vs meaning change), **authority arbitration** (who owns truth when projections disagree), and a **three-way feedback loop** between Human, Machine, and AI representations.

## Scope

New standalone system. Clojure core. PostgreSQL + pgvector storage.
Tree-sitter for multi-language parsing. Local embedding models (Ollama).
MCP interface for AI agent consumption.
Takes useful pieces from semidx (tree-sitter adapters, Semantic IR normalization)
but is not constrained by its architecture.

## Assumptions

1. The first useful output is **semantic search across a codebase** — find code by meaning, not by text.
2. The three-way sync loop is the end goal, but the first slice only covers Human → AI direction (ingest and query).
3. Machine projection (JIT introspection, bytecode analysis) is deferred — it requires deep runtime integration that is not viable in slice 1.
4. Embedding model is swappable. Ollama today, cloud API tomorrow, fine-tuned model later.
5. Single developer. No microservices. Monorepo, one Clojure process, one Postgres.
6. Contract = executable spec (malli schema), not docstring.

---

## Change Model

What is likely to vary soon:
- Embedding model (provider, dimensions, quality)
- Supported languages (new tree-sitter grammars)
- Storage backend (in-memory for tests, Postgres for prod, maybe Datomic later)
- Query interface (MCP today, HTTP API tomorrow, CLI)
- Contract formalization approach (malli, spec, property-based tests)

What should stay stable:
- S-Quant structure (the atomic unit)
- Semantic ledger schema (append-only, immutable)
- Semantic Diff algorithm (implementation vs meaning change)
- Authority state machine (VALID → DRIFT → OUTDATED → CONFLICT)
- Pipeline protocol: parse → normalize → hash → embed → store → query

What must be easy to test or swap:
- Embedding provider (behind a protocol)
- Storage backend (behind a protocol)
- Parser layer (behind a protocol per language)
- Authority resolver (pure function, no I/O)

---

## Boundaries

### 1. Parser (multi-language AST extraction)

**Responsibility:** Take source file + language → produce raw AST nodes.
**Knows about:** tree-sitter grammars, language-specific node types.
**Does not know about:** S-Quants, embeddings, storage, authority.
**Axis of change:** new languages added frequently; grammar versions change.
**Reuse from semidx:** tree-sitter adapter layer, language modules (Clojure, Python, TypeScript, Elixir, Java).

### 2. Normalizer (AST → Semantic IR → S-Quant skeleton)

**Responsibility:** Transform raw AST into normalized Semantic IR units, then into S-Quant skeletons (id, intent, contract — no embedding yet).
**Knows about:** Semantic IR schema, AST node types, logical hash algorithm.
**Does not know about:** embeddings, storage, authority state.
**Axis of change:** normalization rules evolve as we learn what "meaning" looks like per language.
**Key design decision:** Hash is computed from **normalized AST structure** (not text). Renaming a variable does not change the hash. Reordering independent let-bindings does not change the hash.

### 3. Contract Engine

**Responsibility:** Attach executable contracts (input/output schemas, invariants) to S-Quant skeletons.
**Knows about:** malli schemas, function signatures, docstrings, test results.
**Does not know about:** embeddings, storage, authority.
**Axis of change:** contract sources expand (manual specs → inferred from tests → inferred by AI).
**Why separate:** contract formalization is the hardest unsolved piece. It will iterate fast and independently from parsing and embedding.

### 4. Embedding Pipeline

**Responsibility:** Take S-Quant skeleton (intent + contract + source) → produce joint embedding vector.
**Knows about:** embedding model API, tokenization strategy, vector dimensions.
**Does not know about:** storage, authority, parsing.
**Axis of change:** model swaps, dimensionality changes, multi-vector strategies (structural + functional + intentional).
**Protocol:**

```clojure
(defprotocol EmbeddingProvider
  (embed-unit [provider s-quant-skeleton] "Returns {:vector [...] :model-id ... :dimensions ...}")
  (embed-batch [provider skeletons] "Batch embedding for pipeline efficiency")
  (similarity [provider v1 v2] "Cosine similarity between two vectors"))
```

**Implementations:** OllamaProvider, OpenAIProvider, NoOpProvider (for tests).

### 5. Semantic Ledger (storage)

**Responsibility:** Immutable append-only storage of S-Quants with their projections. Time travel via parent_id chain. Vector search via pgvector.
**Knows about:** PostgreSQL, pgvector, EAV model, snapshot management.
**Does not know about:** parsing, embedding generation, authority resolution logic.
**Axis of change:** storage engine (Postgres now, possibly Datomic later), schema migrations, query optimization.
**Protocol:**

```clojure
(defprotocol SemanticLedger
  (append! [ledger s-quant projection-type payload]
    "Append a new entry. Returns ledger-entry-id.")
  (resolve-quant [ledger quant-id]
    "Return latest S-Quant with all projections.")
  (history [ledger quant-id]
    "Return full parent_id chain for time travel.")
  (search-by-vector [ledger embedding-vec opts]
    "Semantic similarity search. Returns ranked S-Quants.")
  (search-by-intent [ledger intent-text opts]
    "Text-based intent search.")
  (diff [ledger quant-id-a quant-id-b]
    "Return SemanticDiff between two quants."))
```

**Implementations:** PostgresLedger, InMemoryLedger (for tests).

### 6. Semantic Diff Engine

**Responsibility:** Given two S-Quants, determine whether the change is **non-semantic** (implementation only) or **semantic** (meaning changed).
**Knows about:** logical hashes, contract comparison, embedding distance thresholds.
**Does not know about:** storage, parsing, authority.
**Axis of change:** diff thresholds, comparison algorithms, what counts as "same meaning."
**Key algorithm:**

```
if hash(A.ast) == hash(B.ast)           → IDENTICAL
if hash(A.ast) != hash(B.ast)
   AND A.contract == B.contract
   AND cosine(A.embedding, B.embedding) > threshold
                                        → NON_SEMANTIC (refactoring)
if A.contract != B.contract
   OR cosine(A.embedding, B.embedding) < threshold
                                        → SEMANTIC (meaning changed)
```

**Pure function, no I/O.** Fully testable with synthetic S-Quants.

### 7. Authority Arbiter

**Responsibility:** Manage the authority state machine per S-Quant. Determine which projection is canonical when they disagree.
**Knows about:** authority states (VALID, DRIFT, OUTDATED, CONFLICT), escalation rules, integrity_hash.
**Does not know about:** storage details, embedding generation, parsing.
**Axis of change:** arbitration rules evolve as we understand real conflict patterns.
**State machine:**

```
VALID (consensus)
  │
  ├─ Human changes code ────→ DRIFT (human, pending machine/AI confirmation)
  ├─ Machine optimizes ─────→ OUTDATED (machine, pending human acceptance)
  ├─ AI proposes change ────→ DRIFT (AI, pending human+machine confirmation)
  │
DRIFT / OUTDATED
  │
  ├─ All projections align ─→ VALID
  ├─ Test failure ──────────→ CONFLICT
  │
CONFLICT
  │
  ├─ Human resolves ────────→ VALID
  └─ (blocks all propagation until manual resolution)
```

**Hierarchy:** `CONSENSUS > HUMAN > MACHINE > AI`
**Pure function for state transitions.** Side effects (notifications, blocks) handled by orchestrator.

### 8. Projection Engine

**Responsibility:** Render an S-Quant for a specific consumer (Human text, Machine IR, AI vector + metadata).
**Knows about:** projection types, rendering formats.
**Does not know about:** storage internals, authority logic.
**Axis of change:** new projection formats (diagram, interactive, REPL-friendly).

### 9. Orchestrator (Pipeline Coordinator)

**Responsibility:** Wire the pipeline: parse → normalize → attach contract → embed → store in ledger → update authority. Coordinate the sync loop.
**Knows about:** pipeline stages (as protocols), execution order, error handling.
**Does not know about:** implementation details of any stage.
**Axis of change:** pipeline topology (batch vs streaming, sync vs async).

### 10. Query Interface (MCP + CLI)

**Responsibility:** Expose semantic search, diff, history, projections to external consumers (AI agents, humans).
**Knows about:** MCP protocol, CLI arg parsing, query schema.
**Does not know about:** embedding generation, parsing, storage details.
**Axis of change:** new transports (HTTP, gRPC), new query types.

---

## Contracts (Key Interfaces)

### 1. S-Quant Schema

**Client:** every module in the system.
**Shape (malli):**

```clojure
[:map
 [:id        :string]          ;; Hash(normalized-AST)
 [:intent    :string]          ;; Declarative description
 [:contract  [:map
              [:inputs  [:vector :any]]
              [:outputs :any]
              [:invariants [:vector :string]]]]
 [:embedding [:map
              [:vector     [:vector :double]]
              [:model-id   :string]
              [:dimensions :int]]]
 [:source    [:map
              [:language :keyword]
              [:path     :string]
              [:span     [:map [:start-line :int] [:end-line :int]]]
              [:text     :string]]]
 [:authority [:enum :valid :drift :outdated :conflict]]
 [:parent-id [:maybe :string]]
 [:created-at :inst]]
```

**Variation strategy:** schema versioning via `:schema-version` field.

### 2. EmbeddingProvider Protocol

**Client:** Orchestrator (pipeline).
**Shape:** see Boundary 4 above.
**Variation:** direct protocol implementation. Ollama, OpenAI, NoOp.

### 3. SemanticLedger Protocol

**Client:** Orchestrator, Query Interface.
**Shape:** see Boundary 5 above.
**Variation:** direct protocol implementation. Postgres, InMemory.

### 4. LanguageAdapter Protocol

**Client:** Parser layer.
**Shape:**

```clojure
(defprotocol LanguageAdapter
  (parse-file [adapter file-path source-text]
    "Returns raw AST nodes for the file.")
  (normalize-units [adapter ast-nodes file-path]
    "Returns seq of normalized Semantic IR units.")
  (supported-extensions [adapter]
    "Returns set of file extensions, e.g. #{\"clj\" \"cljc\"}"))
```

**Variation:** one implementation per language.

### 5. SemanticDiff Result Schema

**Client:** Query Interface, Authority Arbiter.
**Shape:**

```clojure
[:map
 [:diff-type   [:enum :identical :non-semantic :semantic]]
 [:hash-match  :boolean]
 [:contract-match :boolean]
 [:embedding-distance :double]
 [:details     :string]]
```

---

## Dependency Direction

```
                    ┌─────────────────┐
                    │  Query Interface │  (MCP, CLI)
                    │  (edge adapter)  │
                    └────────┬────────┘
                             │ depends on
                    ┌────────▼────────┐
                    │   Orchestrator   │  (pipeline coordination)
                    │   (policy)       │
                    └──┬��─┬──┬──┬──┬──┘
                       │  │  │  │  │
          ┌────────────┘  │  │  │  └────────────┐
          ▼               ▼  │  ▼               ▼
    ┌──────────┐  ┌────────┐ │ ┌──────────┐ ┌─────────┐
    │  Parser  │  │Contract│ │ │ Semantic │ │Authority│
    │  Layer   │  │ Engine │ │ │  Diff    │ │ Arbiter │
    │ (detail) │  │(policy)│ │ │ (policy) │ │ (policy)│
    └──────────┘  └────────┘ │ └──────────┘ └─────────┘
                             │
                    ┌────────▼────────┐
                    │    Embedding    │
                    │    Pipeline     │
                    │    (detail)     │
                    └────────┬────────┘
                             │ depends on
                    ┌────────▼────────┐
                    │ EmbeddingProvider│  (protocol — Ollama, OpenAI, etc.)
                    └─────────────────┘

    All modules depend on:
    ┌─────────────────────────────┐
    │  S-Quant Schema (shared)    │  ← stable data contract
    │  SemanticLedger (protocol)  │  ← storage abstraction
    └─────────────────────────────┘
```

**Policy depends on abstractions** (protocols for storage, embedding, language adapters).
**Details plug into policy-owned seams** (Postgres, Ollama, tree-sitter — all replaceable).
**Orchestrator coordinates but does not absorb logic** — each stage owns its rules.

---

## Risks

### 1. [High] Embedding latency kills REPL flow
**Why it matters:** If every eval triggers a network call to Ollama (50-200ms), interactive development becomes sluggish.
**Mitigation:** Async embedding pipeline. Embed in background, mark S-Quant as `embedding-pending`. Allow queries on stale embeddings while fresh ones compute. Batch mode for bulk indexing.

### 2. [High] Logical hash algorithm is underspecified
**Why it matters:** Hash identity is the foundation. Get it wrong and semantic diff produces garbage. Get it too strict and trivial refactors create duplicate quants.
**Mitigation:** Start with normalized S-expression hash (strip whitespace, sort map keys, normalize names to positions). Test extensively with golden pairs: "these two should be same hash" / "these should differ." Iterate the algorithm before building on it.

### 3. [Medium] Contract formalization in dynamic language
**Why it matters:** Clojure has no static types. "Contract" must come from somewhere — malli specs, test suites, manual annotation, AI inference. All are partial.
**Mitigation:** Contract is optional in slice 1. S-Quant has `:contract nil` until explicitly provided. Semantic Diff falls back to hash + embedding distance when contract is absent. Add contract inference incrementally.

### 4. [Medium] Silent AI drift (hallucinated interpretation)
**Why it matters:** If embedding model "drifts" across versions, semantic distances shift. Two quants that were "same meaning" become "different" without any code change.
**Mitigation:** Store `model-id` and `dimensions` with every embedding. Re-embedding on model change is explicit migration, not silent drift. Integrity hash includes model-id.

### 5. [Low] Storage growth in append-only ledger
**Why it matters:** Every change creates a new ledger entry with vector. Over months, this grows fast.
**Mitigation:** Compaction strategy: retain only latest + semantic-change boundaries. Non-semantic intermediate entries can be pruned after N days. Deferred — not a slice-1 concern.

### 6. [Low] Three-way sync complexity
**Why it matters:** Full Human ↔ Machine ↔ AI loop is architecturally ambitious. Risk of building too much before proving value.
**Mitigation:** Phase it. Slice 1 is one-way (Human → AI). Slice 2 adds AI → Human (suggestions). Machine projection is slice 3+.

---

## Implementation Sequence

### Slice 1: Semantic Ingest + Search (proves core value)

**What:** Parse → Normalize → Hash → Embed → Store → Query by meaning.
**Components activated:**
- Parser layer (reuse semidx tree-sitter adapters for Clojure)
- Normalizer (reuse semidx Semantic IR, add logical hash)
- Embedding Pipeline (Ollama provider, NoOp for tests)
- Semantic Ledger (InMemoryLedger first, then PostgresLedger)
- Query Interface (CLI only: `semantic-core index .` / `semantic-core search "sort algorithm"`)

**Seam introduced early:** EmbeddingProvider protocol. Even in slice 1, embedding is behind a protocol so tests use NoOp and prod uses Ollama.
**What this protects against:** Locking into a specific embedding model.
**Deliverable:** Index a Clojure project, search by intent, get ranked results with source locations.

### Slice 2: Semantic Ledger + Diff

**What:** Switch from "overwrite index" to "append to ledger." Add Semantic Diff.
**Components activated:**
- Semantic Ledger (PostgresLedger with pgvector, parent_id chains)
- Semantic Diff Engine (hash + contract + embedding comparison)
- History/time-travel queries

**Seam introduced:** SemanticLedger protocol (InMemory for tests, Postgres for prod).
**What this protects against:** Losing the ability to track how meaning evolves over time.
**Deliverable:** Re-index after code change, see which functions changed meaning vs just implementation.

### Slice 3: Authority + Contract Engine

**What:** Add authority state machine. Add contract formalization.
**Components activated:**
- Authority Arbiter (state machine, conflict detection)
- Contract Engine (malli schema extraction from function signatures + optional manual specs)
- Integrity hash computation

**What this protects against:** Silent semantic drift. Multiple conflicting views of truth.
**Deliverable:** System flags when AI-inferred meaning disagrees with human-declared contract.

### Slice 4: MCP Interface + Multi-language

**What:** Expose full pipeline via MCP for AI agents. Add Python, TypeScript, Java parsers.
**Components activated:**
- MCP server (reuse semidx MCP patterns)
- Additional LanguageAdapter implementations

**What this protects against:** Being a single-language tool.
**Deliverable:** AI agent can query semantic meaning of a polyglot codebase.

### Slice 5: AI → Human Feedback Loop

**What:** AI generates suggestions (optimization, refactoring) that propagate back to human view.
**Components activated:**
- Projection Engine (render AI suggestions as human-readable diffs)
- Sync loop (AI observation → suggestion → human approval → ledger update)
- Authority transitions for AI-proposed changes

**Deliverable:** System suggests "this function is semantically identical to one in your other project, consider reuse" — and can show the semantic diff.

### Slice 6+ (Future): Machine Projection

**What:** JVM introspection, JIT observation, bytecode analysis.
**Deferred because:** requires deep runtime integration (GraalVM, JVM tooling) that is not justified until slices 1-5 prove value.

---

## What to Reuse from semidx

| semidx component | Reuse strategy |
|---|---|
| Tree-sitter adapters (Clojure, Python, TS, Elixir, Java) | Copy and adapt. These are leaf-node detail code. |
| Semantic IR normalization (`semantic_ir.clj`) | Fork as starting point for Normalizer. Add logical hash. |
| MCP server shell (`mcp/server.clj`, `mcp/core.clj`) | Reuse MCP protocol handling in Slice 4. |
| PostgreSQL connection patterns (`storage.clj`) | Reference for PostgresLedger, but schema is different (EAV vs snapshot). |
| Retrieval policy engine | Evaluate for reuse in query ranking. May be too coupled to old model. |
| Contracts/schemas validation | Reuse malli patterns for S-Quant schema validation. |

**Not reusing:** snapshot-based index model, in-memory atom-based state, usage metrics tracking (rebuild on new foundation).

---

## SOLID Check

- **SRP:** Each boundary owns one axis of change. Parser doesn't know about embeddings. Arbiter doesn't know about storage. Diff engine is pure function.
- **OCP:** New languages attach via LanguageAdapter protocol. New embedding models via EmbeddingProvider. New storage via SemanticLedger. No rewrites.
- **LSP:** InMemoryLedger and PostgresLedger honor the same contract. OllamaProvider and OpenAIProvider return the same shape. Tests prove substitutability.
- **ISP:** EmbeddingProvider has 3 methods, not 30. SemanticLedger has 6 focused operations. No client forced to depend on methods it doesn't use.
- **DIP:** Orchestrator depends on protocols, not Postgres. Policy (Diff, Arbiter) depends on S-Quant schema, not on how embeddings are generated.
