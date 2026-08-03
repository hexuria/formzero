# Working in this repository

Cross-platform eBIRForms reconstruction: Zig 0.16.0, Native SDK CLI 0.6.1,
Node 22.15+. macOS is the supported build host.

`README.md` is the product overview and
`docs/NATIVE_SDK_GUIDE_AND_IMPROVEMENT_PLAN.md` is the operational guide. This
file is the short version of what will bite you.

## Never do these

- **Do not edit `src/app.native`.** It is generated. Edit `src/components/`,
  `src/pages/`, or `src/app-root.fragment`, run `npm run generate`, and commit
  the regenerated output. The generator is deterministic; CI fails on drift.
- **Do not commit taxpayer data**, credentials, signing material, private
  captures, logs, or submission payloads. `reference/` is gitignored because
  source-app captures may contain real taxpayer data. All fixtures and
  screenshots must be synthetic.
- **Do not enable filing, payment, authentication, or production print.** Those
  actions stay disabled until their domain and safety gates exist.
- **Do not widen a fail-closed path.** Unresolved profile state means "export
  nothing", never "export the whole catalog". This pattern is deliberate and
  load-bearing throughout `tax_profile/` and `calendar/`.

## Before you claim a change works

Run the whole gate. Test and build are both required: Zig's lazy analysis lets
either one alone miss code reachable only from the other.

```sh
npm run generate
npm run check:tax-catalog
git diff --check main...HEAD
npx native test --yes -Dplatform=null
npx native check . --strict
npx native build . --yes
```

`git diff --check` needs the range. Bare, it compares the working tree to the
index, so committed whitespace damage passes locally and fails in CI.

`npx native check . --strict` is the gate that matters when you move types:
markup binds to `Model` members through `src/main.zig`, so a moved type must
stay re-exported from there or 27 markup files stop resolving. The test suite
will not catch that.

For visible changes, rebuild and relaunch before trusting screenshots — a
running process may still be the old binary.

## Layout worth knowing

- `src/main.zig` — application model, messages, navigation, effects. Large;
  prefer extracting to a module over adding to it.
- `src/forms/` — catalog contracts and Native-facing form adapters
- `src/form_engine/` — exact form packages. `package.zig` defines the parts
  every form must expose; `root.zig` holds the registry. Adding a form means a
  new directory with `mod.zig` plus one registry line, and the compiler names
  whatever is missing.
- `src/calendar/` — deadline rules, SQLite policy, ICS export
- `src/tax_profile/` — revisioned, effective-dated profiles and Forms Sets
- `scripts/setup-dev-env.sh` — provisions the pinned toolchain; CI and the
  devcontainer both call it

## Conventions

- Match the surrounding comment density. This codebase explains *why* a
  boundary is fail-closed or a value is frozen; keep that up rather than
  narrating what the code already says.
- Deadline and form-availability behaviour is filing-critical. Changing it
  needs a regression test that fails before the change.
- The tax catalog is authored in strict TypeScript under `scripts/tax-catalog/`
  and compiled to Zig. Edit the TypeScript, never the generated
  `src/forms/generated/catalog.zig`.
