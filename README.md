<div align="center">
  <a href="https://mindthelatency.github.io/padwake/">
    <img src="docs/assets/icon.png" alt="PadWake icon" width="96" height="96" />
  </a>

  <h1>PadWake</h1>

  <p>A small Mac menu-bar app to use a Nintendo Switch 2 Pro Controller in World of Warcraft: Forever over USB-C.</p>

  <p>
    <a href="https://mindthelatency.github.io/padwake/">Website</a> &middot;
    <a href="#install">Install</a> &middot;
    <a href="#in-game-commands">Commands</a> &middot;
    <a href="#troubleshooting">Troubleshooting</a> &middot;
    <a href="LICENSE">MIT License</a>
  </p>
</div>

---

## What it does

- **Wakes the controller over USB-C** as soon as you plug it in, and lets you pick the player light (P1–P4) and test all buttons and sticks.
- **Fixes Mac detection** so World of Warcraft actually sees the controller instead of reporting none connected.
- **Matches the physical buttons** so X, Y, A, and B sit in the same places on screen as on the controller, and enables the GL, GR, and C buttons.
- **Sets up your bars and quests** with a small WoW addon for all 9 classes that places skills for your level and talents, and sets DialogueUI to Switch mode so A accepts and B closes.

No Homebrew, third-party libraries, or `sudo` required. You only need macOS 13+ and Apple's Command Line Tools (`xcode-select --install`).

---

## Install

```bash
git clone https://github.com/mindthelatency/padwake.git
cd padwake
make install-app
```

Then:

1. Click the gamepad icon in your Mac menu bar and check **Launch at Login**.
2. Click **Setup** next to your World of Warcraft folder.
3. Quit and reopen **Battle.net** once so WoW picks up the Mac controller fix.
4. Launch **World of Warcraft: Forever** and type `/padwake apply` in chat.

Right-click (or Control-click) the menu-bar icon anytime to wake the controller or quit PadWake.

---

## In-game commands

PadWake installs a small addon (`PadWakeProfiles`) that works with WoW: Forever's built-in controller bars (and detects ConsolePort if you use it). See [games/wow/classes/README.md](games/wow/classes/README.md) for the 9-class button and rear-paddle layouts.

- `/padwake apply` — Full setup (controller settings, rear-paddle macros, DialogueUI Switch mode, and skills for your level and talents).
- `/padwake bars` — Refresh your skills after leveling up, training new spells, or shifting into Stealth / Stance / Form. Add `--fill` to only fill empty slots.
- `/padwake dialogue` — Set DialogueUI to Switch mode (A accepts, B closes).
- `/padwake slots` — Print what is currently in each controller slot.
- `/padwake info` — Show your class cheat sheet.
- `/padwake reset` — Clear PadWake bindings.

---

## Troubleshooting

**WoW still sees no controller**
Make sure the Mac detection toggle is on in PadWake, then completely quit and reopen both Battle.net and WoW. You can check in WoW chat with `/dump C_GamePad.GetAllDeviceIDs()`.

**A and B are swapped in quest dialogs**
Run `/padwake dialogue` in chat and then `/reload` (or open DialogueUI settings → Control → Input Device → Switch).

**Up/down on the sticks feels inverted**
Remove the `~` from `lefty:a1~` / `righty:a3~` in [games/sdl2/gamecontrollerdb_padwake.txt](games/sdl2/gamecontrollerdb_padwake.txt), then click **Update** in PadWake.

---

<details>
<summary>Command-line tool, technical details, and release builds</summary>

### CLI & background daemon

```bash
make                  # Build bin/padwake
./bin/padwake enable  # Wake controller and check input
./bin/padwake status  # Check connection state
./bin/padwake watch   # Auto-wake on USB plug-in
./bin/padwake monitor # Print live button and stick input
make install-wow      # Install WoW: Forever files from Terminal
make install-daemon   # Run as a background LaunchAgent (use make uninstall-daemon if switching to PadWake.app)
```

### How it works under the hood

- Target device: USB VID `0x057E`, PID `0x2069`.
- Sends the USB init packet (`03 91 00 0d 00 08 00 00 01 00 ff ff ff ff ff ff`) and Player LED command (`09 91 00 07 00 08 00 00 <mask> ...`) over Vendor Interface 1 using macOS IOKit.
- Sets `SDL_JOYSTICK_MFI=0` via `launchctl` so SDL2 reads the USB HID stream instead of getting blocked by macOS `GCController`.
- Maps extra buttons via SDL2: `GR` → `PADPADDLE1`, `GL` → `PADPADDLE2`, `C` → `PADPADDLE3`, `Capture` → `PADSOCIAL`, with `"labelStyle": "Reverse"` in `GamePadConfig_PadWake.json`.

### Signed & notarized DMG (maintainers)

```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="padwake-notary" \
make release
```

</details>

---

PadWake is a free, independent open-source project and is not affiliated with Nintendo, Blizzard, or Apple. Released under the [MIT License](LICENSE).
