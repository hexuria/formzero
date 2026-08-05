#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd -P)"
cd "$repository_root"

bash scripts/check-linux-deps.sh

package_root="zig-out/package/linux"
if [ -e "$package_root" ] || [ -L "$package_root" ]; then
    backup="$package_root.previous.$(date +%Y%m%d-%H%M%S)"
    mv "$package_root" "$backup"
    printf 'Moved previous package to %s\n' "$backup"
fi

exec npx native package \
    --target linux \
    --manifest app.zon \
    --output "$package_root" \
    --binary zig-out/bin/ebirforms-zero \
    --optimize ReleaseFast \
    --web-layer exclude \
    --web-engine system \
    --signing none \
    --assets assets
