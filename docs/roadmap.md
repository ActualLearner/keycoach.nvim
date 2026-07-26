# Roadmap

Deferred ideas that were considered and intentionally postponed, so they are
not re-litigated from scratch. Nothing here is a commitment; V1 scope is
defined by the [product specification](product-spec.md).

## Detection beyond hand-written rules

The detector modules are internally replaceable specifically so analysis can
grow past deterministic heuristics without changing the engine interface.
Explored upgrade paths, in rough order of likelihood:

1. **Plugin-specific adapters** that translate opaque plugin actions
   (pickers, file trees, completion menus) into bindable action identities,
   raising detection coverage where evidence is currently weak.
2. **Stronger local sequence mining** over the same content-free
   Observations, finding longer or fuzzier Workflow Patterns than the V1
   adjacent-pair detector.
3. **An optional privacy-preserving model** operating only on redacted event
   summaries, never on content. This must not weaken the capture boundary and
   would be opt-in.

## Sequence remedies beyond a single mapping

The stable-sequence detector currently proposes only a sequence Mapping
Candidate. Recording the sequence as a replayable macro was part of the
original detector design and remains a valid alternative remedy where a
mapping is a poor fit.

## Delivery

- **Rate-limited idle notification**: an off-by-default nudge when the editor
  is idle, for users who never open the dashboard. Pull-first remains the
  default; this must never interrupt active editing.

## Platforms

Committed sequence: Neovim, then VS Code, then classic Vim
([product spec](product-spec.md)). Also floated: **JetBrains adapters**,
feasible only if the portable domain model holds and the IDE exposes enough
observable actions.

## Operation

- **Anonymous opt-in telemetry**: none at launch; GitHub Issues is the
  feedback channel. If ever added, it is a separate explicit opt-in and
  carries only content-free aggregate counts, subject to the same
  never-persist list as local Observations.
- **Docs site on GitHub Pages**: only if the README and `docs/` outgrow
  themselves; must stay on free facilities.
