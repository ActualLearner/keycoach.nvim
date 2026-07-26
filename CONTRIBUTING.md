# Contributing

KeyCoach is intentionally conservative: a weak recommendation is worse than no
recommendation. Changes to detection should include evidence-focused tests and
must preserve the privacy schema in `docs/product-spec.md`.

## Development

1. Install Neovim 0.10 or newer.
2. Run `make test`.
3. Make one behavior change through a public module interface.
4. Add a failing test, implement the behavior, then run `make check`.

Tests should describe observable behavior and should not call private detector,
ranking, serialization, or rendering helpers.

All code must target Lua 5.1 as implemented by Neovim's LuaJIT. Newer Lua
syntax such as `1_000` numeric separators or integer division `//` will not
load. This is also why the test suite runs headlessly inside Neovim's own
LuaJIT rather than a standalone Lua interpreter: it catches these
incompatibilities before users do.

## Pull requests

- Explain the user-visible behavior and its evidence threshold.
- Call out any change to captured or persisted fields.
- Include tests for success, silence on weak evidence, and malformed input where
  relevant.
- Keep runtime dependencies at zero unless the trade-off has been discussed in
  an issue first.
