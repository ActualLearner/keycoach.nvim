# Onboarding Walkthrough UX

Resolves the "Design the onboarding walkthrough UX" wayfinder ticket.

## Trigger

Onboarding never interrupts editing. When `setup()` runs without
`enabled = true` and no consent record exists, KeyCoach stays inert except
for a single `vim.notify` hint after startup:

    KeyCoach is installed but not set up. Run :KeyCoach to begin.

The walkthrough itself runs only when the user invokes `:KeyCoach` (or
`:KeyCoachEnable`) while consent is missing. `enabled = true` in `setup()`
is equivalent explicit consent (product spec) and skips all of this.

## Flow

Three steps in one floating window, same visual shell as the dashboard
(rounded border, centered, minimal style). Every step can quit with `q` or
`<Esc>`; nothing is persisted until the final consent, so an abandoned
walkthrough restarts cleanly from step 1.

### Step 1 — capture boundary

```
╭──────────────────────── KeyCoach Setup (1/3) ────────────────────────╮
│                                                                      │
│  KeyCoach observes how you work and recommends mappings.             │
│                                                                      │
│  What is observed                                                    │
│    • Exact keys in Normal, Visual, Select, Operator-pending modes    │
│    • Counts and categories only in Insert/Replace/Search/Cmdline     │
│    • Mouse buttons, scrolling, mode changes, command identities      │
│                                                                      │
│  Never stored                                                        │
│    • Inserted text, search or command arguments, clipboard data      │
│    • File contents, paths, project names                             │
│    • Anything typed in terminal or prompt buffers                    │
│                                                                      │
│  All analysis happens on this machine. No account, no telemetry.     │
│                                                                      │
│  <CR> continue    q quit                                             │
╰──────────────────────────────────────────────────────────────────────╯
```

### Step 2 — mappings file

Accepted Mapping Candidates are appended (append-only, ADR 0003) to one
Lua file the user picks. The step pre-fills the conventional default and
uses `vim.ui.input` so pickers like dressing.nvim/snacks are honored:

```
╭──────────────────────── KeyCoach Setup (2/3) ────────────────────────╮
│                                                                      │
│  When you accept a recommendation, KeyCoach appends one readable      │
│  vim.keymap.set(...) line to a Lua file you own. It never rewrites   │
│  or removes anything in it.                                          │
│                                                                      │
│  <CR> choose file    q quit                                          │
╰──────────────────────────────────────────────────────────────────────╯

  Mappings file: ~/.config/nvim/lua/keycoach_mappings.lua▌
```

If `setup({ mapping_file = ... })` was provided, the step shows that path
for confirmation instead of asking. The file does not need to exist; its
directory is created on first append. A reminder line tells the user to
`require("keycoach_mappings")` (or equivalent) from their config — also
echoed after the first successful apply.

### Step 3 — consent

```
╭──────────────────────── KeyCoach Setup (3/3) ────────────────────────╮
│                                                                      │
│  Ready to start.                                                     │
│                                                                      │
│    Observe:   this Neovim, within the boundary from step 1           │
│    Analyze:   locally, during idle moments                           │
│    Store:     ~/.local/share/nvim/keycoach/  (30-day detail expiry)  │
│    Suggest:   only in :KeyCoach — never as a popup                   │
│                                                                      │
│    Pause any time:      :KeyCoachPause                               │
│    Delete everything:   :KeyCoachClear                               │
│                                                                      │
│  y start tracking    q not now                                       │
╰──────────────────────────────────────────────────────────────────────╯
```

`y` writes the consent record and starts the collector immediately; a
statusline transition to `KC on` plus a single notify ("KeyCoach is
tracking. Open :KeyCoach any time.") confirms it. `q` leaves KeyCoach
inert.

## Persistence

Consent and the mappings-file path live in
`stdpath("data") .. "/keycoach/settings.json"`, separate from the engine
checkpoint (`checkpoint.json` beside it): settings are user decisions,
the checkpoint is evidence — `:KeyCoachClear` deletes evidence without
revoking consent. Setting `enabled = false` in `setup()` disables
tracking regardless of the consent record.
