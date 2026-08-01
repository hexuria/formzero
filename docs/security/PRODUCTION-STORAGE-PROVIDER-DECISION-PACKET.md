# Production storage provider decision packet

- Status: Decision required; no provider is selected by this document
- Prepared: 2026-07-31
- Scope: Windows x64 and ARM64 local taxpayer-data persistence
- Governing boundary:
  [ADR-0001](ADR-0001-PRODUCTION-LOCAL-STORAGE-KEY-CUSTODY.md)

## Purpose

ADR-0001 correctly keeps production persistence unavailable. This packet
narrows the remaining external decision to candidates that can plausibly meet
that ADR. It is not authority to buy, ship, enable, or claim qualification for
either candidate.

The provider-neutral source vocabulary currently enumerates eight protected
artifact surfaces and fifteen authenticated-backend requirements. Provider
review may add more; it may not silently remove any of these.

The eight surfaces are the primary database, WAL, shared-memory index,
rollback journal, statement/temporary spill, backup/export copies,
migration/rotation copies, and wrapped-key/custody metadata.

The fifteen backend requirements are confidentiality and authenticity; whole-
surface coverage; authentication before SQL or PRAGMA; no plaintext probe or
fallback; no creation over an unreadable repository; key/cipher-version
binding; database/sidecar anti-swap binding; truncation, tamper, and replay
detection; trusted freshness and restore-lineage binding; crash-consistent
create/migrate/rotate; bounded and cleared application buffers; a qualified
database library/page cache; Windows directory and sidecar access control;
reparse-resistant handle-relative resolution; and parent/leaf file-identity
continuity.

Qualification additionally requires Windows x64 and ARM64 release artifacts
with distinct executable/package/toolchain/OS/harness identities and pinned
provenance. Provider and backend evidence is architecture-scoped: product and
configuration identity must remain stable, each architecture must bind its own
binary, and no scenario may reuse the other architecture's implementation
record. Qualification also requires operating-system custody for a random
database key; fail-closed handling of missing, corrupt, replayed, swapped,
wrong-user, wrong-machine, wrong-application, unsupported, revoked, or expired
custody state; exact coverage of all nine repository artifact states; approved
recovery and repository-transition policies; a trusted freshness/restore-
lineage decision; and Windows ACL, reparse, and file-identity attack
qualification.

The checked-in evidence validator can reject incomplete, duplicated, expired,
revoked, cross-wired, or self-selecting records. It requires an exact eight-cell
x64/ARM64 by prohibited-purpose matrix proving database-at-rest material and
handles distinct, non-derived, and non-reused relative to submission protocol,
application credentials, signing identity, and taxpayer identifiers. Repository
state results, key-separation records, scenarios, and decisions are bound into
the canonical record set. The validator does not authenticate a real approver
or vendor artifact by itself, select either candidate, or authorize production.

## Authenticated SQLite candidates

| Candidate | Evidence in favor | Qualification issue | Decision |
| --- | --- | --- | --- |
| SQLCipher 4.17 Windows C/C++ Commercial or Enterprise | The vendor's current Windows package supports x64 and ARM64 and supports static or dynamic linking. Its design encrypts WAL page data and authenticates each encrypted page with an HMAC. `cipher_integrity_check` independently checks page HMACs. | Procurement and license terms require approval. The exact package, crypto provider, license-delivery mechanism, build flags, and runtime files must be pinned. Full-library memory wiping is disabled by default and must be explicitly evaluated. | Recommended technical baseline for qualification, pending commercial and security approval. |
| SQLite SEE using the Windows AES-256-GCM/Bcrypt implementation | It is maintained by the SQLite project, is a drop-in amalgamation, and has a Windows AES-256-GCM implementation. The license permits distribution of qualifying compiled binaries. | The commonly recommended SEE AES-256-OFB mode does not provide authentication and therefore does not meet ADR-0001. The GCM/Bcrypt variant must be selected explicitly. SEE documents that TEMP tables are not encrypted, some header bytes remain visible, and database pages are plaintext in memory. The team must build and qualify both architectures itself and comply with source-redistribution restrictions. | Viable alternate only after GCM-specific, TEMP-surface, build-provenance, and licensing review. |

SQLCipher is the narrower qualification path because its official Windows
package already covers both required architectures and its documented default
design includes encrypted WAL pages and per-page authentication. That is a
technical recommendation, not an accepted product or purchasing decision.

### Candidate sources

- Zetetic, [SQLCipher 4.17.0 release](https://www.zetetic.net/)
- Zetetic,
  [SQLCipher for Windows C/C++](https://www.zetetic.net/sqlcipher/sqlcipher-windows/)
- Zetetic, [SQLCipher design](https://www.zetetic.net/sqlcipher/design/)
- Zetetic, [SQLCipher API](https://www.zetetic.net/sqlcipher/sqlcipher-api/)
- Zetetic, [SQLCipher license information](https://www.zetetic.net/sqlcipher/license/)
- SQLite,
  [SQLite Encryption Extension documentation](https://sqlite.org/see/doc/release/www/readme.wiki)
- SQLite,
  [SQLite SEE license](https://sqlite.org/com/license-see.html)

Versions, prices, delivery contents, and license terms must be rechecked at
procurement and then frozen in reviewed source. A trial artifact cannot become
a production dependency.

## Windows custody candidates

### DPAPI CurrentUser

`CryptProtectData` is the simplest candidate for wrapping a random database
key. Microsoft documents that, normally, the same user's logon credentials
and the same computer are required to recover protected data.
`CryptUnprotectData` also performs an integrity check.

The database key, not the database itself, should be the small protected
payload. The application must use user scope; `CRYPTPROTECT_LOCAL_MACHINE`
would broaden recovery to the computer and is not an acceptable silent
substitute for a user-scoped decision.

DPAPI's prompt-based flow is not a basis for user-presence policy. Microsoft
now marks that flow deprecated and says it will be removed in February 2027.
If interactive authentication is required, a separately reviewed mechanism is
needed.

Sources:

- Microsoft,
  [`CryptProtectData`](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)
- Microsoft,
  [`CryptUnprotectData`](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptunprotectdata)
- Microsoft,
  [CNG cryptography selection guidance](https://learn.microsoft.com/en-us/windows/win32/seccng/cng-portal)

### DPAPI-NG

`NCryptProtectSecret` protects key material to a protection descriptor.
Microsoft positions DPAPI-NG for data that must be accessible to multiple
users or machines after authorization. Its currently documented principal
models include Active Directory groups and web credentials.

DPAPI-NG is relevant only if managed multi-device or multi-user recovery is a
product requirement. It is not a drop-in promise of consumer device transfer;
the deployment identity, principal lifecycle, offline behavior, and recovery
authority must be designed and tested.

Sources:

- Microsoft,
  [`NCryptProtectSecret`](https://learn.microsoft.com/en-us/windows/win32/api/ncryptprotect/nf-ncryptprotect-ncryptprotectsecret)
- Microsoft,
  [CNG DPAPI functions](https://learn.microsoft.com/en-us/windows/win32/seccng/cng-dpapi-functions)

## Recovery authority is a product decision

Choose exactly one initial posture:

1. **Local-only, fail-closed.** The database is intentionally unrecoverable
   after loss of the Windows user profile, machine, and all approved backups.
2. **Explicit user-controlled transfer/recovery.** Design a separately
   authenticated export that rewraps the database key. Define lost-credential,
   revocation, expiry, support, and disclosure behavior before implementation.
3. **Managed enterprise recovery.** Use an approved DPAPI-NG or domain-backed
   model with named administrators, audit, and incident procedures.

Ordinary DPAPI behavior differs on domain-joined systems. Microsoft documents
that Active Directory DPAPI backup keys can recover domain-user material and
that possession of those domain backup keys enables decryption for domain
users. Microsoft also states there is no officially supported rotation path
for those backup keys. Enterprise deployment therefore changes the trust and
recovery model and cannot be inferred from a successful workstation test.

Source:

- Microsoft,
  [DPAPI backup keys on Active Directory domain controllers](https://learn.microsoft.com/en-us/windows/win32/seccng/cng-dpapi-backup-keys-on-ad-domain-controllers)

## Proposed qualification profile

If SQLCipher plus DPAPI CurrentUser is approved, qualification should freeze:

- an exact SQLCipher release and edition;
- distinct x64 and ARM64 executable, package inventory, package manifest,
  library/runtime, toolchain, OS-build, PE-target, and conformance-harness
  identities and digests;
- static or dynamic linkage and every packaged runtime dependency;
- the compiled crypto provider and default cipher/KDF/HMAC settings;
- zero plaintext header configuration unless a reviewed requirement proves it
  necessary;
- memory-security configuration and measured resource impact;
- a binary key API that does not format the database key into SQL text;
- a value-free application/custody scope bound into the wrapped-key record;
- database, wrapped-key, schema, and migration-format versions;
- an approved freshness authority and restore lineage that do not treat a
  replayed but internally valid database/sidecar/wrapped-key set as current;
- owner-only repository/sidecar access control, reparse-resistant
  handle-relative resolution, and parent/leaf file-identity continuity;
- `cipher_status`, `cipher_integrity_check`, and ordinary SQLite integrity
  checks at reviewed lifecycle points; and
- a crash-consistent state machine for creation, rotation, migration,
  quarantine, recovery, and deletion.

The release matrix must include at least:

- create, commit, restart, WAL checkpoint, rollback, and backup;
- wrong user, wrong machine, missing provider, and unavailable provider;
- missing, truncated, corrupt, replayed, and swapped database/custody metadata;
- replay of a complete older database, WAL, shared-memory, and wrapped-key set,
  plus stale or unrelated protected backup restore;
- wrong key and plaintext SQLite files at the production path;
- hostile inherited ACLs, sidecar permission drift, junction/reparse swaps, and
  file replacement between classification and authentication;
- crash or forced termination at every durable transition;
- interrupted rotation and interrupted plaintext migration;
- x64-created/ARM64-opened compatibility where the product claims it;
- native execution of every applicable lifecycle row on both x64 and ARM64,
  bound to the matching artifact and conformance-harness digests;
- package inspection for the exact approved native dependencies; and
- diagnostics proving no key, license value, taxpayer value, or local path is
  emitted.

Passing provider-neutral unit tests is necessary but cannot satisfy this
matrix without the selected provider's actual bytes.

## Decisions needed before ADR-0001 can be replaced

1. Approve a named backend product, version, and license.
2. Approve its build provenance, update ownership, and update policy.
3. Approve an operating-system custody provider and identity scope.
4. Decide whether Windows sign-in is sufficient or separate user presence is
   required.
5. Approve backup, export, and device-transfer policy.
6. Approve password-reset, disaster-recovery, and unrecoverable-key UX.
7. Approve rotation cadence and interruption policy.
8. Approve an anti-rollback freshness authority and backup/restore-lineage
   policy, or explicitly narrow the replay-protection claim.
9. Decide whether existing plaintext development databases are quarantined,
   explicitly migrated, archived outside the product, reset, or deleted.
10. Approve installer/code-signing, release-hardening, and support policy.

The selected owners must then provide the licensed artifacts and authority to
run the complete x64/ARM64 qualification matrix. Until all ten decisions and
their evidence exist,
`unavailable_authenticated_storage_backend_unselected` remains the only honest
production state.
