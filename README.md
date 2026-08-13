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
just clean            # list precise cleanup targets; changes nothing
just worktree-remove  # list registered worktrees; changes nothing
just package   # macOS .app, Linux package, or Windows ARM64 package
just app       # package, then open/launch it
just install   # install for the current user on macOS, Linux, or Windows
just check     # catalog, markup, and manifest checks
just news-sync-offline  # BIR news pipeline over the committed captures
just test      # headless Native SDK tests
just verify    # check, test, build, and whitespace validation
```

### Workspace maintenance

`just clean` is deliberately an inspection-only usage error. It prints the
literal cleanup catalog without touching any file. Select one rebuildable
artifact family in the current worktree, or preview it first:

```sh
just clean zig-cache --dry-run
just clean zig-cache
just clean build
just clean standard
just clean all --force
```

Cleanup first quarantines the selected roots so a mistaken selection remains
recoverable. After reviewing the exact receipt path printed by the command,
permanently reclaim that disk space with the receipt-bound purge:

```sh
just clean purge '/exact/quarantine/receipt.json' --dry-run
just clean purge '/exact/quarantine/receipt.json' --force
```

`purge` never accepts a directory or glob. It revalidates the receipt, every
quarantined path, symlink and filesystem containment, and registered-worktree
topology before removing that one transaction. Purge a worktree's receipt
before removing that worktree; once the source is no longer registered, purge
fails closed because it can no longer independently reconstruct provenance.

Purge authorizes deletion from an exact pre-tombstone manifest, stages each
known leaf by identity, unlinks only that staged leaf, and removes directories
bottom-up with non-recursive empty-directory removal. It never performs a
recursive sweep. Unknown replacements and late insertions are retained and
make purge fail closed. This protects cooperative maintenance, but Node's
pathname APIs cannot make the final rename, unlink, or empty-directory syscall
atomic against a hostile same-user writer; writers must remain stopped during
that final instant. A failure after an artifact move never automatically
restores it: the transaction stays quarantined and a recovery receipt records
each successful rename as verified or uncertain, including expected root
identity and Native-link metadata.

Artifact mutation refuses symlinked roots, ancestors, and nested links, with
one narrow exception for Native's generated layout: an exact
`.native/identities/<identity>/{src,assets}` link may point only to the same
registered worktree's physical `src/` or `assets/` directory. Those links are
counted as leaf entries and never followed. Wrong-target, deeper, dangling, or
newly inserted links fail closed; receipt-bound purge revalidates the exact
links moved into quarantine and rejects replacements or additions. Read-only
inventory may count any other link as a leaf so every registered worktree can
still be reported without traversing it.

On Unix, `just clean` authenticates and independently walks its live launcher
ancestry before the process guard runs. Only that causal chain is exempt, and
only when each process's sole handle in the worktree is a current directory
outside the selected artifact roots. A forged launcher PID, an open artifact
file, or any unrelated shell, app, watcher, or unknown process still refuses
mutation.

The catalog contains only `.zig-cache`, `zig-cache`, `zig-pkg`, `zig-out`,
`.native`, `node_modules`, `coverage`, `test-results`, and
`scripts/news-sync/work`. `all` still means only those declared roots and
requires `--force`; it never means every ignored file. Credentials, private
`reference/` captures, logs, `.claude/`, tracked generated sources, and
backup-suffixed directories are outside the catalog. Cross-worktree cleanup
requires an exact registered absolute path plus `--force`; inspect first with
`just clean list --all-worktrees`.

Remove one linked worktree only by its exact absolute path:

```sh
just worktree-remove '/absolute/registered/worktree/path' --dry-run
just worktree-remove '/absolute/registered/worktree/path' --into origin/main
just worktree-remove '/absolute/registered/worktree/path' --into origin/main --force
```

Normal removal requires a clean, inactive worktree whose `HEAD` is an ancestor
of the locally available integration ref (`origin/main` by default; cleanup
never fetches). `--force` bypasses only ordinary dirty/untracked state and the
integration proof. It cannot bypass primary/current-worktree, exact-path,
locked/prunable/nested-worktree, active-or-unknown-process, Git-operation,
conflict, submodule, protected-ignored-data, or state-drift guards. The command
uses `git worktree remove`, leaves the branch intact, and never prunes metadata
or recursively deletes a caller-supplied directory. Forced removal of a
detached worktree first creates and prints a timestamped
`refs/buwiz/worktree-rescue/...` ref so its commit remains reachable.

Worktree removal refuses every ignored path, including declared build
artifacts, even with `--force`. Run an explicit fine-grained cleanup first so
the removal command never silently treats ignored data as disposable.

Artifact cleanup moves selected roots into a same-filesystem quarantine and
prints a metadata-only receipt. Purging is a separate irreversible command as
shown above. Mutation is currently supported on macOS and Linux hosts with
`lsof`; unsupported or incomplete process inspection always refuses safely.
The Node maintenance module supports Windows artifact inventory, cleanup dry
runs, and bare worktree inventory, including paths with spaces; Windows CI
verifies the complete Just-to-PowerShell argument forwarding path. Exact-path
worktree-removal assessment and destructive maintenance are intentionally
unavailable there until an equally reliable Windows process inspector is
implemented. Process
and filesystem state are rechecked immediately before mutation; no local tool
can prevent a hostile external process from starting in the final instant
before Git acts.

Each worktree intentionally keeps its own `node_modules` and local Zig cache.
The npm download cache and Zig's default global cache are host-level and shared
by default. Installed dependency trees and local Zig build graphs remain
checkout-specific because branches may carry different lockfiles and build
state; symlinking those mutable directories would let one worktree alter
another.

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
- `scripts/postal-reference/` — pinned GeoNames `PH.zip` snapshot, provenance
  manifest, tests, and deterministic offline Zig catalogue generator (CC BY
  4.0; © GeoNames, <https://www.geonames.org/>)
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
