# Claude Fable 5 prompt: taxpayer setup, yearly forms, COR, and branches

Copy this entire prompt into Claude Fable 5. Attach these two screenshots to
the same request if image attachments are available:

- `Screenshot 2026-08-04 at 2.01.56 AM.png`
- `Screenshot 2026-08-04 at 2.02.03 AM.png`

The original local screenshot paths are:

- `/var/folders/6x/ssd0ns1s3kj76cs0pswjdk4m0000gn/T/TemporaryItems/NSIRD_screencaptureui_iyZJL7/Screenshot 2026-08-04 at 2.01.56 AM.png`
- `/var/folders/6x/ssd0ns1s3kj76cs0pswjdk4m0000gn/T/TemporaryItems/NSIRD_screencaptureui_d1pNGv/Screenshot 2026-08-04 at 2.02.03 AM.png`

---

You are a senior product designer, information architect, and workflow
designer for a native desktop tax-preparation application. Work as a design
partner, not as a code generator. Your job is to simplify the first-run and
recurring taxpayer-setup experience without weakening audit history, identity
safety, or filing correctness.

## Assignment

Design a consolidated taxpayer setup experience for eBIRForms that makes all
of these tasks obvious and fast:

1. Open an already configured tax year and edit its active BIR forms.
2. Set up an unconfigured current or historical tax year without creating a
   duplicate yearly Forms Set.
3. Start a year from an existing year's setup, then add or remove forms and
   revise only the taxpayer facts that changed.
4. Keep using unchanged taxpayer facts across years without forcing the user
   to create meaningless duplicate profile records.
5. Record a real taxpayer-fact change at its effective date while preserving
   older filing snapshots.
6. Upload a Certificate of Registration (COR) as evidence in the same area as
   registration and tax-form setup, rather than in a mostly empty standalone
   COR tab.
7. Create another registered branch/profile quickly, optionally seeding safe
   reusable facts and a Forms Set from an existing branch, while requiring the
   new branch identity to be reviewed.
8. Understand which reusable facts feed each active form and fix missing facts
   without editing the same name, address, or contact details separately on
   every form.
9. Apply a form- or filing-specific override only when necessary, with clear
   provenance and an easy way to return to the inherited profile value.

Do not implement anything. Inspect the repository read-only, challenge weak
assumptions, and return a decision-ready UX specification that Codex can turn
into an implementation plan after the user approves it.

## Product intent from the user

The experience must be "easy as fuck" for a first-time user. Optimize for
recognition, error prevention, and a short happy path. Do not expose storage
terminology such as "insert", "revision sequence", or "upsert" in end-user
copy.

The user specifically wants:

- a compact, right-aligned year combobox rather than a full-width year input;
- digits only and a valid four-digit year, never arbitrary text;
- no future year;
- the current year first when the unfiltered list opens, followed by older
  years in descending order;
- type-to-filter behavior;
- existing years to open their current setup for editing;
- missing years to show an explicit setup action, preferably copy such as
  `Set up forms for 2025` rather than implying the user is creating a new BIR
  form definition;
- no duplicate year and no silent overwrite;
- a faster "use/copy another year" path for a year whose profile facts and
  forms are mostly unchanged;
- the copied setup to remain editable before it is saved;
- the standalone COR tab removed and COR upload/review placed with tax forms
  and registration setup;
- a quick, safe way to add a branch as a new profile;
- reusable identity, name, address, and contact facts, with deliberate
  exceptions where a year, branch, form, or filing differs; and
- responsive desktop, compact, and phone layouts.

## Repository and platform context

Repository root:

`/Volumes/goldcoders/Projects/ebirforms.0`

This is a Zig application using Native SDK declarative `.native` markup. It is
not React, HTML, or SwiftUI. Do not propose a web-only component library. The
generated `src/app.native` is not an editable source file.

Read at least these files before designing:

- `docs/tax-profile/ARCHITECTURE.md`
- `docs/tax-profile/IMPLEMENTATION_PLAN.md`
- `docs/tax-profile/TAX_FORM_LIBRARY_AND_COR_ARCHITECTURE.md`
- `docs/tax-profile/FORM_FIELD_CATALOG.md`
- `src/pages/profile-setup.native`
- `src/pages/taxpayer-dashboard.native`
- `src/main.zig`
- `src/tax_profile/field.zig`
- `src/tax_profile/model.zig`
- `src/tax_profile/evolution.zig`
- `src/tax_profile/projection.zig`
- `src/tax_profile/ui_state.zig`
- `src/tax_profile/store.zig`
- `src/forms/spec.zig`
- `src/forms/generated/catalog.zig`

Read this paused plan only to understand nearby responsive calendar work; do
not continue or redesign that calendar in this assignment:

- `docs/calendar/PROFILE_CALENDAR_REMEDIATION_EXECUTION_PLAN_2026-08-04.md`

If repository access is unavailable, use the verified findings below and mark
any additional assumption. Do not invent implementation state.

## Verified current behavior and constraints

### Duplicate yearly Forms Sets

The current source is designed not to duplicate or overwrite a configured
year through the Add flow:

- `src/pages/profile-setup.native` currently renders a full-width `New tax
  year` input, an `Add yearly form set` button, and a separate card for each
  existing year.
- `Model.profileFormsAddYearDisabled()` is intended to disable Add for an
  existing year or a future year.
- the `.profile_forms_add_year` handler rejects a configured year and tells
  the user to edit its card;
- `State.beginManageFormsForYear(year, creating)` separates create mode from
  edit mode;
- `Store.createFormSet` uses an insert-only path and maps the SQLite uniqueness
  failure to `FormSetAlreadyExists`;
- `Store.updateFormSet` rejects a missing year; and
- the database primary key is `(profile_id, tax_year)`.

Therefore, the intended data contract is safe, but the current interaction is
not. The attached running-app screenshot shows 2026 in the Add field while a
2026 card already exists, and the next screenshot shows a blank 2026 manager.
Treat this source/runtime discrepancy as a required failure state for the
future implementation plan. Do not claim the observed build is correct merely
because the source has guards.

### Forms Set semantics

- A Forms Set answers which catalog forms apply to one profile and tax year.
- A configured empty set is authoritative and different from an unconfigured
  year.
- Form checkbox changes are staged; Save atomically creates or updates the
  selected year's set; Cancel restores persisted state.
- Only confirmed active forms feed that profile's Tax Form Library and profile
  calendar.
- The Global Dashboard and global Tax Calendar remain profile-independent.
- A calendar-only catalog entry can produce deadlines but must not pretend an
  in-app form editor exists.

### Taxpayer profile semantics

- A profile has a stable opaque `ProfileId` and append-only, effective-dated
  `ProfileRevision` values.
- Ordinary revisions may change RDO, name/trade name, address, contact facts,
  activities, and registration facts.
- Ordinary revisions may not silently change the canonical TIN or cross the
  broad natural-person/juridical-person/estate/trust identity boundary.
- A TIN correction needs an explicit audited correction path. A genuinely new
  legal taxpayer identity needs a new profile.
- Profile history resolves the highest-sequence revision effective on a date.
  A calendar year is a convenient UI context, but the domain can change within
  a year; do not flatten all profile history into exactly one mutable record
  per year.
- A form consumes only the reusable fields declared by its named role/spec.
- When a form draft is created, it owns an immutable snapshot of projected
  profile values and provenance. Later profile edits, COR uploads, and Forms
  Set changes must never silently rewrite that historical draft.

The current canonical reusable vocabulary contains:

`tin`, `rdo_code`, `taxpayer_name`, `registered_name`,
`registered_address`, `zip_code`, `contact_number`, `email_address`,
`date_of_birth`, `citizenship`, `foreign_tax_number`, `line_of_business`,
`atc`, `tax_type`, `government_withholding_agent`, and
`special_rate_basis`.

Do not turn filing amounts, schedule rows, payment data, calculated values, or
external-document contents into reusable profile facts merely because a form
displays them.

### Branch and identity gaps

- The TIN value object preserves a nine-digit root and an optional three- to
  five-digit branch segment.
- The current profile list is flat. The domain has relationships for spouse,
  predecessor, successor, and business conversion, but it does not yet expose
  a headquarters/branch hierarchy or a quick Add Branch workflow.
- The inspected schema anchors canonical TIN to a profile but does not visibly
  enforce one profile per owner plus full canonical TIN. Treat duplicate-TIN
  prevention and branch grouping as design/schema gaps to be resolved, not as
  completed features.
- Do not assume every fact is safe to copy to a branch. RDO, address,
  registration facts, branch TIN segment, COR evidence, and form obligations
  may differ and require review.

### COR status

- The current COR tab is only a disabled placeholder.
- COR must remain evidence, not authority. Upload/extraction may propose shared
  facts and forms, but nothing becomes authoritative without review and
  confirmation.
- A TIN mismatch must fail closed and offer to create a different profile,
  review the mismatch, or cancel.
- If the user accepts only proposed forms, do not create an unnecessary
  profile revision.
- Do not copy or save a second "tax form" from the COR. Preserve the evidence
  document/reference and confirmed decisions; do not duplicate form data.

## UX principles to apply

Use these as interaction constraints, not as visual-decoration inspiration:

1. One control should have one clear job. The year combobox selects the setup
   context; it must not silently save or overwrite data.
2. Separate navigation from mutation. Selecting a configured year loads its
   editor. Selecting an unconfigured year may open an unsaved setup draft, but
   only an explicit Save creates authoritative state.
3. Prefer one primary year workspace over an Add field, Add/Edit buttons, and
   redundant year cards all competing on the same screen.
4. Use progressive disclosure: show the common path first, expose history,
   advanced provenance, and rare overrides when relevant.
5. Keep visible signifiers for important actions; do not hide required setup
   behind a minimalist surface with no cue.
6. Prevent predictable errors before submission. If concurrency still causes
   a conflict, explain what happened, preserve the user's staged choices, and
   offer to load/merge the existing setup.
7. Use explicit, plain-language statuses such as `Configured`, `Not set up`,
   `Unsaved changes`, and `Effective July 1, 2026`.
8. Preserve keyboard operation, focus order, visible focus, Escape-to-cancel
   popup behavior, screen-reader labels/state, and 44-pixel minimum action
   targets where the Native design system supports them.

Useful standards:

- W3C APG combobox pattern:
  https://www.w3.org/WAI/ARIA/apg/patterns/combobox/
- Apple Human Interface Guidelines, pop-up buttons:
  https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons
- GOV.UK validation and recovery guidance:
  https://design-system.service.gov.uk/patterns/validation/
- Nielsen Norman Group on the interaction cost of hiding important UI:
  https://www.nngroup.com/articles/zen-mode/

## Core design question

Decide whether the separate `Add yearly form set` / `Edit forms` actions and
the year cards should be removed in favor of one reactive year workspace.

The leading hypothesis is:

- A compact year combobox is the single entry point.
- Selecting `2026 · 1 active form` loads the persisted 2026 setup.
- Typing or selecting an allowed missing year offers `Set up forms for 2025`.
- Opening a missing year creates only an in-memory draft.
- The draft offers `Start empty` and a recommended `Use setup from 2026` (or
  `Use previous configured year`) choice.
- Shared profile facts effective for the target date are inherited, not
  physically duplicated.
- The source Forms Set is copied into the target year's unsaved selection and
  can be changed before Save.
- Save explicitly creates the target Forms Set and, only when shared facts
  changed, appends the necessary effective-dated profile revision.
- Existing years never show a create action; they show the existing setup and
  Save changes.
- A rare history/list view can show every configured year without making
  large year cards the primary navigation.

Do not accept this hypothesis blindly. Compare it against alternatives and
recommend the simplest design that still makes configured history and new-year
setup discoverable.

## Required interaction contracts

### 1. Year combobox

Specify all of these details:

- compact desktop width appropriate for a four-digit year and dropdown
  affordance, not full width;
- placement and responsive behavior;
- digits-only editing/filtering;
- exactly four digits on commit;
- current year as the maximum, with no future options or future creation;
- an explicit recommendation for the minimum supported historical year rather
  than silently inheriting the storage layer's `1...9999` range;
- unfiltered ordering: current year first, then older years descending;
- how configured and unconfigured options differ visually and accessibly;
- the row copy and secondary metadata for configured years, empty configured
  years, and missing years;
- type-to-filter and no-match behavior;
- Enter, Up/Down, Escape, Tab, click-away, and focus-restoration behavior;
- loading, read failure, and stale/concurrent state;
- whether a short recent-year list plus a custom typed historical year is
  better than rendering hundreds of years; and
- exact end-user copy. Prefer `Set up forms for YYYY` over `Create tax forms`
  unless you can defend a clearer phrase.

### 2. Create-versus-edit behavior

Design a state machine with no ambiguous Add button:

- configured year selected;
- configured-empty year selected;
- unconfigured valid year selected;
- invalid/incomplete input;
- future year;
- new setup with no changes;
- new setup seeded from another year;
- editing with unsaved changes;
- switching year with unsaved changes;
- a duplicate created concurrently by another window/process;
- save failure; and
- successful creation/update.

State whether the primary action says `Save setup`, `Save changes`, or
something else in each state. Do not auto-save material checkbox or profile
changes merely because the user selected another year.

### 3. Copy/start-from-existing workflow

Design this as a first-class speed path, not a hidden technical clone:

- permit a new current or historical year to start from the nearest relevant
  configured year or another explicitly selected source year;
- show what will be reused, copied, excluded, and reviewed before Save;
- inherit unchanged shared profile facts from the effective revision rather
  than appending an identical profile revision;
- copy the source year's active Forms Set into an unsaved target-year
  selection;
- allow forms and changed taxpayer facts to be edited before Save;
- for historical setup, resolve facts effective for the target period rather
  than blindly copying today's profile;
- if no profile revision is effective for the target date, require a reviewed
  retroactive revision instead of fabricating facts;
- never copy filing drafts, filed artifacts, payment/status history,
  deadlines, operational email credentials, unconfirmed COR proposals, or
  immutable filing snapshots;
- decide whether an existing COR is merely referenced as historical evidence
  or whether a new/updated COR is required; never pretend an old document is
  new evidence; and
- make the result understandable without the user knowing the difference
  between reference reuse and database copying.

Include exact confirmation/summary copy, such as a concise `Starting from
2025` banner and a way to change the source before saving.

### 4. Profile facts over time

Do not force a false one-profile-row-per-calendar-year model. Design a simple
year-context UI over the actual effective-dated history:

- show which revision supplies the selected year's facts;
- show `No changes from 2025` when the same revision continues to apply;
- offer a plain-language `Record a change` action with an effective date;
- support a mid-year change and multiple revisions in one year;
- preserve current TIN/legal-person-class boundaries;
- expose history without overwhelming first-time setup; and
- distinguish correcting wrong data from recording a real-world change.

Evaluate whether the primary information architecture should be:

- `Profile` plus `Registration & Forms`;
- `Overview`, `Profile history`, and `Registration & Forms`; or
- another smaller structure.

The standalone COR tab should not survive unless you demonstrate a concrete,
frequent workflow that justifies it.

### 5. COR inside registration/forms

Design the compact default state and expanded review flow:

- `Upload COR` or `Add updated COR` entry point;
- attached document name/date/status without a large empty panel;
- local/optional cloud-processing disclosure;
- extraction progress, failure, retry, and manual fallback;
- proposed profile facts and proposed forms in independently selectable
  sections;
- current-versus-proposed comparison with evidence location;
- accept, edit, or reject per candidate;
- explicit Apply transaction;
- TIN/branch mismatch handling;
- replace/add-new-document semantics;
- evidence retention/deletion and provenance visibility; and
- no automatic activation and no silent profile overwrite.

### 6. Branch creation and switching

Design a quick `Add branch` flow while acknowledging the current schema gap:

- where the action lives in the profile switcher/sidebar and profile setup;
- whether the UI groups registrations under a taxpayer/TIN root or uses a
  flatter list with relationship metadata;
- the minimum information needed to create the branch;
- full TIN plus branch segment validation;
- duplicate full-TIN detection within the owning account;
- optional `Start from [existing branch]` seeding;
- a review matrix that defaults branch-specific RDO, address, registration
  facts, and Forms Set to review rather than silent copy;
- which facts are safe candidates to copy and which are never copied;
- optional copy of a selected year's Forms Set;
- COR mismatch and missing-COR behavior;
- an unmistakable final summary of the branch being created; and
- switching/isolation rules so staged state from one branch cannot leak into
  another.

Do not copy the source branch's canonical TIN, drafts, filings, secrets, or
unreviewed evidence. Do not promise organization-wide inheritance unless you
also identify the model and persistence changes it requires.

### 7. Form requirements, inheritance, and overrides

Avoid rendering one duplicate taxpayer-profile form for every active BIR form.
Design around the canonical reusable fields and the form catalog's declared
subsets:

- a shared facts editor is authoritative for reusable facts;
- indicate which active forms use a fact when that helps the user fix a
  missing requirement;
- show a `Complete profile` task only for facts genuinely required by an
  active form;
- offer a focused `Missing for 2551Q` view instead of exposing every catalog
  field at once;
- distinguish values inherited from the effective profile, year-scoped setup
  choices, form/filer-role selection, and filing-specific transaction values;
- if a form-specific override is allowed, show provenance such as `From
  profile`, `Changed for this filing`, or `Suggested from COR`;
- require an explicit scope for an override: this filing, a future effective
  profile revision, or another reviewed scope;
- provide `Use profile value` to remove an override; and
- never let an override silently mutate an existing draft snapshot or the base
  profile.

Tell us whether year-scoped per-form profile overrides are actually necessary.
Prefer effective profile revisions plus filing-specific exceptions unless a
real use case requires another persistent layer.

### 8. Responsive behavior

Provide desktop, compact/tablet, and phone wireframes. At minimum:

- the page title occupies its own clear row when space is constrained;
- a compact year control never stretches across the desktop page;
- controls reflow rather than shrink below readable/tappable sizes;
- the primary year/setup status remains visible on a phone;
- COR upload and Save actions remain reachable without a horizontal overflow;
- the 51-form manager becomes one column on a phone; and
- bottom actions do not cover content.

Use the repository's existing `desktopLayout`, `constrainedLayout`, and
`phoneLayout` concepts rather than inventing OS-specific branches.

## Alternatives you must compare

Evaluate at least these three models in a concise decision table:

1. Existing pattern: Add-year input/button plus newest-first year cards and
   per-card Edit buttons.
2. Reactive year combobox: one year-scoped workspace that opens existing setup
   or starts an unsaved missing-year setup.
3. Timeline-first setup: effective-dated profile history and Forms Set changes
   as the primary navigation.

Score each for:

- first-time comprehension;
- duplicate/error prevention;
- speed for a new year;
- speed for a historical year;
- visibility of existing configurations;
- support for mid-year changes;
- branch creation;
- auditability;
- desktop/phone responsiveness;
- accessibility; and
- implementation fit with the verified repository.

Select one primary model. You may borrow a secondary history view from another
model, but do not present three equal recommendations.

## Required deliverables

Return one self-contained Markdown design specification with these sections in
this order:

1. **Executive recommendation** — the chosen model and why, in plain language.
2. **Terms and mental model** — user-facing names for taxpayer profile,
   branch/registration, yearly setup, Forms Set, revision/change, COR evidence,
   and form-specific exception. Identify internal terms that should never
   appear in UI copy.
3. **Repository-grounded findings** — what exists, what is only a placeholder,
   and what needs domain/persistence work. Cite file paths and symbols.
4. **Alternative decision table** — compare the three required models and pick
   one.
5. **Information architecture** — exact tabs/sections/actions. Explicitly say
   where COR, Email Settings, Add Branch, profile history, and yearly form
   setup live.
6. **Domain-to-UI separation diagram** — show owner/account, taxpayer or
   registration profile, effective revisions, yearly/effective Forms Sets,
   COR evidence/proposals, form workspaces, and immutable snapshots.
7. **Primary flows** — first profile, configure current year, configure an
   older year, use another year's setup, edit an existing year, record a
   mid-year fact change, upload/review COR, add a branch, resolve missing form
   facts, and add/remove a form later.
8. **Year combobox specification** — full state, validation, ordering,
   keyboard, focus, copy, and failure contract.
9. **Copy-from-year specification** — source selection, preview, include/
   exclude rules, save semantics, historical effective-date behavior, and
   exact copy.
10. **Profile history specification** — carry-forward behavior, changes versus
    corrections, effective dates, history disclosure, and TIN/legal-class
    boundaries.
11. **COR specification** — compact placement, upload/review, evidence,
    consent, mismatch, and failure behavior.
12. **Branch specification** — creation, grouping/switching, seeding, duplicate
    prevention, review, and schema gaps.
13. **Form requirement and override specification** — inheritance layers,
    provenance labels, missing-data tasks, override scope, and reset behavior.
14. **Desktop/compact/phone wireframes** — annotated low-fidelity ASCII or
    Mermaid wireframes for default, missing-year setup, form manager, and Add
    Branch.
15. **Component/state matrix** — default, hover, focus, expanded, filtered,
    loading, empty, disabled, invalid, unsaved, conflict, success, and read
    failure states.
16. **Content design table** — exact titles, labels, helper text, statuses,
    errors, confirmations, and empty states. Avoid vague copy such as `Invalid
    input` or `An error occurred`.
17. **Accessibility and responsive acceptance criteria** — keyboard order,
    focus restoration, popup dismissal, accessible names/states, contrast,
    touch targets, and reflow.
18. **Data/API/schema gaps** — separate UI-only work from required domain,
    migration, COR storage, branch grouping, uniqueness, and effective Forms
    Set changes. Do not hand-wave gaps.
19. **Phased implementation recommendation** — design dependencies and the
    smallest safe vertical slices, but no code.
20. **Decision log for Codex** — a compact list of approved defaults,
    unresolved questions, explicit non-goals, and testable acceptance
    criteria that can be turned directly into an execution plan.

## Required acceptance scenarios

Your design must explicitly walk through these scenarios:

1. 2026 already exists. Typing/selecting 2026 loads Edit mode; it cannot open
   a blank Create mode, duplicate, or overwrite without a reviewed Save.
2. Another process creates 2026 while this window has an unsaved new-2026
   setup. The user keeps their staged work and gets a recoverable conflict.
3. 2025 is missing. The user selects it, chooses `Use setup from 2026`, removes
   one form, and saves 2025 without changing 2026.
4. The profile facts are unchanged from 2025 to 2026. The UI communicates
   carry-forward without appending a meaningless duplicate revision.
5. The address changes on July 1, 2026. Earlier drafts keep the old snapshot;
   later work uses the new effective revision.
6. A user retroactively sets up 2023. The app uses facts effective in 2023 or
   asks for a reviewed retroactive profile change; it does not copy 2026 facts
   blindly.
7. The user deliberately saves zero active forms for a year. The UI preserves
   `Configured: no active forms` and never treats it as unconfigured.
8. A COR proposes a new address and three forms. The user accepts only the
   forms; no unnecessary profile revision is created.
9. A COR TIN/branch mismatch cannot mutate the selected profile.
10. The user adds a branch, seeds shared name/contact suggestions and a 2026
    Forms Set from headquarters, reviews branch-specific TIN/RDO/address, and
    saves an isolated profile.
11. A required 2551Q profile field is missing. The UI shows the focused missing
    fact and where it is used; it does not ask the user to maintain a separate
    2551Q taxpayer profile.
12. A filing needs a one-off different contact value. The user can see its
    scope/provenance and reset to the profile value without changing historical
    snapshots.
13. Switching year, profile, or branch with unsaved changes cannot silently
    discard or leak staged state.
14. The complete flow works at desktop, compact, and phone widths with no
    horizontal overflow.

## Non-goals and safety boundaries

- Do not redesign the global calendar or resume the paused profile-calendar
  remediation plan.
- Do not generate implementation code.
- Do not edit generated `src/app.native`.
- Do not collapse profile facts, Forms Set membership, filing transaction
  values, drafts, and COR evidence into one mutable record.
- Do not auto-activate OCR/AI suggestions.
- Do not auto-save material changes on year selection.
- Do not silently upsert an existing year from a create path.
- Do not clone drafts, filed artifacts, payments, secrets, or immutable
  snapshots into another year or branch.
- Do not claim every catalog form has an editor; the current catalog contains
  explicit calendar-only entries.
- Do not claim production-safe COR storage until key custody, encryption,
  retention, deletion, and consent gates are designed and verified.
- Do not make legal or BIR-policy claims that are not grounded in supplied
  product requirements or cited primary sources. Mark product assumptions for
  confirmation.

Finish with one recommended screen model and one clear handoff contract. Do
not end with "it depends" and do not give multiple equal designs.
