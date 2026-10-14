# 1701Q grounded-core progress ledger

This ledger is intentionally value-free. It must never contain taxpayer
values, raw/decrypted payloads, secrets, endpoints, or value-bearing artifact
filenames.

## 2026-07-30 - Windows and evidence baseline

### Repository

- Primary worktree: `W:\Projects\ebirforms.0`, branch `main`, HEAD `6df69fc`.
- Windows build worktree:
  `C:\Users\uriah\Desktop\ebirforms.0-windows-arm64`, branch
  `codex/windows-1701q-core`, base `6df69fc`.
- Tracked primary files were clean before implementation.
- Existing untracked roadmap/reference files were preserved.
- macOS ARM64 derived directories were preserved under dated names before the
  clean Windows npm install.

### Toolchain

Verified installations:

- Node.js `24.18.0`, Windows ARM64; npm `11.16.0`.
- MinGit `2.55.0.windows.3`, Windows ARM64.
- Zig `0.16.0`, official Windows ARM64 archive, SHA-256
  `aee38316ee4111717900f45dd3130145c39289e105541d737eb8c5ed653c78ef`.
- Zig `0.16.0`, official Windows x86_64 archive, SHA-256
  `68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e`.
- `@native-sdk/cli@0.6.1` and
  `@native-sdk/cli-win32-arm64@0.6.1` from a clean Windows `npm ci`.
- Native SDK 0.6.1 x64 CLI fallback, SHA-256
  `f92508ddf22141084139481aa0490ef56b37fbde0f55b0ffcbd646c079571684`.

Observed upstream defects:

- Native SDK 0.6.1 ARM64 `native.exe`, SHA-256
  `37dfb942a6ab0c0e710c5cb0456190bb7d63c863fec4f9eb4c4513fb3bcfbf28`,
  crashes on every command with Windows exception `0xc0000005` at fixed
  offset `0xed1c8`.
- Official Zig 0.16.0 ARM64 runs `version` and `env` but crashes on
  `zig build` with `0xc0000005` at fixed offset `0x910f34`.
- The verified x64 Native CLI and x64 Zig compiler run under Windows ARM64
  emulation. Zig is invoked with `-Dtarget=aarch64-windows`, so the product
  binary remains ARM64.

The reproducible environment is in `scripts/windows-dev-env.ps1`.
The script itself passes under
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File`.

### Platform port

Applied in the primary worktree:

- `app.zon` now declares macOS and Windows.
- The manifest and runtime scene use the Native SDK software GPU surface.
- The web layer is explicitly excluded.
- The stale macOS-only CEF directory declaration was removed.

Passed in the local Windows worktree before the current exact-1701Q
integration:

- deterministic catalog/markup generation;
- tax-catalog TypeScript and drift checks;
- Native SDK strict markup check;
- Native SDK non-strict doctor;
- manifest validation, native/no-web-layer detection, software GPU,
  WebView2 runtime, Zig availability, and application icon checks.

The first mapped-share build was abandoned because SMB source/cache access
reduced compiler progress to an unusable rate; the local Windows worktree is
the authoritative build environment. Two app-owned portability defects were
resolved: Windows has no POSIX `localtime_r`, and Zig's translated MinGW
`localtime_s` declaration lost the `_localtime64_s` symbol alias. The runtime
now selects the exported `_localtime64_s` CRT symbol on Windows.

An earlier pre-integration executable established that the x64 compiler can
cross-target a PE32+ ARM64 GUI application without the WebView2 loader. That
artifact predates the current exact-1701Q source and is not promotion
evidence. Its executable identity, launch result, and database result must not
be reused as the final integrated verification record.

### Current-source Windows verification matrix

The current reviewed source completed:

- Zig formatting;
- deterministic generation with no drift;
- the catalog check at 51 form codes, 10 editors, 41 calendar-only forms,
  299 Native inputs, 72 profile targets, and 9 optional profile targets;
- the pure core root at 226 of 226 tests on x64 and 226 of 226 tests on
  ARM64 Windows;
- the shared calendar/profile/evolution/exact-draft store root at 178 of 178
  tests on each target;
- the exact 1701Q persistence/reopen root at 233 of 233 tests on each target;
- the Native CLI test graph at all 13 build steps and 802 of 802 reported
  tests: 391 of 391 for the application artifact plus the attached 178-of-178
  store and 233-of-233 persistence roots;
- the Native model contract at all 5 build steps;
- the strict Native check at 27 of 27 checks with zero warnings; and
- Native doctor with a successful exit and only expected informational
  output.

The component roots overlap and must not be summed. The aggregate Native test
count likewise is not additive with those component roots.

Static application-source scans found zero network/API references. The only
diagnostic print is in a test-only markup assertion and its string is absent
from the ReleaseFast executable. The clean locked dependency install
contained seven packages and reported zero vulnerabilities.

The target-matched SQLite objects used by the two linked roots were:

- x64 COFF `0x8664`, 13,167,356 bytes, SHA-256
  `75494d53e0b8d2c3b46a8a86d2552019a9a0c9f64dd4f21e01efa4e6924a6450`;
- ARM64 COFF `0xAA64`, 15,028,780 bytes, SHA-256
  `287b4498e47ac3c5fac01f61f570a6d003c47ca12255fa17cc05523f4cbd76a9`;
- shared `sqlite3.h` SHA-256
  `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d`.

The pinned x64 Zig executable used under ARM64 emulation had SHA-256
`086ce9d47ba42f33a514e1a6e04eb1d4a8fa1d75e0868e0213caad447c91e864`.

The current reviewed-source inventory contains 113 files, matches all 113
copied entries in the local ARM64 build worktree, and has SHA-256
`7594b1d49b191dc6726ae9598b8ec1f37b532b272c59450acbead9c367250041`.
Two independent `ReleaseFast` ARM64 installs used distinct empty local and
global Zig caches and distinct output prefixes. Both completed successfully,
emitted no PDB, and produced byte-identical 8,268,800-byte
`ebirforms-zero.exe` files with SHA-256
`d88b430704a903a73f035c6d7ff43df879695733c538ee4b5a36e136655c85d1`.
Native SDK 0.6.1 predicts a PDB when it registers the install artifact before
stripping is enabled; `build.zig` clears that stale install prediction, while
the compiler and both independent installs emit no PDB.

The direct Native package step and strengthened post-package verifier passed.
The installed and packaged executable bytes are identical; the executable is
ARM64 PE32+ GUI with exactly one 28-byte `IMAGE_DEBUG_TYPE_REPRO` entry, no
CodeView record, visible
`development_only_plaintext_not_production` classification, and
Authenticode status `NotSigned`. The 13-file unsigned verification artifact
contains no PDB or WebView2 loader. Its manifest has SHA-256
`a8109f033b13d71153d7526c88c01eb955ef7576a251c0978b41c2fbb9962e76`;
its sorted value-free inventory has SHA-256
`1ca80166842f020bc80b2d70deab703d0c7934d517a6a6f9f2d9275a0c045cd1`.
It is not an installer or signed release and has not been launched.

The following ARM64 inventory/build/package snapshot predates the
capability-gated development constructors, stripped CodeView record, visible
storage classification, and strengthened verifier. It remains historical
evidence only. That prior reviewed-source inventory contained 111 files,
matched all 111 then-current-worktree entries, and had SHA-256
`3e020ddc2d14e8f36912d7f8584c1827a52338faa53eed57405d13500db13307`.

The prior ARM64 ReleaseFast build passed all 4 build steps. The installed
`ebirforms-zero.exe` is 8,678,400 bytes with SHA-256
`f88ff9e983825f9d368b7581168f61a2763081bbb52af81839c6e93a4801224c`.
It is an ARM64 PE32+ Windows GUI executable.

On a clean dependency graph, `zig build package` fails because the published
`@native-sdk/cli@0.6.1` npm tarball omits `tools/native-sdk/main.zig`, which
the SDK build graph attempts to compile. The audited fallback called the
pinned Native CLI directly against the already-built ARM64 executable with
Windows target, `ReleaseFast`, excluded web layer, system web-engine setting,
no signing, and the reviewed assets.

The then-current post-package verifier passed. Installed and packaged executable bytes are
identical; the executable is ARM64 PE32+ GUI, Authenticode reports
`NotSigned`, and no ASCII or UTF-16 `WebView2Loader.dll` reference or packaged
loader DLL exists. The manifest reports version `0.1.0`, application ID
`dev.goldcoders.ebirforms`, no web layer, no signing, eight assets, and both
`native_views` and `gpu_surfaces`. The package manifest has SHA-256
`a8109f033b13d71153d7526c88c01eb955ef7576a251c0978b41c2fbb9962e76`.

The package directory contains 13 files and no PDB. Its sorted value-free
inventory is `zig-out/package/windows-package-inventory.txt` and has SHA-256
`3166b49e4017c849f3c9975452f824fd292efb8a9c173b21e9bbbbc52ff22ec6`.
It is an **unsigned verification artifact**, not an installer, signed release,
MSI, MSIX, `setup.exe`, or deployment package.

The prior `a6ab4b672bca...` package directory was preserved intact as a dated
sibling before that prior package was created; the older `415a4921f8fd...`,
`55e8e5b4a569...`, and `9b59b526acfe...` packages also remain preserved. A
clean-cache same-source build to an isolated prefix passed all 4 build steps
and produced the same 8,678,400-byte length, but its SHA-256 was
`0ecd8ef66dafdf7507875facda038c1c1f6a4dad6ab3d400fe8af5963898b4eb`,
not the packaged `f88ff9e9...` digest. Byte-for-byte reproducibility is
therefore not claimed. A byte comparison localized all 20 differing bytes to
the four-byte COFF timestamp and the 16-byte `.buildid` payload; `.text`,
`.rdata`, `.data`, resources, exception data, TLS, and relocations were
identical. The ARM64 null-backend suite
was then rerun from the exact reviewed source and passed all 9 build steps and
388 of 388 tests. That prior package has not been launched or exercised
through Windows UI automation.

### Isolated packaged-GUI evidence

The earlier pre-guard packaged ARM64 application launched and restarted
successfully with a task-specific application-data directory and synthetic
inputs. The global shell, taxpayer dashboard, profile editor, immutable profile
history, and form library rendered through the software GPU surface.

The synthetic database started at schema v2 and migrated successfully. Two
later profile revisions were appended rather than mutating history, leaving
four immutable revisions and current sequence four. It contained one 2026
form set, one explicit `1701Q` / `2018-01-ENCS` entry, and zero
business-activity rows; no business activity is required for 1701Q.
`PRAGMA integrity_check` returned `ok`, and the foreign-key check returned
zero violations. Restart restored the profile/history/form-set view and kept
1701Q visibly enabled.

Seven earlier completed process-bound no-egress observations contained 480,
159, 330, 600, 300, 260, and 41 samples. A later clean stable-scroll run added
60 process-bound samples spanning its intermediate and terminal states. Every
sample in all eight observations reported no TCP connection and no UDP
endpoint for the application process. Endpoint values were not recorded.

An intermediate-source focused smoke collected 10 process-bound samples
before cancellation; each reported no TCP connection and no UDP endpoint.
This is partial launch/no-egress evidence and is not counted as a completed
GUI matrix.

The initial packaged observations made both 1701Q launch controls appear not
to activate. Native automation later proved that both controls dispatched and
that the post-dispatch markup rebuild failed at `src/app.native:5232`.
`exact1701QNoticeTone` exposed semantic values
`neutral`/`success`/`failure`, but Native `WidgetVariant` accepts
`secondary`/`primary`/`destructive`. The state mapping was corrected and
`expectAppMarkupBuilds` now renders the ready 1701Q model in the test graph so
the same runtime-only option failure cannot pass as a state-only success.

The repaired pre-guard snapshot passed the full 9-of-9 graph at 371 of 371
tests and produced the package later used by the authoritative stable-scroll
matrix, executable SHA-256
`fb3fa20507ae62ece033b9831aca92efc2aacb569856b3ea16bdbf82c5a83088`.
This historical package is distinct from the current-source package above.

Pre-guard isolated automation passed both form-launch routes:

- `widget-action ... press` produced the exact 1701Q page;
- `widget-click ...` produced the exact 1701Q page with
  `dispatch_errors=0`; and
- a copied unsigned package produced the same exact page with
  `dispatch_errors=0`.

Each fresh snapshot contained the exact January 2018 editor, Original and
Amended actions, the `Research / candidate` label, and
`Network transport: disabled`. An independent visible-window observation
also confirmed the exact page.

The authoritative stable-scroll observation is
`stable-scroll-matrix-20260731-02`. It used a copied unsigned ARM64 package
whose executable was 8,669,184 bytes with SHA-256
`fb3fa20507ae62ece033b9831aca92efc2aacb569856b3ea16bdbf82c5a83088`,
an isolated application-data directory, and synthetic data only. Every
application action reported `dispatch_errors=0`. The driver re-read the
automation snapshot before each action, resolved the unnamed page-scroll
ancestor while excluding `Sidebar navigation`, and used synchronous
`increment`/`decrement` actions. It did not reuse offscreen widget IDs or use
momentum wheel input. The earlier run containing a misspelled view label was
excluded before any form assertion.

The clean run opened the Original 173-control workspace, changed the
qualified `txtLOB` probe to a synthetic lowercase value, and observed that all
workflow actions and an attempted Amended context change were blocked while
the editor was dirty. Explicit commit applied the qualified blur chain and
normalized the value to uppercase. Calculation, the separate Save gate, and
the masked Editable candidate then passed. Navigation through the form
library preserved the Original context, `1/0` candidate history, and masked
candidate metadata. No generated plaintext was revealed.

Material Original work blocked Amended replacement without loss. Explicit
discard unmounted the workspace, controls, and candidate; a newly opened
Amended workspace had `0/0` history, and a pristine switch back to Original
also started at `0/0`. This proves visible context/history isolation and reset;
opaque workspace-identity inequality remains headless evidence.

The first Full-validation attempt failed on the synthetic profile's missing
birth date and retained focus on the Full validation button while leaving the
Editable candidate present and masked. A new immutable synthetic profile
revision supplying the birth date was added only inside the isolated run.
After selecting the required taxpayer-type, ATC, tax-rate, and deduction
radios, Full validation reached the terminal success message. Final Copy then
produced a masked, candidate-only artifact with history `Editable: 1 -
Final Copy: 1`. Imported ciphertext and decrypted plaintext remained
unavailable. Reveal, exact-workspace and generated-candidate durable
persistence, outbound encryption, queue, upload, and submission were never
invoked. The isolated synthetic profile revision was intentionally persisted
through the existing plaintext profile store.

The matrix also exposed a source-only shell-context defect: a different
sidebar taxpayer could be selected behind material exact work. The completed
matrix remains bound only to the historical `fb3fa...` package.

The first selection correction was bound to the intermediate `9b59...`
package. Its focused smoke, `current-source-guard-20260731-01`, was canceled
before any cross-taxpayer interaction or assertion after 10 process-bound
zero-egress samples. It is not a guard assertion.

Current source now captures immutable exact-workspace filer profile and
revision provenance, reconciles stale sidebar flags without refreshing the
exact projection, guards taxpayer selection and new-profile creation, and
defensively blocks cross-profile/new-profile saves while preserving editor
data. A same-stable-filer revision may advance only with an explicit notice;
the exact workspace, revision binding, and candidate remain byte-stable.
Host/ARM64 regressions cover every rendered selection/create/save route and
build markup at each rejection/preservation state.

Those final changes are bound to the 113-file inventory with SHA-256
`7594b1d49b191dc6726ae9598b8ec1f37b532b272c59450acbead9c367250041`
and current
`d88b430704a903a73f035c6d7ff43df879695733c538ee4b5a36e136655c85d1`
package above. That package has not been launched. Packaged-GUI qualification
of the final guard remains incomplete and Windows UI control must not resume
without explicit user authorization.

The research workspace now defines a closed offline stable-scroll evidence
contract for a future authorized run. Its current profile contains the 18
historical checkpoints plus five GUI-reachable guard checkpoints; the
defensive stale-new-profile-save state is headless-only. Complete local
verification requires all 23 ordered checkpoints, fresh pre/post snapshot
bytes, all 51 ordered application commands covering 27 source-bound routes,
zero dispatch errors, both deterministic scroll directions, checkpoint-bound
intermediate and terminal no-egress samples, and all 16 local byte bindings.
Its strongest verdict is deliberately labeled
`valid-complete-local-bytes-bound-unreviewed`; it cannot establish reviewer
authority or substitute for the GUI run. Native journal and replay-report
bytes remain self-attested opaque inputs: the current Native CLI version,
digest, size, and x86-64 PE identity are authority-pinned, but journal and
replay semantics are not parsed and Native record/replay execution is always
reported unauthenticated. No manifest was fabricated for the historical
folders because their action, snapshot, and no-egress streams were not
persisted. Historical manifest-shape and package-relabel validation remains
available, while execution-artifact qualification deliberately supports only
`current-guard-v1`.

The new stable-scroll capture-kit producer performs only stable, no-follow
reads and binds the current 113-file source inventory, `src/app.native`, the
reviewed x64 Native CLI, the unsigned ARM64 package, and the closed
checkpoint/command/route profile. It always reports
`preflight_status: blocked` and
`launch_preconditions_satisfied: false`: readable caller-supplied build
reports, drivers, fixtures, and no-egress samplers are not thereby trusted.
The downstream verifier now binds the canonical capture-kit digest and byte
count, exact no-egress sampler identity, and a five-event canonical chained
run-state journal from `prepared` through `verified`, with capture, replay,
verification, and attestation timing relationships enforced. These remain
local consistency proofs: the sampler is unreviewed and point-sampled, the
journal is self-attested, exact command operands and a fixed scroll schedule
are unresolved, and continuous no-egress capture is not established.
Preparing or verifying the kit launches no process and writes no evidence
artifact.

Restart still does not establish exact durable-workspace support: the Native
workspace is intentionally in-memory, while the reviewed headless adapter's
persistence/reopen behavior is covered by its 233-of-233 matrix.

### Exact 1701Q evidence

Frozen exact identity:

- Offline eBIRForms package `7.9.6.0`;
- launcher SHA-256
  `de8ef0815509d65189e6794e1f8135a5ecf5f2800005d1fc5c87043efd96dbca`;
- source `BIR-Form1701Qv2018.hta`, resource type `23`, ID `170`;
- HTA SHA-256
  `5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0`;
- ten-file runtime-set digest
  `9d129c83cdf32ebea58291d36bc2b3e09a5fc40061ab072a6de6b0d51ecff917`;
- all nine active JS/VBS dependencies exist and match embedded resources.
- official 1701Q PDF SHA-256
  `fdcce0ff83660bb831e8d95a5054a0fc7b924f049097b2ece6667318baaa49f5`
  (1,109,208 bytes);
- official 1701Q guide SHA-256
  `ff07962229015a50b0aa169f91fa32e10c534f6730de5bf59263e22d34e270bc`
  (152,170 bytes).

Value-free occurrence findings:

- 193 static form controls;
- two select-one controls are unconditionally injected into `frmMain` by
  `init()` -> `getRdo()` before load/save/final actions;
- 173 runtime serializer-eligible controls;
- 172 editable-save occurrences because the two address controls collapse;
- 173 Final Copy plaintext occurrences with separate address controls;
- editable and Final Copy are distinct codecs, not two names for one XML.
- the two ordered occurrence manifests are executable metadata; all 173 live
  controls now have exactly one reviewed ownership class, independently of
  serializer-readiness evidence.

Workflow findings:

- a lexical source scan finds 28 alert tokens around full Validate, but only
  25 are active ordered failure sites; one is the terminal success alert and
  two are inside a block comment. Commented alerts are not executable rules;
- Save runs a separate four-rule prerequisite, not full validation;
- Final Copy has a legacy programmatic bypass defect that the new typed
  lifecycle must reject rather than reproduce;
- the primary Final Copy plaintext is built separately from editable save;
- the unsigned legacy `Encrypt.exe` remains evidence-only.

### Container qualification

- The audited value-free evidence anchors are
  `payload-inventory.v3.json` SHA-256
  `711e14dd4e923f4574f4b1fae59c2f5f926b3c4513d0ce121c70f9ba65ba533e`,
  `source-ledger.v1.json` SHA-256
  `009a1360414536ea5c03621a5c2d8fe2a977ab38a4cee3111eb2180e99199954`,
  and `filename-candidate-gap-report.v1.json` SHA-256
  `fa10f4a8961d0c20fc2d4152607a554c3fb110293484a35bb01d8e209cf823f4`.
- Value-free historical evidence records 67 successful external decryptions
  and 67 byte-identical external re-encryptions.
- The versioned inventory records 16 plaintext and 67 encrypted sample
  records, with 56 unique ciphertext hashes. This host has 5 of 16 plaintext
  records and 47 physical matching ciphertext files. Those 47 hashes address
  58 of the 67 encrypted inventory records because 11 records duplicate a
  present hash. The physical-instance gap is 20; the hash-addressable record
  gap is nine, corresponding to nine missing unique hashes.
- The capture-gap report contains 12 historical candidate groups, zero
  reviewed same-session pairs, zero artifact-contract capabilities, and zero
  1701Q groups. Historical 1701Q sample hash matches are not authoritative
  pairs because no capture ledger proves association, byte equality, or
  ordering.
- All four required architecture-scoped Windows qualification reports are
  absent. The two legacy default report locations are absent as well.
- The read-only `audit-evidence-readiness.mjs` gate reports these distinctions
  without paths, filenames, taxpayer values, or secret values. Against the
  six current authorized local evidence roots it exits 1 with `blocked` and
  0 of 7 gates passed; all six roots were available and stable. The observed
  corpus has 47 physical matches with no
  hard-linked or repeated filesystem identities. They are 47 observational
  physical instances and address 58 inventory records by content hash; they do
  not prove original-source multiplicity. Independently authenticated
  custody commitments remain 0 of 67 because no attestation or attestation
  authority is present. The provenance state is
  `unavailable-no-attestation-authority`,
  `source_instance_provenance_qualified` is false, and
  `private_vector_files` remains false.
- The closed future provenance contract rejects copied bytes and caller-
  created unique labels as authority. Qualification would require 67 distinct
  custodian-signed acquisition commitments, one purpose-exclusive custody key,
  a separate purpose-exclusive review key and principal, and exact source-
  policy/trust pins. The source policy remains `unavailable-unselected`.
- The value-free acquisition handoff can consume either an existing
  classification or scan repeatable authorized roots directly in memory. It
  binds the exact reviewed inventory and ledger, all 67 encrypted-record
  ordinals and identities, and all 56 ciphertext groups while preserving
  duplicate-group ambiguity. It independently recomputes the embedded
  availability identity, reviewed record/group projection, input metadata,
  and transitive signed-byte implementation hashes. It reports the
  47-present/20-missing physical shape and the 58-addressable/nine-hash-gap
  shape without emitting local paths. The final current-contract handoff is
  71,649 canonical UTF-8 bytes with SHA-256
  `56571d121e15c1b34a1673a0045a5d88523fbcb90f23bfd9a75f42381b4a42f5`.
  Custody request and merge paths reobserve the exact handoff, inventory, and
  ledger; review-request preparation requires the public trust store and
  cryptographically verifies all 67 custody signatures before asking the
  separate reviewer to sign. Captured collection primordials and post-install
  signature verification keep the merge fail-closed. Artifact stdout remains
  path-free and no private key is accepted or loaded.
- Readiness-output validation derives private-vector observational
  completeness, source-policy binding, provenance qualification, the vector
  gate, summary, status, and production verdict from their detailed counts and
  evidence fields. Caller-coordinated summary booleans cannot promote a
  contradictory 0-of-67 or hash-incomplete observation.
- Production readiness authority is fixed in reviewed source to form `1701Q`
  and two distinct same-session pairs. The source policy is currently
  `unavailable-unselected`. Its closed dual-architecture qualification-run
  verifier is implemented, production-clock-bound, and wired to the readiness
  CLI, while the checked v1 capture-gap report remains a schema-valid negative
  report. Caller-supplied paths, keys, reports, and matching digests are
  observations only; they cannot create their own trust root or select another
  form/count.
- The source policy now reserves exact pins for the inventory, source ledger,
  source corpus, capture-gap report, both reviewer trust stores, provider and
  spouse bindings, and independent x86_64 and ARM64 codec/compressor evidence.
  Release qualification requires separate decrypt and exact-encrypt reports,
  probe binaries, toolchains, approvals, and zlib 1.2.12 components for both
  architectures. Reports, probes, and components require distinct digests and
  physical identities across architectures and roles. A shared Zig
  cross-compiler is allowed only as a consistent toolchain identity and cannot
  double as evidence.
- Both Windows known-answer schemas are closed over all 67 sorted value-free
  actual-output records. Decrypt evidence must match every expected plaintext
  identity; exact-encrypt evidence must match every expected ciphertext byte
  identity. Minimal counters, legacy/macOS identities, malformed PE stubs,
  cloned pair evidence, hard-link multiplicity, contradictory ledger
  bindings, future attestations, and duplicate trust keys are rejected.
- Protocol-provider and spouse-oracle signatures can be validated as
  lower-level evidence, but they do not become production qualification
  without the source policy and locally observed pinned identities. Mere
  presence of legacy `FORMZERO_EBIRFORMS_PROTOCOL_SECRET` state vetoes the
  protocol gate without reading its value or length. The spouse helper is
  hashed only and is never executed.
- The final provenance adversarial review passes 46 of 46. The focused
  stable-scroll contract and capture-kit set passes 44 of 44, and the combined
  private-vector acquisition, signing, and readiness set passes 59 of 59.
- The final serial research suite reports 310 tests: 308 passed, zero failed,
  and two intentionally skipped. Its Zig corpus checker cross-targets
  the source-closed `aarch64-windows` profile, records PE/COFF output, verifies
  PE machine `0xAA64`, validates a closed Draft 2020-12 v2 record, and binds
  the canonical inventory entry in the exact source ledger. A checked
  83-artifact v2 record was deliberately not fabricated because 20 encrypted
  source instances are absent and the inventory-bound decrypt executable is
  Mach-O ARM64 while the parser is Windows ARM64 PE. The historical v1 record
  and source ledger remain unchanged; no caller-authored ready/exit-0 path
  remains.
- The prior exact compressor oracle was macOS native libz 1.2.12, not Zig or
  Windows. No pinned Windows zlib 1.2.12 component is available; the local
  MinGit zlib 1.3.2 cannot qualify that profile.
- The protected corpus is incomplete; Windows KAT/probe identities, production
  SecretProvider bindings, and the signed spouse-oracle report are absent on
  this host. The evidence-only spouse helper is present with reviewed SHA-256
  `c00bd4131a725af53f48c6385d3332c4b789e15441bf52bbac73117c96c1b0ac`,
  but a helper file alone is not an oracle.
- Therefore Windows 67-vector qualification is currently unavailable and
  outbound encryption remains fail-closed.
- Safe work that can continue: clean-room decrypt implementation, strict
  ordered parser integration, synthetic known answers, malformed-input tests,
  qualification plumbing, and the visibly disabled artifact-lab state.
- A clean-room decrypt-only candidate now passes five synthetic inline tests
  under x64 Zig 0.16 on Windows ARM64. It remains `0/67`, exposes no outbound
  encryption operation, and is not official-compatible until the private gate
  can run.

### Headless component test evidence

- `src/core_logic_test.zig` provides a Native-SDK-independent root at `src/`
  so relative domain imports remain valid.
- The current component-root evidence passes 226 of 226 tests on the x64 host
  target and 226 of 226 tests on the ARM64 Windows product target.
- `src/tax_profile_store_test_root.zig` passes 178 of 178 tests on each target.
- `src/form_1701q_exact_persistence_test_root.zig` passes 233 of 233 tests on
  each target.
- These roots import overlapping modules, so their totals must not be added
  and represented as a unique-test count.
- The current Native application artifact passes 391 of 391 tests, including
  the fail-closed custody boundary and shell-context regression. Its full
  Native test graph passes 13 of 13 build steps and reports 802 of 802 after
  also executing the attached 178-test store and 233-test persistence roots;
  those overlapping roots are not additional unique tests. Current source is
  bound to the
  113-file reviewed inventory, SHA-256
  `7594b1d49b191dc6726ae9598b8ec1f37b532b272c59450acbead9c367250041`,
  and the verified current package, executable SHA-256
  `d88b430704a903a73f035c6d7ff43df879695733c538ee4b5a36e136655c85d1`.
  The completed full GUI matrix remains bound separately to the earlier
  `fb3fa20507ae62ece033b9831aca92efc2aacb569856b3ea16bdbf82c5a83088`
  package.
- Windows automation on the historical
  `fb3fa20507ae62ece033b9831aca92efc2aacb569856b3ea16bdbf82c5a83088`
  package reached the exact page and completed the stable-scroll flow described
  above. Assertions that still require external evidence are not promoted by
  either GUI or headless results.
- A Zig cache rooted on `W:` cannot atomically rename compilation results;
  tests and Windows builds use local C: caches.

### 1701Q calculation and validation entry points

- Fixed-point centavo inputs preserve the legacy sequence of whole-peso
  `Math.round` nodes without binary floating point.
- All three year-dependent graduated tables, the 8% branch, Part III
  propagation, credits, penalties, spouse aggregation, negative halves, and
  overflow failure are covered by focused tests.
- Full validation exposes exactly 25 active first-error failures plus its
  separate success result; spouse checksum remains an injected external
  verdict and blocks closed when unknown.
- The four-rule editable Save gate is independent from full validation.
- The artifact transition requires successful full validation and rejects the
  legacy programmatic Save/Final Copy fallthrough.
- Source-transcription and boundary tests pass. Evidence readiness remains
  false until the governing differential/oracle reconciliation gate is also
  available; unit tests do not silently substitute for that gate.

### 1701Q plaintext codecs

- The strict lossless parser preserves source order, legitimate duplicate
  keys, the exact envelope/tails, and parse-render byte identity while
  rejecting malformed, trailing, lossy, over-limit, and wrong-shape input.
- Editable save requires all 173 live controls in DOM order and emits 172
  occurrences after the exact address collapse, selective JavaScript
  `escape()`, and current-page reset.
- Final Copy emits all 173 live controls with separate raw address values and
  the final sentinel.
- Synthetic golden SHA-256 tests pin both outputs and the two runtime-injected
  RDO positions.
- MSHTML separator normalization is proven as TAB + CRLF + twelve spaces.
  Philippine offline eBIRForms `CreateTextFile` is pinned to Windows-1252
  by the 2026-08-23 1601C ACP-1252 Save capture. Raw values encode as 1252;
  scalars outside 1252 fail closed (no Windows best-fit). Editable and Final
  Copy serializer-exact flags are true. Artifacts stay candidate until
  calculation and validation are also reconciled. See
  `docs/core-logic/MAC_HANDOVER_WINDOWS_1252.md`.

### 1701Q tax-profile projection

- One required filer and one optional, explicitly bound, distinct spouse map
  into 28 exact legacy controls in live DOM order.
- Every emitted value owns its profile/revision provenance. Page-2 TIN/name
  fan-out, TIN/date transforms, the exact 100/50-character address split, and
  the 138-value RDO option domain are covered by reconciliation tests.
- Type, ATC, tax-rate, deduction, and foreign-credit elections remain
  transaction-owned and cannot be inferred from profile subject kind, civil
  status, or relationships.
- Profile refresh returns a new immutable snapshot; marriage never
  auto-selects a spouse profile, and a successor corporation cannot replace
  the natural-person filer.
- The mapping is integrated into the shared engine and
  `profile_mapping_reviewed` is true. Non-ASCII profile values continue to
  fail closed pending legacy ANSI qualification.
- The generic catalog now reconciles the typed 1701Q spouse requirement:
  spouse citizenship and spouse foreign tax number are present and explicitly
  optional. The generated catalog expectations are 299 extracted inputs, 72
  profile targets, and 9 optional profile targets across the current catalog;
  1701Q contributes 37 Native-page inputs.
- Catalog generation and drift checks passed in the final synchronized
  matrix. Count agreement is not a calculation, validation, or
  payload-exactness promotion.

### Typed transaction and ordered draft state

- Every one of the 173 runtime controls has exactly one origin: 28 profile,
  91 transaction, 3 preparer, 7 filing-context, 2 external-evidence, 37
  derived, and 5 system.
- Profile application is atomic and cannot overwrite ATC, tax-rate,
  deduction, or other transaction elections. Calculation, validation,
  editable, Final Copy, and occurrence bridges reject missing, wrong-kind,
  mixed-origin, or stale-snapshot inputs.
- Credential-bearing legacy controls are represented only as locked-empty
  order positions and are excluded from transaction digests.
- Draft workspaces are random-identity, optimistic-revision guarded, and
  append-only. Each immutable revision binds the complete package key,
  occurrence-manifest digest, profile snapshot digest, transaction digest,
  ordered raw/normalized/emitted values, and validation status.
- Duplicate serialized keys remain distinct ordered occurrences; they are
  never persisted through a collapsing map. Stored buffers are deep-copied
  and zeroed before release.
- Current evidence truthfully labels generated plaintext as a candidate, not
  exact. Final Copy candidate generation additionally requires the full
  validation transition.
- Editable and Final histories are separate exact-shape streams. Each stream
  is bounded to 64 immutable revisions and 64 MiB of retained occurrence-value
  bytes. Capacity and byte accounting are preflighted, and failed appends roll
  back without weakening the prior stream.

### Exact Native UI and workspace isolation

- The exact page is a view/controller over the typed 173-control state; its
  row list and editor are not serialization authorities. The older coarse
  1701Q draft cannot affect exact projection, validation, or candidates.
- The interaction runtime initializes source-derived disabled states, routes
  radios through the reviewed click path, keeps filing identity locked, and
  performs text commit plus any qualified blur chain atomically. A failed
  control remains visibly failed until that control succeeds; an unrelated
  success does not erase it.
- Candidate-reachable commits enforce the frozen restrictive keypress domain
  for all 78 non-empty applicable bindings: date text is limited to digits and
  slash, whole-number text to digits, and negative money is accepted only for
  controls whose source contract permits it.
- This is a conservative commit-domain gate, not browser interaction parity.
  Exact per-keystroke behavior, date masking, selection/composition edge
  cases, and paste behavior remain unqualified.
- The application-owned fixed-capacity editor wipes its full storage and
  scratch buffers. Dirty editor state blocks direct actions and selection or
  workspace changes until the edit is committed or explicitly hidden and
  discarded.
- Exact work survives navigation away from and back to 1701Q. It is closed
  only by the visible `Discard and close exact workspace` action.
- Original and Amended are explicit workspace-opening actions, not editable
  radios. Each creates a new opaque workspace identity with locked filing
  context; material work blocks replacement until explicit discard.
- Strict Native markup keeps the intentionally retired coarse-1701Q bindings
  in an explicit `view_unbound` inventory rather than reintroducing obsolete
  methods. Removing that old coarse model surface remains a follow-up cleanup.
- Native exact state deliberately owns no SQLite store. The durable adapter is
  headless-only until production key custody and the reviewed integration seam
  are available.

### Tax-profile evolution persistence

- SQLite profile schema v3 adds immutable taxpayer identity anchors, audited
  identity corrections, effective-dated `single`/`married` history, and
  effective-dated spouse/predecessor/successor/business-conversion
  relationships.
- Ordinary revisions keep one natural-person profile across individual and
  sole-proprietor states when the canonical TIN is unchanged. A corporation
  remains a distinct profile and can be linked with
  `business_converted_to`.
- v1/v2 backfill is deterministic, idempotent, and transactional; conflicting
  historical TINs, legal-person classes, and malformed identities roll back
  and require reviewed repair.
- Store schema v4 extends that profile history with exact ordered draft
  workspaces and immutable revision streams. It supports at most 32
  workspaces per filing business key and returns at most 32 alternates.
  The canonical business key enforces filer, form/revision, period, and
  Original/Amended intent. Exact schema identity separately gates the package
  and payload shape, while Editable and Final remain permitted sibling streams
  under one workspace.
- Duplicate audited saves remain distinct revisions. Ordered duplicate
  serializer keys remain distinct occurrences rather than collapsing into a
  map.
- Every persisted revision freezes the validation receipt derived from the
  retained `SaveValidated` state. Persist and reopen callers cannot supply a
  replacement verdict; reopen replays the selected revision with its stored
  receipt and fails closed on context, history, binding, digest, or readiness
  mismatch.
- Profile projection normalizes the legacy uppercase fields into the form copy
  without mutating profile provenance or its digest. Email case remains
  preserved. Editable and Final candidate reopen paths are covered, including
  mixed-case profile sources.
- Exact occurrence values in SQLite are plaintext. The adapter is permanently
  labeled synthetic/test-only until a separately reviewed application
  key-custody and at-rest-encryption design is implemented.

### Production local-storage key custody

- [ADR-0001](../security/ADR-0001-PRODUCTION-LOCAL-STORAGE-KEY-CUSTODY.md)
  records the whole-database threat boundary and the decisions that remain
  external. The
  [provider decision packet](../security/PRODUCTION-STORAGE-PROVIDER-DECISION-PACKET.md)
  evaluates the leading backend/custody combinations and required approvals
  without selecting or connecting one.
  Protecting only exact occurrence values is insufficient because taxpayer
  profiles, form bindings, metadata, journals, WAL files, and backups are also
  value-bearing.
- `src/security/key_custody.zig` adds a compile-tested, fail-closed
  classification boundary. The current artifact is source-fixed to
  `development_only_plaintext_not_production`; its bootstrap accepts no
  runtime input and mints an opaque development capability whose identity is
  checked before file-backed path validation. The separate synthetic exact
  plaintext token remains test-only and opaque. Fabricating a pointer of
  either public opaque type fails closed. The production capability has no
  constructor, accepts no key material, and always returns
  `error.ProductionStorageUnavailable`.
- `src/security/repository_opening.zig` adds an inert, zero-field typed factory
  for the shared calendar/tax-profile production repository. Public `open`
  accepts only the repository scope and fails before any provider callback;
  callers cannot inject contracts or select a backend at runtime.
- A private value-free harness verifies a source-selected 12-stage contract:
  release qualification; recovery and repository-transition policy binding;
  custody authentication; backend initialization; location resolution;
  artifact classification; state-routed interrupted-operation recovery or
  approved provision/legacy transition; repository authentication; schema
  inspection/migration; and operational readiness. Recovery is allowed only
  for interrupted authenticated states, transition only for absent or
  `legacy_plaintext_untrusted` under an approved transition policy, and
  unsupported, mismatched, or tampered states stop at classification.
  SQL/PRAGMA authority appears only after repository authentication. The stage
  markers and contracts are private and the harness cannot compile into a
  non-test artifact or mint production authority.
- All four raw exact-draft Store operations and all four public exact adapter
  entry points validate the test capability before validation, allocation,
  query preparation, or transaction start. Forged-capability regressions
  leave workspace/revision row counts at zero and prove that a rejected reopen
  does not consume its loaded workspace.
- The current production state is
  `unavailable_authenticated_storage_backend_unselected`. This is a boundary,
  not encryption: the capability-gated stock-SQLite APIs remain
  development-only and the Native exact page remains memory-only.
- `production_storage_requirements.zig` and
  `production_storage_evidence.zig` add a provider-neutral, value-free
  qualification vocabulary and observational validator. The closed matrix has
  13 evidence gates; eight protected surfaces; 15 backend requirements; 12
  custody failures; nine recovery scenarios; nine repository artifact states;
  22 architecture/scenario cells; eight database-key separation cells; and ten
  externally owned decisions. Architecture-specific provider/backend
  identities, canonical record bindings, time-bounded distinct owner/reviewer
  approvals, and material/non-derivation/handle-reuse separation are all
  required. Even a structurally complete record remains
  `unavailable_unselected` with `production_authorized = false`; the module
  accepts no key material, performs no I/O, and is not wired into the
  repository factory or application bootstrap.
- Application startup obtains the source-minted development bootstrap before
  reading `EBIRFORMS_DATA_DIR`, resolving or creating a path, or performing
  storage I/O. Both stores removed the public two-argument `Store.open` and now
  expose only an explicitly named file-backed development constructor that
  validates the capability first. Their integration state is
  `unavailable_development_plaintext_artifact_only`; value-bearing profile,
  calendar, and generic-draft data remain plaintext despite the stronger
  artifact boundary.
  The raw exact-draft Store/adapter seam is test-capability-gated, and exact
  Native workspace persistence is unavailable by construction; no production
  encrypted-storage or operating-system custody implementation is connected
  or enforced.
- `build.zig` exposes only the `-Dproduction-release=true` gate. It fails with a
  source-pinned, value-free unavailable reason and returns before Native SDK
  constructs artifact steps. A named `production-release` step is deliberately
  unregistered so it cannot be combined with an ordinary artifact request. The
  default executable visibly embeds
  `development_only_plaintext_not_production`, and the Windows package
  verifier requires that string plus a single PE reproducible debug marker
  with no CodeView entry.
- The standard test step now includes both SQLite-linked roots when the
  resolved target matches Zig's build-host architecture. Cross-target runs
  compile both roots but deliberately do not assume OS emulation; target-native
  execution remains a separate qualification command.
- A future implementation must authenticate the database before every SQL
  statement or PRAGMA, cover the main database and all SQLite side files,
  keep the database key separate from protocol secrets, and fail closed for
  missing, corrupt, swapped, wrong-user, wrong-machine, legacy-plaintext, or
  cipher-mismatch state. Silent reset, plaintext fallback, and automatic
  promotion are forbidden.
- Windows DPAPI CurrentUser is technically feasible as a custody candidate,
  and an authenticated SQLite codec must be selected separately. Backend and
  license choice, user-presence policy, recovery/backup, rotation, legacy
  database disposition, and x64/ARM64 release qualification still require
  external approval and evidence.

### Offline artifact lab

- The session holds generated plaintext, imported ciphertext, and decrypted
  plaintext in distinct slots and masks every slot by default.
- Explicit reveal is scoped to one slot; comparison exposes only byte length,
  SHA-256, equality, and the first differing byte offset.
- Generated and decrypted plaintext must pass the strict 1701Q artifact
  validator before acceptance. Missing inputs and invalid artifacts fail
  closed.
- The API has no encrypt, submit, queue, upload, or transport transition; the
  user-supplied decrypt secret is borrowed for the operation and never retained
  by the session.
- The clean-room decrypt-only candidate remains synthetic-known-answer tested
  but has no private-corpus qualification. The Native page has no production
  SecretProvider, file import, or decryption integration.

### Spouse TIN checksum gate

- The official source delegates the spouse checksum verdict through
  `ValidateTinWChkDgt` to the legacy `chkt.exe`.
- The recovered helper is an unsigned 32-bit executable with SHA-256
  `c00bd4131a725af53f48c6385d3332c4b789e15441bf52bbac73117c96c1b0ac`.
  It is evidence-only: the application and tests do not ship or execute it.
- No provenance-approved local replacement and no controlled oracle-vector
  corpus are available. Application validation therefore supplies
  `.not_evaluated` and fails closed when the spouse checksum rule applies.
- A translated algorithm must not be promoted from static inspection alone.
  Promotion requires an approved provenance path, controlled inputs and
  outputs, and differential evidence.

### Remaining promotion blockers

- Official paired captures or controlled oracle reconciliation for the
  calculation sequence and ordered validation. Editable and Final Copy
  plaintext serializers are Windows-1252 exact; remaining codec work is
  calc/validation, not another ACP guess.
- The private 67-vector decrypt-and-encrypt corpus, protocol secret, and a
  compatible pinned compressor. The remaining observed corpus gap is 20
  observational physical instances and nine unique ciphertext hashes; source-
  authenticated custody commitments remain 0 of 67. Outbound encryption
  remains absent until all 67 custody commitments and independently approved
  x86_64 and ARM64 Windows decrypt/exact-encrypt report sets, toolchains, probe
  binaries, and zlib 1.2.12 components pass the source-selected qualification
  gate.
- Selection, licensing, implementation, and x64/ARM64 qualification of an
  authenticated whole-database backend and operating-system custody provider,
  plus approved recovery, rotation, backup, and legacy-plaintext policy. The
  accepted fail-closed boundary is not encryption at rest.
- A secure SecretProvider plus reviewed import/decryption UI. Secrets and
  taxpayer artifacts must never enter logs, screenshots, docs, filenames, or
  diagnostics.
- A provenance-approved spouse checksum implementation and controlled oracle
  vectors for the unsigned legacy helper boundary.
- Exact per-keystroke, date-mask, paste, selection, and composition parity.
- Print/PDF parity and control-level accessibility.
- Removal of the obsolete coarse-1701Q model surface after its explicit
  `view_unbound` inventory is retired safely.

### Next action

1. With explicit authorization for Windows UI control, complete the full
   current-guard stable-scroll capture/replay matrix using the current
   `d88b430704a903a73f035c6d7ff43df879695733c538ee4b5a36e136655c85d1`
   package: all 23 checkpoints, 51 application commands, 27 source-bound
   routes, fresh per-command resolution, checkpoint-bound no-egress samples,
   and all 16 local byte bindings. The earlier `9b59...` attempt was canceled
   before interaction after 10 zero-egress samples and does not qualify the
   final guard's GUI behavior.
2. Acquire authoritative paired captures, the complete protected 67-vector
   corpus, 67 distinct custodian-signed acquisition commitments with the
   purpose-exclusive custody/review authorities and source pins, and a
   SecretProvider binding. Also acquire independently approved x86_64 and
   ARM64 Windows KAT/toolchain evidence, pinned compatible Windows zlib 1.2.12
   components, and provenance-approved spouse-checksum oracle vectors.
3. Obtain the external storage-backend, custody, recovery, and legacy-data
   decisions recorded by ADR-0001; then implement and qualify authenticated
   whole-database storage. Keep all evidence flags and production
   persistence, encryption, import, queue, and submission capabilities
   fail-closed until their respective gates pass. Do not start another form.
