# Architecture

Rivetdeck Native is an independent macOS 14+ SwiftUI application with an AppKit lifecycle. It uses Observation, Swift Concurrency, Foundation and Security, without third-party Swift dependencies, Chromium, or WebView. Xcode 16 / Swift 6 is the baseline. It does not depend on any adjacent repository. [ADR 0001](adr/0001-dsh-transport.md) records the verified transport choice.

## Concrete ownership

```text
RivetdeckNative.xcodeproj       native macOS application; shared launch scheme
Package.swift                  same app, reusable core, CLI probe and XCTest suite
Sources/RivetdeckNative/        AppKit lifecycle, SwiftUI shell, observable UI state, Keychain
Sources/RivetdeckCore/          client protocol, SDK actor, byte framing, process supervision
Sources/DSHProbe/               executable using the production client
runtime/                       exact official npm package + lock, independent probes/checks
Tests/                         protocol/process fixtures and test-only local model
scripts/                       build, native app smoke, deterministic project generation
.github/workflows/ci.yml        macOS build, unit, official runtime and model-fixture checks
```

The Xcode app compiles the same core files directly; SwiftPM exposes them as RivetdeckCore. App sources conditionally import that module under SWIFT_PACKAGE. `scripts/generate-project.py` maintains explicit source membership with no XcodeGen dependency. It is only needed after adding/removing Swift files.

## Process and connection lifecycle

AppModel is MainActor + Observable. It owns one application-lifetime DSHClient, so closing a window does not cancel running agents. NavigationSplitView, system toolbar/menus, native sheets, file panels, TextEditor, context menus and standard window controls provide the UI. Cmd+N creates a session; Cmd+O opens a workspace while disconnected; Cmd+Return sends. A single SwiftUI Window scene supplies system restoration; the AppKit delegate raises it on reopen. A ProcessInfo user-initiated activity covers handshake and live running Agent IDs (including observed subagents), preventing App Nap during work while still allowing idle system sleep. Last-window close keeps the app alive; Quit awaits teardown via NSApplication.TerminateReply.terminateLater when needed; an already stopped runtime permits terminateNow.

SDKClient is an actor. It validates runtime/workspace paths and exact supported dsh/protocol package versions, starts the declared dsh bin through an explicit Node URL, sends initialize, checks identity and publishes connected only after the response. No timer/sleep is used for readiness. There is no automatic restart: user reconnect is explicit to avoid rerunning or duplicating agent work. Reconnect clears live UI projections and starts a new generation; opening persisted work requires an explicit Session ID.

ProcessSupervisor has separate serial Pipe read/write workers and drains stderr without retaining its raw content. `availableData` is intentionally used: Foundation read(upToCount:) waited for more bytes in the initial experiment and caused handshake timeout. Per-generation ordered output feeds the actor, which correlates requests and handles events serially. Process exit is emitted only after stdout has drained. Stale generations cannot update the replacement connection.

Disconnect sends shutdown (5-second response deadline), allows 5 seconds for natural process exit, then SIGTERM and a further 2 seconds before SIGKILL. Foundation's owned process group is used for forced cleanup only when getpgid(child)==child; otherwise the direct child is killed. DSH root disposal owns its subprocesses. Detached/reparented plugin processes outside that group are not guaranteed to be reclaimed; hostile plugins are trusted code, and exhaustive descendant cleanup remains a release-hardening item. Client deinitialization force-stops its owned process as a last resort. Compiler `-disable-sandbox` in build scripts only addresses nested compiler macro restrictions; it does not change DSH sandbox policy.

## Data and resource bounds

DSH owns sessions, headers, attachments, permissions, configuration and credential references. The client neither reads private session logs nor writes an alternate session format. Resume does not imply history replay. Unknown event names are activity summaries in a partial live presentation, not a complete log reconstruction.

UserDefaults stores UI preferences and at most 12 recent workspace paths. API keys use Keychain; they are passed only to the child environment, never preferences or diagnostics. DSH also supports its own stored credentials; its precedence remains upstream-owned. Default DSH home is `~/Library/Application Support/Rivetdeck Native/DSH`, distinct from CLI/Electron. A first-run user must select a workspace; Finder's default cwd `/` is not accepted implicitly.

Bounds: 8 MiB wire frame, 128 queued output chunks (a Pipe read returns available bytes), 64 pending RPCs, 512 queued events per observer, 128 session sequence trackers, 16 visible sessions, 200 live rows per session, 32,768 characters per message, 100 metadata diagnostic lines, 262,144 UTF-8 bytes per prompt. Queue overflow terminates the affected stream and disconnects rather than silently losing history. A stalled observer must reconnect; SDK provides no replay. UI rows explicitly report truncation/eviction. Subscriptions cancel and release via AsyncStream termination; per-session retained buffers are cleared on reconnect. Upstream SDK agents cannot be individually disposed, so complete Host resource release requires disconnect.

Each pending request has a deadline and cancellation cleanup. Cancelling a Swift waiter abandons that local request; it does not invent upstream agent cancellation. Agent failure is derived from turn/end.reason, not prompt/wait RPC success. Unexpected EOF, malformed frames, process exit and transport failures reject pending requests and update UI state. Last-seen sequences are per session, and backwards/duplicate delivery fails the connection.

## Security boundary

The app is deliberately not App-Sandboxed: the local Agent needs user-authorized workspace files and tool processes. DSH's full sdk Profile retains workspace-write + ask by default. Session cwd changes do not expand original permissions. Without an SDK approval answerer, approval fails closed. No always-allow mode, permission override or automatic retry is added.

Environment is built from an allowlist: Node/tool PATH, real HOME, isolated DSH_HOME, fixed shell/locale, temporary directory, explicit model credential and optional endpoint. NODE_OPTIONS, shell bootstrap scripts, ambient API keys and DSH_PERMISSION_MODE are not inherited. A workspace's trusted DSH configuration/.env and installed plugins can still affect the Host; untrusted repository code is not isolated merely by using native UI. Do not select a workspace you do not trust.

No production HTTP listener or remote page-to-local bridge exists. Stdout framing is strict and stderr is separate. Raw stderr is counted and discarded to avoid leaking arbitrary plugin secrets; RPC errors redact the explicit key and token patterns. UI diagnostics retain metadata only. Provider error bodies are not displayed; turn failures show a structured code. Message content belongs to the conversation and may naturally contain sensitive user data. Crash diagnosis trades raw plugin detail for safe UI reports; upstream private diagnostics in the isolated DSH home remain upstream-owned.

## M3 design plan (not implemented)

1. Resolve cancel/approval/history/catalog before broadening the desktop surface. Seek upstream SDK additions or validate a <=500-line public Web adapter, with contract tests for peer lifetimes and permission semantics. No private imports or second Cordis client application.
2. Multi-workspace ownership: explicit per-workspace runtime boundaries or verified Host registry support; do not widen a live session's sandbox implicitly. Validate the multi-root plugin independently.
3. Native Git diff using file snapshots and an exposed Host plugin API; preserve upstream tool/permission ownership. Evaluate a system-backed PTY terminal separately before considering SwiftTerm. No terminal implementation in this kickoff.
4. Drag/drop and attachments through upstream admission rules; notifications only after permission and meaningful completion. Native approval UI only when an actual reply contract exists.
5. Plugin manager: profile ownership, exact package versions, pnpm distribution, compatibility checks and install rollback; JS Client UI needs native implementations or a separately isolated optional WebView surface.
6. Runtime Manager: provenance, package-set checks, upgrade rehearsal, recovery UI, checkpoint/restore only through supported upstream contracts. Finish memory/CPU/energy profiling and detached-process cleanup tests.
7. Release: reproducible Node acquisition, third-party notices/SBOM, architecture-specific native closures, nested Developer ID signing, hardened-runtime entitlements, quarantine testing and notarization. Auto-update and store distribution remain later work.
