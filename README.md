# eBIRForms Native reconstruction

This project recreates the current Rust/GPUI eBIRForms desktop surfaces
with [Native SDK](https://github.com/vercel-labs/native) declarative markup
and a compact Zig state core.

Most form, filing, payment, authentication, import, print, and network
surfaces remain presentation-only. The tax-calendar milestone is functional:
it resolves recurring deadlines, applies business-day policy and sourced
overrides, persists calendar policy in SQLite, and exports the selected
calendar year to the user's default calendar application.

## Tax calendar

- 12 compiled rule groups ported from the local Rust reference, covering
  152 dated obligations per taxable year and 18 event-based obligations.
- Calendar-year projection includes prior-December and prior-taxable-year
  filings whose final due date falls in the selected year.
- Saturdays and Sundays are automatic. Official holidays and closures are
  explicit, source-cited SQLite records; no guessed holiday data is seeded.
- Sourced deadline overrides are applied after base business-day adjustment.
  Regions, taxpayer types, effective dates, and expiry metadata are preserved.
- The calendar database is stored in the platform application-data directory
  as `calendar.sqlite3`, with migrations, foreign keys, WAL, and a busy timeout.
- “Add to default calendar” creates a standards-compliant all-day `.ics`
  calendar with stable UIDs and 7-day/1-day alerts, then opens the registered
  calendar application. Importing into an iCloud, Google, or Outlook calendar
  can propagate through that account.

The `.ics` path is a user-confirmed import handoff, not managed two-way sync.
Provider-neutral connection/event mapping tables are ready for later EventKit,
Google Calendar API, or Microsoft Graph adapters, but direct OAuth sync is not
configured. The current packaged application target remains macOS.

## Included surfaces

- 7 primary application pages
- 10 BIR form editor layouts
- 7 auxiliary overlays, previews, and supporting windows
- 1 Screen Gallery that makes every static surface directly reviewable

All sample taxpayer information is synthetic. Local GPUI reference captures
live under `reference/` and are intentionally git-ignored because the source
application can display private taxpayer data.

Rendered Native review captures are kept in `review/`:

- `global-dashboard.png`
- `screen-gallery.png`
- `form-0605.png`
- `admin-auth.png`
- `theme-light.png`
- `theme-dark.png`

## Engineering guide

Read the
[Native SDK guide and eBIRForms improvement plan](docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md)
before adding CI, full-loop tests, automation, extensions, or release signing.

## Source layout

- `src/main.zig` owns navigation, appearance, and Native SDK effect wiring.
- `src/calendar/domain.zig` owns pure rules and schedule resolution.
- `src/calendar/store.zig` owns SQLite schema, policy, and provider mappings.
- `src/calendar/ics.zig` owns standards-based calendar export.
- `src/calendar/ui_state.zig` converts domain/storage records into bounded UI state.
- `src/components/` contains the shared application shell.
- `src/pages/` contains the editable screen templates.
- `src/app-root.fragment` contains the final page dispatcher.
- `src/app.native` is generated; do not edit it directly.

Native SDK 0.6.1 compiles one markup entrypoint. The deterministic flattening
step keeps the editable files modular while producing that runtime entrypoint.
The theme selector uses model-owned Geist design tokens while preserving the
system high-contrast and reduced-motion settings.

## Build and run

```sh
rtk npm ci
rtk npm run generate
rtk npx native test --yes -Dplatform=null
rtk npx native check . --strict
rtk npx native build . --yes
rtk npx native dev . --yes
```

Run the flattening command after editing any `.native` source. The generated
file is stable and the script is idempotent.

The repository owns its Native SDK 0.6.1 build graph and pins the official
SQLite 3.53.4 amalgamation by Zig package hash. Requirements: Node.js 22.15
or newer and Zig 0.16.0.
