# Native SDK guide and eBIRForms improvement plan

Date: 2026-07-29

Audit baseline: `69d0277` (`Initial Native SDK eBIRForms baseline`)

Toolkit audited: Native SDK CLI `0.6.1`, commit `a7509a7`, automation protocol `0x096c8aa4730c11ec`

This document is the review artifact for the next phase of the app. It explains
how the relevant Native SDK facilities apply to this repository and proposes a
dependency-ordered improvement plan. It does not authorize or implement the CI,
test, security, extension, or release changes described below.

## Executive recommendation

Keep the app zero-config and native-rendered for now. The next useful milestone
is not an extension, WebView, or production signing pipeline. It is a small
quality foundation:

1. Pin the Native CLI, Zig, and Node versions.
2. Add real full-loop markup tests beside the eight existing model tests.
3. Add a fast headless CI job.
4. Add one automation smoke flow that proves desktop and compact responsive
   layouts through the real runtime.
5. Put log privacy and retention rules in place before real taxpayer data is
   introduced.

Only after those gates pass should the project add a signed release workflow or
consider Native SDK extensions for persistence, printing, filing transport, or
background processing.

## Current state

The app is a zero-config Native SDK project:

- [`app.zon`](../app.zon) is the product manifest.
- [`src/main.zig`](../src/main.zig) owns `Model`, `Msg`, `update`, appearance,
  responsive state, asset loading, and runtime options.
- [`src/app.native`](../src/app.native) is generated from the modular markup by
  [`scripts/flatten-native.mjs`](../scripts/flatten-native.mjs).
- [`src/components/`](../src/components) and [`src/pages/`](../src/pages) are the
  editable markup sources.
- Build files under `.native/build/`, caches, `zig-out/`, dependencies, local
  secrets, signing credentials, and private reference captures are ignored.

It is a native-rendered GPU-canvas app. It does not currently use a WebView,
JavaScript bridge, extension registry, filesystem access, network access,
credential storage, or native dialogs. `js_window_api` is explicitly disabled.

The product is still intentionally presentation-only. Filing, payment,
authentication, importing, persistence, validation, printing, and network
actions remain unimplemented. The disabled controls are therefore a safety
property, not missing test setup.

### Verified baseline

| Check | Audit result |
| --- | --- |
| Generated markup | `npm run generate` reported `src/app.native` up to date |
| Static validation | `native check --strict` passed all 27 markup files and `app.zon` |
| Existing tests | `native test` passed 8 of 8 tests |
| Headless test mode | `native test --yes -Dplatform=null` passed 8 of 8 tests |
| Product build | `native build` produced the ReleaseFast binary |
| Environment preflight | `native doctor --manifest app.zon --strict` passed on the audit Mac |
| Live runtime | Automation reported `ready=true`, `gpu_nonblank=true`, and zero dispatch errors |
| Responsive runtime | Live resize checks found the full desktop shell at 1225 px and mobile launcher at 620 px |
| Automation image | A 3.6 MB deterministic `main-canvas` screenshot was produced in the ignored automation cache |
| macOS package | A roughly 5.7 MB native-only `.app` was created |
| Local signing | Ad-hoc packaging passed `codesign --verify --deep --strict` |

### Important gaps

- There is no CI workflow.
- The CLI/toolkit version is not locked by repository metadata.
- There is no dependency lockfile.
- The eight tests exercise model transitions only. They do not build the real
  markup tree or dispatch through actual widgets.
- There is no `src/tests.zig`, `TestHarness` suite, or committed automation
  smoke script.
- Packaging is macOS-only and public Developer ID signing/notarization has not
  been configured.
- The default persistent log was approximately 20.5 MB at audit time. Metadata
  only was inspected: its mode was `0644` and its directory mode was `0755`.
  That is not an acceptable long-term default for real tax data.
- Review PNGs are intentional evidence but total roughly 131 MB. No individual
  file exceeds 10 MB, but continued growth will make normal Git clones costly.

## How the requested Native SDK features fit this app

### Automation

Official reference: [Automation](https://native-sdk.dev/automation)

Native automation is file-based runtime automation, not browser DOM
automation. It can:

- wait for `ready=true`;
- inspect windows, GPU surfaces, widget roles, accessible names, bounds, and
  state;
- poll semantic assertions without arbitrary sleeps;
- resize the live app;
- drive retained-canvas widgets through their real input paths;
- capture deterministic CPU-reference-rendered PNGs for a `gpu_surface`;
- report dispatch errors and dropped trace records.

That is an excellent match for this app because its entire UI is a
`gpu_surface`. The main limitation—no WebView pixel or DOM capture—does not
matter today.

Automation is compile-time gated:

```sh
rtk native build --yes -Dautomation=true
rtk proxy ./zig-out/bin/ebirforms-zero
```

Run the automation commands from the project directory used to launch the app:

```sh
rtk native automate wait
rtk native automate snapshot
rtk native automate assert \
  'ready=true' \
  'gpu_nonblank=true' \
  'dispatch_errors=0' \
  'dropped_trace_records=0'
rtk native automate assert --absent \
  'error event=' \
  'dispatch_errors=[1-9]'
rtk native automate resize 1225 768
rtk native automate screenshot main-canvas
```

Use `native automate assert`, which polls and prints useful failure evidence,
instead of `sleep` plus `grep`.

Two project-specific rules are important:

1. Resize to a known width before asserting a responsive surface. A live window
   may already have been resized or interacted with.
2. Once real taxpayer data exists, never publish live snapshots or screenshots
   from a developer profile. CI must boot from an explicitly synthetic fixture.

The live website and the installed 0.6.1 skill disagree on an internal protocol
detail: the website describes queued `command-<n>.txt` entries while the local
skill describes a single `command.txt` slot. App code and tests should never
write these files directly. Use `native automate` and require the CLI/app
protocol versions to match.

### Testing

Official references:

- [Testing](https://native-sdk.dev/testing)
- [Testing in CI](https://native-sdk.dev/testing/ci)

Native SDK testing has three useful layers:

1. **Pure model tests** drive `update` directly. The app already has eight.
2. **Full-loop markup tests** build the real `.native` tree, locate a widget,
   derive its typed message through the tree, dispatch it, rebuild, and assert
   both state and UI.
3. **Live automation smoke tests** launch the real runtime and verify window,
   rendering, semantics, responsive layout, and error-free dispatch.

`TestHarness` adds headless runtime integration through `NullPlatform` for
lifecycle, command, window, and runtime error behavior. It should be added only
when the app has runtime services that the simpler full-loop tests cannot
cover.

For heap safety, `TestHarness` and `UiApp` test instances must use
`create`/`destroy`; they are too large for ordinary test-thread stacks.

### CI

The default zero-config scaffold intentionally has no CI. `native init --full`
contains useful recipes, but this app should not eject merely to copy them.
The zero-config CLI can run the same checks.

Recommended CI tiers:

| Tier | Runner | Purpose |
| --- | --- | --- |
| Fast PR gate | Ubuntu | Generation drift, manifest/markup checks, null-platform tests, normal build |
| Runtime smoke | Ubuntu + GTK4 + Xvfb | Real Linux window, GPU surface, semantics, responsive resize, non-empty screenshot |
| Platform smoke | macOS | AppKit/Metal behavior and ad-hoc package verification |
| Release | macOS, protected tags only | Developer ID signing, notarization, stapling, distributable image |

The fast job should run both test and build. Zig's lazy analysis means either
one alone can miss code referenced only by the other.

### Packaging

Official reference: [Packaging](https://native-sdk.dev/packaging)

This app does not need `native eject` to package:

```sh
rtk native build --yes
rtk native package --target macos --signing adhoc
```

The package is native-only: binary, metadata, icons, and `assets/`. It carries
no browser runtime. Everything under `assets/` ships, so tests, samples, and
optional large data must stay elsewhere.

The current package is a development artifact, not a public release:

- `app.zon` still uses `dev.goldcoders.ebirforms.static`;
- the description explicitly calls it a static recreation;
- the manifest targets macOS only;
- ad-hoc signing proves bundle integrity but not publisher identity;
- no notarization or stapling gate exists.

The documented platform status also matters:

- macOS packaging/signing is the mature path;
- Linux output is an install tree, not a `.deb`, RPM, Flatpak, or AppImage;
- Windows output is still early, directory-based support rather than a complete
  signed installer;
- iOS and Android packaging are experimental.

Do not label Linux, Windows, or mobile as supported because a packaging command
exists. Each needs a clean-machine install, launch, update, and uninstall
acceptance suite.

### Code signing

Official reference: [Code Signing](https://native-sdk.dev/packaging/signing)

The modes are:

```sh
rtk native package --target macos --signing none
rtk native package --target macos --signing adhoc
rtk native package \
  --target macos \
  --signing identity \
  --identity "Developer ID Application: Your Name"
```

Ad-hoc signing is suitable for local and CI integrity checks. Public
distribution requires a Developer ID signature followed by notarization and
stapling. Signing credentials belong in CI secrets and an ephemeral keychain,
never in the repository. The `.gitignore` protects common private-key,
certificate-container, and provisioning-profile formats.

The release order must be:

1. build the final binary and all final resources;
2. assemble the final app bundle;
3. identity-sign the final bundle;
4. verify the signature;
5. archive and submit to `notarytool`;
6. staple the accepted ticket;
7. verify the stapled artifact;
8. create the final distribution image;
9. never mutate the signed app afterward.

`native doctor` confirms that tools such as `codesign`, `notarytool`, and
`hdiutil` exist. It does not prove that a valid identity, credentials,
entitlements, or notarization result is available.

### Native SDK packages

Official reference: [Package Distribution](https://native-sdk.dev/packages)

This page describes distribution of the Native SDK itself; it is not an app
extension marketplace.

`@native-sdk/cli` installs the `native` command, selects one exact
platform-specific binary package, and carries the SDK source against which the
app builds. The wrapper, binary, and SDK source share one version/commit.

For this repository, CI and onboarding must not follow npm `latest` silently:

```sh
rtk npm install -g @native-sdk/cli@0.6.1
rtk native version
rtk zig version
rtk node --version
```

The audited toolchain is:

- Native SDK CLI `0.6.1`;
- Zig `0.16.0`;
- Node `24.11.1` locally, with the app requiring Node `22.15` or newer.

Use `NATIVE_SDK_PATH` only for an intentional test against a toolkit checkout,
never as an accidental machine-specific CI dependency.

### Debugging

Official reference: [Debugging](https://native-sdk.dev/debugging)

Useful trace modes are `off`, `events`, `runtime`, and `all`:

```sh
rtk native dev -Dtrace=runtime
rtk native dev -Dtrace=all
```

Use a temporary directory when collecting an intentional diagnostic bundle:

```sh
NATIVE_SDK_LOG_DIR=/tmp/ebirforms-native-logs \
NATIVE_SDK_LOG_FORMAT=jsonl \
  rtk native dev -Dtrace=runtime
```

The app already declares Native SDK panic capture. Crash reports can still
contain sensitive panic messages, so application errors must never interpolate
TINs, credentials, form bodies, imported file contents, or submission payloads.

The current persistent log behavior needs hardening before real data:

- define prohibited fields and redact them before trace emission;
- default release tracing to `off` or a deliberately minimal sanitized mode;
- use owner-only directory/file permissions;
- implement bounded rotation and retention;
- upload diagnostic artifacts only on failure and only to restricted storage;
- make support bundles an explicit user action with a visible content summary.

The WebView debug overlay does not apply to the current retained-canvas UI.

### `native doctor`

Official reference: [`native doctor`](https://native-sdk.dev/debugging/doctor)

Use the strict form for a real gate:

```sh
rtk native doctor --manifest app.zon --strict
```

Without `--strict`, warnings are informational and the command exits
successfully. Doctor checks the host, manifest, WebView/platform prerequisites,
log-path writability, optional CEF layout, and signing-tool availability. It is
a preflight, not a functional, privacy, or security audit.

Run it:

- during onboarding;
- in the platform smoke job after OS packages are installed;
- immediately before packaging;
- with explicit Chromium/CEF flags only if the app actually adopts Chromium.

### Extensions

Official reference: [Extensions](https://native-sdk.dev/extensions)

Native SDK extensions are trusted, in-process Zig modules registered through a
`ModuleRegistry`. They are not downloaded plugins and they are not sandboxed.
Modules can have start, stop, and command hooks plus declared capabilities.
Start order follows registration; stop order is reversed.

This app has no extension registry, and its zero-config runner does not expose
extension wiring through the current app options. Adopting modules would likely
require owning the runner/build setup with `native eject`.

That is not justified yet. Consider an extension only when a concrete native
service cannot be cleanly expressed through the existing typed app/effects
layer, such as:

- encrypted persistence;
- a PDF/print engine;
- filing transport;
- credential-backed authentication;
- a durable background-submission queue.

Before ejecting, require a design that defines module identity, dependency and
registration order, state ownership, failure/rollback behavior, shutdown,
input bounds, permissions, logging rules, and tests. Capability declarations
are metadata and introspection; they do not sandbox native code.

### Security

Official reference: [Security](https://native-sdk.dev/security)

Today the strongest fact is architectural: there is no WebView or bridge. The
app grants the stock native-app `view` and `command` permissions, declares
native views/GPU surfaces, denies external links, and leaves the JS window API
off.

Immediate security work should be conservative:

- test whether every current permission and origin is actually required;
- do not add `filesystem`, `network`, `credentials`, `clipboard`, or `dialog`
  authority until a reviewed feature needs it;
- keep real data out of logs, screenshots, fixtures, and panic strings;
- preserve the private `reference/` boundary;
- keep filing and payment controls disabled until their domain gates exist.

If HTML print preview later becomes a WebView:

- serve packaged local content from `zero://app`;
- keep the child WebView bridge disabled unless a specific command requires it;
- use exact command origins and a strict CSP;
- deny external navigation by default;
- never render remote or taxpayer-controlled HTML with native bridge access;
- add negative tests for `permission_denied`, unknown commands, oversize
  payloads, forbidden origins, and default-denied dialogs/credentials.

Large forms, XML, PDFs, and database records should not be squeezed through the
bridge. Bridge messages are bounded; use validated, bounded native
file/resource flows when those features exist.

## How to use Native SDK skills in this repository

Official reference: [Agent Skills](https://native-sdk.dev/skills)

Install the discovery skill once for the coding agent:

```sh
rtk npx skills add vercel-labs/native
```

The discovery skill is intentionally small. It tells the agent to load the
version-matched guidance from the installed CLI:

```sh
rtk native skills list
rtk native skills get core --full
rtk native skills get native-ui
rtk native skills get automation
rtk native skills get zig
```

Use this routing for eBIRForms:

| Work | Skill to load |
| --- | --- |
| Architecture, `app.zon`, security, packaging, runtime behavior | `core --full` |
| `.native` markup, `Model`/`Msg`/`update`, layout, full-loop UI tests | `native-ui` |
| Running app, snapshot/assert/resize/screenshot, CI smoke | `automation` |
| Zig 0.16 standard-library migration errors | `zig` |
| TypeScript app core | `ts-core` only if this repo later has `src/core.ts` |

Recommended agent loop:

1. Run `native version`.
2. Inspect `app.zon`, `src/main.zig`, and the editable markup source.
3. Load `core --full`.
4. Load only the specialized skill needed by the task.
5. Make the smallest layer-correct change.
6. Run generation, strict checks, tests, and build.
7. For visible/runtime changes, build with automation and assert the live app.
8. Report exact commands and evidence.

Do not vendor all skills into the repository by default. Reading them from the
pinned CLI keeps guidance and toolkit behavior aligned. If a particular agent
cannot load CLI skills, explicit delivery to that agent's skill directory is
possible, but the copied file then needs a refresh policy.

## Proposed test design

### Keep the existing model tests

The eight tests in `src/main.zig` already protect:

- theme/system appearance transitions;
- responsive sidebar state;
- hiding/restoring navigation without losing the route;
- taxpayer selection and local tabs;
- transient preview return paths;
- profile setup return paths;
- viewport breakpoint classification.

Keep them fast and direct.

### Add `src/tests.zig` full-loop tests

Use the structure produced by `native init --template zig-core`: build
`main.app_markup` through `canvas.MarkupView(Model, Msg)`, finalize the tree,
derive messages from real widget handlers, dispatch them, rebuild, and assert.

First cases:

1. **Taxpayer route:** press `Demo Corporation`; assert the model, visible
   taxpayer identity, selected semantics, and stable unrelated widget IDs.
2. **Dashboard tabs:** press `Tax Form Library`, rebuild, and assert both model
   state and selected tab semantics.
3. **Preview return:** press a form's `Print Preview`, assert the overlay, press
   its close/back control, and prove the exact form route returns.
4. **Safety controls:** locate representative filing/payment/save controls and
   prove disabled widgets do not dispatch.
5. **Theme rebuild:** press the theme control, rebuild, assert effective scheme
   and stable structural IDs.
6. **Responsive layout:** run the real layout engine at 390, 620, 900, and 1225
   widths; assert the intended mobile, rail, and expanded navigation surfaces.

Test helpers should fail with the missing role/name printed, not a null-unwrap
panic. Rebuild the tree after every dispatch because a tree is a snapshot.

### Add one live smoke script

The initial smoke should prove only durable contracts:

- app reaches `ready=true`;
- main window and `main-canvas` exist;
- GPU output is nonblank;
- there are no dispatch errors or dropped trace records;
- desktop resize exposes `Open Global Dashboard` and the full-sidebar control;
- compact resize exposes `Open navigation`;
- a non-empty screenshot is produced.

Start with semantic and non-empty-image checks. Add byte-for-byte screenshot
goldens only after pinning the runner image because OS text metrics can drift.

## Proposed CI gates

### Fast PR job

```sh
rtk npm run generate
rtk git diff --exit-code -- src/app.native
rtk native validate app.zon
rtk native check --strict
rtk native test --yes -Dplatform=null
rtk native build --yes
```

The job must print and verify the exact Node, Zig, and Native CLI versions.

### Linux Xvfb smoke

After installing GTK4 and Xvfb:

```sh
rtk native build --yes \
  -Dplatform=linux \
  -Dweb-engine=system \
  -Dautomation=true \
  -Dtrace=off

rtk proxy rm -rf -- .zig-cache/native-sdk-automation
rtk proxy xvfb-run -a ./zig-out/bin/ebirforms-zero &
app_pid=$!
trap 'kill "$app_pid" >/dev/null 2>&1 || true' EXIT

rtk native automate wait
rtk native automate resize 1225 768
rtk native automate assert \
  'ready=true' \
  'gpu_nonblank=true' \
  'role=button name="Open Global Dashboard"' \
  'dispatch_errors=0' \
  'dropped_trace_records=0'
rtk native automate assert --absent \
  'error event=' \
  'dispatch_errors=[1-9]'
rtk native automate screenshot main-canvas
rtk native automate resize 620 768
rtk native automate assert \
  'role=button name="Open navigation"' \
  'gpu_nonblank=true'
```

The workflow should launch the app in the background with a guaranteed cleanup
trap, then run the assertions described above. Upload the snapshot, screenshot,
and sanitized logs only when useful. A failed Linux build is a portability
finding to fix; it does not justify weakening the gate.

### macOS smoke and package

On the actual product platform:

```sh
rtk native doctor --manifest app.zon --strict
rtk native build --yes -Dautomation=true -Dtrace=off
# Run the responsive automation smoke.
rtk native package --target macos --signing adhoc
rtk codesign --verify --deep --strict --verbose=2 \
  zig-out/package/ebirforms-zero.app
```

This job produces a development artifact. It must not be called a public
release.

## Phased implementation plan

### Phase 0 — repository baseline

Status: completed in the audit baseline.

Deliverables:

- Git repository on `main`;
- Native/Zig/Node-aware `.gitignore`;
- generated output, dependencies, secrets, signing credentials, and private
  source-app references excluded;
- intentional source/assets/review evidence committed.

### Phase 1 — reproducibility and the fast quality gate

Changes:

- document or lock the exact Native CLI version;
- add Node engine/package-manager metadata and a lockfile where appropriate;
- add a CI workflow with generation drift, validation, strict checking, null
  tests, and a normal build;
- print tool versions in CI.

Acceptance:

- a fresh runner uses Native CLI 0.6.1 and Zig 0.16.0;
- generated markup cannot drift silently;
- all current eight tests, strict checks, and the normal build pass;
- no machine-specific `NATIVE_SDK_PATH` appears in repository CI.

Stop condition:

- do not proceed by following npm `latest` or by committing generated
  `.native/build` files.

### Phase 2 — full-loop UI coverage

Changes:

- add `src/tests.zig`;
- add focused widget/tree/layout helpers;
- cover the six cases listed in Proposed test design;
- keep pure model tests separate and fast.

Acceptance:

- tests dispatch messages through the real widget tree;
- disabled filing controls are proven inert;
- desktop/tablet/phone layout contracts are exercised headlessly;
- `native test --yes -Dplatform=null` passes from a clean checkout.

Stop condition:

- do not add screenshot tests to compensate for missing semantic/state
  assertions.

### Phase 3 — runtime automation

Changes:

- add one repository smoke script;
- add Linux Xvfb and macOS automation jobs;
- clear stale automation state before launch;
- capture failure artifacts safely.

Acceptance:

- readiness, nonblank GPU output, responsive desktop/compact surfaces, and zero
  dispatch errors are proven in CI;
- the app process is always terminated, including on test failure;
- no raw developer profile or real taxpayer data reaches CI artifacts.

Stop condition:

- do not write automation protocol files directly or hard-code a protocol
  version independently of the pinned CLI.

### Phase 4 — privacy, security, and diagnostics

Changes:

- inventory current permission/origin needs with negative tests;
- define prohibited log fields;
- choose sanitized release trace behavior;
- design log rotation, retention, and owner-only permissions;
- add a safe support-bundle policy;
- document threat gates for import, persistence, authentication, printing, and
  filing.

Acceptance:

- no taxpayer identity, TIN, form payload, credential, token, or imported path
  appears in normal logs or panic messages;
- logs are bounded and owner-only;
- no new capability is granted without a test and an owning feature;
- external links remain denied.

Stop condition:

- do not enable real-data features while diagnostic storage remains
  unbounded/world-readable.

### Phase 5 — packaging and release engineering

Changes:

- decide the production bundle ID and version/tag policy;
- add an ad-hoc package integrity job;
- add protected Developer ID/notarization jobs only after credentials and
  ownership are settled;
- test the final installed artifact on a clean supported Mac;
- choose a review-image storage policy before adding more large captures.

Acceptance:

- app version matches the release tag;
- the final bundle passes strict code-sign verification;
- notarization succeeds and is stapled;
- a quarantined clean-machine download launches normally;
- the release artifact is immutable after signing.

Stop condition:

- do not call an ad-hoc package, a doctor pass, or a successful local launch a
  production release.

### Phase 6 — extensions and real product capabilities

Changes:

- write a separate design for the first real domain capability;
- prefer the typed app/effects layer;
- adopt `ModuleRegistry` and `native eject` only if a concrete native service
  requires runtime module wiring;
- add domain, failure, security, and recovery tests before enabling UI actions.

Acceptance:

- the extension or service has one clear owner and bounded inputs;
- startup, partial failure, cancellation, retry, shutdown, and recovery are
  tested;
- filing/payment operations are idempotent and auditable;
- secret and taxpayer-data boundaries are explicit.

Stop condition:

- do not add an extension simply to demonstrate the extension API.

## Recommended first implementation slice

After this plan is approved, implement only Phases 1 and the smallest part of
Phase 2:

1. pin the toolchain;
2. add the fast CI job;
3. add `src/tests.zig` with taxpayer selection, one dashboard tab transition,
   one disabled filing-control assertion, and one responsive layout test;
4. run generation, strict checking, null tests, normal build, and doctor;
5. stop for review before adding live CI automation or release credentials.

This creates meaningful protection without changing product behavior, runtime
permissions, build ownership, or distribution authority.
