# Test-only protocol peer. Never used by the application or real-runtime probes.
import json, os, sys, time
mode_file = os.path.join(os.getcwd(), 'fixture-mode')
mode = open(mode_file).read().strip() if os.path.exists(mode_file) else 'normal'
cwds = {}
def send(value):
    print(json.dumps(value), flush=True)
for line in sys.stdin:
    frame = json.loads(line)
    method, params = frame['method'], frame.get('params', {})
    result = {}
    if method == 'initialize':
        if mode == 'timeout': continue
        if mode == 'invalid':
            print('not protocol stdout', flush=True)
            continue
        result = {'serverInfo': {'name': 'deepseek-harness-sdk-runtime', 'version': 'fixture'}}
    elif method == 'session/working-directory/get':
        result = {'cwd': cwds.setdefault(params['sessionId'], os.getcwd())}
    elif method == 'session/working-directory/set':
        cwds[params['sessionId']] = params['path']
        result = {'cwd': params['path']}
    elif method == 'session/prompt':
        if mode == 'crash': os._exit(7)
        if mode == 'disconnect':
            os.close(1)
            time.sleep(10)
            break
        session = params['sessionId']
        send({'jsonrpc': '2.0', 'method': 'session.status', 'params': {'sessionId': session, 'status': 'running'}})
        send({'jsonrpc': '2.0', 'method': 'session.event', 'params': {'sessionId': session, 'event': {'type': 'user/message', 'seq': 1, 'data': {'id': session+'-message', 'role': 'user', 'content': params['contentBlocks']}}}})
        send({'jsonrpc': '2.0', 'method': 'session.status', 'params': {'sessionId': session, 'status': 'idle'}})
        result = {'messageId': session+'-message'}
    elif method == 'session/resume':
        send({'jsonrpc': '2.0', 'id': frame['id'], 'error': {'code': -32603, 'message': 'unknown session; token=fixture-secret'}})
        continue
    send({'jsonrpc': '2.0', 'id': frame['id'], 'result': result})
    if method == 'shutdown': break
