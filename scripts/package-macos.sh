#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd -P)"
cd "$repository_root"

eval "$(node scripts/app-identity.mjs prepare --format shell)"

package_root="zig-out/package"
app_bundle="$package_root/$BUWIZ_APP_NAME.app"
runtime_assets="$repository_root/.zig-cache/$BUWIZ_APP_NAME-package-assets"

# Package only assets declared by app.zon. The workspace can contain unrelated
# design-review artifacts under assets/; copying the entire tree makes the
# production bundle non-reproducible and can exceed the Native SDK per-file
# packaging limit.
rm -rf "$runtime_assets"
mkdir -p "$runtime_assets/assets/brand"
cp assets/icon.png "$runtime_assets/assets/icon.png"
cp assets/brand/bagong-pilipinas.png "$runtime_assets/assets/brand/bagong-pilipinas.png"
cp assets/brand/bir-new-logo.png "$runtime_assets/assets/brand/bir-new-logo.png"
cp assets/brand/goldcoders-logo.png "$runtime_assets/assets/brand/goldcoders-logo.png"
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
  --assets "$runtime_assets"

codesign --verify --deep --strict "$app_bundle"
printf 'Packaged %s (%s)\n' "$app_bundle" "$BUWIZ_BUNDLE_ID"
