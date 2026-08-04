# Finding: the Native SDK ships an OS credential store (2026-08-04)

Status: informational record. This changes no decision and lifts no gate.
ADR-0001 and the provider decision packet remain the authorities; this
document exists so the eventual custody work starts from what is actually
available rather than rediscovering it.

## What was found

The Native SDK (0.6.1) exposes a working OS-native credential store,
reachable from application Zig today:

- **API surface** — `PlatformServices.setCredential / getCredential /
  deleteCredential` (`node_modules/@native-sdk/cli/src/platform/types.zig`,
  ~:2875), over `CredentialKey { service, account }` and
  `Credential { service, account, secret }` (~:1304). Limits: service 128
  bytes, account 256 bytes, **secret 4096 bytes** — ample for a wrapped
  database key. Errors are explicit (`CredentialNotFound`,
  `CredentialFieldTooLarge`, `InvalidCredentialOptions`), and unbound
  services return `error.UnsupportedService`. A capability probe exists
  (`.credentials`).
- **Real backends, not stubs**:
  - macOS: Keychain via `SecItemAdd/Update/CopyMatching/Delete`,
    `kSecClassGenericPassword` (`src/platform/macos/root.zig` ~:1976;
    `appkit_host.m` ~:12071).
  - Windows: Credential Manager via `CredWriteW/CredReadW/CredDelete`,
    `CRED_TYPE_GENERIC` (`src/platform/windows/root.zig` ~:1366;
    `webview2_host.cpp` ~:6591).
  - Linux: libsecret via `dlopen("libsecret-1.so.0")` and
    `secret_password_{store,lookup,clear}_sync` (`src/platform/linux/root.zig`
    ~:1317; `gtk_host.c` ~:4758).
  - The null test platform ships an in-memory fake
    (`src/platform/null_platform.zig` ~:1434), so an adapter is testable
    with `-Dplatform=null`.
- **The seam already exists in this app.** `Effects.services` exposes
  `*const PlatformServices` and the COR file dialog already calls a platform
  service through it (`src/main.zig`, `attachCorDocument`). A custody
  adapter would use the same pattern; no SDK change is needed.

## Caveats the custody ADR must resolve

1. **Primitive mismatch.** The decision packet's simplest Windows candidate
   is raw DPAPI CurrentUser (`CryptProtectData`) wrapping a random database
   key. The SDK primitive is **Credential Manager**, which stores blobs
   DPAPI-protected per-user but is a different API with different
   enumeration, roaming, and backup behavior than the packet analyzed.
   Choosing the SDK path means re-running the packet's user-presence and
   scope-binding analysis against Credential Manager; it is not a drop-in.
2. **Manifest permission.** `app.zon` does not declare the `credentials`
   permission. The permission check is enforced on the JS bridge, not on
   Zig-side `PlatformServices` calls, but the manifest should declare it
   before any adapter ships.
3. **Windows coupling.** The Windows credential functions are bound only
   when `web_engine == .system`. `app.zon` sets that today; the coupling is
   worth a regression guard if an adapter ever lands.
4. **No effect variant.** Credentials exist only as synchronous
   loop-thread platform services (plus JS-bridge wrappers); there is no
   async effect. Fine for key unwrap at open; worth knowing before designing
   rotation flows.

## Why nothing was built

The gate's current state is `unavailable_authenticated_storage_backend_
unselected` — the **backend** half (SQLCipher/SEE selection, licensing, and
the packet's ten approvals) is external and unresolved, and
`key_custody.zig`'s comptime guard forbids any non-`unavailable_` state by
design. A custody-provider adapter against the SDK store is technically
unblocked and would advance the *second* checkpoint
(`unavailable_operating_system_custody_provider_unimplemented`), but it was
deliberately deferred: consumer-less custody code written before the
CredMan-vs-DPAPI decision risks encoding the wrong primitive, and ADR-0001
requires the provider and backend to be named in the same reviewed change.
