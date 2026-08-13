# Use PowerShell for recipes on Windows; Unix hosts keep just's sh default.

set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]
set positional-arguments

npm_command := if os() == "windows" { "npm.cmd" } else { "npm" }

default:
    @just --list

# Reclaim only declared build artifacts; no target lists choices and changes nothing.
[unix]
clean *args:
    @WORKSPACE_MAINTENANCE_CWD="$(git rev-parse --show-toplevel)" WORKSPACE_MAINTENANCE_JUST_PID="$PPID" WORKSPACE_MAINTENANCE_JUST_EXE="$(command -v just)" node "{{justfile_directory()}}/scripts/workspace-maintenance.mjs" clean "$@"

[windows]
clean *args:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 maintenance clean (Get-Variable args).Value

# Remove one exact registered worktree after fail-closed safety checks.
[unix]
worktree-remove *args:
    @WORKSPACE_MAINTENANCE_CWD="$(git rev-parse --show-toplevel)" WORKSPACE_MAINTENANCE_JUST_PID="$PPID" WORKSPACE_MAINTENANCE_JUST_EXE="$(command -v just)" node "{{justfile_directory()}}/scripts/workspace-maintenance.mjs" worktree-remove "$@"

[windows]
worktree-remove *args:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 maintenance worktree-remove (Get-Variable args).Value

# Prepare the branch-qualified manifest and print its resolved identity.
identity:
    node scripts/app-identity.mjs prepare --format json

# Provision the pinned Zig toolchain and locked npm dependencies.
[unix]
setup:
    if [ "{{ os() }}" = "linux" ]; then bash scripts/check-linux-deps.sh; fi
    bash scripts/setup-dev-env.sh

# Windows toolchains are pinned and loaded by the Windows development guide.
[windows]
setup:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 setup

# Reinstall only the locked JavaScript dependencies.
deps:
    {{ npm_command }} ci

# Regenerate the Native markup and tax-catalog outputs.
generate:
    {{ npm_command }} run generate

# Run the BIR news-sync pipeline against the live CMS and publish outputs.
news-sync:
    {{ npm_command }} run news:sync -- all

# Run the same pipeline against the committed captures; touches no network.
news-sync-offline:
    {{ npm_command }} run news:sync -- all --offline

# Validate catalog ownership and Native markup/app manifest.
[macos]
check: generate
    #!/usr/bin/env bash
    set -euo pipefail
    {{ npm_command }} run test:app-identity
    {{ npm_command }} run test:windows-maintenance
    {{ npm_command }} run test:workspace-maintenance
    {{ npm_command }} run check:tax-catalog

    {{ npm_command }} run check:postal-reference
    {{ npm_command }} run typecheck:news-sync
    {{ npm_command }} run test:news-sync
    eval "$(node scripts/app-identity.mjs prepare --format shell)"
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native doctor --manifest "$BUWIZ_MANIFEST" --strict

[linux]
check: generate
    #!/usr/bin/env bash
    set -euo pipefail
    {{ npm_command }} run test:app-identity
    {{ npm_command }} run check:tax-catalog

    {{ npm_command }} run check:postal-reference
    bash scripts/check-linux-deps.sh
    eval "$(node scripts/app-identity.mjs prepare --format shell)"
    node scripts/patch-native-sdk-combobox-tab.mjs
    # Strict doctor treats macOS-only codesigning as an unsupported Linux
    # capability. Validate the manifest explicitly; build/package below prove
    # the actual Linux host integration.
    npx native validate "$BUWIZ_MANIFEST"
    npx native doctor --manifest "$BUWIZ_MANIFEST"

[windows]
check: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 check

# Run the headless Native SDK test suite.
[unix]
test: generate
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native test . --yes -Dplatform=null

[windows]
test: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 test

# Build a ReleaseFast production binary into zig-out/bin/.
[macos]
build: generate
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native build . --yes

[windows]
build: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 build

[linux]
build: generate
    bash scripts/check-linux-deps.sh
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native build . --yes

# Build a ReleaseFast binary with Native automation enabled.
[macos]
build-automation: generate
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native build . --yes -Dautomation=true

[windows]
build-automation: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 build-automation

[linux]
build-automation: generate
    bash scripts/check-linux-deps.sh
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native build . --yes -Dautomation=true

# Run the local Debug app with Native markup hot reload.
[macos]
run: generate
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native dev . --yes

[windows]
run: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 run

[linux]
run: generate
    bash scripts/check-linux-deps.sh
    node scripts/patch-native-sdk-combobox-tab.mjs
    npx native dev . --yes

# Check the toolchain and manifest without building the app.
[macos]
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(node scripts/app-identity.mjs prepare --format shell)"
    npx native doctor --manifest "$BUWIZ_MANIFEST" --strict

[linux]
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/check-linux-deps.sh
    eval "$(node scripts/app-identity.mjs prepare --format shell)"
    npx native validate "$BUWIZ_MANIFEST"
    npx native doctor --manifest "$BUWIZ_MANIFEST"

[windows]
doctor:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 doctor

# Create and verify an ad-hoc signed macOS application bundle.
[macos]
package: build
    bash scripts/package-macos.sh

# Create and verify the documented unsigned Windows ARM64 package.
[windows]
package: build
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 package

[linux]
package: build
    bash scripts/package-linux.sh

# Build the production bundle and open a fresh app instance.
[macos]
app: package
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(node scripts/app-identity.mjs prepare --format shell)"
    open -n "zig-out/package/$BUWIZ_APP_NAME.app"

[windows]
app: package
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 app

[linux]
app: package
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(node scripts/app-identity.mjs prepare --format shell)"
    exec "zig-out/package/$BUWIZ_APP_NAME-linux/bin/$BUWIZ_APP_NAME"

# Install current-user macOS application; set BUWIZ_INSTALL_DIR=/Applications for system-wide install.
[macos]
install: package
    bash scripts/install-macos.sh

# Install the unsigned Windows package for the current user; override the

# parent directory with BUWIZ_INSTALL_DIR when needed.
[windows]
install: package
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 install

[linux]
install: package
    bash scripts/install-linux.sh

# Run the main local validation gates.
verify: check test build
    git diff --check
