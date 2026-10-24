# Rivetdeck Native

An independent macOS client for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness), built with SwiftUI and AppKit. The native UI talks directly to the official npm runtime over JSON-RPC stdio. Agent, Session, Tool, Model, persistence, permissions and Cordis Host plugins remain owned by DSH.

This repository is not a DSH fork and contains no vendored DSH monorepo, submodule, Electron UI, or WebView chat shell. Existing [Rivetdeck](https://github.com/cherrchen/Rivetdeck) was used only as an architectural reference.

## Current status

M0 and M1 are implemented; M2 has a real runtime connection and a tested minimal conversation path. The app provides a native window, workspace picker/recent paths, session sidebar, live conversation/activity, prompt composer, status/errors, settings and Keychain API-key storage. It creates sessions, resumes a known Session ID, and supervises the official sdk Profile. Closing a window keeps the runtime alive; Quit performs bounded shutdown.

**Prototype limits:** one workspace per runtime; 16 live UI sessions; no SDK session catalog, historical transcript replay, per-session cancel/disposal, token deltas, arbitrary plugin RPC or approval replies. Full sdk retains workspace-write + ask; approvals without an answerer fail closed. Disconnect stops the whole runtime. Live UI rows are bounded and not persisted by Swift. Reconnect clears them; DSH retains its own data. Model configuration changes require reconnect.

Real official-runtime tests cover handshake, session creation, directory operations, prompt receipts, events, missing-credential errors, graceful shutdown, restart and persistence resume. A test-only local model drives a real DSH tool call/result and assistant message. **No real paid-model response has been verified.** Tests never substitute a mock runtime for a reported real connection. See [integration evidence](docs/upstream-integration.md) and [verification results](docs/verification.md).

## Requirements

- macOS 14+; Apple Silicon is the tested target (macOS 15.8).
- Xcode 16+ / Swift 6; tested with Xcode 16.4 / Swift 6.1.2.
- A real Node.js 24+ executable, tested with Node 24.18.0 / npm 11.16.0. Version-manager shims may fail under Process; use `node -p 'process.execPath'` to find the real executable.
- Registry access for the first locked dependency install. No adjacent source checkout or pnpm is required for normal startup.

## Open and run in Xcode

```sh
npm ci --prefix runtime
npm --prefix runtime run verify
open RivetdeckNative.xcodeproj
```

Select the shared **RivetdeckNative** scheme and **My Mac**, then Run. The launch scheme uses the repository as its working directory. No external Swift packages or project generator are needed. `Package.swift` can also be opened in Xcode; the `.xcodeproj` gives a proper macOS `.app` target. After adding/removing Swift files, run `python3 scripts/generate-project.py` to update its source membership.

In the app:

1. Choose **Open Workspace…** (Cmd+O). First run requires an explicit directory selection.
2. Open **Settings…** (Cmd+,). Check Node executable and the `runtime` directory. Default DSH home is `~/Library/Application Support/Rivetdeck Native/DSH`, independent from CLI/Electron. Do not select an actively used Electron/CLI home.
3. Set the provider/model route if needed; defaults are `deepseek-official` / `deepseek-flash`. Store your own DeepSeek key using **Save to Keychain**, or configure credentials in this isolated DSH home using upstream-supported tools. The app does not automatically inherit shell API keys. The model ID must be supported by your provider configuration.
4. Click **Connect** in the sidebar footer or hero card. Connected means the actual SDK handshake succeeded. Send a prompt with Cmd+Return (Return inserts a newline) and inspect real DSH messages, folded per-turn tool steps and structured turn errors.

A missing key still permits handshake/session testing and produces a real `MISSING_CREDENTIAL` turn error. A prompt receipt or successful `session/wait` alone does not mean the model answered. Use File → Resume Session by ID to reopen a known DSH session; copy IDs from a sidebar context menu. SDK resume does not replay old messages.

## Command-line verification

```sh
# Pure protocol/process tests. Official-runtime test skips unless explicitly configured.
scripts/swift-check.sh

# Include real DSH, in a disposable home, with no paid-model credentials.
RIVETDECK_INTEGRATION_NODE="$(node -p 'process.execPath')" \
RIVETDECK_RUNTIME_ROOT="$PWD/runtime" scripts/swift-check.sh

# Production Swift client → official runtime, restart and resume. No API key by default.
/tmp/rivetdeck-native-build/debug/dsh-probe \
  "$(node -p 'process.execPath')" "$PWD/runtime" "$PWD/.runtime-test/manual"

# Real DSH and Swift, deterministic test-only local model and real working_directory tool.
node Tests/Integration/model-fixture.mjs /tmp/rivetdeck-native-build/debug/dsh-probe

# Separate feasibility test: authenticated HTTP + Swift URLSession WebSocket.
node runtime/scripts/web-probe.mjs
```

`swift test` also works in a normal unrestricted terminal. `swift-check.sh` redirects caches/builds into temporary storage and disables the compiler's nested macro sandbox for restricted build environments; DSH permissions remain unchanged. You can override `RIVETDECK_BUILD_DIR`. The final normal app’s full native user flow was verified interactively. The unattended GUI smoke script remains timing-sensitive in this automation environment and its latest run timed out; it is not counted as a final automated pass. The tests include JSON byte framing/UTF-8/limits, event projection, timeout, malformed stdout, unexpected exit/disconnect, concurrent request routing, session isolation and error redaction. Fixture peers are confined to Tests. GitHub Actions runs the macOS builds and keyless integration checks; the hosted workflow has not yet been run by this kickoff.

For keyless manual probes, use a fresh DSH home and a disposable workspace without credential configuration or `.env`; upstream-configured credentials still take precedence.

To deliberately test a real model, add `--live` to `dsh-probe` and explicitly export `DEEPSEEK_API_KEY` in your own terminal. This optional test may incur provider charges and is not run by CI. Do not put credentials into command arguments, files, screenshots or logs.

## Build a developer App

```sh
# Build .artifacts/RivetdeckNative.app using externally configured Node/runtime.
scripts/build-app.sh

# Or include Node and the complete verified official runtime for standalone startup.
# A successful build and signing replaces the generated App in .artifacts.
scripts/build-app.sh --bundle-runtime "$(node -p 'process.execPath')"

# Debug App only: real native window + official runtime, no credentials.
# Quit existing instances first; a logged-in desktop is required.
scripts/app-smoke.sh "$PWD/.artifacts/RivetdeckNative.app" "$(node -p 'process.execPath')"
```

Both build modes use the same launch/handshake code. Bundled startup never installs packages and does not require npm/pnpm. The complete development bundle is about 1 GiB; most is the official runtime dependency closure, not the native UI. Offline startup is supported; a remote model still needs provider connectivity. Developer bundles are ad-hoc signed, **not Developer ID signed or notarized**. Intel runtime, hardened Node entitlements, third-party release notices and clean-Mac quarantine validation remain release gates. See [runtime packaging](docs/runtime-packaging.md).

## Diagnostics and architecture

Toggle the right-hand inspector (⌥⌘I) for session metadata and bounded connection logs; the Runtime menu's Diagnostics item opens it directly. Raw stderr is drained without displaying arbitrary plugin output or secrets; exit status and byte counts are reported. Structured model errors appear in the conversation. Upstream startup diagnostics, when produced, live in this app's DSH home; review them privately. There is no automatic crash-restart or prompt resubmission.

- [Upstream integration and A/B/C comparison](docs/upstream-integration.md)
- [Architecture, ownership, concurrency, security and M3 plan](docs/architecture.md)
- [Transport decision](docs/adr/0001-dsh-transport.md)
- [Runtime installation, native libraries and release plan](docs/runtime-packaging.md)
- [Executed verification and remaining work](docs/verification.md)

The existing repository GPL-3.0 license is retained. DSH and bundled dependencies keep their respective licenses. Rivetdeck Native is an independent client, not an official DeepSeek application.
