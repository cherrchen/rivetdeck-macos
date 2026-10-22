# Official DSH runtime module

This folder is an independent npm project. It uses only the published `@deepseek-ai/dsh@0.2.1-rc.2` package, with a committed package-lock. No monorepo workspace setup, adjacent checkout, fork or copied build output is required.

Use Node 24.18.0 / npm 11.16.0:

```sh
npm ci --prefix runtime
npm --prefix runtime run verify
```

If this machine's normal npm cache is unwritable, use `npm --cache /tmp/rivetdeck-npm-cache ci --prefix runtime`; do not change ownership of a shared cache just to build this project.

The Swift client directly launches the real Node executable with this package's declared dsh bin and `--profile sdk`. There is no production Node adapter and no app-start install. sdk-minimal is intentionally not used: it omits full policy/services and defaults to danger-full-access.

M0 standalone probe (run from repository root):

```sh
mkdir -p /tmp/rivetdeck-poc
swiftc -module-cache-path /tmp/rivetdeck-poc/cache runtime/scripts/stdio-poc.swift -o /tmp/rivetdeck-poc/stdio-poc
/tmp/rivetdeck-poc/stdio-poc "$(node -p 'process.execPath')"
node runtime/scripts/web-probe.mjs
```

The stdio probe uses `.runtime-test/poc` and no API credentials. It tests the real protocol including an expected unknown-method error for cancel. The Web probe starts a loopback ephemeral-port Host, exchanges its token without logging it, checks authentication/origin fences and compiles a small Swift URLSession HTTP/WebSocket probe. It cleans up its temporary Host home. The Web transport is research tooling, not the app's production transport.

Production-client probe, tests and App build instructions are in the root README. See `docs/runtime-packaging.md` for native dependencies, offline startup, bundled Node, plugin/pnpm ownership, signing and release limitations.
