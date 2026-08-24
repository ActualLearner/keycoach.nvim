# Competitive analysis: habit plugins and data-collecting tools

Research from August 2026. Sources: plugin READMEs and docs on GitHub,
vendor documentation, and community discussions. Two research passes: one
over the Neovim habit/efficiency category, one over developer tools that
collect usage data.

## The Neovim habit/efficiency category

| Plugin | Stars | Observes behavior? | Consent? | Default state |
| --- | --- | --- | --- | --- |
| hardtime.nvim | ~3.8k | Yes — key repeats, logs to a local file | No (log path disclosed in README) | On by default |
| which-key.nvim | ~7.3k | No | — | On by default |
| vim-be-good | ~4.5k | Optional local debug log | Off by default, disclosed | Explicit invocation |
| precognition.nvim | ~1.4k | No | — | Visible by default |
| hawtkeys.nvim | ~252 | No (static config analysis) | — | Explicit invocation |
| keymap-stats.nvim | ~1 | Yes — keymap execution counts, local | No (no wording at all) | Explicit invocation |

**Nobody in the category asks for consent.** Only hardtime even discloses
its local log file, and it does so casually ("Your log file is at ...") in
the Usage section. The category norm is: local observation, disclosed or
not, on by default, with pause/toggle commands one keystroke away.

## Data-collecting developer tools

| Tool | Local/remote | Consent model | Disclosure |
| --- | --- | --- | --- |
| WakaTime | Remote | Implicit opt-in (API key config) | Install page, FAQ |
| Code Time | Remote | Opt-in via account | Trust center |
| ActivityWatch | Local only | None needed — nothing transmits | "Local-first" is the headline feature |
| WhatPulse | Remote | Account opt-in + toggles | FAQ ("is it a keylogger?") |
| VS Code | Remote | Opt-out | Docs; VSCodium exists because of it |
| JetBrains | Remote | Opt-in (release builds) | Settings dialog |
| Homebrew | Remote | Opt-out with first-run notice | Docs |
| Neovim core | — | No telemetry; plugin telemetry actively suppressed by nvim-lspconfig | Community norm |

Patterns that matter:

1. **Local-only tools skip consent entirely** (ActivityWatch). Consent
   exists to protect against data *leaving* the machine. KeyCoach is
   local-only, which puts it in the ActivityWatch class, not the WakaTime
   class.
2. **The Neovim community is stricter than commercial editors.** When the
   Intelephense LSP shipped telemetry on by default, nvim-lspconfig
   suppressed it and framed the norm: "this should be opt-in and not
   opt-out". But that norm is about *remote transmission*, not local
   files — hardtime writes logs freely.
3. **"Local-first" framing is the strongest trust play** (ActivityWatch:
   "your data stays on your device — never uploaded"; "We, the developers,
   do not have access to your data").
4. **Aggregation wording defuses keylogger fears** (WhatPulse: "accumulated
   manner rather than logging the order").

## Decision: disclosure instead of a consent gate

KeyCoach's three-step consent walkthrough has no peer in the category and
is the largest install-friction item. The evidence supports replacing it:

- Every competitor observes locally without asking; the ones that succeed
  pair default-on with easy pause and clear disclosure.
- KeyCoach is local-only (ADR 0001): nothing ever transmits, so the
  threat consent protects against does not exist.
- The Neovim norm for local observation is disclosure + pause commands,
  which KeyCoach already has (`:KeyCoachPause`, `:KeyCoachClear`,
  `:KeyCoachData`).

New model: tracking starts on setup by default (`enabled = false` opts
out; a previously recorded consent refusal is still honored), with a
one-time disclosure notification stating what is observed, that nothing
leaves the machine, and how to pause. The three-step walkthrough and the
`KC setup` state are removed; the mappings file defaults to
`stdpath("config")/lua/keycoach_mappings.lua`.

## UX patterns worth stealing

1. **hardtime's aggregated habit report** (`:Hardtime report`) — we have
   this with `:KeyCoachReport`; its configurable-report UI is a reference.
2. **precognition's peek mode** — hints shown until the next cursor move;
   a low-noise pattern for any future ambient hints.
3. **which-key's collapsed-config README** — full default options inside a
   `<details>` block keeps the README scannable.
4. **hawtkeys' duplicate-keymap detection** (`:HawtkeysDupes`) — a cheap,
   useful addition to the report.
5. **vim-be-good's gamification** — timed drills; a possible future mode
   for practicing an applied mapping.
6. **hardtime's community hint registry** (GitHub Discussions) — pattern
   hints contributed by users.

## The gap we occupy

No plugin combines longitudinal usage analytics with personalized
coaching. hardtime reports hints fired but does not trend over sessions;
keymap-stats is nearly abandoned; hawtkeys analyzes config statically, not
behavior. "You ran `:Telescope find_files` 12 times across 3 sessions —
here is a conflict-free mapping, applied and verified" is an unoccupied
position. The trade-off we accept for it is being the only plugin in the
category that persists behavior data, which makes the local-only guarantee
and disclosure the load-bearing parts of the trust model.
