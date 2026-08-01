# Legacy dashboard parity contract

This contract separates the two calendar projections implemented by the
desktop application. Both projections consume the same canonical rules,
SQLite deadline overrides, and non-working-day policy.

## Global Dashboard

- The Global Dashboard is never scoped by the selected taxpayer.
- Its form picker starts with every supported form selected and remains
  session-only. It must not be persisted into a tax profile.
- Zero, one, and multiple selections filter both calendar markers and the
  deadline list from the same selection state.
- A calendar day toggles an exact-date filter. Selecting it again returns to
  the whole visible month.
- Global month navigation does not change the taxpayer dashboard month or its
  Forms Set.
- Important News loads the last SQLite cache immediately and refreshes through
  one bounded network effect. A failed refresh retains the last good cache.

## Taxpayer Dashboard

- The selected tax profile's effective Forms Set is the only form scope.
- The Calendar view contains Upcoming Deadlines, Action Required, and Overdue.
- An unconfigured Forms Set uses the catalog fallback; an explicitly empty
  Forms Set intentionally shows no obligations.
- Global form-picker changes never alter these three columns.
- Calendar and Profile Settings actions stay on the taxpayer header (inside
  the compact wrench menu on phones); they are not duplicated in the global
  dashboard.

## Responsive and accessibility evidence

- Reference desktop: 1280 x 802.
- Fullscreen desktop: 1800 x 1129.
- Phone: 390 x 844.
- Calendar day and navigation targets are at least 44 x 44 points.
- The Global Dashboard uses two content lanes only when each lane remains at
  least 320 points wide; otherwise Calendar and Important News stack.
- The taxpayer dashboard uses three columns only while the available content
  width can carry them without clipping; otherwise they stack.
- Loading, empty, error, selected, disabled, focus, and offline-cache states
  are part of parity, not optional polish.

## Completion gates

Generated `src/app.native` is never hand-edited. Source fragments are
regenerated twice and the second generation must be idempotent. Headless tests,
strict model-contract checks, layout sweeps, the automation build, exact-binary
desktop/phone screenshots, and process cleanup must all pass before parity is
reported complete.
