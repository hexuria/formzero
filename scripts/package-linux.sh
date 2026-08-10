#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd -P)"
cd "$repository_root"

bash scripts/check-linux-deps.sh
eval "$(node scripts/app-identity.mjs prepare --format shell)"

package_root="zig-out/package/$BUWIZ_APP_NAME-linux"
if [ -e "$package_root" ] || [ -L "$package_root" ]; then
    backup="$package_root.previous.$(date +%Y%m%d-%H%M%S)"
    mv "$package_root" "$backup"
    printf 'Moved previous package to %s\n' "$backup"
fi

exec npx native package \
    --target linux \
  --manifest "$BUWIZ_MANIFEST" \
    --output "$package_root" \
  --binary "zig-out/bin/$BUWIZ_APP_NAME" \
    --optimize ReleaseFast \
    --web-layer exclude \
    --web-engine system \
    --signing none \
    --assets assets
