# Dashboard and Recommendation Menu UX

Resolves the "Design the dashboard and recommendation menu UX" wayfinder
ticket. Builds on the existing `dashboard.lua` floating-window shell
(centered, rounded border, `q`/`<Esc>` close, `r` refresh) rather than
replacing it.

## Layout

One floating window, list-style, cursorline enabled. One Recommendation
occupies two lines plus a blank separator — the existing render shape,
extended with a header keymap hint and per-kind verbs:

```
╭─────────────────────────────── KeyCoach ───────────────────────────────╮
│ KeyCoach                                     Tracking active           │
│                                                                        │
│ 1  Use existing mapping  <leader>ff                                    │
│    telescope.find_files · 42 uses across 6 sessions · ~120 keys saved  │
│                                                                        │
│ 2  Add mapping  <leader>gd                                             │
│    lsp.goto_definition · 18 uses across 4 sessions · ~54 keys saved    │
│                                                                        │
│ 3  Use native action  5j                                               │
│    repeated j motion · 11 runs across 3 sessions · ~33 keys saved      │
│                                                                        │
│ <CR> apply/got it · o options · r refresh · q close                    │
╰────────────────────────────────────────────────────────────────────────╯
```

An empty dashboard keeps the current "No recommendations yet" line and
adds one Comment-highlighted line about how evidence accrues ("KeyCoach
recommends only patterns seen across several sessions").

## Primary action — `<CR>` on a Recommendation

Per the spec: one primary apply action.

- **mapping_candidate** → confirmation echo, then apply:
  `Append  vim.keymap.set("n", "<leader>gd", ...)  to keycoach_mappings.lua? [y/n]`
  On `y`: live inventory recheck (spec), append via the appender, feedback
  `accepted` recorded, card leaves the list, notify shows the appended line.
  If the recheck finds the key taken, the card regenerates instead (same
  path as "another key").
- **existing_mapping / native_action** → nothing to apply; `<CR>` records
  `acknowledged` feedback and collapses the card ("Got it — watching for
  adoption."). The pattern retires automatically once adoption is
  observed, or resurfaces if the long way continues.

## Secondary menu — `o` (also `<Tab>`)

`vim.ui.select` on the highlighted Recommendation — honors the user's
picker plugin, zero extra UI code:

```
Recommendation 2: Add mapping <leader>gd
> Another key            (regenerates; never re-proposes a key rejected
                          for this Workflow Pattern)
  Snooze 30 days         (returns only with materially stronger evidence)
  Never suggest this     (Exclusion — reversible in :KeyCoachData)
  Why am I seeing this?  (echoes the evidence + detector in plain words)
```

"Another key" is present only on `mapping_candidate` cards.

## Data management — `:KeyCoachData`

The spec's inspect/export/delete surface, reachable as a command and from
the dashboard footer. A small floating menu via `vim.ui.select`:

- **Inspect** — opens a scratch buffer with pretty-printed store JSON
  (evidence aggregates, suppressions, accepted mappings — the user sees
  exactly what exists).
- **Export** — writes the checkpoint JSON to a user-chosen path
  (`vim.ui.input`, default `~/keycoach-export.json`).
- **Restore an exclusion** — `vim.ui.select` over current Exclusions;
  choosing one removes the suppression.
- **Delete everything** — `:KeyCoachClear` with a y/n confirm; consent
  and settings survive, evidence dies.

## Statusline

Unchanged contract from `init.lua`: `KC off` / `KC setup` / `KC on` /
`KC paused` / `KC <n>` where `n` is ready Recommendations. Documented in
the help doc with a lualine snippet.
