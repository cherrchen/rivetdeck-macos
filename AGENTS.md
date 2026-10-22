# Rivetdeck Native

- `Sources/RivetdeckNative` owns SwiftUI/AppKit and UI preferences.
- `Sources/RivetdeckCore` owns process supervision, SDK wire decoding, and the typed client boundary. Keep wire JSON out of UI code.
- `runtime` owns exact npm versions, lockfile, probes, and packaging checks. Never vendor DSH source, use monorepo workspace dependencies, modify installed packages, or reimplement Agent/Session/Tool business logic.
- Read installed protocol declarations before adding methods. SDK limitations must remain visible in docs and UI. Mocks belong only in tests/Previews.
- Validate Swift changes with `swift test` and the Xcode build in README. Validate runtime changes with `npm ci --prefix runtime`, `npm --prefix runtime run verify`, and the keyless integration probe. Never use paid model credentials in default tests.
- Keep README, ADRs, and implementation consistent. Record failures and unverified behavior honestly; never invent execution or test results.
