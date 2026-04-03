#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sshtunnelmanager-regression.XXXXXX")"
SSHD_DIR="$WORK_DIR/sshd"
HARNESS_DIR="$WORK_DIR/harness"

cleanup() {
  if [[ -n "${CRASH_PID:-}" ]]; then
    kill -9 "$CRASH_PID" 2>/dev/null || true
  fi

  if [[ -n "${SSHD_PID:-}" ]]; then
    kill "$SSHD_PID" 2>/dev/null || true
    wait "$SSHD_PID" 2>/dev/null || true
  fi

  if [[ -n "${LOCAL_FORWARD_PORT:-}" ]]; then
    pkill -f "${LOCAL_FORWARD_PORT}:127.0.0.1:22" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

require_tool swiftc
require_tool ssh
require_tool ssh-keygen
require_tool sshd
require_tool pgrep
require_tool python3

pick_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

SSHD_PORT="$(pick_free_port)"
LOCAL_FORWARD_PORT="$(pick_free_port)"

mkdir -p "$SSHD_DIR" "$HARNESS_DIR"

ssh-keygen -q -t ed25519 -N '' -f "$SSHD_DIR/test_key" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$SSHD_DIR/host_key" >/dev/null
cp "$SSHD_DIR/test_key.pub" "$SSHD_DIR/authorized_keys"

cat > "$SSHD_DIR/sshd_config" <<EOF
Port $SSHD_PORT
ListenAddress 127.0.0.1
HostKey $SSHD_DIR/host_key
PidFile $SSHD_DIR/sshd.pid
AuthorizedKeysFile $SSHD_DIR/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
PermitRootLogin no
AllowUsers $USER
StrictModes no
PrintMotd no
LogLevel ERROR
Subsystem sftp internal-sftp
EOF

/usr/sbin/sshd -D -f "$SSHD_DIR/sshd_config" -E "$SSHD_DIR/sshd.log" &
SSHD_PID=$!
sleep 1

ssh \
  -p "$SSHD_PORT" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "$SSHD_DIR/test_key" \
  "$USER@127.0.0.1" \
  true >/dev/null

cat > "$HARNESS_DIR/main.swift" <<'EOF'
import Foundation
import Combine

let mode = CommandLine.arguments[1]
let keyPath = CommandLine.arguments[2]
let sshPort = Int(CommandLine.arguments[3])!
let localPort = Int(CommandLine.arguments[4])!

let config = TunnelConfiguration(
    name: "Regression Tunnel",
    sshUser: NSUserName(),
    sshHost: "127.0.0.1",
    sshPort: sshPort,
    localPort: localPort,
    remoteHost: "127.0.0.1",
    remotePort: 22,
    sshKeyPath: keyPath,
    autoReconnect: false,
    serverAliveInterval: 15
)

let manager = TunnelManager()
manager.tunnels.removeAll()
let tunnel = TunnelState(configuration: config)
manager.tunnels = [tunnel]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    Foundation.exit(1)
}

switch manager.connect(tunnel) {
case .success:
    break
case .queuedWhileStopping:
    fail("Tunnel connect was unexpectedly queued while stopping in a fresh harness run")
case .portConflict(let existingTunnel):
    fail("Tunnel failed to connect: local port conflict with \(existingTunnel.configuration.displayName)")
}

let connectionDeadline = Date().addingTimeInterval(10)
while tunnel.status != .connected && Date() < connectionDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}

guard tunnel.status == .connected else {
    let lastLog = tunnel.logs.last?.message ?? "No tunnel logs captured."
    fail("Tunnel failed to reach connected state before timeout. Final status: \(tunnel.status.rawValue). Last log: \(lastLog)")
}

FileHandle.standardOutput.write(Data("CONNECTED\n".utf8))

switch mode {
case "disconnect":
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    var didDisconnect = false
    manager.disconnect(tunnel) {
        didDisconnect = true
    }
    let disconnectDeadline = Date().addingTimeInterval(10)
    while !didDisconnect && Date() < disconnectDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    guard didDisconnect else {
        fail("Tunnel did not finish disconnecting before timeout")
    }
case "crash":
    RunLoop.main.run(until: Date().addingTimeInterval(30))
default:
    fatalError("Unknown mode: \(mode)")
}
EOF

swiftc \
  -o "$HARNESS_DIR/harness" \
  "$ROOT_DIR/SSHTunnelManager/Models/TunnelConfiguration.swift" \
  "$ROOT_DIR/SSHTunnelManager/Models/TunnelState.swift" \
  "$ROOT_DIR/SSHTunnelManager/Services/SSHTunnelProcess.swift" \
  "$ROOT_DIR/SSHTunnelManager/Services/TunnelManager.swift" \
  "$HARNESS_DIR/main.swift"

assert_no_residual_processes() {
  if pgrep -f "${LOCAL_FORWARD_PORT}:127.0.0.1:22" >/dev/null 2>&1; then
    echo "Residual SSH tunnel process detected" >&2
    pgrep -fl "${LOCAL_FORWARD_PORT}:127.0.0.1:22" >&2 || true
    exit 1
  fi
}

wait_for_connected_signal() {
  local output_file="$1"
  local harness_pid="$2"
  local deadline=$((SECONDS + 15))

  while (( SECONDS < deadline )); do
    if [[ -f "$output_file" ]] && grep -q '^CONNECTED$' "$output_file"; then
      return 0
    fi

    if ! kill -0 "$harness_pid" 2>/dev/null; then
      echo "Harness exited before signaling connected state" >&2
      [[ -f "$output_file" ]] && cat "$output_file" >&2 || true
      return 1
    fi

    sleep 0.1
  done

  echo "Timed out waiting for harness connected signal" >&2
  [[ -f "$output_file" ]] && cat "$output_file" >&2 || true
  return 1
}

echo "== CPU check while connected =="
"$HARNESS_DIR/harness" disconnect "$SSHD_DIR/test_key" "$SSHD_PORT" "$LOCAL_FORWARD_PORT" >"$HARNESS_DIR/disconnect.out" 2>"$HARNESS_DIR/disconnect.err" &
HARNESS_PID=$!
wait_for_connected_signal "$HARNESS_DIR/disconnect.out" "$HARNESS_PID"
sleep 1
CPU_VALUE="$(ps -o %cpu= -p "$HARNESS_PID" | tr -d '[:space:]')"
echo "Harness CPU: ${CPU_VALUE}%"
python3 - <<PY
cpu = float("${CPU_VALUE:-0}")
if cpu > 5.0:
    raise SystemExit(f"CPU regression detected: {cpu}%")
PY
wait "$HARNESS_PID"

echo "== Disconnect cleanup check =="
sleep 1
assert_no_residual_processes

echo "== Crash cleanup check =="
"$HARNESS_DIR/harness" crash "$SSHD_DIR/test_key" "$SSHD_PORT" "$LOCAL_FORWARD_PORT" >"$HARNESS_DIR/crash.out" 2>"$HARNESS_DIR/crash.err" &
CRASH_PID=$!
wait_for_connected_signal "$HARNESS_DIR/crash.out" "$CRASH_PID"
kill -9 "$CRASH_PID" 2>/dev/null || true
CRASH_PID=
sleep 3
assert_no_residual_processes

echo "Regression checks passed."
