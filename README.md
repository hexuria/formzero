# Buwiz App

[![CI](https://github.com/hexuria/formzero/actions/workflows/ci.yml/badge.svg)](https://github.com/hexuria/formzero/actions/workflows/ci.yml)

Cross-platform Buwiz tax application, built with Native SDK 0.6.1 and
Zig 0.16.0. The app includes responsive desktop UI, ten BIR form layouts, a
global form/deadline dashboard, and a functional tax-calendar engine.

## Product status

| Area | Status |
| --- | --- |
| Navigation, themes, responsive layouts | Functional; the theme and sidebar width are remembered across launches |
| Global Dashboard calendar | Functional; complete resolved schedule, never profile-filtered, with an optional RDO context view that is remembered across launches |
| Important News | Functional; BIR issuances compiled four times a day by the `scripts/news-sync/` pipeline from BIR's own publication API, shown for the calendar month in view, cached in SQLite with the last good copy retained when a refresh fails |
| Tax deadline calculation | Functional; 20 compiled rule groups |
| Calendar policy | Persisted in SQLite with sourced holidays and overrides |
| Synced deadline overrides | Advisory; deadline-extension circulars are extracted deterministically into RDO-scoped overrides that carry their source reference and can be dismissed in the app. Extraction is fail-closed, so a missed extension is far likelier than a wrong date |
| Calendar export | Functional `.ics` handoff to the default calendar app, scoped to the profile's Forms Set |
| Tax profiles and Forms Set | Persisted, revisioned, effective-dated, and the sole source of form availability for the taxpayer calendar and its export |
| Canonical TIN root, Registration Units, and filing scope | Isolated session-only fixture-preview vertical slice: evidence-gated head office/branch lifecycle, fail-closed 2550Q planning, transient scope-provenance validation, and a value-owned read-only preview snapshot; immutable draft/artifact provenance remains deferred, while legacy cutover and the production policy catalog remain blocked |
| Recurring form drafts | Existing 2551Q/1701Q save/resume plus a grounded, ordered 1701Q exact-core integration in progress |
| Grounded 1701Q core | Exact 173-control contract, calculations, ordered validation, immutable profile mapping, candidate plaintext codecs, decrypt-only Artifact Lab, and schema-v4 draft streams under test |
| Other form editors and print previews | UI/projection coverage only; not filing-ready |
| Import, authentication, filing payment, and submission | UI only |
| Distribution | macOS development bundle, Linux package, and Windows ARM64 directory package; none is signed or production-ready |

**Do not use this app as an authoritative filing plan yet.** The taxpayer
calendar is limited to an explicitly configured, per-tax-year Forms Set and
resolves each deadline against that deadline's own taxable year. A taxpayer
year with no Forms Set, including a newly created year, shows no profile
deadlines and is not offered by the profile calendar year picker. The `.ics`
export preserves a compatibility fallback for legacy stores that have not yet
been configured, but newly saved yearly sets are always authoritative.
The app does not yet fully model fiscal periods, eFPS groups, every scoped
policy, filing submission, or official print/file parity. Deadline changes
synced from BIR issuances are machine-extracted from published PDFs and are
advisory; read the linked issuance before relying on a moved deadline. Always
confirm deadlines and filing requirements with official BIR guidance.

All bundled taxpayer data is synthetic. `reference/` is intentionally ignored
because source-app captures may contain private taxpayer data.

## Quick start

Requirements: Node.js 22.15+, Zig 0.16.0, and [Just](https://just.systems/).
Linux also needs `pkg-config`, GTK4, and WebKitGTK 6.0 development files. macOS is the
original development host. Windows ARM64 uses a pinned host-tool workaround
documented in the [Windows development guide](docs/WINDOWS_DEVELOPMENT.md).

On macOS or Linux, `just setup` provisions the pinned Zig compiler (verified
against its published SHA-256), checks the Node runtime, and installs the locked
npm dependencies. It is idempotent, and wraps the same script CI and the
development container run:

```sh
just setup
```

Then use the short command surface:

```sh
just run
```

`@native-sdk/cli` is pinned to 0.6.1 in `package-lock.json`.

### Just commands

```sh
just run       # local Debug app with hot reload
just build     # ReleaseFast binary in zig-out/bin/
just identity  # show this checkout's resolved app name and bundle ID
just package   # macOS .app, Linux package, or Windows ARM64 package
just app       # package, then open/launch it
just install   # install for the current user on macOS, Linux, or Windows
just check     # catalog, markup, and manifest checks
just news-sync-offline  # BIR news pipeline over the committed captures
just test      # headless Native SDK tests
just verify    # check, test, build, and whitespace validation
```

`just install` keeps the previous user-level app as a timestamped sibling. On
macOS the `main` build installs to `~/Applications/Buwiz App.app` by default. On Linux it
installs the package under `~/.local/lib/buwiz`, adds a launcher at
`~/.local/bin/buwiz`, and installs the desktop entry under
`~/.local/share/applications`. On Windows it installs the unsigned package to
`%LOCALAPPDATA%\Programs\Buwiz App` and creates a Start Menu shortcut. Set
`BUWIZ_INSTALL_DIR` to override the install prefix on Linux or the parent
directory on macOS and Windows.

Builds from branches other than `main` automatically receive a readable,
collision-resistant suffix in the executable name, display name, bundle ID,
package directory, install path, and default data directory. For example, a
`feature/tin` build is
named `buwiz-feature-tin-<hash>` and can run beside both the main Buwiz App and
the legacy eBIRForms application. Detached checkouts must set
`BUWIZ_BUILD_REF` to the source branch name before building. Use
`BUWIZ_DATA_DIR` for an explicit data location; branch builds reject the legacy
`EBIRFORMS_DATA_DIR` override so they cannot silently reuse legacy app data.
Use `just package` for distributable artifacts. On non-main branches, the
Native SDK's direct `zig build package` step fails closed because that upstream
step reads the unsuffixed root manifest.

Linux builds require GTK4 and WebKitGTK 6.0 development files because the Native SDK
uses the system GTK/WebKit host. Install them with
`sudo apt-get install pkg-config libgtk-4-dev libwebkitgtk-6.0-dev` on Debian/Ubuntu
(the dependency check prints Fedora and Arch equivalents). The Linux
artifact is a relocatable Native SDK directory; AppImage, Flatpak, and tarball
generation are still future release work. The Windows path is for the audited
Windows ARM64 environment; load it with the [Windows development guide](docs/WINDOWS_DEVELOPMENT.md)
before running the Windows build/package commands. Its package is unsigned
and is a copied application directory, not an MSI/MSIX installer.

## Development rule

The Native entrypoint and its bounded import shards are generated:

- `src/app.native`
- `src/app-shared.generated.native`
- `src/app-pages.generated.native`
- `src/app-forms.generated.native`
- `src/app-auxiliary.generated.native`

Edit files under `src/components/`, `src/pages/`, or
`src/app-root.fragment`, then run:

```sh
just generate
```

Commit all five regenerated Native outputs together. The generator is
deterministic and idempotent.

## Source map

- `src/main.zig` — application model, messages, navigation, effects, and tests
- `src/components/` — reusable UI and state components
- `src/pages/` — editable page and form markup
- `src/app*.generated.native` — generated bounded Native import shards
- `src/app.native` — generated Native root entrypoint
- `src/calendar/domain.zig` — deadline rules and schedule resolution
- `src/calendar/store.zig` — SQLite schema, policy, and provider mappings
- `src/calendar/ics.zig` — RFC 5545 calendar generation
- `src/calendar/ui_state.zig` — calendar state and application adapter
- `src/news/feed_json.zig` — bounded parser for the compiled BIR feed, covering
  both the Important News notices and the synced deadline overrides
- `src/preferences/store.zig` — app-owned interface preferences (theme, sidebar
  width, dashboard RDO context) in their own `preferences.sqlite3`
- `src/tax_profile/` — reusable facts, immutable revisions, evolution,
  persistence, canonical Taxpayer/Registration Unit evidence, migration
  inventory, and profile UI state
- `src/filing/` — reviewed policy selection, Filing Planner resolution,
  transient scope-provenance validation, and a value-owned read-only preview
  snapshot, plus exact form projection context; immutable draft/artifact
  provenance remains deferred
- `src/form_engine/` — occurrence-first exact form contracts, calculations,
  validation, workflow, and draft state
- `src/forms/` — generated catalog contracts and Native-facing form adapters
- `src/artifact_lab/` — masked local plaintext/ciphertext/decrypted comparison
- `src/container_codec/` — bounded, strict legacy decrypt-only codec
- `src/security/` — sensitive-memory helpers plus fail-closed key-custody and
  typed production repository-opening boundaries
- `scripts/tax-catalog/` — strict TypeScript catalog authoring and deterministic
  Zig/report generation
- `scripts/news-sync/` — deterministic BIR issuance sync: CMS reads, PDF
  extraction, feed compilation, and per-circular review reports; operated per
  the [news sync runbook](docs/news/NEWS_SYNC_OPERATIONS.md)
- `scripts/flatten-native.mjs` — modular markup generator
- `app.zon` — product manifest, permissions, assets, and platform target

## Quality gate

Before merging:

```sh
just verify
```

For visible changes, rebuild and relaunch the app before reviewing screenshots;
an already-running process may still show an older binary.

See the [contributor guide](docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md) for
automation, security, packaging, and the remaining release gates.
Windows contributors must also use the
[Windows ARM64 guide](docs/WINDOWS_DEVELOPMENT.md); invoking `npx native`
currently selects a crashing ARM64 CLI on the audited host.
