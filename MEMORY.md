# Project Memory

Current implementation reality: what exists in this repository right now and
why. This is not a changelog of removed implementation; see `git log`.

## What Exists And Why

- `ARCHITECTURE_CONSTITUTION.md` remains **DRAFT, not ratified**. It has been
  distilled to product identity rather than conformance mechanics: semantic
  graph as the product, entity nodes rather than chunks, exact/unresolved/
  approximate separation, stable identity, incrementality with consistent
  observation, language frontends plus a common core, consumer independence, and
  local operation without mandatory source-data transmission.
- The constitution still owns exactly five terms whose distinctions are product
  identity: entity, node, relationship, assertion, and fact. Source containers
  are entities; source ingestion can establish facts about source organization;
  exact system resolution can establish facts when supporting evidence and
  method establish the claim.
- The constitution deliberately moved concrete requirements out of its frozen
  boundary. Core rosters, schemas, conformance checks, fixtures, measurements,
  storage mechanics, snapshot mechanics, fingerprint/revision mechanisms,
  delivery plans, implementation stack, local budgets, and process artifacts
  now belong in companion documents.
- This commit intentionally updates only the constitution and memory, because
  repository rules require constitution changes to be isolated. Companion
  documentation will be updated in the next commit to match the new document
  layout.

## What Does Not Exist Yet

- No graph implementation, test suite, build/dependency manifest, fixed
  implementation language, or source layout.
- No executable conformance suite, contracts, fixtures, published capability
  matrix, accepted core roster, or published semantic contract.

## Active Constraints And Known Gaps

- Ratification has not been performed. The DRAFT status keeps the constitution
  correctable until an explicit ratification commit changes the status line.
- The current supporting documents still contain references to the previous,
  more detailed constitution shape until the follow-up documentation migration
  lands.
