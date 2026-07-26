# KeyCoach Product Specification

## Purpose

KeyCoach helps experienced Neovim users discover useful mappings they already
have and add conflict-free mappings for actions they repeatedly perform the
long way.

The goal is real adoption by real users, not a demonstration project. This is
why distribution goes through the plugin managers users already have and why
the product must earn trust: local-only analysis, silence over noise, and no
edits to configuration the user did not accept.

## Initial audience

The initial user already works productively in Neovim, maintains a personal
configuration, and knows basic Vim editing. They do not need lessons; they use
only a narrow subset of available mappings or repeatedly invoke useful actions
without mappings.

## Product loop

1. After one-time consent, observe editor activity silently.
2. Normalize activity immediately and discard content-bearing input.
3. Accumulate evidence across Sessions.
4. Rank only high-confidence Insights.
5. Prefer an Existing Mapping or shorter native action.
6. Otherwise propose a conflict-free Mapping Candidate.
7. Let the user apply the candidate or open a compact menu to request another,
   Snooze it, or create an Exclusion.
8. Observe later work for Adoption and stop presenting learned Recommendations.

## V1 recommendation types

- A frequently used action has an Existing Mapping the user does not use.
- A frequently used bindable action has no mapping.
- A stable multi-action sequence recurs across Sessions.
- A verbose native editing pattern has a shorter Vim action.

Weak or ambiguous evidence produces no Recommendation.

## Capture boundary

KeyCoach may observe exact keys only in Normal, Visual, Select, and
Operator-pending modes. It records only counts and action categories in Insert,
Replace, Search, Command-line, Prompt, and Terminal modes. It may observe mouse
buttons, scrolling, mode changes, cursor movement, selections, edits, undo and
redo, and command identities without arguments.

KeyCoach never persists inserted text, command or search arguments, clipboard
data, file contents, paths, project names, or raw content-bearing input.

Terminal and prompt-like buffers, where secrets are most likely to be typed,
are excluded from observation beyond mode-level action counts.

## Onboarding

The first run walks through three steps before any observation starts:

1. Explain the capture boundary above and that all analysis stays local.
2. Ask for the Lua mappings file that accepted candidates may be appended to.
3. Ask for explicit consent to begin tracking.

Passing `enabled = true` in `setup()` is equivalent explicit consent and
skips the walkthrough. Without consent, KeyCoach stays fully inert.

## Interaction

- Tracking is enabled only after one-time consent.
- Tracking is otherwise passive and can be paused or resumed immediately.
- The dashboard is opened explicitly and shows ranked Recommendations.
- No popup interrupts active editing.
- A statusline function exposes tracking state and ready Recommendation count.
- A Recommendation presents one primary apply action and a secondary menu.
- Requesting another key regenerates from the remaining free candidates that
  match the user's conventions and never re-proposes a candidate previously
  rejected for the same Workflow Pattern.
- Snooze lasts 30 days and requires materially stronger new evidence before the
  same Workflow Pattern can reappear: recurrence since the Snooze must exceed
  the evidence that originally triggered the Recommendation, not merely meet
  the base threshold again.
- Exclusions are explicit, permanent until restored, and locally manageable.
- Adoption is inferred, never asked: an accepted Recommendation counts as
  adopted when later Sessions show the accepted mapping replacing the original
  Workflow Pattern, and the Recommendation then retires. If later Sessions
  show the pattern continuing without the mapping, the Recommendation remains
  available rather than being nagged.
- There are no tutorials, exercises, streaks, or gamification.

## Mapping application

- The user selects a Lua mappings file during setup.
- A candidate must be free across every observed applicable mapping context.
- The live mapping inventory is rechecked immediately before applying.
- Applying appends one readable `vim.keymap.set(...)` statement.
- KeyCoach never rewrites or removes configuration.

## Data and operation

- All analysis is deterministic and local in V1.
- Normalized detailed Observations expire after 30 days; compact aggregate
  evidence may remain.
- Users can inspect, export, and delete local state.
- There is no account, backend, sync, or product telemetry in V1.

## Platform sequence

1. Neovim 0.10+ as a pure Lua plugin with no required runtime dependency.
2. VS Code using its observable editor events. VS Code cannot expose raw
   keystrokes or arbitrary UI clicks, so that adapter observes commands,
   edits, selections, and navigation only, and recommends at command
   granularity.
3. Classic Vim where instrumentation permits useful evidence.

The domain records and golden behavior fixtures stay runtime-neutral even when
an editor adapter is platform-specific. Further platform ideas live in the
[roadmap](roadmap.md).

## Distribution

The project is public and MIT licensed. Neovim users install it directly from
GitHub with common plugin managers. Documentation and releases use free GitHub
facilities. Everything the project depends on to operate — hosting, CI,
distribution, and any future optional service — must fit free tiers.
