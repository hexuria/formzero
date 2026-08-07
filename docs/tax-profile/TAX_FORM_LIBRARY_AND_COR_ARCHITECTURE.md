# Tax Form Library, Forms Set, and COR-assisted Profile Setup

Status: implemented yearly Forms Set baseline; COR workflow remains follow-up  
Repository baseline reviewed: `main` at `895415d` on 2026-08-01

> Filing-scope clarification (2026-08-07): Forms Set is the user's persisted
> workspace preference for what the product surfaces. It is not registration
> evidence and cannot create, hide, or prove a legal Filing Obligation. The
> [multi-branch guide](TIN_BRANCH_PROFILE_AND_FILING_GUIDE_2026-08-07.md) and
> [revised implementation plan](TIN_BRANCH_IMPLEMENTATION_PLAN_2026-08-07.md)
> control where this document discusses taxpayer identity, Branch Codes,
> Registration Units, or filing scope.

The yearly Forms Set and profile-calendar consolidation described in the
2026-08-04 implementation is now the UI contract: yearly sets are created
once, edited from Profile Settings → Tax Forms, and filtered into the profile
Calendar by deadline taxable year. The historical design notes below remain
useful for the COR workflow, but older references to a raw Forms Set field or a
Tax Form Library management entry point are superseded.

## Purpose

This document defines how one user can maintain multiple taxpayer profiles,
choose which form workspaces to surface for each profile, browse and filter the
Tax Form Library, and optionally populate profile facts and form registrations
from an uploaded BIR Certificate of Registration (COR).

The intended product flow is:

1. A taxpayer profile can exist with only its minimum identity, initially the
   TIN plus an internal profile ID.
2. The user can upload a COR and review extracted profile facts and suggested
   forms.
3. If no usable COR is available, extraction fails, or the recommendation is
   incomplete, the user can manually choose forms from the full catalog.
4. Only user-confirmed data becomes authoritative profile data or an active
   Forms Set.
5. The active Forms Set controls that profile's Tax Form Library and profile
   calendar, while the Global Dashboard and global calendar remain unfiltered
   by any taxpayer profile.

## Core decision

A form is not a tax profile. Do not create one copy of a taxpayer profile for
2551Q, another for 1702Q, and another for every later form.

Use these separate concepts:

```text
Application user/account
  └─ Taxpayer profile (stable taxpayer or registration identity)
       ├─ Effective-dated profile revisions and shared facts
       ├─ COR documents, extraction runs, and evidence
       ├─ Effective Forms Set for each tax year/date
       └─ Form workspaces and immutable filing snapshots
```

The base tax profile answers, "Who is the taxpayer?" The Forms Set answers,
"Which form workspaces should this user see?" A Resolved Filing Plan answers,
"What is the evidenced obligation, filing unit, and return coverage for this
period?" A form workspace answers, "What is being prepared for this filing
period?"

This separation avoids duplicated TIN, name, address, RDO, registration, and
contact data drifting between form-specific copies of the same taxpayer.

## Identity and lifecycle rules

### Minimum profile

- The minimum user-facing identity is a TIN.
- The database must still assign an opaque, stable `profile_id`; never use the
  TIN as a mutable primary key.
- Branch code or registration-location details should be captured when known.
- Profiles must be scoped to their owning user/account. A profile selection or
  extraction result from one user must never appear for another user.
- The user can save multiple taxpayer profiles in the same application.

### Revisions versus new profiles

Changes must be classified by identity rather than by form:

| Change | Recommended treatment |
| --- | --- |
| Non-VAT to VAT under the same taxpayer/TIN | New effective-dated profile revision and Forms Set revision |
| Address, RDO, trade name, or registration-fact update | New profile revision |
| A different set of required forms next year | New Forms Set for that tax year |
| A form becomes applicable or stops mid-year | New effective-dated Forms Set revision |
| Sole proprietor becomes a corporation with a different legal taxpayer/TIN | New taxpayer profile, optionally linked as predecessor/successor |
| Historical form draft already exists | Retain its immutable profile snapshot; never refresh it silently |

A change from sole proprietorship to corporation should not mutate the old
profile when it creates a new legal taxpayer identity. The prior profile and
its filings must remain historically correct.

## Current repository state

The repository already contains important foundations:

- The generated catalog contains 51 registered form codes.
- Ten form codes currently have Native editor layouts; 41 are explicitly
  `calendar_only` and must not be represented as fillable forms.
- `src/tax_profile/store.zig` persists per-profile, per-tax-year Forms Sets
  through insert-only `createFormSet`, atomic `updateFormSet`, and the existing
  compatibility helpers.
- The store preserves three distinct states: no configured row, configured
  non-empty, and configured empty.
- `src/tax_profile/ui_state.zig` uses the Forms Set for form availability.
- `src/pages/profile-setup.native` exposes newest-first yearly Forms Set cards
  and a create/edit flow backed by the full catalog manager.
- `src/pages/taxpayer-dashboard.native` renders active forms as cards and
  opens exact filing periods in their form workspace.
- The profile calendar is bounded by the authoritative yearly Forms Set; an
  unconfigured year is not offered by its searchable year picker.
- Global calendar rules, resolved deadlines, and SQLite overrides are global.
  The Global Dashboard form picker is a global display filter and must stay
  independent from the selected taxpayer profile.

The primary missing product surface is a catalog-backed, profile-scoped Forms
Set editor and the COR ingestion/review workflow.

## Forms Set semantics

The authoritative key is conceptually:

```text
owner/account + profile_id + tax year + effective interval
```

Each active entry identifies at least:

```text
form_code + form_revision
```

It should also retain provenance such as manual selection, confirmed COR
extraction, import, or migration.

### Recommended states

The product should distinguish these states explicitly:

| State | Meaning |
| --- | --- |
| `needs_configuration` | A new minimum profile exists, but its forms have not been chosen or confirmed |
| `proposal_pending` | Manual or COR-derived candidate changes exist but are not authoritative |
| `active_nonempty` | The confirmed Forms Set contains one or more forms |
| `active_empty` | The user deliberately confirmed that no forms apply |
| `legacy_catalog_default` | Compatibility behavior for an existing unconfigured profile that currently falls back to all 51 codes |

For newly created minimum profiles, the recommended behavior is
`needs_configuration`, not silently activating all 51 forms. Existing profiles
that already depend on the catalog fallback can preserve that behavior through
an explicit compatibility state until the user reviews them.

Selecting zero forms and never configuring forms are not the same state.

### Effective dating

The existing store supports one set per profile and tax year. The long-term
model should also support effective intervals because registration obligations
can change during a year.

A Forms Set revision should include:

- `profile_id`;
- `tax_year`;
- `effective_from` and optional `effective_until`;
- status and revision sequence;
- source kind;
- optional COR document/extraction reference;
- user confirmation timestamp; and
- the selected form-code/revision entries.

Overlapping active intervals for the same profile and tax year must be rejected.

## Tax Form Library UX

The existing taxpayer dashboard tabs should remain:

- Calendar;
- Tax Form Library.

The profile settings surface should retain its profile-specific tabs:

- Tax Profile;
- COR;
- Email Settings.

Do not add a global Form Catalog action. Form activation belongs to the current
taxpayer profile.

### Library header

The Tax Form Library should show compact, inline controls rather than padded
containers:

- selected tax year or as-of date;
- search field;
- filter control;
- active count, for example `2 of 51 active`;
- Forms Set management is reached through Profile Settings → Tax Forms.
- Add to Calendar is available only in the profile Calendar tab.

On a phone, profile settings and form-management actions should live in the
existing compact action button/menu rather than consuming header width.

### Library views

The default view shows forms active for the selected profile and period. A
management view lists all 51 catalog forms so the user can change the Forms Set.

Useful filters include:

- Active, inactive, or all;
- form code or title search;
- tax type/category;
- filing frequency;
- editor available versus calendar-only; and
- suggested by COR, confirmed, or manually selected.

Each row should show:

- checkbox or selection control while managing;
- form code and title;
- filing frequency/category;
- active/inactive state;
- `Editor available` or `Calendar only` capability;
- missing profile-data warnings when applicable; and
- provenance such as `Confirmed from COR` or `Selected manually`.

`Calendar only` means the form can participate in deadlines and calendar
exports but does not have an implemented editor. It must not expose a misleading
`Open Form` action.

### Editing behavior

- Changes are staged in memory until the user selects Save.
- Save replaces the Forms Set atomically.
- Cancel restores the persisted set.
- `Select all` and `Clear all` are scoped to the current profile and period.
- Clearing all must explain that the profile library and profile deadlines will
  be empty; it must not silently restore the catalog fallback.
- `Reset to catalog default` is a separate compatibility action.
- Deactivating a form prevents new form workspaces for that effective period but
  does not delete historical drafts or filed artifacts.
- Switching taxpayer profiles clears every transient selection and search state
  that could expose the previous profile's information.

The raw comma-separated Forms Set input is removed from the end-user UI.
Profile Settings shows newest-first yearly summaries and opens a scoped full
catalog manager for the selected year. Duplicate years are rejected before a
new manager is opened, and the store's insert-only path remains the final
concurrency guard.

## COR-assisted setup

The Certificate of Registration is the evidence document. OCR is one possible
extraction mechanism, not the source of authority.

### Entry points

Support two profile-scoped entry points:

1. `Create profile from COR` when the user has not yet created the taxpayer.
2. `Upload updated COR` from the selected profile's COR tab or Tax Form Library.

An upload initiated for one profile must never update another profile.

### Extraction pipeline

Use a layered pipeline:

```text
Validate file
  → preserve immutable original and hash
  → extract embedded PDF text when available
  → run OCR for scanned/image pages
  → parse known COR labels and tables deterministically
  → optionally use AI to normalize or interpret ambiguous content
  → map tax types/frequencies to candidate catalog forms
  → present candidates for user review
  → commit only confirmed changes
```

Text extraction should precede OCR because digitally generated PDFs may already
contain reliable text. AI is a fallback/normalization layer and must not be the
only path.

### Candidate profile facts

Depending on the COR revision and legibility, extraction may propose:

- TIN and branch code;
- registered taxpayer/legal name;
- trade name;
- taxpayer or entity type;
- registered address;
- RDO code;
- registration/effectivity date;
- line of business or registered activities;
- VAT or non-VAT registration facts;
- withholding/tax-type registrations;
- filing frequency; and
- visible form codes.

Not every COR exposes every field, and a tax type does not always map one-to-one
to a form code. The mapping layer must therefore return candidates with reasons,
not fabricated certainty.

### Candidate forms

Form recommendations can come from:

1. an exact form code visible in the COR;
2. a versioned deterministic mapping from tax type and filing frequency;
3. an AI interpretation that cites the underlying extracted text; or
4. a manual user selection.

Every recommendation should carry:

- normalized form code and revision when known;
- source page and bounding box or text span;
- raw extracted value;
- normalized value;
- extraction/mapping engine and version;
- confidence or ambiguity state; and
- reason for the recommendation.

AI-generated or OCR-derived suggestions must never activate forms automatically.

### Review screen

The review UI should have two independently selectable sections:

1. Profile information;
2. Suggested forms.

For each candidate, show the proposed value beside the current value and link
back to its source location in the COR. The user can accept, edit, or reject
each item.

Applying confirmed changes should be one application transaction:

1. retain the COR and extraction provenance;
2. create a new effective-dated profile revision for accepted shared facts;
3. create a new effective Forms Set revision for accepted forms;
4. link both revisions to the evidence; and
5. leave existing form snapshots and drafts unchanged.

If only forms are accepted, no unnecessary profile revision should be created.

### TIN mismatch

When the extracted TIN does not match the selected profile, fail closed. Offer:

- Create a new tax profile from this COR;
- Review the mismatch; or
- Cancel.

Never silently overwrite the selected profile or merge two taxpayer identities.

### Failure and fallback

If the document is unsupported, unreadable, partially extracted, or the user
declines AI processing, the manual 51-form picker remains fully usable.

The COR workflow may fail without blocking creation of a minimum TIN profile.

## OCR and AI boundaries

Define provider-independent interfaces rather than coupling profile state to a
particular OCR or AI vendor:

```text
CorDocumentRepository
DocumentTextExtractor
OcrEngine
CorFieldInterpreter
TaxTypeToFormMapper
CorProposalRepository
FormSetRepository
```

The OCR/AI layer returns structured candidates. Only the application service
that handles user confirmation may call profile-revision and Forms Set writes.

Cloud processing must be opt-in. The UI should disclose what document data will
leave the device, which provider will process it, and whether the provider
retains data. A local text/OCR path should remain available where practical.

## Proposed persistence additions

Exact names can follow project conventions, but the model needs these records:

```text
cor_documents
  id, owner_id, profile_id?, sha256, mime_type, page_count,
  encrypted_storage_reference, uploaded_at

cor_extraction_runs
  id, document_id, engine, engine_version, status,
  raw_text_hash, started_at, completed_at, failure_code

cor_extraction_candidates
  id, extraction_run_id, target_kind, target_key,
  raw_value, normalized_value, page, source_region,
  confidence, interpretation_reason

cor_review_decisions
  candidate_id, decision, confirmed_value, decided_by, decided_at

profile_form_set_revisions
  id, profile_id, tax_year, effective_from, effective_until,
  sequence, status, source_kind, source_document_id?, confirmed_at

profile_form_set_entries
  form_set_revision_id, form_code, form_revision,
  selection_source, source_candidate_id?
```

The current `tax_profile_form_sets` and entry tables can be migrated or wrapped
behind the existing store API. The first implementation should avoid rewriting
working persistence until the revised state model and migration tests exist.

## Calendar behavior

Keep activation, display preference, and global policy distinct:

```text
Global deadline rules + holidays + overrides
  → complete resolved global schedule

Global Dashboard picker
  → display filter over the global schedule

Profile Forms Set
  → forms legally/operationally active for that profile and effective period

Optional profile calendar display preference
  → further narrows the profile Forms Set; it can never add inactive forms
```

Therefore:

- The Global Dashboard and global Tax Calendar continue to expose the complete
  catalog schedule and ignore profile selection.
- The taxpayer dashboard calendar uses the global resolved schedule intersected
  with the selected profile's effective Forms Set.
- A profile calendar preference, if retained, is intersected again with the
  Forms Set.
- Calendar export from a profile follows the same bounded projection.
- Global rules and SQLite overrides remain global administrative data.

## Form workspace behavior

Opening a form should require:

1. the form is active for the selected profile and period;
2. an editor exists for that form revision;
3. the required profile roles/facts can be resolved; and
4. the resulting profile snapshot passes composition validation.

If profile data is incomplete, the library row should show `Complete profile`
and route to the missing facts rather than opening a broken editor.

At draft creation, copy the qualified profile revision and role bindings into an
immutable snapshot. Later COR imports, profile edits, or Forms Set changes must
not rewrite that draft automatically.

## Security and privacy requirements

COR files contain taxpayer identity and registration information. Treat them as
sensitive evidence:

- validate MIME type, file signature, size, and page limits;
- isolate document parsing and reject malformed inputs;
- encrypt originals and extracted text at rest where the supported local key
  provider permits it;
- keep document references scoped by owner and profile;
- hash originals for integrity and duplicate detection;
- record extraction engine/version and review decisions;
- do not put raw document text into application logs;
- require explicit consent before cloud OCR/AI processing;
- support deletion according to the product's evidence-retention policy; and
- ensure failed profile switches cannot expose prior candidates or files.

The current fail-closed production key-custody boundary remains authoritative.
This feature must not claim production-safe document storage until that gate is
actually satisfied.

## Implementation seams

Primary files and modules expected to change:

- `src/pages/taxpayer-dashboard.native`: catalog-backed library, filters, form
  management, capability/provenance statuses.
- `src/pages/profile-setup.native`: COR upload/review entry points and removal
  of the raw comma-separated Forms Set input.
- `src/tax_profile/ui_state.zig`: selected-profile/year state, staged Forms Set,
  fail-closed switching, proposal review, notices, and projections.
- `src/tax_profile/store.zig`: effective Forms Set revisions, COR metadata,
  candidates, review decisions, and migrations.
- `src/forms/generated/catalog.zig`: authoritative 51-form metadata consumed by
  the UI; it remains generated.
- `scripts/tax-catalog/catalog.ts`: add filter/display metadata only when it is
  genuinely catalog authority.
- `src/calendar/ui_state.zig`: intersect profile deadlines/export with the
  effective Forms Set while leaving global projections unchanged.
- `src/main.zig`: application messages, effects, and view projections.
- `src/security/`: document-storage and cloud-processing policy boundaries.

Continue editing source fragments and regenerate `src/app.native`; do not hand
edit the generated file.

## Execution plan

### Phase 1: lock domain semantics

- Confirm minimum profile identity and duplicate-TIN/branch rules.
- Add explicit Forms Set states and effective intervals.
- Define migration behavior for existing catalog-fallback profiles.
- Define form capability metadata and availability rules.

Exit: the domain can distinguish unconfigured, proposal, configured empty,
configured non-empty, and legacy fallback without relying on UI conventions.

### Phase 2: profile-scoped Forms Set editor

- Replace comma-separated entry with a catalog-backed staged selector.
- Add year/as-of selection, search, filters, counts, select all, clear all,
  Save, Cancel, and reset-to-default behavior.
- Drive Tax Form Library cards and form launch availability from the saved set.
- Preserve mobile action-menu behavior and compact spacing.

Exit: two profiles and two tax years can maintain independent selections across
restart, including explicit empty.

### Phase 3: calendar intersection

- Derive profile deadlines and export from the effective Forms Set.
- Bound any retained profile display preference by that set.
- Prove the Global Dashboard and global calendar remain unchanged.

Exit: enabling or disabling a profile form changes only that profile's library,
deadlines, and export.

### Phase 4: COR evidence ingestion

- Add validated upload, immutable local evidence reference, hashing, and status.
- Implement embedded-text extraction before OCR.
- Add deterministic COR field parsing with fixtures.
- Keep the feature usable without a cloud provider.

Exit: a COR can be uploaded, retained, extracted, retried, and reviewed without
mutating profile or Forms Set state.

### Phase 5: proposal review and atomic apply

- Present profile facts and form suggestions with page/source evidence.
- Handle TIN matches and mismatches explicitly.
- Persist review decisions and apply accepted facts/forms transactionally.
- Preserve historical drafts and profile snapshots.

Exit: only confirmed candidates affect authoritative state, with complete
provenance and rollback on failure.

### Phase 6: optional AI interpretation

- Add an opt-in provider adapter for ambiguous extraction/normalization.
- Require structured schema output and source grounding.
- Record provider/model/version and consent.
- Test that AI failures fall back to deterministic/manual workflows.

Exit: the application remains fully functional when AI is unavailable or
declined.

### Phase 7: hardening and UX verification

- Add authorization, malformed-file, concurrency, restart, and migration tests.
- Verify desktop, compact, and phone layouts with the project app only.
- Verify accessibility names, keyboard navigation, focus restoration, and
  screen-reader state for selection controls.
- Re-run generation, catalog drift, Native tests, strict check, and build.

## Acceptance scenarios

1. A user creates a TIN-only profile and manually enables 2551Q. Only 2551Q is
   active in that profile's library and profile calendar.
2. The same user creates a second profile and enables 1702Q. The selections do
   not leak between profiles.
3. One profile has 2551Q in 2026 and a VAT-related set in 2027. Switching years
   displays the correct independent set.
4. A registration change during a year creates a new effective set without
   rewriting earlier-period drafts or deadlines.
5. A COR suggests profile facts and forms, but nothing changes before explicit
   user confirmation.
6. A COR TIN mismatch cannot update the selected profile.
7. Failed OCR or declined AI processing still permits manual selection from all
   51 catalog codes.
8. A calendar-only form can produce profile deadlines but cannot open a form
   editor.
9. An explicitly empty Forms Set yields an empty profile library/calendar and
   never widens to all forms.
10. The global calendar remains complete and profile-independent throughout.
11. Switching profiles during extraction or editing cannot expose or save the
   previous profile's candidates.
12. Restarting the app restores confirmed Forms Sets, evidence status, and
   review state without treating proposals as authoritative.

## Decisions still requiring product confirmation

The architecture recommends defaults, but these choices should be confirmed
before implementation:

1. Whether new TIN-only profiles begin as `needs_configuration` with zero active
   forms, as recommended, or temporarily inherit all 51 forms.
2. Whether a Forms Set may change mid-year in the first release or only by tax
   year, with effective intervals added immediately afterward.
3. Whether the profile calendar needs an additional display-only filter after
   Forms Set activation, or should always show every active form.
4. Which local OCR engine is supported first on macOS and Windows.
5. Whether any cloud AI provider is permitted, and the exact consent,
   retention, and redaction requirements.
6. COR evidence retention/deletion policy after an extraction is confirmed.

## Next-session handoff

Start the next session by reading this file together with:

- `docs/tax-profile/ARCHITECTURE.md`;
- `docs/tax-profile/IMPLEMENTATION_PLAN.md`;
- `src/tax_profile/store.zig`;
- `src/tax_profile/ui_state.zig`;
- `src/pages/taxpayer-dashboard.native`;
- `src/pages/profile-setup.native`; and
- `src/calendar/ui_state.zig`.

Before coding, confirm the six product decisions above. Then implement the
smallest vertical slice: one selected profile, one tax year, a staged 51-form
picker, SQLite persistence, and a filtered Tax Form Library. COR ingestion and
AI should build on that authoritative manual path rather than bypass it.
