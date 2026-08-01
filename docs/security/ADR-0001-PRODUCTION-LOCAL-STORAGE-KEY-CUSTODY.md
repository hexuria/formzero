# ADR-0001: Production local-storage key-custody boundary

- Status: Accepted boundary; storage backend and operating-system provider
  remain deliberately unselected
- Date: 2026-07-31
- Scope: Local persistence of taxpayer profiles, form snapshots, exact draft
  histories, calendar/account bindings, and related SQLite journals or backups
- Candidate analysis:
  [production storage provider decision packet](PRODUCTION-STORAGE-PROVIDER-DECISION-PACKET.md)

## Decision

Production taxpayer persistence is unavailable until a separately reviewed
storage backend provides authenticated encryption for every value-bearing
database surface and an approved operating-system custody provider can release
its key.

This is a production classification and design boundary. The current
application remains a development artifact and still uses a shared
stock-SQLite database for calendar and tax-profile persistence, but it may
reach those file-backed constructors only through the source-minted
development capability described below. No production artifact can be
requested through the current build graph.

The current SQLite stores are plaintext development infrastructure. They must
not receive production taxpayer data and must never be promoted by a runtime
flag, environment variable, command-line key, silent fallback, or optimistic
probe. Exact-draft SQLite persistence remains synthetic/test-only. This record
does not select SQLCipher, SQLite SEE, a per-column envelope, or any other
encryption implementation.

The executable boundary in `src/security/key_custody.zig` therefore exposes:

1. a source-selected artifact classification fixed to
   `development_only_plaintext_not_production`;
2. an identity-checked development plaintext capability minted only by the
   current-artifact bootstrap;
3. a separate test-only opaque capability for synthetic exact persistence;
4. an opaque production capability with no constructor;
5. production states whose names and meanings are all unavailable states; and
6. a production gate that always returns
   `error.ProductionStorageUnavailable`.

The development bootstrap accepts no runtime input and runs before the
application reads `EBIRFORMS_DATA_DIR`, resolves a repository path, creates a
directory, or performs storage I/O. Both file-backed Store constructors
validate its capability before path validation. A cast pointer fails identity
validation. An attempted production consumer must likewise validate a
production capability as well as obtain one; current source rejects even a
pointer cast to that opaque type and provides no usable production minting
path.

`src/security/production_storage_requirements.zig` records the current
provider-neutral minimum contract as closed vocabularies. Their arrays are
compile-time exhaustive relative to their corresponding enums: adding or
duplicating an enum member without deliberately updating its reviewed array
fails compilation. They enumerate required database-surface categories,
authenticated-backend properties, custody failure conditions, recovery
scenarios, repository artifact classifications, x64/ARM64 qualification
scenarios, key-purpose separation, and currently identified external
product/security/operations decisions. This mechanism does not prove that the
real-world set is complete; provider review may require new enum members.
These types are requirements, not evidence that a provider satisfies them.

The current closed vocabulary contains eight protected surfaces, fifteen
authenticated-backend requirements, twelve custody failure conditions, nine
recovery scenarios, nine repository artifact states, twelve qualification
scenarios, two Windows architectures, four prohibited key-purpose comparison
domains, and ten external decisions. The backend requirements now include a
trusted freshness/restore-lineage binding plus Windows directory and sidecar
access control, reparse-resistant handle-relative resolution, and parent/leaf
file-identity continuity. Qualification includes full-bundle replay/restore
freshness and Windows ACL/reparse/file-identity attacks.

`src/security/production_storage_evidence.zig` is the machine-verifiable,
provider-neutral evidence model for those vocabularies. It requires every
requirement and decision exactly once; every applicable lifecycle scenario on
both x64 and ARM64; distinct architecture records for executable, package
inventory, package manifest, toolchain, OS build, PE machine/target, and
conformance-harness identity; and one provider/backend implementation record
per architecture. Provider and backend product/configuration identities must
remain stable across architectures, while their x64 and ARM64 binary digests
must be distinct. Every scenario binds its matching architecture artifact and
component record. Evidence must also cover all nine repository artifact states
and the exact eight-cell architecture-by-prohibited-purpose matrix. Each matrix
record attests that database-at-rest material is distinct, non-derived, and
does not reuse a handle relative to submission-protocol material, application
credentials, signing identity, or taxpayer identifiers.

Time-bounded, non-revoked approvals require distinct owner/reviewer bindings.
Detached scenario, key-separation, and decision records have individual
digests, and one canonical digest binds the complete result and decision set.
Verdicts use closed value-free failure codes and count only records whose full
validation gate passed. A structurally complete verdict is explicitly
observational, keeps the effective source selection `unavailable_unselected`,
never authorizes production, and cannot mint
`ProductionStorageCapability`.

`src/security/repository_opening.zig` defines twelve typed stages in one
security-significant partial order:

1. bind release qualification;
2. bind recovery policy;
3. bind repository-transition policy;
4. authenticate the custody provider;
5. initialize the authenticated backend;
6. resolve repository location;
7. classify the complete artifact set through that backend;
8. reconcile an interrupted authenticated operation;
9. apply an approved initial-provision or legacy transition;
10. authenticate the reconciled repository;
11. inspect or migrate its schema; and
12. verify operational readiness against the same release approval.

Every successful route executes the qualification, policy, custody, backend,
location, classification, final authentication, schema, and readiness stages.
Recovery is invoked only for an authenticated interrupted state. Provision or
legacy transition is invoked only for an absent or untrusted legacy
repository. Authenticated-current skips both callbacks, and terminally unsafe
states stop immediately after classification. No valid route invokes both
recovery and provision/legacy transition.

The private callback interfaces pass no repository or location proof into
policy or custody stages. Location resolution receives metadata authority
only, and the callback designated for SQL or PRAGMA work requires the private
authenticated-repository marker. These types order a synthetic harness; they
cannot inspect or constrain the body of a future callback. Review and
qualification of a selected implementation must independently prove that its
earlier callbacks issue no SQL, PRAGMA, plaintext probe, or fallback.

Recovery may convert only an authenticated interrupted state to
authenticated-current; provision/legacy transition may convert only absent or
untrusted legacy plaintext to authenticated-current. Unsupported cipher,
custody/database mismatch, and unrecognized or tampered states receive neither
callback and cannot be relabeled into an authenticated repository.

The public factory is a zero-field type: callers cannot select even an
unavailable checkpoint, much less a ready state. It accepts no runtime
contracts or provider selector and delegates the source-selected current state
to the unavailable production gate. Stage-marker and callback-contract types
are private because an opaque pointer by itself is forgeable and must not be
treated as production authority. The ordered routes are exercised only by an
in-memory, value-free test harness. There is no production transition into
that harness, no ready state, and no provider, backend, path, key, recovery,
transition, or qualification decision embedded in the factory.

Adding a production-ready state or a constructor for the production capability
requires a new reviewed decision and cannot be represented as a data or
configuration change.

`build.zig` exposes only the `-Dproduction-release=true` option. It fails with
the value-free, source-pinned unavailable reason and returns before Native SDK
creates an executable, test artifact, install step, or package input. A named
`production-release` top-level step is deliberately not registered, so it
cannot be combined with `install` or a package step while ordinary development
artifacts remain schedulable. The ordinary build remains explicitly classified
as `development_only_plaintext_not_production`; the classification is visible
in the application shell and required in the packaged executable by the
Windows package verifier.

## Current facts

- `src/main.zig` obtains the source-minted current-artifact bootstrap before
  reading environment-based repository location input or performing
  filesystem work, then passes that development capability to both stores for
  one application-data SQLite file.
- `src/calendar/store.zig` and `src/tax_profile/store.zig` use the stock SQLite
  amalgamation and enable WAL for file-backed databases.
- Taxpayer TINs, names, addresses, contact details, form snapshot values, and
  exact occurrence values are stored as ordinary SQLite text or blobs.
- `src/security/sensitive_memory.zig` securely clears selected application-owned
  buffers before freeing them. It is not a key store, database codec, locked
  allocator, crash-dump control, or operating-system custody provider.
- `src/security/production_storage_evidence.zig` validates exact observational
  evidence structure and architecture binding only. Its complete synthetic
  fixture proves validator behavior, not a provider, backend, approval,
  production release, or real qualification result.
- The production repository factory models the shared calendar/tax-profile
  database as one typed protection scope; it remains unavailable and is not
  an authenticated implementation for those stores. Regressions prove that every
  unavailable state invokes zero callbacks and that a synthetic failure at
  each reachable stage on authenticated-current, interrupted-recovery, and
  provision/legacy-transition routes prevents every later stage. Together
  those routes cover all twelve declared stages.
- Matrix tests prove that interrupted provision, rotation, and migration can
  reach authentication only through recovery; absent and legacy plaintext can
  reach it only through an approved transition; invalid cross-classification
  attempts fail before authentication; and unsafe terminal states stop after
  classification without receiving recovery, transition, authentication, or
  the schema callback designated for SQL or PRAGMA work. These harness tests
  do not qualify the bodies of an unimplemented provider's callbacks.
- The calendar and tax-profile stores export the explicit classification
  `development_only_plaintext_not_production` and the integration state
  `unavailable_development_plaintext_artifact_only`. Their explicitly named
  development constructors require the validated source-minted capability and
  do not satisfy or fall back from the production factory. The former public
  two-argument `Store.open` surface no longer exists.
- The exact Native workspace remains memory-only. The headless exact
  persistence adapter is explicitly synthetic/test-only, requires the
  privately minted test capability at every public adapter entry point, and is
  not connected to the Native save path.
- The four raw exact-draft Store operations validate that same capability
  before validation, query preparation, allocation, or transaction start.
  Merely fabricating a pointer of the public opaque type fails with
  `error.InvalidSyntheticPlaintextTestCapability`; regression tests verify
  that no exact workspace or revision row is created and that a rejected
  reopen does not consume its loaded workspace.

No current code path provides production encryption at rest, key recovery,
rotation, or a production storage capability.

## Protected assets

The future production boundary must cover at least:

- taxpayer identity anchors, TINs, names, addresses, contact details, civil
  status, relationships, and correction history;
- Forms Set selections, profile projections, legacy draft values, exact draft
  occurrence values, provenance, and immutable validation receipts;
- database metadata that reveals taxpayer/form/period associations;
- SQLite main files, rollback journals, WAL files, temporary spill files,
  backups, and migration copies;
- active database keys, wrapped-key records, rotation state, and recovery
  material; and
- plaintext and key copies held in application or database-library memory.

Protecting only exact occurrence columns is insufficient because the same
database contains other taxpayer-identifying and value-bearing records.
Submission-container encryption is also outside this boundary and cannot
substitute for local protection.

## Threat model

### In scope

- offline copying, theft, backup disclosure, or forensic inspection of the
  application-data directory;
- access to those files from a different local operating-system account;
- tampering, truncation, replay, or swapping of database and custody metadata;
- wrong-user, wrong-machine, unavailable-provider, or corrupt-key startup;
- partial creation, crash recovery, migration interruption, and key-rotation
  interruption;
- accidental secret disclosure through logs, diagnostics, panic messages,
  filenames, screenshots, tests, or command history; and
- accidental use of the synthetic plaintext repository from a production
  persistence path.

### Outside the protection claim

- an attacker executing code as the same authenticated user while the
  application can release its key;
- administrator, kernel, hypervisor, debugger, injected-code, malicious-build,
  or compromised-release access;
- plaintext intentionally revealed in the UI, screen capture, shoulder
  surfing, or accessibility-process compromise;
- live process-memory inspection after the approved backend has decrypted a
  page or value; and
- availability after loss of all approved custody or recovery material.

These exclusions are limits on the protection claim, not permission to log,
retain, or expose plaintext.

## Required production invariants

A later production implementation must satisfy all of these invariants before
the unavailable state can change:

1. The backend authenticates as well as encrypts every value-bearing database
   surface in scope.
2. A key is applied and the database is authenticated before any schema query,
   PRAGMA, migration, or application read.
3. Key material never enters source control, SQLite, environment variables,
   command-line arguments, UI state, filenames, logs, screenshots, panic
   messages, or diagnostics.
4. The at-rest database key is independent from submission-container protocol
   secrets, credentials, signing keys, and taxpayer identifiers.
5. Missing, unavailable, corrupt, mismatched, or unsupported custody state
   fails closed. The application never retries as plaintext and never
   auto-creates a replacement database over an unreadable one.
6. A plaintext legacy database cannot be opened by a production repository.
   Migration, quarantine, reset, backup, and deletion require an explicit
   reviewed transition.
7. Synthetic test providers, fixture keys, and development-plaintext authority
   cannot be constructed or selected by production code, runtime input, or
   configuration.
8. Key creation, persistence, rotation, and recovery have crash-consistent
   state transitions and never leave an ambiguous database/key pairing.
9. All application-owned plaintext and key buffers use bounded lifetimes and
   verified clearing. Database-library page-cache behavior is included in
   backend qualification.
10. Windows x64 and ARM64, packaging, restart, WAL, rollback, corruption, and
    recovery tests pass without recording value-bearing artifacts.
11. An authenticated freshness authority and restore-lineage policy detect
    replay of an otherwise valid older database, sidecar, and wrapped-key set.
12. Production repository directories and sidecars use the approved Windows
    access-control policy, reject reparse-point substitution, and preserve
    parent/leaf file identity across classification and authentication.
13. Qualification evidence binds every applicable scenario to the matching
    x64 or ARM64 executable, package inventory and manifest, toolchain, OS
    build, PE target, and conformance harness.

## State classification

The current production state is:

`unavailable_authenticated_storage_backend_unselected`

The executable model also reserves these later unavailable checkpoints:

- `unavailable_operating_system_custody_provider_unimplemented`
- `unavailable_recovery_policy_unapproved`
- `unavailable_legacy_plaintext_transition_unapproved`

The source-selected production repository factory exposes no state field and
uses the current source constant only. Its private exhaustive gate recognizes
these unavailable checkpoints, and every one returns
`error.ProductionStorageUnavailable` before calling a provider, backend,
location, schema, PRAGMA, or migration callback.

There is intentionally no `ready`, `enabled`, `encrypted`, or `qualified`
state. Adding one requires a follow-up ADR that names the backend and provider,
defines their key lifecycle and recovery behavior, records the qualification
evidence, and changes the executable boundary in the same reviewed change.

## Development and test-only plaintext boundaries

Plaintext persistence remains useful for deterministic schema, migration,
rollback, replay, and corruption tests using synthetic values. It is classified
as `synthetic_plaintext_test_only`.

The capability that represents this classification:

- is opaque and contains no key material;
- can be obtained only while Zig is compiling a test artifact; and
- does not imply that an on-disk artifact is safe to retain or distribute; and
- is checked by identity against a private module token, so a forged opaque
  pointer does not grant plaintext persistence authority.

The opaque production type is also not sufficient authority by itself. Current
source rejects a fabricated production pointer and has no successful validator.

The raw exact-draft Store and adapter APIs enforce the test authority. Broader
calendar, profile, and legacy-draft file persistence uses a different opaque
development capability. Its only minting path is the source-selected
current-artifact bootstrap; both stores identity-check it before inspecting a
path. In-memory constructors remain explicitly ephemeral. This enforcement is
not encryption: until those surfaces are refactored behind the typed
production factory and an approved custody-aware repository type, they remain
development-only and the Native exact page must keep durable persistence
unavailable.

## Deferred authority

The repository can implement the fail-closed boundary and tests without
choosing policy on behalf of the product owner. The following decisions require
external security, product, and operational authority:

- authenticated storage backend, version, license, build provenance, and
  update policy;
- operating-system custody provider and user, machine, application, or
  user-presence scope;
- whether Windows sign-in alone is sufficient or interactive authentication is
  required;
- backup, export, device transfer, administrator password reset, disaster
  recovery, and unrecoverable-key UX;
- rotation cadence and recovery from interrupted rotation;
- anti-rollback freshness authority and backup/restore-lineage policy;
- handling of existing plaintext development databases; and
- code signing, installer identity, release hardening, and support procedures.

The executable requirements vocabulary keeps these as ten explicit
outstanding decisions: backend product/version/license; backend provenance and
updates; custody provider/scope; user presence; backup/export/device transfer;
password reset/disaster recovery/unrecoverable-key UX; rotation and interrupted
rotation; anti-rollback freshness and restore lineage; legacy plaintext
disposition; and release signing/hardening/support.

Until those decisions and their qualification evidence exist, the production
capability, production-release build, and exact Native persistence remain
unavailable by construction. Existing calendar and tax-profile repositories
remain callable only from the source-classified development artifact after
capability validation. They are not encrypted and must not receive production
taxpayer data.
