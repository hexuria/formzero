# Tax-profile implementation plan

This plan is dependency-ordered. A later phase cannot weaken an earlier
domain invariant merely to make UI wiring easier.

## Execution status

All seven phases are implemented in the isolated
`codex/tax-profile-architecture` worktree.

- The generated catalog covers 51 codes, 10 exact editors, 41 explicit
  `calendar_only` entries, 299 Native inputs, and 72 profile targets.
- Persisted profile revisions, Forms Set, named role bindings, immutable
  snapshots, lifecycle guards, and transaction values are integrated.
- All ten editors project their declared profile subset. The recurring 2551Q
  and 1701Q editors additionally own controlled transaction state and exact
  save/resume adapters.
- The full Native suite passes 180 tests; catalog/type/drift, strict markup and
  model contract, strict doctor, ReleaseFast build, and isolated runtime
  restart gates pass.
- Fiscal 2551Q remains explicitly disabled and domain-rejected until fiscal
  profile effective dates and draft identities can be modeled truthfully.
  Submission and official print/file parity remain outside this feature.

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
