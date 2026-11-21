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

        TMP_PLIST="$(mktemp "$HOME/Library/LaunchAgents/.${PLIST_LABEL}.plist.XXXXXX")"
        trap 'rm -f "$TMP_PLIST"' EXIT
        rm -f "$TMP_PLIST"

        # Construct plist via PlistBuddy (immune to XML & shell injection)
        /usr/libexec/PlistBuddy -c "Add :Label string $PLIST_LABEL" "$TMP_PLIST" >/dev/null
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string /bin/sh" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string -c" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:2 string /bin/launchctl setenv SDL_JOYSTICK_MFI 0; exec "$1" watch' "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:3 string --" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:4 string $BIN_PATH" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :KeepAlive bool true" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :StandardOutPath string $LOG_PATH" "$TMP_PLIST"
        /usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $LOG_PATH" "$TMP_PLIST"

        plutil -lint "$TMP_PLIST" >/dev/null
        chmod 644 "$TMP_PLIST"
        mv -f "$TMP_PLIST" "$PLIST_PATH"

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
