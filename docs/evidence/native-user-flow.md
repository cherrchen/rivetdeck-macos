# Native user-flow verification — 2026-10-22

Verified through the actual macOS application's accessibility tree and screenshot, using the final single SwiftUI Window scene and bundled official runtime. This was a normal app launch, not a mock/Preview or the debug smoke entry point.

1. Opened `.artifacts/RivetdeckNative.app` and observed the native split window, sidebar, system toolbar, standard controls and empty workspace state.
2. Used its NSOpenPanel, including the system Go to Folder sheet, to select `.runtime-test/manual-gui` in this repository.
3. Opened the native Settings window. It showed the bundle's `Resources/node/bin/node`, `Resources/runtime`, provider `deepseek-official`, and model `deepseek-flash`. The API-key field was empty; no key was saved or removed.
4. Selected the test-only DSH home `.runtime-test/manual-gui/home`, then clicked Connect Runtime. The actual UI became Connected and displayed a real New Session plus `permission/preset`, `sandbox/mode` and `approval/policy` events.
5. Entered and sent `Native UI integration check: reply briefly.` in the native TextEditor. The real user message, injected workspace/runtime context and DSH step activity appeared. The Agent finished idle, and the conversation/error banner displayed `Agent failed (MISSING_CREDENTIAL). Check DSH configuration and credentials.`
6. Clicked Disconnect Runtime. The actual UI became Stopped and session creation became disabled.
7. Restored the normal independent home `~/Library/Application Support/Rivetdeck Native/DSH`, then quit the native app normally.

The context reported workspace-write plus ask, and explicitly stated approval without an answerer fails closed. No permissions were disabled. No paid-model answer is claimed. The separate model-fixture integration test verifies real assistant/tool output through the production Swift client with a deterministic test-only provider.

Repeated desktop automation had also exposed duplicate Launch Services registrations from temporary Xcode products and stale test instances. Those task-created registrations/instances were cleaned up. The project uses a single native Window scene with explicit reopen behavior and a conventional executable instead of Xcode's debug-dylib trampoline.
