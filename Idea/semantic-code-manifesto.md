# Semantic Code: Multidimensional Representation of Programs

> Distilled from brainstorming session (source: `new-idea.md`).
> Raw ideas preserved, repetition and conversational scaffolding removed.

---

## Core Thesis

Code is not text. Text is one of many projections of a logical entity.
A program is a **multidimensional object** that can be viewed through different lenses
at different levels of detail — like C4 model levels (Context → Code).

Three projections exist simultaneously:

| Projection | Consumer | Native format | Purpose |
|---|---|---|---|
| **Human** | Developer | Declarative text (S-expressions, intent-based syntax) | Cognitive readability, intent expression |
| **Machine** | CPU/JVM | Bytecode, LLVM IR, WASM | Execution, optimization |
| **AI** | Embedding model | Vector in semantic space (tensor of joint embeddings) | Search, analysis, translation, optimization |

These are not competing representations — they are **zoom levels of the same fractal**.
A change at Machine level (JIT optimization) is just a detail refinement at L3;
it doesn't alter Context (intent) at L1.

---

## Key Insight: Intent as Invariant

The "conflict" between readable code and fast code is a false dilemma.
It existed because compilation was a **one-way ticket** — we destroyed intent
when producing bytecode and couldn't recover it.

AI breaks this barrier. It acts as a **universal sense decoder**:
- Machine produces optimized "spaghetti" (SIMD, unrolled loops, bit shifts)
- AI reverse-engineers the invariant: "these 150 instructions implement FFT"
- Human sees a clean high-level abstraction

Result: code exists in **superposition** — maximally efficient for execution
and maximally clear for analysis — simultaneously. No compromise needed.

---

## The Atomic Unit: S-Quant (Semantic Quantum)

The atomic node of the semantic graph is a **triplet**:

```
S-Quant:
  id:        Hash(logical_structure)  — NOT hash of text; formatting is irrelevant
  intent:    Reference to declarative description ("sort list descending")
  contract:  Input/output types + invariants (what must not change)
  embedding: Coordinates in multidimensional meaning-space
```

Hash is computed from **logical structure** (normalized AST), not source text.
Otherwise whitespace/formatting breaks identity.

### Multidimensional Embedding (Joint Embeddings)

A single vector is insufficient. The embedding is a **tensor** combining:
1. **Structural** — from AST/graph
2. **Functional** — from test results and runtime behavior
3. **Intentional** — from comments, docs, and developer history

When overlaid, these produce **"stereoscopic vision"** of code.

---

## Semantic Diff: The Most Valuable Concept

Formal separation between two types of change:

### Non-Semantic Change (Refactoring)
Implementation changes, contract preserved.
Example: replacing `filter` with `reduce` yielding identical results.
→ New `node_id` for Machine projection, **same** `node_id` for Intent.

### Semantic Change (Logic mutation)
Contract or intent is altered.
Example: function now returns `nil` instead of error, or sorts by date instead of ID.
→ **New top-level node** in the graph. A branch of meaning.

Without this distinction, the graph degrades into an infinite append-only log.

---

## Storage: Semantic Ledger

Immutable event-graph in PostgreSQL. Each record is a **transaction of meaning**.

```
semantic_ledger:
  node_id          UUID        — reference to S-Quant
  projection_type  Enum        — HUMAN | MACHINE | AI
  payload          JSONB/Bytea — projection content
  parent_id        UUID        — previous iteration of this meaning (time travel)
  context_tags     Array       — project, task, author labels
  authority        Enum        — HUMAN | MACHINE | AI | CONSENSUS
  integrity_hash   Hash        — checksum confirming all three projections are aligned
```

Tech stack:
- **PostgreSQL** — single engine for EAV, vectors, and graph-like queries
- **pgvector** — stores embeddings alongside code, enables semantic SQL queries
- **Clojure** — homoiconic: code is already data, trivial to convert to semantic graph
- **REPL** — the sync loop already exists in one direction (Human → AST → Bytecode)

---

## Arbitration Protocol: Who Owns the Truth?

When projections disagree, the system needs a **conflict resolution protocol**.

### States

| State | Condition | Authority |
|---|---|---|
| **VALID** | Human Intent = Machine Tests = AI Vector | CONSENSUS |
| **DRIFT** | Human changed code, AI confirmed meaning, tests pending | HUMAN (Pending) |
| **OUTDATED** | Machine optimized, AI confirmed isomorphism, Human sees stale text | MACHINE |
| **CONFLICT** | Machine reports FAIL but Human claims code is correct | MANUAL_REQUIRED |

### Hierarchy
Canonical S-Quant is the one with highest authority:
`CONSENSUS > HUMAN > MACHINE > AI`

Any change breaking `integrity_hash` → node moves to `STAGING`
until new consensus is reached.

### Cross-Validation on CONFLICT
1. AI generates formal proof that Human Intent matches Machine Bytecode
2. Property-based testing generates counterexample if Machine disagrees
3. Human sees report and resolves: fix Intent or fix Code

---

## The Feedback Loop (Three-Way Bridge)

```
Human ──writes intent──→ Semantic Core ──compiles──→ Machine
  ↑                           ↑                         │
  │                           │                         │
  └──── AI renders ←──── AI observes ←── telemetry ────┘
        human view        runtime data
```

- Human → Machine: classic compilation (intent → bytecode)
- Machine → AI: telemetry — load, branching, actual data types at runtime
- AI → Human + Machine: optimization proposals, meaning translation between zoom levels

The REPL solves one direction. The idea is to **extend REPL to a three-participant loop**
where AI is a permanent observer and translator.

---

## Why Clojure Is the Natural Fit

- **Homoiconicity**: code is data. Mapping `Data ↔ Code` is direct.
  The parse tree IS the code — ideal "food" for AI.
- **REPL**: the tightest Human→Machine feedback loop in mainstream languages.
  Foundation for extending to three-way sync.
- **Immutability**: aligns with append-only semantic ledger.
  State changes are explicit, auditable.
- **S-expressions**: minimal syntax = minimal noise in embeddings.
  No syntactic sugar polluting the semantic signal.

---

## Risks and Open Questions

### Solved (in principle)
- **Synchronization**: not a "problem" but a process. Three projections are views
  of a live object, not files on disk. Changes propagate like database replication.
- **Bidirectional mapping**: Clojure's homoiconicity makes this tractable.
  Image-based systems (Smalltalk, Unison) prove the concept.

### Unsolved
1. **Embedding latency**: generating vectors on every eval kills REPL flow.
   Needs async/batch strategy or local model (Ollama?).
2. **Contract formalization**: "input/output types and invariants" in a dynamically
   typed language. Spec? Malli? Property-based tests? Must be executable, not docstring.
3. **Integrity hash algorithm**: how exactly to verify that Intent, Contract,
   and Embedding "correspond to each other" — not defined.
4. **Silent AI drift**: if AI gradually misinterprets meaning without triggering
   CONFLICT, the graph accumulates invisible semantic debt.
5. **Storage growth**: every eval → ledger record with 3 projections + vector.
   Compaction / GC strategy needed.
6. **Semantic hallucination**: AI "beautifies" a bug in bytecode,
   shows clean picture in human projection. New class of bugs: **semantic bugs**.

---

## Minimum Viable Prototype

Do not build "the world of three planes" immediately. Start with:

1. **Postgres + pgvector**: store function text and its vector
2. **Clojure REPL hook**: on each `eval`, send code to local model, update vector in DB
3. **Semantic search**: find "logically similar" functions across past projects

This alone gives the superpower of meaning-based navigation
without the full arbitration complexity.
