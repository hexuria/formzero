# Tax-profile implementation plan

This plan is dependency-ordered. A later phase cannot weaken an earlier
domain invariant merely to make UI wiring easier.

## Execution status

The architecture phases began in the isolated
`codex/tax-profile-architecture` worktree, with the cadence-aware library
slice now carried forward in the current checkout.

- The generated catalog covers 51 codes, 10 exact editors, 41 explicit
  `calendar_only` entries, 299 Native inputs, and 72 profile targets.
- Persisted profile revisions, Forms Set, named role bindings, immutable
  snapshots, lifecycle guards, and transaction values are integrated.
- All ten editors project their declared profile subset. The recurring 2551Q
  and 1701Q editors additionally own controlled transaction state and exact
  save/resume adapters.
- The full Native suite passes 903 tests with 3 platform skips (906 total);
  catalog/type/drift, strict markup and model contract, strict doctor, and the
  ReleaseFast build pass. Runtime UI inspection is environment-dependent and
  must be rerun where the Computer Use service is available.
- Fiscal 2551Q remains explicitly disabled and domain-rejected until fiscal
  profile effective dates and draft identities can be modeled truthfully.
  Submission and official print/file parity remain outside this feature.

### Cadence-aware Tax Form Library slice

The library extension is now implemented on top of the Forms Set boundary:

- The generated 51-form catalog declares `monthly`, `quarterly`, `annual`, or
  `on_demand` cadence plus valid period bounds (including the 1701Q Q1-Q3
  exception).
- A typed `FilingPeriod` value object emits canonical `YYYY-M##`, `YYYY-QN`,
  `YYYY-A`, and `YYYY-ONNN` identities and validates them against catalog
  policy before an editor opens.
- Browse mode shows only persisted active forms and renders their monthly,
  quarterly, annual, or on-demand filing periods as the card actions. Manage
  mode renders catalog selection cards with staged status and no filing
  actions.
- One immediate grouped filter exposes Jan-Dec, Q1-Q4, Annual, On-demand, and
  active on-demand form choices. No explicit month or quarter selection means
  all periods (there is no redundant `All` tile). Selecting one or more months
  or quarters shows only those period buttons. The closed control summarizes
  the exact choice, such as `Jan · Q2`; filtering never changes Forms Set
  authority. Reset restores the unfiltered state and clears the search query.
- Monthly and quarterly period choices use intrinsic-width, tap-sized buttons
  with a clear selected state. The card grid reserves its columns from the
  catalog cadence and available card width, so hiding periods never makes the
  remaining buttons grow. Browse mode provides bordered empty states for no
  active forms and for filters that match no forms; manage mode retains its
  catalog-specific empty state.
- Each period button carries a typed filing identity into the workspace, so
  the tax year and month, quarter, annual period, or on-demand occurrence are
  prefilled rather than inferred from unrelated calendar state.
- On-demand editor cards keep a distinct Start new return action and expose
  saved occurrences as separate resume/view actions with lifecycle status.
  Saved actions show their stable `O###` filing reference; durable reservations
  may intentionally leave gaps when an attempted workspace cannot be opened.
- The global calendar remains independent; profile calendar bounds and Forms
  Set activation remain unchanged.

Generic persistence adapters now cover monthly, annual, and on-demand editor
workspaces. Canonical period keys, deterministic draft IDs, catalog role and
snapshot validation, profile-as-of derivation, and rehydration are exercised
by round-trip tests; the existing 2551Q/1701Q recurring adapters remain
backward-compatible with their legacy quarterly keys.

Transaction-value binding is still intentionally form-specific. The generic
path persists the immutable profile snapshot and accepts separate transaction
value writes, but it does not claim that every static editor has a complete
transaction calculator or filing workflow.

## Phase 0 — Isolation and baseline

- Create `codex/tax-profile-architecture` in a separate worktree.
- Install exact dependencies.
- Generate Native source.
- Record green test, strict-check, release-build, and doctor baselines.

Stop if the baseline is red for reasons unrelated to this feature.

## Phase 1 — Catalog and reusable vocabulary

- Inventory every field in every current Native editor revision.
- Classify provenance as profile, transaction, derived, filing context, or
  external.
- Assign stable field IDs, named roles, role cardinality/subject policy,
  per-target presence, value types, and source locations.
- Reconcile the 51-code registry with the 10 current editors and explicitly
  mark the other 41 codes `calendar_only`.
- Generate Zig metadata and a human-reviewable report from strict TypeScript.
- Enforce the closed reusable-field vocabulary and generator drift in tests.

Acceptance: exact registry/editor/control counts and deterministic output.

## Phase 2 — Domain and form contracts

- Add validated field newtypes and period/money value objects.
- Add immutable effective-dated profile revisions with cohesive subject,
  activity, registration-fact, and source variants.
- Add the coarse typestate profile builder.
- Add capability discovery and typed value resolution.
- Add compile-time form/role specifications and runtime qualification.
- Add owned snapshots with complete provenance.
- Implement exact 2551Q and 1701Q contracts and filing payload unions.

Acceptance: malformed static specs fail compilation; under-qualified runtime
profiles are rejected with precise issues; snapshots own their values.

## Phase 3 — Persistence

- Add namespaced migrations alongside the existing calendar schema.
- Persist profile shells, stable revision IDs, effective periods, source
  variants, subject variants, activities, and registration facts losslessly.
- Enforce atomic first-save, append-only revisions, and optimistic conflicts.
- Persist Forms Set's three states.
- Persist drafts, named role bindings, immutable snapshot fields, transaction
  values, amendments, and lifecycle transitions.
- Add a domain adapter that is the only profile-revision serialization path.

Acceptance: domain -> SQLite -> domain round-trips every variant and component;
SQLite row IDs never escape the persistence layer.

## Phase 4 — Profile UI and Forms Set

- Replace sample profiles with persisted dynamic rows and stable selection.
- Add controlled inputs for subject-specific and reusable facts.
- Route save/load through the domain builder and adapter.
- Make revision creation explicit; never edit the current revision in place.
- Keep COR evidence and operational email credentials separate from tax facts.
- Configure per-year Forms Set, preserving `needs_configuration`, explicit
  empty, and the legacy catalog-default compatibility state.
- Feed the same stored policy to calendar and form availability.

Acceptance: restarting with the same data directory reloads profiles and
Forms Set; invalid input never reaches storage.

## Phase 5 — Recurring 2551Q

- Create or resume a draft for a selected profile and quarter.
- Qualify and project the exact seven-field header.
- Persist its filer binding and immutable snapshot provenance.
- Bind the seven profile-derived controls read-only.
- Bind transaction controls and Schedule 1 rows separately.
- Require an externally supplied rate and persist transaction values.
- Prove a later profile revision does not alter the existing draft.

Acceptance: the next quarter reuses the profile but has independent filing
values; no ATC or rate is smuggled into the singleton header.

## Phase 6 — 1701Q and remaining editor projections

- Create or resume a 1701Q draft with required filer and optional spouse.
- Persist both named bindings and their snapshots.
- Reject the same profile in both roles.
- Bind reusable filer/spouse controls and keep computation fields
  filing-specific.
- Exercise catalog-backed projection coverage for every profile target in the
  other eight current editors.
- Keep 41 registry-only forms explicitly unavailable as editors.

Acceptance: all 72 catalog profile targets resolve through the same canonical
vocabulary, are intentionally omitted by optional role/target policy, or
produce a truthful qualification issue.

## Phase 7 — Lifecycle and release gates

- Persist draft save/resume and coarse lifecycle transitions.
- Preserve amendment relationships and prior snapshots.
- Run catalog generation/type/drift checks.
- Run full Native tests and strict model/markup analysis.
- Run release build, strict doctor, and whitespace checks.
- Review the isolated diff and commit only green dependency-sized phases.

Stop conditions:

- a reusable value has no truthful source;
- legacy rows conflict;
- a form target's provenance is ambiguous;
- a tax policy/rate would need to be guessed; or
- a generated file would need hand-editing.
