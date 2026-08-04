---
type: policy
title: Issue labels and project-board tracking
description: Every issue carries a type:* and priority:* label; a multi-phase initiative gets tracked on its own dedicated project board rather than folded into the repo's default backlog view.
tags: [policy, issues, labels, project-board, triage]
timestamp: 2026-08-04
---

# Issue labels and project-board tracking

**Every issue carries two labels**: a `type:*` (`type:bug`, `type:feature`, `type:chore`,
`type:epic`, `type:spike`, `type:docs`) and a `priority:*` (`priority:P0` through `priority:P3`).
This is what makes a backlog scannable instead of a flat list, and it is cheap to keep true:
setting the pair at triage time takes seconds, and skipping it lets the whole backlog rot back
into an undifferentiated list within a few dozen issues.

Point the repo's own issue-form templates (`.github/ISSUE_TEMPLATE/`), if it has any, at these
`type:*` labels directly rather than GitHub's legacy `bug`/`enhancement` defaults, so a
template-filed issue already carries a correct `type:*` on arrival. Where the volume of issues
justifies it, enforce the pair with a lightweight, non-blocking GitHub Action rather than trusting
habit — reference implementation:
[OCCTSwift#471](https://github.com/SecondMouseAU/OCCTSwift/pull/471) (a first-party
`actions/github-script` step that posts and updates a sticky comment naming any missing label,
including on blank issues that bypass the template dropdowns). Not every repo needs this wired up
immediately; the labels themselves are the mandatory part, the Action is a low-cost addition once
issue volume makes manual triage unreliable.

**A multi-phase initiative gets a dedicated project board, scoped to its own issues.** A refactor,
migration, or audit large enough to span several tracked sub-issues (an "epic" in the `type:epic`
sense) needs a GitHub Project with a `Status` field reflecting that initiative's real workflow
stages, not the generic Todo/In Progress/Done default — for example Backlog, In Progress, PR
Review, Code-Review, Ready, Done. Create it as its own project rather than repurposing an existing
ecosystem-wide board: a shared board's `Status` field is load-bearing for every other item already
on it, and replacing its options to fit one initiative breaks the view for everything else tracked
there. Add only the initiative's own issues, not the repo's whole backlog. Reference
implementation: [OCCTSwift #377](https://github.com/SecondMouseAU/OCCTSwift/issues/377) and its
project, [OCCTSwift Refactor (#377)](https://github.com/orgs/SecondMouseAU/projects/2).

**Keep the board's `Status` current where one exists — treat it as part of finishing the work, not
a separate chore.** Update `Status` at the same points the workflow already visits: starting work
on the issue moves the card to `In Progress`, opening a PR moves it to `PR Review`, a review
landing moves it to `Code-Review`. An agent picking up a board-tracked issue moves it to
`In Progress` itself at the start of that work, not after. For an initiative staged through its own
integration branch rather than merging straight to the default branch, a merged PR is `Code-Review`,
not `Done` — reserve `Done` for the point the initiative's branch itself reaches the default
branch, and don't wire the project's native "Item closed"/"PR merged" → `Done` automations for that
shape of initiative, since both fire on the wrong event. See the full **Issue tracking** section of
[OKF-STANDARD.md](https://github.com/SecondMouseAU/ecosystem/blob/main/OKF-STANDARD.md) for the
detailed rationale, incident history, and a GitHub platform quirk around `Linked pull requests` not
populating for non-default-branch PRs.

Ecosystem standard: see
[OKF-STANDARD.md](https://github.com/SecondMouseAU/ecosystem/blob/main/OKF-STANDARD.md).
