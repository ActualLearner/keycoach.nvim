# keycoach.nvim

[![CI](https://github.com/ActualLearner/keycoach.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ActualLearner/keycoach.nvim/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/tag/ActualLearner/keycoach.nvim?label=release)](https://github.com/ActualLearner/keycoach.nvim/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Local-first workflow coaching for Neovim.

![KeyCoach demo: quiet observation, recommendation card, one-keystroke apply](assets/demo.gif)

Type the same long commands day after day — `:Telescope find_files`, `:b#`, `:nohl` — and never
build the muscle memory for a faster way? KeyCoach quietly watches how you edit, notices what you
repeat, and suggests a keymapping that fits your setup: one you already have but keep forgetting,
or a conflict-free new one, applied with a single keystroke.

Everything runs on your machine. KeyCoach never sees inserted text, search or command arguments,
or file contents — only that you pressed keys in normal mode or ran a command. It stays quiet
while you work and shows only patterns with evidence across multiple sessions.

## What it does

- Finds frequently invoked commands and actions that already have a mapping.
- Proposes mappings for high-frequency actions that do not have one.
- Recognizes stable repeated action sequences and verbose native motions.
- Checks global, mode-specific, plugin, and loaded buffer-local mappings before
  proposing a key.
- Learns leader and prefix conventions from the effective mapping inventory.
- Lets you apply, regenerate, snooze, or exclude a recommendation.
- Tracks whether an accepted recommendation becomes part of normal work.

There are no tutorials, exercises, accounts, cloud services, or required
runtime dependencies.

## How it compares

| | KeyCoach | hardtime.nvim | which-key.nvim | precognition.nvim |
| --- | --- | --- | --- | --- |
| Watches what you actually use | ✅ across sessions | ✅ key repeats | ❌ | ❌ |
| Suggests new mappings for your habits | ✅ conflict-free | ❌ (blocks + hints) | ❌ (browses existing) | ❌ (shows motions live) |
| Reminds you of mappings you forgot | ✅ | ❌ | ❌ | ❌ |
| Persists evidence over time | ✅ 30-day window | ✅ local log | ❌ | ❌ |
| Works offline, fully local | ✅ | ✅ | ✅ | ✅ |
| Never blocks your keys | ✅ pull-first dashboard | ⚠️ blocks repeats | ✅ | ✅ |

## Privacy

All analysis happens locally. KeyCoach never persists inserted text, command or
search arguments, clipboard data, file contents, paths, or project names.
Nothing is ever sent anywhere — there is no account, no cloud, no telemetry
endpoint.

Exact keys are eligible for observation only in Normal, Visual, Select, and
Operator-pending modes. Content-bearing modes are reduced immediately to safe
action categories and counts. See [the product specification](docs/product-spec.md)
for the complete boundary.

Everything is stored in one folder, `stdpath("data")/keycoach/` (two JSON
files). `:KeyCoachClear` deletes all of it in one command; `:KeyCoachPause`
stops observation immediately.

## Requirements

- Neovim 0.10 or newer

KeyCoach uses public Neovim APIs and has no dependency on a specific
distribution or plugin manager.

## Installation

### lazy.nvim and LazyVim

```lua
{ "ActualLearner/keycoach.nvim" }
```

That is the whole setup. Tracking starts by default — what KeyCoach
observes is described in [Privacy](#privacy) below. `:KeyCoachPause`
stops it at any time, `:KeyCoachClear` deletes everything stored, and
`:checkhealth keycoach` verifies your setup.

### packer.nvim

```lua
use({ "ActualLearner/keycoach.nvim" })
```

### vim-plug

```vim
Plug 'ActualLearner/keycoach.nvim'
```

Pass options only if you want to override defaults (see Configuration).
Pass `enabled = false` to start disabled.

Accepted mappings are appended as readable `vim.keymap.set` statements to
the chosen file, and KeyCoach loads that file itself: an applied mapping is
active immediately and on every later start. You never wire the file into
your config by hand.

## Usage

| Command | Purpose |
| --- | --- |
| `:KeyCoach` | Open ranked recommendations |
| `:KeyCoachEnable` | Turn tracking on (clears a stored refusal) |
| `:KeyCoachPause` | Pause observation immediately |
| `:KeyCoachResume` | Resume observation |
| `:KeyCoachStatus` | Show tracking and recommendation status |
| `:KeyCoachMappings` | Open the selected mappings file |
| `:KeyCoachUndo [lhs]` | Comment out a KeyCoach-added mapping (default: the last one) |
| `:KeyCoachReport` | Weekly digest of observed actions, adopted mappings, exclusions |
| `:KeyCoachData` | Inspect, export, or manage local data |
| `:KeyCoachClear` | Delete locally stored observations (keeps consent) |

Run `:checkhealth keycoach` to verify your setup — data directory permissions, mappings
file writability, and consent status.

The dashboard is pull-first: KeyCoach does not interrupt active editing with
recommendation popups.

### Statusline

`require("keycoach").statusline()` returns a compact status string. For
lualine.nvim:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      { require("keycoach").statusline },
    },
  },
})
```

## Configuration

<details>
<summary>Full default options</summary>

```lua
require("keycoach").setup({
  mapping_file = vim.fn.stdpath("config") .. "/lua/keycoach_mappings.lua",
  enabled = nil,
  retention_days = 30,
  session_idle_minutes = 30,
})
```

</details>

```lua
require("keycoach").setup({
  -- Default suggestion; chosen during onboarding when omitted.
  mapping_file = vim.fn.stdpath("config") .. "/lua/keycoach_mappings.lua",

  -- `nil` tracks by default (honoring a stored refusal); false disables.
  enabled = nil,

  -- Detailed normalized observations expire after this many days.
  retention_days = 30,

  -- Consecutive inactivity that starts a new evidence session.
  session_idle_minutes = 30,
})
```

Accepted mappings are appended as readable `vim.keymap.set(...)` statements.
KeyCoach never rewrites or removes existing configuration.

## FAQ

**Is this a keylogger?**
No. KeyCoach counts what you press in normal-mode editing — it never records
insert-mode text, search or command arguments, clipboard contents, or file
contents, in that order and by design. Counts are aggregated per action; the
order and context of your typing are not stored.

**Does it send anything anywhere?**
No. There is no network code in the plugin. Everything lives in two JSON
files under `stdpath("data")/keycoach/`.

**How do I turn it off?**
`:KeyCoachPause` stops observation immediately (evidence is kept);
`enabled = false` in `setup()` disables it permanently;
`:KeyCoachClear` deletes everything already stored.

**Why did a recommendation disappear after I applied it?**
That is the adoption loop working: once you start using the new mapping
instead of the old way, the card retires itself. If you go back to the old
way, it can return.

**Where do applied mappings go?**
Into one readable Lua file you chose during setup (by default
`stdpath("config")/lua/keycoach_mappings.lua`), as plain
`vim.keymap.set(...)` lines. KeyCoach loads that file itself — no config
wiring needed. `:KeyCoachUndo` comments out the last one if you change
your mind.

## Data controls

Local state is stored beneath `stdpath("data")/keycoach/`. Use
`:KeyCoachClear` to remove it. Exclusions remain reversible in the dashboard.

## Development

StyLua is required for `make lint`.

```sh
make test
make check
make lint
```

Tests run headlessly in Neovim without a third-party test framework. The
recommendation engine is deterministic and exercised through portable fixture
shapes so later editor adapters can reproduce its behavior.

## Documentation

- [Product specification](docs/product-spec.md) — audience, product loop,
  capture boundary, and V1 scope
- [Recommendation engine design](docs/design/recommendation-engine.md) —
  engine interface, reliability rationale, and invariants
- [QA checklist](docs/qa-checklist.md) — the "done enough" bar for the
  v1.0.0 release
- [Architecture decision records](docs/adr/) — why observation is local-only,
  why Neovim comes first, why config writes are append-only, and why the
  engine is one atomic call
- [Roadmap](docs/roadmap.md) — deferred ideas and future platforms
- [Domain language](CONTEXT.md) — canonical terminology

## License

[MIT](LICENSE)
