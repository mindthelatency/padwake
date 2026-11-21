#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_PATH="$REPO_DIR/bin/padwake"
WOW_APP="${1:-}"
if [[ -z "$WOW_APP" ]]; then
    for flavor in _forever_ _classic_era_ _anniversary_ _classic_ _retail_; do
        for appname in "World of Warcraft.app" "World of Warcraft Classic.app"; do
            candidate="/Applications/World of Warcraft/${flavor}/${appname}"
            if [[ -d "$candidate" ]]; then
                WOW_APP="$candidate"
                break 2
            fi
        done
    done
    WOW_APP="${WOW_APP:-/Applications/World of Warcraft/_forever_/World of Warcraft.app}"
fi

if [[ ! -x "$BIN_PATH" ]]; then
    echo "[wow] Building padwake..."
    make -C "$REPO_DIR"
fi

echo "[wow] Ensuring USB gamepad is awake..."
"$BIN_PATH" enable

echo "[wow] Launching World of Warcraft ($WOW_APP) with SDL_JOYSTICK_MFI=0..."
open -n --env SDL_JOYSTICK_MFI=0 -a "$WOW_APP"
