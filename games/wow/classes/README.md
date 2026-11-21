# World of Warcraft — Controller Class Profiles

Controller profiles for **World of Warcraft** (**Forever**, **Classic**, and **Retail**), built for Switch 2 Pro Controller (`057E:2069`) with rear paddles (`GR`, `GL`, `C`) and both native `C_GamePad` and **ConsolePort** layouts.

## Universal Controller Backbone

Every class shares the same 4-layer modifier structure so switching specs or alts never breaks muscle memory:

| Input | Physical Button | Function |
|---|---|---|
| `PADLTRIGGER` | **ZL** | Hold for **SHIFT** layer (`MULTIACTIONBAR1BUTTON1..8`) |
| `PADRTRIGGER` | **ZR** | Hold for **CTRL** layer (`MULTIACTIONBAR2BUTTON1..8`) |
| `ZL + ZR` | **ZL + ZR** | Hold for **SHIFT+CTRL** layer (`MULTIACTIONBAR3BUTTON1..4`) |
| `PAD1`–`PAD4` | **B / A / Y / X** | Core rotational abilities (Base, ZL, ZR, ZL+ZR — matches Switch 2 diamond in both position & letter) |
| `PADDUP`–`PADDLEFT` | **D-Pad** | Combat utility, traps/totems/seals, party targeting (`ZL+D-Pad` for healers) |
| `PADRSHOULDER` | **R** | Target Nearest Enemy (`ZL+R` = Previous Enemy, `ZR+R` = Nearest Friend) |
| `PADLSHOULDER` | **L** | Interact with Target (`SoftTargetInteract=3`; `ZL+L` = Self, `ZR+L` = Assist) |
| `PADLSTICK` / `PADRSTICK` | **L3 / R3** | Auto-Run / Jump |
| `PADPADDLE1` | **GR** | Class Interrupt / Instant Panic macro (`ZL+GR` = Signature Forever macro) |
| `PADPADDLE2` | **GL** | Class Mobility / Stance / Pet / Form macro (`ZL+GL` = Secondary class macro) |
| `PADPADDLE3` | **C** | World Map (`ZL+C` = Bags, `ZR+C` = Character) |
| `PADFORWARD` / `PADBACK` | **`+` / `-`** | Game Menu / All Bags |

## Class Profiles

| Class | Profile | Strafe Angle | Soft Target Friend | GR (`PADPADDLE1`) | GL (`PADPADDLE2`) |
|---|---|---|---|---|---|
| **Warrior** | [warrior.json](warrior.json) | `0°` (melee) | `0` | `PW_WAR_INT` (Shield Bash / Pummel) | `PW_WAR_CHG` (Charge / Intercept) |
| **Paladin** | [paladin.json](paladin.json) | `0°` (melee) | `1` (hybrid) | `PW_PAL_STUN` (Hammer of Justice) | `PW_PAL_CLN` (Smart Cleanse) |
| **Hunter** | [hunter.json](hunter.json) | `115°` (kite) | `0` | `PW_HNT_FD` (Stopcast Feign Death) | `PW_HNT_PET` (Pet Attack / Follow) |
| **Rogue** | [rogue.json](rogue.json) | `0°` (melee) | `0` | `PW_ROG_KICK` (Kick) | `PW_ROG_STL` (Stealth / Vanish) |
| **Priest** | [priest.json](priest.json) | `115°` (caster) | `3` (healer) | `PW_PRI_FEAR` (Psychic Scream) | `PW_PRI_SHLD` (Smart PW:Shield) |
| **Shaman** | [shaman.json](shaman.json) | `0°` (hybrid) | `1` (hybrid) | `PW_SHM_INT` (Stopcast Earth Shock) | `PW_SHM_WLF` (Indoor Ghost Wolf) |
| **Mage** | [mage.json](mage.json) | `115°` (kite) | `0` | `PW_MAG_CS` (Stopcast Counterspell) | `PW_MAG_BLK` (Stopcast Blink) |
| **Warlock** | [warlock.json](warlock.json) | `115°` (caster) | `0` | `PW_WLK_FEAR` (Stopcast Fear) | `PW_WLK_PET` (Pet Attack / Follow) |
| **Druid** | [druid.json](druid.json) | `0°` (feral/hybrid) | `1` (hybrid) | `PW_DRU_CC` (Form-aware CC) | `PW_DRU_TRV` (Aquatic / Travel / Cat) |
| **Death Knight** | [deathknight.json](deathknight.json) | `0°` (melee/tank) | `0` | `PW_DK_INT` (Mind Freeze) | `PW_DK_GRIP` (Death Grip) |

## Applying In-Game (Native or ConsolePort)

Install via **PadWake.app** (pick Forever, Classic, or Retail and click **Setup**) or `./scripts/install-wow.sh`, then run in chat:

```text
/padwake apply
```

`PadWakeProfiles` automatically detects your logged-in class and level, scans your spellbook for the highest trained rank of every ability, applies the optimized `C_GamePad` CVars, saves your `PAD*` bindings via Blizzard's official API (immune to cloud `synchronizeBindings` overwrites), creates your 4 `PW_*` starter macros, and **auto-populates your controller action bars** (including Stealth, Stance, Cat/Bear, and Shadowform bonus bars).

After leveling up or visiting your class trainer, run `/padwake bars` (or `/padwake bars --fill` to only fill empty slots) to upgrade your bars to your newly trained spells. If **ConsolePort** is loaded, it automatically preserves ConsolePort's `PAD*` bindings while still applying class CVars, starter macros, and action bars.
