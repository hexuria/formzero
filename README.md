# eBIRForms Native static reconstruction

This project recreates the current Rust/GPUI eBIRForms desktop surfaces
with [Native SDK](https://github.com/vercel-labs/native) declarative markup
and a compact Zig state core.

The milestone is deliberately presentation-only. Filing, payment,
authentication, importing, persistence, validation, printing, and network
actions are not implemented.

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

- `src/main.zig` owns page selection and System/Light/Dark appearance state.
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
rtk node scripts/flatten-native.mjs
rtk native test
rtk native check --strict
rtk native build
rtk native dev
```

Run the flattening command after editing any `.native` source. The generated
file is stable and the script is idempotent.

Requirements: Native SDK CLI 0.6.1, Node.js 22.15 or newer, and Zig.
