import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const runtime = fileURLToPath(new URL('..', import.meta.url));
const require = createRequire(new URL('../package.json', import.meta.url));
assert(Number(process.versions.node.split('.')[0]) >= 24, 'Node.js 24+ required');
const manifest = JSON.parse(await readFile(new URL('../package.json', import.meta.url)));
assert.equal(manifest.dependencies['@deepseek-ai/dsh'], '0.2.1-rc.2');
for (const name of ['dsh', 'dsh-sdk-protocol', 'dsh-sdk-jsonrpc-server', 'dsh-sdk-app']) {
 const pkg = JSON.parse(await readFile(resolve(runtime, 'node_modules/@deepseek-ai', name, 'package.json')));
 assert.equal(pkg.version, '0.2.1-rc.2');
 console.log(`${pkg.name}@${pkg.version}`);
}
const subprocessRequire = createRequire(require.resolve('@deepseek-ai/dsh-subprocess-local'));
subprocessRequire('koffi');
const pty = subprocessRequire('node-pty');
const terminal = pty.spawn('/bin/sh', ['-c', 'printf RIVETDECK_PTY_OK'], { name: 'xterm', cols: 80, rows: 24, cwd: runtime, env: { PATH: '/usr/bin:/bin' } });
const result = await new Promise((accept, reject) => {
 let text = '';
 const timer = setTimeout(() => { terminal.kill(); reject(new Error('PTY timed out')); }, 5000);
 terminal.onData(chunk => { text += chunk; });
 terminal.onExit(({ exitCode }) => { clearTimeout(timer); accept({ text, exitCode }); });
});
assert.equal(result.exitCode, 0); assert.match(result.text, /RIVETDECK_PTY_OK/);
await access(resolve(runtime, 'node_modules/@deepseek-ai/dsh/lib/bin.js'), constants.R_OK);
console.log('PASS: official package closure, koffi load, native PTY spawn/exit. No model API called.');
