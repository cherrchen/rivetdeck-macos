# ADR 0001: Direct SDK stdio for the first native prototype

Status: accepted for M1/M2 on 2026-10-22; desktop feature completeness remains deferred.

Use Swift Foundation Process/Pipe and newline-delimited JSON-RPC against the published `@deepseek-ai/dsh@0.2.1-rc.2`, profile `sdk`. The installed protocol is `@deepseek-ai/dsh-sdk-protocol@0.2.1-rc.2`; its registry `latest` tag unexpectedly points to 0.0.1-rc.1, so do not install unversioned SDK packages.

Evidence: a standalone Swift executable initialized the official installed runtime, created two sessions through working-directory/get, submitted a prompt, received 21 real notifications, received an explicit unknown-method error for session/cancel, and shut down with exit 0. The keyless run is a credential failure, not a successful model answer. Web authenticated session/list also worked; its exact argument name is `_request`, not `request`.

A direct SDK client is the smallest verified boundary and opens no listening socket. It retains the full sdk profile's sandbox, approval, persistence, model, and Cordis services. We do not choose sdk-minimal: its default danger-full-access policy and omitted services are unsuitable defaults here.

SDK does not expose session list, historical events, title updates, per-session disposal, cancel, permission answering, settings or arbitrary plugin RPC. Live session events are durable log events, not token deltas. Display these restrictions. Missing approval answerers fail closed upstream. Never compensate by disabling permissions or reading/writing private session files.

A direct Web client could support these richer flows, but requires auth cookies, exact generated Typert argument contracts, multiplexed streams, cursor recovery, binary codecs and interaction-peer lifetimes. Do not reproduce Cordis/Typert in Swift in this kickoff.

A Node adapter speaking the public Web Connection/Gateway clients is a possible later seam for richer desktop controls, not yet required. Before adopting one, validate public exports, explicit authentication and cancellation semantics, pin the package set, and cap the adapter at 500 handwritten protocol lines (excluding tests/generated models); no agent logic, private import paths, second UI/client runtime or permission bypass. A thin adapter around SDK alone cannot supply missing methods.

Revisit this ADR when official SDK gains needed methods or a separately validated public Web adapter has smaller maintenance cost than the missing capabilities. No claim of complete third-party Client UI compatibility is made.
