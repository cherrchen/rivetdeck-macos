#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Usage: app-smoke.sh APP_PATH NODE_PATH [RUNTIME_ROOT]}"
node_binary="${2:?Supply a real Node.js executable}"
if /usr/bin/pgrep -x RivetdeckNative >/dev/null; then
  echo "Quit existing Rivetdeck Native instances before running the desktop smoke test." >&2
  exit 1
fi
probe_root="$(mktemp -d "${TMPDIR:-/tmp}/rivetdeck-app-smoke.XXXXXX")"
result="$probe_root/result.json"
runtime_root="${3:-$PWD/runtime}"
watchdog_pid=""
trap 'if [[ -n "$watchdog_pid" ]]; then kill "$watchdog_pid" 2>/dev/null || true; fi; rm -rf "$probe_root"' EXIT
# Launch the actual AppKit executable with deterministic test arguments.
"$app/Contents/MacOS/RivetdeckNative" --smoke-test "$result" "$node_binary" "$runtime_root" "$probe_root/dsh" "$probe_root" quit &
launcher_pid=$!
# Bounded watchdog only; result creation and SDK initialize are the readiness signals.
(
  sleep 55 &
  timer_pid=$!
  trap 'kill "$timer_pid" 2>/dev/null || true; exit 0' TERM
  wait "$timer_pid"
  if [[ -f "$result.pid" ]]; then
    read -r native_pid < "$result.pid" || true
    if [[ "${native_pid:-}" =~ ^[0-9]+$ ]]; then kill "$native_pid" 2>/dev/null || true; fi
  else
    # If a scene never appeared, identify only this test's unique launch arguments.
    /usr/bin/pgrep -f -- "--smoke-test $result " | while read -r native_pid; do
      kill "$native_pid" 2>/dev/null || true
    done
  fi
  kill "$launcher_pid" 2>/dev/null || true
) &
watchdog_pid=$!
set +e
wait "$launcher_pid"
launch_status=$?
set -e
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
watchdog_pid=""
python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as file: result = json.load(file)
print(json.dumps(result, indent=2))
assert result.get('nativeWindowCount', 0) > 0
assert result.get('handshake') is True
assert result.get('receipt')
assert not result.get('mock')
assert not result.get('error')
assert result.get('missingCredentialRendered') is True
assert result.get('liveRowCount', 0) > 0
PY

if [[ "$launch_status" -ne 0 ]]; then echo "Native app did not exit cleanly: $launch_status" >&2; exit "$launch_status"; fi
