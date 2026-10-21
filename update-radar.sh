#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-pubgdma}"
REPO_NAME="${REPO_NAME:-NEPTUNE-RADAR-LINUX-V3}"
REPO_REF="${REPO_REF:-main}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

find_repo_root() {
  local extracted_dir=""
  extracted_dir="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -f "$extracted_dir/install-ubuntu.sh" && -f "$extracted_dir/start-radar.sh" ]]; then
    printf '%s\n' "$extracted_dir"
    return 0
  fi
  if [[ -d "$extracted_dir/NeptuneRadar3-LINUX-PUBLIC" && -f "$extracted_dir/NeptuneRadar3-LINUX-PUBLIC/install-ubuntu.sh" ]]; then
    printf '%s\n' "$extracted_dir/NeptuneRadar3-LINUX-PUBLIC"
    return 0
  fi
  return 1
}

list_repo_files() {
  local root="$1"
  (
    cd "$root"
    find . -type f \
      ! -path './.git/*' \
      ! -path './runtime/*' \
      ! -path './server/instances/*' \
      ! -path './config/config.toml' \
      ! -path './config/password.toml' \
      | sed 's#^\./##' \
      | sort
  )
}

list_repo_dirs() {
  local root="$1"
  (
    cd "$root"
    find . -type d \
      ! -path '.' \
      ! -path './.git' \
      ! -path './.git/*' \
      ! -path './runtime' \
      ! -path './runtime/*' \
      ! -path './server/instances' \
      ! -path './server/instances/*' \
      | sed 's#^\./##' \
      | sort
  )
}

list_local_empty_dirs() {
  local root="$1"
  (
    cd "$root"
    find . -type d -empty \
      ! -path '.' \
      ! -path './.git' \
      ! -path './.git/*' \
      ! -path './runtime' \
      ! -path './runtime/*' \
      ! -path './server/instances' \
      ! -path './server/instances/*' \
      | sed 's#^\./##' \
      | sort
  )
}

file_hash() {
  local path="$1"
  sha256sum "$path" | awk '{print $1}'
}

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required."
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required."
  exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "sha256sum is required."
  exit 1
fi

echo "Checking for updates..."
curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/package.tar.gz"
tar -xzf "$TMP_DIR/package.tar.gz" -C "$TMP_DIR"

REMOTE_ROOT="$(find_repo_root || true)"
if [[ -z "${REMOTE_ROOT:-}" ]]; then
  echo "Linux updater content not found in the downloaded archive."
  exit 1
fi

mapfile -t REMOTE_FILES < <(list_repo_files "$REMOTE_ROOT")
mapfile -t LOCAL_FILES < <(list_repo_files "$APP_DIR")
mapfile -t REMOTE_DIRS < <(list_repo_dirs "$REMOTE_ROOT")
mapfile -t LOCAL_EMPTY_DIRS < <(list_local_empty_dirs "$APP_DIR")

declare -A REMOTE_SET=()
declare -A REMOTE_DIR_SET=()

for file in "${REMOTE_FILES[@]}"; do
  REMOTE_SET["$file"]=1
done

for dir in "${REMOTE_DIRS[@]}"; do
  REMOTE_DIR_SET["$dir"]=1
done

CHANGED_FILES=()
REMOVED_FILES=()
REMOVABLE_DIRS=()

for file in "${REMOTE_FILES[@]}"; do
  remote_path="$REMOTE_ROOT/$file"
  local_path="$APP_DIR/$file"
  if [[ ! -f "$local_path" ]]; then
    CHANGED_FILES+=("$file")
    continue
  fi
  if [[ "$(file_hash "$remote_path")" != "$(file_hash "$local_path")" ]]; then
    CHANGED_FILES+=("$file")
  fi
done

for file in "${LOCAL_FILES[@]}"; do
  if [[ -z "${REMOTE_SET[$file]+x}" ]]; then
    REMOVED_FILES+=("$file")
  fi
done

for dir in "${LOCAL_EMPTY_DIRS[@]}"; do
  if [[ -z "${REMOTE_DIR_SET[$dir]+x}" ]]; then
    REMOVABLE_DIRS+=("$dir")
  fi
done

TOTAL_CHANGES=$(( ${#CHANGED_FILES[@]} + ${#REMOVED_FILES[@]} + ${#REMOVABLE_DIRS[@]} ))

if [[ "$TOTAL_CHANGES" -eq 0 ]]; then
  echo "You're running the latest version."
  exit 0
fi

echo "Updates are available."
echo "Files to update: ${#CHANGED_FILES[@]}"
echo "Files to remove: ${#REMOVED_FILES[@]}"
echo "Empty folders to remove: ${#REMOVABLE_DIRS[@]}"
echo "Total changes: $TOTAL_CHANGES"
read -r -p "Do you want to update now? [y/N] " reply

case "${reply,,}" in
  y|yes)
    ;;
  *)
    echo "Update cancelled."
    exit 0
    ;;
esac

for file in "${CHANGED_FILES[@]}"; do
  mkdir -p "$(dirname "$APP_DIR/$file")"
  cp -f "$REMOTE_ROOT/$file" "$APP_DIR/$file"
done

for file in "${REMOVED_FILES[@]}"; do
  rm -f "$APP_DIR/$file"
done

for dir in "${REMOVABLE_DIRS[@]}"; do
  rmdir "$APP_DIR/$dir" 2>/dev/null || true
done

mapfile -t FINAL_REMOVABLE_DIRS < <(list_local_empty_dirs "$APP_DIR")
for dir in "${FINAL_REMOVABLE_DIRS[@]}"; do
  if [[ -z "${REMOTE_DIR_SET[$dir]+x}" ]]; then
    rmdir "$APP_DIR/$dir" 2>/dev/null || true
  fi
done

chmod +x \
  "$APP_DIR/install-from-github.sh" \
  "$APP_DIR/install-ubuntu.sh" \
  "$APP_DIR/start-radar.sh" \
  "$APP_DIR/stop-radar.sh" \
  "$APP_DIR/uninstall-ubuntu.sh" \
  "$APP_DIR/update-radar.sh"

if [[ $EUID -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
  systemctl restart neptune-radar.service || true
fi

echo "Update completed successfully."
