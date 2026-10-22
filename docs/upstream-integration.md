# Upstream integration evidence

Investigated on 2026-10-22, Apple Silicon, macOS 15.8, Xcode 16.4 / Swift 6.1.2, Node 24.18.0 / npm 11.16.0. This document separates executed behavior from source inspection.

## Package and source boundary

The only direct production npm dependency is **`@deepseek-ai/dsh@0.2.1-rc.2`**. `runtime/package-lock.json` locks its entire published dependency graph and integrity hashes. The installed SDK protocol, server, client, base and SDK application packages are 0.2.1-rc.2. They are transitive production dependencies, not copied local build artifacts. The CLI entry is its declared bin `node_modules/@deepseek-ai/dsh/lib/bin.js`.

Registry metadata for unversioned `dsh-sdk-protocol` and `dsh-sdk-client` returned `latest=0.0.1-rc.1`, despite 0.2.1-rc.2 being published and required by dsh. Never independently use their unversioned tags. The DSH tarball integrity was `sha512-tvY+yhfKRifthbqPe/OK0AYxM5ZkvqfYq/jMYgJcEUxiRRL1Vwra3Ti5TB6AXgSWQdiPHYh/Vp6SJa9yHwMNuw==`; npm metadata did not provide a gitHead.

The local upstream checkout used for source inspection was commit `687f282e8625c6b8d11ff58211a90524be2e4317`. Source links below refer to that immutable reference; the installed package declarations and actual executions, rather than an assumption of identical build provenance, define the tested contract.

- [SDK request and notification types](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/sdk/protocol/src/types.ts)
- [SDK line transport](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/sdk/protocol/src/transport.ts)
- [SDK server dispatch, initialization, session ownership](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/sdk/server/src/server.ts)
- [SDK readiness and shutdown lifecycle](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/sdk/server/src/index.ts)
- [Full sdk composition](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/bundle/sdk-app/cordis.patch.yml), [base policy](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/bundle/base/cordis.patch.yml)
- [Standalone sdk-minimal composition and danger-full-access default](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/bundle/sdk-minimal/README.md)
- [Web auth and operator exchange](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/client/connection/src/browser-auth.ts), [trust fence](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/client/connection/src/api-request-trust.ts)
- [Web RPC HTTP envelope](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/client/connection/src/rpc-host.ts), [stream protocol](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/api/gateway/src/stream-protocol.ts)
- [Session controller: list, prompt, cancel, page, follow](https://github.com/deepseek-ai/deepseek-harness/blob/687f282e8625c6b8d11ff58211a90524be2e4317/packages/api/session-controller/src/index.ts), [Workspace controller](https://github.com/deepseek-ai/deepseek-harness/tree/687f282e8625c6b8d11ff58211a90524be2e4317/packages/api/workspace-controller), [Settings controller](https://github.com/deepseek-ai/deepseek-harness/tree/687f282e8625c6b8d11ff58211a90524be2e4317/packages/api/settings-controller)

The native default model is `deepseek-flash`, copied from the installed adapter’s declared advisory catalog. The original M0 standalone probe used `deepseek-chat`; a successful keyless handshake for either ID is not proof of provider-side model availability. Real account/model availability remains unverified.

## SDK: executed and inspected

SDK framing is UTF-8 newline-delimited JSON-RPC 2.0, **not LSP Content-Length framing**. Stdout belongs to protocol frames; stderr is separate. `initialize` accepts cwd/provider/model, validates the route and waits for Loader settlement before returning `serverInfo`. Its reported wire version is **0.0.1**, not the npm package version. There is no protocol capability negotiation or version compatibility guarantee to infer from it.

| Capability | Evidence / limitation |
| --- | --- |
| Ready / handshake | Executed from the independent Swift M0 program and production SDKClient. Exact server identity checked. |
| Create | No session/create method. Executed lazy creation using session/working-directory/get, with caller-generated UUID IDs. |
| Prompt | Executed session/prompt with contentBlocks; receives durable messageId, not a completed answer. |
| Observe | Executed session.event and session.status; preserves session-local sequence/order. SDK emits recorded log events. It does **not** subscribe to live assistant token deltas. |
| Agent state | Executed running → idle; turn/end.reason reports model failure independently of RPC success. |
| Directories | get/set executed, including multi-session directory isolation in tests. Set changes effective cwd without expanding original sandbox rights. |
| Resume | Executed clean shutdown → new process → session/resume against the same isolated DSH home. No historical messages are replayed. |
| Multiple sessions | Two actual M0 sessions; concurrent protocol requests and isolated state tested with a fixture peer. Truly simultaneous paid-model execution is not tested. |
| Tools | Real official DSH working_directory call/result executed with a deterministic local **test model**. Swift displays those actual events. Shell execution in the model loop is not validated; native PTY spawning is separately tested. |
| Shutdown | Executed protocol shutdown, process exit 0, restart and persistent session resume. EOF, signals and root disposal inspected upstream. |
| Cancel | Actual session/cancel request rejected with unknown-method (-32603). No single-session cancellation method in installed protocol. |
| Approvals | No SDK request/reply interface. Full sdk retains workspace-write + ask. Upstream user-approval resolves missing/throwing answerers to unavailable (fail closed). Human approval round-trip has not been run. |
| Catalog/history/settings | Absent from installed SDK. No private log-file reads or invented methods added. |
| Other notifications | Subagent notifications inspected/decoded; real subagent execution not verified. Unknown plugin events are shown as activity names in a partial live view, not reconstructed as durable history. |

M0's keyless prompt generated 21 real notifications and a missing-credential turn; session/wait still returned `{}`. Therefore successful RPC receipts/waits must **never** be equated with successful model output. The native decoder reports the structured turn error.

A separate test uses the official DSH runtime and a loopback deterministic Messages API fixture. DSH executes its own working_directory tool and produces a real assistant/message (`RIVETDECK_FIXTURE_OK`) through the production Swift transport. The fixture is only under Tests/Integration, uses a test-only key, and is neither a real DeepSeek answer nor an application fallback. No paid API credentials were used.

## Web Host: executed and inspected

`dsh web --host 127.0.0.1 --port 0 --no-open` boots the ordinary published Web profile. The printed launch URL contains a secret token; probes capture it in memory and never print it. `GET /connect?token=…&interactions=answer` exchanges it for a signed, authority-bound operator cookie. Default interactions=none can perform unary calls but the `$events` stream fails with `gateway/interactions-forbidden`. Browser cookies and independent API-operator cookies have different ownership.

Executed with **Swift URLSession**, without a Cordis client:

- `POST /api/session/list` with `{type:"client-request",rpcId,method:"session/list",payload:{args:{_request:{}}}}` returns a server-response with result.ok/value.
- A request without authentication returns 401. A cross-origin request with valid cookie returns 403.
- URLSessionWebSocketTask opens `/api/remote.mux`, sends `{type:"open",streamId,endpoint:"$events",payload:{args:{}}}`, and receives an `item` with `value.type=ready`. Explicit cancellation and socket teardown complete.

The `_request` spelling is generated from the actual method parameter. Sending `request` failed strict argument validation in the first probe. This is concrete upgrade coupling. The gateway validates generated invocation descriptors, Context/lookup identities, codecs and scoped Peer access; a non-TypeScript caller is feasible but must pin these contracts. Successful unary values with byte attachments use multipart metadata and byte parts, not always JSON. Streams have open/item/end/cancel, per-stream uplinks, cursors, errors and peer lifetimes. Closing the operator's WebSocket invalidated subsequent requests with the same operator cookie in an experiment; long-lived connection ownership must be designed before using this in production.

Source inspection found session cancel, cold page/follow history, catalog, workspace and settings RPCs, and scoped waterfall interaction replies through `$events/result`. Plugins can register generated Remote services and event sources. This kickoff does **not** claim to have run Web prompt/cancel/history recovery/approval/settings mutation or binary attachment transfer. The full browser Host bootstrap, rendered frontend and private Electron desktop Host are not application dependencies here.

## Transport comparison

| Dimension | A: direct Swift SDK | B: direct Swift Web | C: minimal Node adapter |
| --- | --- | --- | --- |
| Direct capabilities | Handshake, lazy sessions, resume, prompts, durable events, cwd, whole-runtime shutdown | Authenticated HTTP and event stream verified; source offers broader desktop API | Same capabilities as whichever public upstream surface it wraps; no new business semantics |
| Missing | Catalog/history/cancel/approval reply/settings/plugin RPC, token deltas, session disposal | Stable Swift schemas and codec/stream/recovery implementation; complete flows unverified | A SDK-only wrapper still lacks SDK methods; richer Web wrapper still needs lifecycle validation |
| Own protocol code | Small NDJSON client and event projection, implemented | Named-argument codecs, unary/multipart, mux, cursors, operator auth and interaction forwarding | Versioned IPC + protocol translation; requires public Connection/Gateway exports and generated contracts |
| Upgrade cost | Lowest measured surface, but limited capability and wire version not release identity | Highest coupling to generated contracts; exact parameter names matter | Can keep Swift stable, but moves evolving TS/Cordis dependencies into adapter |
| Plugins | Full sdk Host composition remains; native UI does not execute JS UI | Host Remote extensions callable if schemas are supported | Public Host extensions may be mapped; no arbitrary JS UI becomes SwiftUI |
| Sessions/concurrency | Multiple SDK-owned agents; per-session IDs/events; 16 visible prototype sessions; no per-session release | Catalog, retention/history/control exist upstream; peer ownership must remain live | Must preserve upstream IDs, original workspace policy and cancellation ownership |
| Performance/security | One Node process + native UI, no HTTP listener; bounded stdio, trusted local plugins | Loopback ephemeral port plus token/cookie/origin checks; streaming overhead and secret bootstrap | Same Node runtime plus small adapter work; stable local stdio preferred; no privilege bypass |
| Long-term decision | Chosen verified prototype transport, feature-limited | Feasible candidate, no production reimplementation of all Typert/Cordis | Deferred candidate if measured public bridge is simpler; not built or claimed verified |

## Plugins and profile ownership

Use upstream `dsh plugin --profile sdk add <published-package@exact-version>` in this application's DSH_HOME. The upstream manager uses pnpm, profile locks, compatibility checks, dependency manifests and bundle reconciliation. Installation is a deliberate maintenance operation, never app startup. This app does not take ownership of an Electron desktop profile, modify a plugin's owner, or silently enable packages.

Local compatibility analysis only (plugins were not installed/run in this kickoff):

- [multi-root-workspace](https://github.com/cherrchen/dsh-plugin-multi-root-workspace): Host filesystem/sandbox/scope/instructions/process fencing are distinct from its `/client` UI contribution. Its declared version matrix includes DSH 0.2.1-rc.2. Preserving Host logic does not prove it composes safely with sdk; validate profile ownership and permissions before enabling. A native roots editor would need an exposed API or upstream SDK extension.
- [dsh-plugin-git](https://github.com/cherrchen/dsh-plugin-git): Host APIs and Web conversation/sidebar/settings UI have separate dependencies. Declared 0.2.1-rc.2 support is not evidence of native UI support. SDK cannot call arbitrary git Remotes; native diff work is M3.
- Theme Studio's Web CSS tokens have no direct SwiftUI effect and are outside the prototype.

## Reproduction and remaining verification

See README commands and evidence files in `docs/evidence`. No real credential/model response, real approval response, paid concurrency, Shell-Agent sandbox behavior, plugin installation, or third-party Host plugin integration has been verified. Do not share this application's DSH home concurrently with CLI/Electron. Migration and shared-store concurrency need separate upstream validation.
