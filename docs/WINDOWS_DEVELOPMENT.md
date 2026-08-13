# Windows ARM64 development

The audited Windows target is Windows 11 ARM64. The application is built as a
native ARM64 GUI executable, but two host tools currently run as x64 binaries
under Windows emulation:

- Native SDK CLI 0.6.1: the ARM64 executable exits with access violation
  `0xc0000005` on this host.
- Zig 0.16.0: the official ARM64 compiler reports its version but exits with
  access violation `0xc0000005` during non-trivial builds.

This is a host-tool workaround, not a change to the product target. The x64
Zig compiler is always passed `-Dtarget=aarch64-windows`.

## Current 1701Q integration status

The safe implementation now contains the typed 173-control 1701Q engine,
source-ordered calculation and validation, strict editable and Final Copy
candidate codecs, composable effective-dated profiles, bounded schema-v4 exact
draft storage, a fail-closed reopen adapter, and the masked offline artifact
lab.

The current-source Windows verification matrix is:

- formatting passed;
- deterministic generation passed with no drift;
- the catalog check passed with 51 form codes, 10 editors, 41
  calendar-only forms, 299 Native inputs, 72 profile targets, and 9 optional
  profile targets;
- pure core passed 226 of 226 on x64 and 226 of 226 on ARM64 Windows;
- shared calendar/profile/evolution/exact-draft store passed 178 of 178 on
  each target;
- exact 1701Q persistence/reopen passed 233 of 233 on each target;
- the Native CLI test graph passed all 13 build steps and 802 of 802 reported
  tests: 391 of 391 for the application artifact plus the attached 178-of-178
  store and 233-of-233 persistence roots;
- the Native model contract passed all 5 build steps;
- the strict Native check passed all 27 checks with zero warnings, and doctor
  exited successfully with only the expected informational output; and
- static application-source scans found zero network/API references. The only
  diagnostic print is inside a test-only markup assertion and its string is
  absent from the ReleaseFast executable.

The three component roots overlap and their counts must not be summed. The
Native and component-root runs also exercise overlapping tests. The graph's
`802` is exactly `391 + 178 + 233`, not a unique-test count.

The current reviewed-source inventory contains 113 files, matches all 113
current-worktree entries, and has SHA-256
`7594b1d49b191dc6726ae9598b8ec1f37b532b272c59450acbead9c367250041`.

The generated catalog currently expects 299 Native inputs, 72 profile targets,
and 9 optional profile targets. The 1701Q spouse catalog now includes optional
citizenship and foreign tax number, matching the typed five-field spouse
requirement.

## Pinned environment

The current audit environment uses:

- Node.js 24.18.0 for Windows ARM64;
- MinGit 2.55.0.windows.3 for Windows ARM64;
- Zig 0.16.0 for Windows x86_64;
- Native SDK CLI 0.6.1 for Windows x86_64;
- `@native-sdk/cli@0.6.1` and
  `@native-sdk/cli-win32-arm64@0.6.1` from `npm ci`.

[`scripts/windows-dev-env.ps1`](../scripts/windows-dev-env.ps1) verifies the
exact executable hashes and identities before exporting any build variables.
It deliberately does not download or replace tools. A missing file or hash
mismatch is a hard failure that must be reviewed, not bypassed.

The script also places npm and both Zig cache layers under
`%LOCALAPPDATA%\Buwiz`. Do not put Zig caches on the mapped `W:` drive:
that filesystem failed atomic cache renames during the audit.

## First setup

Install the pinned tools at the paths declared near the top of
`scripts/windows-dev-env.ps1`. From a fresh local Windows worktree, install the
locked JavaScript dependencies:

```powershell
npm ci
```

Then enable local scripts only for the current shell and load the verified
environment:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
. .\scripts\windows-dev-env.ps1
```

The environment check must print the expected Node, Git, Zig, Native CLI, SDK,
and local cache identities. Use the exported CLI path rather than `npx
native`; `npx` selects the crashing ARM64 Native CLI package on this host.

## Just command surface

With the verified environment loaded, the repository's cross-platform command
surface is:

```powershell
just setup
just check
just test
just build
just package
just install
just news-sync
just news-sync-offline
just clean
just clean list --all-worktrees
just clean build --dry-run
just worktree-remove 'C:\exact\registered\worktree' --dry-run
```

On Windows, workspace maintenance is inspection-only: the bare commands,
inventory, and `--dry-run` are supported and do not prepare app identity or
mutate `.native`. Destructive cleanup and worktree removal fail closed until a
reliable Windows process inspector is available. Run destructive maintenance
from macOS or Linux after reviewing the exact target and dry-run there.

The two `news-sync` recipes run the BIR issuance pipeline. They are plain Node
and need no Zig toolchain, so they resolve through `{{ npm_command }}` on every
platform without a Windows-specific recipe; a live run additionally wants
poppler's `pdftotext` on `PATH`, and the pipeline exits 2 with the install hint
when it is missing. `scripts/just-windows.ps1` accepts them as verbs too, and
its `check` verb now runs the pipeline's typecheck and test suite alongside the
catalog checks, matching the unix recipe.

These news verbs have not been exercised on the audited ARM64 host — the
PowerShell parses and every npm script it names exists, but nothing beyond that
is verified on Windows.

`just package` builds the unsigned Windows ARM64 directory artifact. `just
install` copies the main build to `%LOCALAPPDATA%\Programs\Buwiz App` by default and creates
`Buwiz App.lnk` in the current user's Start Menu. Branch builds include their
sanitized branch suffix in both locations. Set `$env:BUWIZ_INSTALL_DIR` to
change the parent directory before running
`just install`; previous installs are moved to timestamped `.previous.*`
siblings.

## Development checks

Run formatting and generation before Native checks:

```powershell
& $env:NATIVE_SDK_ZIG fmt --check build.zig src
npm run generate
npm run check:tax-catalog
& $env:BUWIZ_NATIVE_CLI test . --yes -Dplatform=null
& $env:BUWIZ_NATIVE_CLI check . --strict
$identity = node scripts/app-identity.mjs prepare --format json | ConvertFrom-Json
& $env:BUWIZ_NATIVE_CLI doctor --manifest $identity.manifestPath
```

Run the Native-SDK-independent grounded-core root on both the host and product
architectures:

```powershell
$coreX64Cache = Join-Path $env:LOCALAPPDATA `
  "Buwiz\zig-cache\core-x64"
$coreArm64Cache = Join-Path $env:LOCALAPPDATA `
  "Buwiz\zig-cache\core-arm64"

& $env:NATIVE_SDK_ZIG test src/core_logic_test.zig `
  --cache-dir $coreX64Cache
& $env:NATIVE_SDK_ZIG test src/core_logic_test.zig `
  -target aarch64-windows `
  --cache-dir $coreArm64Cache
```

The two SQLite-linked roots are:

```text
src\tax_profile_store_test_root.zig
src\form_1701q_exact_persistence_test_root.zig
```

`build.zig` registers both under `test-storage-linked` and makes the ordinary
`test` step depend on them. When the resolved target matches Zig's build-host
OS and architecture, the step compiles and runs both roots. When cross-targeting
it compiles both but deliberately does not assume that OS emulation can execute
the foreign architecture. Run each target-native qualification separately with
a target-matched SQLite object; never link the x64 SQLite object into the ARM64
test. Preserve the command and object identity in the final value-free test
record; do not preserve a database or test values in documentation.

The production-release option is an intentional negative gate:

```powershell
& $env:NATIVE_SDK_ZIG build -Dproduction-release=true
& $env:NATIVE_SDK_ZIG build test-production-release-gate
& $env:NATIVE_SDK_ZIG build test-windows-package-pe-parser
```

The option must fail with the source-pinned, value-free storage unavailable
reason before Native SDK registers artifact steps. There is deliberately no
named `production-release` top-level step. The regression also proves that the
ambiguous `zig build production-release install` invocation is rejected as an
unknown step and that neither attempted install prefix contains artifact files.
The PE parser regression uses synthetic PE32 and PE32+ images; it requires no
ARM64 product build or package output.

Build the Windows ARM64 product explicitly from the synchronized local
worktree, then package the resulting binary with the pinned Native CLI:

```powershell
& $env:NATIVE_SDK_ZIG build `
  -Dtarget=aarch64-windows `
  -Doptimize=ReleaseFast

$identity = node scripts/app-identity.mjs prepare --format json | ConvertFrom-Json
$packageRoot = "zig-out\package\$($identity.appName)-windows"
& $env:BUWIZ_NATIVE_CLI package `
  --target windows `
  --manifest $identity.manifestPath `
  --output $packageRoot `
  --binary "zig-out\bin\$($identity.appName).exe" `
  --optimize ReleaseFast `
  --web-layer exclude `
  --web-engine system `
  --signing none `
  --assets assets

& .\scripts\verify-windows-package.ps1 `
  -AppName $identity.appName `
  -BundleId $identity.bundleId
```

On a clean `npm ci`, `zig build package` fails because the published
`@native-sdk/cli@0.6.1` npm tarball omits `tools/native-sdk/main.zig`, even
though the SDK build graph tries to compile that file. This is an upstream
packaging defect. The verified fallback above calls the same pinned Native
CLI directly against the already-built ARM64 binary; do not copy an
unreviewed missing source file into the dependency or weaken the package
checks.

The main-branch product is `zig-out\bin\buwiz.exe`; other branches use the
resolved `buwiz-<branch>-<hash>.exe` name. The direct package step produces an
unsigned verification artifact directory at `$packageRoot`. The audited
directory contains 13 files, including
the packaged executable, package manifest, icon, README, resource assets, and
asset manifest. It contains no PDB.

Native SDK 0.6.1 registers its install artifact before the application build
enables stripping, so its install model initially predicts a PDB even though
the compiler emits none. `build.zig` clears those predicted PDB install fields
after enabling stripping. Both independent clean-cache installs completed
without a PDB, and the package verifier independently rejects any PDB.

Native SDK 0.6.1 does not generate a Windows installer. This is not MSI, MSIX,
`setup.exe`, signing, or deployment. The ordinary package step does not
request an archive and does not require `zip`. If a convenience ZIP is made
later, it remains unsigned and is not an installer.

The packager does not clean its output directory. Before the final package,
resolve the exact absolute `$packageRoot` path and safely move any
older directory aside so stale files cannot enter the inventory.

The final `package-manifest.zon` must report a Windows artifact, version
`0.1.0`, the resolved `$identity.bundleId`, the resolved
`$($identity.appName).exe` executable, `ReleaseFast`, GUI subsystem, no web layer,
no signing, seven assets, and both `native_views` and `gpu_surfaces`.

`scripts\verify-windows-package.ps1` is the required post-package verifier.
It checks installed/package executable equality, ARM64 PE32+ GUI identity,
one `IMAGE_DEBUG_TYPE_REPRO` entry with no CodeView/RSDS entry, the visible
`development_only_plaintext_not_production` classification, `NotSigned`,
manifest identity and native-only settings, PDB absence, and WebView2-loader
absence. It writes the sorted value-free inventory to
`zig-out\package\$($identity.appName)-windows-package-inventory.txt`.

## Local worktree rule

Compilation directly from `W:` is much slower than a local filesystem and
previously exposed cache rename failures. Use the maintained local build
worktree:

```text
C:\Users\uriah\Desktop\ebirforms.0-windows-arm64
```

Synchronize only the reviewed source state into that worktree. Do not copy
SQLite databases, payload captures, protocol secrets, decrypted artifacts, or
other taxpayer-bearing files.

## Historical pre-Buwiz ARM64 build and package evidence

The following snapshot records the pre-rename `ebirforms-zero` identity. It is
retained as build provenance and does not describe current output names.

The current reviewed-source inventory contains 113 files, matches all 113
copied entries in the local Windows build worktree, and has SHA-256
`7594b1d49b191dc6726ae9598b8ec1f37b532b272c59450acbead9c367250041`.

Two independent `ReleaseFast` ARM64 installs used distinct empty local and
global Zig caches and distinct output prefixes. Both completed successfully,
emitted no PDB, and produced byte-identical 8,268,800-byte
`ebirforms-zero.exe` files with SHA-256
`d88b430704a903a73f035c6d7ff43df879695733c538ee4b5a36e136655c85d1`.
Two earlier bounded attempts were interrupted by their command time limits,
preserved, and excluded from reproducibility evidence; only the two
uninterrupted fresh-cache installs above are authoritative.

The direct Native package step completed, and
`scripts\verify-windows-package.ps1` passed. It verified identical installed
and packaged executable bytes, ARM64 PE32+ GUI identity, exactly one 28-byte
`IMAGE_DEBUG_TYPE_REPRO` entry, no CodeView record, `NotSigned`, the visible
`development_only_plaintext_not_production` classification, and no PDB or
WebView2 loader. The unsigned verification artifact contains 13 files. Its
manifest retains SHA-256
`a8109f033b13d71153d7526c88c01eb955ef7576a251c0978b41c2fbb9962e76`;
its sorted value-free inventory has SHA-256
`1ca80166842f020bc80b2d70deab703d0c7934d517a6a6f9f2d9275a0c045cd1`.
It is not an installer or signed release. It has not been launched or
exercised through Windows UI automation.

## Prior ARM64 build and package evidence

The following snapshot predates the capability-gated constructors, stripped
CodeView record, visible development-storage classification, and strengthened
verifier. It is retained as historical evidence only and does not qualify the
current source. The prior reviewed-source ReleaseFast build passed all 4 build
steps and produced:

- `zig-out\bin\ebirforms-zero.exe`, 8,678,400 bytes;
- SHA-256
  `f88ff9e983825f9d368b7581168f61a2763081bbb52af81839c6e93a4801224c`;
- PE machine `0xAA64`, optional-header magic `0x020B`, and subsystem `2`
  (Windows GUI).

The installed and packaged executables are byte-identical.
`Get-AuthenticodeSignature` reports `NotSigned`. Neither ASCII nor UTF-16
`WebView2Loader.dll` occurs in the executable, and no such DLL exists in the
package. The package manifest reports version `0.1.0`, application ID
`dev.goldcoders.ebirforms`, `ReleaseFast`, GUI subsystem, no web layer, no
signing, eight assets, and both `native_views` and `gpu_surfaces`.
The package manifest has SHA-256
`a8109f033b13d71153d7526c88c01eb955ef7576a251c0978b41c2fbb9962e76`.

The then-current verifier passed. It recorded the 13-file sorted, value-free
inventory at `zig-out\package\windows-package-inventory.txt`, whose SHA-256 is
`3166b49e4017c849f3c9975452f824fd292efb8a9c173b21e9bbbbc52ff22ec6`.
This directory is an **unsigned verification artifact**, not an installer,
signed release, MSI, MSIX, `setup.exe`, or deployment package. It contains no
PDB.

Before packaging, the prior `a6ab4b672bca...` directory was moved intact to a
dated sibling rather than overwritten; the older `415a4921f8fd...`,
`55e8e5b4a569...`, and `9b59b526acfe...` packages also remain preserved. A
clean-cache same-source build to an isolated prefix passed all 4 build steps
and produced the same 8,678,400-byte length, but its SHA-256 was
`0ecd8ef66dafdf7507875facda038c1c1f6a4dad6ab3d400fe8af5963898b4eb`,
not the packaged `f88ff9e9...` digest. Byte-for-byte reproducibility is
therefore not claimed. A byte comparison localized all 20 differing bytes to
the four-byte COFF timestamp and the 16-byte `.buildid` payload; `.text`,
`.rdata`, `.data`, resources, exception data, TLS, and relocations were
identical. The final ARM64
null-backend suite was then rerun from the exact reviewed source and passed all
9 build steps and 388 of 388 tests. That prior package has not been launched
or exercised through Windows UI automation.

The target-matched SQLite test objects were independently identified:

- x64 COFF `0x8664`, 13,167,356 bytes, SHA-256
  `75494d53e0b8d2c3b46a8a86d2552019a9a0c9f64dd4f21e01efa4e6924a6450`;
- ARM64 COFF `0xAA64`, 15,028,780 bytes, SHA-256
  `287b4498e47ac3c5fac01f61f570a6d003c47ca12255fa17cc05523f4cbd76a9`;
- shared `sqlite3.h` SHA-256
  `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d`.

## Isolated GUI/no-egress status

Use a task-specific isolated application-data directory and synthetic inputs
only. Do not capture displayed taxpayer values, raw/decrypted payloads,
secrets, screenshots, value-bearing filenames, or endpoints in the handoff
record.

The earlier pre-guard packaged ARM64 application launched and restarted
successfully. The global shell, taxpayer dashboard, profile editor, immutable
profile history, and form library rendered through the software GPU surface.
A synthetic schema-v2 fixture migrated successfully; two later profile
revisions were appended rather than mutating history, leaving four immutable
revisions and current sequence four. The database contained one 2026 form set,
one explicit `1701Q` / `2018-01-ENCS` entry, and zero business-activity rows.
The latter is valid for 1701Q. `PRAGMA integrity_check` returned `ok`, and the
foreign-key check returned zero violations. Restart restored the
profile/history/form-set view and kept 1701Q visibly enabled.

Seven earlier process-bound no-egress observations collected 480, 159, 330,
600, 300, 260, and 41 samples respectively. The clean stable-scroll matrix
added 60 samples spanning its intermediate and terminal states. Every sample
reported no TCP connection and no UDP endpoint for the application process.
This agrees with the static application-source scan that found zero
network/API references. Endpoint values were not recorded.

An intermediate-source focused smoke collected 10 process-bound samples before
cancellation; each reported no TCP connection and no UDP endpoint. This is
partial launch/no-egress evidence and is not counted as a completed GUI
matrix.

The initial 1701Q controls did dispatch, but their post-dispatch page rebuild
failed at `src/app.native:5232`: the exact state supplied
`neutral`/`success`/`failure` where Native `WidgetVariant` requires
`secondary`/`primary`/`destructive`. The corrected mapping and a
ready-1701Q renderer assertion passed the full 9-of-9 graph and 371 of 371
tests. A fresh ARM64 ReleaseFast automation build passed 4 of 4 steps, and the
direct package fallback plus post-package verifier passed. That repair snapshot
produced the pre-guard package used by the full stable-scroll matrix,
executable SHA-256
`fb3fa20507ae62ece033b9831aca92efc2aacb569856b3ea16bdbf82c5a83088`.

Pre-guard isolated runs passed both `widget-action ... press` and
`widget-click ...` form-launch routes. The clean click route and the copied
unsigned package each reported `dispatch_errors=0` and rendered the exact
January 2018 editor, Original/Amended controls, `Research / candidate`, and
`Network transport: disabled`. A visible-window observation independently
confirmed the exact page.

The authoritative clean observation is
`stable-scroll-matrix-20260731-02`. It used the copied unsigned package with
executable SHA-256
`fb3fa20507ae62ece033b9831aca92efc2aacb569856b3ea16bdbf82c5a83088`,
an isolated application-data directory, and synthetic inputs only. Every
application action reported `dispatch_errors=0`.

For deterministic scrolling, re-read `snapshot.txt` before every action.
Resolve the unnamed scroll ancestor whose viewport contains the target and
exclude the named `Sidebar navigation` group. Invoke its synchronous
`increment` or `decrement` action (PageDown/PageUp), wait for the new snapshot,
and resolve all target IDs again. Do not reuse IDs across rebuilds and do not
use wheel input for this matrix because Native momentum can leave the target
moving. A rejected automation command is not an application assertion.

The clean matrix verified:

- dirty-editor workflow blocking and rejected Amended replacement;
- explicit commit plus the qualified blur chain, including synthetic
  lowercase-to-uppercase normalization;
- masked Editable-candidate preservation through form-library navigation;
- material Original/Amended replacement blocking, explicit discard, and fresh
  `0/0` context histories;
- first Full-validation failure with focus retained on its action and the
  candidate still masked;
- successful Full validation after an isolated immutable synthetic profile
  revision and the four required transaction elections; and
- masked Final Copy candidate presentation with `1/1` history.

Generated plaintext was never revealed. Exact-workspace and generated-candidate
durable persistence, imported ciphertext, decryption, outbound encryption,
queue, upload, and submission remained unavailable or unused. The isolated
synthetic profile revision was intentionally persisted through the existing
plaintext profile store.

The run also exposed a shell-context source defect: a different sidebar
taxpayer could be selected behind material exact work. The completed matrix is
therefore evidence only for the historical `fb3fa...` package, not for later
guard changes.

The first correction was bound to the intermediate
`9b59b526acfe602c19be2ee898c45bb5407d33e14f76cff5aa433620c88c34b5`
package. Its focused smoke, `current-source-guard-20260731-01`, was canceled
before interaction after 10 zero-TCP/UDP samples. It is partial launch
evidence only.

Current source additionally captures the exact workspace's immutable filer
profile and revision provenance, guards taxpayer selection and new-profile
creation, rejects defensive cross-profile/new-profile saves without consuming
editor data, and preserves an existing exact candidate across an explicitly
reported newer revision of the same stable filer. Host and ARM64 headless
regressions cover all rendered selection/create/save paths and build markup at
the rejection and preservation states. These changes are bound to the current
`d88b430704a903a73f035c6d7ff43df879695733c538ee4b5a36e136655c85d1`
package, which has not been launched. Packaged-GUI qualification of the final
guard therefore remains incomplete and requires explicit authorization before
resuming Windows UI control.

The research workspace now contains a closed offline stable-scroll evidence
schema and verifier for the next authorized observation. The current profile
requires the 18 historical checkpoints plus five GUI-reachable guard checks;
the defensive stale-new-profile-save state remains headless-only. A complete
offline verdict requires 23 ordered checkpoint records, fresh pre/post
snapshot bytes for every checkpoint, all 51 ordered application commands
covering 27 source-bound routes, zero dispatch errors, both deterministic
scroll directions, checkpoint-bound intermediate and terminal no-egress
samples, and all 16 local package/source/driver/fixture/snapshot/no-egress,
resolution, receipt, and Native-artifact bindings. Its strongest result is
explicitly
`valid-complete-local-bytes-bound-unreviewed`: it binds the supplied local
bytes and checks their internal consistency; it does not authenticate reviewer
authority, GUI execution, Native record/replay semantics, or the source of the
no-egress capture. The current Native CLI version, digest, size, and x86-64 PE
identity are authority-pinned, but Native journal and replay-report semantics
remain self-attested and opaque, and Native record/replay execution is always
reported unauthenticated. The historical folders have no persisted action,
snapshot, or no-egress manifest and were not retrospectively promoted;
execution-artifact qualification is explicitly limited to
`current-guard-v1`.

The capture-kit producer performs stable, no-follow reads and binds the
current 113-file inventory, `src/app.native`, the reviewed x64 Native CLI, the
unsigned ARM64 package, and the closed 23-checkpoint/51-command/27-route
profile. It deliberately remains blocked even when caller-supplied build
reports, drivers, fixtures, and no-egress samplers are readable. A later
execution attestation now independently binds the canonical kit digest and
byte count, exact sampler identity, and a canonical five-event chained
run-state journal from `prepared` through `verified`, including capture,
replay, verification, and attestation timing relationships. This does not
upgrade the unreviewed point sampler, self-attested journal, opaque Native
semantics, unresolved exact command operands/fixed scroll schedule, or absent
continuous no-egress capture. The producer and verifier launch no process and
write no evidence artifact.

The Native exact workspace remains intentionally in memory only; application
restart must not be described as exact durable-workspace support. The
headless 233-of-233 persistence/reopen matrix independently verifies that the
reviewed adapter preserves an immutable selected revision and its validation
receipt.

## 1701Q safety boundary

Windows setup does not promote unfinished filing capabilities:

- network transport, queueing, upload, and submission remain absent;
- outbound encryption remains unavailable until all 67 private Windows
  decrypt and encrypt known-answer vectors pass and all 67 source instances
  have independently authenticated custody provenance under the source-
  selected qualification policy;
- the current local SQLite exact-draft store contains plaintext and is limited
  to synthetic/test data. The accepted
  [ADR-0001](security/ADR-0001-PRODUCTION-LOCAL-STORAGE-KEY-CUSTODY.md)
  boundary leaves production in
  `unavailable_authenticated_storage_backend_unselected`; it does not provide
  encryption at rest. Every raw exact-draft Store operation and exact adapter
  entry point now validates the privately minted test capability before any
  query or mutation, and forged opaque pointers fail closed;
- the public production repository factory is source-selected, zero-field,
  accepts no runtime provider contracts, and fails before any callback. Its
  private value-free harness covers the complete 12-stage future contract:
  release qualification, recovery and repository-transition policy binding,
  custody authentication, backend initialization, location resolution,
  artifact classification, state-routed recovery or approved transition,
  repository authentication, schema inspection/migration, and operational
  readiness. Recovery is reachable only for interrupted authenticated states;
  transition is reachable only for `absent` or
  `legacy_plaintext_untrusted` under an approved transition policy; and
  terminal unsafe classifications stop before SQL/PRAGMA authority;
- application startup acquires a source-minted artifact bootstrap before
  reading `BUWIZ_DATA_DIR` (or the main-build-only `EBIRFORMS_DATA_DIR`
  compatibility override), resolving or creating paths, or performing
  storage I/O. The shared calendar and tax-profile file constructors require
  and identity-check that opaque development capability before path
  validation. The old public two-argument `Store.open` surface is absent and
  the integration state is `unavailable_development_plaintext_artifact_only`.
  This is enforceable development-artifact separation, not encryption:
  value-bearing records remain plaintext and only exact Native workspace
  persistence is unavailable by construction;
- generated editable and Final Copy plaintext remain visibly labeled
  candidates until their official paired-capture evidence gates pass.
- the Native exact page owns only in-memory workspace history; durable GUI
  persistence remains disabled until key custody and the reviewed adapter seam
  are connected;
- candidate commits enforce the frozen restrictive input domain, but exact
  per-keystroke, date-mask, paste, selection, and composition parity remains
  unqualified;
- spouse checksum validation remains `.not_evaluated` because the official
  source delegates it to an unsigned 32-bit `chkt.exe` with SHA-256
  `c00bd4131a725af53f48c6385d3332c4b789e15441bf52bbac73117c96c1b0ac`;
  that helper is evidence-only and is never shipped or executed;
- the clean-room decrypt-only candidate has no private 67-vector Windows
  qualification, and there is no production SecretProvider or import/decrypt
  UI;
- the local evidence set contains 5 of 16 plaintext records and 47 physical
  ciphertext matches. Those hashes address 58 of 67 encrypted inventory
  records (47 of 56 unique ciphertext hashes); there are no reviewed
  same-session pairs, no 1701Q capture group, and neither Windows known-answer
  report exists. Filesystem multiplicity is observational only:
  no provenance attestation or attestation authority is present, independently
  authenticated custody commitments remain 0 of 67, the provenance state is
  `unavailable-no-attestation-authority`,
  `source_instance_provenance_qualified` is false, and
  `private_vector_files` remains false;
- the closed future provenance contract cannot promote copied bytes or
  caller-created unique labels. Qualification would require 67 distinct
  custodian-signed acquisition commitments, one purpose-exclusive custody key,
  a separate purpose-exclusive review key and principal, and exact
  source-policy/trust pins. The source policy remains
  `unavailable-unselected`, so none of that authority currently exists;
- the value-free acquisition handoff binds the reviewed inventory and ledger,
  every one of the 67 encrypted-record identities, and all 56 ciphertext
  groups without emitting local paths. It preserves the current
  47-present/20-missing physical and 58-addressable/nine-hash-gap shape,
  independently recomputes the exact reviewed projection/input metadata and
  transitive signing implementation, and was regenerated as 71,649 canonical
  UTF-8 bytes with SHA-256
  `56571d121e15c1b34a1673a0045a5d88523fbcb90f23bfd9a75f42381b4a42f5`.
  Custody request and merge reobserve the handoff, inventory, and ledger.
  Review-request preparation requires a public trust store and verifies all 67
  custody signatures before emitting the separate reviewer request; no
  private key is accepted or loaded. Readiness-output validation recomputes
  observation, policy, provenance, gate, summary, status, and production
  verdict coherence from detailed fields rather than trusting caller-set
  booleans. The signing path nevertheless remains externally unavailable
  until exact preflight succeeds under distinct purpose-exclusive
  custody/review keys and principals;
- the production readiness target is fixed in reviewed source to `1701Q` and
  two distinct same-session pairs. The source policy is
  `unavailable-unselected`. The closed dual-architecture qualification-run
  verifier is implemented and uses the production clock, observed file bytes,
  source-pinned Ed25519 authority, and disjoint report/probe/component
  identities, but no source policy or external run is selected. Caller-supplied
  keys, paths, reports, and matching digests remain observational only. The
  current six-root authorized audit found every root available and stable,
  then exited 1 with `blocked` and 0 of 7 gates passed;
- Windows codec and compressor qualification requires independent x86_64 and
  ARM64 reports, probe binaries, toolchains, approvals, and zlib 1.2.12
  components. Closed report schemas bind all 67 actual vector outcomes;
  hard-link inflation, cloned evidence, cross-architecture identity reuse,
  future attestations, and self-rooted trust fail closed;
- the final provenance adversarial review passes 46 of 46; the focused
  stable-scroll contract and capture-kit set passes 44 of 44, and the combined
  private-vector acquisition, signing, and readiness set passes 59 of 59;
- the final serial research suite reports 310 tests: 308 passed, zero failed,
  and two intentionally skipped. Its Zig corpus checker cross-targets
  the source-closed `aarch64-windows` profile, verifies PE machine `0xAA64`,
  validates a closed Draft 2020-12 v2 record, and directly binds the canonical
  inventory entry in the exact source ledger. A checked 83-artifact v2 record
  was deliberately not fabricated: 20 encrypted source instances are absent,
  and the inventory-bound decrypt executable is Mach-O ARM64 while the parser
  is Windows ARM64 PE. The historical v1 record and source ledger remain
  unchanged. No legacy helper binary was executed;
- no pinned Windows zlib 1.2.12 component, approved authenticated SQLite
  backend, operating-system key provider, recovery policy, or legacy-plaintext
  transition is available. The
  [provider decision packet](security/PRODUCTION-STORAGE-PROVIDER-DECISION-PACKET.md)
  narrows the technical candidates and required approvals without selecting
  or connecting one;
- the provider-neutral storage evidence model closes 13 structural gates over
  eight protected surfaces, 15 backend requirements, 12 custody failures,
  nine recovery scenarios, nine repository states, 22 native
  architecture/scenario cells, eight database-key separation cells, and ten
  external decisions. A complete record is still observational-only,
  source-unselected, and never production-authorizing; no provider, key
  material, backend, repository factory, or bootstrap path is connected;
- print/PDF parity, control-level accessibility, and removal of the obsolete
  coarse-1701Q model surface remain promotion work.

The value-free implementation and test ledger is
[`docs/core-logic/PROGRESS.md`](core-logic/PROGRESS.md).
