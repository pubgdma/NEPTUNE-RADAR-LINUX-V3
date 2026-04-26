#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/config/config.toml"
SERVER_PATH="$SCRIPT_DIR/neptune-direct-server.js"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
PIDS=()
PORTS=()
INSTANCE_LABELS=()
SERVER_IP="0.0.0.0"
SERVER_PORT_FALLBACK="7823"
BROWSER_IP="127.0.0.1"
DEFAULT_PASSWORD_CONFIG="$SCRIPT_DIR/config/password.toml"

parse_config() {
  local config_path="$1"
  awk '
    function flush_instance() {
      if (!in_instance) return
      if (enabled == "") enabled = "true"
      if (id == "" && port != "") id = port
      if (port != "") print "INSTANCE\t" id "\t" port "\t" enabled
      in_instance = 0
    }
    {
      line = $0
      sub(/[;#].*$/, "", line)
      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*\[server\][ \t]*$/) {
        flush_instance()
        section = "server"
        next
      }
      if (line ~ /^[ \t]*\[\[instances\]\][ \t]*$/) {
        flush_instance()
        section = "instances"
        in_instance = 1
        id = ""
        port = ""
        enabled = ""
        next
      }
      if (section == "server") {
        if (match(line, /^[ \t]*ip[ \t]*=[ \t]*"([^"]+)"/, m)) print "SERVER_IP\t" m[1]
        if (match(line, /^[ \t]*port[ \t]*=[ \t]*([0-9]+)/, m)) server_port = m[1]
        next
      }
      if (section == "instances") {
        if (match(line, /^[ \t]*id[ \t]*=[ \t]*"([^"]+)"/, m)) id = m[1]
        if (match(line, /^[ \t]*port[ \t]*=[ \t]*([0-9]+)/, m)) port = m[1]
        if (match(line, /^[ \t]*enabled[ \t]*=[ \t]*(true|false)/, m)) enabled = m[1]
      }
    }
    END {
      flush_instance()
      if (server_port != "") print "SERVER_PORT\t" server_port
    }
  ' "$config_path"
}

load_settings() {
  local have_instance=0
  while IFS=$'\t' read -r kind a b c; do
    case "$kind" in
      SERVER_IP)
        SERVER_IP="$a"
        ;;
      SERVER_PORT)
        SERVER_PORT_FALLBACK="$a"
        ;;
      INSTANCE)
        have_instance=1
        if [[ "$c" == "true" ]]; then
          PORTS+=("$b")
          INSTANCE_LABELS+=("$a:$b")
        fi
        ;;
    esac
  done < <(parse_config "$CONFIG_PATH")

  if [[ "$have_instance" -eq 0 ]]; then
    PORTS+=("$SERVER_PORT_FALLBACK")
    INSTANCE_LABELS+=("main:$SERVER_PORT_FALLBACK")
  fi

  if [[ ${#PORTS[@]} -eq 0 ]]; then
    echo "No enabled instances found in config/config.toml"
    exit 1
  fi

  if [[ "$SERVER_IP" != "0.0.0.0" && "$SERVER_IP" != "::" ]]; then
    BROWSER_IP="$SERVER_IP"
  fi
}

stop_existing() {
  pkill -f "$SERVER_PATH" 2>/dev/null || true
  if command -v lsof >/dev/null 2>&1; then
    for port in "${PORTS[@]}"; do
      old_pids="$(lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u || true)"
      if [[ -n "${old_pids:-}" ]]; then
        kill -9 $old_pids 2>/dev/null || true
      fi
    done
  fi
}

cleanup() {
  if [[ ${#PIDS[@]} -gt 0 ]]; then
    kill "${PIDS[@]}" 2>/dev/null || true
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
  rm -f "$RUNTIME_DIR"/*.pid 2>/dev/null || true
}

start_all() {
  PIDS=()
  mkdir -p "$RUNTIME_DIR"
  for item in "${INSTANCE_LABELS[@]}"; do
    instance_id="${item%%:*}"
    port="${item##*:}"
    instance_password_config="$SCRIPT_DIR/config/passwords_server_manager/$instance_id.toml"
    password_config="$DEFAULT_PASSWORD_CONFIG"
    if [[ -f "$instance_password_config" ]]; then
      password_config="$instance_password_config"
    fi
    (
      export NEPTUNE_RADAR_ROOT="$SCRIPT_DIR"
      export NEPTUNE_RADAR_CONFIG="$CONFIG_PATH"
      export NEPTUNE_RADAR_IP="$SERVER_IP"
      export NEPTUNE_RADAR_PORT="$port"
      export NEPTUNE_RADAR_INSTANCE="$instance_id"
      export NEPTUNE_RADAR_PASSWORD_CONFIG="$password_config"
      exec node "$SERVER_PATH"
    ) >>"$RUNTIME_DIR/$instance_id.log" 2>&1 &
    pid=$!
    PIDS+=("$pid")
    printf '%s\n' "$pid" > "$RUNTIME_DIR/$instance_id.pid"
  done
}

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is not installed."
  echo "Run ./install-ubuntu.sh or install Node.js 24+ manually."
  exit 1
fi

if [[ ! -f "$SERVER_PATH" ]]; then
  echo "Radar server file not found:"
  echo "$SERVER_PATH"
  exit 1
fi

load_settings
stop_existing

echo
echo "Neptune Radar is starting..."
for item in "${INSTANCE_LABELS[@]}"; do
  instance_id="${item%%:*}"
  port="${item##*:}"
  echo "Instance: $instance_id"
  echo "IP: $BROWSER_IP"
  echo "Port: $port"
  echo "Open your browser and go to: http://$BROWSER_IP:$port"
  echo
done
echo "Keep this window open while using the radar."
echo

trap 'cleanup; exit 0' INT TERM
trap 'cleanup' EXIT

while true; do
  start_all
  if wait -n "${PIDS[@]}"; then
    exit_code=0
  else
    exit_code=$?
  fi
  echo
  echo "Radar server stopped."
  echo "Exit code: $exit_code"
  echo "Restarting all enabled instances in 2 seconds. Press Ctrl+C to stop."
  cleanup
  sleep 2
done
