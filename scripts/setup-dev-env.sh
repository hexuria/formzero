#!/usr/bin/env bash
#
# Provision the Buwiz App toolchain: a pinned Zig compiler, a verified Node
# runtime, and the locked npm dependencies.
#
# This is the single provisioning path shared by GitHub Actions
# (.github/workflows/ci.yml) and container images
# (.devcontainer/devcontainer.json), so a green pipeline and a working
# development container cannot drift apart.
#
# The script is idempotent: re-running it on a provisioned host performs no
# downloads and leaves the toolchain untouched.
#
# Usage:
#   scripts/setup-dev-env.sh                        # toolchain and npm deps
#   scripts/setup-dev-env.sh --skip-npm             # toolchain only
#   scripts/setup-dev-env.sh --update-shell-profile # also persist PATH
#
# PATH is never written to a shell profile unless --update-shell-profile is
# passed. Container images opt in; a contributor's own machine is left alone
# and is shown the export line instead.
#
# Environment:
#   ZIG_INSTALL_ROOT  Where versioned Zig directories live.
#                     Default: $HOME/.local/zig
#   LOCAL_BIN         Where the `zig` symlink is created.
#                     Default: $HOME/.local/bin

set -euo pipefail

# Keep this in sync with `minimum_zig_version` in build.zig.zon. The assertion
# in verify_pinned_zig_version below fails the run if they diverge.
readonly ZIG_VERSION="0.16.0"

# Minimum Node runtime, per README.md "Quick start".
readonly NODE_MINIMUM_MAJOR=22
readonly NODE_MINIMUM_MINOR=15

# SHA-256 digests published at https://ziglang.org/download/index.json for
# ZIG_VERSION. A downloaded archive that does not match is deleted, never
# extracted.
zig_expected_sha256() {
    case "$1" in
    x86_64-linux) echo "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00" ;;
    aarch64-linux) echo "ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17" ;;
    x86_64-macos) echo "0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7" ;;
    aarch64-macos) echo "b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489" ;;
    *) return 1 ;;
    esac
}

readonly ZIG_INSTALL_ROOT="${ZIG_INSTALL_ROOT:-$HOME/.local/zig}"
readonly LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
readonly ZIG_PREFIX="$ZIG_INSTALL_ROOT/$ZIG_VERSION"

SKIP_NPM=0
UPDATE_SHELL_PROFILE=0

log() { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die() {
    printf '\nerror: %s\n' "$*" >&2
    exit 1
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --skip-npm) SKIP_NPM=1 ;;
        --update-shell-profile) UPDATE_SHELL_PROFILE=1 ;;
        -h | --help)
            sed -n '3,30p' "$0" | sed 's|^# \{0,1\}||'
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
        esac
        shift
    done
}

repository_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command '$1' not found. $2"
}

# Guards against the pinned compiler silently falling behind the build
# manifest. build.zig.zon is the product's source of truth; this script only
# carries the matching digests.
verify_pinned_zig_version() {
    local manifest="$1" declared
    declared="$(sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p' "$manifest")"
    [ -n "$declared" ] ||
        die "could not read minimum_zig_version from $manifest"
    [ "$declared" = "$ZIG_VERSION" ] ||
        die "build.zig.zon requires Zig $declared but this script pins $ZIG_VERSION.
       Update ZIG_VERSION and the zig_expected_sha256 digests together."
}

detect_zig_target() {
    local os arch
    case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="macos" ;;
    *) die "unsupported operating system '$(uname -s)'.
       Windows contributors follow docs/WINDOWS_DEVELOPMENT.md instead." ;;
    esac
    case "$(uname -m)" in
    x86_64 | amd64) arch="x86_64" ;;
    arm64 | aarch64) arch="aarch64" ;;
    *) die "unsupported CPU architecture '$(uname -m)'" ;;
    esac
    printf '%s-%s' "$arch" "$os"
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        die "neither sha256sum nor shasum is available; cannot verify downloads"
    fi
}

zig_version_at() {
    local candidate="$1"
    [ -x "$candidate" ] || return 1
    "$candidate" version 2>/dev/null
}

install_zig() {
    local target expected url archive extracted staging
    target="$(detect_zig_target)"
    expected="$(zig_expected_sha256 "$target")" ||
        die "no pinned Zig $ZIG_VERSION digest for target '$target'"

    if [ "$(zig_version_at "$ZIG_PREFIX/zig" || true)" = "$ZIG_VERSION" ]; then
        log "Zig $ZIG_VERSION already installed at $ZIG_PREFIX"
        return 0
    fi

    require_command curl "Install curl and re-run."
    require_command tar "Install tar and re-run."
    command -v xz >/dev/null 2>&1 ||
        die "'xz' is required to unpack the Zig archive.
       Debian/Ubuntu: apt-get install -y xz-utils"

    url="https://ziglang.org/download/$ZIG_VERSION/zig-$target-$ZIG_VERSION.tar.xz"
    staging="$(mktemp -d)"
    # shellcheck disable=SC2064 # expand staging now so cleanup survives reassignment
    trap "rm -rf '$staging'" RETURN
    archive="$staging/zig.tar.xz"

    log "downloading $url"
    curl --fail --location --silent --show-error --retry 3 --retry-delay 2 \
        --output "$archive" "$url" ||
        die "failed to download Zig $ZIG_VERSION for $target"

    local actual
    actual="$(sha256_of "$archive")"
    if [ "$actual" != "$expected" ]; then
        rm -f "$archive"
        die "checksum mismatch for zig-$target-$ZIG_VERSION.tar.xz
       expected $expected
       actual   $actual
       The archive was discarded and nothing was installed."
    fi
    log "sha256 verified"

    tar -xJf "$archive" -C "$staging"
    extracted="$staging/zig-$target-$ZIG_VERSION"
    [ -d "$extracted" ] ||
        die "unexpected archive layout: $extracted is missing"

    mkdir -p "$ZIG_INSTALL_ROOT"
    rm -rf "$ZIG_PREFIX"
    mv "$extracted" "$ZIG_PREFIX"
    log "installed Zig $ZIG_VERSION to $ZIG_PREFIX"
}

link_zig_onto_path() {
    mkdir -p "$LOCAL_BIN"
    ln -sf "$ZIG_PREFIX/zig" "$LOCAL_BIN/zig"

    # GitHub Actions consumes this file to extend PATH for later steps.
    if [ -n "${GITHUB_PATH:-}" ]; then
        printf '%s\n' "$LOCAL_BIN" >>"$GITHUB_PATH"
        log "exported $LOCAL_BIN through GITHUB_PATH"
        return 0
    fi

    if [ "$UPDATE_SHELL_PROFILE" -eq 1 ]; then
        # Opt-in only, for container images that own their own home directory.
        # One guarded block per profile, so repeated runs never accumulate.
        local marker="# added by ebirforms scripts/setup-dev-env.sh"
        local profile
        for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            [ -f "$profile" ] || continue
            grep -Fq "$marker" "$profile" && continue
            {
                printf '\n%s\n' "$marker"
                printf 'export PATH="%s:$PATH"\n' "$LOCAL_BIN"
            } >>"$profile"
            log "added $LOCAL_BIN to PATH in $profile"
        done
    fi

    case ":${PATH}:" in
    *":$LOCAL_BIN:"*) ;;
    *) log "for this shell, run: export PATH=\"$LOCAL_BIN:\$PATH\"" ;;
    esac
}

require_node() {
    require_command node "Install Node.js $NODE_MINIMUM_MAJOR.$NODE_MINIMUM_MINOR or newer."
    require_command npm "Install Node.js $NODE_MINIMUM_MAJOR.$NODE_MINIMUM_MINOR or newer."

    local raw major minor
    raw="$(node --version)"
    raw="${raw#v}"
    major="${raw%%.*}"
    minor="${raw#*.}"
    minor="${minor%%.*}"

    if [ "$major" -lt "$NODE_MINIMUM_MAJOR" ] ||
        { [ "$major" -eq "$NODE_MINIMUM_MAJOR" ] && [ "$minor" -lt "$NODE_MINIMUM_MINOR" ]; }; then
        die "Node $NODE_MINIMUM_MAJOR.$NODE_MINIMUM_MINOR or newer is required, found $(node --version)"
    fi
    log "Node $(node --version), npm $(npm --version)"
}

install_npm_dependencies() {
    if [ "$SKIP_NPM" -eq 1 ]; then
        log "skipped (--skip-npm)"
        return 0
    fi
    # `npm ci` is mandatory rather than `npm install`: @native-sdk/cli is pinned
    # to 0.6.1 in package-lock.json and the model contract is version-specific.
    npm ci
    log "installed locked dependencies"
}

main() {
    parse_arguments "$@"
    local root
    root="$(repository_root)"
    cd "$root"

    step "Verifying pinned toolchain versions"
    verify_pinned_zig_version "$root/build.zig.zon"
    log "Zig $ZIG_VERSION matches build.zig.zon"

    step "Installing Zig $ZIG_VERSION"
    install_zig
    link_zig_onto_path

    step "Checking Node runtime"
    require_node

    step "Installing npm dependencies"
    install_npm_dependencies

    step "Toolchain ready"
    log "zig:  $("$ZIG_PREFIX/zig" version)"
    log "next: npm run generate && npx native test --yes -Dplatform=null"
}

main "$@"
