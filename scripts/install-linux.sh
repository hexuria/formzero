#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd -P)"
package_root="$repository_root/zig-out/package/linux"

if [ ! -d "$package_root" ]; then
    printf 'error: Linux package directory is missing: %s\n' "$package_root" >&2
    exit 1
fi

prefix="${EBIRFORMS_INSTALL_DIR:-$HOME/.local}"
app_name="ebirforms-zero"
app_dir="$prefix/lib/$app_name"
launcher="$prefix/bin/$app_name"
desktop_file="$prefix/share/applications/$app_name.desktop"

mkdir -p "$prefix/bin" "$prefix/lib" "$prefix/share"

if [ -e "$app_dir" ] || [ -L "$app_dir" ]; then
    backup="$app_dir.previous.$(date +%Y%m%d-%H%M%S)"
    mv "$app_dir" "$backup"
    printf 'Moved previous install to %s\n' "$backup"
fi

mkdir -p "$app_dir"
cp -a "$package_root/." "$app_dir/"

if [ -e "$launcher" ] || [ -L "$launcher" ]; then
    backup="$launcher.previous.$(date +%Y%m%d-%H%M%S)"
    mv "$launcher" "$backup"
    printf 'Moved previous launcher to %s\n' "$backup"
fi
ln -s "../lib/$app_name/bin/$app_name" "$launcher"

if [ -d "$package_root/share" ]; then
    cp -a "$package_root/share/." "$prefix/share/"
fi

if [ ! -f "$desktop_file" ]; then
    printf 'error: Linux desktop entry is missing: %s\n' "$desktop_file" >&2
    exit 1
fi

# Native SDK emits a package-relative Exec value. The installed launcher is
# absolute so desktop environments also work with a custom prefix.
tmp_desktop="$desktop_file.tmp.$$"
awk -v launcher="$launcher" '
    /^Exec=/ {
        print "Exec=\"" launcher "\""
        next
    }
    { print }
' "$desktop_file" >"$tmp_desktop"
mv "$tmp_desktop" "$desktop_file"

installed_binary="$app_dir/bin/$app_name"
if [ ! -x "$installed_binary" ]; then
    printf 'error: installed Linux executable is missing: %s\n' "$installed_binary" >&2
    exit 1
fi

printf 'Installed %s\n' "$app_dir"
printf 'Launcher: %s\n' "$launcher"
printf 'Desktop entry: %s\n' "$desktop_file"
