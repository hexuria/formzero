# Goal prompt: Windows-first grounded 1701Q filing core

Work in `W:\Projects\ebirforms.0` on `main`'s current tax-profile baseline.
Follow
`docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md` as the governing plan.

## Objective

Build the first grounded, end-to-end **offline** form implementation for
**BIR Form 1701Q, January 2018 ENCS, Offline eBIRForms 7.9.6** on Windows
ARM64.

The finished vertical slice must:

- build and run with Native SDK 0.6.1 and Zig 0.16.0 on Windows ARM64;
- compose exactly one filer and zero/one distinct spouse from reusable,
  effective-dated tax profiles;
- preserve immutable profile snapshots and explicit profile refresh;
- implement typed transaction state, official calculations, and the exact
  ordered validation entry points;
- preserve ordered/repeated field occurrences;
- save, close, reopen, and reproduce the same draft and provenance;
- encode/decode exact editable-save and Final Copy plaintext bytes;
- locally decrypt, strictly parse, and compare controlled encrypted artifacts;
- enable official-compatible encryption only if the Windows implementation
  passes all 67 private exact known-answer vectors;
- show plaintext, encrypted, decrypted, hashes, qualification, and differences
  in a masked-by-default Offline Artifact Lab; and
- make zero network or submission attempts.

Do not start another form.

## Required working rules

1. Preserve user changes and keep derived caches platform-specific.
2. Ground every semantic decision in the byte-verified Desktop audit,
   official BIR 1701Q PDF/guide, paired synthetic oracle captures, or an
   explicit reviewed inference.
3. Use exact package identity and evidence hashes; `form_code` alone is never
   enough.
4. Keep tax profile, form engine, byte codecs, container codec, UI, and future
   transport as separate modules.
5. Use an ordered occurrence list as serializer authority; never serialize
   from a map.
6. Preserve first-error validation order and distinct validate/save/final
   workflows.
7. Use decimal/fixed-point money with explicit evidence-backed rounding.
8. Never commit or log raw/decrypted XML, taxpayer values, credentials,
   protocol secrets, endpoints, original value-bearing filenames, or
   value-bearing screenshots.
9. Use only synthetic data in an egress-blocked disposable oracle
   environment. Never ship or invoke the unsigned legacy helpers from the app.
10. Keep encryption fail-closed when vectors are missing, skipped, or
    mismatched. A candidate compressor must not be called official-compatible.
11. Do not reuse FSL-covered/rebuilt implementation source without explicit
    provenance/license approval; prefer a clean-room implementation from
    value-free findings and independent tests.
12. No live BIR/eFPS/SFTP/HTTP submission, authentication, receipt, or queue
    transition.

## Initial sequence

1. Record the current repo status and baseline without disturbing user work.
2. Create/use a Windows-specific worktree and caches.
3. Install/verify Git, Node >=22.15, official Zig 0.16.0 AArch64, and set an
   absolute `NATIVE_SDK_ZIG` path. Run a clean Windows `npm ci` and verify
   `@native-sdk/cli-win32-arm64@0.6.1`.
4. Port `app.zon` and the runtime scene from macOS/Metal-only to a tested
   Windows software/cross-platform configuration.
5. Run generation, catalog checks, `zig build`, `zig build test`,
   null-platform Native tests, strict Native check, Windows build, doctor, and
   a GUI smoke test. Record the real baseline.
6. Freeze the 1701Q exact package/dependency/evidence manifest, including HTA
   SHA-256
   `5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0`.
7. Implement the architecture phases A-G in the governing plan, testing each
   phase before proceeding.

## Evidence sources

- Desktop audit:
  `C:\Users\uriah\Desktop\eBIRForms-Core-Logic-Audit-2026-07-30`
- Installed official package:
  `C:\eBIRForms`
- Payload research:
  `W:\Projects\ebirforms-form-payload-research`
- Merged tax-profile architecture:
  `W:\Projects\ebirforms-tax-profile-architecture`
- Priority order:
  `W:\Projects\ebirforms.0\FORM_BUILD_PRIORITY.md`

Treat sibling worktrees as read-only evidence unless deliberately importing
reviewed, provenance-safe changes into `main`.

## Required verification

Run all existing tests plus:

- exact source/dependency drift tests;
- profile identity/civil-status/successor/role/snapshot tests;
- calculation and rounding boundary tests;
- ordered first-error validation differential tests;
- occurrence/order/duplicate/selective-encoding tests;
- editable/final exact byte and strict parser tests;
- persistence migration/rollback/concurrency/save-reopen tests;
- cipher KATs, all 67 private decrypt vectors, and all 67 private exact encrypt
  vectors before enabling outbound encryption;
- corruption, wrong-secret, size, zlib trailing-data, UTF-8, and malformed
  payload negative tests;
- Native model/tree/accessibility tests;
- Windows GUI automation, print/PDF, packaging, offline restart, network-denial,
  and value-free logging scans.

Missing private fixtures must produce `not qualified`/failure, never a skipped
passing release gate.

## Handoff

Maintain a concise progress ledger with:

- changes made;
- commands and results;
- evidence IDs;
- test totals;
- unresolved gaps;
- encryption qualification state;
- security/provenance review; and
- exact next action.

The goal is complete only when 1701Q passes every applicable promotion gate in
the governing plan, or the remaining fail-closed blocker genuinely requires
new user authority/external evidence. Do not continue to 1601C or 1601EQ
without a separate user review.

