# eBIRForms Native

Native macOS reconstruction of eBIRForms, built with Native SDK 0.6.1 and Zig
0.16.0. The app includes responsive desktop UI, ten BIR form layouts, a global
form/deadline dashboard, and a functional tax-calendar engine.

## Product status

| Area | Status |
| --- | --- |
| Navigation, themes, responsive layouts | Functional |
| Global Dashboard form filter | Functional; 51-form searchable multi-select |
| Tax deadline calculation | Functional; 20 compiled rule groups |
| Calendar policy | Persisted in SQLite with sourced holidays and overrides |
| Calendar export | Functional `.ics` handoff to the default calendar app |
| Tax profiles and Forms Set | Persisted, revisioned, effective-dated, and shared by calendar/form availability |
| Recurring form drafts | 2551Q and 1701Q profile snapshots plus transaction values save/resume |
| Other form editors and print previews | UI/projection coverage only; not filing-ready |
| Import, authentication, filing payment, and submission | UI only |
| Distribution | macOS development build; not notarized or production-ready |

**Do not use this app as an authoritative filing plan yet.** Calendar export
applies a selected taxpayer's persisted Forms Set when configured and uses the
catalog fallback only while that set is unconfigured. It does not yet fully
model fiscal periods, eFPS groups, every scoped policy, filing submission, or
official print/file parity. Always confirm deadlines and filing requirements
with official BIR guidance.

All bundled taxpayer data is synthetic. `reference/` is intentionally ignored
because source-app captures may contain private taxpayer data.

## Quick start

Requirements: Node.js 22.15+, Zig 0.16.0, and macOS.

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
- `src/tax_profile/` — reusable facts, immutable revisions, persistence, and profile UI state
- `src/forms/` — generated form contracts, profile composition, draft persistence, and 2551Q/1701Q transaction state
- `scripts/tax-catalog/` — strict TypeScript catalog authoring and deterministic Zig/report generation
- `scripts/flatten-native.mjs` — modular markup generator
- `app.zon` — product manifest, permissions, assets, and platform target

## Quality gate

Before merging:

```sh
npm run generate
npm run check:tax-catalog
git diff --check
npx native test --yes -Dplatform=null
npx native check . --strict
npx native build . --yes
```

For visible changes, rebuild and relaunch the app before reviewing screenshots;
an already-running process may still show an older binary.

See the [contributor guide](docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md) for
automation, security, packaging, and the remaining release gates.
