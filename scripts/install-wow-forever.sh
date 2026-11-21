#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WOW_WTF=""
CLASS_PRESET="auto"

usage() {
    echo "Usage: $0 [--class <auto|warrior|paladin|hunter|rogue|priest|deathknight|shaman|mage|warlock|druid>] [/path/to/World of Warcraft/<flavor>/WTF]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --class)
            if [[ $# -lt 2 ]]; then
                echo "Error: --class requires a value." >&2
                usage
                exit 1
            fi
            CLASS_PRESET="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Error: unknown option '$1'" >&2
            usage
            exit 1
            ;;
        *)
            WOW_WTF="$1"
            shift
            ;;
    esac
done

case "$CLASS_PRESET" in
    auto|warrior|paladin|hunter|rogue|priest|deathknight|shaman|mage|warlock|druid)
        CLASS_TOKEN="$(printf '%s' "$CLASS_PRESET" | tr '[:lower:]' '[:upper:]')"
        ;;
    *)
        echo "Error: invalid --class '$CLASS_PRESET'." >&2
        usage
        exit 1
        ;;
esac

if [[ -z "$WOW_WTF" ]]; then
    for flavor in _forever_ _classic_era_ _anniversary_ _classic_; do
        candidate="/Applications/World of Warcraft/${flavor}"
        if [[ -d "$candidate" ]]; then
            WOW_WTF="${candidate}/WTF"
            break
        fi
    done
    WOW_WTF="${WOW_WTF:-/Applications/World of Warcraft/_forever_/WTF}"
fi

# Allow passing either the flavor root (e.g. .../_classic_era_) or its WTF directory
if [[ "$(basename "$WOW_WTF")" != "WTF" && -d "$WOW_WTF" ]]; then
    WOW_WTF="${WOW_WTF}/WTF"
fi

FLAVOR_PARENT="$(dirname "$WOW_WTF")"
if [[ ! -d "$FLAVOR_PARENT" ]]; then
    echo "Error: WoW flavor directory not found at: $FLAVOR_PARENT" >&2
    usage
    exit 1
fi
mkdir -p "$WOW_WTF"

GCDB="$WOW_WTF/gamecontrollerdb.txt"
CONFIG_WTF="$WOW_WTF/Config.wtf"
PAD_JSON="$WOW_WTF/GamePadConfig_PadWake.json"

# 1. Upsert SDL2 mapping entries idempotently into WTF/gamecontrollerdb.txt
touch "$GCDB"
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    guid="${line%%,*}"
    if awk -v g="${guid}," 'index($0, g) == 1 { found=1; exit } END { exit !found }' "$GCDB"; then
        if grep -qxF -- "$line" "$GCDB"; then
            echo "[wow] SDL2 mapping for $guid already up to date in $GCDB"
        else
            TMP_GCDB="$(mktemp "$WOW_WTF/.gamecontrollerdb.txt.XXXXXX")"
            awk -v g="${guid}," -v repl="$line" '
                index($0, g) == 1 && !done { print repl; done=1; next }
                { print }
            ' "$GCDB" > "$TMP_GCDB"
            chmod 644 "$TMP_GCDB"
            mv -f "$TMP_GCDB" "$GCDB"
            echo "[wow] Updated SDL2 mapping for $guid in $GCDB"
        fi
    else
        printf '\n%s\n' "$line" >> "$GCDB"
        echo "[wow] Added SDL2 mapping for $guid to $GCDB"
    fi
done < "$REPO_DIR/games/sdl2/gamecontrollerdb_padwake.txt"

# 2. Install GamePadConfig_PadWake.json atomically (Reverse Switch 2 diamond + GL/GR/C paddles)
TMP_JSON="$(mktemp "$WOW_WTF/.GamePadConfig_PadWake.json.XXXXXX")"
trap 'rm -f "$TMP_JSON"' EXIT
cp "$REPO_DIR/games/wow/GamePadConfig_PadWake.json" "$TMP_JSON"
chmod 644 "$TMP_JSON"
mv -f "$TMP_JSON" "$PAD_JSON"
rm -f "$WOW_WTF/GamePadConfig_Switch2.json"
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

# 4. Install lightweight PadWakeProfiles companion addon for in-game class profile apply
ADDON_SRC="$REPO_DIR/games/wow/AddOns/PadWakeProfiles"
if [[ -d "$ADDON_SRC" ]]; then
    if [[ "$(basename "$WOW_WTF")" == "WTF" ]]; then
        FLAVOR_ROOT="$(dirname "$WOW_WTF")"
    else
        FLAVOR_ROOT="$WOW_WTF"
    fi
    ADDON_DST="$FLAVOR_ROOT/Interface/AddOns/PadWakeProfiles"
    mkdir -p "$ADDON_DST"

    for fname in PadWakeProfiles.toc PadWakeProfiles.lua; do
        TMP_FILE="$(mktemp "$ADDON_DST/.${fname}.XXXXXX")"
        cp "$ADDON_SRC/$fname" "$TMP_FILE"
        chmod 644 "$TMP_FILE"
        mv -f "$TMP_FILE" "$ADDON_DST/$fname"
    done

    TMP_PRESET="$(mktemp "$ADDON_DST/.SelectedPreset.lua.XXXXXX")"
    cat > "$TMP_PRESET" <<EOF
-- Updated automatically by scripts/install-wow-forever.sh
local _, ns = ...
ns.selectedPreset = "${CLASS_TOKEN}"
EOF
    chmod 644 "$TMP_PRESET"
    mv -f "$TMP_PRESET" "$ADDON_DST/SelectedPreset.lua"
    echo "[wow] Installed PadWakeProfiles addon -> $ADDON_DST (preset: $CLASS_TOKEN)"
fi

echo "[wow] Done! In World of Warcraft, verify with '/dump C_GamePad.GetAllDeviceIDs()' and apply your class profile with '/padwake apply'."
