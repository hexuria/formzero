# Profile Calendar Remediation Execution Plan

Date: 2026-08-04  
Baseline: `main` at `e84e300` (`Consolidate yearly tax forms and profile calendar`)  
Scope: implementation plan only; do not edit `src/app.native` directly

> **Status: PAUSED on 2026-08-04.** Do not execute this plan until the
> taxpayer-profile, yearly setup, branch, and COR information architecture has
> been reviewed. The active design handoff is
> `docs/tax-profile/CLAUDE_FABLE_5_TAXPAYER_SETUP_UX_PROMPT_2026-08-04.md`.

## 1. Required outcome

Implement this exact profile-page contract:

1. The taxpayer page has three primary tabs in this order:
   `Calendar`, `Tax Form Library`, `Profile Settings`.
2. Remove both desktop and constrained-layout `Profile Settings` header buttons.
3. The Calendar tab restores the three work areas that existed before
   `e84e300`:
   `Upcoming Deadlines`, `Action Required`, and `Overdue`.
4. The Calendar tab adds a searchable multi-select form filter. Its options
   are only the forms active in the selected taxpayer's persisted Forms Set
   for the selected tax year.
5. The form filter supports individual toggle, filtered Select All, Deselect
   All, and case-insensitive search by form code or title.
6. The closed form-filter label is exactly `0 forms`, `1 form`, or `N forms`.
   Do not use the word `selected` on the profile calendar. Do not change the
   Global Dashboard's existing label in this patch.
7. Remove the top toolbar deadline-count badge such as `0 deadlines`.
   Keep the Action Required and Overdue work-item counts because they describe
   those queues, not the form-filter selection.
8. Restore the eBIRForms sidebar logo and all footer logos in a packaged macOS
   launch, including a launch whose initial working directory is `/`.
9. Preserve the already-fixed centered calendar dots.
10. A calendar day click may filter only the Upcoming list. It must never
    decide whether a row is overdue and must not change the Action Required or
    Overdue queues.

Do not revert `e84e300` wholesale. It also contains required yearly Forms Set,
year picker, dialog, calendar-export, and Tax Calendar cleanup work.

## 2. Responsive toolbar contract

Use the existing viewport predicates; do not introduce a device-name or OS
check.

### Desktop (`desktopLayout`)

Use one toolbar row when it fits:

`dynamic deadline title | form multi-select | year picker | Add to Calendar`

The Add to Calendar control may retain its text label on desktop.

### Compact/tablet (`constrainedLayout` and not `phoneLayout`)

Use two rows:

1. dynamic deadline title by itself;
2. form multi-select and year picker as equal growing controls, followed by a
   44 x 44 icon-only Add to Calendar button.

### Phone (`phoneLayout`)

Use the three-row version so neither picker is squeezed:

1. dynamic deadline title by itself;
2. year picker growing to the available width, plus a 44 x 44 icon-only Add
   to Calendar button;
3. form multi-select at full width.

The icon-only button must keep the accessible label `Add to Calendar`. Do not
render the year and form picker as two half-width controls on a phone: after
padding, gaps, and the icon button, each control becomes too narrow.

## 3. Current-code findings

| Finding | Source anchor | Consequence |
| --- | --- | --- |
| The Calendar was flattened into one full-width schedule | `src/pages/taxpayer-dashboard.native`, template `taxpayer-calendar-section` | Restore lane templates and responsive composition. |
| The responsive lane calculations still exist | `src/main.zig`, `TaxpayerDashboardLaneMode`, `dashboardThreeColumnLayout`, `dashboardTwoColumnLayout`, `profileCalendarLaneWidth` | Reuse them; do not add a second breakpoint system. |
| The old lane code is available in the parent of `e84e300` | `git show e84e300^:src/pages/taxpayer-dashboard.native` and matching `src/main.zig` | Use as a reference only; correct its selected-day coupling and year checks. |
| The current reusable view is wired to global property and message names | `src/components/multi-select-combobox.native` | Add a profile adapter/template; pasting the current template would mutate Global Dashboard state. |
| Reusable selection behavior already exists | `src/components/multi_select.zig` | Use this state core instead of writing another bitset/query implementation. |
| Per-year active forms are already cached | `src/tax_profile/ui_state.zig`, `calendarFormCodes`, `formAvailable`, `calendarFormSetAvailable` | Derive profile-filter options from this authoritative Forms Set. |
| `DashboardSection` has only `calendar` and `forms` | `src/main.zig` | Add an inline `profile_settings` dashboard section for an existing taxpayer. |
| Profile settings already has reusable inner content | `src/pages/profile-setup.native`, template `profile-setup-content` | Mount this content in the new dashboard tab; keep standalone setup for new-profile and form-completion flows. |
| All packaged PNGs are present | `zig-out/package/ebirforms-zero.app/Contents/Resources/assets` | The missing logo is not a packaging-copy defect. |
| The running packaged process had working directory `/` | observed with `lsof -a -p <pid> -d cwd` | Relative image loads fail under Finder/open launch. |
| Boot images use relative paths | `src/main.zig`, `registerBootImages` | Resolve the packaged Resources directory before image effects run. |
| Native SDK 0.6.1 image effects open from `std.Io.Dir.cwd()` | `node_modules/@native-sdk/cli/src/runtime/effects.zig`, `runImageLoad` | Fix this in app bootstrap; do not patch generated or installed SDK files. |

## 4. State and filtering contract

Keep these three concepts separate:

| Concept | Authority | May this patch mutate it? |
| --- | --- | --- |
| Active form membership for a taxpayer/year | persisted yearly Forms Set | No, except through the existing Profile Settings > Tax Forms editor. |
| Forms currently visible on the profile Calendar | new session-owned multi-select state | Yes, through the new Calendar filter. |
| Forms exported by Add to Calendar | persisted yearly Forms Set and existing adjacent-tax-year rule | No behavior change in this patch. |

The new multi-select is a view filter. Checking or unchecking a Calendar form
must not activate/deactivate a form, write SQLite, or alter the `.ics` export.
Do not wire `taxProfiles.persistCalendarFormSelection`; that API is
profile-wide and cannot truthfully represent a per-year Forms Set. Leave the
existing persistence API/schema untouched in this patch.

### Required model state

In `src/main.zig`:

1. Define a profile-calendar selection state using
   `multi_select.State(form_catalog.registry_count, 96)`.
2. Add it to `Model` as a separate field from `globalDashboard.forms`.
3. Add it to `Model.view_unbound` because views consume derived adapters, not
   the raw state.
4. Add one reconciliation helper that:
   - closes the picker and clears its query;
   - sets an index to selected only when the catalog form is active for the
     selected profile and selected profile-calendar year;
   - forces inactive indices to false.
5. Call that helper after:
   - taxpayer selection;
   - profile-calendar year selection;
   - successful Forms Set create/save/edit;
   - selected-profile Forms Set refresh;
   - profile deletion or clearing selection.
6. Do not call it on month navigation or day selection. Those actions must
   preserve the user's form filter.

### Required derived adapters

Add profile-specific adapters; do not reuse the `globalCalendar*` names:

- picker open/disabled/query values;
- selected active-form count and pluralized `forms` label;
- menu/option heights and widths for each responsive toolbar branch;
- visible option rows;
- any-selected and all-filtered-selected flags;
- an active-and-selected deadline inclusion predicate.

Each option row uses a stable catalog index and exposes both code and title.
Display `CODE - Title` (or an equivalent single readable line), and match the
query against both values with `multi_select.containsAsciiInsensitive`.

For aliases such as `1604C`/`1604F` represented by catalog selection
`1604CF`, keep using `formCodesEquivalent` and the existing alias rule. A
deadline is visible only when its yearly Forms Set includes the canonical
option and the session filter selects it.

Split the current scope predicate into two explicit concepts:

- Forms Set inclusion: used by export and security/availability guards;
- view inclusion: Forms Set inclusion plus the new session filter, used by
  on-screen markers and all three Calendar lanes.

This split prevents a display-only deselection from silently changing an
export.

## 5. Multi-select view and messages

### `src/components/multi-select-combobox.native`

Keep the Global Dashboard template working unchanged. Add a profile-calendar
template with the same interaction structure:

1. closed select trigger;
2. autofocus search field;
3. pinned Select All/Deselect All actions;
4. bounded scrolling menu;
5. selected check mark per option;
6. `No matching options` empty row.

Use profile-specific bindings and messages. Do not make the profile template
call `multi_select_*`, because those messages intentionally own only
`globalDashboard.forms` today.

### `scripts/flatten-native.mjs`

If the profile component is inserted through an `@include-template`
directive, add its exact template name to `generatedTemplateIncludes`. Do not
edit the generated `src/app.native` by hand.

### `src/main.zig` messages

Add and handle these independent actions (names may be mechanically adjusted,
but keep the one-to-one behavior):

- `profile_calendar_forms_open`
- `profile_calendar_forms_close`
- `profile_calendar_forms_query_changed`
- `profile_calendar_forms_toggle_option`
- `profile_calendar_forms_select_all_filtered`
- `profile_calendar_forms_clear_all`

Dispatch guards:

- ignore an out-of-range index;
- ignore an inactive form index even if a stale UI message arrives;
- Select All touches only active options matching the query;
- Clear/Deselect All clears only this session filter;
- no handler writes the profile store.

## 6. Restore the three Calendar lanes

Use the pre-`e84e300` templates as a layout reference, with the following
corrected data rules.

### Upcoming Deadlines

Include a deadline only when all are true:

- deadline calendar year and month match the viewed profile calendar;
- if a day is selected, the deadline day matches it;
- the deadline passes the active Forms Set plus view-filter predicate;
- `final_deadline >= calendarToday`;
- no matching paid draft exists.

The calendar and the list live in this lane. Do not show a deadline-count
badge beside the top toolbar title or the Upcoming heading.

### Action Required

Include a row only when all are true:

- a real persisted draft exists for the selected filer and period;
- lifecycle is neither `paid` nor `cancelled`;
- its matching deadline is in the viewed calendar year and month;
- its matching deadline is not before `calendarToday`;
- its form passes the active Forms Set plus view-filter predicate.

Ignore the selected day. Store the matching deadline ID on the row so its
button can use the same exact-period launch path as a deadline row. Do not use
the draft array slot as a navigation identity.

### Overdue

Include a deadline only when all are true:

- its deadline calendar year matches the viewed profile calendar year;
- `final_deadline < calendarToday`;
- no matching paid draft exists;
- its form passes the active Forms Set plus view-filter predicate;
- it is in the viewed month, or it has a matching open draft that must remain
  in the backlog.

Ignore the selected day. Status comes only from `calendarToday`; selecting day
27 can never make day 27 overdue.

### Lane layout

Reuse the existing lane-mode functions:

- three columns at the existing three-column threshold;
- calendar lane left and Action Required + Overdue stacked right at the
  existing two-column threshold;
- all three stacked below that.

Do not stretch the calendar beyond `profileCalendarLaneWidth`.

### Card actions

Cards are informational surfaces; use a clear button for the form action
instead of making the entire card an accidental navigation target.

- Upcoming: `Start Form`, `Resume Form`, or `View Form` from lifecycle.
- Action Required: `Resume Form` or `View Form`.
- Overdue: `Open Form` (or `File Form` if product copy already uses it).

All buttons carry the exact deadline ID to `openProfileDeadlineById` and then
the existing exact filing-period launch path. With a launch-ready fixture, the
resulting `contentPage()` must be the form page, never `profile_setup`.

Do not bypass profile qualification. A `.needs_profile` launch is a separate
safety state, not the ready-routing regression: it should open the new inline
Profile Settings tab with the existing completion message and pending launch,
then return to the exact form after a successful save. The worker must not
make an incomplete projection appear editable merely to keep a form page
visible.

## 7. Make Profile Settings a primary tab

### `src/main.zig`

1. Add `.profile_settings` to `DashboardSection`.
2. Add `dashboardProfileSettingsActive`.
3. Add `show_dashboard_profile_settings`.
4. Entering it for an existing profile calls `taxProfiles.editSelected()`,
   selects the dashboard section, and stays on `.taxpayer_dashboard`.
5. Update the existing completion flow so `.needs_profile` can select this
   inline tab while retaining `PendingProfileFormLaunch`.
6. On successful inline save:
   - refresh the selected Forms Set and form launch assessments;
   - reset/reconcile the profile calendar form filter;
   - if a pending form launch exists, continue to that exact form;
   - otherwise remain in Profile Settings and reopen the newly saved revision
     for editing.
7. Inline Cancel discards staged profile edits and returns to Calendar. Keep
   standalone close/back behavior for new-profile creation and other
   standalone origins.

### `src/pages/taxpayer-dashboard.native`

1. Remove both header `Profile Settings` buttons.
2. Add `Profile Settings` to both constrained and regular primary tab rows.
3. When selected, mount `profile-setup-content` below the primary tabs.
4. Keep `Calendar` and `Tax Form Library` content mutually exclusive with it.

### `src/pages/profile-setup.native`

Keep `profile-setup-content` reusable and keep `profile-setup-page` for:

- creating a new taxpayer before a dashboard context exists;
- any standalone recovery flow that truly needs its own back navigation.

Do not duplicate the settings form into the taxpayer page.

## 8. Fix packaged logo/resource loading

Do not add fallback text logos and do not copy assets to another source
directory. The package already contains the correct files.

In `src/main.zig`, before app creation and before any image-loading effects:

1. Resolve the executable path with Zig 0.16's
   `std.process.executablePath(init.io, buffer)`.
2. Add a pure helper that recognizes the packaged macOS shape
   `*.app/Contents/MacOS/<executable>` and returns
   `*.app/Contents/Resources`.
3. Verify that `Resources/assets/brand/ebirforms.png` exists.
4. For that packaged shape only, call
   `std.process.setCurrentPath(init.io, resources_path)` before the runtime
   creates worker threads.
5. For a normal development binary, leave the working directory untouched so
   `assets/...` and `src/app.native` keep their documented project-relative
   meaning.
6. If a path looks packaged but Resources or the required brand image is
   missing, return a boot error. Do not silently show an unbranded shell.

Do not patch `node_modules/@native-sdk/cli`; the dependency is pinned and a
local dependency edit would disappear on `npm ci`.

Unit-test the pure path recognizer for:

- packaged macOS executable path;
- ordinary `zig-out/bin/ebirforms-zero` path;
- misleading directory names that are not the exact
  `.app/Contents/MacOS` shape.

The live package test must verify the eBIRForms sidebar image plus all three
footer image semantics labels.

## 9. File-by-file execution order

The worker must use this order so each step has one responsibility.

1. **State core and predicates — `src/main.zig`**
   - add profile form-filter state/messages/adapters;
   - split Forms Set scope from view scope;
   - add the corrected lane row builders;
   - add the Profile Settings dashboard section;
   - add packaged-resource path bootstrap.
2. **Component — `src/components/multi-select-combobox.native`**
   - add the profile adapter template without changing Global Dashboard
     behavior.
3. **Profile page markup — `src/pages/taxpayer-dashboard.native`**
   - add the responsive toolbar;
   - restore lanes and explicit action buttons;
   - add Profile Settings tab/content;
   - remove header settings buttons and deadline badge.
4. **Composition — `scripts/flatten-native.mjs` only if needed**
   - register the generated include name.
5. **Focused tests — `src/main.zig` and component/state tests**
   - add the matrix below before broad validation.
6. **Generate — `rtk npm run generate`**
   - inspect both source fragment diff and generated `src/app.native` diff;
   - run generation a second time and require no drift.
7. **Full validation and packaged live verification**
   - follow Sections 10 and 11.

## 10. Required automated tests

Replace the current weak test named
`profile dashboard markup builds with the three calendar lanes`; it only
builds markup and does not prove that three lane headings exist.

### Form filter

- initial profile/year selection selects every active form and no inactive
  form;
- options show only active forms for the chosen yearly Forms Set;
- code search works;
- title search works case-insensitively;
- filtered Select All changes only matching active forms;
- Deselect All produces `0 forms` and zero markers/rows in all three lanes;
- singular label is `1 form`; plural is `2 forms`;
- profile/year switch resets to all active forms in the new scope;
- month/day navigation preserves the current filter;
- filter actions do not change the persisted Forms Set or profile-wide
  calendar-selection tables;
- Global Dashboard selection remains unchanged after every profile-filter
  action.

### Three lanes and date behavior

- exact headings `Upcoming Deadlines`, `Action Required`, and `Overdue` exist
  in the built widget tree;
- an open future deadline appears in Upcoming;
- a persisted nonterminal draft appears in Action Required;
- a past unpaid deadline appears in Overdue;
- a paid draft appears in neither Action Required nor Overdue;
- selecting a day filters Upcoming only;
- Action Required and Overdue rows/counts are identical before and after day
  selection;
- year, month, profile Forms Set, and profile form-filter scope are enforced;
- marker colors derive from injected `calendarToday`, not the selected date;
- action button on a launch-ready 2551Q/1701Q fixture opens the exact form and
  period;
- pressing non-action card space does not navigate.

### Profile Settings tab

- three primary tabs exist in both regular and constrained markup;
- no header button with label `Profile Settings` remains;
- selecting the primary settings tab stays on taxpayer dashboard and mounts
  `profile-setup-content`;
- Cancel returns to Calendar without saving;
- Save stays inline when there is no pending form launch;
- a pending qualified form launch resumes after successful profile save;
- new-profile creation still uses the standalone setup page.

### Responsive toolbar

Build and inspect widget trees at representative viewport classes:

- desktop: single toolbar row and text Add to Calendar button;
- compact/rail: title row plus equal picker row and icon button;
- phone: title row, year-plus-icon row, full-width form-filter row;
- no control exceeds the available content width;
- icon-only button retains `Add to Calendar` semantics.

### Logo/resources

- pure packaged-resource path tests described in Section 8;
- the existing `registerBootImages` IDs remain stable;
- packaged launch from `/` loads image IDs 1, 2, 3, 4, and 6;
- sidebar and footer semantic image nodes exist after load.

## 11. Validation commands

Run from `/Volumes/goldcoders/Projects/ebirforms.0`. Prefix every command with
`rtk` as required by this workspace.

```sh
rtk npm run generate
rtk npm run generate
rtk npm run check:tax-catalog
rtk git diff --check main...HEAD
rtk npx native test --yes -Dplatform=null
rtk npx native check . --strict
rtk npx native build . --yes
rtk npx native build . --yes -Dautomation=true
rtk npx native doctor --manifest app.zon --strict
rtk npx native package --target macos --signing adhoc
rtk codesign --verify --deep --strict zig-out/package/ebirforms-zero.app
```

Test and build are both required. Generation must be idempotent. A green
headless suite is not visual proof of the responsive layout or packaged logo.

## 12. Isolated AeroSpace live verification

Do not reuse, close, focus, resize, or move the user's existing eBIRForms
window. Create a new app instance and move only the new window to an empty
AeroSpace workspace. Workspace 10 was empty during this investigation, but
re-check immediately before launch.

1. Record existing eBIRForms window IDs:

   ```sh
   rtk aerospace list-windows --app-bundle-id dev.goldcoders.ebirforms --format '%{window-id}|%{workspace}|%{window-title}'
   rtk aerospace list-workspaces --all
   ```

2. Launch a new packaged instance with `open -n` so the test exercises bundle
   resource resolution rather than inheriting the repository working
   directory:

   ```sh
   rtk open -n /Volumes/goldcoders/Projects/ebirforms.0/zig-out/package/ebirforms-zero.app
   ```

3. Poll by bundle ID, identify only the window ID absent from the prelaunch
   list, and move that exact ID without switching the user's current
   workspace:

   ```sh
   rtk aerospace list-windows --app-bundle-id dev.goldcoders.ebirforms --format '%{window-id}|%{workspace}|%{window-title}'
   rtk aerospace move-node-to-workspace --window-id NEW_WINDOW_ID 10
   ```

4. Verify the move:

   ```sh
   rtk aerospace list-windows --workspace 10 --app-bundle-id dev.goldcoders.ebirforms --format '%{window-id}|%{workspace}|%{window-title}'
   ```

5. Only after the new window is isolated, use Native automation to exercise:
   - desktop width;
   - compact/rail width;
   - phone width;
   - year picker;
   - form filter search, one form, no forms, and all forms;
   - each of the three lanes;
   - Profile Settings primary tab;
   - sidebar/footer image rendering.

6. Capture synthetic screenshots and assert:

   ```sh
   rtk npx native automate wait
   rtk npx native automate assert 'ready=true' 'gpu_nonblank=true' 'dispatch_errors=0' 'dropped_trace_records=0'
   rtk npx native automate screenshot main-canvas
   ```

If automation cannot distinguish the new instance, stop. Do not operate the
existing window as a fallback.

## 13. Stop conditions

Stop and report instead of improvising when any of these occurs:

- the selected year has no explicit Forms Set but the form filter shows
  catalog-wide options;
- a filter action writes SQLite or changes active Forms Set membership;
- display deselection changes `.ics` export contents;
- selected day changes Action Required or Overdue;
- a launch-ready card routes to `profile_setup`;
- the packaged app still depends on repository cwd for images;
- the Global Dashboard's selection changes when the profile filter changes;
- generation is non-idempotent;
- strict check, tests, build, package signature, or automation assertions fail;
- the only available eBIRForms window is the user's existing instance.

## 14. Definition of done

This remediation is complete only when all of the following are true:

- all three primary taxpayer tabs are visible and the header settings button
  is gone;
- all three Calendar work areas are present at every supported width;
- phone toolbar uses the required three-row layout without clipping;
- form filter lists and searches only active forms for the selected
  profile/year and labels its selection as `N form(s)`;
- the redundant deadline badge is gone;
- day selection cannot alter overdue/action classification;
- ready card actions open the exact form period;
- packaged sidebar/footer logos render after a Finder-style launch;
- generated markup is committed together with source fragment changes;
- every command in Section 11 passes;
- live evidence was collected from a newly launched app isolated by
  AeroSpace, without disturbing an existing app window.
