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
| Form editors and print previews | UI only; not filing-ready |
| Profile setup, import, authentication, payment, and submission | UI only |
| Distribution | macOS development build; not notarized or production-ready |

**Do not use this app as an authoritative filing plan yet.** Calendar export
currently falls back to the full supported form catalog. It does not yet apply
a taxpayer's persisted Forms Set, fiscal year, eFPS group, or scoped policy.
Always confirm deadlines and filing requirements with official BIR guidance.

All bundled taxpayer data is synthetic. `reference/` is intentionally ignored
because source-app captures may contain private taxpayer data.

## Quick start

Requirements: Node.js 22.15+, Zig 0.16.0, and macOS.

```sh
rtk npm ci
rtk npm run generate
rtk npx native test --yes -Dplatform=null
rtk npx native check . --strict
rtk npx native build . --yes
rtk npx native dev . --yes
```

`@native-sdk/cli` is pinned to 0.6.1 in `package-lock.json`.

## Development rule

`src/app.native` is generated. Edit files under `src/components/`,
`src/pages/`, or `src/app-root.fragment`, then run:

```sh
rtk npm run generate
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
- `scripts/flatten-native.mjs` — modular markup generator
- `app.zon` — product manifest, permissions, assets, and platform target

## Quality gate

Before merging:

```sh
rtk npm run generate
rtk git diff --check
rtk npx native test --yes -Dplatform=null
rtk npx native check . --strict
rtk npx native build . --yes
```

For visible changes, rebuild and relaunch the app before reviewing screenshots;
an already-running process may still show an older binary.

See the [contributor guide](docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md) for
automation, security, packaging, and the remaining release gates.
