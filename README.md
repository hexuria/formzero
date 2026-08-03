# eBIRForms Native

[![CI](https://github.com/hexuria/formzero/actions/workflows/ci.yml/badge.svg)](https://github.com/hexuria/formzero/actions/workflows/ci.yml)

Cross-platform reconstruction of eBIRForms, built with Native SDK 0.6.1 and
Zig 0.16.0. The app includes responsive desktop UI, ten BIR form layouts, a
global form/deadline dashboard, and a functional tax-calendar engine.

## Product status

| Area | Status |
| --- | --- |
| Navigation, themes, responsive layouts | Functional |
| Global Dashboard calendar | Functional; complete resolved schedule, never profile-filtered |
| Tax deadline calculation | Functional; 20 compiled rule groups |
| Calendar policy | Persisted in SQLite with sourced holidays and overrides |
| Calendar export | Functional `.ics` handoff to the default calendar app, scoped to the profile's Forms Set |
| Tax profiles and Forms Set | Persisted, revisioned, effective-dated, and the sole source of form availability for the taxpayer calendar and its export |
| Recurring form drafts | Existing 2551Q/1701Q save/resume plus a grounded, ordered 1701Q exact-core integration in progress |
| Grounded 1701Q core | Exact 173-control contract, calculations, ordered validation, immutable profile mapping, candidate plaintext codecs, decrypt-only Artifact Lab, and schema-v4 draft streams under test |
| Other form editors and print previews | UI/projection coverage only; not filing-ready |
| Import, authentication, filing payment, and submission | UI only |
| Distribution | macOS development build and Windows ARM64 development executable; neither is signed or production-ready |

**Do not use this app as an authoritative filing plan yet.** The taxpayer
calendar is limited to an explicitly configured, per-tax-year Forms Set and
resolves each deadline against that deadline's own taxable year. A taxpayer
year with no Forms Set, including a newly created year, shows no profile
deadlines and is not offered by the profile calendar year picker. The `.ics`
export preserves a compatibility fallback for legacy stores that have not yet
been configured, but newly saved yearly sets are always authoritative.
The app does not yet fully model fiscal periods, eFPS groups, every scoped
policy, filing submission, or official print/file parity. Always confirm
deadlines and filing requirements with official BIR guidance.

All bundled taxpayer data is synthetic. `reference/` is intentionally ignored
because source-app captures may contain private taxpayer data.

## Quick start

Requirements: Node.js 22.15+ and Zig 0.16.0. macOS is the original development
host. Windows ARM64 uses a pinned host-tool workaround documented in the
[Windows development guide](docs/WINDOWS_DEVELOPMENT.md).

On macOS or Linux, `scripts/setup-dev-env.sh` provisions the pinned Zig
compiler (verified against its published SHA-256), checks the Node runtime, and
installs the locked npm dependencies. It is idempotent, and it is the same
script CI and the development container run:

```sh
scripts/setup-dev-env.sh
```

Otherwise, install the toolchain yourself and start from `npm ci`:

```sh
npm ci
npm run generate
npx native test --yes -Dplatform=null
npx native check . --strict
npx native build . --yes
npx native dev . --yes
```

`@native-sdk/cli` is pinned to 0.6.1 in `package-lock.json`.

## Development rule

`src/app.native` is generated. Edit files under `src/components/`,
`src/pages/`, or `src/app-root.fragment`, then run:

```sh
npm run generate
```

Commit the regenerated `src/app.native`. The generator is deterministic and
idempotent.

## Source map

- `src/main.zig` — application model, messages, navigation, effects, and tests
- `src/components/` — reusable UI and state components
- `src/pages/` — editable page and form markup
- `src/calendar/domain.zig` — deadline rules and schedule resolution
- `src/calendar/store.zig` — SQLite schema, policy, and provider mappings
- `src/calendar/ics.zig` — RFC 5545 calendar generation
- `src/calendar/ui_state.zig` — calendar state and application adapter
- `src/tax_profile/` — reusable facts, immutable revisions, evolution,
  persistence, and profile UI state
- `src/form_engine/` — occurrence-first exact form contracts, calculations,
  validation, workflow, and draft state
- `src/forms/` — generated catalog contracts and Native-facing form adapters
- `src/artifact_lab/` — masked local plaintext/ciphertext/decrypted comparison
- `src/container_codec/` — bounded, strict legacy decrypt-only codec
- `src/security/` — sensitive-memory helpers plus fail-closed key-custody and
  typed production repository-opening boundaries
- `scripts/tax-catalog/` — strict TypeScript catalog authoring and deterministic
  Zig/report generation
- `scripts/flatten-native.mjs` — modular markup generator
- `app.zon` — product manifest, permissions, assets, and platform target

## Quality gate

Before merging:

```sh
npm run generate
npm run check:tax-catalog
git diff --check main...HEAD
npx native test --yes -Dplatform=null
npx native check . --strict
npx native build . --yes
```

For visible changes, rebuild and relaunch the app before reviewing screenshots;
an already-running process may still show an older binary.

See the [contributor guide](docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md) for
automation, security, packaging, and the remaining release gates.
Windows contributors must also use the
[Windows ARM64 guide](docs/WINDOWS_DEVELOPMENT.md); invoking `npx native`
currently selects a crashing ARM64 CLI on the audited host.
