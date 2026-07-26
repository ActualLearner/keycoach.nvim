# Issue tracker: GitHub

Issues and PRDs live as GitHub issues. Use the `gh` CLI for operations and
infer the repository from its Git remote.

## Conventions

- Create: `gh issue create --title "..." --body "..."`
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open`
- Comment: `gh issue comment <number> --body "..."`
- Label: `gh issue edit <number> --add-label "..."`
- Close: `gh issue close <number> --comment "..."`

Pull requests as a triage surface: no.

When a skill says "publish to the issue tracker", create a GitHub issue.
When it says "fetch the relevant ticket", read that GitHub issue.

Wayfinder maps and child work items are represented by linked GitHub issues,
using `wayfinder:*` labels and native dependencies where available.
