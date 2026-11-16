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
verification debt list in `ROADMAP.md`. The integration limit in the profile keeps that list
short enough to check in one sitting.

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

- The change was opened in a browser, or is marked `UNVERIFIED: browser`.
- Empty, loading and error states exist.
- Narrow viewport is usable or deliberately read-only.
- No console errors on the changed screens.
- Text is in all shipped languages; no hard-coded colours or one-off components where the
  design system has one.
