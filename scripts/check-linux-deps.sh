#!/usr/bin/env bash

set -euo pipefail

if ! command -v pkg-config >/dev/null 2>&1; then
    printf '%s\n' \
        'error: pkg-config is required for the Linux Native SDK build.' \
        '       Debian/Ubuntu: sudo apt-get install pkg-config libgtk-4-dev' \
        '       Fedora:        sudo dnf install pkgconf-pkg-config gtk4-devel' \
        '       Arch:          sudo pacman -S pkgconf gtk4' >&2
    exit 1
fi

if ! pkg-config --exists gtk4; then
    printf '%s\n' \
        'error: GTK4 development files were not found.' \
        '       Debian/Ubuntu: sudo apt-get install pkg-config libgtk-4-dev' \
        '       Fedora:        sudo dnf install pkgconf-pkg-config gtk4-devel' \
        '       Arch:          sudo pacman -S pkgconf gtk4' >&2
    exit 1
fi

if ! pkg-config --exists webkitgtk-6.0; then
    printf '%s\n' \
        'error: WebKitGTK 6.0 development files were not found.' \
        '       Debian/Ubuntu: sudo apt-get install pkg-config libgtk-4-dev libwebkitgtk-6.0-dev' \
        '       Fedora:        sudo dnf install pkgconf-pkg-config gtk4-devel webkitgtk6.0-devel' \
        '       Arch:          sudo pacman -S pkgconf gtk4 webkitgtk-6.0' >&2
    exit 1
fi

printf 'GTK4: %s\n' "$(pkg-config --modversion gtk4)"
printf 'WebKitGTK: %s\n' "$(pkg-config --modversion webkitgtk-6.0)"
