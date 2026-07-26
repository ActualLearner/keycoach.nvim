# Recommendation Engine Interface

## Requirements

The engine consumes content-free Observations, feedback, time, and an effective
mapping inventory. It returns a new durable checkpoint and ranked
Recommendations. Editor capture, persistence, rendering, clocks, and config
writes remain outside the engine.

## Designs considered

### Atomic transition

One pure entry point accepts an opaque checkpoint and a complete analysis cycle:

```lua
advance(checkpoint, cycle) -> transition, problem
```

The engine owns validation, idempotency, aggregation, feedback, detection,
candidate allocation, conflict checks, ranking, retention, and checkpoint
migration. This minimizes method count and prevents callers from learning an
ordering protocol.

### Extensible reducer program

A configured program exposes `initial_state`, `advance`, and `recommend`, plus
internal-style contracts for detectors, resolvers, and rankers. It makes future
experimentation easy, but turns hypothetical extension points into caller-facing
concepts and separates ingestion from output lifecycle.

### Stateful coaching facade

A mutable `Coach` opens Sessions, accepts Observations incrementally, creates
ephemeral Dashboard capabilities, and emits snapshots. This is convenient for
Neovim's hot path, but callers must obey Session, snapshot, and Dashboard
lifetime rules. Those rules would need to be reproduced in every editor adapter.

## Selected design

Use the atomic transition interface. Keep the versioned opaque checkpoint,
portable values, and internally replaceable detector/resolver/ranker modules
from the reducer design. Let the Neovim adapter buffer activity cheaply and call
the engine on idle, persistence flush, or dashboard open rather than per key.

```lua
local transition, problem = engine.advance(checkpoint, {
  now_ms = now_ms,
  observations = observations,
  feedback = feedback,
  inventory = inventory,
})
```

`transition` contains `checkpoint`, ranked `recommendations`, reversible
`exclusions`, newly evidenced `adoptions`, and non-fatal `notices`. A hard
problem returns no checkpoint; a repeated identical cycle produces the same
transition.

This interface has greater depth than the alternatives because deleting it
would force ingestion order, feedback state, confidence, conflicts, retention,
and ranking into every editor adapter.

## Why deterministic heuristics are enough for V1

Detection quality varies by signal, and the engine is tuned to recommend only
where reliability is high:

- **High reliability**: mapping occupancy and free-key checks, repeated
  command identities, exact repeated key sequences, and excessive primitive
  motion runs. These are directly observable and form the four V1 detectors.
- **Moderate reliability**: near-identical sequences, mappings introduced by
  lazy-loaded plugins (handled by inventory rescans), and mouse actions that
  resolve to an observable command.
- **Weak reliability**: opaque plugin UI interactions and Lua callbacks, and
  anything requiring intent inference.

Weak signals must produce fewer Recommendations, never incorrect ones — which
the silence invariants below enforce. Upgrade paths past hand-written rules
are recorded in the [roadmap](../roadmap.md).

## Invariants

- All crossing values are JSON-compatible and pass a closed privacy schema.
- Observation and feedback identities make retries idempotent.
- Session ordinals are monotonic; time cannot regress.
- A cycle applies atomically or returns no new checkpoint.
- Recommendation ordering and identifiers are deterministic.
- Snooze and Exclusion target stable Workflow Patterns, not transient cards.
- Existing Mapping and native alternatives precede Mapping Candidates.
- A Mapping Candidate is valid only for the supplied inventory revision.
- Adoption is inferred from later Observations, never asserted by the UI.
- Weak evidence, incomplete inventory, or no free candidate yields silence.

## Confirmed test seams

The user delegated routine engineering decisions after approving the product
contract. Tests therefore exercise these selected public seams:

1. `require("keycoach.engine").advance` for analysis, feedback, retention,
   conflict behavior, determinism, and portable golden fixtures.
2. `require("keycoach").setup`, status, dashboard data, feedback, and apply for
   observable Neovim plugin behavior, using a temporary mappings file.

Tests do not call private detectors, rankers, serializers, or UI render helpers.
