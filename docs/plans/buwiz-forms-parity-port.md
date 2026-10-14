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
| Byte-exact oracles | `crates/bir-core/tests/sample-payloads/*.official.xml`, `*.plain.xml` (78 each), `*.steps.json` (UI scripts for the jsdom oracle: `click`, `set`, `call`), typed drafts in `crates/bir-core/tests/sample_payloads/form_*.rs` | Test data, vendored as binary and SHA-checked; committed only after the §2 amendment, fetched at test time until then. All 78 are pure ASCII with LF line endings. Only 7 forms have a `positive-minimal.json` fixture. |
| Official runtime oracle | `tools/official-xml/` (`oracle.js`, `runtime.js`, `gen_layout.js`) over the byte-exact official package | Tool. This repo's `Justfile` already requires Node. |
| Printed sheets | `html-frozen/<slug>/` (`index.html`, `form.css`, `writer-cells.json`, `provenance.json`), `base.css`, Arimo/Tinos fonts; generator in [hexuria/buwiz-forms-html](https://github.com/hexuria/buwiz-forms-html) (`v1-frozen`) | Data plus the fill pass in `crates/bir-print/src/frozen_html.rs` to port. |
| IAF encryption | `crates/bir-core/src/crypto.rs` (`compress_and_encrypt`: C zlib level 9 through `libz-sys`, then DCPcrypt's AES-256 chaining: SHA-256 key, encrypted-zero-block IV, CBC on full blocks, final partial block XORed with the encrypted chaining value, no padding, so ciphertext length equals compressed length) | Port by extending `legacy.zig`. The 78 ciphertext SHA-256 pins came from unicorn emulation of `Encrypt.exe`, not a native run. The passphrase is hardcoded in `crypto.rs` and is not ported. |
| Transport | `crates/bir-core/src/transport.rs` (dispatcher lookup, AES-256-CBC/PBKDF2-HMAC-SHA1 field unwrap with a second static secret, UTF-8 BOM kept, SFTP PUT to `/{formType}/{basename}`), `filing_queue.rs` (scoped authorization, lease, restart recovery), `receipt.rs` (IMAP receipt parse) | Port. Evidence: `evidence/sftp-submission/` records a live PUT and BIR receipt for 1601C with the dummy TIN. |

What it does not prove: live submission is evidenced for one form (1601C,
dummy TIN). The other 38 queueable forms are proven at the plaintext and
ciphertext level against the official runtime, not by live filing. This plan
keeps that distinction.

## What this repository has

- Exact-form engine in `src/form_engine/`: a compile-time package contract
  (`package.zig`, 14 required parts) with three packages: 1701Q (identity-ready),
  1601C (identity, print preparation, validate lock, import paths, encryption
  path and remittance totals ready, plus `transaction_submit.zig`; the
  `root.zig` comment saying "every other part fail-closed" is stale), and
  1601EQ (incomplete script closure).
- Ordered validation already ported line-by-line from the HTA for those forms
  (for example `form_1601c_2018/validation.zig`).
- Editable-save and Final Copy plaintext codecs; a decrypt-only legacy
  container codec (`src/container_codec/legacy.zig`) that takes the protocol
  secret as a parameter (`EmptyProtocolSecret` if absent) and is gated on 67
  private known-answer vectors. `editable_serializer_exact` and
  `final_plaintext_serializer_exact` are false for every form until the ANSI
  code-page captures in `docs/ansi-code-page-capture.md` qualify the encoding.
- Eleven `.native` form layouts in `src/pages/forms/` (0605, 0619-e, 0619-f,
  1601-c, 1601-eq, 1701, 1701q, 1702-mx, 1702-rt, 2550q, 2551q); no WebView (`app.zon`:
  `webview_layer = "exclude"`), so no HTML print path yet.
- A hard offline boundary: `transport_enabled = false` in `form_engine/draft.zig`,
  `evidence.zig` and the 1701Q state modules, and
  [`docs/submit-path-findings.md`](../submit-path-findings.md) on why.
- Scope rules in `docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md`: §2 puts
  live submission, authentication, receipt handling and reuse of legacy
  transport helpers out of scope, and bans committing raw or decrypted XML,
  protocol secrets or endpoints. §12 says stop if a secret would land in git
  or work would cross into live transport. §11 allows one active exact form
  revision at a time.

## Decision: data reuse plus a Zig port, not FFI

| Option | Verdict |
| --- | --- |
| Link `bir-core` as a C-ABI static library | Rejected. It pulls tokio, reqwest, russh, vendored OpenSSL, rusqlite/SQLCipher and IMAP into a Zig app that already owns SQLite, and adds a second toolchain to every platform build. |
| Link only `bir-rules` | Not enough. Its compiled IR covers 2550Q; the other 42 forms validate in hand-written `bir-core` code. |
| Shell out to the `bir` CLI | Rejected. The official sample payloads are a better oracle and need no Rust toolchain. |
| **Reuse the language-neutral artifacts, generate what is mechanical, port the rest** | **Chosen.** Layouts, rule fixtures and frozen HTML are committed data; sample payloads and ciphertexts are vendored as binary and hash-checked (fetched at test time until §2 allows committing them); the writer, fill pass, crypto and validators are small enough to port, and the byte-exact oracles make a port checkable. |

Rules for the port:

- Every ported rule keeps its source: the official HTA hash and line (as this
  repo already does) **and** the buwiz-forms `rule_id`.
- Existing formzero packages (1701Q, 1601C, 1601EQ) are not replaced. Where
  both implementations exist, a differential test must show they agree; a
  disagreement is a finding to resolve against the official package, not a
  tie-break in favour of either repo. Both repos already read the same HTA
  bytes for these three forms (1601C `3fb7b418…`, 1701Q `5f164dde…`, 1601EQ
  `cd56bf18…` appear in formzero's evidence and buwiz-forms'
  `rules/forms/*/evidence.md`).
- No protocol secret is ported. buwiz-forms hardcodes the IAF passphrase in
  `crypto.rs` and a second static secret for the dispatcher field unwrap;
  here both come from private runtime configuration, as `legacy.zig` already
  requires.
- Nothing §2 bans is committed: no raw official XML, no ciphertexts, no
  endpoints. Until §2 is amended, raw samples are fetched at test time and
  checked against a committed hash manifest (W1).
- No binary floating point for amounts. buwiz-forms uses `f64` in several
  form models (for example `form_1601eq.rs` `rate_for_year`); ports use this
  repo's `domain/money.zig` decimals.
- Tax rules are never copied across forms because labels look alike (same rule
  as `docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md` §11).

## Prerequisite: amend the architecture plan before W6 and W7

`docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md` §2 puts live submission,
authentication, receipt handling and legacy transport helpers out of scope,
and §12 makes "work would cross into live transport" a stop condition. A
decision record alone does not lift that. Before any W6 or W7 code, the owner
merges a PR that amends §2 and §12 to say what is now in scope (dispatcher
lookup, SFTP upload, receipt parsing), what stays banned (secrets, endpoints,
raw XML in git), and which stop conditions still apply.

W0 to W5 do not need the amendment. They stay inside the current scope as
long as they follow the artifact rules below.

## Artifact rules (all workstreams)

| Artifact | Where it lives |
| --- | --- |
| Rule corpus, fixtures, layout JSON, frozen HTML | Committed under `vendor/buwiz-forms/` after the HTA source provenance and licence review in W1 |
| Official sample XML (`*.official.xml`, `*.plain.xml`), ciphertexts (`*.iaf.xml`) | Vendored as binary (`-text` in `.gitattributes`, so git never rewrites line endings) and checked against SHA-256 values in the committed manifest. §2 bans committed raw XML, so they enter git only once the §2 amendment allows these dummy-TIN samples; until then the same bytes are fetched at test time into an ignored cache and checked against the same manifest. |
| `*.steps.json` | Fetched at test time like the samples (only the W3 jsdom check uses them). |
| IAF passphrase, dispatcher unwrap secret | Never in this repo. Supplied at runtime by a private harness or private config. Tests that need them skip with a visible reason when absent. |
| Dispatcher and SFTP hosts | Runtime configuration, not source. §2 bans committed endpoints, so this plan refers to them through buwiz-forms `transport.rs`. |

These are two separate reviews: the licence and provenance review of
HTA-derived source, and the §2 ban on raw XML, taxpayer values, credentials,
secrets, endpoints and value-bearing screenshots. Passing the first does not
waive the second.

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

Already known, so W0 does not redo it: the HTAs formzero uses for 1601C, 1701Q
and 1601EQ have the same hashes as the buwiz-forms corpus. What W0 still has
to do is compare the v7.9.6.2.1 installer contents with the older pins:
buwiz-forms' rule corpus records `package_version` 7.9.6.0, its changelog
pins `BIRForms.exe` 7.9.6.1, and the ZIP was re-published on 2026-10-09.

- The installer is Inno Setup; `7z` cannot open it. Unpack with
  `innoextract` (no execution), hash every `forms/*.html` HTA plus
  `BIRForms.exe`, `Encrypt.exe` and `ebfSFTP.exe`, and record them in
  `docs/evidence/ebirforms-package.md`. Never commit the installer or
  extracted official files.
- Record the full `Encrypt.exe` SHA-256. buwiz-forms `docs/FORMS.md` only
  shows a truncated one.
- Compare those hashes with the buwiz-forms pins (rule corpus source-set
  hashes). Only forms whose HTA hash differs need re-research.
- Use [hexuria/rea](https://github.com/hexuria/rea) where the claim depends on
  shipped binaries: `inspect_managed_artifact` on `ebfSFTP.exe` / `BIRForms.exe`
  (.NET) to confirm the submit path and how the dispatcher is called, and
  `analyze_javascript_application` on HTA scripts when a validation path is
  unclear.
- The HTA HTTP upload path in [`docs/submit-path-findings.md`](../submit-path-findings.md)
  and the `ebfSFTP.exe` dispatcher path in buwiz-forms
  `evidence/sftp-submission/` ship in the same package. They are not a version
  difference. Record which one the BIRForms Submit button actually invokes.
- **HTTPS go/no-go for the dispatcher.** buwiz-forms evidence says the
  official `ebfSFTP` client calls the dispatcher over plain HTTP; buwiz-forms
  gets HTTPS by rewriting the scheme and falls back to HTTP. A TLS probe of
  both dispatcher hosts from our build machine on 2026-10-14 (port 443 only,
  no dispatcher request) got connection refused on one and a timeout on the
  other. Repeat from a Philippine network and record whether either host
  serves valid HTTPS. W6's transport policy depends on the answer.

Exit test: evidence file merged; per-form HTA hash diff table attached to the
tracking issue; HTTPS go/no-go recorded.

### W1. Vendor buwiz-forms artifacts with provenance

- Add `scripts/buwiz-sync.mjs` that copies, from a pinned buwiz-forms commit,
  into `vendor/buwiz-forms/`: `rules/forms/**`, `rules/shared/**`,
  `crates/bir-core/data/official-xml/*.json`, `html-frozen/**` (including
  fonts and `provenance.json`).
- `*.official.xml`, `*.plain.xml` and `*.iaf.xml` are vendored as binary:
  `.gitattributes` marks them `-text`. buwiz-forms' own `.gitattributes`
  (`* text=auto eol=lf`) normalizes every text file to LF and only marks
  `*.iaf.xml` binary, so the sync copies the exact bytes at the pinned commit
  and never lets git touch them again. Until the §2 amendment,
  `scripts/buwiz-sync.mjs --fetch-test-data` writes them (and `*.steps.json`)
  to an ignored cache instead, with the same manifest check.
- The manifest records each sample's line separator, because it differs per
  form (see "Line endings" below).
- Write `vendor/buwiz-forms/MANIFEST.json`: source commit, path, SHA-256 per
  file, for committed and fetched files alike. `just check` fails if a
  committed byte differs; tests fail if a fetched byte differs.
- HTA source provenance and licence review before the first sync: buwiz-forms
  is MIT, but the frozen HTML, layouts and rule text derive from official BIR
  material. Record the decision in the manifest.

Exit test: `node scripts/buwiz-sync.mjs --check` in CI.

### W2. Generic engine pieces in Zig

Port once, reuse for every form:

| Piece | Source | Zig home | Oracle |
| --- | --- | --- | --- |
| Layout writer/reader (ordered entries, repeated keys, folded fields, defaults) | `official_xml.rs` | `src/form_engine/official_layout.zig` | every `*.official.xml` sample |
| `js_escape`, `official_amount` | `official_xml.rs` | same | unit vectors from the samples |
| Comptime layout loader (JSON embedded with `@embedFile`, parsed at build time; no runtime JSON parsing of untrusted data) | `data/official-xml/*.json` | `build.zig` step generating one `.zig` per layout | generated file is checked in and diffed |
| Fixture runner: load `fixtures/negative-cases.json` and positive cases, apply field values, assert first error id and message | `rules/forms/*/fixtures/` | `src/form_engine/rule_fixtures.zig` (tests only) | the fixtures themselves |

The writer must stay occurrence-first, as the existing engine is: repeated
ordered keys are why a plain field map is lossy.

Exit test: for all 78 samples, read `*.official.xml` with the layout reader,
write it back with the layout writer, and get identical bytes. The
`*.steps.json` files are UI scripts for the jsdom oracle, not typed inputs,
so replaying them needs per-form recompute and belongs to W3.

This exit test is measured on the LF text buwiz-forms committed. It proves the
reader and writer are lossless, not that LF is what the official package
writes (see "Line endings"). It also does not qualify
`editable_serializer_exact` or `final_plaintext_serializer_exact` (risk 4).

### W3. Per-form validation and calculations

For each form, one exact revision active at a time (§11):

1. Generate the occurrence table and editable/final-copy codec skeleton from
   the vendored layout and `fields.json`.
2. Port `recompute` and `validate_on` from `crates/bir-core/src/forms/form_<code>.rs`,
   cross-checked against `rules/forms/<form>/validations.json` and the HTA
   lines they cite. Keep the official validation order and exact alert text.
3. Fill the 14 parts `package.zig` requires; register in
   `src/form_engine/root.zig`.
4. Tests:
   - every negative fixture fails with the expected first error;
   - the form's typed sample drafts (from buwiz-forms
     `crates/bir-core/tests/sample_payloads/form_<code>.rs`) recompute and
     write the fetched `*.official.xml` byte for byte;
   - where a `*.steps.json` exists, a dev-only jsdom run of it produces the
     same plaintext as the typed draft.

Positive fixtures are thin: only 7 forms have `positive-minimal.json`. For
the rest, the sample payloads are the only positive evidence, and each form's
promotion report says so.

For 1701Q, 1601C and 1601EQ the formzero port already exists. buwiz-forms'
`*.official.xml` files are Final Copy documents (they end in
`All Rights Reserved BIR 2012.0`), so the differential test compares formzero
codec output with them byte for byte; no `bir` CLI. Until the line-ending
capture lands, that comparison is structural only for 1601C and 1701Q: their
codecs pin CRLF and every buwiz-forms sample is LF. 1601EQ's `document.zig`
pins no separator yet and stays fail-closed. File any other disagreement.

### Line endings (blocks byte parity for 1601C and 1701Q)

- formzero pins tab + CRLF + 12 spaces (`separator = "	
            "`
  in `form_1701q_2018/document.zig` and `form_1601c_2018/document.zig`), from
  a controlled check of Windows' HTML engine (`docs/ansi-code-page-capture.md`).
- buwiz-forms' samples use tab + LF + 12 spaces for some forms (1601C, 1701Q
  among them) and spaces only for the rest (0619E, 0619F, 1600PT/VT, 1601EQ,
  1604C, …). None of the 78 `*.official.xml` files at `8a95f630` contains a
  `
`, and buwiz-forms' `* text=auto eol=lf` would strip one anyway.
- The `Encrypt.exe` SHA-256 pins in `sample_payloads/form_*.rs` were computed
  from those LF `.plain.xml` files, so they inherit the question.

Decide which line ending is real with one Windows capture, done in the
existing ANSI capture session (`docs/ansi-code-page-capture.md`). Until then,
buwiz-forms' samples are a structural oracle for 1601C and 1701Q, and every
"byte for byte" or SHA-pin result in this plan is labelled as measured on LF
text.

Order (from `FORM_BUILD_PRIORITY.md` and architecture plan §11):

1. **1701Q**: reference slice.
2. **Re-certify** 1601C, 0619E, 0619F against the new gates.
3. **Priority 2:** 1601EQ, 1702Q, 1601FQ, 1603Q.
4. **Priority 3:** 1600VT, 1600PT, 2550M.
5. **Priority 4:** 1701MS, 1701, 1701A, 1700, 1702RT, 1604C, 1604E, 1604F, 1702MX.
6. **Priority 5:** 1706, 1606, 1800, 1801, 2000OT, 2000.
7. **Deferred:** 1602Q, 1600WP, 1702EX, 1707, 1707A, then the remaining
   buwiz-forms forms. 2200A, 2200AN, 2200M and 2200P go last because
   buwiz-forms cannot queue them either.

Known evidence blockers from §11 still apply: 1601EQ is missing active
scripts, 1603Q lacks `tax-rate-helper.js`. buwiz-forms evidence for these
forms is checked against those gaps, not assumed to close them.

Exit test per form: the fixture runner and sample tests pass in `just test`;
a row in the coverage matrix below is ticked.

### W4. Printed forms from frozen HTML

The app has no WebView. Two ways to use the frozen sheets:

| Option | Cost | Notes |
| --- | --- | --- |
| A. Enable the Native SDK WebView only for a read-only print preview window | Small | Follow `docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md`: bundled assets only, strict CSP, no bridge, no remote origins, no script. Print/PDF through the system webview. |
| B. Keep native layouts and use frozen HTML only as the visual oracle | Large (43 native sheets) | No new attack surface; visual parity has to be rebuilt per form. |

Recommendation: **A** for print and PDF, native editors unchanged. This changes
the security boundary: it needs an owner decision and an architecture plan
amendment before work starts.

Port `crates/bir-print/src/frozen_html.rs` fill to Zig: fill by
`input[name]`, TIN/name stamps, leftover writer keys, comb text, money, date and
checkbox joins, repeated keys across pages. Output is a static HTML string
with no scripts.

Missing print/jurat image: §11 records that 1601C and 1601FQ lack it in the
official package. Check whether the frozen sheets for these forms contain a
recreated image, and with what provenance. If they don't, print promotion for
both stays blocked until the image is recovered.

Exit test: filled HTML for each sample equals the buwiz-forms fill output for
the same inputs (golden files), and each sheet passes the buwiz-forms-html
structural print-parity check (it replaced raster pixel diffing; see
`tools/formgen/README.md` there).

### W5. Final Copy and IAF encryption

What the official package actually does: the HTA's
`Aes.Ctr.encrypt(val, aesPW, 256)` call is dead code. The HTA saves plaintext
to `IAF_RDO_Copy/`, and `Encrypt.exe` produces the encrypted IAF. W5 ports
`Encrypt.exe`'s behaviour, not the HTA CTR path.

- Compression: C zlib at level 9, vendored and built in `build.zig`, matching
  buwiz-forms' `libz-sys`. The ciphertext is pinned byte for byte, so no other
  deflate implementation.
- Cipher: DCPcrypt's AES-256 mode, which is not standard AES-CBC. SHA-256 of
  the passphrase is the key, the IV is an encrypted zero block, full blocks
  are CBC, and the final partial block is XORed with the encrypted chaining
  value (CFB style). There is no padding: ciphertext length equals compressed
  length. `std.crypto` gives the AES block and SHA-256 but not this mode.
  Extend `src/container_codec/legacy.zig`, which already decrypts it, with the
  encrypt direction rather than writing a second implementation.
- Secrets: do not port `BIR_IAF_PASSPHRASE` from `crypto.rs`. The passphrase
  comes from private runtime configuration, through `legacy.zig`'s existing
  protocol-secret parameter. Encrypt tests run only when a private harness
  supplies it, and skip visibly otherwise.
- Known-answer vectors: the 78 buwiz-forms ciphertexts are official
  known-answer vectors. They follow formzero's private-vector model, not
  casual vendoring: binary (`-text`), SHA-checked, and committed only if the
  §2 amendment allows it; otherwise fetched at test time with only their
  SHA-256 and provenance in the committed manifest. Their pins came from unicorn emulation
  of `Encrypt.exe`, not a native run; W5 records a native Windows capture for
  at least one sample before calling the encrypt path qualified.

Exit test: with the private passphrase supplied, Zig ciphertext SHA-256
equals the pinned value for every sample, and decrypt round-trips. Those pins
were computed from LF plaintext, so until the line-ending capture lands the
result is reported as measured on LF text, and it does not qualify the
encrypt path for 1601C or 1701Q.
Without it, the tests skip and the gate stays closed.

### W6. Submission

Blocked on the architecture plan amendment above. This repository is offline
by design (`transport_enabled = false`).

Design, ported from buwiz-forms `transport.rs` and `filing_queue.rs`:

- **Never** reuse the HTA HTTP upload path described in
  `docs/submit-path-findings.md` (credentials and XML in query strings).
- Transport is a single module `src/transport/` behind an interface with three
  implementations: in-process fake (default), loopback SFTP for tests, and
  production. Production only when `BIR_SFTP_LIVE=1` **and** the user confirms
  a per-filing authorization in the UI.
- Endpoint resolution: the dispatcher returns encrypted fields that are
  unwrapped (AES-256-CBC, PBKDF2-HMAC-SHA1, 100,000 rounds, a second static
  secret supplied privately like the IAF passphrase) into SFTP host, user and
  password. Keep the UTF-8 BOM when unwrapping, as buwiz-forms
  `evidence/sftp-submission/PROTOCOL.md` documents. PUT the IAF to
  `/{formType}/{basename}`.
- Dispatcher transport policy follows the W0 HTTPS go/no-go:
  - If a dispatcher host serves valid HTTPS, use HTTPS only, with no fallback.
  - If none does, plain HTTP is the only way to submit. That is an explicit
    security exception written into the architecture plan amendment and
    shown to the user, never a silent fallback on a certificate error.
- SFTP host key: buwiz-forms does not check it. Record the server key during
  owner-authorized acceptance and pin it; a changed key fails closed.
- SSH/SFTP: link libssh2 (C, built in `build.zig`) rather than writing SSH in
  Zig. Decide in the architecture plan amendment.
- Queue: port the `filing_queue.rs` state machine (scoped authorization,
  lease, restart recovery, submitted vs confirmed) onto this repo's SQLite.
  Preflight re-runs full validation and re-derives the plaintext from the
  saved draft; a stale or edited draft cannot be sent.
- Logs and receipts never contain credentials, secrets or plaintext payloads.

Exit test: loopback SFTP integration test in CI; fake transport is the default
in every test. Live acceptance is a separate, owner-authorized run with the
dummy TIN buwiz-forms used for its live proof (`00000000000000`) only,
recorded in `docs/evidence/`.

### W7. Receipt confirmation

Blocked on the same amendment (§2 lists receipt handling as out of scope).

Port `receipt.rs` (IMAP fetch and sanitizing parse). Match on TIN, form and
period, not filename (BIR strips `#email#`). A filing is **confirmed** only
when a matching receipt exists; until then it is **submitted**.

Exit test: sanitized parser fixtures pass; the queue moves to confirmed only
on a matching fixture.

### W8. Product gates

No new capability vocabulary. Gates use this repo's existing readiness flags,
computed from what passed here, not copied from buwiz-forms:

| buwiz-forms `FormCapabilities` | formzero gate |
| --- | --- |
| `typed_model`, `formula_evidence` | package parts `occurrences`, `calculations`, `validation` ready |
| `xml_round_trip` | `editable_codec` and `final_copy_codec` ready; `editable_serializer_exact` and `final_plaintext_serializer_exact` only after ANSI capture (risk 4) |
| `persistence` | `transaction` ready |
| `editor` | `interaction` and `control_contract` ready |
| `render_contract`, `html_spec`, `visual_parity`, `native_print`, `pdf_export` | `document` ready plus the per-form print gate (for 1601C, `print_preparation_ready`) |
| `queue_submission` | `workflow` ready plus `encryption_path_ready`, then the W6 transport gate |

A form is offered for submission only when all earlier gates pass.

## Coverage matrix

Tick a cell only when its exit test passes in this repo.

| Form | W3 validation | W2 plaintext | W4 print | W5 IAF | W6 queue | W7 receipt |
| --- | --- | --- | --- | --- | --- | --- |
| 1701Q | | | | | | |
| 1601C | | | | | | |
| 1601EQ | | | | | | |
| _remaining 40 forms, in W3 order_ | | | | | | |

The tracking issue keeps one checkbox per workstream and per form group.

## Risks and open decisions

1. **Package drift.** BIR shows v7.9.6.2.1 but re-published the ZIP on
   2026-10-09, and the rule corpus records 7.9.6.0. Until W0 compares HTA
   hashes, parity claims hold only for the package buwiz-forms actually
   researched (the three overlapping formzero forms already match).
2. **Validation is hand-written Rust, not data.** For 42 forms the executable
   rules live in code; the corpus is evidence and fixtures. Porting is the bulk
   of the effort, roughly one form per day once W2 is in place.
3. **Thin positive evidence.** 7 forms have positive fixtures; the rest rely
   on sample payloads.
4. **ANSI code page.** `docs/ansi-code-page-capture.md` keeps
   `editable_serializer_exact` and `final_plaintext_serializer_exact` false
   until Windows `CreateTextFile` output is captured. All 78 buwiz-forms
   samples are ASCII and were produced in jsdom, which does not model
   `CreateTextFile`, so they cannot qualify those flags.
5. **Line endings.** formzero pins CRLF for 1601C and 1701Q; every
   buwiz-forms sample and ciphertext pin is LF. One Windows capture decides
   which is real (W3, "Line endings").
6. **Dispatcher HTTPS** (W0, W6). If BIR serves only HTTP, submission needs an
   explicit security exception.
7. **Architecture changes need the owner:** the §2/§12 amendment for W6 and W7,
   and the WebView for print (W4).
8. **Ciphertext provenance.** The pins come from emulating `Encrypt.exe`
   (W5).
9. **Live filing** is proven for one form in buwiz-forms. Do not claim more
   for this app until its own acceptance runs say so.
10. Disagreements between the two repos on 1701Q, 1601C and 1601EQ are resolved
   against the official package, with the evidence recorded in both repos.

## Verification commands

- This repo: `just check`, `just test`, `just verify`.
- buwiz-forms oracle: `just test` (includes `sample_payloads_test.rs`),
  `npm run rules:check`.
- Sync drift: `node scripts/buwiz-sync.mjs --check`.

Safety for every run: dummy TIN only, fake or loopback transport unless the
owner authorizes a live run, no real taxpayer data, secrets or endpoints in
fixtures, logs or git.
