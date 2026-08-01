# Tax Form Library Interaction Audit

Date: 2026-08-01  
Branch: `codex/tax-form-library-forms-set`  
Commit under review: `3af467c` (feature base: `b9dea48`)

## Outcome

The constrained/mobile Tax Form Library row action was too wide because it
rendered the full `Open Form`/`Complete profile` text button beside the card
content. It now renders a 44 x 44 icon-only `file-text` button. The dynamic
launch label remains on the button as its accessible name, so the action is
compact visually without becoming unnamed for keyboard or screen-reader users.
The action is icon-only through phone, compact, and narrow-tablet widths; wider
desktop layouts retain the text action because their available width is larger.

The selected tax year is also now displayed directly between the previous- and
next-year chevrons on both compact and desktop headers. The count remains with
the Tax Form Library title, making the year-navigation relationship explicit.

## Evidence and limitation

The control wiring, state transitions, and persistence paths were inspected in
the source and covered by the Native checks and test suite. A live click pass
was attempted with both the Computer Use service and the Native automation
publisher. Neither service attached in this environment: Computer Use failed
during service startup and the automation-enabled app terminated with `SIGABRT`
before publishing a snapshot. Therefore this report does not claim that the
controls were clicked in a live session. The behavior below is the verified
source/model behavior, and the remaining visual risk should be rechecked when a
working UI harness is available.

## Control behavior

### Tax-year chevrons

The left and right chevrons are not duplicate form-navigation controls:

- Left (`Previous tax year`) dispatches `calendar_previous_year`.
- Right (`Next tax year`) dispatches `calendar_next_year`.

Each control changes the selected tax year, loads that profile's Forms Set for
the new year, and refreshes the profile calendar and launch assessments. It does
not change the global calendar schedule, and it does not move between forms.
When a Forms Set edit is dirty, either control is rejected with an unsaved
changes error until the user saves or cancels the staged edit.

### Activity filters

- **Active** shows forms currently selected for the profile and year.
- **Inactive** shows forms not selected for the profile and year.
- **All** shows the complete 51-form catalog.

Outside Manage Forms, these filters use the persisted Forms Set. During Manage
Forms, they use the staged checkbox selection so a user can inspect the pending
result before saving.

### Capability filters

- **All capabilities** includes both editor-backed and calendar-only catalog
  entries.
- **Editor available** shows the ten catalog entries with a Native editor
  layout.
- **Calendar only** shows the other 41 entries. They can contribute deadlines
  and calendar exports, but they never expose an Open Form editor action.

On constrained layouts the three capability choices are inside the compact
Capability filter menu; on wider layouts they are inline buttons.

### Search

The `Search by form code` field dispatches `profile_forms_search_input` on each
input event. Matching is case-insensitive and is applied to the catalog form
code (for example, `2551q` matches `2551Q`). It intentionally does not search
the form title, category, or filing frequency. That is correct for the current
placeholder, but title/category search would be a separate future enhancement
if users expect a broader catalog search.

### Manage Forms

`Manage Forms` opens a profile- and tax-year-scoped staged editor containing the
full catalog. Checkbox changes, Select all, Clear all, search, and filters only
change in-memory staged state. They do not write SQLite.

- **Select all** selects all 51 catalog entries in the staged set.
- **Clear all** removes every staged selection. Saving this result creates an
  explicit `active_empty` Forms Set; it does not fall back to all forms.
- **Reset to catalog default** is a separate compatibility action for legacy
  catalog-fallback profiles.
- **Save** atomically replaces the Forms Set for the selected profile and year,
  then refreshes the profile library and profile calendar.
- **Cancel** restores the persisted selection and closes the staged editor.

Profile or tax-year context changes are blocked while staged selections are
dirty. Switching profiles also resets transient query, filter, and staged
selection state, which prevents one profile's pending selection from leaking
into another profile.

### Open Form

An Open Form action is only shown for an active catalog entry that has an
implemented editor. Before routing, the launch preflight checks:

1. the form is active for the selected profile and year;
2. an editor revision exists;
3. required profile facts and roles can be resolved; and
4. the launch assessment is eligible.

An incomplete profile is routed to Profile Setup (`Complete profile`), an
ambiguous activity is routed to the activity-selection flow, and an ineligible
or unavailable form is disabled. Calendar-only entries never route to an
editor. Historical drafts are not deleted when a form is later deactivated.

## Findings and polish recommendations

| ID | Finding | Status |
| --- | --- | --- |
| F-01 | Full text launch action overflowed constrained/mobile cards. | Fixed in this branch with a labeled 44 x 44 icon button. |
| F-02 | A live click/screenshot pass could not run because Computer Use and Native automation failed to attach. | Environment blocker; rerun on a working harness. |
| F-03 | Search matches form code only, not title/category/frequency. | Working as labeled; consider broader search only if product requirements call for it. |
| F-04 | In Manage Forms, Active/Inactive filtering follows staged checkbox state while each row's Active/Inactive badge still describes the persisted set. | Potential wording ambiguity. Consider changing the management labels to Selected/Not selected or adding a Pending badge. |
| F-05 | The capability selector is a compact menu on small screens and inline controls on wide screens. | Source layout is intentional; verify focus and dismissal on a live device. |

F-04 does not change persistence correctness: the staged state is what Save
would commit, and the persisted state remains authoritative until Save succeeds.
It is a clarity improvement rather than a data-integrity defect.

## Verification completed

The following gates passed after regeneration:

```text
npm run generate
npx native check . --strict
  27 markup files checked; all ok
npx native test --yes -Dplatform=null
  876/876 tests passed
npx native build . --yes
  ReleaseFast build succeeded
git diff --check
  no whitespace errors
```

## Screenshot evidence

Post-fix reference-rendered captures are available for review:

- Phone, 408 x 800: `/tmp/ebirforms-tax-form-library-current-phone.png`
- Narrow tablet, 768 x 768: `/tmp/ebirforms-tax-form-library-current-tablet.png`
- Wider desktop, 1176 x 768: `/tmp/ebirforms-tax-form-library-current-desktop.png`

The phone and narrow-tablet captures show the icon-only action. The wider
desktop capture intentionally retains the labeled `Open Form` action. These
PNGs were rendered from the real app markup and synthetic profile model through
the Native SDK reference renderer. The live macOS window still could not attach
to the Computer Use or Native automation service in this environment.

The earlier pre-fix baselines remain available for comparison:

- `/tmp/ebirforms-tax-form-library-desktop.png`
- `/tmp/ebirforms-tax-form-library-tablet.png`
- `/tmp/ebirforms-tax-form-library-mobile.png`
