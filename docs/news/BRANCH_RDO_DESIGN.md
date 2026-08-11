# Per-branch RDO deadline verdicts — design

Backlog item 1 in [NEXT_STEPS.md](NEXT_STEPS.md): a Taxpayer gets one
profile-level RDO verdict covering every office. If a Registration Unit sits
inside a circular's scope while another sits outside, the calendar is wrong for
one of them.

**Recommendation: do not build it yet.** Registration Units cannot exist in the
same session as a saved Taxpayer Profile, so there is no data for a per-unit
calendar to read, and the Filing Scope needed to label a per-unit deadline
honestly is unresolvable by construction. Three upstream items must land first.
The target shape, for when they do, is a **Filing Unit picker driving one
scoped projection at a time** — not a union of every unit's extensions.

---

## a) Where Registration Units come from at calendar time

They do not reach calendar time at all. The chain from the calendar backwards:

- `selectedTaxpayerCalendarContext` (`src/main.zig`) builds
  `calendar_ui.TaxpayerContext` from `Model.selectedTaxpayerRdo()` and
  `selectedTaxpayerKind()`.
- `selectedTaxpayerRdo()` returns `taxProfiles.registeredRdoCode()`
  (`src/tax_profile/ui_state.zig`), which is `revision.identity.rdo_code` —
  the **Taxpayer Profile's** single registered RDO, a legacy v1-era column
  (`rdo_code TEXT NOT NULL` in the profile revision schema).
- `src/calendar/domain.zig` and `src/calendar/ui_state.zig` contain no
  occurrence of "branch", "unit", or any per-unit concept. The calendar has
  never seen a Registration Unit.

Registration Units live on a parallel, unreachable track:

- `Model.registrationLedger` is a `TaxpayerRegistrationLedger` over the same
  `profile_store.Store`, and `refreshRegistrationWorkspace` (`src/main.zig`)
  loads `registrationWorkspace` from it at startup.
- The unit tables — `taxpayer_registration_units`,
  `taxpayer_registration_unit_revisions`, and the contact-revision tables — are
  created by `schema_v28` only.
- `Store.openDevelopmentPlaintext`, the constructor a normal launch uses, is
  pinned to `.migration_ceiling = .normal_file` = `normal_file_schema_version`
  = **27** (`src/tax_profile/store.zig`, commit `0b8af9a` "keep TIN branch
  schema fixture-only"). A real user's `calendar.sqlite3` therefore **does not
  contain the unit tables**, and the workspace refresh fails into
  `reportLoadFailure()`.
- The only v28 store a launch can produce is
  `Store.openRegistrationFixturePreviewMemory`, reached solely when
  `EBIRFORMS_TIN_BRANCH_FIXTURE_PREVIEW=1` **and** an explicit data directory
  are both set (`requireRegistrationFixtureDataBoundary`). It is
  `openMemory` — the ledger is discarded when the process exits.

Two consequences settle the question:

1. **Registration Units never persist.** Not "preview-only data"; ephemeral
   data. Nothing a user creates in a fixture session is there on the next
   launch.
2. **Units and a saved profile are mutually exclusive.** In a fixture session
   the tax-profile store *and* the calendar store are both in-memory
   (`calendar_ui.persistence.Store.openMemory`), so there is no saved Taxpayer
   Profile, no persisted calendar policy, and no synced overrides to scope.
   Outside a fixture session there are no units. Additionally
   `registrationMutationGateForStore` requires `no_legacy_profiles` — a store
   holding even one legacy profile refuses unit creation with
   `legacy_profiles_present`.

So: **no**, units are not populated for a normally created profile, and cannot
be.

## b) What the calendar should show for a multi-unit taxpayer

CONTEXT.md makes this a Filing Scope question before it is a display question.
A **Per-Registered-Unit Return** ("a separate return for each Registration Unit
that holds the applicable Tax-Type Registration for the period") and a
**Head-Office-Consolidated Return** ("one return filed by the Head Office that
covers the resolved set of applicable Registration Units") are different
obligations. The **Filing Unit** — "the Registration Unit whose TIN Root and
branch code identify the filer on a return" — is what an RDO verdict attaches
to, and Filing Scope is what decides which units are Filing Units.

**Recommended: a Filing Unit picker, one scoped projection at a time.** The
selected Filing Unit's `rdo_code` becomes the calendar's RDO context; the
calendar shows that unit's deadlines with a caption naming the unit and, for a
consolidated form, its Return Coverage. This mirrors the dashboard's RDO
context (`globalDashboard.rdoContext()` / `applyGlobalRdoContext`) and the
preference persistence that just landed in `src/preferences/store.zig`, so the
interaction is one the app already teaches.

Why it wins: one projection is one filer, which is exactly what a return is. A
Head-Office-Consolidated Return produces one calendar (the Head Office's) and
says so; a Per-Registered-Unit Return produces one calendar per unit and the
user steps between them. Neither is blurred into the other. It also needs no
growth of the fixed-size projection arrays.

**Rejected — the union of every unit's extensions, labelled per unit.** It
blurs the two obligations the domain is deliberate about: for a
head-office-consolidated form it would render N deadline rows for **one**
obligation, inviting the reader to conclude each branch files. It also inverts
the fail-closed posture — a form whose Filing Scope is unresolved would appear
as a set of confident per-unit rows. Mechanically it is the expensive option
too: `State.deadlines` is `[256]DeadlineRow` and `State` is embedded three
times in `Model`, with `[max_deadlines]` parallel arrays in `Model`
(`profileDeadlineLaunchAssessments`, `...Ready`, `profileDeadlineRemediations`).
Multiplying rows by unit count re-runs the memory problem R1.2 already hit.

**Rejected — head office only, branches surfaced separately.** This is
today's behaviour plus a disclaimer. Worse, it asserts a Head Office where the
data has none: the legacy profile's `rdo_code` belongs to the **Taxpayer**, not
to a Registration Unit whose normalized branch code is all zeroes. Labelling it
"head office" would be a claim the store cannot support.

## c) What the resolver needs

**`TaxpayerContext` stays single-valued. Resolution runs once per Filing Unit.**

`overrideAppliesToContext` (`src/calendar/ui_state.zig`) is a scope-membership
test: does this record's region/RDO list contain the taxpayer's district. If
`rdo` became a set, "applies" would silently weaken to "applies to at least one
of your offices" — the union semantics rejected above, pushed down into the
resolver where no caller could opt out of it. Keeping the context single-valued
means every projection remains attributable to exactly one filer, and
`recomputeForTaxpayer` needs no change at all.

The seam that changes is one layer up: which RDO `selectedTaxpayerCalendarContext`
reads. Today it is the profile identity's; it would become the selected Filing
Unit's `RegistrationUnitRevision.rdo_code`, falling back to the profile
identity RDO when the taxpayer has no units — which preserves today's behaviour
exactly for the zero-unit and one-unit cases.

## d) Fail-closed behaviour

- **Unit with no confirmed RDO.** `RegistrationUnitRevision.rdo_code` is
  `?RdoCode3` and is explicitly allowed to be unknown on pre-transfer records.
  Such a unit must project with **no RDO context** — the unscoped nationwide
  schedule, the same thing an unsaved profile gets today — captioned that the
  district is not confirmed. It must never inherit the Head Office's district;
  that would be the "default branch" best guess CONTEXT.md names under Review
  Required.
- **Units disagreeing.** Not an error condition. Different districts for
  different units is the ordinary case and is why the picker exists; each unit
  gets its own projection.
- **Consolidated return whose coverage spans districts.** The Filing Unit's RDO
  decides, because the Filing Unit identifies the filer. The divergence is
  surfaced in the caption, not resolved silently, and not allowed to add
  deadlines from the branches' districts.
- **Filing Scope unresolved.** Today this is every form (see below). The
  calendar must fall back to the current taxpayer-level projection and must
  make no per-unit claim. A Review Required scope may not be rendered as a
  deadline verdict.

---

## What blocks it

Three upstream items, all outside `src/calendar` and all outside this feature:

1. **Legacy cutover.** `schema_v28` must be reachable on a normal file-backed
   store, which requires the reviewed Migration Decision path the migration
   inventory deliberately refuses to perform (`registration_migration_inventory.zig`:
   "This is deliberately not a migrator"). Until then, units are ephemeral and
   cannot coexist with a saved profile.
2. **A production policy catalog.** `registration_workspace.production_policy_catalog`
   is `&.{}` — deliberately empty, so `FilingPlanner.plan` returns Review
   Required rather than promoting the fixture. Without a Policy Revision for a
   form there is no Filing Scope, and without a Filing Scope a per-unit deadline
   cannot be labelled as either obligation.
3. **Planner support for registration-driven scope.** `src/filing/planner.zig`
   answers `.registration_driven` with `.unsupported_policy_category` →
   Review Required, and rejects every form revision other than
   `2550Q 2024-04-ENCS`. `per_registered_unit` exists in `src/filing/policy.zig`
   as a type and nowhere as behaviour;
   `registration_workspace.ResolvedScopeCategory` has exactly one member,
   `head_office_consolidated`. The one scope where a branch's own RDO changes
   the answer is precisely the one the planner cannot resolve.

Any per-unit calendar code written today would be guarded by a condition that
cannot be true in a production session — dead code shipped against data that
does not exist.

## Effort

- **Upstream (1)–(3):** large, evidence-gated, and already tracked as blocked
  in the README status table. Not estimated here.
- **The calendar work itself, once unblocked:** roughly 2–3 days.
  - `src/tax_profile/ui_state.zig` — expose the selected taxpayer's
    Registration Units and their effective `rdo_code`s, beside the existing
    `registeredRdoCode()`.
  - `src/main.zig` — Filing Unit selection state and messages mirroring
    `selectGlobalRdoContext` / `clearGlobalRdoContext`;
    `selectedTaxpayerCalendarContext` reads the selected unit's RDO, falling
    back to the profile identity RDO when there are no units; caption text.
  - `src/preferences/store.zig` — a second preference record for the selected
    Filing Unit, following `RdoContextPreference`'s tri-state.
  - `src/pages/*.fragment` — the picker, which means `just generate` and all
    five regenerated shards in the same commit.
  - `src/calendar/ui_state.zig` — unchanged.

## Smallest honest thing available now

None in `src/`. The accurate statement — that the RDO verdict covers the one
district recorded on the Taxpayer Profile and the app does not yet model a
Taxpayer with offices in more than one district — belongs in the README status
table beside the existing synced-overrides caveat, not in a UI caption that
would have to name a Head Office the store cannot prove.
