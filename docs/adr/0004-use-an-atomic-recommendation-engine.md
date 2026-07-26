# Use one atomic transition as the recommendation engine interface

The recommendation engine exposes one pure `advance(checkpoint, cycle)` transition rather than separate observation, analysis, ranking, and feedback methods or a mutable Session facade. This keeps ordering, idempotency, retention, confidence, and suppression inside one deep module, at the cost of batching Neovim activity before analysis; versioned JSON-compatible fixtures make the same behavior portable to later editor adapters.
