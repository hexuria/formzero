# Tax Profile and Tax Form Profile Ownership Matrix

Date: 2026-08-04; simplified 2026-08-05
Status: current simplified ownership contract
Scope: exact-revision metadata for the supported Native editors

> The activity/obligation-anchor pilot described in the historical review
> below was rejected and removed on 2026-08-05. Forms Set activation is the
> authority for form availability. Historical Registration rows remain
> readable only by the migration/export boundary and are not normal setup or
> readiness inputs.

## Decision

The current 16-key `ReusableField` vocabulary is too coarse to decide where a value is edited. A field appearing on a BIR form does not by itself make that value a base tax-profile field or a tax-form-profile setting.

The implementation uses four product ownership layers:

| Code | Owner layer | Rule |
|---|---|---|
| `P` | Base Tax Profile | Effective-dated taxpayer identity, contact, accounting basis, EOPT tier, and Primary Line of Business. |
| `S` | Tax Form Profile | A genuine form-revision/year value. It never duplicates inherited Base fields. |
| `D` | derived filing context | Tax year, selected quarter/month, and return period derived from the selected filing tile and Base accounting basis. |
| `T` | filing transaction | Per-return inputs, schedule rows, amounts, calculations, artifacts, and filing state. |

The preexisting taxpayer-year settings module remains only for the current
1701/1701Q consumers until those exact revisions are audited. 2551Q does not
consume it.

### Catalog implementation result

The generator now joins every discovered Native input to exact stable-ID
metadata in `scripts/tax-catalog/catalog.ts`. Labels and placeholders are no
longer ownership, role, value-type, or profile-key authority. A missing or
stale declaration fails generation.

The first ownership review reduced direct profile targets from 72 to 65. The
execution pass then restored 26 inherited header controls proven by the legacy
constructors, bringing the generated catalog to 91 profile targets. Those new
targets remain optional until the exact official revision proves legal
requiredness:

- 0605: ZIP, contact number, and email;
- 1601C: ZIP and email;
- 0619E: taxpayer name, line of business, address, ZIP, contact, and email;
- 0619F: line of business, address, ZIP, contact, and email;
- 1702RT and 1702MX: ZIP, contact, and email; and
- 2550Q: address, ZIP, contact, and email.

The reviewed ownership corrections also establish that:

- 0605 ATC and tax type are filing transactions;
- 0605 Line of Business / Occupation is filing-owned; a UI may offer Base
  Primary Line of Business as an editable convenience, but no Registration
  activity is selected or persisted for the form;
- 1601C ATC is exact-revision form policy `WW010`;
- 0619F tax type is exact-revision form policy `WB`;
- 0619E ATC and tax type are exact-revision form policy `WME10` and `WE`;
- forms that display Line of Business inherit the Base Tax Profile's Primary
  Line of Business directly; no activity selection is stored per form;
- 1701 and 1701Q retain their existing taxpayer-year settings temporarily;
  2551Q owns `income_tax_rate_election` in its generic Tax Form Profile; and
- ATC rows and other return-specific business details remain filing
  transactions unless an exact revision proves a different owner.

### Current-branch ownership/runtime disposition — 2026-08-04

The reviewed pre-correction 72-target table below remains the historical input
to this decision. It is not being relabeled as though those original mappings
were always correct. The current execution branch applies the corrected
ownership through these concrete boundaries:

| Boundary | Current source disposition |
| --- | --- |
| Base/effective profile (`P`/`D`) | Universal identity/contact values are stored once and inherited read-only by form setup. `src/tax_profile/applicability.zig` supplies the shared subject/classification policy for conditional personal, Trade Name, and business sections. |
| Historical Registration | Legacy activity/obligation rows are isolated behind read-only migration/export storage. They do not participate in current setup, projection, readiness, or filing launch. |
| Taxpayer-Year compatibility | `src/tax_profile/taxpayer_year_settings.zig` remains only for the current 1701 and 1701Q consumers. 2551Q has no taxpayer-year dependency. |
| Tax Form Profile (`S`) | `src/tax_profile/tax_form_profile.zig` owns append-only profile/year/form/form-revision setup revisions. The generated spec controls semantic keys, roles, value types, source kinds, validation, setup/no-setup mode, revision, and deterministic SHA. History, reactivation, copy/review, and optimistic conflicts are retained rather than overwritten. |
| Shared binding resolution | `src/tax_profile/tax_form_profile_binding_resolver.zig` resolves only genuine saved form values and named profile roles. Activity and obligation anchors are not supported setup values. |
| Copy migration | The schema v20 migration rebuilds Tax Form Profile copy provenance so the source foreign key identifies the retained source form revision and source revision, including cross-form-revision copies; it does not rewrite setup values into the target contract. |
| Draft provenance | Immutable provenance records the exact Base Tax Profile, applicable taxpayer-year compatibility revision, Tax Form Profile, Forms Set decision, generated catalog, and copied values. New provenance contains no Registration components or anchors. |
| Filing transaction/artifact (`T`/`C`) | Amounts, schedules, filing choices, calculated values, signatures, artifacts, and submission state remain outside Tax Profile, Taxpayer-Year, and Tax Form Profile. Card `Editor available` is not a fileability claim. |

Final package/test/live evidence remains authoritative in the execution plan,
not duplicated or inferred from this matrix. The
[final workflow acceptance evidence](TAX_PROFILE_AND_FORM_PROFILE_EXECUTION_PLAN_2026-08-04.md#final-workflow-acceptance-evidence--2026-08-04)
records the final catalog and gate counts, exact package/hash/PID, and successful
Computer Use plus Native readiness/navigation replays. Ownership-specific live
proof for the simplified branch must include inherited Base facts, direct Base
Primary Line of Business projection, year-scoped 2551Q setup, revision history,
and exact return to Forms Set. The earlier selected-Registration-activity proof
belongs only to the rejected pilot and is not evidence for the current product
contract.

The 91-target census is a source-ownership result, not proof of legal
requiredness, official print/XML fidelity, successful submission, or
production readiness.

### Requiredness rule

`required` in the generated catalog currently means “projection blocks when this catalog target is absent.” It is not sufficient evidence that the BIR legally requires the field for every allowed taxpayer kind. Base-profile Save must validate the base-profile contract only. Exact-form readiness must be shown on the active form card for the selected tax year, never as an unfixable active-form warning on the base Tax Profile view.

### Taxpayer-kind codes

| Code | Applicability |
|---|---|
| `K-ALL` | `individual`, `sole_proprietor`, `corporation`, `partnership`, `estate`, `trust`, `other_legal_entity` under the current catalog. |
| `K-IET` | `individual`, `sole_proprietor`, `estate`, `trust`; the current income-tax-form policy. |
| `K-PERSON` | Natural person only: `individual` or `sole_proprietor`; never a corporation, partnership, estate, trust, or other legal entity. |
| `K-ENTITY` | `corporation`, `partnership`, or `other_legal_entity`. |
| `K-ACTIVITY` | A filer for whom Base Primary Line of Business applies. Normally self-employed/mixed-income individuals and business entities; not purely-compensation individuals. Estate/trust applicability requires source evidence. |
| `K-SPOUSE` | A separately selected natural-person spouse profile. |
| `K-SPECIAL` | A filing for which the exact form revision owns a special/preferential-rate basis value. |
| `K-0605-LOB` | The activity/occupation truth for the liability paid by this particular 0605 filing; official semantics remain an evidence gate. |

The current product policy now separates legal subject kind from the natural-person filing classifications purely compensation, self-employed, and mixed income, and the conditional UI is implemented from that shared policy. The remaining legal taxonomy and official requiredness questions are evidence-gated; they must not be resolved by silently changing saved subject identity or inventing form values.

## Canonical base/effective profile contract

These are the fields the Tax Profile view owns. They are independent of whether any form is active:

| Field | Applicability | Storage rule |
|---|---|---|
| TIN | all profiles | Stable identity; ordinary revisions must not silently change it. |
| RDO | all profiles | Effective-dated registration identity. It belongs in the profile detail, not the sidebar profile card. |
| Taxpayer subject kind | all profiles | Canonical legal-person kind; reconcile with taxpayer classification before implementation. |
| Taxpayer or registered name | all profiles | Store in the truthful subject variant; derive form-specific `taxpayer_name` or `registered_name`. |
| Registered address | all profiles | Effective-dated contact. |
| ZIP code | all profiles | Effective-dated contact. |
| Contact number | all profiles | Effective-dated contact. |
| Registered email address | all profiles | Effective-dated contact. |
| Taxpayer classification | applicability-dependent | Separate from legal subject kind; individual choices include purely compensation, self-employed, and mixed income. |
| Trade name | self-employed/mixed or registered business entity only | Conditional subject/business fact; never render for a purely-compensation individual. |
| Birth date, citizenship, foreign TIN | natural person only | Hide, do not merely disable, for corporations and other non-natural persons. Foreign TIN is conditional on foreign-tax applicability. |
| Calendar/Fiscal basis and fiscal year-end month | all profiles | Effective-dated Base accounting context. The month is present only for Fiscal. |
| EOPT tier | applicable taxpayers | Effective-dated Base value; exact manifests decide whether a form consumes it. |
| Primary Line of Business | self-employed, mixed-income, and applicable entities | One effective-dated Base value projected directly into exact revisions that contain the field. ATC is not inferred from it. |

Current model evidence: `src/tax_profile/model.zig:68-78`, `src/tax_profile/model.zig:80-175`, and `src/tax_profile/model.zig:177-230`. Prior-app comparison: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/profile.rs:8-55`, `:153-166`, `:216-234`, and `:409-555`; conditional UI evidence is `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-desktop/src/views/profile_manager/tab_tax_profile.rs:23-36` and `:70-193`.

## Tax-form setup contracts

`setup` means the form revision declares at least one typed setup key. It does
not authorize an empty database row: if all settings resolve automatically and
the user has made no explicit selection, persist no setup record. `no_setup` is
an explicit contract, not an unfinished screen. Every active Forms Set entry,
including `no_setup` and calendar-only entries, exposes a Tax Form Profile
action. For forms without setup, that action opens inherited Base details
read-only; “no editor” below means no Tax Form Profile edit control, not no
view action.

| Form revision | Contract | Tax-form setup owns | Tax Form Profile card behavior |
|---|---|---|---|
| 0605 1999-07-ENCS | `no_setup` | Nothing. ATC, tax type, and liability-specific line of business/occupation belong to the filing. | Show inherited Base details read-only and explain the filing-owned fields; no Edit button and no setup row. |
| 1601C 2018-01-ENCS | `no_setup` | Nothing. The exact revision's Line of Business is inherited directly from Base Primary Line of Business. | Show inherited Base values read-only; fixed ATC `WW010` remains read-only form policy. No Tax Form Profile editor is needed. |
| 0619E 2018-01-ENCS | `no_setup` | Nothing. The exact revision's Line of Business is inherited directly from Base Primary Line of Business. | Show inherited Base values read-only; fixed ATC and tax type remain read-only form policy. No Tax Form Profile editor is needed. |
| 0619F 2018-01-ENCS | `no_setup` | Nothing. The exact revision's Line of Business is inherited directly from Base Primary Line of Business. | Show inherited Base values read-only; fixed tax type and item ATCs remain read-only form policy. No Tax Form Profile editor is needed. |
| 1701Q 2018-01-ENCS | `setup` | `spouse_profile_id` only. | Edit only the genuine spouse-profile role binding. Existing taxpayer-year settings remain a separate compatibility source and are not duplicated in this Tax Form Profile. |
| 1701 2018-01-ENCS | `setup` | `spouse_profile_id` only. | Edit only the genuine spouse-profile role binding. Existing taxpayer-year settings remain a separate compatibility source and are not duplicated in this Tax Form Profile. |
| 1702RT 2018-01-ENCS | `no_setup` | Nothing. The exact revision's Line of Business is inherited directly from Base Primary Line of Business. | Show inherited Base values read-only; no Tax Form Profile editor is needed. |
| 1702MX 2018-01-ENCS | `setup` | `special_rate_basis` only. | Edit the plain form-specific special-rate basis. It does not reference a Registration obligation; schedule rates and amounts remain filing transactions. |
| 2550Q 2024-04-ENCS | `no_setup` | Nothing. EOPT tier is inherited from the Base Tax Profile. The exact 2024 revision has no Line of Business field. | Show inherited Base EOPT read-only and “No additional yearly details required”; never display or project Line of Business. |
| 2551Q 2018-01-ENCS | `setup` | `income_tax_rate_election` only. | Edit the yearly Graduated-versus-8% choice in the generic Tax Form Profile. Inherited Base values stay read-only; Schedule 1 ATC rows remain filing transactions. |

Only active Forms Set entries for the selected tax year may show a Tax Form Profile card. Deactivating a form hides its card without deleting historical setups or drafts. Reactivation resolves the setup effective for that exact profile, tax year, form code, and form revision.

## Historical appendix — rejected 2026-08-04 pilot (non-normative)

> Historical only. The activity/obligation-anchor model in this appendix was
> rejected on 2026-08-05 and must not be used as a current implementation
> contract. Within the appendix, words such as “current,” `setup`, and
> “implemented” describe the 2026-08-04 pilot snapshot. Notation such as
> `D(P.activity)`, activity bindings, obligation bindings, Registration-derived
> readiness, and the former 2551Q taxpayer-year dependency is superseded by the
> current Decision and Tax-form setup contracts above.

### Reviewed pre-correction 72-target ownership matrix

Evidence notation:

- `CR` / `CO`: current generated catalog says required / optional.
- `LP`: the prior app prefills the value from its taxpayer profile.
- `LF`: the prior app derives a locked form constant or typed classification.
- `LB`: the value comes from a separately bound profile or effective component.
- `G-REQ`: exact official-form requiredness/applicability still must be proved.
- `G-FIELD`: the full official input census for the exact revision still must be reconciled with the Native editor.

#### 0605 — 1999-07-ENCS (`no_setup`)

Prior-app constructor evidence: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_0605.rs:480-507`. It deliberately initializes ATC and tax type to `None` at lines 494-495.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `0605.1999-07-ENCS.input.atc_only_source_proven_pairs` | `atc` / required | `T` | `K-ALL` | none | `CR`; prior app leaves blank; `G-REQ` | `src/pages/forms/0605.native:6` |
| `0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs` | `tax_type` / required | `T` | `K-ALL` | none | `CR`; prior app leaves blank; `G-REQ` | `src/pages/forms/0605.native:7` |
| `0605.1999-07-ENCS.input.tin` | `tin` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0605.native:14` |
| `0605.1999-07-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0605.native:15` |
| `0605.1999-07-ENCS.input.line_of_business_occupation` | `line_of_business` / required | `T` with optional seed from `D(P.activity)` | `K-0605-LOB` | none | `CR`, legacy flat-profile seed; official activity-versus-occupation semantics unresolved | `src/pages/forms/0605.native:16` |
| `0605.1999-07-ENCS.input.taxpayer_name` | `taxpayer_name` / required | `D(P.subject)` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0605.native:17` |
| `0605.1999-07-ENCS.input.registered_address` | `registered_address` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0605.native:18` |

#### 1601C — 2018-01-ENCS (`setup`)

Prior-app evidence: fixed ATC with pinned official PDF/XML hashes at `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_1601c.rs:28-35`; constructor projection at `:225-246`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `1601C.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1601-c.native:3` |
| `1601C.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1601-c.native:4` |
| `1601C.2018-01-ENCS.input.taxpayer_name` | `taxpayer_name` / required | `D(P.subject)` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1601-c.native:5` |
| `1601C.2018-01-ENCS.input.registered_address` | `registered_address` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1601-c.native:6` |
| `1601C.2018-01-ENCS.input.line_of_business` | `line_of_business` / required | `D(P.activity) + S(activity_id)` | `K-ACTIVITY` | activity binding | `CR`, `LP`; current `K-ALL` policy is too broad | `src/pages/forms/1601-c.native:8` |
| `1601C.2018-01-ENCS.input.contact_number` | `contact_number` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1601-c.native:9` |
| `1601C.2018-01-ENCS.input.atc` | `atc` / required | `D(form_policy.WW010)` | `K-ALL` | none; read-only | `CR`, `LF`; hash-locked exact-revision evidence | `src/pages/forms/1601-c.native:20` |

#### 0619F — 2018-01-ENCS (`setup`, `evidence_required`)

Prior-app evidence: exact-revision constants and hashes at `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_0619f.rs:18-37`, derived tax type at `:312-322`, and profile header projection at `:257-280`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `0619F.2018-01-ENCS.input.tax_type_code` | `tax_type` / required | `D(form_policy.WB)` | `K-ALL` | none; read-only | `CR`, `LF`; fixed exact-revision value | `src/pages/forms/0619-f.native:6` |
| `0619F.2018-01-ENCS.input.government_withholding_agent` | `government_withholding_agent` / required | `D(P.registration_obligation)` | `K-ALL` | none | `CR`, `LF`; derive agent category, do not copy a boolean into setup | `src/pages/forms/0619-f.native:8` |
| `0619F.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0619-f.native:9` |
| `0619F.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0619-f.native:10` |
| `0619F.2018-01-ENCS.input.registered_taxpayer_name` | `taxpayer_name` / required | `D(P.subject)` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0619-f.native:11` |

#### 1701Q — 2018-01-ENCS (`setup`)

Prior-app projection and year-election evidence: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_1701q.rs:546-625`. Current role/applicability boundary: `docs/tax-profile/ARCHITECTURE.md:130-152`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `1701Q.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701q.native:53` |
| `1701Q.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701q.native:57` |
| `1701Q.2018-01-ENCS.input.taxpayer_filer_name` | `taxpayer_name` / required | `D(P.subject)` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701q.native:61` |
| `1701Q.2018-01-ENCS.input.registered_address` | `registered_address` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701q.native:65` |
| `1701Q.2018-01-ENCS.input.zip_code` | `zip_code` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701q.native:68` |
| `1701Q.2018-01-ENCS.input.date_of_birth` | `date_of_birth` / optional | `P` | `K-PERSON` | none | `CO`, `LP`; hide for estate/trust | `src/pages/forms/1701q.native:72` |
| `1701Q.2018-01-ENCS.input.email_address` | `email_address` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701q.native:76` |
| `1701Q.2018-01-ENCS.input.citizenship` | `citizenship` / optional | `P` | `K-PERSON` | none | `CO`; prior app leaves blank; foreign applicability gate | `src/pages/forms/1701q.native:80` |
| `1701Q.2018-01-ENCS.input.foreign_tax_number` | `foreign_tax_number` / optional | `P` | `K-PERSON` | none | `CO`; prior app leaves blank; foreign applicability gate | `src/pages/forms/1701q.native:84` |
| `1701Q.2018-01-ENCS.input.spouse_tin` | `tin` / required when role bound | `D(P.identity) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | zero-or-one role; `CR` only after binding | `src/pages/forms/1701q.native:113` |
| `1701Q.2018-01-ENCS.input.spouse_rdo_code` | `rdo_code` / required when role bound | `D(P.identity) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | zero-or-one role; `CR` only after binding | `src/pages/forms/1701q.native:117` |
| `1701Q.2018-01-ENCS.input.spouse_name` | `taxpayer_name` / required when role bound | `D(P.subject) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | zero-or-one role; `CR` only after binding | `src/pages/forms/1701q.native:121` |
| `1701Q.2018-01-ENCS.input.spouse_citizenship` | `citizenship` / optional | `D(P.person) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | `CO`; foreign applicability gate | `src/pages/forms/1701q.native:124` |
| `1701Q.2018-01-ENCS.input.spouse_foreign_tax_number` | `foreign_tax_number` / optional | `D(P.person) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | `CO`; foreign applicability gate | `src/pages/forms/1701q.native:127` |

#### 1701 — 2018-01-ENCS (`setup`)

Prior-app profile, activity, and taxpayer-year-election projection: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_1701.rs:476-525`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `1701.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701.native:6` |
| `1701.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701.native:7` |
| `1701.2018-01-ENCS.input.taxpayer_name` | `taxpayer_name` / required | `D(P.subject)` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701.native:8` |
| `1701.2018-01-ENCS.input.registered_address` | `registered_address` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701.native:9` |
| `1701.2018-01-ENCS.input.zip_code` | `zip_code` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701.native:10` |
| `1701.2018-01-ENCS.input.date_of_birth` | `date_of_birth` / optional | `P` | `K-PERSON` | none | `CO`, `LP`; hide for estate/trust | `src/pages/forms/1701.native:11` |
| `1701.2018-01-ENCS.input.email_address` | `email_address` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701.native:12` |
| `1701.2018-01-ENCS.input.citizenship` | `citizenship` / optional | `P` | `K-PERSON` | none | `CO`; foreign applicability gate | `src/pages/forms/1701.native:13` |
| `1701.2018-01-ENCS.input.foreign_tax_number` | `foreign_tax_number` / optional | `P` | `K-PERSON` | none | `CO`; foreign applicability gate | `src/pages/forms/1701.native:14` |
| `1701.2018-01-ENCS.input.contact_number` | `contact_number` / required | `P` | `K-IET` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1701.native:15` |
| `1701.2018-01-ENCS.input.spouse_tin` | `tin` / required when role bound | `D(P.identity) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | zero-or-one role; `CR` only after binding | `src/pages/forms/1701.native:21` |
| `1701.2018-01-ENCS.input.spouse_rdo_code` | `rdo_code` / required when role bound | `D(P.identity) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | zero-or-one role; `CR` only after binding | `src/pages/forms/1701.native:22` |
| `1701.2018-01-ENCS.input.spouse_name` | `taxpayer_name` / required when role bound | `D(P.subject) + S(spouse_profile_id)` | `K-SPOUSE` | spouse binding | zero-or-one role; `CR` only after binding | `src/pages/forms/1701.native:23` |

#### 1702RT — 2018-01-ENCS (`setup`)

Prior-app entity-header projection: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_1702rt.rs:462-501`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `1702RT.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-rt.native:6` |
| `1702RT.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-rt.native:7` |
| `1702RT.2018-01-ENCS.input.registered_name` | `registered_name` / required | `D(P.subject)` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-rt.native:8` |
| `1702RT.2018-01-ENCS.input.registered_address` | `registered_address` / required | `P` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-rt.native:9` |
| `1702RT.2018-01-ENCS.input.line_of_business` | `line_of_business` / required | `D(P.activity) + S(activity_id)` | `K-ACTIVITY` | activity binding | `CR`; prior constructor does not project this field; `G-FIELD` | `src/pages/forms/1702-rt.native:13` |

#### 1702MX — 2018-01-ENCS (`setup`)

Prior-app entity-header and filing-owned schedules: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_1702mx.rs:383-446`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `1702MX.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-mx.native:6` |
| `1702MX.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-mx.native:7` |
| `1702MX.2018-01-ENCS.input.registered_name` | `registered_name` / required | `D(P.subject)` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-mx.native:8` |
| `1702MX.2018-01-ENCS.input.registered_address` | `registered_address` / required | `P` | `K-ENTITY` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/1702-mx.native:9` |
| `1702MX.2018-01-ENCS.input.line_of_business` | `line_of_business` / required | `D(P.activity) + S(activity_id)` | `K-ACTIVITY` | activity binding | `CR`; prior constructor does not project this field; `G-FIELD` | `src/pages/forms/1702-mx.native:13` |
| `1702MX.2018-01-ENCS.input.special_preferential_rate_basis` | `special_rate_basis` / optional | `D(P.registration_obligation)` | `K-SPECIAL` | obligation binding only if ambiguous | `CO`; schedules retain filing-specific basis/rates; `G-REQ` | `src/pages/forms/1702-mx.native:14` |

#### 2550Q — 2024-04-ENCS (`no_setup`)

Prior-app profile and EOPT projection: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_2550q.rs:927-952`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `2550Q.2024-04-ENCS.input.tin` | `tin` / required | `P` | `K-ALL` | none | `CR`, `LP`; VAT-obligation applicability must replace `K-ALL` activation | `src/pages/forms/2550q.native:9` |
| `2550Q.2024-04-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2550q.native:10` |
| `2550Q.2024-04-ENCS.input.taxpayer_name` | `taxpayer_name` / required | `D(P.subject)` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2550q.native:11` |

#### 2551Q — 2018-01-ENCS (`no_setup`)

The current architecture fixes the seven-field header boundary at `docs/tax-profile/ARCHITECTURE.md:107-128`. Prior-app projection, annual election, and transaction-owned Schedule 1 evidence: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_2551q.rs:364-469`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `2551Q.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-ALL` | none | `CR`, `LP`; active percentage-tax obligation controls applicability | `src/pages/forms/2551q.native:81` |
| `2551Q.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2551q.native:82` |
| `2551Q.2018-01-ENCS.input.taxpayers_name` | `taxpayer_name` / required | `D(P.subject)` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2551q.native:83` |
| `2551Q.2018-01-ENCS.input.registered_address` | `registered_address` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2551q.native:86` |
| `2551Q.2018-01-ENCS.input.zip_code` | `zip_code` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2551q.native:90` |
| `2551Q.2018-01-ENCS.input.contact_number` | `contact_number` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2551q.native:94` |
| `2551Q.2018-01-ENCS.input.email_address` | `email_address` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/2551q.native:98` |

#### 0619E — 2018-01-ENCS (`setup`, `evidence_required`)

Prior-app exact-revision constants and hashes: `/Volumes/goldcoders/reverse-engineer-ebir-forms/bir/crates/bir-core/src/forms/form_0619e.rs:17-38`; derived codes at `:309-315`; profile header at `:254-279`.

| Stable target | Current key / presence | Correct owner | Kind | Setup effect | Requiredness evidence / gate | Current source |
|---|---|---|---|---|---|---|
| `0619E.2018-01-ENCS.input.atc` | `atc` / required | `D(form_policy.WME10)` | `K-ALL` | none; read-only | `CR`, `LF`; fixed exact-revision value | `src/pages/forms/0619-e.native:6` |
| `0619E.2018-01-ENCS.input.tax_type_code` | `tax_type` / required | `D(form_policy.WE)` | `K-ALL` | none; read-only | `CR`, `LF`; fixed exact-revision value | `src/pages/forms/0619-e.native:7` |
| `0619E.2018-01-ENCS.input.tin` | `tin` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0619-e.native:9` |
| `0619E.2018-01-ENCS.input.rdo_code` | `rdo_code` / required | `P` | `K-ALL` | none | `CR`, `LP`; `G-REQ` | `src/pages/forms/0619-e.native:10` |
| `0619E.2018-01-ENCS.input.government_withholding_agent` | `government_withholding_agent` / required | `D(P.registration_obligation)` | `K-ALL` | none | `CR`, `LF`; derive agent category, do not duplicate a boolean in setup | `src/pages/forms/0619-e.native:17` |

### Historical source-backed catalog repairs outside the original 72 targets

The 72-row matrix records the pre-correction generated classification and the
reviewed owner decision for each former target. The execution pass restored the
26 inherited controls listed in the implementation result above. The remaining
items in this table stay evidence-gated where they are conditional entity or
registration facts rather than ordinary reusable header strings.

| Form | Baseline omission or ownership defect | Correct owner | Evidence |
|---|---|---|---|
| 0605 | ZIP, contact, email, taxpayer classification are absent; ATC/tax type are wrongly profile-owned. | ZIP/contact/email `P`; classification `D(P.subject/classification)`; ATC/tax type `T`. | Prior app `form_0605.rs:480-507`. |
| 1601C | ZIP, email, and withholding-agent category are absent; fixed ATC is wrongly profile-owned. | ZIP/email `P`; category `D(P.registration_obligation)`; ATC `D(form_policy)`. | Prior app `form_1601c.rs:225-246`. |
| 0619E | Taxpayer name, line of business, address, ZIP, contact, and email are absent; fixed codes are wrongly profile-owned. | Header `P/D`; activity `D(P.activity)+S`; codes `D(form_policy)`. | Prior app `form_0619e.rs:254-279`. |
| 0619F | Line of business, address, ZIP, contact, and email are absent; fixed tax type is wrongly profile-owned. | Header `P/D`; activity `D(P.activity)+S`; tax type `D(form_policy)`. | Prior app `form_0619f.rs:257-280`. |
| 1701Q | Contact, line of business, filer type, and ATC are absent from the profile matrix; annual election/deduction is wrongly a filing transaction. | Contact `P`; activity/ATC/filer type `D`; supported filer activity selection `S`; election/deduction `Y`. Spouse activity selection remains evidence-gated. | Prior app `form_1701q.rs:546-625`, specifically activity/ATC at `:573-577` and line of business at `:613`; current transaction target `src/pages/forms/1701q.native:88`. |
| 1701 | ATC/activity and annual election/deduction sources are absent from the profile matrix. | Supported filer activity/ATC `D+S`; election/deduction `Y`. Spouse activity selection remains evidence-gated. | Prior app `form_1701.rs:476-525`, specifically recognized filer ATC selection at `:495-503`. |
| 1702RT | ZIP, incorporation date, contact, and email are absent; current line-of-business target is not populated by the prior constructor. | Header `P`; incorporation date `P` conditional; LOB `D+S`. | Prior app `form_1702rt.rs:462-501`. |
| 1702MX | ZIP, incorporation date, contact, and email are absent; current LOB and special basis require official reconciliation. | Header `P`; LOB `D+S`; special basis `D(P.registration_obligation)`; schedules `T/C`. | Prior app `form_1702mx.rs:383-446`. |
| 2550Q | Address, ZIP, contact, email, and EOPT classification are absent. | Header `P`; EOPT `D(P.registration/classification)`. | Prior app `form_2550q.rs:927-952`. |
| 2551Q | Taxpayer type, business start date, EOPT, and annual election are not in the seven-field header projection; Schedule 1 must not migrate to setup. | First three `D/P`; annual election `Y`; Schedule 1 `T/C`. | Prior app `form_2551q.rs:364-469`; architecture `docs/tax-profile/ARCHITECTURE.md:107-128`. |

### Historical taxpayer-year settings proposal before draft composition

The rejected pilot's generated
`FormDefinition.consumed_taxpayer_year_settings` contract used the closed keys
`income_tax_rate_election` and `deduction_method`. At that historical point,
1701 and 1701Q consumed both and 2551Q also consumed
`income_tax_rate_election`. That 2551Q ownership is no longer current: its
visible annual election now belongs to the exact 2551Q Tax Form Profile for
the selected taxpayer, tax year, form revision, and setup specification.

| Key | Applicability | Consumers | Evidence / gate |
|---|---|---|---|
| `income_tax_rate_election` | self-employed or mixed-income natural person | 1701Q, 1701, applicable 2551Q item 13 | Prior app records a year-indexed election ledger at `profile.rs:76-87` and `:119-126`; constructors consume it in `form_1701q.rs:549-572`, `form_1701.rs:504-524`, and `form_2551q.rs:374-442`. |
| `deduction_method` | graduated income-tax filer | 1701Q and 1701; possibly corporate forms after official proof | Same constructor evidence; do not infer when the year is unrecorded or conflicting. |
| `accounting_period_basis` and `year_end_month` | only when the taxpayer is legally fiscal | all compatible period identities | Current app supports calendar operation and deliberately rejects/defers fiscal 2551Q at `docs/tax-profile/ARCHITECTURE.md:125-128`; official period rules are a blocking gate. |

These settings must be effective for `(profile_id, tax_year)`. A form setup may consume them read-only but must not copy them.

### Historical typed source/provenance implementation

The generated catalog still uses the closed 16-value `ReusableField` vocabulary for reusable field identity, but persistence no longer treats every value as undifferentiated `tax_profile` provenance. `src/forms/draft_provenance.zig:231-317` defines the source-aware immutable identities used by draft snapshots, while the Registration, Taxpayer-Year, and Tax Form Profile stores retain their own typed append-only revisions.

The implemented source contract carries these minimum identities:

| Variant | Minimum identity carried |
|---|---|
| `profile_field` | profile ID, effective revision ID/sequence, canonical field |
| `subject_projection` | profile revision plus semantic projection such as taxpayer display name, registered name, subject kind, or conditional trade name |
| `business_activity_field` | stable activity anchor ID, effective component revision, `line_of_business` or `atc` |
| `registration_obligation_field` | stable obligation anchor ID, effective component revision, typed obligation/status field |
| `taxpayer_year_setting` | profile ID, tax year, setting key, setting revision |
| `form_policy` | exact form code/revision, policy key, evidence/mapping revision |
| `tax_form_setup_binding` | profile ID, tax year, exact form code/revision, setup revision, binding key and stable target ID |

`T` and `C` values are not reusable profile-source values. They remain transaction/calculation/artifact provenance in the draft.

Stable profile-scoped activity and obligation anchors with independently effective revisions are implemented in `src/tax_profile/registration.zig:86-206` and its storage adapters. A year-scoped Tax Form Profile stores the stable anchor, and the shared resolver selects the exact effective revision for the filing date. It never persists a revision-local row ID as though it were stable.

## Current remaining evidence gates and invariants

### Remaining evidence or product gates

1. **Exact official field census (`G-FIELD`).** For every one of the 10 editor revisions, reconcile the Native controls, official PDF fields, official XML/package fields where available, and prior-app constructor. The prior app is behavioral evidence, not legal authority.
2. **Requiredness/applicability (`G-REQ`).** Record official evidence for each `required`, optional, and taxpayer-kind condition. Do not treat a current catalog default as proof.
3. **Legal subject taxonomy.** Qualify the current subject-kind and natural-person classification policy against official evidence before any migration changes identity semantics.
4. **Ambiguous Base migration review.** A legacy Registration migration that cannot prove one EOPT tier or Primary Line of Business remains explicitly review-required in the Base Tax Profile; it must never silently select one legacy row.

### Current invariants covered by final acceptance

1. **One Base source.** Identity, contact, accounting basis, EOPT tier, and Primary Line of Business are effective-dated Base values. New setup, projection, readiness, and filing provenance do not depend on Registration activity or obligation anchors.
2. **Exact setup identity.** A Tax Form Profile revision is scoped to profile, tax year, exact form code/revision, generated setup spec, and active Forms Set interval. Genuine named-profile roles and primitive form-specific values remain explicit.
3. **Canonical readiness.** Filing tiles, card presentation, and launch dispatch consume the same cached exact-period `FormReadiness`; a card does not independently recompute persistence-backed readiness.
4. **Source-aware snapshot persistence.** New draft provenance records the exact Base Tax Profile, Forms Set decision, applicable compatibility settings, Tax Form Profile revision, generated catalog, and copied values. Historical Registration provenance remains readable only at the migration/export boundary.
5. **Explicit absence with a visible view.** `no_setup` and active calendar-only forms create no setup row and expose no Edit action, but they still expose a Tax Form Profile action that shows inherited Base details read-only. A `setup` contract never fabricates an empty revision.
6. **Activation behavior.** Only active forms appear in normal browse. Deactivation retains historical setup and draft provenance while blocking new work.
7. **UI mode behavior.** Tax Profile and Tax Form Profile open read-only. Edit creates a draft; clean Save/Cancel are disabled; dirty Cancel restores the persisted snapshot; successful Save returns to view mode.

## Verification baseline

The generated catalog remains authoritative for the current source inventory;
final packaged verification and the evidence gates above do not permit
hand-editing generated output:

- `scripts/tax-catalog/catalog.ts:122-139` defines the current 16 keys.
- `scripts/tax-catalog/catalog.ts:1063-1809` declares the 10 exact editors.
- `docs/tax-profile/FORM_FIELD_CATALOG.md` records the generated inventory. Its current values must agree with this simplified contract: 2551Q owns its yearly rate choice in Tax Form Profile, while only 1701 and 1701Q retain taxpayer-year compatibility settings.
- `src/forms/ui_state.zig:35-59` compile-time locks the 10 editor revisions and 16-key cache.
- `src/forms/catalog_projection.zig` tests the generated field/projection boundary without making the rejected Registration pilot normative.

Catalog changes must be authored in the source catalog or source `.native` fragments, regenerated, and checked; generated Zig and generated Markdown are not hand-edited.
