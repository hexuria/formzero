# Plan: port buwiz-forms validation, printed forms and submission into formzero

Status: plan, tracked in [#95](https://github.com/hexuria/formzero/issues/95). Update both as work lands.

## Goal

Bring the parts of [hexuria/buwiz-forms](https://github.com/hexuria/buwiz-forms)
that already cover the 43-form eBIRForms scope into this Zig/Native SDK app,
without hand-redoing the research:

1. **Validation and calculations** with the same ordered first-error behaviour
   and exact alert text as the official Offline eBIRForms package.
2. **Printed forms**: the 43 frozen HTML sheets and their fill rules.
3. **Submission**: Final Copy plaintext, IAF encryption, dispatcher-backed
   SFTP upload, and receipt confirmation.

"Reuse" means reusing the language-neutral artifacts and the oracles that
prove them, and porting only the code that cannot be shared.

## What buwiz-forms has (pinned at `8a95f630`)

Verified by reading the repository, not by running it:

| Area | Where it lives | Reusable as |
| --- | --- | --- |
| Form inventory, 43 forms | `crates/bir-core/src/forms/support_level.rs` (`FORM_CAPABILITY_REGISTRY`), `docs/FORMS.md` | Data. 39 forms can be queued; 2200AN, 2200M, 2200P and 2200A cannot. 0 are marked `release_ready`. |
| Rule research corpus | `rules/forms/<form>-v<rev>/` (`fields.json`, `validations.json`, `calculations.json`, `workflow.json`, `fixtures/`, `gaps.md`), `rules/shared/` | Data. 659 JSON files, 2,007 validation rules, 623 calculations, 1,354 negative fixtures, each tied to an official HTA hash and line. |
| Executable validation | Hand-written Rust per form: `crates/bir-core/src/forms/form_*.rs` (`validate_on`, `recompute`, `to_bir_field_map`). Compiled rule IR (`crates/bir-rules`, `bir-rules-codegen`) only covers 2550Q today | Port target. The fixtures above are the acceptance tests. |
| Submit plaintext layouts | `crates/bir-core/data/official-xml/*.json` (51 layouts) and `official_xml.rs` (`write`, `read`, `js_escape`, `official_amount`) | Data plus a small generic writer to port. Layouts were produced by running each HTA's own `saveXMLsubmit()` loop in jsdom (`tools/official-xml`). |
| Byte-exact oracles | `crates/bir-core/tests/sample-payloads/*.official.xml`, `*.plain.xml`, `*.steps.json` (78 official samples), `sample_payloads_test.rs` | Data. Our plaintext must equal them byte for byte. |
| Official runtime oracle | `tools/official-xml/` (`oracle.js`, `runtime.js`, `gen_layout.js`) over the byte-exact official package | Tool. This repo's `Justfile` already requires Node. |
| Printed sheets | `html-frozen/<slug>/` (`index.html`, `form.css`, `writer-cells.json`, `provenance.json`), `base.css`, Arimo/Tinos fonts; generator in [hexuria/buwiz-forms-html](https://github.com/hexuria/buwiz-forms-html) (`v1-frozen`) | Data plus the fill pass in `crates/bir-print/src/frozen_html.rs` to port. |
| IAF encryption | `crates/bir-core/src/crypto.rs` (`compress_and_encrypt`: zlib level 9, then DCPcrypt-style AES-256-CBC with a SHA-256 key and an encrypted-zero-block IV) | Port. Output SHA-256 is pinned against the official `Encrypt.exe` in the sample tests. |
| Transport | `crates/bir-core/src/transport.rs` (dispatcher `tinDispatcherSFTP.php`, AES-256-CBC/PBKDF2-HMAC-SHA1 field unwrap, SFTP PUT to `/{formType}/{basename}`), `filing_queue.rs` (scoped authorization, lease, restart recovery), `receipt.rs` (IMAP receipt parse) | Port. Evidence: `evidence/sftp-submission/` records a live PUT and BIR receipt for 1601C with the dummy TIN. |

What it does not prove: live submission is evidenced for one form (1601C,
dummy TIN). The other 38 queueable forms are proven at the plaintext and
ciphertext level against the official runtime, not by live filing. This plan
keeps that distinction.

## What this repository has

- Exact-form engine in `src/form_engine/`: a compile-time package contract
  (`package.zig`, 14 required parts) with three packages: 1701Q (identity-ready),
  1601C (identity-ready, other parts fail closed), 1601EQ (incomplete script
  closure).
- Ordered validation already ported line-by-line from the HTA for those forms
  (for example `form_1601c_2018/validation.zig`).
- Editable-save and Final Copy plaintext codecs; a decrypt-only legacy
  container codec (`src/container_codec/legacy.zig`) gated on 67 private
  known-answer vectors.
- Ten `.native` form layouts in `src/pages/forms/`; no WebView (`app.zon`:
  `webview_layer = "exclude"`), so no HTML print path yet.
- A hard offline boundary: `transport_enabled = false` in `form_engine/draft.zig`,
  `evidence.zig` and the 1701Q state modules, and
  [`docs/submit-path-findings.md`](../submit-path-findings.md) on why.

## Decision: data reuse plus a Zig port, not FFI

| Option | Verdict |
| --- | --- |
| Link `bir-core` as a C-ABI static library | Rejected. It pulls tokio, reqwest, russh, vendored OpenSSL, rusqlite/SQLCipher and IMAP into a Zig app that already owns SQLite, and adds a second toolchain to every platform build, including the Windows ARM64 workaround. |
| Link only `bir-rules` | Not enough. Its compiled IR covers 2550Q; the other 42 forms validate in hand-written `bir-core` code. |
| Shell out to the `bir` CLI | Kept only as a test oracle (differential testing), never as a runtime dependency. |
| **Vendor the language-neutral artifacts, generate what is mechanical, port the rest** | **Chosen.** Layouts, fixtures, sample payloads and frozen HTML are data; the writer, fill pass, crypto and validators are small enough to port, and the byte-exact oracles make a port checkable. |

Rules for the port:

- Every ported rule keeps its source: the official HTA hash and line (as this
  repo already does) **and** the buwiz-forms `rule_id`.
- Existing formzero packages (1701Q, 1601C, 1601EQ) are not replaced. Where
  both implementations exist, a differential test must show they agree; a
  disagreement is a finding to resolve against the official package, not a
  tie-break in favour of either repo.
- No binary floating point for amounts. buwiz-forms uses `f64` in several
  form models (for example `form_1601eq.rs` `rate_for_year`); ports use this
  repo's `domain/money.zig` decimals.
- Tax rules are never copied across forms because labels look alike (same rule
  as `docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md` §11).

## Workstreams

Each workstream lists its exit test. Nothing is "done" until the exit test
runs in CI (or, for live filing, on the recorded acceptance run).

### W0. Pin the latest official package

Checked 2026-10-14 on <https://www.bir.gov.ph/ebirforms>:

| Item | Value |
| --- | --- |
| Version on page | Offline eBIRForms Package v7.9.6.2.1 |
| Download | `https://bir-cdn.bir.gov.ph/BIR/pdf/Offline_eBIRForms_Package_v7.9.6.2.1.zip` |
| ZIP | 18,485,242 bytes, SHA-256 `28fab6775ef8b8d37f2ba09e178b7badc84572c9436378f729d3f31ecffdfe1b`, `Last-Modified: Fri, 09 Oct 2026 02:07:07 GMT` |
| Installer inside | `Offline_eBIRForms_Package_v7.9.6.2 1.exe`, 18,507,965 bytes, SHA-256 `e34979cf3c51d48228e239b348aef76674c4847036ba0f966799ecd3ecba96b6` (matches the hash BIR prints on the page) |
| Release notice | RMC No. 104-2026 (2026-09-24) announces 7.9.6.2 |

buwiz-forms' README targets the same 7.9.6.2.1, but its rule corpus records
`package_version` 7.9.6.0 and its changelog pins `BIRForms.exe` 7.9.6.1. The
ZIP was re-published on 2026-10-09, so the installer contents still have to
be compared before trusting any pin.

- The installer is Inno Setup; `7z` cannot open it. Unpack with
  `innoextract` (no execution), hash every `forms/*.html` HTA plus
  `BIRForms.exe`, `Encrypt.exe` and `ebfSFTP.exe`, and record them in
  `docs/evidence/ebirforms-package.md`. Never commit the installer or
  extracted official files.
- Compare those hashes with the buwiz-forms pins (rule corpus source-set
  hashes, `docs/FORMS.md` `Encrypt.exe` SHA-256). Only forms whose HTA hash
  differs need re-research.
- Use [hexuria/rea](https://github.com/hexuria/rea) where the claim depends on
  shipped binaries: `inspect_managed_artifact` on `ebfSFTP.exe` / `BIRForms.exe`
  (.NET) to confirm the live submit path and dispatcher constants, and
  `analyze_javascript_application` on HTA scripts when a validation path is unclear.
- Reconcile [`docs/submit-path-findings.md`](../submit-path-findings.md)
  (HTA `uploadXMLFile` HTTP path) with buwiz-forms
  `evidence/sftp-submission/` (7.9.6.x submits through `ebfSFTP.exe` and the
  dispatcher). Record which path the pinned package actually calls.

Exit test: evidence file merged; per-form HTA hash diff table attached to the
tracking issue.

### W1. Vendor buwiz-forms artifacts with provenance

- Add `scripts/buwiz-sync.mjs` that copies, from a pinned buwiz-forms commit,
  into `vendor/buwiz-forms/`:
  `rules/forms/**`, `rules/shared/**`, `crates/bir-core/data/official-xml/*.json`,
  `crates/bir-core/tests/sample-payloads/**`, `html-frozen/**` (including
  fonts and `provenance.json`).
- Write `vendor/buwiz-forms/MANIFEST.json`: source commit, path, SHA-256 per
  file. `just check` fails if any vendored byte differs from the manifest.
- Licence check before the first sync: buwiz-forms is MIT; frozen HTML and
  sample payloads are derived from official BIR material. Record the decision
  in the manifest, as `docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md` §2
  requires for HTA-derived material.

Exit test: `node scripts/buwiz-sync.mjs --check` in CI.

### W2. Generic engine pieces in Zig

Port once, reuse for every form:

| Piece | Source | Zig home | Oracle |
| --- | --- | --- | --- |
| Layout replay writer/reader (ordered entries, repeated keys, folded fields, defaults) | `official_xml.rs` | `src/form_engine/official_layout.zig` | every `*.official.xml` sample |
| `js_escape`, `official_amount` | `official_xml.rs` | same | unit vectors from the samples |
| Comptime layout loader (JSON embedded with `@embedFile`, parsed at build time; no runtime JSON parsing of untrusted data) | `data/official-xml/*.json` | `build.zig` step generating one `.zig` per layout | generated file is checked in and diffed |
| Fixture runner: load `fixtures/negative-cases.json` and positive cases, apply field values, assert first error id and message | `rules/forms/*/fixtures/` | `src/form_engine/rule_fixtures.zig` (tests only) | the fixtures themselves |

Layout replay must stay occurrence-first, as the existing engine is: repeated
ordered keys are why a plain field map is lossy.

Exit test: all 78 official sample plaintexts reproduced byte for byte from
their `*.steps.json` inputs through the Zig writer.

### W3. Per-form validation and calculations

For each form, in the order below:

1. Generate the occurrence table and editable/final-copy codec skeleton from
   the vendored layout and `fields.json`.
2. Port `recompute` and `validate_on` from `crates/bir-core/src/forms/form_<code>.rs`,
   cross-checked against `rules/forms/<form>/validations.json` and the HTA
   lines they cite. Keep the official validation order and exact alert text.
3. Fill the 14 parts `package.zig` requires; register in
   `src/form_engine/root.zig`.
4. Tests: every negative fixture fails with the expected first error; every
   sample payload round-trips; a differential test runs the buwiz-forms `bir`
   CLI (dev only, optional in CI) on the same inputs and compares field maps.

For 1701Q, 1601C and 1601EQ the formzero port already exists: run step 4
only and file disagreements.

Order (follows `FORM_BUILD_PRIORITY.md`, then by queue readiness):

1. 1601C, 1701Q, 1601EQ (differential only)
2. 0619E, 0619F, 1702Q, 2550Q, 2551Q, 0605 (layouts already in `src/pages/forms/`)
3. 1701, 1702RT, 1702MX, 1702EX, 1701A (annual returns)
4. Remaining queueable forms from `docs/FORMS.md` in buwiz-forms
5. 2200A, 2200AN, 2200M, 2200P last: buwiz-forms cannot queue them either

Exit test per form: the fixture runner and sample round-trip pass in
`just test`; a row in the coverage matrix below is ticked.

### W4. Printed forms from frozen HTML

The app has no WebView. Two ways to use the frozen sheets:

| Option | Cost | Notes |
| --- | --- | --- |
| A. Enable the Native SDK WebView only for a read-only print preview window | Small | Follow `docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md`: bundled assets only, strict CSP, no bridge, no remote origins, no script. Print/PDF through the system webview. |
| B. Keep native layouts and use frozen HTML only as the visual oracle | Large (43 native sheets) | No new attack surface; visual parity has to be rebuilt per form. |

Recommendation: **A** for print and PDF, native editors unchanged. This is a
change to the security boundary and needs an owner decision before work
starts.

Port `crates/bir-print/src/frozen_html.rs` fill to Zig: fill by
`input[name]`, TIN/name stamps, leftover writer keys, comb text, money, date and
checkbox joins, repeated keys across pages. Output is a static HTML string
with no scripts.

Exit test: filled HTML for each sample equals the buwiz-forms fill output for
the same inputs (golden files), and each sheet passes the buwiz-forms-html
structural print-parity check (it replaced raster pixel diffing; see
`tools/formgen/README.md` there).

### W5. Final Copy and IAF encryption

- Port `compress_and_encrypt` / `decrypt_and_decompress` from `crypto.rs`:
  zlib level 9, then AES-256-CBC with a SHA-256-derived key and an IV from
  encrypting a zero block, matching DCPcrypt and the official `Encrypt.exe`.
- AES-256 and SHA-256 come from `std.crypto`. zlib is the risk: the
  ciphertext is pinned byte for byte, so the compressor must emit exactly what
  zlib level 9 emits. If Zig's deflate does not, build vendored zlib from C in
  `build.zig` (Zig compiles C natively, no second toolchain).
- Reconcile with `src/container_codec/legacy.zig`: the buwiz-forms sample
  ciphertexts become additional public known-answer vectors; the encrypt
  direction stays behind the same qualification gate.
- Passphrases come from runtime configuration, never from source or tests in
  this repo.

Exit test: Zig ciphertext SHA-256 equals the pinned value for every sample
that has one; decrypt round-trip for all of them.

### W6. Submission (lifts the offline boundary)

This repository is offline by design (`transport_enabled = false`). Shipping
submission needs an architecture decision record before any network code:
`docs/adr/000N-bir-sftp-submission.md`, approved by the owner.

Design, ported from buwiz-forms `transport.rs` and `filing_queue.rs`:

- **Never** reuse the HTA HTTP upload path described in
  `docs/submit-path-findings.md` (credentials and XML in query strings).
- Transport is a single module `src/transport/` behind an interface with three
  implementations: in-process fake (default), loopback SFTP for tests, and
  production. Production only when `BIR_SFTP_LIVE=1` **and** the user confirms
  a per-filing authorization in the UI.
- Endpoint resolution: `tinDispatcherSFTP.php` returns AES-256-CBC fields
  (PBKDF2-HMAC-SHA1) that are unwrapped into SFTP host, user and password.
  PUT the IAF to `/{formType}/{basename}`.
- Fix the weaknesses buwiz-forms keeps on purpose
  (`evidence/sftp-submission/PROTOCOL.md`): pin the `ebf2.bir.gov.ph`
  host key once recorded, and do not fall back from HTTPS to HTTP on a
  certificate error. If BIR's server forces either, fail closed and surface it.
- SSH/SFTP: link libssh2 (C, built in `build.zig`) rather than writing SSH in
  Zig. Decide in the ADR.
- Queue: port the `filing_queue.rs` state machine (scoped authorization,
  lease, restart recovery, submitted vs confirmed) onto this repo's SQLite.
  Preflight re-runs full validation and re-derives the plaintext from the
  saved draft; a stale or edited draft cannot be sent.
- Logs and receipts never contain credentials, passphrases or plaintext
  payloads.

Exit test: loopback SFTP integration test in CI; fake transport is the default
in every test. Live acceptance is a separate, owner-authorized run with the
the dummy TIN buwiz-forms used for its live proof (`00000000000000`) only, recorded in `docs/evidence/`.

### W7. Receipt confirmation

Port `receipt.rs` (IMAP fetch and sanitizing parse). Match on TIN, form and
period, not filename (BIR strips `#email#`). A filing is **confirmed** only
when a matching receipt exists; until then it is **submitted**.

Exit test: parser fixtures from buwiz-forms (sanitized) pass; queue moves to
confirmed only on a matching fixture.

### W8. Product gates

Per form, the app shows the same capability flags buwiz-forms uses in
`support_level.rs`, computed from what actually passed here, not copied:
`validation`, `editable_save`, `final_copy`, `print`, `queue_submission`,
`receipt`. A form is offered for submission only when all prior gates pass.

## Coverage matrix

Tick a cell only when its exit test passes in this repo.

| Form | W3 validation | W2 plaintext | W4 print | W5 IAF | W6 queue | W7 receipt |
| --- | --- | --- | --- | --- | --- | --- |
| 1601C | | | | | | |
| 1701Q | | | | | | |
| 1601EQ | | | | | | |
| _remaining 40 forms, from buwiz-forms `docs/FORMS.md`_ | | | | | | |

The tracking issue keeps one checkbox per workstream and per form group.

## Risks and open decisions

1. **Package drift.** BIR shows v7.9.6.2.1, the version buwiz-forms targets,
   but the ZIP was re-published on 2026-10-09 and the rule corpus records
   7.9.6.0. Until W0 compares HTA hashes, parity claims hold only for the
   package buwiz-forms actually researched.
2. **Validation is hand-written Rust, not data.** For 42 forms the executable
   rules live in code; the corpus is evidence and fixtures. Porting is the bulk
   of the effort, roughly one form per day once W2 is in place.
3. **zlib byte-exactness** (W5).
4. **Security boundary changes** need owner approval: WebView for print (W4)
   and network transport (W6).
5. **Live filing** is proven for one form in buwiz-forms. Do not claim more
   for this app until its own acceptance runs say so.
6. Disagreements between the two repos on 1701Q, 1601C and 1601EQ are resolved
   against the official package, with the evidence recorded in both repos.

## Verification commands

- This repo: `just check`, `just test`, `just verify`.
- buwiz-forms oracle: `just test` (includes `sample_payloads_test.rs`),
  `npm run rules:check`.
- Sync drift: `node scripts/buwiz-sync.mjs --check`.

Safety for every run: dummy TIN only, fake or loopback transport unless the
owner authorizes a live run, no real taxpayer data in fixtures or logs.
