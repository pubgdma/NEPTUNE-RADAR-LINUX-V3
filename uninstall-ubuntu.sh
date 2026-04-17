#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/neptune-radar}"

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo."
  exit 1
fi

systemctl stop neptune-radar 2>/dev/null || true
systemctl disable neptune-radar 2>/dev/null || true
rm -f /etc/systemd/system/neptune-radar.service
systemctl daemon-reload

if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
fi

echo "neptune-radar.service removed."
echo "Install directory removed: $INSTALL_DIR"

