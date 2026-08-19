# V1.0.0 QA checklist

This sharpens the "done enough" bar for tagging KeyCoach v1.0.0. Every row maps
to the [product specification](product-spec.md) and the destination in the
[Wayfinder map](https://github.com/ActualLearner/keycoach.nvim/issues/1).

Run the automated gates first; a red gate stops the release. Then walk the
manual checks in a real Neovim and record evidence on the release ticket
([issue #10](https://github.com/ActualLearner/keycoach.nvim/issues/10)).

## Automated gates

| Gate | Command | Requirement |
| --- | --- | --- |
| Headless suite | `make test` | Engine, store, capture, collector, inventory, appender, dashboard, help doc, and wired-plugin smoke specs all pass. |
| Cold load | `make check` | Test suite passes and a bare `require("keycoach")` on a clean runtimepath loads without error. |
| Format | `make lint` | StyLua 2.0.2 `--check .` is clean. |
| CI | workflow `ci.yml` | `make check` on Neovim `v0.10.4` and `stable`; `make lint` on Ubuntu. |

## Spec-derived verification

### Onboarding and consent

| Check | Automated evidence | Manual step |
| --- | --- | --- |
| Fresh install is inert and hints | `keycoach_spec` "runs onboarding…"; `smoke_spec` "installs fresh…" | Install from the README snippet; expect one notify: "KeyCoach is installed but not set up. Run :KeyCoach to begin." Statusline shows `KC setup`. |
| `enabled = true` is explicit consent | `keycoach_spec` pause/resume tests | `setup({ enabled = true })` starts tracking without the walkthrough. |
| Walkthrough persists nothing until consent | `onboarding.lua` flow (design `onboarding-ux.md`) | Abandon each of the three steps with `q`/`<Esc>`; data dir stays empty and the hint reappears next start. |
| Three-step walkthrough | `smoke_spec` onboarding path | `:KeyCoach` shows boundary → mappings file → consent. `y` starts tracking (`KC on` + notify); `q` leaves it inert. |

### Capture boundary

| Check | Automated evidence | Manual step |
| --- | --- | --- |
| Exact keys only in Normal/Visual/Select/Operator-pending | `capture_spec` exact-mode cases; `collector_spec` key capture | No persisted record ever contains typed text, command or search arguments, clipboard data, or paths. |
| Content-bearing modes reduce to counts | `capture_spec` aggregate-category cases; `collector_spec` content-bearing keys | Insert/search/command-line/terminal input persists only as `category:*_input` with no `lhs`. |
| Command identities without arguments | `collector_spec` command cases; `smoke_spec` command record | `:Telescope find_files` is recorded as `command:Telescope` only; `vim.cmd`/`:Ex <path>` never persist the argument. |
| Terminal and prompt buffers excluded | `collector_spec` "ignores … terminal command lines" | Command identities issued from terminal buffers are not recorded. |

### Four V1 recommendation types

| Check | Automated evidence | Manual step |
| --- | --- | --- |
| Existing Mapping for a frequent action | `engine_spec` existing-mapping cases (incl. canonical modes); `smoke_spec` "Existing Mapping already present" | Define `<leader>ex` for a command, run it 10+ times across 3+ sessions, `:KeyCoach` lists "Use existing mapping". |
| Mapping Candidate for an unmapped bindable action | `engine_spec` candidate cases; `smoke_spec` "recommends, applies, and retires" | Run an unmapped command repeatedly; `:KeyCoach` proposes a free `<leader>`-style key. |
| Stable sequence | `engine_spec` sequence case | Repeat a two-action sequence across sessions; a candidate is proposed for the pair. |
| Verbose native motion | `engine_spec` native-action case | Hammer `j` in runs; `:KeyCoach` suggests `{count}j`. |

Weak or ambiguous evidence must stay silent (`engine_spec` silence cases).

### Mapping application

| Check | Automated evidence | Manual step |
| --- | --- | --- |
| Candidate free in every observed context | `engine_spec` conflict cases; `appender_spec` | No proposed key collides with a global, mode, plugin, or loaded buffer-local mapping. |
| Live inventory recheck before apply | `keycoach_spec` "regenerates when its key is taken"; `appender_spec` stale-inventory | Take the key between listing and `<CR>`; the card regenerates instead of overwriting. |
| Append-only readable line | `smoke_spec` apply path; `appender_spec` | Applying appends one `vim.keymap.set("n", …)` statement and never rewrites existing lines. |

### Feedback: Snooze, Exclusion, Adoption

| Check | Automated evidence | Manual step |
| --- | --- | --- |
| Snooze lasts 30 days and needs materially stronger evidence | `engine_spec` snooze case | `o` → Snooze 30 days; the card hides and only resurfaces after the window with stronger recurrence. |
| Exclusion is permanent until restored | `engine_spec` exclude/restore case | `o` → Never suggest this; `:KeyCoachData` → Restore an exclusion brings it back. |
| Adoption is inferred, never asked | `engine_spec` adoption case | After applying, using the mapping in later sessions retires the card; continuing the long way resurfaces it. |
| Never re-propose a rejected key | `engine_spec` rejected-key case | `o` → Another key never proposes the rejected key again for that pattern. |

### Data and operation

| Check | Automated evidence | Manual step |
| --- | --- | --- |
| Local-only, deterministic, no telemetry | ADR 0001; `engine_spec` determinism | `stdpath("data")/keycoach/` holds everything; no network calls. |
| 30-day detail expiry keeps aggregates | `engine_spec` retention case | After the window, `details` prune while aggregate occurrences remain. |
| Inspect / export / delete | `keycoach_spec` data cases | `:KeyCoachData` inspect/export/delete round-trip; `:KeyCoachClear` keeps consent and the mappings file. |
| Statusline contract | `keycoach_spec` statusline cases | `KC off` / `KC setup` / `KC on` / `KC paused` / `KC <n>` reflect real state. |
| All commands registered | `keycoach_spec` command registration | `:KeyCoach`, `:KeyCoachEnable`, `:KeyCoachPause`, `:KeyCoachResume`, `:KeyCoachStatus`, `:KeyCoachMappings`, `:KeyCoachData`, `:KeyCoachClear` all work. |

### Distribution

| Check | Evidence |
| --- | --- |
| README install snippets resolve | `smoke_spec` cold-load path; repo is `ActualLearner/keycoach.nvim` |
| Zero required runtime dependencies | `init.lua` uses public Neovim APIs only |
| Vim help doc ships | `doc/keycoach.txt`, checked by `help_doc_spec` |
| MIT license | `LICENSE` |

## Release steps

1. Merge this QA branch with all automated gates green.
2. Confirm the manual checklist above passes on a fresh install and record
   evidence as a comment on issue #10.
3. Tag the merge commit `v1.0.0`.
4. Create a GitHub release from the tag summarizing the V1 scope, install
   snippet, and the spec sections delivered. Announcement and validation
   tuning stay out of scope per the map.

## Known limitations (deferred)

- Editor-action signals (undo/redo, cursor movement, selection changes) are
  supported by the capture schema but not yet collected by the Neovim adapter;
  the four V1 detectors do not depend on them.
- A command that errors (e.g. an `E492` typo) still counts toward its command
  identity; Neovim exposes no reliable post-execution success signal at
  `CmdlineLeave`, so a few bad invocations are counted as weak evidence.
- A legacy `:map x :X<CR>`-style mapping that itself opens a command line is
  recorded both as the mapping use and as the command identity. `<Cmd>`-style
  mappings (which the appender emits) do not double count.
- VS Code and classic Vim adapters, idle notifications, and detection
  fine-tuning remain on the [roadmap](roadmap.md).