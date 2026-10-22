// Read-only Web transport feasibility probe. Does not open a browser or print credentials.
import { spawn, spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';
import { resolve } from 'node:path';
process.chdir(fileURLToPath(new URL('../..', import.meta.url)));
const home = await mkdtemp(resolve(tmpdir(), 'rivetdeck-web-'));
const child = spawn(process.execPath, ['runtime/node_modules/@deepseek-ai/dsh/lib/bin.js', 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'], {
  env: { PATH: '/usr/bin:/bin:/usr/sbin:/sbin', HOME: home, DSH_HOME: home }, stdio: ['pipe', 'pipe', 'pipe'],
});
let output = '', errors = '';
child.stderr.on('data', chunk => { errors = (errors + chunk).slice(-16384); });
const deadline = setTimeout(() => { child.kill('SIGTERM'); }, 45000);
try {
 const url = await new Promise((accept, reject) => {
  child.stdout.on('data', chunk => {
   output = (output + chunk).slice(-65536);
   const match = output.match(/dsh web: (http:\/\/127\.0\.0\.1:\d+\/\?token=[^\s]+)/);
   if (match) accept(new URL(match[1]));
  });
  child.once('exit', code => reject(new Error(`Host exited ${code}: ${errors.replace(/token=[^\s]+/g, 'token=[redacted]')}`)));
 });
 const origin = url.origin;
 const body = JSON.stringify({ type: 'client-request', rpcId: 'probe-list', method: 'session/list', payload: { args: { _request: {} } } });
 const unauthorized = await fetch(origin + '/api/session/list', { method: 'POST', headers: { 'content-type': 'application/json' }, body });
 console.log('Unauthenticated list HTTP', unauthorized.status);
 const connect = new URL('/connect', url); connect.search = url.search; connect.searchParams.set('interactions', 'answer');
 const exchange = await fetch(connect, { redirect: 'manual' });
 const cookie = exchange.headers.get('set-cookie')?.split(';')[0];
 if (exchange.status !== 302 || !cookie) throw new Error('Token exchange failed');
 console.log('Launch token exchange HTTP 302, signed cookie received (redacted)');
 const result = await fetch(origin + '/api/session/list', { method: 'POST', headers: { 'content-type': 'application/json', cookie }, body });
 const value = await result.json();
 console.log('Authenticated list HTTP', result.status, JSON.stringify(value));
 if (!value.result?.ok) throw new Error('Session list failed');
 const badOrigin = await fetch(origin + '/api/session/list', { method: 'POST', headers: { 'content-type': 'application/json', cookie, origin: 'https://example.invalid' }, body });
 console.log('Cross-origin list HTTP', badOrigin.status);
 if (unauthorized.status !== 401 || badOrigin.status !== 403) throw new Error('Trust fence failed');
 const swiftBinary = resolve(tmpdir(), 'rivetdeck-swift-web-probe');
 const compile = spawnSync('/usr/bin/xcrun', ['swiftc', '-parse-as-library', '-module-cache-path', resolve(tmpdir(), 'rivetdeck-web-module-cache'), 'runtime/scripts/web-probe.swift', '-o', swiftBinary], { encoding: 'utf8' });
 if (compile.status !== 0) throw new Error('Swift probe compilation failed: ' + compile.stderr);
 const swift = spawn(swiftBinary, [], { stdio: ['pipe', 'pipe', 'pipe'] });
 swift.stdout.pipe(process.stdout);
 let swiftErrors = ''; swift.stderr.on('data', data => { swiftErrors += data; });
 swift.stdin.end(JSON.stringify({ origin, cookie }));
 const [swiftCode] = await once(swift, 'exit');
 if (swiftCode !== 0) throw new Error('Swift Web probe failed: ' + swiftErrors.slice(0, 2000));
} finally {
 clearTimeout(deadline);
 const exited = once(child, 'exit');
 child.kill('SIGTERM');
 const kill = setTimeout(() => child.kill('SIGKILL'), 8000);
 await exited; clearTimeout(kill);
 await rm(home, { recursive: true, force: true });
 console.log('Web Host stopped');
}
