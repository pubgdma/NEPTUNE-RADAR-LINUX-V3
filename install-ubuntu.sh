#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_PATH="/etc/systemd/system/neptune-radar.service"
TEMPLATE_PATH="$SCRIPT_DIR/neptune-radar.service.template"
INSTALL_DIR="${INSTALL_DIR:-/opt/neptune-radar}"
CONFIG_PATH="$SCRIPT_DIR/config/config.toml"

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

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo."
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg lsof

if ! command -v node >/dev/null 2>&1; then
  mkdir -p /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  fi
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
fi

chmod +x "$SCRIPT_DIR/install-from-github.sh" "$SCRIPT_DIR/install-ubuntu.sh" "$SCRIPT_DIR/start-radar.sh" "$SCRIPT_DIR/stop-radar.sh" "$SCRIPT_DIR/uninstall-ubuntu.sh" "$SCRIPT_DIR/update-radar.sh"

mkdir -p "$INSTALL_DIR"
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  cp -a "$SCRIPT_DIR"/. "$INSTALL_DIR"/
fi

chmod +x "$INSTALL_DIR/install-from-github.sh" "$INSTALL_DIR/install-ubuntu.sh" "$INSTALL_DIR/start-radar.sh" "$INSTALL_DIR/stop-radar.sh" "$INSTALL_DIR/uninstall-ubuntu.sh" "$INSTALL_DIR/update-radar.sh"

sed "s|__APP_DIR__|$INSTALL_DIR|g" "$TEMPLATE_PATH" > "$SERVICE_PATH"
systemctl daemon-reload
systemctl enable neptune-radar.service
systemctl restart neptune-radar.service

sleep 2

echo
echo "Service status:"
systemctl --no-pager --full status neptune-radar.service || true

echo
echo "Enabled instances:"
while IFS=$'\t' read -r kind a b c; do
  if [[ "$kind" == "INSTANCE" && "$c" == "true" ]]; then
    echo "  - $a on port $b"
  fi
done < <(parse_config "$CONFIG_PATH")

echo
echo "Install directory: $INSTALL_DIR"
echo "Systemd service created: neptune-radar.service"
echo
echo "Start service:"
echo "  sudo systemctl start neptune-radar"
echo
echo "Stop service:"
echo "  sudo systemctl stop neptune-radar"
echo
echo "Service logs:"
echo "  journalctl -u neptune-radar -f"

