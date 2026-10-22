# Runtime installation and distribution

## Current development artifact

`runtime/package.json` has one direct production dependency, @deepseek-ai/dsh **0.2.1-rc.2**. npm's package-lock locks all registry artifacts and integrity hashes; pnpm/workspace dependencies and adjacent repositories are not required to build. npm 11.16.0 is recorded as the package manager. Node 24.18.0 was tested. `npm ci --prefix runtime` installs build-time runtime assets, while `npm --prefix runtime run verify` checks versions, loads koffi and actually spawns/exits a native PTY. Installation errors remain in terminal output; no app startup installs are performed.

npm 11.16 reported five packages with lifecycle scripts. The checked-in exact-version allowScripts entries cover DSH's executable-bit repair helper, node-pty, koffi and protobufjs. The Google genai no-op preinstall is denied. Older npm may ignore this policy; use the recorded toolchain. No installed upstream source is edited. A clean **offline npm ci** using the already-filled cache was executed successfully, proving the lock/cache closure; first-time installation still needs the registry.

`scripts/build-app.sh --bundle-runtime /absolute/path/to/node` builds the native app and copies the installed, verified **entire** production closure, the real Node executable and its available license into a developer bundle. There are no npm devDependencies in this runtime manifest. A new bundle is staged and signed before replacing this script’s generated App in .artifacts. Xcode's ordinary Run uses the selected development Node/runtime paths. Both builds use the same Process → Node → declared dsh bin → --profile sdk mechanism and initialize handshake.

```text
RivetdeckNative.app/Contents/
  MacOS/RivetdeckNative           SwiftUI/AppKit executable
  Resources/
    node/bin/node                architecture-specific Node executable
    node/LICENSE                 Node notices (when available beside distribution)
    runtime/package.json
    runtime/package-lock.json
    runtime/node_modules/        complete official production closure
    runtime-build.json           Node version, architecture and DSH version
    Rivetdeck-LICENSE
```

Mutable DSH state belongs under `~/Library/Application Support/Rivetdeck Native/DSH`, never inside the signed bundle. Runtime lookup first permits explicit user configuration; otherwise it finds bundled Resources, then the development working directory. Node lookup permits an explicit real executable, bundled Node, common installation paths and local nvm installations. Finder launch requires neither a shell startup script nor pnpm. Do not distribute a version-manager shim as Node.

The current developer bundle is roughly **1 GiB on disk** (976 MiB in the final development build) before optimization, dominated by the official dsh CLI dependency closure (installed node_modules ~834 MiB). This is disk footprint, not a memory/CPU measurement. No Electron or Chromium is included by Rivetdeck. Do not claim quantified resource savings without profiling. Removing unused packages or platform binaries requires audited closure tests, including plugins; this kickoff deliberately does not prune the upstream install.

## Native dependencies actually inspected

- `node-pty@1.2.0-beta.15`: darwin-arm64 pty.node and spawn-helper are Mach-O arm64. verify runs a real /bin/sh PTY through the public package. DSH's published postinstall restores spawn-helper's executable bit.
- `koffi@3.1.1`: native FFI prebuild successfully loaded. Each target architecture must have its own valid prebuild/build and signing treatment.
- The selected Node executable's otool dependencies were system CoreFoundation, Security, libc++ and libSystem; no local Homebrew dynamic library dependency was observed.
- These checks prove only the current ARM64 development machine. The Swift Xcode target also compiles x86_64; the bundled Node/native closure remains ARM64 and **Intel operation is not verified**.

Profile composition includes more dependencies than immediate chat startup uses. Native imports can be lazy; successful npm installation or handshake is not proof every tool/helper works. Full Shell-Agent tool execution, sandbox helpers under hardened runtime, remote providers and third-party plugin native dependencies remain validation work.

## Offline startup versus model connectivity

Bundled Node + npm closure supports startup, handshake and session operations without registry access. No npm/pnpm is invoked at startup. Offline does not provide an offline DeepSeek model: requests need valid credentials and provider connectivity unless a separately configured local model is used. The automated local model fixture is a **test-only simulator**, never an app fallback.

The development app can read a saved Keychain credential on explicit Connect. Runtime receives a restricted environment, independent DSH_HOME and workspace. No ambient NODE_OPTIONS, DSH permission override or arbitrary API token is forwarded. Tests use disposable homes and workspaces. See architecture.md for process deadlines and cleanup limitations.

## Plugins and pnpm

The shipped CLI's plugin manager invokes pnpm and owns profile locks/compatibility checks. The prototype bundles no package manager and has no native plugin-install UI. Existing bundled Host services run without pnpm. For deliberate development-only plugin management, disconnect the app, set its exact DSH_HOME, make a supported pnpm available and use the official CLI:

```sh
DSH_HOME="$HOME/Library/Application Support/Rivetdeck Native/DSH" \
  /absolute/path/to/node runtime/node_modules/@deepseek-ai/dsh/lib/bin.js \
  plugin --profile sdk add '<published-package@exact-version>'
```

This syntax/profile mechanism was inspected; third-party installations were not executed. Do not change Electron's profile or use its unpublished desktop Host artifacts. A future distributed installer must supply a pinned package-manager runtime in a separate maintenance path, verify integrity, preserve profile ownership, handle native rebuilds and avoid changing signed app resources. Installing arbitrary npm plugins executes trusted local code; native UI is not a sandbox for plugins.

## Developer signing and release gates

The build script applies **ad-hoc development signing**. In the current restricted automation environment codesign required execution outside the tool sandbox; ordinary Terminal/Xcode development is unaffected. `--deep --sign -` is for a local development artifact only. It is not a valid public release strategy and does not establish notarization or Gatekeeper acceptance.

Before public distribution:

1. Acquire pinned Node directly from official Node distributions with checksums/provenance; record minimum macOS support. Copy the Node license and retain third-party licenses. Produce an SBOM from the exact npm lock and review package licenses.
2. Build/install production closures for each architecture; validate PTY, Koffi, spawn-helper, all native libraries and every lazily loaded supported tool. Do not mix ARM64 Node with an Intel runtime.
3. Enumerate nested Mach-O executables, .node bundles and dylibs; sign each with Developer ID in dependency order, then sign the outer app. Evaluate Node JIT entitlements and library validation deliberately. The present app has no hardened-runtime entitlement validation; this is a release blocker.
4. Run codesign strict verification, Gatekeeper/quarantine tests, sandbox/approval tests, all process-crash/descendant cleanup cases and offline smoke against the **relocated signed** bundle. Ensure plugin code remains in mutable data directories with an explicit trust policy.
5. Create archive/DMG, submit via notarytool, staple, validate on a clean ARM64 Mac. Signing identity, provisioning and notarization credentials are intentionally not assumed or requested here.
6. Rehearse upgrades with a separate DSH home and persisted sessions. Never let two products write the same profile until upstream migration/concurrent access semantics are proven. Design rollback and automatic update only after this gate.

The project's original GPL-3.0 LICENSE is retained. DSH packages are MIT and other dependencies keep their own notices. Final release notices/redistribution review is still required.
