#!/bin/bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_directory="$repository_root/.build/release-build"
output_directory="$repository_root/.build/dist"
mkdir -p "$output_directory"

xcodebuild \
  -project "$repository_root/DNS Easy Switcher.xcodeproj" \
  -scheme "DNS Easy Switcher" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_directory" \
  'ARCHS=arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  "CURRENT_PROJECT_VERSION=${GITHUB_RUN_NUMBER:-1}" \
  build

application="$build_directory/Build/Products/Release/DNS Easy Switcher.app"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$application/Contents/Info.plist")"
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid application version: $release_version" >&2
  exit 1
fi
if [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" != "v$release_version" ]]; then
  echo "Release tag must match the application version: v$release_version" >&2
  exit 1
fi

architectures="$(/usr/bin/lipo -archs "$application/Contents/MacOS/DNS Easy Switcher")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    echo "The application is missing its $architecture executable." >&2
    exit 1
  fi
done
/usr/bin/codesign --verify --deep --strict "$application"

asset_name="DNS-Easy-Switcher-$release_version-universal-macos"
staging_directory="$(mktemp -d "$build_directory/package.XXXXXX")"
trap 'rm -rf -- "$staging_directory"' EXIT
/usr/bin/ditto "$application" "$staging_directory/DNS Easy Switcher.app"
ln -s /Applications "$staging_directory/Applications"

/usr/bin/ditto -c -k --keepParent "$application" "$output_directory/$asset_name.zip"
/usr/bin/hdiutil create \
  -volname "DNS Easy Switcher" \
  -srcfolder "$staging_directory" \
  -format UDZO \
  -ov "$output_directory/$asset_name.dmg"
/usr/bin/hdiutil verify "$output_directory/$asset_name.dmg"
/usr/bin/unzip -tq "$output_directory/$asset_name.zip"

cp "$repository_root/CHANGELOG.md" "$output_directory/RELEASE_NOTES.md"
(
  cd "$output_directory"
  /usr/bin/shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > SHA256SUMS
)
echo "Universal release packages: $output_directory"
