#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_PATH="$REPO_DIR/bin/padwake"
WOW_APP="${1:-/Applications/World of Warcraft/_forever_/World of Warcraft.app}"

if [[ ! -x "$BIN_PATH" ]]; then
    echo "[wow] Building padwake..."
    make -C "$REPO_DIR"
fi

echo "[wow] Ensuring USB gamepad is awake..."
"$BIN_PATH" enable

echo "[wow] Launching World of Warcraft Forever with SDL_JOYSTICK_MFI=0..."
open -n --env SDL_JOYSTICK_MFI=0 -a "$WOW_APP"
