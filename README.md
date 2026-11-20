# PadWake — macOS USB Gamepad Enabler (VID `0x057E` / PID `0x2069`)

Zero-dependency native macOS IOKit USB wake utility, auto-hotplug daemon, live HID input monitor, and SDL2 / World of Warcraft Forever gamepad configuration for the **Nintendo Switch 2 Pro Controller** over USB-C.

No Homebrew, no `libusb`, and no `sudo` required.

> **Disclaimer:** Independent open-source interoperability utility. Not affiliated with, endorsed by, or sponsored by Nintendo Co., Ltd., Blizzard Entertainment, Inc., or Apple Inc. All trademarks belong to their respective owners.

---

## Why This Is Needed on macOS 27

When connected over USB-C on macOS, the controller (`VID 0x057E`, `PID 0x2069`) exposes:
- **Interface 0 (`If_Hid`, USB HID Game Pad):** Already parsed by macOS `AppleUserUSBHostHIDDevice` with a standard HID Report `0x09` (21 buttons + 4×12-bit analog axes `X`, `Y`, `Rx`, `Rz`), readable by `IOHIDManager` and SDL2 games.
- **Interface 1 (Vendor Class `0xFF`, Bulk OUT `EP 0x02` / Bulk IN `EP 0x82`):** Unclaimed by any kernel driver.

Two macOS 27 + SDL2 quirks prevent games from seeing inputs out of the box:

1. **USB silent boot state:** The controller sends **zero** HID reports (`ReportAvailableCalls = 0`) until a host sends the USB initialization handshake (`0x03 0x91 ...`) and Player LED packet (`0x09 0x91 ...`) over Interface 1. Once woken, Interface 0 immediately streams 64-byte HID `Report 0x09` packets continuously.
2. **macOS 27 `GCController` veto bug in SDL2 (`SDL_JOYSTICK_MFI`):** On macOS 27, `[GCController supportsHIDDevice:]` returns `YES` for `057e:2069`, causing SDL2's IOKit driver (`SDL_iokitjoystick`) to discard the controller and hand it off to `GCController` (`SDL_mfijoystick`) — yet `GCController.controllers()` never publishes it (`0 GamePad devices connected`). Launching the game (or its launcher) with **`SDL_JOYSTICK_MFI=0`** bypasses that veto so SDL2's IOKit driver reads the controller directly.

---

## Quick Start

### Option A: Native macOS Menu-Bar App (`PadWake.app`) — Recommended
```bash
# Build & launch PadWake.app in your menu bar (ad-hoc signed for local use)
make open-app

# Or install directly to /Applications/PadWake.app and launch it
# (Required if you want to enable "Launch at Login" via SMAppService)
make install-app
```
Inside **PadWake.app**:
- Auto-wakes your controller whenever plugged in via IOKit hotplug notifications
- Live **Player LED** (`P1`–`P4`) switcher & collapsible **Live Input Tester**
- One-click **Fix macOS SDL2 MFi Veto (`SDL_JOYSTICK_MFI=0`)** toggle
- One-click **Install Gamepad Mappings…** folder picker
- Native macOS **Launch at Login** (`SMAppService`)

*(If you previously ran `make install-daemon`, you can run `make uninstall-daemon` once you enable Launch at Login in `PadWake.app`.)*

### Building a Signed & Notarized Release DMG (Direct Distribution)
Once you have an Apple Developer ID certificate and `notarytool` profile stored in Keychain:
```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="padwake-notary" \
make release
```
This builds a **Universal Binary (`arm64` + `x86_64`)**, signs with **Hardened Runtime**, packages a drag-to-Applications `.dmg`, submits to Apple Notary Service, staples the ticket, and verifies Gatekeeper acceptance.

### Option B: CLI / LaunchAgent
```bash
# 1. Build the native macOS IOKit binary
make

# 2. Wake the connected controller and verify live HID Report 0x09 streaming
./bin/padwake enable

# 3. Install SDL2 & GamePadConfig mappings into World of Warcraft Forever
make install-wow

# 4. Install the background LaunchAgent (auto-wakes on USB hotplug AND persists SDL_JOYSTICK_MFI=0)
make install-daemon
# -> Quit and reopen your game launcher once so it inherits SDL_JOYSTICK_MFI=0.

# (Alternative) Launch World of Warcraft Forever directly with SDL_JOYSTICK_MFI=0:
make launch-wow
```

> **Note if you rename or move this folder:** All scripts resolve their path dynamically, *except* the already-installed `~/Library/LaunchAgents/com.local.padwake.plist`, which stores the absolute path to `bin/padwake`. After renaming or moving this directory, simply re-run:
> ```bash
> make install-daemon
> ```

---

## Commands

| Command | Description |
|---|---|
| `make` | Build `bin/padwake` (links only `IOKit` + `CoreFoundation`) |
| `./bin/padwake status` | Check USB/HID presence and whether HID reports are streaming |
| `./bin/padwake enable [--led 1-4]` | Send USB wake handshake + Player LED command and verify HID stream |
| `./bin/padwake watch [--led 1-4]` | Stay running and auto-wake on USB hotplug via IOKit notifications |
| `./bin/padwake monitor` | Live-decode all 21 buttons and both 12-bit analog sticks |
| `make install-wow` | Install `gamecontrollerdb.txt` entries, `GamePadConfig_PadWake.json`, and `GamePadEnable` |
| `make launch-wow` | Wake controller and launch World of Warcraft Forever with `SDL_JOYSTICK_MFI=0` |
| `make install-daemon` | Install/start `LaunchAgent` (`watch` + `launchctl setenv SDL_JOYSTICK_MFI 0`) |
| `make uninstall-daemon` | Stop/remove `LaunchAgent` and unset `SDL_JOYSTICK_MFI` |

---

## Verifying & Customizing In-Game

- **Check detected devices in chat** (`/console GamePadListDevices` logs to `Logs/General.log` rather than chat):
  ```text
  /dump C_GamePad.GetAllDeviceIDs()
  ```
- **Stick Y-axis inversion:** If vertical stick movement feels inverted, remove the `~` from `lefty:a1~` / `righty:a3~` in `wow/gamecontrollerdb_padwake.txt` (or add `"scale": -1` to `LStickY`/`RStickY` in `wow/GamePadConfig_PadWake.json`) and re-run `make install-wow`.
- **Rear paddles & extra buttons:** `GR` → `PADPADDLE1` (`b18`), `GL` → `PADPADDLE2` (`b19`), `C` → `PADPADDLE3` (`b20`), `Capture` → `PADSOCIAL` (`b17`).
- **Daemon logs:** `~/Library/Logs/padwake.log`.

---

## Packaging, Signing, Legal & Naming Guide

See [docs/DISTRIBUTION_AND_LEGAL.md](docs/DISTRIBUTION_AND_LEGAL.md) for the complete roadmap covering:
- Turning this into a signed & notarized macOS menu-bar `.app` (Tier 1 vs Tier 2 DriverKit/virtual HID)
- Mac App Store vs Direct Distribution requirements & entitlements
- Legal, trademark, interoperability, and game ToS / anti-cheat checklist
- Catchy trademark-free app name shortlist & GitHub/Google discoverability tips
