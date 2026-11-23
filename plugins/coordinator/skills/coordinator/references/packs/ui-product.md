# Pack: product with a user interface

Switch on in the profile for any unit whose changes a user sees in a browser or an app.

## Rule: UI is verified by using it

Unit tests and a green build do not show that a screen works. Each UI unit's gate has two
parts:

1. **Automated:** lint, type check, unit tests, and (when the project has it) a small
   end-to-end smoke over the main flow against mock or seeded data.
2. **Manual pass:** someone opens the changed screens and uses them. The profile says who
   (coordinator, QA, owner) and when (per PR, or once per release over everything merged
   since the last one).

A PR merged without its manual pass is noted `UNVERIFIED: browser` and goes on the
verification debt list in `ROADMAP.md`. Releasing by group and the safety ceiling in the profile keep that list
short enough to check in one sitting.

## Rule: a draft before the build

A new screen is approved by the owner as a draft before it is built for real (Semi Group owner
decision C-022, amended by C-023). The draft is real app code with mock data, so nothing is
redrawn later. The project's own standard (for Semi Group: `handbook/standards/ui-drafts.md`
in the group ledger) gives the route, fixtures, viewports and checks; this pack gives the
coordination around it.

- **When.** Every task issue of a UI unit carries `Draft: required` or `Draft: not needed`
  (`templates/task-issue.md`). Rule: a new screen or page, a layout change of an existing page,
  or a flow of several steps → `required`. Copy, bug, spacing or token fixes, design-system
  syncs and changes that follow an approved draft → `not needed`. The coordinator sets it in
  `ticket.md`; the owner can override it.
- **Phase 1, draft (agent).** The agent builds the screens on a route no menu links to (a
  `_draft` route) with typed mock fixtures, every state switchable, then sends the owner the
  screenshots with `SendUserFile` (three per screen: `<screen>-desktop.png`,
  `<screen>-ipad.png`, `<screen>-iphone.png`, plus key states) and reports to the coordinator
  by message. The FIRST line starts with `Draft ready:` (issue number), then the draft URL,
  the screenshot files per screen, what is mocked, and `Context: <k tokens>`. Then it waits,
  like after "PR ready". A draft PR, if one is opened, is never merged as it is.
- **Phase 2, owner review.** The owner answers in the agent's session or to the coordinator:
  approve, or change requests. Change requests go to the agent, which updates the draft, sends
  new screenshots and reports `Draft ready:` again. On approval the coordinator comments
  `Draft approved: <YYYY-MM-DD>` on the issue (with a link to the owner's words, or "in chat"),
  notes it in the unit's row of `COORDINATION.md`, and sends the agent
  `Next: build #<n> (same session)`. The coordinator never approves a draft itself.
- **Phase 3, build (same agent, same issue).** The build of the same issue is not a next issue:
  `Next: build #<n> (same session)` is an exception to the same-session rule (its cap, the
  "no session can be started" condition and the 3-in-a-row count do not apply; context
  thresholds do). The agent keeps the draft's components, replaces the fixtures with the real
  data, adds tests and navigation, deletes the `_draft` route and its fixtures in the same PR,
  and reports "PR ready" as usual. A change beyond the approved draft goes back to the owner
  as a new `Draft ready:`, never straight into the PR.
- **Waiting.** `Draft ready` is a waiting state like `PR ready`: the agent's turn may end
  after it is sent, and an agent-side Stop hook (issue #10) accepts it as the report for the
  turn.

## The manual pass

- Run from a clean checkout of the branch under test, in a sandbox: mock devices, seeded or
  fictional data, no real customers, no production credentials, nothing that can send, print,
  charge or switch hardware.
- For each changed flow: the normal path, an empty state, an error state, and a narrow
  (phone) viewport.
- Check the browser console for errors.
- Record what was checked and what was not, in the PR or the release notes.

## PR requirements

- The PR body carries a short checklist of what to click, written by the author.
- New or changed user-facing text exists in every language the product ships.
- The project's design-system and lint rules pass.

## Release notes for the owner

When the owner releases the unit: what changed in plain words, three to six steps to try per
flow, what was verified and how, what is still `UNVERIFIED` and why (for example "needs the
real device", "needs an app we do not have on this machine").

## Checklist (adds to the core checklist)

- The issue says `Draft: required` → the PR links the owner's approval (the issue's
  `Draft approved: <date>` comment) and contains no `_draft` route or draft fixtures. No
  approval → send it back; the build does not merge on an unapproved draft.
- The change was opened in a browser, or is marked `UNVERIFIED: browser`.
- Empty, loading and error states exist.
- Narrow viewport is usable or deliberately read-only.
- No console errors on the changed screens.
- Text is in all shipped languages; no hard-coded colours or one-off components where the
  design system has one.
