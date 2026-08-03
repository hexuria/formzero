# Contributor guide and release gates

Current baseline: Native SDK CLI 0.6.1, Zig 0.16.0, Node.js 22.15+, macOS.

This is the operational guide for contributors. The
[README](../README.md) is the product overview.

## Non-negotiable boundaries

- `src/app.native` is generated. Edit fragments and run
  `rtk npm run generate`.
- Filing, payment, authentication, profile saving, import, and production print
  are not implemented. Keep those actions disabled until their domain and
  safety gates exist.
- Calendar export is an `.ics` import handoff, not managed two-way sync.
- The current catalog fallback is not a taxpayer-specific filing plan.
- Never commit taxpayer data, credentials, signing material, private captures,
  logs, or submission payloads.
- Rebuild and relaunch before trusting live UI evidence.

## Change map

| Change | Primary files |
| --- | --- |
| App state, navigation, effects | `src/main.zig` |
| Shared UI or selection behavior | `src/components/` |
| Page or form layout | `src/pages/` |
| Final markup composition | `src/app-root.fragment` |
| Deadline rules | `src/calendar/domain.zig` |
| Calendar persistence | `src/calendar/store.zig` |
| Calendar export | `src/calendar/ics.zig` |
| Calendar/UI adapter | `src/calendar/ui_state.zig` |
| Permissions, assets, platform | `app.zon` |

Reusable features must keep state and behavior separate from page wiring. A
selection that affects deadlines or calendar markers must drive every output
from the same state, not duplicate UI-only state.

## Environment provisioning

`scripts/setup-dev-env.sh` is the single provisioning path. It installs the Zig
version declared by `build.zig.zon`, verifies the download against its
published SHA-256 before extracting it, refuses to run against a mismatched
Node, and installs locked npm dependencies with `npm ci`. Re-running it
downloads nothing.

`.github/workflows/ci.yml` and `.devcontainer/devcontainer.json` both call it,
so a green pipeline and a working container cannot drift apart. The script does
not touch a contributor's shell profile unless `--update-shell-profile` is
passed, which only the container does.

## Continuous integration

Every push to `main` and every pull request runs the gate below on
`macos-latest`, the supported build host. A second job provisions a cold
`macos-latest` and `ubuntu-latest` runner from the setup script and asserts
that a repeat run is idempotent, so the container path stays proven even though
the product's own build targets remain macOS and Windows.

## Required validation

Run after every code or markup change:

```sh
rtk npm run generate
rtk git diff --check
rtk npx native test --yes -Dplatform=null
rtk npx native check . --strict
rtk npx native build . --yes
```

What each gate proves:

| Gate | Proves |
| --- | --- |
| Generate | Runtime entrypoint matches editable fragments |
| Diff check | No whitespace or conflict-marker damage |
| Headless tests | Model, calendar, storage, export, and component behavior |
| Strict check | Markup and manifest match the model contract |
| Build | ReleaseFast application compiles |

Test and build are both required. Zig's lazy analysis can allow either command
alone to miss code used only by the other.

## Live UI verification

Build with automation enabled:

```sh
rtk npx native build . --yes -Dautomation=true
rtk proxy ./zig-out/bin/ebirforms-zero
```

From another terminal in the same project directory:

```sh
rtk npx native automate wait
rtk npx native automate resize 1225 768
rtk npx native automate assert \
  'ready=true' \
  'gpu_nonblank=true' \
  'dispatch_errors=0' \
  'dropped_trace_records=0'
rtk npx native automate screenshot main-canvas
```

Resize to a known width before checking responsive behavior. Prefer semantic
assertions and non-empty rendering over fixed delays or fragile pixel
comparisons. Use only synthetic fixtures for screenshots.

## Security and privacy

The app currently has no WebView or JavaScript bridge. `app.zon` grants only
`view` and `command`, denies external navigation, and targets a native GPU
surface. Preserve that minimum-authority posture.

Before real taxpayer data is allowed:

- default release tracing to off or sanitized metadata only;
- prohibit TINs, credentials, form bodies, imports, and payloads in logs and
  panic messages;
- use owner-only log permissions with bounded rotation and retention;
- make diagnostic export explicit and show the user what it contains;
- keep screenshots and test fixtures synthetic;
- review every new filesystem, network, credential, clipboard, or dialog
  permission.

If print preview later uses a WebView, keep the bridge disabled by default,
serve only packaged local content, use exact origins and a strict CSP, reject
external navigation, and add negative permission tests.

## Packaging and release truth

Development package:

```sh
rtk npx native doctor --manifest app.zon --strict
rtk npx native package --target macos --signing adhoc
rtk codesign --verify --deep --strict \
  zig-out/package/ebirforms-zero.app
```

Ad-hoc signing proves local bundle integrity only. A public macOS release
requires all of the following:

1. production bundle identifier, name, version, and description;
2. clean-machine build and test;
3. Developer ID signature using CI-managed secrets;
4. signature verification;
5. Apple notarization and stapling;
6. launch, install, update, and uninstall acceptance checks;
7. a final artifact that is not modified after signing.

Do not call a build “deployed” or “production-ready” until these gates pass.
Linux, Windows, and mobile are not supported targets for this app today.

## Priority roadmap

### P0 — filing-safe calendar scope

- **Done.** Persist the taxpayer's per-year Forms Set.
- **Done.** Export zero events for an explicitly empty Forms Set. The taxpayer
  calendar filters each deadline against its own taxable year, and the ICS
  serializer independently enforces the profile's registered form scope.
- Resolve fiscal-year, eFPS group, region, taxpayer scope, and effective dates.
  Region, RDO, and taxpayer-type scopes resolve today; fiscal years and eFPS
  groups do not.
- Add official-source provenance and regression cases for every rule change.

Exit gate: exported deadlines are demonstrably profile-specific and
source-backed.

### P1 — continuous quality

- **Done.** Add CI for generation drift, tests, strict checks, and the normal
  build. See `.github/workflows/ci.yml`.
- Add a committed automation smoke flow for desktop and compact widths.
- Add real widget/full-loop tests for routing, disabled safety actions, theme,
  selection, and responsive layout.
- Keep screenshots as failure evidence; avoid large committed image growth.

Exit gate: a clean runner reproduces the complete quality gate and live smoke.

### P2 — production capabilities

- Define durable form/profile data ownership and migrations.
- Implement validation before persistence, printing, filing, or payment.
- Add secure credentials, idempotent submission, retry/status boundaries, and
  auditable user confirmation.
- Add production PDF/print parity and official filing transport tests.

Exit gate: each capability has domain tests, negative security tests, recovery
behavior, and an explicit user-visible state model.

## Current verified baseline

On 2026-08-03, on macOS arm64 and on the `macos-latest` CI runner:

- the test graph reported 909 passed and 3 skipped across 13 build steps;
- all 27 markup files and `app.zon` passed strict checking;
- `npm run generate` reported no drift and the catalog check verified 51 codes;
- the ReleaseFast binary built at `zig-out/bin/ebirforms-zero`.

The 912 figure sums three overlapping roots — the application artifact plus the
attached store and 1701Q persistence roots — so it is a graph total, not a
count of unique tests. The three skips are screenshot generators that run only
when their environment variable is set.

This baseline is now reproduced by CI on every push and pull request rather
than asserted by hand.

These are development gates, not filing certification or production release
approval.
