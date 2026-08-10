#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd -P)"
cd "$repository_root"

eval "$(node scripts/app-identity.mjs prepare --format shell)"

source_app="zig-out/package/$BUWIZ_APP_NAME.app"
if [ ! -d "$source_app" ]; then
  printf 'error: macOS package is missing: %s\n' "$source_app" >&2
  exit 1
fi

target_dir="${BUWIZ_INSTALL_DIR:-$HOME/Applications}"
target_app="$target_dir/$BUWIZ_DISPLAY_NAME.app"
mkdir -p "$target_dir"
if [ -e "$target_app" ] || [ -L "$target_app" ]; then
  backup="$target_app.previous.$(date +%Y%m%d-%H%M%S)"
  mv "$target_app" "$backup"
  printf 'Moved previous install to %s\n' "$backup"
fi

ditto "$source_app" "$target_app"
printf 'Installed %s\n' "$target_app"
