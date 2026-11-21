#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WOW_WTF="${1:-/Applications/World of Warcraft/_forever_/WTF}"

if [[ ! -d "$WOW_WTF" ]]; then
    echo "Error: WoW Forever WTF directory not found at: $WOW_WTF" >&2
    echo "Usage: $0 [/path/to/World of Warcraft/_forever_/WTF]" >&2
    exit 1
fi

GCDB="$WOW_WTF/gamecontrollerdb.txt"
CONFIG_WTF="$WOW_WTF/Config.wtf"
PAD_JSON="$WOW_WTF/GamePadConfig_PadWake.json"

# 1. Install SDL2 mapping entries idempotently into WTF/gamecontrollerdb.txt
touch "$GCDB"
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    guid="${line%%,*}"
    if grep -q "^${guid}," "$GCDB"; then
        echo "[wow] SDL2 mapping for $guid already present in $GCDB"
    else
        printf '\n%s\n' "$line" >> "$GCDB"
        echo "[wow] Added SDL2 mapping for $guid to $GCDB"
    fi
done < "$REPO_DIR/games/sdl2/gamecontrollerdb_padwake.txt"

# 2. Install GamePadConfig_PadWake.json (Reverse face labels + GL/GR/C paddles)
cp "$REPO_DIR/games/wow/GamePadConfig_PadWake.json" "$PAD_JSON"
echo "[wow] Installed $PAD_JSON"

# 3. Enable GamePadEnable in Config.wtf if not already set
if [[ -f "$CONFIG_WTF" ]]; then
    if grep -q '^SET GamePadEnable ' "$CONFIG_WTF"; then
        echo "[wow] GamePadEnable already configured in $CONFIG_WTF"
    else
        printf '\nSET GamePadEnable "1"\n' >> "$CONFIG_WTF"
        echo "[wow] Enabled SET GamePadEnable \"1\" in $CONFIG_WTF"
    fi
fi

echo "[wow] Done! Launch World of Warcraft Forever and verify in chat with: /dump C_GamePad.GetAllDeviceIDs()"
