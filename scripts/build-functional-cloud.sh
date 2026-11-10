#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$task_root/upstream-functional"
expected_source=2764867bdbba0f69170b2a0d835179b20116fdc6
test "$(git -C "$source_dir" rev-parse HEAD)" = "$expected_source"
mkdir -p "$task_root/dist"
cd "$source_dir"
xcodebuild -quiet -project Erosion.xcodeproj -scheme Erosion \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$RUNNER_TEMP/erosion-functional-derived" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" SDKROOT=iphoneos \
  PRODUCT_BUNDLE_IDENTIFIER=com.zwthys.ErosionCN \
  'INFOPLIST_KEY_CFBundleDisplayName=Erosion CN' build
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload"
ditto "$RUNNER_TEMP/erosion-functional-derived/Build/Products/Release-iphoneos/Erosion.app" "$stage/Payload/Erosion.app"
app="$stage/Payload/Erosion.app"
# Keep the main bundle directly under Payload and use an XML Info.plist for importers.
plutil -convert xml1 "$app/Info.plist"
while IFS= read -r -d '' nested; do
  codesign -f -s - "$nested"
done < <(find "$app" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
codesign -f -s - --entitlements Erosion/Erosion.entitlements "$app"
(cd "$stage" && zip -qry "$task_root/dist/Erosion-CN-0.7.2-Compat.ipa" Payload)
git rev-parse HEAD > "$task_root/dist/upstream-source-commit.txt"
cat > "$task_root/dist/INSTALL.txt" <<'EOF'
Erosion-CN 0.7.2 functional build (not the v3 permission-only checker).
Source: Kianuni/Erosion-CN at 2764867bdbba0f69170b2a0d835179b20116fdc6.
Built on GitHub using the standard Payload/Erosion.app/Info.plist layout.
The IPA is ad-hoc signed. Re-sign it with your own certificate and App Group.
Import Erosion-CN-0.7.2-Compat.ipa after extracting the outer artifact ZIP.
This package has NOT been tested for device installation or Apple Intelligence activation.
Before applying changes, export the original MobileGestalt backup for the current iOS build.
EOF
