#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_PATH="$REPO_DIR/bin/padwake"
PLIST_LABEL="com.local.padwake"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
LOG_PATH="$HOME/Library/Logs/padwake.log"

ACTION="${1:-install}"

case "$ACTION" in
    install)
        if [[ ! -x "$BIN_PATH" ]]; then
            echo "Error: $BIN_PATH not built yet. Run 'make' first." >&2
            exit 1
        fi
        mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
        cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>/bin/launchctl setenv SDL_JOYSTICK_MFI 0; exec "${BIN_PATH}" watch</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
</dict>
</plist>
EOF
        launchctl setenv SDL_JOYSTICK_MFI 0
        launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
        echo "[daemon] Set launchd env SDL_JOYSTICK_MFI=0 (restart your game launcher once if already open)"
        echo "[daemon] Installed and started ${PLIST_LABEL}"
        echo "[daemon] Logs: ${LOG_PATH}"
        ;;
    uninstall)
        launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
        launchctl unsetenv SDL_JOYSTICK_MFI 2>/dev/null || true
        rm -f "$PLIST_PATH"
        echo "[daemon] Uninstalled ${PLIST_LABEL} and unset SDL_JOYSTICK_MFI"
        ;;
    *)
        echo "Usage: $0 [install|uninstall]" >&2
        exit 1
        ;;
esac
