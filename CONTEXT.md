# Workflow Coaching

Workflow Coaching observes how an experienced editor user works and identifies
repeated opportunities to use a shorter existing action or create a useful
mapping.

## Language

**Action**:
A meaningful editor operation, regardless of whether it was triggered by keys,
a command, or the mouse.
_Avoid_: Event, input

**Observation**:
A privacy-preserving record that an action occurred in a relevant editor
context.
_Avoid_: Keystroke log, telemetry event

**Session**:
A period of editor activity used to distinguish a recurring habit from a
one-off action. In the Neovim adapter, a Session begins at plugin startup and
rolls over after a 30-minute gap with no Observations; Session numbers are
allocated from the checkpoint and strictly increase.
_Avoid_: Recording

**Workflow Pattern**:
A recurring action or sequence of actions with enough evidence to evaluate as
a habit.
_Avoid_: Macro, user intent

**Insight**:
Evidence that a Workflow Pattern can be completed with less effort.
_Avoid_: Alert, lesson

**Recommendation**:
An actionable response to an Insight: use an Existing Mapping, use a shorter
native action, or add a Mapping Candidate.
_Avoid_: Exercise, tutorial, tip

**Existing Mapping**:
A mapping already effective in the relevant editor context.
_Avoid_: Generated mapping, default key

**Mapping Candidate**:
A proposed mapping that is free in every context where it would apply and
matches the user's established mapping conventions.
_Avoid_: Existing Mapping, random keybind

**Adoption**:
Evidence that the user began using an accepted Recommendation in normal work.
_Avoid_: Completion, lesson progress

**Snooze**:
A temporary suppression of a Recommendation until time and stronger evidence
make it relevant again.
_Avoid_: Dismissal, rejection

**Exclusion**:
An explicit, reversible instruction never to recommend a particular Workflow
Pattern.
_Avoid_: Snooze
