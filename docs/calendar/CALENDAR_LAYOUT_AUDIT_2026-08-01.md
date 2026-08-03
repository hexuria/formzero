# Calendar and profile layout audit

> Superseded by the 2026-08-04 yearly Forms Set/calendar consolidation. The
> historical screenshots and measurements below document the earlier
> three-lane taxpayer layout; the current UI uses a single selected-year
> deadline list, a configured-year picker, and puts Forms Set management in
> Profile Settings → Tax Forms.

Date: 2026-08-01  
App under test: `/Volumes/goldcoders/Projects/ebirforms.0/zig-out/eBIRForms Verify.app`  
Test data: isolated temporary `EBIRFORMS_DATA_DIR`; no user profile data was used.

## Outcome

The planned calendar and profile layout remediation is implemented and live
verified. The global dashboard remains global, its form multi-select filters
both deadline rows and calendar markers, and the taxpayer dashboard scopes its
calendar to the selected profile's Forms Set. The wide taxpayer dashboard now
renders the requested Upcoming / Action Required / Overdue lanes, while compact
widths use bounded two-column or stacked fallbacks.

Deadline markers now use one shared current-date rule in both calendars:
overdue is red, due today or tomorrow is orange (the date-only approximation of
24 hours), due in two through seven days is green, and later deadlines use the
theme's normal text color. A repeating clock refresh prevents the classification
from becoming stale after midnight. Calendar-cell accessibility labels also
include the deadline count and status, so color is not the only signal.

## Final implementation evidence

| View | Captured result | Verified behavior |
| --- | --- | --- |
| Global dashboard, fullscreen | [Screenshot](screenshots/2026-08-01/result-10-calendar-marker-colors-wide.png) | Green Aug 5 marker and normal later markers; compact calendar and deadlines remain beside Important News. |
| Global dashboard, previous month | [Screenshot](screenshots/2026-08-01/result-11-calendar-marker-overdue-wide.png) | Past July markers render red. |
| Taxpayer dashboard, fullscreen | [Screenshot](screenshots/2026-08-01/result-12-taxpayer-marker-colors-wide.png) | The same green/normal rule appears in the profile-scoped calendar, with all three lanes visible. |
| Global form picker | [Screenshot](screenshots/2026-08-01/result-02-global-form-picker.png) | Search and bulk actions stay pinned; the options list scrolls; all/none/one/many selections update markers and rows. |
| Profile settings, phone 390px | [Screenshot](screenshots/2026-08-01/result-07-profile-settings-phone-390.png) | No brand logo in the top bar; one chevron/title header, three tabs, visible labels, flat fields, and one subject-kind control. |
| Taxpayer actions, phone 390px | [Screenshot](screenshots/2026-08-01/result-06-taxpayer-actions-phone-390.png) | Circular wrench opens 44px Profile Settings and Add to Calendar actions. |
| Global dashboard, compact 700px | [Screenshot](screenshots/2026-08-01/result-08-global-dashboard-compact-700.png) | Calendar header stacks cleanly and the picker fills its lane. |
| Taxpayer dashboard, compact 700px | [Screenshot](screenshots/2026-08-01/result-09-taxpayer-dashboard-compact-700.png) | Calendar is capped at 500px and all three semantic sections remain reachable by scrolling. |

The final fullscreen Native snapshot was 1800x1098 on Aerospace workspace 5.
It reported `ready=true`, `gpu_status=ready`, and `dispatch_errors=0`.
Accessibility inspection identified `Show 1 deadline for day 5: due within
seven days` and later deadlines as `due later`. The fixture had no deadline due
today or tomorrow; orange behavior is therefore covered by the model boundary
tests rather than fabricated screenshot data.

Final automated gates:

- Native SDK tests: 863/863 passed.
- Strict markup/model-contract check: passed for all 27 markup files.
- Native doctor: passed for the macOS target.
- Tax catalog: verified 51 codes, 10 editors, 41 calendar-only forms, 299
  Native inputs, and 72 profile targets.
- ReleaseFast build and `git diff --check`: passed.

## Evidence matrix

| View | Captured result | Main observation |
| --- | --- | --- |
| Default desktop, 1225x800 | [Screenshot](screenshots/2026-08-01/issue-01-default-desktop-stacked.png) | The profile lanes stack and the calendar stretches across 881px. |
| Fullscreen, 1920x1080 | [Screenshot](screenshots/2026-08-01/reference-wide-three-column.png) | The requested three-lane structure is present. |
| Profile editor, 390x844 | [Screenshot](screenshots/2026-08-01/issue-02-mobile-profile-density.png) | Values have no persistent visual labels and subject type consumes seven rows. |
| Global form picker, 1920x1080 | [Screenshot](screenshots/2026-08-01/issue-03-form-picker-fixed-height.png) | One filtered option still leaves a 420px popup with a large blank area. |
| Profile actions, 390x844 | [Screenshot](screenshots/2026-08-01/issue-04-mobile-action-popover.png) | The wrench is correct, but its menu rows are only 32px high. |
| Compact global dashboard, 700x900 | [Screenshot](screenshots/2026-08-01/issue-05-compact-calendar-height.png) | The calendar dominates the viewport and pushes news far below the fold. |

## Baseline findings and implemented remedies

### P1 - The desktop breakpoint reverses available space and loses the lanes

At 1225px, the expanded 280px sidebar and 64px page gutters leave 881px of
dashboard content. `dashboardThreeColumnLayout` requires 974px, so all three
lanes become one vertical stack. The Upcoming calendar then stretches across
the entire content width. See `src/main.zig:641` and
`src/pages/taxpayer-dashboard.native:336`.

The transition is non-monotonic: at 1099px the 72px rail leaves about 979px of
content and permits three lanes, but at 1100px the 280px sidebar appears,
content drops to about 756px, and the dashboard collapses. A wider window must
never produce a narrower effective dashboard.

Recommended fix:

1. Keep the 72px sidebar rail until available dashboard content can sustain the
   expanded sidebar, approximately 1320-1400px; keep the full profile list as an
   overlay. At 1225px this yields about 1089px of content, enough for three
   usable lanes with 44px calendar targets.
2. Add an explicit medium fallback if the rail is not desired: Upcoming in a
   360-400px left lane, with Action Required and Overdue stacked in the right
   lane. Do not stretch the compact calendar across the full page.
3. Keep the current stacked natural-height layout only below the compact
   breakpoint.
4. Add boundary tests at 767/768, 1099/1100, 1225, 1320, and 1920px. Effective
   dashboard width and lane count must be monotonic as the window grows.

Acceptance criteria:

- The default 1225x800 window shows all three semantic lanes without a
  full-width calendar.
- Every calendar day remains at least 44x44 on touch layouts.
- The full taxpayer list is still reachable in one action.

The calendar itself also needs an aspect-ratio rule. Its cells are always 44px
high while their widths grow to roughly 125px in the default stacked view.
Derive `profileCalendarDayHeight` from the actual lane width, clamp it to
44-72px, and cap the stacked calendar near 480-500px instead of rendering a
flattened full-width grid.

### P1 - Mobile profile fields are dense and become visually unlabeled

The screen adds 16px page padding and another card inset, reducing the usable
field width. More importantly, Native's `label` attribute supplies accessible
semantics but is not a persistent visible field label in the rendered screen;
once a value replaces the placeholder, `123-456-789-000` and `040` have no
visible TIN/RDO labels. Seven full-width subject-kind buttons then consume most
of the first viewport. See `src/pages/profile-setup.native:43` and
`src/pages/profile-setup.native:86`.

Recommended fix:

1. Create a reusable field wrapper that renders a visible label plus the input;
   retain the native `label` for accessibility.
2. On phones, remove card chrome and its second horizontal inset. Use section
   headings and separators inside the page's single 16px gutter.
3. Replace the seven mobile subject-kind buttons with one 44px native select.
   Desktop can retain a wrapped radio/button group.
4. Keep Tax Profile / COR / Email Settings as the existing tabs.

Acceptance criteria:

- Every populated field remains identifiable without relying on a placeholder.
- Phone content uses one 16px page gutter, not nested card gutters.
- Subject kind takes one control row on phone.

### P1 - Multi-select popup has fixed empty height and no useful option viewport

The reusable combobox hard-codes `height="420"`. With one search match it
still displays 420px of menu, while the unfiltered 54-option list extends past
the visible menu bounds and relies too heavily on search. See
`src/components/multi-select-combobox.native:25`.

Recommended fix:

1. Derive menu height from the visible row count and clamp it between the
   header/control height and 420px.
2. Put option rows in an actual scrolling region with the search field and bulk
   actions pinned above it.
3. Use 44px rows on phone/compact and 32-36px rows on pointer desktop.
4. Let the trigger and popup fill the available content width on phone instead
   of retaining the fixed 240px width.

Acceptance criteria:

- One match produces a compact popup with no blank lower panel.
- Any of the 54 forms can be reached by scrolling or search.
- All / none / one / many selection continues to filter both markers and rows.

### P2 - Global calendar and news density are too loose

On a 1920px window the global calendar lane is about 692px wide and its day
height can grow to 96px. The deadline heading reaches the bottom edge and news
cards show fewer stories than the legacy dashboard. On a 700px compact window,
the stacked calendar still permits 72px days and pushes Important News below
roughly 1470px. See `src/main.zig:650` and `src/main.zig:667`.

Recommended fix:

1. Cap the desktop calendar lane at about 520-560px and let news consume the
   remaining width.
2. Cap two-column desktop day rows at 56-64px and stacked compact rows at
   52-56px, while preserving the 44px minimum.
3. Reduce news-card vertical rhythm to 12-16px padding, a one-line title, and a
   two-line summary target.
4. Require the first deadline card, not only its heading, to be visible at
   1920x1080.

At narrower two-column widths, also stack the Compliance Calendar label above
the picker whenever its lane is below about 400px. The current row combines a
fixed 240px picker, a 12px gap, and the heading, so the heading can wrap or clip.

### P2 - Empty lanes do not read as finished surfaces

In the wide three-column screenshot, Upcoming has strong card boundaries while
Action Required and Overdue appear to float in open whitespace.

Recommended fix:

- Give all three lanes a consistent first surface.
- Use compact 140-180px empty-state cards; do not stretch empty cards to the
  calendar height.
- Keep the three headings and their first surfaces aligned.

### P2 - Compact action menu misses touch and icon targets

The circular 44x44 wrench matches the requested interaction, but the two menu
rows render at 32px and Add to Calendar uses a clock. See
`src/pages/taxpayer-dashboard.native:386`.

Recommended fix:

- Make compact menu rows at least 44px high.
- Use the calendar icon for Add to Calendar.
- Preserve outside-click, Escape, navigation, and action dismissal.
- If the anchored menu continues to obscure metadata, use a small native
  action sheet while retaining the wrench trigger.

Apply the same 44px constrained-height rule to the global picker trigger,
Refresh, dashboard tabs, profile tabs, and tax-calendar tabs. Current `sm` and
default controls render around 32-40px.

### P2 - A profile appears selected on the global dashboard

The global dashboard correctly ignores profile Forms Sets, but the sidebar can
still render the last profile with selected styling. That visually contradicts
the page's global scope. The styling comes directly from `profile.active` in
`src/components/shell.native:1` and `src/components/shell.native:281`.

Recommended fix:

- Separate loaded profile context from visual navigation selection.
- Highlight a profile only on taxpayer-scoped pages; show no selected profile
  on Global Dashboard and Tax Calendars.

### P3 - Small consistency defects

- Format `1 deadline`, not `1 deadlines`.
- Increase deadline markers to a visible 5-6px dot or a compact count for
  multiple deadlines.
- Keep the existing date tile/divider hierarchy on every deadline row.
- Preserve the current mobile behavior: no brand logo in the top bar, one
  chevron/title header, profile tabs, and the circular wrench.

### P3 - Tax Calendar repeats too much chrome on compact screens

The mobile shell already supplies the `Tax Calendars` title, but the page still
adds `Tax Calendar Explorer`, Refresh, section tabs, year navigation, a month
heading, and month navigation before the first deadline. Suppress the content
title on constrained layouts, combine Refresh with the tab/toolbar area, and
collapse year/month controls into one compact period toolbar.

### P3 - Very short windows can overflow the sidebar chrome

The manifest allows a 500px minimum height, while the fixed expanded sidebar
header and dock consume roughly 522px before useful scrolling. Put the dock in
the short-height scroll region or add a height-aware compact sidebar mode.

## Verified non-issues

- The mobile footer does not cover the final content. The scroll viewport ends
  at y=786, the footer begins at y=786, and the fully scrolled Overdue body ends
  at y=768.
- The wide taxpayer dashboard already renders three lanes.
- The phone lane-overlap defect found during this audit was corrected: stacked
  lanes now use natural height instead of sharing equal grow height.
- The duplicate Global Dashboard content title on phone was removed; the shell
  title is now the only page title.

## Recommended execution order

1. Mobile visible labels, single-gutter sections, and subject-kind select.
2. Responsive taxpayer lane mode and default-window sidebar rail behavior.
3. Dynamic/scrolling multi-select popup.
4. Calendar/news density and consistent empty-lane surfaces.
5. Touch-row, selection-highlight, marker, icon, and count-polish pass.
6. Re-run 390x844, 700x900, 1225x800, and 1920x1080 visual snapshots plus the
   existing Native SDK test/check/build gates.
