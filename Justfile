# Use PowerShell for recipes on Windows; Unix hosts keep just's sh default.

set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

app_bundle := "zig-out/package/ebirforms-zero.app"
npm_command := if os() == "windows" { "npm.cmd" } else { "npm" }

default:
    @just --list

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

# Validate catalog ownership and Native markup/app manifest.
[unix]
check: generate
    {{ npm_command }} run check:tax-catalog
    npx native check . --strict

[windows]
check: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 check

# Run the headless Native SDK test suite.
[unix]
test: generate
    npx native test . --yes -Dplatform=null

[windows]
test: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 test

# Build a ReleaseFast production binary into zig-out/bin/.
[macos]
build: generate
    npx native build . --yes

[windows]
build: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 build

[linux]
build: generate
    bash scripts/check-linux-deps.sh
    npx native build . --yes

# Build a ReleaseFast binary with Native automation enabled.
[macos]
build-automation: generate
    npx native build . --yes -Dautomation=true

[windows]
build-automation: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 build-automation

[linux]
build-automation: generate
    bash scripts/check-linux-deps.sh
    npx native build . --yes -Dautomation=true

# Run the local Debug app with Native markup hot reload.
[macos]
run: generate
    npx native dev . --yes

[windows]
run: generate
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 run

[linux]
run: generate
    bash scripts/check-linux-deps.sh
    npx native dev . --yes

# Check the toolchain and manifest without building the app.
[unix]
doctor:
    npx native doctor --manifest app.zon --strict

[windows]
doctor:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 doctor

# Create and verify an ad-hoc signed macOS application bundle.
[macos]
package: build
    npx native package --target macos --signing adhoc
    codesign --verify --deep --strict {{ app_bundle }}

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
    open -n {{ app_bundle }}

[windows]
app: package
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 app

[linux]
app: package
    zig-out/package/linux/bin/ebirforms-zero

# Install the current-user macOS application; set EBIRFORMS_INSTALL_DIR=/Applications for system-wide install.
[macos]
install: package
    #!/usr/bin/env bash
    set -euo pipefail
    target_dir="${EBIRFORMS_INSTALL_DIR:-$HOME/Applications}"
    target_app="$target_dir/eBIRForms.app"
    mkdir -p "$target_dir"
    if [[ -e "$target_app" ]]; then
        backup="$target_app.previous.$(date +%Y%m%d-%H%M%S)"
        mv "$target_app" "$backup"
        echo "Moved previous install to $backup"
    fi
    ditto {{ app_bundle }} "$target_app"
    echo "Installed $target_app"

# Install the unsigned Windows package for the current user; override the

# parent directory with EBIRFORMS_INSTALL_DIR when needed.
[windows]
install: package
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/just-windows.ps1 install

[linux]
install: package
    bash scripts/install-linux.sh

# Run the main local validation gates.
verify: check test build
    git diff --check
