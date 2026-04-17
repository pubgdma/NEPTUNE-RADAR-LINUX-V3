#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PATH="$SCRIPT_DIR/neptune-direct-server.js"
CONFIG_PATH="$SCRIPT_DIR/config/config.toml"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
PORTS=()

parse_config() {
  local config_path="$1"
  awk '
    function flush_instance() {
      if (!in_instance) return
      if (port != "") print port
      in_instance = 0
    }
    {
      line = $0
      sub(/[;#].*$/, "", line)
      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*\[\[instances\]\][ \t]*$/) {
        flush_instance()
        in_instance = 1
        port = ""
        next
      }
      if (match(line, /^[ \t]*port[ \t]*=[ \t]*([0-9]+)/, m)) {
        if (in_instance) {
          port = m[1]
        } else if (fallback_port == "") {
          fallback_port = m[1]
        }
      }
    }
    END {
      flush_instance()
      if (fallback_port != "") print fallback_port
    }
  ' "$config_path"
}

while IFS= read -r port; do
  [[ -n "$port" ]] && PORTS+=("$port")
done < <(parse_config "$CONFIG_PATH")

pkill -f "$SERVER_PATH" 2>/dev/null || true

if command -v lsof >/dev/null 2>&1; then
  for port in "${PORTS[@]}"; do
    old_pids="$(lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u || true)"
    if [[ -n "${old_pids:-}" ]]; then
      kill -9 $old_pids 2>/dev/null || true
    fi
  done
fi

rm -f "$RUNTIME_DIR"/*.pid 2>/dev/null || true

echo "Radar stopped."

