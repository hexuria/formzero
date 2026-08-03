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
- The Calendar view has one selected-year schedule list. It keeps due,
  overdue, paid, and in-progress rows together, with an action that opens the
  exact form period when an editor exists.
- Only an explicitly configured yearly Forms Set can contribute profile
  deadlines. An explicitly empty set shows no obligations, and an unconfigured
  year is unavailable in the profile calendar year picker.
- The calendar year picker lists configured years only, omits future years,
  and filters older configured years as the user types.
- Global form-picker changes never alter the profile calendar.
- Add to Calendar is a profile Calendar action; Forms Set management lives in
  Profile Settings → Tax Forms.

## Responsive and accessibility evidence

- Reference desktop: 1280 x 802.
- Fullscreen desktop: 1800 x 1129.
- Phone: 390 x 844.
- Calendar day and navigation targets are at least 44 x 44 points.
- The Global Dashboard uses two content lanes only when each lane remains at
  least 320 points wide; otherwise Calendar and Important News stack.
- The taxpayer dashboard keeps its calendar and selected-year schedule list in
  one readable flow; the calendar width is capped and the shell's phone,
  compact, and desktop paddings keep controls at the same 44-point targets.
- Loading, empty, error, selected, disabled, focus, and offline-cache states
  are part of parity, not optional polish.

## Completion gates

Generated `src/app.native` is never hand-edited. Source fragments are
regenerated twice and the second generation must be idempotent. Headless tests,
strict model-contract checks, layout sweeps, the automation build, exact-binary
desktop/phone screenshots, and process cleanup must all pass before parity is
reported complete.
