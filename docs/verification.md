# Verification record — 2026-10-22

Executed locally on Apple Silicon, macOS **15.8 (24H23)**, Xcode **16.4 (16F6)**, Swift **6.1.2**, Node **24.18.0**, npm **11.16.0**. All model tests were keyless or used an explicitly marked loopback model fixture. No real paid-model API was exercised.

| Check | Command / result |
| --- | --- |
| Registry metadata and dependency install | `npm --cache /tmp/rivetdeck-npm-cache install --prefix runtime --no-audit --no-fund` — 613 packages installed from published registry packages. |
| Locked reinstall offline | `npm ci --prefix runtime --cache /tmp/rivetdeck-npm-cache --offline --no-audit --no-fund` — passed, 613 packages, existing cache. First-time installation still requires network. |
| Native runtime closure | `npm --prefix runtime run verify` — pinned DSH package identities, koffi load, real node-pty /bin/sh spawn/output/exit passed. |
| M0 standalone Swift | Compile `runtime/scripts/stdio-poc.swift`, run with the real Node executable — handshake, two sessions, cwd get/set, prompt receipt, 21 notifications, expected unsupported cancel error, shutdown exit 0. |
| Swift build | `swift build --scratch-path /tmp/rivetdeck-build --cache-path /tmp/rivetdeck-spm-cache --disable-sandbox` with redirected compiler caches — passed, app/core/probe built. |
| Swift/XCTest + real runtime | `RIVETDECK_BUILD_DIR=/tmp/rivetdeck-build RIVETDECK_INTEGRATION_NODE=<real-node> RIVETDECK_RUNTIME_ROOT=$PWD/runtime scripts/swift-check.sh` — **12 tests passed, 0 failures, 0 skipped**. Individual cases and timestamps are preserved in docs/evidence/swift-tests.txt. |
| Default keyless unit mode | Same script without integration environment — previous run passed with the official-runtime test safely skipped. Fixture peer tests require only the system Python installed with Xcode. |
| Production Swift client / DSH | `dsh-probe <real-node> $PWD/runtime <isolated-home>` — actual session/prompt/events, visible MISSING_CREDENTIAL failure, shutdown, restart, persisted ID resume. |
| Relocated bundled runtime | Same production probe using `.artifacts/RivetdeckNative.app/Contents/Resources/node/bin/node` and its Resources/runtime — passed, independent of the development Node/npm closure. |
| Real DSH / test model | `node Tests/Integration/model-fixture.mjs /tmp/rivetdeck-build/debug/dsh-probe` — real DSH working_directory tool call/result, real assistant/message carrying deterministic fixture text, 25 session notifications, restart/resume. Not a DeepSeek-generated answer. |
| Web alternative | `node runtime/scripts/web-probe.mjs` — unsigned request 401, authenticated session/list success, cross-origin request 403, Swift URLSession unary success, Swift WebSocket `$events` ready and cancellation, Host stopped. |
| Xcode native app | `xcodebuild -project RivetdeckNative.xcodeproj -scheme RivetdeckNative -configuration Debug -derivedDataPath /tmp/rivetdeck-native-xcode OTHER_SWIFT_FLAGS='-disable-sandbox' CODE_SIGNING_ALLOWED=NO build` — **BUILD SUCCEEDED**, arm64 and x86_64 Swift compilation. This does not validate an Intel Node runtime. |
| Developer bundle | `scripts/build-app.sh --bundle-runtime <real-node>` — passed; native App, complete production npm dependencies, ARM64 Node and Node license copied, staged ad-hoc signature completed. |
| Native App automated smoke | One earlier prototype run passed (one window, handshake/receipt, 16 UI rows, credential failure, clean exit). **Final unattended command-line repeat still timed out before producing result.json in this desktop automation environment. It is not counted as a final automated pass.** The final normal-app user flow below passed interactively. |
| Native desktop inspection | The final normal-app user flow (see evidence/native-user-flow.md) selected a workspace with NSOpenPanel, verified bundled paths in Settings, connected, submitted a prompt, displayed the real credential failure, disconnected and quit. Computer-use accessibility inspection confirmed the actual SwiftUI/AppKit split window, toolbar, sidebar, composer, diagnostic sheet, connected state, real session rows and MISSING_CREDENTIAL conversation error. No WebView involved. |
| Final signature verification | `codesign --verify --deep --strict .artifacts/RivetdeckNative.app` — exit 0. Developer ad-hoc signature, not Developer ID/notarized. |
| Project/static checks | `plutil -lint RivetdeckNative.xcodeproj/project.pbxproj`, `bash -n scripts/*.sh`, `git diff --check` — passed. |

Evidence is under [evidence](evidence/): M0 stdout, production keyless client, native runtime check, Web probe, deterministic model fixture and XCTest case results. Logs deliberately omit authentication cookies, launch tokens and API keys. A source checkout/build is not evidence of a paid-model response.

## Failures encountered and addressed

- The default npm cache was not writable in the tool sandbox. A task-local temporary cache fixed installation; no shared ownership changes were made.
- The shell's `node` resolved to a mise shim that failed under a restricted Process environment. Probes and app configuration use the real `process.execPath` binary instead.
- SwiftPM output on the external-volume build path hit an output-file-map permission error. Temporary scratch/cache directories made builds reproducible in this environment.
- Xcode's nested compiler macro sandbox failed with `sandbox_apply: Operation not permitted`. Build scripts apply the compiler's `-disable-sandbox` flag. DSH policy remains workspace-write + ask.
- Foundation read(upToCount:) waited for additional Pipe bytes and caused an initial handshake timeout. Available-byte reads fixed it; lifecycle and real-runtime tests exercise the corrected code.
- One test compared `/var/...` with Python's physical `/private/var/...` cwd. Canonical URL comparison fixed the test; no runtime behavior was changed to hide the difference.
- Web strict argument validation rejected `request`; installed metadata/source and the actual error identified the correct `_request` field. The default noninteractive operator also correctly rejected `$events`; explicit interactions=answer is required.
- Signing the bundle inside the tool sandbox failed. Local developer signing succeeded with authorized execution outside that sandbox; the app is still not notarized.
- Initial automated GUI attempts timed out during programmatic quit even though a real handshake/receipt had completed. The smoke runner was moved to application lifetime. After confirmed runtime teardown, the delegate returns terminateNow; active-runtime quits retain asynchronous shutdown. Programmatic termination is dispatched after the smoke task returns, avoiding a redundant nested async quit loop. It also waits for the real structured failure to reach native UI state before recording its result. Repeat runs additionally exposed duplicate Launch Services registrations and restored empty WindowGroup scenes; the final app uses a single Window with reopen behavior, disables the debug-dylib trampoline, and the smoke script rejects overlapping app instances. The normal final app passed the full interactive native flow, but unattended command-line repeats remained unreliable even after those changes. This outstanding test-runner issue is retained honestly; the earlier prototype pass is separate evidence, not a final automated pass.

## Remaining verification and next actions

1. Stabilize the unattended GUI smoke runner (final command-line launch timed out before its scene/result callback); keep the successful computer-use native user-flow test as separate evidence. Duplicate test app registrations were cleaned up, and ordinary final-app launch/connection/prompt/disconnect/quit were verified.
2. Supply a real model credential deliberately and validate interactive answers, tools and provider limits. This is optional/paid and was not run.
3. Resolve upstream SDK catalog/history/cancel/approval/dispose gaps before implementing broader desktop controls. Real approval replies and Shell-Agent sandbox behavior have not been exercised. PTY verification alone does not establish tool policy correctness.
4. Validate third-party Host plugins in a separate DSH home, including profile ownership, permissions, exported APIs and update matrices. Declared compatibility is not tested compatibility here.
5. Test macOS 14 on hardware/VM, Intel Node/native dependency closure, window restoration/VoiceOver comprehensively and background execution under real sustained Agent work. Keychain save/remove behavior and OS permission prompts need user-owned interactive credential testing.
6. Complete nested Developer ID signing, Node hardened-runtime entitlements, SBOM/notices, detached descendant cleanup, clean-Mac/quarantine and notarization before public distribution. The artifact is an ad-hoc development app only.
7. GitHub Actions is committed but has not been dispatched remotely. No claims are made about hosted CI success. No commits/PRs were pushed and no adjacent repositories were modified.
