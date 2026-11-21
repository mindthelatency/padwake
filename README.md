<div align="center">
  <a href="https://mindthelatency.github.io/padwake/">
    <img src="docs/assets/icon.png" alt="PadWake app icon" width="120" height="120" />
  </a>

  <h1>PadWake</h1>

  <p>
    <strong>Nintendo Switch 2 Pro Controller for World of Warcraft: Forever on macOS — plug in and play.</strong>
  </p>

  <p>
    A tiny, zero-dependency macOS menu-bar app, IOKit USB wake utility, and lightweight WoW: Forever companion addon built specifically for <code>057E:2069</code> over USB-C.
  </p>

  <p>
    <a href="https://mindthelatency.github.io/padwake/"><img src="https://img.shields.io/badge/Website-padwake-0ea5e9?style=flat-square" alt="Website" /></a>
    <img src="https://img.shields.io/badge/macOS-13%2B%20(Apple%20Silicon%20%26%20Intel)-111827?style=flat-square&logo=apple&logoColor=white" alt="macOS 13+" />
    <img src="https://img.shields.io/badge/WoW-Forever%20(%5Fforever%5F)-6366f1?style=flat-square" alt="WoW: Forever" />
    <img src="https://img.shields.io/badge/Dependencies-Zero-10b981?style=flat-square" alt="Zero Dependencies" />
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-f59e0b?style=flat-square" alt="MIT License" /></a>
  </p>

  <p>
    <a href="#features">Features</a> &middot;
    <a href="#quick-start">Quick Start</a> &middot;
    <a href="#why-padwake">Why PadWake?</a> &middot;
    <a href="#cli--launchagent">CLI &amp; Daemon</a> &middot;
    <a href="#troubleshooting">Troubleshooting</a>
  </p>
</div>

---

Plugged a **Nintendo Switch 2 Pro Controller** (`VID 0x057E / PID 0x2069`) into your Mac over USB-C to play **World of Warcraft: Forever** and hit a wall of silent USB boot states, macOS's SDL2 veto, swapped `A`/`B` buttons, dead rear paddles, and empty crossbars?

**PadWake** solves the entire stack end-to-end in one tiny menu-bar app + zero-dependency companion addon — with **no Homebrew, no `libusb`, no kernel extensions, and no `sudo`**.

---

## Features

- **WoW: Forever Readiness Checklist** — One glance in the menu bar confirms all four layers are green: **Switch 2 Controller Awake (`057E:2069`)**, **macOS SDL2 Veto Fix (`SDL_JOYSTICK_MFI=0`)**, **WoW: Forever (`_forever_`) + `PadWakeProfiles` installed**, and **`DialogueUI` Switch Mode**.
- **Automatic USB-C Wake & Player LEDs** — Event-driven IOKit hotplug watcher (`~0%` idle CPU) sends the USB-C wake handshake and sets `P1`–`P4` LEDs automatically on connect.
- **Exact Switch 2 Face Diamond & Rear Paddles** — Pairs positional SDL2 mapping with WoW's `"labelStyle": "Reverse"` so the on-screen diamond matches your physical controller in **both position and printed letter** (`X` Top, `Y` Left, `A` Right, `B` Bottom), while mapping **`GL`**, **`GR`**, **`C`**, and **`Capture`** natively.
- **Level- & Talent-Spec-Aware Auto-Bars (All 9 Classes)** — The bundled `PadWakeProfiles` addon (v1.3.0) populates WoW: Forever's native Crossbar (`ZR` primary, `ZL` secondary, `ZL+ZR` cooldowns) with your highest-rank known spells, adapts to your talent specialization and active Stealth/Stance/Form, prompts on your first shift into a new form, and auto-configures **`DialogueUI`** to Switch mode (`A`=Accept, `B`=Exit).
- **Visual Switch 2 Live Input Tester** — Verify all **21 buttons** (`ZL`/`L`/`R`/`ZR`, `-`/`Cap`/`Home`/`C`/`+`, D-Pad, `X`/`Y`/`A`/`B` diamond, `L3`/`R3` clicks, and **`GL`/`GR`** rear paddles) plus both 12-bit analog sticks live inside the popover.

---

## Quick Start

> **Prerequisite:** Apple's Xcode Command Line Tools (`xcode-select --install`). No Homebrew or third-party libraries needed.

### 1. Build & Launch `PadWake.app`

```bash
git clone https://github.com/mindthelatency/padwake.git
cd padwake
make install-app
```

### 2. Finish Setup in 10 Seconds

1. Click the **gamepad icon** in your macOS menu bar and check **Launch at Login**.
2. In the **WoW: Forever Readiness** card, click **Setup** next to your auto-detected `_forever_` folder (installs `gamecontrollerdb.txt`, `GamePadConfig_PadWake.json`, `GamePadEnable`, and `Interface/AddOns/PadWakeProfiles`).
3. **Restart Battle.net once** so the game inherits `SDL_JOYSTICK_MFI=0`.
4. Launch **World of Warcraft: Forever** and run one slash command in chat:
   ```text
   /padwake apply
   ```
   PadWake applies class-tuned `C_GamePad` CVars, binds **`GL`/`GR`/`C`** to smart class macros, populates your native Forever Crossbar (`ZR`/`ZL`/`ZL+ZR`) for your current level and talent spec, and switches `DialogueUI` (if installed) to **Switch** mode.

<details>
<summary><strong>World of Warcraft: Forever — 9-Class Profiles &amp; Slash Commands</strong></summary>

All 9 classes are supported out of the box (Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, and Druid) — see [games/wow/classes/README.md](games/wow/classes/README.md) for the complete button, paddle (`GR`/`GL`/`C`), and macro reference.

- **Level- &amp; Talent-Spec-Aware:** Scans your live spellbook for highest trained ranks and inspects your talent tree points (`Protection` vs `Fury`/`Arms`, `Holy` vs `Prot` vs `Ret`, `Survival` melee vs ranged, `Shadow` vs `Holy`/`Disc`, `Ele`/`Enh`/`Resto`, `Feral`/`Balance`/`Resto`), falling back cleanly for Level 1–9 characters.
- **Native Forever Crossbar + ConsolePort Support:** Writes directly to WoW: Forever's native `GamepadMainActionBarFrame` storage slots (`ZR`/`ZL`/`ZL+ZR`, preserving native crossbar bindings and Stealth/Stance/Form paging), and detects **ConsolePort** automatically if installed.
- **First-Shift Prompts:** The first time you enter Stealth, Cat/Bear Form, Shadowform, or another Warrior Stance without bars populated yet, PadWake reminds you once to run `/padwake bars`.
- **Automatic `DialogueUI` Switch Mode:** When `DialogueUI` is installed and a Switch 2 controller (`1406:8297`) is connected, `/padwake apply` sets `DialogueUI_DB.InputDevice = 4` (Switch) so `A` confirms and `B` cancels quest dialogs.
- **Commands:**
  - `/padwake apply [class] [--keep-bars] [--force-bindings]` — Full setup (CVars, macros, rear paddles, `DialogueUI` Switch mode, and level/spec bars)
  - `/padwake bars [class] [--fill]` — Refresh controller bars after leveling up, learning spells, or shifting into a new stance/form
  - `/padwake dialogue` — Set `DialogueUI` to Switch mode (`A`=Accept, `B`=Exit)
  - `/padwake slots` / `/padwake info` / `/padwake reset` — Inspect slots, view class cheat sheet, or clear bindings

</details>

> **Tip:** Right-click (or Control-click) the menu-bar icon anytime to quickly **Wake Controller** or **Quit PadWake**.

---

## Why PadWake?

Getting a Switch 2 Pro Controller (`057E:2069`) to feel truly native in **World of Warcraft: Forever** on macOS requires solving four separate layers at once:

1. **Silent USB-C Boot State** — On plug-in, the controller sends zero HID reports until the host sends a USB initialization handshake and Player LED packet over Vendor Interface 1.
2. **macOS `GCController` / SDL2 MFi Veto** — Recent macOS versions report `GCController` support for `057E:2069` without publishing a controller, causing WoW's embedded SDL2 backend to report 0 controllers. Setting `SDL_JOYSTICK_MFI=0` lets SDL2 read the native USB HID stream directly.
3. **Switch vs. Xbox Button Geometry &amp; Rear Paddles** — Standard SDL2 configs render an Xbox diamond (`Y` Top / `B` Right / `A` Bottom) and ignore `GL`/`GR`/`C`. PadWake pairs positional SDL2 mapping with WoW's `"labelStyle": "Reverse"` and canonical SDL2 `rawIndex` paddle bindings (`16=GR`, `17=GL`, `18=C`, `15=Capture`).
4. **WoW: Forever Crossbar &amp; Quest Dialogs** — `PadWakeProfiles` populates Forever's native `GamepadMainActionBarFrame` slots (`185–208`) for your level and spec and sets `DialogueUI` to Switch mode so `A` accepts quests and `B` closes dialogs.

<details>
<summary><strong>Technical &amp; HID protocol details</strong></summary>

- **Interface 0 (`If_Hid`, USB HID Game Pad):** Parsed by macOS `AppleUserUSBHostHIDDevice` with standard **HID Report `0x09`** — 21 buttons + 4×12-bit analog axes (`X`, `Y`, `Rx`, `Rz`), readable directly by `IOHIDManager` and SDL2.
- **Interface 1 (Vendor Class `0xFF`, Bulk OUT `EP 0x02` / Bulk IN `EP 0x82`):** Unclaimed by macOS kernel drivers. PadWake opens it via native `IOUSBInterfaceInterface300` and sends:
  - **Wake handshake:** `03 91 00 0d 00 08 00 00 01 00 ff ff ff ff ff ff`
  - **Player LED (`P1`–`P4`):** `09 91 00 07 00 08 00 00 <mask> 00 00 00 00 00 00 00`
- **Extra buttons &amp; rear paddles mapping:** `GR` → `PADPADDLE1` (`b18` / SDL2 `rawIndex 16`), `GL` → `PADPADDLE2` (`b19` / SDL2 `rawIndex 17`), `C` → `PADPADDLE3` (`b20` / SDL2 `rawIndex 18`), `Capture` → `PADSOCIAL` (`b17` / SDL2 `rawIndex 15`).

</details>

---

## CLI &amp; LaunchAgent

Prefer a headless terminal tool instead of the menu-bar app? PadWake also builds a standalone IOKit CLI (`bin/padwake`) and keeps `games/sdl2/gamecontrollerdb_padwake.txt` available for any other SDL2 game.

<details>
<summary><strong>Show CLI commands &amp; background LaunchAgent setup</strong></summary>

```bash
# Build the standalone CLI (links only IOKit + CoreFoundation)
make

# Wake the connected controller and verify live HID Report 0x09 streaming
./bin/padwake enable

# Install WoW: Forever mappings + PadWakeProfiles addon via script
make install-wow

# Optional: run as a background LaunchAgent (auto-wakes + sets SDL_JOYSTICK_MFI=0)
make install-daemon
```

| Command | Description |
|---|---|
| `make` | Build `bin/padwake` |
| `make app` / `make install-app` | Build &amp; install `/Applications/PadWake.app` |
| `./bin/padwake status` | Check USB/HID presence and whether HID reports are streaming |
| `./bin/padwake enable [--led 1-4]` | Send USB wake handshake + Player LED command and verify HID stream |
| `./bin/padwake watch [--led 1-4]` | Stay running and auto-wake on USB hotplug via IOKit notifications |
| `./bin/padwake monitor` | Live-decode all 21 buttons and both 12-bit analog sticks |
| `make install-wow` | Install `gamecontrollerdb.txt`, `GamePadConfig_PadWake.json`, `GamePadEnable`, and `PadWakeProfiles` |
| `make launch-wow` | Wake controller and launch *World of Warcraft: Forever* with `SDL_JOYSTICK_MFI=0` |
| `make install-daemon` / `uninstall-daemon` | Install or remove the CLI `LaunchAgent` (`~/Library/Logs/padwake.log`) |

> If you switch from the CLI `LaunchAgent` to `PadWake.app`, run `make uninstall-daemon` so only `PadWake.app` manages hotplug waking.

</details>

---

## Troubleshooting

<details>
<summary><strong>Controller is awake in PadWake, but WoW: Forever still shows 0 controllers</strong></summary>

Make sure **macOS SDL2 Veto Fix** is toggled on in the Readiness Checklist, then **completely quit and reopen Battle.net and WoW: Forever** so the process inherits `SDL_JOYSTICK_MFI=0`.

Verify device detection in chat with:
```text
/dump C_GamePad.GetAllDeviceIDs()
```

</details>

<details>
<summary><strong>Quest dialogs in DialogueUI have A and B swapped</strong></summary>

Run `/padwake dialogue` (or `/padwake apply`) in-game and type `/reload`, or open `DialogueUI` settings → **Control** → **Input Device** → **Switch**.

</details>

<details>
<summary><strong>Up/down analog stick movement feels inverted</strong></summary>

Remove the `~` from `lefty:a1~` / `righty:a3~` in [games/sdl2/gamecontrollerdb_padwake.txt](games/sdl2/gamecontrollerdb_padwake.txt) (or add `"scale": -1` to `LStickY` / `RStickY` in [games/wow/GamePadConfig_PadWake.json](games/wow/GamePadConfig_PadWake.json)), then click **Update** in PadWake.

</details>

<details>
<summary><strong>Building a signed &amp; notarized release DMG (for maintainers)</strong></summary>

With an Apple **Developer ID Application** certificate and a `notarytool` keychain profile:

```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="padwake-notary" \
make release
```

This builds a **Universal Binary (`arm64` + `x86_64`)**, signs with Hardened Runtime, creates a drag-to-Applications `.dmg`, submits to Apple Notary Service, staples the ticket, and verifies Gatekeeper acceptance.

</details>

---

## Disclaimer &amp; License

> PadWake is an independent open-source interoperability utility. It is not affiliated with, endorsed by, or sponsored by Nintendo Co., Ltd., Blizzard Entertainment, Inc., or Apple Inc. All trademarks belong to their respective owners.

Released under the [MIT License](LICENSE).
