# Packaging, Signing, Distribution, Legal & Naming Guide

> **Note:** This document summarizes practical macOS engineering, App Review, and intellectual-property considerations. It is not formal legal advice—consult an IP attorney before selling or distributing commercially.

---

## 1. Two Architecture Tiers for a macOS App

### Tier 1: Signed & Notarized Menu-Bar Utility App (Recommended Starting Point)

Wraps the native IOKit C core (`src/padwake_core.c`) in a SwiftUI/AppKit `NSStatusBar` menu-bar `.app` bundle. Works for World of Warcraft and other SDL2 games.

**Core features to include:**
- Menu-bar status icon (disconnected / asleep / awake)
- Player LED selector (`1`–`4`)
- Live button & stick input visualizer
- One-click game config installer (using `NSOpenPanel` if desired)
- Native **Launch at Login** using `ServiceManagement` (`SMAppService.mainApp`), replacing manual `~/Library/LaunchAgents/*.plist` scripts
- Automatic `SDL_JOYSTICK_MFI=0` session env setup (`launchctl setenv`) or per-launch env injection

**Code Signing & Notarization (Direct Distribution, outside Mac App Store):**
- **Personal use (your own Macs):** Free—ad-hoc signing (`codesign -s -`) or a free Apple ID signing certificate works locally.
- **Public distribution (zero Gatekeeper warnings):**
  1. Enroll in the **Apple Developer Program** ($99/year) to obtain a **Developer ID Application** certificate.
  2. Build as a **Universal Binary** (`arm64` + `x86_64`) via Xcode or `lipo`.
  3. Sign with **Hardened Runtime** (unsandboxed—no special Apple entitlement approvals required):
     ```bash
     codesign --force --options runtime --timestamp \
       --sign "Developer ID Application: Your Name (TEAMID)" \
       YourApp.app
     ```
  4. Notarize and staple (~1–2 min automated Apple check):
     ```bash
     ditto -c -k --keepParent YourApp.app YourApp.zip
     xcrun notarytool submit YourApp.zip --keychain-profile "notary" --wait
     xcrun stapler staple YourApp.app
     ```
  5. Distribute via `.dmg` / GitHub Releases / Homebrew Cask (optionally add **Sparkle** for signed in-app auto-updates).

---

### Tier 2: System-Wide Native `GCController` Virtual Gamepad (Every macOS Game)

Makes the controller appear natively to macOS `GameController.framework` across *all* macOS games (including non-SDL games, App Store / Apple Arcade games, and optionally Bluetooth LE) without needing `SDL_JOYSTICK_MFI=0`.

**Two implementation options:**
1. **Userspace Virtual HID (`IOHIDUserDevice`):** Translates HID Report `0x09` into a standard virtual HID gamepad descriptor recognized by `GCController`. Requires Apple-approved `com.apple.developer.hid.virtual.device` entitlement (or a privileged helper / virtual HID dext).
2. **DriverKit System Extension (`.dext`):** Embedded in `Contents/Library/SystemExtensions/` and activated via `OSSystemExtensionManager`. Matches the USB interface directly, sends the wake handshake automatically, and can support rumble/gyro cleanly.

**Main hurdle for Tier 2:**
- Requires the $99/year Developer Program **plus** submitting a formal entitlement request to Apple (`com.apple.developer.driverkit.transport.usb`, `com.apple.developer.driverkit.family.hid.device`, or `com.apple.developer.hid.virtual.device`).
- Apple manually reviews requests (typically days to ~2 weeks) and issues a custom provisioning profile tied to your App ID and Team ID.
- During local development without the entitlement, DriverKit extensions only load with SIP disabled (`systemextensionsctl developer on`).

---

## 2. Mac App Store vs Direct Distribution

**Direct Distribution (Developer ID + Notarization) is strongly recommended** over the Mac App Store:

| Consideration | Direct Distribution (Developer ID) | Mac App Store |
|---|---|---|
| **App Sandbox (Guideline 2.4.5)** | Optional (Hardened Runtime only) | **Mandatory** |
| **`launchctl setenv SDL_JOYSTICK_MFI 0`** | Works | **Blocked** by App Sandbox & Guideline 2.4.5 (cannot modify other apps' runtime environment) |
| **Writing game `WTF/` config files** | Works directly (or via `NSOpenPanel`) | Requires explicit `NSOpenPanel` user folder selection |
| **IOKit USB Vendor Interface 1** | Works with zero special entitlements | Requires Sandbox USB entitlement or approved DriverKit `.dext` |
| **DriverKit `.dext` approval** | Needs Apple entitlement approval | Needs Apple entitlement approval + App Review (Apple may decline overriding another vendor's VID/PID) |
| **Trademark scrutiny (Guideline 5.2)** | Standard trademark law applies | Strict App Review rejections on any third-party brand names or controller artwork |

---

## 3. Legal, IP & Game-ToS Checklist

1. **Interoperability & Clean-Room Code (Copyright / DMCA):**
   - Sending unencrypted USB initialization packets (`0x03 0x91 ...`, `0x09 0x91 ...`) so hardware you own interoperates with macOS is standard host-side interoperability (similar to SDL3, Linux `hid-nintendo`, and Steam Input).
   - **Never** bundle proprietary firmware, copyrighted assets, cryptographic/signing keys, or DRM/authentication bypasses (e.g., console dock VDM authentication or NFC/amiibo encryption keys).
   - Keep the codebase clean-room; if incorporating third-party libraries (e.g., SDL3 under zlib, or MIT/GPL code), strictly follow their license requirements.

2. **Trademarks (Highest Practical Risk):**
   - **Do not** use third-party trademarks (hardware manufacturers, console/controller brand names, or game titles) in your:
     - App name
     - Bundle identifier (`com.yourname.appname`)
     - Repository / domain name
     - App icon (avoid tracing official controller silhouettes or logos)
     - Source code identifiers/logs
   - **Do** use factual nominative compatibility descriptions in documentation/marketing (e.g., *"Compatible with ..."*) accompanied by a clear non-affiliation disclaimer.

3. **Game Terms of Service & Anti-Cheat Hygiene:**
   - **Safe:** Waking a standard USB HID gamepad, setting `SDL_JOYSTICK_MFI=0`, and generating documented game config files (`WTF/gamecontrollerdb.txt`, `WTF/GamePadConfig_*.json`). Maintain strict **1:1 input mapping** (one physical press = one game input).
   - **Never add:** `DYLD_INSERT_LIBRARIES` / code injection, game memory reading/writing, automated macros, turbo/rapid-fire, or multi-action sequences.

4. **Platform Shelf-Life:**
   - Apple historically adds native `GameController.framework` support for major controllers in subsequent macOS point releases. Factor this in before investing heavily in a DriverKit entitlement review or paid distribution.

---

## 4. Naming & GitHub / Google Discoverability

### Shortlist of Catchy, Trademark-Free Names

**Short & Self-Explanatory (best recall):**
- **PadWake** — 2 syllables, clear purpose, ideal menu-bar app feel.
- **HIDSpark** — distinctive on Google/GitHub, evokes sparking a silent HID controller awake.
- **ProWake** — subtle wink to pro-style controllers without infringing trademarks.

**Clever / Insider Nod:**
- **SlotOne** — nods to lighting up the Player 1 LED after the handshake.
- **Padforge** — clean utility brand with a subtle RPG nod.
- **NudgeHID** — playful nod to nudging a sleeping USB HID device awake.

**Classic Indie Mac Utility Feel:**
- **CocoaPad** — classic macOS developer flavor, easy to Google.
- **PadPilot** — scales well if you later add Bluetooth, LEDs, or per-game presets.
- **GripBridge** — nods to rear grip paddles (`GL`/`GR`) + bridging into macOS games.

### Discoverability Formula
Use a **unique, trademark-free project name** paired with a **descriptive GitHub repo description and topics** so users searching for controller support find it immediately and remember the short name later:
- **Example repo description:** `PadWake — Native macOS USB wake utility & gamepad configurator for Switch 2 Pro Controllers (zero dependencies).`
- **Suggested GitHub topics:** `macos`, `iokit`, `hid`, `usb`, `gamepad`, `sdl2`, `pro-controller`, `nintendo-switch-2`, `world-of-warcraft`.
