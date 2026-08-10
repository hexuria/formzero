#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd -P)"
cd "$repository_root"

eval "$(node scripts/app-identity.mjs prepare --format shell)"

package_root="zig-out/package"
app_bundle="$package_root/$BUWIZ_APP_NAME.app"
if [ -e "$app_bundle" ] || [ -L "$app_bundle" ]; then
  backup="$app_bundle.previous.$(date +%Y%m%d-%H%M%S)"
  mv "$app_bundle" "$backup"
  printf 'Moved previous package to %s\n' "$backup"
fi

npx native package \
  --target macos \
  --manifest "$BUWIZ_MANIFEST" \
  --output "$app_bundle" \
  --binary "zig-out/bin/$BUWIZ_APP_NAME" \
  --optimize ReleaseFast \
  --web-layer exclude \
  --web-engine system \
  --signing adhoc \
  --assets assets

codesign --verify --deep --strict "$app_bundle"
printf 'Packaged %s (%s)\n' "$app_bundle" "$BUWIZ_BUNDLE_ID"
