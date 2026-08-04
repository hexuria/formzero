# Tax Profile and Registration & Forms audit

- Date: 2026-08-04
- Audited current revision: `abd45c6` on `main`
- Audited installed legacy application: `/Applications/eBIRForms 2.app`,
  version `0.1.0` build `25`
- Legacy source checkout:
  `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir` at `e34fa848`
- Status: historical evidence baseline at `abd45c6`, with the execution-branch
  workflow result linked below
- Governing execution contract:
  [`TAX_PROFILE_AND_FORM_PROFILE_EXECUTION_PLAN_2026-08-04.md`](TAX_PROFILE_AND_FORM_PROFILE_EXECUTION_PLAN_2026-08-04.md)

## Document status and precedence

This audit records observed/source-backed behavior at the revisions above. It
does not itself authorize a guessed field meaning or certify filing support.
Where older tax-profile documents conflict, use this precedence:

| Document | Status for this work |
| --- | --- |
| This audit | Current defect/evidence baseline. |
| [Tax Profile and Tax Form Profile execution plan](TAX_PROFILE_AND_FORM_PROFILE_EXECUTION_PLAN_2026-08-04.md) | Current dependency order, acceptance gates, and implementation stop conditions. |
| [Taxpayer Setup UX Specification](TAXPAYER_SETUP_UX_SPEC_2026-08-04.md) | **Partially superseded.** Its §13 verdict and decision D13 that reject a persistent year-scoped per-form setup layer no longer govern. Non-conflicting historical behavior remains evidence, not authority over this plan. |
| [Tax-profile architecture](ARCHITECTURE.md) | Retained architectural foundation: canonical taxpayer facts, named roles, owned projection, and immutable draft snapshots remain required. |
| [Earlier implementation plan](IMPLEMENTATION_PLAN.md) | Historical implementation baseline. The new execution plan governs remaining and replacement work where the scopes overlap. |
| [Tax Form Library, Forms Set, and COR architecture](TAX_FORM_LIBRARY_AND_COR_ARCHITECTURE.md) and [interaction audit](TAX_FORM_LIBRARY_INTERACTION_AUDIT.md) | Retained as domain/history evidence. The new execution plan governs the Tax Profile view/edit, Registration browse/manage, and Tax Form Profile interactions. |

No tax-profile docs index or README exists at this revision, so the paired audit
and execution plan are the entry point. Milestone 0 does not rewrite the older
documents or any source file merely to change their historical record.

## Outcome

At audited revision `abd45c6`, the Tax Profile and Registration & Forms
experience was not ready for users. The primary failures were architectural,
not isolated styling bugs:

1. Tax Profile has no read-only mode. Opening it immediately creates an edit
   session.
2. Registration & Forms has a browse presentation in the markup, but the
   application forces every configured year into manage mode, making that
   presentation unreachable.
3. No tax-form-specific, tax-year-scoped profile entity, persistence, page, or
   catalog contract exists.
4. The current specification explicitly rejected the per-form annual layer.
   The new product direction therefore supersedes that decision; this is not
   an unfinished button that can be wired up safely in isolation.
5. Subject-specific fields are not governed by one applicability policy.
   Visibility, validation, buffer clearing, persistence, and projection can
   disagree.
6. The generated catalog reflects incomplete current Native markup rather
   than a verified inventory of each form's real recurring header and setup
   needs.

The legacy application should be used as behavioral evidence, not copied
wholesale. It provides useful View/Edit intent, profile-to-form projection, a
2551Q snapshot/freeze pattern, and—on the later source checkout—a solid
per-year Forms Set model. It does **not** contain the requested annual Tax Form
Profile, and it has always-enabled Save, field overexposure, and destructive
save defects that must not be imported. In build 25, saving reconstructs
`atc_codes` as empty, the Individual `Birth Date` control writes the shared
business-start field, and the 8% election editor mutates only the machine's
current tax year.

### Execution update

The initial catalog defect inventory below has now produced a source-backed
header repair. Twenty-six inherited controls were restored from the reviewed
legacy constructors: ZIP/contact/email for 0605; ZIP/email for 1601C; the
missing shared header values for 0619E/F; ZIP/contact/email for 1702RT/MX; and
address/ZIP/contact/email for 2550Q. These controls project canonical profile
or selected-activity values; they do not create copied annual settings. Their
catalog presence is optional until exact official requiredness is qualified,
so a migrated null remains unrecorded instead of being invented.

The generated census is therefore 325 inputs and 91 profile targets, 34 of
which are optional. Incorporation date, EOPT classification, and exact
withholding-agent category remain separate evidence-aware registration or
entity facts; this repair does not misclassify them as generic strings.

The current execution branch also separates the four statuses that the
baseline cards conflated: Forms Set activation, Tax Form Profile setup
readiness, editor availability, and fileability. A static Native editor now
says `Editor available` independently from its still-unqualified filing
artifact status; a calendar-only form says `Calendar only` and `No artifact`.
Confirmed v16 Registration facts such as withholding-agent designation, EOPT
tier, registration activity status, and special-law/treaty basis are displayed
read-only instead of being silently counted but hidden.

### Current-branch disposition — 2026-08-04

The findings below remain the historical defect baseline observed at
`abd45c6`. They are intentionally not rewritten into past tense or removed.
On `codex/tax-profile-form-profile-execution`, the corresponding source
implementation now has this disposition. Final full-gate and packaged live
evidence is recorded in the governing execution plan:

- Tax Profile has distinct create/view/edit modes. Saved values render as
  read-only semantic rows; Edit captures a baseline; clean Save/Cancel are
  disabled; dirty Cancel restores in place; Save appends and returns to view;
  and dirty navigation asks the user to Stay or Discard.
- One applicability policy controls natural-person classification,
  personal/entity/business visibility, Trade Name, and business activity.
  Corporations no longer inherit the personal section, while self-employed
  and mixed-income users can reach Line of Business. Sidebar RDO is removed.
- Registration & Forms now opens in browse mode and enters staged checkbox
  management only through Manage Forms. Activation history is exact-year and
  date-effective. The same Forms Set resolver supplies period/card and launch
  availability rather than each surface interpreting the interval separately.
- The schema v16 migration establishes an independent append-only Registration
  stream for stable activities, obligations, and typed statuses. Its
  selected-year projection includes
  components whose intervals intersect the year, so a January–June activity
  is not hidden merely because it is inactive on 31 December.
- **P1 — open and bounded: same stable anchor with multiple effective segments
  inside one year.** If one stable anchor
  has multiple separately effective revisions inside the same selected year,
  the current workspace does not expose all of those segments as separately
  editable rows. A segmented-history editor is required; the implementation
  must not collapse or overwrite those revisions.
- The generated catalog now covers 51 form codes, 10 supported editor
  revisions, 41 explicit calendar-only forms, 325 inputs, and 91 direct
  profile targets, including 26 restored inherited headers. Its deterministic
  Tax Form Profile contracts distinguish `setup` from `no_setup` and retain
  official requiredness questions as evidence gates.
- Taxpayer-Year settings and Tax Form Profile are separate append-only streams,
  each with read-only/edit state, exact-year resolution, history, explicit
  prior-year copy/review, optimistic conflicts, and retained history through
  deactivation/reactivation. The schema v20 migration fixes copied Tax Form
  Profile source provenance to reference the retained source form revision.
- Tax Form Profile is a year/form/revision-scoped page. It shows inherited
  Tax Profile facts read-only, generated setup selectors, history/readiness,
  inactive-history behavior, and a direct Registration repair path that
  returns to the same form/year.
- Draft provenance records source-specific immutable identities. Exact 1701Q
  writes require the schema v19 frozen provenance sidecar and its shared
  Taxpayer-Year election; resume reconstructs the historical projection from
  the exact named profile/component revisions and fails closed on missing or
  mismatched history instead of using today's profile.

The detailed R1–R14 and Milestone 0–12 mapping is in
[Current-branch implementation disposition](TAX_PROFILE_AND_FORM_PROFILE_EXECUTION_PLAN_2026-08-04.md#current-branch-implementation-disposition--2026-08-04).
The authoritative [final workflow acceptance evidence](TAX_PROFILE_AND_FORM_PROFILE_EXECUTION_PLAN_2026-08-04.md#final-workflow-acceptance-evidence--2026-08-04)
records 1,381 passing tests / 4 intentional skips, 29 strict-checked markup
files, the exact fresh package/hash/PID/data directory, zero-error desktop and
408×800 replays, and Computer Use accessibility inspection. Packages produced
before the Registration keyed-loop, Tax Form Profile edit/picker, and return-
context renderer corrections are superseded.

None of this source disposition proves production filing support. Official
form/PDF/XML fidelity, calculation and validation completeness, submission,
signing/key custody, notarization, and distribution remain separate gates.

## Form usage and implementation priority finding

Neither the installed build nor the local repositories contain trustworthy
anonymous usage telemetry, so this audit cannot truthfully claim which forms
users *actually* file most often. The source-backed planning proxy is the
[existing form build priority](../../FORM_BUILD_PRIORITY.md): common monthly
withholding/remittance work starts with 1601C, 0619E, and 0619F; the ordinary
quarterly queue starts with 1701Q and 1601EQ, with 2550Q and 2551Q already in
the supported-editor set; ordinary annual individual/business forms precede
specialist forms.

That priority is an implementation roadmap, not an activation default. The
current taxpayer's Registration & Forms selection remains authoritative: no
form is activated merely because it is common, and specialist/calendar-only
forms remain visible and truthful without pretending that an editor or filing
artifact exists. The exhaustive ownership audit therefore covers all 10
current editor revisions while keeping the other 41 catalog forms explicitly
calendar-only.

## Product interpretation used by this audit

The request's “view mode where we only see the save tax profile” is interpreted
as “show the **saved** Tax Profile read-only, with one Edit Tax Profile action.”
It is not interpreted as showing a Save button in view mode.

“Self-employed” is a natural-person tax classification, not a separate legal
person. The existing `Sole proprietor` choice can remain as a user-facing
shortcut, but the domain must distinguish:

- legal/subject identity (natural person, corporation, partnership, estate,
  trust, and so on); and
- individual tax classification (pure compensation, self-employed or
  professional, mixed income, and other applicable classifications).

Build 25 confirms that self-employed users could access Line of Business, but
it rendered the field for every taxpayer type. The new product policy is to
show business activity for self-employed, mixed-income, sole-proprietor, and
applicable legal-entity profiles while hiding it for a purely compensation
individual with no business activity.

## Evidence and audit method

### Milestone 0 application at `abd45c6`

- PR #14 was merged first, then `main` was fast-forwarded to `abd45c6` and
  verified equal to `origin/main` with a clean worktree.
- Generated Native markup was refreshed with `rtk npm run generate`.
- A fresh automation-enabled ReleaseFast binary was packaged and relaunched.
- Computer Use and Native accessibility automation were used to open a
  taxpayer, Tax Profile, and Registration & Forms; change subject kind; scroll
  the complete editors; and exercise both Cancel actions.
- The five supplied annotated screenshots were checked against that fresh
  process rather than against a stale running binary.
- Current source, state transitions, SQLite migrations, catalog generation,
  and tests were inspected.

### Legacy application and source

- Computer Use confirmed the installed app's separate View/Edit intent and
  Tax Form Library cards. Visual capture became blank after deeper navigation
  in the legacy GPU surface, so detailed conclusions were cross-checked
  against the installed bundle metadata and matching historical source.
- The installed build is universal `x86_64/arm64`, version `0.1.0`, build `25`,
  SHA-256
  `fa6de9b35a6dbea69e9184108a32a1bf7b000eded8e96b12925c110114867f4c`.
- Build 25 strongly correlates to historical commit `1cfcb220`: that commit
  declares build 25 and the following commit declares build 26. The bundle
  does not embed a Git SHA, so this is strong correlation, not cryptographic
  proof.
- The current legacy checkout at `e34fa848` was also audited because it contains
  a newer per-tax-year Forms Set implementation absent from installed build 25.

### Baseline verification

The codebase is mechanically green despite the product failures:

| Gate | Result |
| --- | --- |
| `rtk npm run generate` | deterministic output already current |
| `rtk npm run check:tax-catalog` | 51 codes, 10 editors, 41 calendar-only forms, 299 inputs, 72 profile targets; passed |
| `rtk npx native test --yes -Dplatform=null` | 1054 passed, 4 skipped; passed |
| `rtk npx native check . --strict` | 28 markup files and manifest; passed |
| `rtk npx native build . --yes -Dautomation=true` | ReleaseFast build passed |

This green baseline is important: existing tests either omit the requested
state transitions or intentionally encode the wrong interaction model. A
passing suite is not evidence that these pages function correctly.

### Audit claim boundaries and stop conditions

- Treat the baseline as revision-specific evidence, not a permanent expected
  test count. Any later count change requires an explained source/catalog diff.
- Stop implementation when an official or legacy field meaning is ambiguous;
  record it as evidence-gated instead of promoting it into profile storage.
- Do not treat the build-25-to-`1cfcb220` correlation as an exact binary source
  attestation; the installed bundle has no embedded Git SHA.
- Do not turn the initial catalog defect inventory in finding F into persistence
  until the ownership matrix is reviewed and approved.
- If a baseline command fails before a feature slice begins for an unrelated
  reason, stop that slice and report the failure rather than weakening a gate.

## Severity summary

| Priority | Finding | User impact | Confirmed by |
| --- | --- | --- | --- |
| P0 | No Tax Profile view/edit/create state | Users are always editing; clean Save/Cancel are wrong; Cancel leaves the page | live UI and source |
| P0 | Registration & Forms is forced into manage mode | Checkboxes and bulk actions appear immediately; clean Cancel appears to do nothing | live UI and source |
| P0 | No annual Tax Form Profile | Reusable form/year setup cannot be saved or reused | schema, catalog, navigation, source |
| P0 | Existing specification rejects the requested layer | A local UI patch would conflict with domain and persistence assumptions | specification and source |
| P1 | Subject applicability is fragmented | Corporation sees personal fields; Trade Name and Line of Business rules are incorrect | live UI and source |
| P1 | Missing-detail warning is on the wrong surface/year | Warning can describe another year and reacts to unsaved buffers | live UI and source |
| P1 | Catalog mappings are incomplete or misclassified | Forms request the wrong reusable facts or omit real recurring headers | current/legacy comparison |
| P1 | Mid-year activation is recorded but not consistently consumed | “From a date” does not reliably control library/calendar availability | store and UI state |
| P1 | UI cannot edit every shape accepted by the domain | Multiple activities or independently effective components can become unsupported | domain/editor source |
| P2 | Sidebar leaks RDO and unsaved edits | Selected row is inconsistent and can display an unsaved RDO | live UI and source |
| P2 | Desktop selected-state concern from screenshot is no longer reproducible | Fresh build does show selected subject state; coverage remains weak | live UI and source |

## Supplied screenshot disposition

| Screenshot | Disposition after fresh rebuild |
| --- | --- |
| 4:20:11 PM — active-form missing details on Tax Profile | Confirmed wrong surface. It can additionally read the wrong selected year and unsaved buffers. Replace with base validation plus form-card/form-profile readiness. |
| 4:22:09 PM — Registration & Forms immediately managing | Confirmed. Browse cards exist but are unreachable; clean Cancel remains enabled and leaves the same manager visible. |
| 4:24:30 PM — clean Tax Profile actions and Cancel semantics | Confirmed. Clean Save and Cancel were enabled. After an unsaved change, Cancel navigated to Calendar rather than reverting in place and returning to view. Save must append a revision, not overwrite history. |
| 4:26:19 PM — Corporation fields and selected state | Corporation still exposes Individual capabilities, confirmed. The selected subject styling itself worked on the fresh merged build, so that sub-issue is not currently reproducible. |
| 4:38:27 PM — sidebar RDO | Confirmed. Remove it; the current value can also come from the unsaved editor buffer. |

The user-request and screenshot-to-milestone mapping is maintained in
[Requirement traceability](TAX_PROFILE_AND_FORM_PROFILE_EXECUTION_PLAN_2026-08-04.md#requirement-traceability),
so every disposition above has an implementation owner and a release proof.

## Detailed findings

### A. Tax Profile opens directly as an editor

Opening Profile Settings invokes `editSelected()` immediately in
[`src/main.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/main.zig#L8167). The dashboard embeds the editable
component directly in
[`src/pages/taxpayer-dashboard-page.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/pages/taxpayer-dashboard-page.native#L45),
and the action footer is always rendered in
[`src/pages/profile-setup.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/pages/profile-setup.native#L928).

`saveDisabled()` checks store attachment and supported shape, not whether the
editor is dirty
([`src/tax_profile/ui_state.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/tax_profile/ui_state.zig#L585)).
In the clean live state:

- Cancel was enabled;
- Save New Revision was enabled.

After making an unsaved subject-kind change, pressing Cancel navigated to
Calendar instead of restoring the Tax Profile in place and returning to
read-only mode.

Navigation also silently invokes `cancelEdit()` in
[`src/main.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/main.zig#L10165), and an existing test codifies the
silent discard behavior near line 13884.

Required behavior:

- existing profile -> `viewing`;
- Edit Tax Profile -> `editing` with a captured baseline;
- clean editing -> Save and Cancel disabled;
- first truthful change -> both enabled;
- Cancel -> restore baseline and return to `viewing` without leaving Profile
  Settings;
- successful Save -> append revision and return to `viewing`; and
- navigation with dirty edits -> explicit discard/stay guard.

The store already avoids appending an unchanged revision near
[`src/tax_profile/ui_state.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/tax_profile/ui_state.zig#L1432), but
that persistence safeguard does not repair the interaction.

### B. Registration & Forms is permanently in manage mode

Opening the tab calls `ensureYearWorkspaceOpen()`
([`src/main.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/main.zig#L8177)). Opening a configured year sets
`managing_forms = true`
([`src/tax_profile/ui_state.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/tax_profile/ui_state.zig#L1925)),
and the render predicate treats every `.viewing` workspace as the manager
([`src/main.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/main.zig#L3175)).

The live clean state showed:

- `When does this apply?` controls;
- search and all-form filters;
- `Select all 51` and `Clear all`;
- checkboxes on every form card;
- Cancel enabled; and
- Save Changes disabled.

Pressing Cancel left the same manager visible. Existing APIs already express
the intended transition—`beginManageForms()` near line 2324 and
`cancelManageForms()` near line 2416 of
[`src/tax_profile/ui_state.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/tax_profile/ui_state.zig)—but the
application path and visibility predicate do not use them correctly.

Browse cards without checkboxes already exist in
[`src/pages/taxpayer-dashboard.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/pages/taxpayer-dashboard.native#L663),
but normal Registration & Forms navigation cannot reach them.

Required behavior:

- configured year opens in browse mode;
- browse mode shows active forms only, without checkboxes;
- one Manage Forms action enters staged management;
- only manage mode shows effectivity, search, checkboxes, select/clear, Save,
  and Cancel;
- clean manage mode disables Save and Cancel;
- changed manage mode enables both; and
- Save or Cancel returns to browse mode visibly.

### C. Annual Tax Form Profile is absent at every layer

There is no generic page in the page enum near
[`src/main.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/main.zig#L177), no card action in
[`src/pages/taxpayer-dashboard.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/pages/taxpayer-dashboard.native#L663),
and no `(profile, tax year, form revision)` setup aggregate in the v10 schema
beginning around
[`src/tax_profile/store.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/tax_profile/store.zig#L8260).

Current form context can choose a filing activity or spouse, but those choices
become durable only inside an immutable filing draft. They cannot be reused as
annual setup. Draft persistence also hardcodes `tax_profile` provenance and
rejects unknown provenance in
[`src/forms/persistence_adapter.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/forms/persistence_adapter.zig#L681).

Most importantly, the existing UX specification says “not necessary — do not
build them” in
[`TAXPAYER_SETUP_UX_SPEC_2026-08-04.md`](TAXPAYER_SETUP_UX_SPEC_2026-08-04.md#13-form-requirement-and-override-specification).
That decision is superseded by the current request.

The safe new layer is **not** a free-form override table. It is a generated,
typed annual setup contract that:

- inherits canonical taxpayer facts read-only;
- saves only stable form/year selections and reusable defaults;
- never stores transaction amounts, schedules, penalties, payments, or
  calculated fields; and
- is snapshotted with exact provenance when a filing draft is created.

### D. Base identity and conditional fields are not modeled coherently

The requested universal base contract is:

- local profile name/label;
- TIN;
- RDO;
- taxpayer subject kind;
- taxpayer or registered legal name;
- registered address;
- ZIP code;
- contact number; and
- registered email address.

The local profile label is application metadata. It may default to the legal
name, but it must not be the legal filing value or the durable relational key.
Current storage has no separate stable display label and effectively conflates
the two concepts.

Individual capabilities are always rendered in
[`src/pages/profile-setup.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/pages/profile-setup.native#L453).
For legal entities they are disabled rather than hidden. Business Registration
is also always rendered near line 507. Trade Name is shown only for sole
proprietors, while the domain rejects it for legal entities. Business
activities are accepted regardless of subject kind, and changing subject kind
immediately clears buffers that become inapplicable.

There is no single subject/classification policy consumed by rendering,
validation, clearing, persistence, and form projection. That is the root cause
of the screenshot where Corporation still shows Individual capabilities.

The first policy matrix must establish at least:

| Field group | Applicable subjects/classifications |
| --- | --- |
| Universal base | every taxpayer profile |
| Birth date, citizenship, foreign TIN | natural person only |
| Individual tax classification | natural person only |
| Trade/business name | self-employed, mixed-income, sole proprietor, and applicable business/legal entities |
| Registered business activities / Line of Business | self-employed, mixed-income, sole proprietor, and applicable business/legal entities; hidden for pure compensation without activity |
| Incorporation/registration facts | applicable legal entities |
| Estate/trust facts | matching legal kind only |

Changing classification must stage potentially inapplicable values until Save
or an explicit confirmation; it must not silently destroy saved facts.

### E. Missing-detail warnings are misplaced and can use the wrong year

The “details are missing for your active forms” card is rendered inside Tax
Profile near
[`src/pages/profile-setup.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/pages/profile-setup.native#L279).
The calculation reads `calendar.selected_year` rather than the open
Registration & Forms year near
[`src/main.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/main.zig#L3678), and it reads mutable editor buffers
rather than the persisted effective revision.

Therefore it can:

- describe a different year from the year being configured;
- disappear because of unsaved typing; and
- imply that form-specific setup belongs in the base profile.

ZIP, contact, and registered email remain universal base fields as requested.
The correction is about ownership and presentation:

- universal validation belongs to Edit Tax Profile;
- each active form card and Tax Form Profile page owns its readiness summary;
- a form missing a shared base fact says, for example, `Missing taxpayer ZIP`
  and links to Edit Tax Profile;
- a form-specific setting is completed on that form's annual profile; and
- no canonical fact is copied into the annual form-profile rows.

### F. Catalog coverage is incomplete and sometimes wrong

The current generator truthfully reports what the Native markup declares, but
the markup has not been reconciled against complete official/legacy form
headers. Initial cross-checks found:

| Form | Current issue | Correct ownership direction |
| --- | --- | --- |
| 0605 | Omits recurring contact header fields and classifies ATC/tax type as required shared profile facts | Full base header inherited; ATC and tax type remain payment-specific unless official evidence proves a reusable default |
| 0619E/F | Omits Line of Business, address, ZIP, contact, and email mappings | Base/contact inherited; activity selected where the form needs it |
| 1601C | Omits ZIP and email | Base/contact inherited |
| 1701/1701Q | Inconsistent activity/contact coverage; annual election is not a first-class taxpayer/year fact | natural-person facts inherited; annual election taxpayer/year-owned; activity and spouse bindings in Tax Form Profile |
| 1702RT/MX | Omits ZIP, incorporation date, contact, and email | base/contact inherited; entity facts conditional; accounting choices classified deliberately |
| 2550Q | Catalog currently exposes only TIN/RDO/name | full base header inherited; EOPT/registration facts classified separately |
| 2551Q | Seven-field header is correctly bounded | explicit inherited-only/no-setup contract; Schedule 1 remains filing-owned |

This table is an initial defect inventory, not certification of every control.
All 10 supported editor revisions need a signed-off ownership matrix before
annual-profile persistence is implemented. The 41 `calendar_only` forms do not
have editor contracts and must not pretend to have editable Tax Form Profiles.

### G. Activation/effectivity semantics are only partially wired

Date-scoped Forms Set resolution exists near
[`src/tax_profile/store.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/tax_profile/store.zig#L2752), but form
availability and calendar caching still use year-only resolution near
[`src/tax_profile/ui_state.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/tax_profile/ui_state.zig#L2683).
The UI itself acknowledges that deadlines continue following yearly setup.

The `From a date` control currently records history without reliably changing
all downstream availability. Before release, one of two decisions is required:

1. wire date-aware resolution into card visibility, editor launch, calendar,
   export, and new-draft guards; or
2. temporarily remove `From a date` and support whole-year activation only.

Leaving the half-contract visible is not acceptable.

### H. Domain shapes exceed editor capability

The domain permits multiple effective business activities and independently
effective registration facts, but the editor rejects revisions with repeated
activities/facts or component periods that differ from the enclosing revision.
It also models only a narrow registration-fact set and rejects overlapping
facts of the same kind, even though a taxpayer can hold multiple simultaneous
registered obligations.

The plan must preserve the good effective-dated domain rather than flattening
it to match the current editor. The UI and adapters should grow to support:

- multiple activities;
- repeatable typed registration obligations;
- stable IDs used by form-profile bindings; and
- independently effective facts with truthful selection when ambiguous.

### I. Sidebar RDO should be removed

Only the selected sidebar row appends `RDO` in
[`src/components/shell.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/components/shell.native#L15), and the
display reads the editable RDO buffer near
[`src/main.zig`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/main.zig#L1789). It can therefore leak an unsaved
value and is inconsistent between selected and unselected rows.

Remove the sidebar RDO fragment. Keep RDO in the profile detail and relevant
filing contexts.

### J. Subject selected state is not a current blocker

The supplied screenshot reported a hover-only subject state. On the fresh
post-merge build, choosing Corporation produced both accessibility `selected`
state and visible selected styling. Current markup binds `selected` near
[`src/pages/profile-setup.native`](https://github.com/hexuria/formzero/blob/abd45c68da79af8f7fee007b6d19935bca14014f/src/pages/profile-setup.native#L370).

This specific issue is not reproducible after rebuilding and relaunching. It
still needs a desktop rendered-state regression test; if user testing finds
the contrast too subtle, add a check indicator or stronger selected token.
Do not remove the existing binding or file it as currently absent.

## Legacy behavior: copy, adapt, or reject

### Installed build 25

Its effective flat profile contains taxpayer name, TIN, RDO, Line of Business,
registered address, ZIP, phone, email, taxpayer type, VAT status, and a shared
date. It distinguishes individual classifications, including self-employed,
inside `Individual`; Line of Business is shown to everyone.

The sidebar has separate View and Edit actions. View opens the taxpayer
dashboard/Tax Form Library rather than a read-only Tax Profile detail, so the
requested detail view is still new work.

Build 25 derives applicable forms from profile facts and the selected year. It
has no explicit Forms Set, no activation/deactivation UI, and no annual Tax
Form Profile. Its registry contains 35 form definitions, and the dashboard
renders the applicable subset, but routing handles only 2551Q, 1701Q, and
1601C; other emitted actions silently do nothing.

Its 2551Q path demonstrates a valuable snapshot rule: profile headers are
copied when a draft starts, editable 2551Q draft headers may be refreshed
deliberately, and submitted 2551Q returns remain frozen. The 1701Q and 1601C
launch paths do not prove the same lifecycle. Its persistence should not be
copied: profile content is stored as a flat JSON blob; drafts and related
records identify the taxpayer by TIN; annual `NULL` periods can duplicate; and
monthly forms reuse a quarter column.

### Later legacy checkout

The current `/bir` source adds reusable Forms Set machinery worth adapting:

- per-year active/inactive decisions;
- source and evidence provenance;
- fail-closed active filtering;
- manual-decision history;
- reconciliation that preserves manual decisions;
- atomic persistence; and
- support/fileability distinctions.

Its Profile Manager remains edit-only: sidebar View opens the dashboard, while
Edit opens Profile Manager. That editor renders immediate checkboxes, shows
Trade Name too broadly in COR editing, requires Line of Business globally,
and keeps Save enabled when clean.

### Adaptation decision

| Copy/adapt | Build new | Do not copy |
| --- | --- | --- |
| Separate View/Edit intent | True read-only Tax Profile detail | Flat profile JSON |
| Profile-to-form projection | Explicit Registration browse/manage state | TIN as relational identity |
| 2551Q snapshot/freeze pattern | Annual typed Tax Form Profile | Automatic inference as filing authority |
| Per-year Forms Set provenance/history | Readiness per active form | Birth date/business-start aliasing |
| Reconciliation preserving manual decisions | Stable role/activity/obligation bindings | Immediate checkbox editing |
| Support/fileability gating | Profile/form-profile provenance in drafts | Always-enabled Save |
| Dirty snapshots from later checkout | Explicit prior-year copy review | Unsupported cards that silently do nothing |

## Correct field ownership

| Owner | Values |
| --- | --- |
| Local profile metadata | stable opaque profile ID; local profile label/name |
| Universal taxpayer profile | TIN, RDO, subject kind, taxpayer/legal registered name, registered address, ZIP, contact number, registered email |
| Subject-conditional profile | natural-person birth date/citizenship/foreign TIN; applicable trade name; business start/incorporation facts; estate/trust facts |
| Effective registration | repeated activities, registered tax-type set, VAT/percentage status, withholding categories, government/private agent status, EOPT tier, registration status, special-law/treaty basis |
| Taxpayer-year settings | elections shared across multiple forms, such as the annual income-tax election; fiscal/calendar basis where it truly applies taxpayer-wide |
| Forms Set | whether a form revision is active for the taxpayer/year and, if supported, its effective interval and evidence |
| Tax Form Profile | stable role/activity/obligation/spouse/representative selections and genuinely form-specific reusable defaults for one form revision and tax year |
| Filing transaction | period, amendment status, relief choice, amounts, schedules, credits, payments, penalties, attachments, and overpayment disposition |
| Calculated/display | totals, tax due, deadlines, rate-derived lines, calculated attachment counts |
| Artifact/signature evidence | actual signature/authorization/certification, receipts, submitted payload, and immutable filing evidence |

Annual taxpayer elections consumed by several returns must not be copied into
multiple Tax Form Profiles. 2551Q Schedule 1 and 0605 payment ATC/tax type must
not be promoted to shared profile data merely because they appear repeatedly.

## Required user-visible end state

### Tax Profile

- Read-only saved profile by default.
- One Edit Tax Profile action.
- Universal fields always shown.
- Entire inapplicable sections hidden, not disabled clutter.
- Clean edit actions disabled; dirty Cancel restores; Save appends a revision.
- No aggregate active-form warning card on this page.

### Registration & Forms

- Tax year is explicit.
- Browse mode shows active cards only, without checkboxes.
- Each supported active editor card shows readiness and View/Edit Tax Form
  Profile.
- Calendar-only active forms say `Calendar only — no form profile available`.
- Manage Forms is explicit; only that mode shows all cards and checkboxes.
- Activation/deactivation is staged, dirty-aware, and preserved by year.

### Tax Form Profile

- Read-only by default with form code/title, exact form revision, tax year,
  activation status, and readiness.
- Inherited taxpayer details are visible but not duplicated or edited here.
- Edit mode contains only generated form/year setup fields.
- 2025 and 2026 can differ without mutating each other.
- Inactive forms cannot start new setup or drafts, while history remains
  readable.
- A new filing snapshots the exact taxpayer revision, annual form-profile
  revision, and selected components; later changes never mutate that draft.

## Audit conclusion

At `abd45c6`, the page was not salvageable by merely hiding two sections and
adding one button. The safe path was to preserve the existing opaque profile
IDs, effective revisions, named-role projection, Forms Set history, and
immutable draft snapshots, then add explicit UI modes and a narrowly typed
annual form-setup layer. The execution branch implements that replacement path
and passes the recorded workflow acceptance gates, subject to the explicit
same-anchor segmented-history P1 and the separate official filing/legal gates.
