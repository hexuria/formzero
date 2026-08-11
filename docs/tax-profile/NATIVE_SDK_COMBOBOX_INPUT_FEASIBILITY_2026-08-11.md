# Native SDK Combobox/Input Feasibility — 2026-08-11

## Scope and source boundary

This note reviews the Native SDK `0.6.1` source and bundled official Native UI
guidance installed in this checkout. It does **not** claim that the behavior
below is available from an unmodified upstream package: this workspace adds a
postinstall patch at `scripts/patch-native-sdk-combobox-tab.mjs`.

The official Native UI guide documents `combobox` as a text-entry element with
`placeholder` and `on-input`; single-line text-entry controls can also use
`on-submit`. It documents the built-in clear affordance only for
`search-field`, not for `combobox`. [1]

## Verification boundary

`native check` and `native markup check` are provided by a prebuilt platform
binary. [9] That binary embeds the unpatched 0.6.1 markup parser, so it still
reports `on-blur` as unknown even after this workspace patches the SDK source.
It is therefore not a valid gate for this version-pinned extension. The
authoritative checks are `npx native test --yes -Dplatform=null` and
`npx native build . --yes`: both invoke Zig builds whose generated framework
dependency resolves through `NATIVE_SDK_PATH` to the patched
`node_modules/@native-sdk/cli` source. [10] A future standalone static checker
would need a locally rebuilt Native CLI, not another source patch.

## Finding

| Requested behavior | Feasible? | Evidence and boundary |
| --- | --- | --- |
| `on-blur` on `<input>` / `<combobox>` | Yes, with this workspace's patch | The patch adds the `blur` event to the schema, limits it to text-entry widgets, adds `on_blur` to the UI handler model, and dispatches it when focus moves. [2] This is not described in the bundled public element table, which lists `on-input` and `on-submit` only. [1] |
| `selected` + `expanded` bindings | Yes | `selected` is part of the documented appearance/state attribute vocabulary, and `expanded` is represented in widget semantics. [3] The local patch uses `selected` specifically to show the combobox clear affordance, and uses `expanded` to choose `chevron-up` versus `chevron-down`. [4] |
| Clear-X on a selected combobox | Yes, with this workspace's patch and an `on-input` clear handler | The patch changes the clear predicate to include selected comboboxes and renders the shared clear button in place of the chevron. The runtime turns that press into `TextInputEvent.clear`, which reaches `on-input`. [4][5] The application must clear its authoritative selection in its `on-input` reducer; clearing only displayed text is not sufficient. |
| Tab / Shift+Tab into the first / last filtered menu item | Yes, with this workspace's patch | The patch adds an owned-combobox menu-entry lookup. Its runtime changes keep the menu mounted and move focus to the first visible entry on Tab or last visible entry on Shift+Tab. [6] |
| Enter selects the focused result | Yes | The patch deliberately leaves Enter on the normal focused `menu-item` activation path. Its added runtime test opens a combobox, enters its first row with Tab, presses Enter, and asserts that the model closes the menu. [7] Application menu items still need `on-press` handlers that commit the chosen value. |
| macOS Command+Backspace/Delete clears text-entry widgets | Yes, with this workspace's patch | The patch maps `super` + Backspace/Delete (without Alt/Shift) to `TextInputEvent.clear`; the local SDK test covers both key names and asserts `on-input` receives the edit. [8] This is intentionally macOS-only and is not an application-level command. |

## Application implications

- Bind `expanded` to the app-owned dropdown state for every combobox expected
  to show an open-state chevron. A selected combobox intentionally shows clear-X
  instead of the chevron, so the up-chevron is observable when the control has
  no committed selection.
- Bind `selected` only where the application can define a real clear operation.
  A non-null canonical field such as `SubjectKind` should remain non-clearable
  until its domain model defines an explicit unset/default transition.
- Treat keyboard and pointer clear identically: both arrive as
  `TextInputEvent.clear` through `on-input`. The reducer should clear the
  authoritative value, displayed query, and any open picker state together.
- The SDK patch includes generic runtime regression tests, but Profile Setup
  still benefits from an app-level integration test that verifies the real
  widget bindings and resulting domain mutation.

## Sources

1. Bundled official Native UI guide, text-entry element contract:
   [`node_modules/@native-sdk/cli/skill-data/native-ui/SKILL.md:176-179`](../../node_modules/@native-sdk/cli/skill-data/native-ui/SKILL.md#L176-L179).
2. Workspace patch, schema/UI/markup blur support:
   [`scripts/patch-native-sdk-combobox-tab.mjs:61-152`](../../scripts/patch-native-sdk-combobox-tab.mjs#L61-L152).
3. Native SDK widget semantic state (`selected` and optional `expanded`):
   [`node_modules/@native-sdk/cli/src/automation/snapshot.zig:198-203`](../../node_modules/@native-sdk/cli/src/automation/snapshot.zig#L198-L203).
4. Workspace patch, selected-combobox clear-X and expanded-chevron rendering:
   [`scripts/patch-native-sdk-combobox-tab.mjs:158-198`](../../scripts/patch-native-sdk-combobox-tab.mjs#L158-L198).
5. Native SDK runtime, clear-X dispatches `.clear` through the normal text edit
   path:
   [`node_modules/@native-sdk/cli/src/runtime/canvas_widget_events.zig:2150-2167`](../../node_modules/@native-sdk/cli/src/runtime/canvas_widget_events.zig#L2150-L2167).
6. Workspace patch, owned-menu Tab/Shift+Tab behavior:
   [`scripts/patch-native-sdk-combobox-tab.mjs:229-276`](../../scripts/patch-native-sdk-combobox-tab.mjs#L229-L276).
7. Native SDK runtime regression test, Tab enters a menu and Enter activates it:
   [`node_modules/@native-sdk/cli/src/runtime/ui_app_tests.zig:2675-2724`](../../node_modules/@native-sdk/cli/src/runtime/ui_app_tests.zig#L2675-L2724).
8. Workspace patch and installed SDK implementation for Command+Delete:
   [`scripts/patch-native-sdk-combobox-tab.mjs:164-179`](../../scripts/patch-native-sdk-combobox-tab.mjs#L164-L179) and
   [`node_modules/@native-sdk/cli/src/primitives/canvas/events.zig:402-456`](../../node_modules/@native-sdk/cli/src/primitives/canvas/events.zig#L402-L456).
9. Native CLI dispatcher resolves and spawns an optional per-platform binary,
   while passing the packaged SDK source path separately:
   [`node_modules/@native-sdk/cli/bin/native.js:1-12`](../../node_modules/@native-sdk/cli/bin/native.js#L1-L12) and
   [`node_modules/@native-sdk/cli/bin/native.js:66-126`](../../node_modules/@native-sdk/cli/bin/native.js#L66-L126).
10. Native build/test verbs invoke `zig build`, and generated build graphs use
    `NATIVE_SDK_PATH` as the `native_sdk` dependency root:
    [`node_modules/@native-sdk/cli/src/tooling/verbs.zig:75-143`](../../node_modules/@native-sdk/cli/src/tooling/verbs.zig#L75-L143) and
    [`node_modules/@native-sdk/cli/src/tooling/buildgraph.zig:60-80`](../../node_modules/@native-sdk/cli/src/tooling/buildgraph.zig#L60-L80).
