#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-Debug}"
derived="${RIVETDECK_DERIVED_DATA:-/tmp/rivetdeck-native-xcode}"
# This flag affects compiler macro subprocesses only, never DSH sandbox/approval policy.
xcodebuild -project RivetdeckNative.xcodeproj -scheme RivetdeckNative \
  -configuration "$configuration" -derivedDataPath "$derived" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' CODE_SIGNING_ALLOWED=NO build
mkdir -p .artifacts
staging="$(mktemp -d "$PWD/.artifacts/build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/RivetdeckNative.app"
ditto "$derived/Build/Products/$configuration/RivetdeckNative.app" "$bundle"
if [[ "${1:-}" == "--bundle-runtime" ]]; then
  node_binary="${2:?Supply an absolute Node.js executable path}"
  "$node_binary" -e 'if (+process.versions.node.split(".")[0] < 24) process.exit(1)'
  "$node_binary" runtime/scripts/verify.mjs
  resources="$bundle/Contents/Resources"
  mkdir -p "$resources/runtime" "$resources/node/bin"
  cp "$node_binary" "$resources/node/bin/node"
  node_license="$(dirname "$node_binary")/../LICENSE"
  if [[ -f "$node_license" ]]; then cp "$node_license" "$resources/node/LICENSE"; fi
  cp runtime/package.json runtime/package-lock.json "$resources/runtime/"
  ditto runtime/node_modules "$resources/runtime/node_modules"
  cp LICENSE "$resources/Rivetdeck-LICENSE"
  "$node_binary" -p 'JSON.stringify({node:process.version,arch:process.arch,dsh:"0.2.1-rc.2"}, null, 2)' > "$resources/runtime-build.json"
fi
# Development only. Public distribution requires explicit nested Developer ID signing.
codesign --force --deep --sign - "$bundle"
# Replace only this script's generated artifact, after the new bundle is complete.
destination="$PWD/.artifacts/RivetdeckNative.app"
rm -rf -- "$destination"
mv "$bundle" "$destination"
echo "Built $destination"
