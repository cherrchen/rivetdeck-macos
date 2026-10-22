#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Redirect compiler caches for restricted build environments; does not alter DSH policy.
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/rivetdeck-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/rivetdeck-swift-cache"
exec swift test --scratch-path "${RIVETDECK_BUILD_DIR:-/tmp/rivetdeck-native-build}" \
  --cache-path "${TMPDIR:-/tmp}/rivetdeck-spm-cache" \
  --config-path "${TMPDIR:-/tmp}/rivetdeck-spm-config" \
  --security-path "${TMPDIR:-/tmp}/rivetdeck-spm-security" --disable-sandbox "$@"
