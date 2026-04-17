#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-pubgdma}"
REPO_NAME="${REPO_NAME:-NEPTUNE-RADAR-LINUX-V3}"
REPO_REF="${REPO_REF:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/neptune-radar}"
TMP_DIR="$(mktemp -d)"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer with sudo."
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl tar gzip gnupg lsof

echo "Downloading ${ARCHIVE_URL}"
curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/package.tar.gz"
tar -xzf "$TMP_DIR/package.tar.gz" -C "$TMP_DIR"

EXTRACTED_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
PACKAGE_DIR=""

if [[ -f "$EXTRACTED_DIR/install-ubuntu.sh" && -f "$EXTRACTED_DIR/start-radar.sh" ]]; then
  PACKAGE_DIR="$EXTRACTED_DIR"
elif [[ -d "$EXTRACTED_DIR/NeptuneRadar3-LINUX-PUBLIC" && -f "$EXTRACTED_DIR/NeptuneRadar3-LINUX-PUBLIC/install-ubuntu.sh" ]]; then
  PACKAGE_DIR="$EXTRACTED_DIR/NeptuneRadar3-LINUX-PUBLIC"
else
  echo "Linux installer content not found in the downloaded archive."
  exit 1
fi

chmod +x \
  "$PACKAGE_DIR/install-from-github.sh" \
  "$PACKAGE_DIR/install-ubuntu.sh" \
  "$PACKAGE_DIR/start-radar.sh" \
  "$PACKAGE_DIR/stop-radar.sh" \
  "$PACKAGE_DIR/uninstall-ubuntu.sh" \
  "$PACKAGE_DIR/update-radar.sh"

cd "$PACKAGE_DIR"
INSTALL_DIR="$INSTALL_DIR" ./install-ubuntu.sh

echo
echo "Installation completed."
echo "Radar is installed to: $INSTALL_DIR"
echo "Service name: neptune-radar"
echo "Open in browser: http://YOUR_VPS_IP:7823"
