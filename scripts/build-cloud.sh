#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
mkdir -p dist
case "${1:?Choose Erosion-Check or GestaltX}" in
  Erosion-Check)
    xcodebuild -quiet -project Erosion.xcodeproj -scheme Erosion \
      -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
      -derivedDataPath "$RUNNER_TEMP/erosion-derived" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
      DEVELOPMENT_TEAM="" SDKROOT=iphoneos \
      PRODUCT_BUNDLE_IDENTIFIER=com.zwthys.ErosionCheck \
      'INFOPLIST_KEY_CFBundleDisplayName=Erosion 验证' build
    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT
    mkdir -p "$stage/Payload"
    cp -R "$RUNNER_TEMP/erosion-derived/Build/Products/Release-iphoneos/Erosion.app" "$stage/Payload/"
    app="$stage/Payload/Erosion.app"
    while IFS= read -r -d '' nested; do
      codesign -f -s - "$nested"
    done < <(find "$app" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
    codesign -f -s - --entitlements Erosion/Erosion.entitlements "$app"
    (cd "$stage" && zip -qry "$root/dist/Erosion-26.6-Check-v2.ipa" Payload)
    git rev-parse HEAD > dist/source-commit.txt
    ;;
  GestaltX)
    source_sha=36110fd7544ceefdc419e13d337ec515e3ec53dc
    source_dir="$RUNNER_TEMP/gestaltx-source"
    git init "$source_dir"
    git -C "$source_dir" remote add origin https://github.com/huamidev/GestaltX.git
    git -C "$source_dir" fetch --depth 1 origin "$source_sha"
    git -C "$source_dir" checkout --detach FETCH_HEAD
    bash "$source_dir/.github/scripts/build-ipa.sh" "$root/dist"
    git -C "$source_dir" rev-parse HEAD > dist/source-commit.txt
    ;;
  *) echo 'Unknown build target' >&2; exit 2 ;;
esac
