-- PadWakeProfiles.lua
-- Lightweight, zero-dependency companion addon for PadWake (057E:2069 USB Gamepad).
-- Applies World of Warcraft (Forever, Classic & Retail) class-optimized C_GamePad CVars,
-- native PAD* bindings (immune to synchronizeBindings cloud overwrites), starter macros,
-- DialogueUI Switch auto-config, and level- & spec-aware action bars.

local ADDON_NAME, ns = ...
local PREFIX = "|cff38bdf8[PadWake]|r "

local function printMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

local function isConsolePortLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("ConsolePort") == true
    elseif IsAddOnLoaded then
        return IsAddOnLoaded("ConsolePort") == true
    end
    return false
end

local function isForeverGamepadUI()
    if C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle then
        return C_InputInterfaceStyle.GetCurrentStyle() == 1
    end
    return GetCVar and GetCVar("InputDeviceInterfaceStyle") == "1"
end

-- Detects Nintendo Switch 2 Pro Controller (VID 0x057E = 1406, PID 0x2069 = 8297)
local function isSwitch2Connected()
    if not (C_GamePad and C_GamePad.GetAllDeviceIDs and C_GamePad.GetDeviceRawState) then
        return false
    end
    local okIds, ids = pcall(C_GamePad.GetAllDeviceIDs)
    if not okIds or type(ids) ~= "table" then
        return false
    end
    for _, id in ipairs(ids) do
        local okState, raw = pcall(C_GamePad.GetDeviceRawState, id)
        if okState and type(raw) == "table" and raw.vendorID == 1406 and raw.productID == 8297 then
            return true
        end
    end
    return false
end

local function configureDialogueUISwitchMode(explicitCommand)
    if type(DialogueUI_DB) ~= "table" then
        if explicitCommand then
            printMsg("DialogueUI addon is not loaded — nothing to configure.")
        end
        return false
    end

    if not explicitCommand and not isSwitch2Connected() then
        return false
    end

    if DialogueUI_DB.InputDevice == 4 then
        if explicitCommand then
            printMsg("DialogueUI is already set to Switch mode (4: A=Accept, B=Exit).")
        end
        return true
    end

    local prev = tostring(DialogueUI_DB.InputDevice or "default")
    DialogueUI_DB.InputDevice = 4 -- 4 = Nintendo Switch layout (PAD2/A confirm, PAD1/B cancel)
    printMsg(string.format("Set DialogueUI InputDevice to Switch (4, was %s) so A=Accept and B=Exit match your Switch 2 controller. Type '/reload' to activate.", prev))
    return true
end

local function safeSetCVar(key, value)
    if C_CVar and C_CVar.GetCVarInfo then
        if C_CVar.GetCVarInfo(key) == nil then
            return false
        end
    end
    local ok = pcall(SetCVar, key, tostring(value))
    return ok
end

local function levelTierLabel(level)
    if level < 10 then
        return "Starter (L1-9)"
    elseif level < 20 then
        return "Early Leveling (L10-19)"
    elseif level < 40 then
        return "Mid Leveling (L20-39)"
    elseif level < 60 then
        return "Late Leveling / Dual-Spec (L40-59)"
    end
    return "Endgame (L60)"
end

-- Base C_GamePad CVars shared across all 9 WoW: Forever classes
local BASE_CVARS = {
    GamePadEnable = "1",
    GamePadEmulateShift = "PADLTRIGGER",
    GamePadEmulateCtrl = "PADRTRIGGER",
    GamePadEmulateAlt = "NONE",
    GamePadEmulateTapWindowMs = "350",
    GamePadCursorAutoEnable = "1",
    GamePadCursorCentering = "1",
    SoftTargetEnemy = "3",
    SoftTargetInteract = "3",
}

-- Universal 4-layer ConsolePort-compatible crossbar bindings (32 combat slots + paddles)
local BASE_BINDINGS = {
    -- Base layer (Action Bar 1: slots 1..8, or bonus bar 73..104 in stance/stealth/form)
    { "PAD1", "ACTIONBUTTON1" },
    { "PAD2", "ACTIONBUTTON2" },
    { "PAD3", "ACTIONBUTTON3" },
    { "PAD4", "ACTIONBUTTON4" },
    { "PADDUP", "ACTIONBUTTON5" },
    { "PADDRIGHT", "ACTIONBUTTON6" },
    { "PADDDOWN", "ACTIONBUTTON7" },
    { "PADDLEFT", "ACTIONBUTTON8" },

    -- SHIFT layer (Hold ZL / PADLTRIGGER -> Bottom-Left Action Bar: slots 61..68)
    { "SHIFT-PAD1", "MULTIACTIONBAR1BUTTON1" },
    { "SHIFT-PAD2", "MULTIACTIONBAR1BUTTON2" },
    { "SHIFT-PAD3", "MULTIACTIONBAR1BUTTON3" },
    { "SHIFT-PAD4", "MULTIACTIONBAR1BUTTON4" },
    { "SHIFT-PADDUP", "MULTIACTIONBAR1BUTTON5" },
    { "SHIFT-PADDRIGHT", "MULTIACTIONBAR1BUTTON6" },
    { "SHIFT-PADDDOWN", "MULTIACTIONBAR1BUTTON7" },
    { "SHIFT-PADDLEFT", "MULTIACTIONBAR1BUTTON8" },

    -- CTRL layer (Hold ZR / PADRTRIGGER -> Bottom-Right Action Bar: slots 49..56)
    { "CTRL-PAD1", "MULTIACTIONBAR2BUTTON1" },
    { "CTRL-PAD2", "MULTIACTIONBAR2BUTTON2" },
    { "CTRL-PAD3", "MULTIACTIONBAR2BUTTON3" },
    { "CTRL-PAD4", "MULTIACTIONBAR2BUTTON4" },
    { "CTRL-PADDUP", "MULTIACTIONBAR2BUTTON5" },
    { "CTRL-PADDRIGHT", "MULTIACTIONBAR2BUTTON6" },
    { "CTRL-PADDDOWN", "MULTIACTIONBAR2BUTTON7" },
    { "CTRL-PADDLEFT", "MULTIACTIONBAR2BUTTON8" },

    -- SHIFT+CTRL layer (Hold ZL + ZR -> Right Action Bar: slots 25..32)
    { "SHIFT-CTRL-PAD1", "MULTIACTIONBAR3BUTTON1" },
    { "SHIFT-CTRL-PAD2", "MULTIACTIONBAR3BUTTON2" },
    { "SHIFT-CTRL-PAD3", "MULTIACTIONBAR3BUTTON3" },
    { "SHIFT-CTRL-PAD4", "MULTIACTIONBAR3BUTTON4" },
    { "SHIFT-CTRL-PADDUP", "MULTIACTIONBAR3BUTTON5" },
    { "SHIFT-CTRL-PADDRIGHT", "MULTIACTIONBAR3BUTTON6" },
    { "SHIFT-CTRL-PADDDOWN", "MULTIACTIONBAR3BUTTON7" },
    { "SHIFT-CTRL-PADDLEFT", "MULTIACTIONBAR3BUTTON8" },

    -- Shoulders, Sticks, Menu & C Button
    { "PADRSHOULDER", "TARGETNEARESTENEMY" },
    { "SHIFT-PADRSHOULDER", "TARGETPREVIOUSENEMY" },
    { "CTRL-PADRSHOULDER", "TARGETNEARESTFRIEND" },
    { "PADLSHOULDER", "INTERACTTARGET" },
    { "SHIFT-PADLSHOULDER", "TARGETSELF" },
    { "CTRL-PADLSHOULDER", "ASSISTTARGET" },
    { "PADLSTICK", "TOGGLEAUTORUN" },
    { "PADRSTICK", "JUMP" },
    { "PADFORWARD", "TOGGLEGAMEMENU" },
    { "PADBACK", "OPENALLBAGS" },
    { "SHIFT-PADBACK", "TOGGLEWORLDMAP" },
    { "PADPADDLE3", "TOGGLEWORLDMAP" },
    { "SHIFT-PADPADDLE3", "OPENALLBAGS" },
    { "CTRL-PADPADDLE3", "TOGGLECHARACTER0" },
}

-- Action slot offsets for standard bars & stance/stealth/form bonus bars:
--   base   (1..8):   Action Bar 1 (B, A, Y, X, Up, Right, Down, Left)
--   shift  (61..68): ZL / SHIFT layer (MultiBarBottomLeft)
--   ctrl   (49..56): ZR / CTRL layer (MultiBarBottomRight)
--   both   (25..32): ZL+ZR / SHIFT+CTRL layer (MultiBarRight)
--   bonus1 (73..80): Rogue Stealth / Warrior Battle Stance / Druid Cat Form / Priest Shadowform
--   bonus2 (85..92): Warrior Defensive Stance
--   bonus3 (97..104): Warrior Berserker Stance / Druid Bear & Dire Bear Form
local BAR_OFFSETS = {
    base   = 0,
    shift  = 60,
    ctrl   = 48,
    both   = 24,
    bonus1 = 72,
    bonus2 = 84,
    bonus3 = 96,
}

-- All 9 World of Warcraft: Forever class profiles with level-adaptive priority skill lists.
-- Each slot holds an ordered list of candidate abilities (endgame/spec -> level 1 fallback).
-- Prefixes: "macro:<NAME>" picks up a macro, "item:<ID>" picks up an owned item (e.g. 6948 = Hearthstone).
local CLASS_PROFILES = {
    WARRIOR = {
        name = "Warrior",
        summary = "Melee/Tank (0 deg turn) | GR: Shield Bash/Pummel | GL: Charge/Intercept | ZL+GR: Victory Rush/Execute | ZL+GL: Stance Toggle",
        cvars = {
            GamePadFaceMovementMaxAngle = "0",
            SoftTargetFriend = "0",
        },
        paddles = {
            { "PADPADDLE1", "PW_WAR_INT" },
            { "PADPADDLE2", "PW_WAR_CHG" },
            { "SHIFT-PADPADDLE1", "PW_WAR_VR" },
            { "SHIFT-PADPADDLE2", "PW_WAR_STN" },
        },
        macros = {
            { name = "PW_WAR_INT", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast [equipped:Shields] Shield Bash; Pummel" },
            { name = "PW_WAR_CHG", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/startattack\n/cast [nocombat] Charge; Intercept" },
            { name = "PW_WAR_VR",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/startattack\n/cast Victory Rush\n/cast Execute" },
            { name = "PW_WAR_STN", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast [stance:1] Berserker Stance; Battle Stance" },
        },
        bars = {
            base = {
                [1] = { "Mortal Strike", "Bloodthirst", "Shield Slam", "Heroic Strike", "Attack" },
                [2] = { "Slam", "Victory Rush", "Heroic Strike", "Rend" },
                [3] = { "Overpower", "Thunder Clap", "Cleave", "Rend" },
                [4] = { "macro:PW_WAR_VR", "Execute", "Victory Rush", "Rend" },
                [5] = { "Rend", "Sunder Armor", "Hamstring" },
                [6] = { "Hamstring", "Piercing Howl", "Thunder Clap" },
                [7] = { "Battle Shout", "Commanding Shout" },
                [8] = { "Charge", "Mocking Blow", "Thunder Clap" },
            },
            bonus1 = { -- Battle Stance
                [1] = { "Mortal Strike", "Bloodthirst", "Heroic Strike", "Attack" },
                [2] = { "Slam", "Victory Rush", "Heroic Strike", "Rend" },
                [3] = { "Overpower", "Thunder Clap", "Cleave" },
                [4] = { "macro:PW_WAR_VR", "Execute", "Victory Rush", "Rend" },
                [5] = { "Rend", "Sunder Armor" },
                [6] = { "Hamstring", "Piercing Howl" },
                [7] = { "Battle Shout", "Commanding Shout" },
                [8] = { "Charge", "Mocking Blow" },
            },
            bonus2 = { -- Defensive Stance
                [1] = { "Shield Slam", "Devastate", "Sunder Armor", "Heroic Strike", "Attack" },
                [2] = { "Revenge", "Heroic Strike" },
                [3] = { "Thunder Clap", "Cleave", "Demoralizing Shout" },
                [4] = { "Shield Block", "Last Stand", "Shield Wall" },
                [5] = { "Taunt", "Mocking Blow" },
                [6] = { "Disarm", "Shield Bash" },
                [7] = { "Demoralizing Shout", "Battle Shout" },
                [8] = { "Challenging Shout", "Sunder Armor" },
            },
            bonus3 = { -- Berserker Stance
                [1] = { "Bloodthirst", "Mortal Strike", "Heroic Strike", "Attack" },
                [2] = { "Whirlwind", "Slam", "Cleave" },
                [3] = { "macro:PW_WAR_VR", "Execute", "Victory Rush" },
                [4] = { "Berserker Rage", "Death Wish", "Recklessness" },
                [5] = { "Intercept", "Charge" },
                [6] = { "Pummel", "Hamstring" },
                [7] = { "Battle Shout", "Commanding Shout" },
                [8] = { "Intimidating Shout", "Piercing Howl" },
            },
            shift = {
                [1] = { "Battle Stance" },
                [2] = { "Defensive Stance" },
                [3] = { "Berserker Stance" },
                [4] = { "Berserker Rage" },
                [5] = { "Bloodrage" },
                [6] = { "Demoralizing Shout", "Disarm" },
                [7] = { "Sweeping Strikes", "Shield Block", "Cleave" },
                [8] = { "Intimidating Shout", "Taunt" },
            },
            ctrl = {
                [1] = { "Shield Wall", "Retaliation", "Recklessness" },
                [2] = { "Last Stand", "Death Wish" },
                [3] = { "Shoot", "Throw" },
                [4] = { "Challenging Shout", "Mocking Blow" },
                [5] = { "macro:PW_WAR_CHG" },
                [6] = { "macro:PW_WAR_INT" },
                [7] = { "item:6948" },
                [8] = { "macro:PW_WAR_STN" },
            },
        },
    },

    PALADIN = {
        name = "Paladin",
        summary = "Hybrid Melee/Tank/Heal (0 deg, SoftFriend=1) | GR: HoJ | GL: Smart Cleanse | ZL+GR: Smart Flash of Light | ZL+GL: Divine Shield",
        cvars = {
            GamePadFaceMovementMaxAngle = "0",
            SoftTargetFriend = "1",
        },
        paddles = {
            { "PADPADDLE1", "PW_PAL_STUN" },
            { "PADPADDLE2", "PW_PAL_CLN" },
            { "SHIFT-PADPADDLE1", "PW_PAL_HEAL" },
            { "SHIFT-PADPADDLE2", "PW_PAL_BUB" },
        },
        macros = {
            { name = "PW_PAL_STUN", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Hammer of Justice\n/stopcasting\n/cast Hammer of Justice" },
            { name = "PW_PAL_CLN",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Cleanse\n/cast [@mouseover,help,nodead][help,nodead][@player] Cleanse" },
            { name = "PW_PAL_HEAL", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Flash of Light\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash of Light" },
            { name = "PW_PAL_BUB",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Divine Shield\n/stopcasting\n/cast Divine Shield" },
        },
        bars = {
            base = {
                [1] = { "Judgement", "Crusader Strike", "Seal of Righteousness", "Attack" },
                [2] = { "Seal of Command", "Seal of Righteousness", "Seal of the Crusader" },
                [3] = { "Consecration", "Holy Shock", "Exorcism", "Hammer of Justice" },
                [4] = { "Hammer of Wrath", "Exorcism", "Holy Shock", "Holy Light" },
                [5] = { "Seal of the Crusader", "Seal of Wisdom", "Seal of Light" },
                [6] = { "Hand of Reckoning", "Righteous Defense", "Holy Shield", "Hammer of Justice" },
                [7] = { "macro:PW_PAL_HEAL", "Flash of Light", "Holy Light" },
                [8] = { "Holy Light" },
            },
            shift = {
                [1] = { "Blessing of Freedom", "Blessing of Protection" },
                [2] = { "Blessing of Protection", "Divine Protection" },
                [3] = { "Blessing of Sacrifice", "Turn Undead" },
                [4] = { "Divine Favor", "Avenging Wrath", "Divine Protection" },
                [5] = { "Blessing of Kings", "Blessing of Might" },
                [6] = { "Blessing of Wisdom", "Blessing of Sanctuary" },
                [7] = { "Cleanse", "Purify" },
                [8] = { "Sense Undead", "Turn Undead" },
            },
            ctrl = {
                [1] = { "Lay on Hands" },
                [2] = { "Divine Shield", "Divine Protection" },
                [3] = { "Retribution Aura", "Devotion Aura" },
                [4] = { "Concentration Aura", "Sanctity Aura", "Devotion Aura" },
                [5] = { "Summon Charger", "Summon Warhorse" },
                [6] = { "Righteous Fury" },
                [7] = { "Redemption" },
                [8] = { "item:6948" },
            },
        },
    },

    HUNTER = {
        name = "Hunter",
        summary = "Ranged Kiter / Melee Surv (115 deg kite) | GR: Feign Death | GL: Pet Attack/Follow | ZL+GR: Combat Freezing Trap | ZL+GL: Hunter's Mark",
        cvars = {
            GamePadFaceMovementMaxAngle = "115",
            SoftTargetFriend = "0",
        },
        paddles = {
            { "PADPADDLE1", "PW_HNT_FD" },
            { "PADPADDLE2", "PW_HNT_PET" },
            { "SHIFT-PADPADDLE1", "PW_HNT_TRAP" },
            { "SHIFT-PADPADDLE2", "PW_HNT_MARK" },
        },
        macros = {
            { name = "PW_HNT_FD",   icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Feign Death\n/stopcasting\n/petpassive\n/cast Feign Death" },
            { name = "PW_HNT_PET",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/petattack [harm,nodead]\n/petfollow [noharm][dead]" },
            { name = "PW_HNT_TRAP", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Freezing Trap\n/stopcasting\n/cast Freezing Trap" },
            { name = "PW_HNT_MARK", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Hunter's Mark\n/cast Hunter's Mark\n/petattack [pet,harm,nodead]" },
        },
        bars = {
            base = {
                [1] = { "Auto Shot", "Raptor Strike", "Attack" },
                [2] = { "Aimed Shot", "Arcane Shot", "Raptor Strike" },
                [3] = { "Multi-Shot", "Arcane Shot", "Mongoose Bite", "Wing Clip" },
                [4] = { "Serpent Sting", "Scorpid Sting", "Viper Sting", "Raptor Strike" },
                [5] = { "Concussive Shot", "Wing Clip" },
                [6] = { "Hunter's Mark" },
                [7] = { "Disengage", "Deterrence", "Wing Clip" },
                [8] = { "Scatter Shot", "Tranquilizing Shot", "Flare" },
            },
            shift = {
                [1] = { "Freezing Trap", "Immolation Trap" },
                [2] = { "Frost Trap", "Explosive Trap" },
                [3] = { "Immolation Trap", "Explosive Trap" },
                [4] = { "Volley", "Distracting Shot" },
                [5] = { "Aspect of the Hawk", "Aspect of the Monkey" },
                [6] = { "Aspect of the Cheetah", "Aspect of the Pack" },
                [7] = { "Aspect of the Monkey", "Aspect of the Wild" },
                [8] = { "Mend Pet", "Call Pet", "Revive Pet" },
            },
            ctrl = {
                [1] = { "Rapid Fire", "Bestial Wrath" },
                [2] = { "Intimidation", "Readiness", "Counterattack" },
                [3] = { "Call Pet", "Revive Pet", "Feed Pet" },
                [4] = { "Dismiss Pet", "Tame Beast" },
                [5] = { "Track Humanoids", "Track Beasts" },
                [6] = { "Scare Beast", "Flare" },
                [7] = { "item:6948" },
                [8] = { "Eagle Eye", "Eyes of the Beast" },
            },
        },
    },

    ROGUE = {
        name = "Rogue",
        summary = "Melee Stealth DPS (0 deg turn) | GR: Kick | GL: Stealth/Vanish | ZL+GR: Sprint | ZL+GL: Nearest Sap",
        cvars = {
            GamePadFaceMovementMaxAngle = "0",
            SoftTargetFriend = "0",
        },
        paddles = {
            { "PADPADDLE1", "PW_ROG_KICK" },
            { "PADPADDLE2", "PW_ROG_STL" },
            { "SHIFT-PADPADDLE1", "PW_ROG_SPR" },
            { "SHIFT-PADPADDLE2", "PW_ROG_SAP" },
        },
        macros = {
            { name = "PW_ROG_KICK", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Kick\n/startattack\n/cast Kick" },
            { name = "PW_ROG_STL",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast [combat] Vanish; Stealth" },
            { name = "PW_ROG_SPR",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Sprint\n/cast Sprint" },
            { name = "PW_ROG_SAP",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Sap\n/cleartarget\n/targetenemy\n/cast Sap" },
        },
        bars = {
            base = {
                [1] = { "Mutilate", "Hemorrhage", "Sinister Strike", "Backstab", "Attack" },
                [2] = { "Envenom", "Eviscerate" },
                [3] = { "Slice and Dice", "Rupture", "Gouge", "Throw", "Shoot" },
                [4] = { "Kidney Shot", "Gouge", "Riposte", "Feint", "Backstab" },
                [5] = { "Backstab", "Riposte", "Feint", "Hemorrhage" },
                [6] = { "Blind", "Gouge", "Kick" },
                [7] = { "Evasion", "Feint", "Sprint" },
                [8] = { "Throw", "Shoot", "Expose Armor", "Distract" },
            },
            bonus1 = { -- Stealth Bar
                [1] = { "Cheap Shot", "Ambush", "Garrote", "Sinister Strike" },
                [2] = { "Ambush", "Garrote", "Backstab", "Eviscerate" },
                [3] = { "Garrote", "Pick Pocket", "Sap" },
                [4] = { "macro:PW_ROG_SAP", "Sap", "Pick Pocket" },
                [5] = { "Distract", "Pick Pocket" },
                [6] = { "Sprint", "Blind" },
                [7] = { "Premeditation", "Cold Blood", "Evasion" },
                [8] = { "Pick Lock", "Detect Traps" },
            },
            shift = {
                [1] = { "Evasion" },
                [2] = { "Sprint" },
                [3] = { "Vanish", "Stealth" },
                [4] = { "Preparation", "Adrenaline Rush", "Blade Flurry", "Cold Blood" },
                [5] = { "Rupture", "Expose Armor" },
                [6] = { "Kick" },
                [7] = { "Stealth" },
                [8] = { "Distract", "Sap" },
            },
            ctrl = {
                [1] = { "Blade Flurry", "Ghostly Strike" },
                [2] = { "Adrenaline Rush", "Cold Blood" },
                [3] = { "Pick Lock", "Poisons" },
                [4] = { "Detect Traps", "Disarm Trap" },
                [5] = { "macro:PW_ROG_KICK" },
                [6] = { "macro:PW_ROG_STL" },
                [7] = { "item:6948" },
                [8] = { "macro:PW_ROG_SAP" },
            },
        },
    },

    PRIEST = {
        name = "Priest",
        summary = "Healer/Shadow (115 deg, SoftFriend=3, ZL+D-Pad=Party 1-4) | GR: Psychic Scream | GL: Smart PW:Shield | ZL+GR: Smart Dispel | ZL+GL: Smart Flash Heal",
        cvars = {
            GamePadFaceMovementMaxAngle = "115",
            SoftTargetFriend = "3",
        },
        extraBindings = {
            { "SHIFT-PADDUP", "TARGETPARTYMEMBER1" },
            { "SHIFT-PADDRIGHT", "TARGETPARTYMEMBER2" },
            { "SHIFT-PADDDOWN", "TARGETPARTYMEMBER3" },
            { "SHIFT-PADDLEFT", "TARGETPARTYMEMBER4" },
        },
        paddles = {
            { "PADPADDLE1", "PW_PRI_FEAR" },
            { "PADPADDLE2", "PW_PRI_SHLD" },
            { "SHIFT-PADPADDLE1", "PW_PRI_DISP" },
            { "SHIFT-PADPADDLE2", "PW_PRI_HEAL" },
        },
        macros = {
            { name = "PW_PRI_FEAR", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Psychic Scream\n/stopcasting\n/cast Psychic Scream" },
            { name = "PW_PRI_SHLD", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Power Word: Shield\n/cast [@mouseover,help,nodead][help,nodead][@player] Power Word: Shield" },
            { name = "PW_PRI_DISP", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Dispel Magic\n/cast [@mouseover,exists,nodead][exists,nodead][@player] Dispel Magic" },
            { name = "PW_PRI_HEAL", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Flash Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash Heal" },
        },
        bars = {
            base = {
                [1] = { "Flash Heal", "Lesser Heal", "Smite" },
                [2] = { "Penance", "Mind Blast", "Smite" },
                [3] = { "Renew", "Shadow Word: Pain" },
                [4] = { "macro:PW_PRI_SHLD", "Power Word: Shield", "Smite" },
                [5] = { "Greater Heal", "Heal", "Devouring Plague", "Lesser Heal" },
                [6] = { "macro:PW_PRI_DISP", "Dispel Magic", "Silence" },
                [7] = { "Shoot", "Smite" },
                [8] = { "Fade", "Shadowform" },
            },
            bonus1 = { -- Shadowform
                [1] = { "Mind Flay", "Mind Blast", "Smite" },
                [2] = { "Mind Blast" },
                [3] = { "Shadow Word: Pain" },
                [4] = { "Devouring Plague", "Vampiric Embrace" },
                [5] = { "Silence", "Psychic Scream" },
                [6] = { "Dispel Magic" },
                [7] = { "Shoot" },
                [8] = { "Fade" },
            },
            shift = {
                [1] = { "Prayer of Healing", "Holy Nova", "Heal" },
                [2] = { "Abolish Disease", "Cure Disease" },
                [3] = { "Fear Ward" },
                [4] = { "Mind Control", "Shackle Undead", "Mind Soothe" },
            },
            ctrl = {
                [1] = { "Inner Focus", "Power Infusion" },
                [2] = { "Desperate Prayer", "Vampiric Embrace" },
                [3] = { "Power Word: Fortitude" },
                [4] = { "Inner Fire", "Divine Spirit", "Shadow Protection" },
                [5] = { "Shadowform", "Divine Spirit" },
                [6] = { "Resurrection" },
                [7] = { "item:6948" },
                [8] = { "Levitate", "Mind Vision" },
            },
        },
    },

    SHAMAN = {
        name = "Shaman",
        summary = "Enh/Ele/Resto (0 deg, SoftFriend=1) | GR: Stopcast Earth Shock | GL: Indoor Ghost Wolf | ZL+GR: Smart Heal | ZL+GL: Totem Set",
        cvars = {
            GamePadFaceMovementMaxAngle = "0",
            SoftTargetFriend = "1",
        },
        paddles = {
            { "PADPADDLE1", "PW_SHM_INT" },
            { "PADPADDLE2", "PW_SHM_WLF" },
            { "SHIFT-PADPADDLE1", "PW_SHM_HEAL" },
            { "SHIFT-PADPADDLE2", "PW_SHM_TOT" },
        },
        macros = {
            { name = "PW_SHM_INT",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Earth Shock\n/stopcasting\n/cast Earth Shock" },
            { name = "PW_SHM_WLF",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Ghost Wolf\n/cast Ghost Wolf" },
            { name = "PW_SHM_HEAL", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Lesser Healing Wave\n/cast [@mouseover,help,nodead][help,nodead][@player] Lesser Healing Wave" },
            { name = "PW_SHM_TOT",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/castsequence reset=6 Strength of Earth Totem, Windfury Totem, Mana Spring Totem, Searing Totem" },
        },
        bars = {
            base = {
                [1] = { "Stormstrike", "Lightning Bolt", "Attack" },
                [2] = { "Lava Burst", "Earth Shock" },
                [3] = { "Flame Shock", "Chain Lightning" },
                [4] = { "Frost Shock", "Purge", "Lightning Bolt" },
                [5] = { "Earthbind Totem", "Tremor Totem", "Stoneclaw Totem" },
                [6] = { "Grounding Totem", "Searing Totem" },
                [7] = { "macro:PW_SHM_HEAL", "Riptide", "Lesser Healing Wave", "Healing Wave" },
                [8] = { "Windfury Totem", "Grace of Air Totem", "Healing Stream Totem" },
            },
            shift = {
                [1] = { "Strength of Earth Totem", "Stoneskin Totem" },
                [2] = { "Searing Totem", "Fire Nova Totem", "Magma Totem" },
                [3] = { "Cure Poison", "Cure Disease" },
                [4] = { "Water Shield", "Lightning Shield" },
                [5] = { "Healing Wave" },
                [6] = { "Chain Heal", "Riptide" },
                [7] = { "Mana Spring Totem", "Healing Stream Totem" },
                [8] = { "Tremor Totem", "Poison Cleansing Totem" },
            },
            ctrl = {
                [1] = { "Elemental Mastery", "Nature's Swiftness" },
                [2] = { "Mana Tide Totem", "Shamanistic Rage" },
                [3] = { "Windfury Weapon", "Flametongue Weapon", "Rockbiter Weapon" },
                [4] = { "Astral Recall" },
                [5] = { "Ghost Wolf" },
                [6] = { "Totemic Recall" },
                [7] = { "Ancestral Spirit" },
                [8] = { "item:6948" },
            },
        },
    },

    MAGE = {
        name = "Mage",
        summary = "Ranged/AoE Kiter (115 deg kite) | GR: Stopcast Counterspell | GL: Stopcast Blink | ZL+GR: Ice Block Toggle | ZL+GL: Polymorph",
        cvars = {
            GamePadFaceMovementMaxAngle = "115",
            SoftTargetFriend = "0",
        },
        paddles = {
            { "PADPADDLE1", "PW_MAG_CS" },
            { "PADPADDLE2", "PW_MAG_BLK" },
            { "SHIFT-PADPADDLE1", "PW_MAG_IB" },
            { "SHIFT-PADPADDLE2", "PW_MAG_POLY" },
        },
        macros = {
            { name = "PW_MAG_CS",   icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Counterspell\n/stopcasting\n/cast Counterspell" },
            { name = "PW_MAG_BLK",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Blink\n/stopcasting\n/cast Blink" },
            { name = "PW_MAG_IB",   icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Ice Block\n/stopcasting\n/cancelaura Ice Block\n/cast Ice Block" },
            { name = "PW_MAG_POLY", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Polymorph\n/cast [@mouseover,harm,nodead][harm,nodead] Polymorph" },
        },
        bars = {
            base = {
                [1] = { "Frostfire Bolt", "Frostbolt", "Fireball", "Arcane Blast" },
                [2] = { "Ice Lance", "Fire Blast", "Arcane Missiles" },
                [3] = { "Cone of Cold", "Blast Wave", "Arcane Explosion" },
                [4] = { "Frost Nova", "Scorch", "Pyroblast" },
                [5] = { "Blizzard", "Flamestrike", "Arcane Explosion" },
                [6] = { "Polymorph" },
                [7] = { "Ice Barrier", "Mana Shield", "Frost Armor" },
                [8] = { "Remove Lesser Curse", "Shoot" },
            },
            shift = {
                [1] = { "Frost Nova" },
                [2] = { "Ice Block", "Cold Snap" },
                [3] = { "Presence of Mind", "Cold Snap" },
                [4] = { "Evocation" },
                [5] = { "Arcane Intellect" },
                [6] = { "Ice Armor", "Mage Armor", "Frost Armor" },
                [7] = { "Slow Fall", "Dampen Magic" },
                [8] = { "Shoot" },
            },
            ctrl = {
                [1] = { "Icy Veins", "Combustion", "Arcane Power" },
                [2] = { "Conjure Mana Ruby", "Conjure Mana Citrine", "Conjure Mana Jade", "Conjure Mana Agate" },
                [3] = { "Conjure Water" },
                [4] = { "Conjure Food" },
                [5] = { "Blink" },
                [6] = { "Teleport: Orgrimmar", "Teleport: Stormwind", "Teleport: Ironforge", "Teleport: Undercity" },
                [7] = { "item:6948" },
                [8] = { "Amplify Magic", "Detect Magic" },
            },
        },
    },

    WARLOCK = {
        name = "Warlock",
        summary = "DoT & Pet Caster (115 deg kite) | GR: Stopcast Fear | GL: Pet Attack/Follow | ZL+GR: Pet Special | ZL+GL: Life Tap",
        cvars = {
            GamePadFaceMovementMaxAngle = "115",
            SoftTargetFriend = "0",
        },
        paddles = {
            { "PADPADDLE1", "PW_WLK_FEAR" },
            { "PADPADDLE2", "PW_WLK_PET" },
            { "SHIFT-PADPADDLE1", "PW_WLK_PACT" },
            { "SHIFT-PADPADDLE2", "PW_WLK_TAP" },
        },
        macros = {
            { name = "PW_WLK_FEAR", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Fear\n/stopcasting\n/cast Fear" },
            { name = "PW_WLK_PET",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/petattack [harm,nodead]\n/petfollow [noharm][dead]" },
            { name = "PW_WLK_PACT", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast [pet:Felhunter] Spell Lock; [pet:Voidwalker] Sacrifice; [pet:Succubus] Seduction" },
            { name = "PW_WLK_TAP",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Life Tap\n/cast Life Tap" },
        },
        bars = {
            base = {
                [1] = { "Shadow Bolt", "Incinerate", "Drain Life" },
                [2] = { "Corruption", "Immolate" },
                [3] = { "Immolate", "Siphon Life", "Drain Life" },
                [4] = { "Shadowburn", "Conflagrate", "Drain Soul" },
                [5] = { "Curse of Agony", "Curse of Doom", "Curse of Weakness" },
                [6] = { "Death Coil", "Howl of Terror", "Fear" },
                [7] = { "Life Tap", "Dark Pact" },
                [8] = { "Shoot", "Drain Mana" },
            },
            shift = {
                [1] = { "Curse of the Elements", "Curse of Shadow", "Curse of Weakness" },
                [2] = { "Curse of Recklessness", "Curse of Tongues" },
                [3] = { "Rain of Fire", "Hellfire" },
                [4] = { "Banish", "Enslave Demon" },
                [5] = { "Health Funnel" },
                [6] = { "Shadow Ward" },
                [7] = { "Create Healthstone (Major)", "Create Healthstone (Greater)", "Create Healthstone", "Create Healthstone (Lesser)", "Create Healthstone (Minor)" },
                [8] = { "Create Soulstone (Major)", "Create Soulstone (Greater)", "Create Soulstone", "Create Soulstone (Lesser)", "Create Soulstone (Minor)" },
            },
            ctrl = {
                [1] = { "Amplify Curse", "Fel Domination", "Demonic Sacrifice" },
                [2] = { "Demon Armor", "Demon Skin" },
                [3] = { "Summon Felhunter", "Summon Succubus", "Summon Voidwalker", "Summon Imp" },
                [4] = { "Summon Voidwalker", "Summon Imp" },
                [5] = { "Summon Dreadsteed", "Summon Felsteed" },
                [6] = { "Unending Breath", "Eye of Kilrogg" },
                [7] = { "item:6948" },
                [8] = { "Ritual of Summoning" },
            },
        },
    },

    DRUID = {
        name = "Druid",
        summary = "Feral/Balance/Resto (0 deg, SoftFriend=1) | GR: Form-Aware CC | GL: Aquatic/Travel/Cat | ZL+GR: Bear Form | ZL+GL: Smart Rejuvenation",
        cvars = {
            GamePadFaceMovementMaxAngle = "0",
            SoftTargetFriend = "1",
        },
        paddles = {
            { "PADPADDLE1", "PW_DRU_CC" },
            { "PADPADDLE2", "PW_DRU_TRV" },
            { "SHIFT-PADPADDLE1", "PW_DRU_BEAR" },
            { "SHIFT-PADPADDLE2", "PW_DRU_HOT" },
        },
        macros = {
            { name = "PW_DRU_CC",   icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast [stance:1] Bash; [stance:3,stealth] Pounce; [stance:3] Rip; Entangling Roots" },
            { name = "PW_DRU_TRV",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast [swimming] Aquatic Form; [outdoors] Travel Form; Cat Form" },
            { name = "PW_DRU_BEAR", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast Dire Bear Form\n/cast Bear Form" },
            { name = "PW_DRU_HOT",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Rejuvenation\n/cast [@mouseover,help,nodead][help,nodead][@player] Rejuvenation" },
        },
        bars = {
            base = { -- Caster
                [1] = { "Wrath" },
                [2] = { "Starfire", "Moonfire" },
                [3] = { "Moonfire", "Insect Swarm" },
                [4] = { "macro:PW_DRU_HOT", "Rejuvenation", "Healing Touch" },
                [5] = { "Entangling Roots" },
                [6] = { "Faerie Fire", "Abolish Poison", "Cure Poison" },
                [7] = { "Regrowth", "Healing Touch" },
                [8] = { "Barkskin", "Hurricane" },
            },
            bonus1 = { -- Cat Form
                [1] = { "Mangle (Cat)", "Shred", "Claw", "Attack" },
                [2] = { "Ferocious Bite", "Rip" },
                [3] = { "Rake", "Tiger's Fury" },
                [4] = { "Faerie Fire (Feral)", "Ravage", "Pounce" },
                [5] = { "Prowl" },
                [6] = { "Dash" },
                [7] = { "Cower", "Tiger's Fury" },
                [8] = { "Track Humanoids" },
            },
            bonus3 = { -- Bear / Dire Bear Form
                [1] = { "Lacerate", "Mangle (Bear)", "Maul", "Attack" },
                [2] = { "Swipe", "Maul" },
                [3] = { "Demoralizing Roar" },
                [4] = { "Growl" },
                [5] = { "Feral Charge" },
                [6] = { "Bash" },
                [7] = { "Frenzied Regeneration", "Enrage" },
                [8] = { "Challenging Roar" },
            },
            shift = {
                [1] = { "Cat Form" },
                [2] = { "Dire Bear Form", "Bear Form" },
                [3] = { "Moonkin Form", "Travel Form" },
                [4] = { "Nature's Swiftness", "Swiftmend", "Innervate" },
                [5] = { "Rejuvenation" },
                [6] = { "Regrowth" },
                [7] = { "Abolish Poison", "Cure Poison", "Remove Curse" },
                [8] = { "Tranquility", "Hurricane" },
            },
            ctrl = {
                [1] = { "Innervate", "Barkskin" },
                [2] = { "Mark of the Wild" },
                [3] = { "Thorns" },
                [4] = { "Rebirth" },
                [5] = { "Travel Form", "Aquatic Form" },
                [6] = { "Teleport: Moonglade" },
                [7] = { "item:6948" },
                [8] = { "Soothe Animal" },
            },
        },
    },

    DEATHKNIGHT = {
        name = "Death Knight",
        summary = "Classic Melee/Tank (0 deg turn) | GR: Mind Freeze | GL: Death Grip | ZL+GR: Anti-Magic Shell | ZL+GL: Death Strike",
        cvars = {
            GamePadFaceMovementMaxAngle = "0",
            SoftTargetFriend = "0",
        },
        paddles = {
            { "PADPADDLE1", "PW_DK_INT" },
            { "PADPADDLE2", "PW_DK_GRIP" },
            { "SHIFT-PADPADDLE1", "PW_DK_AMS" },
            { "SHIFT-PADPADDLE2", "PW_DK_DS" },
        },
        macros = {
            { name = "PW_DK_INT",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Mind Freeze\n/cast Mind Freeze" },
            { name = "PW_DK_GRIP", icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Death Grip\n/cast Death Grip" },
            { name = "PW_DK_AMS",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Anti-Magic Shell\n/cast Anti-Magic Shell" },
            { name = "PW_DK_DS",   icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Death Strike\n/cast Death Strike" },
        },
        bars = {
            base = {
                [1] = { "Scourge Strike", "Obliterate", "Heart Strike", "Plague Strike", "Blood Strike", "Attack" },
                [2] = { "Frost Strike", "Death Coil", "Rune Strike" },
                [3] = { "Howling Blast", "Icy Touch", "Outbreak" },
                [4] = { "Death Strike", "Festering Strike", "Plague Strike" },
                [5] = { "Death and Decay", "Pestilence", "Blood Boil" },
                [6] = { "Chains of Ice", "Strangulate", "Dark Command" },
                [7] = { "Horn of Winter", "Bone Shield" },
                [8] = { "Death Grip", "Dark Command" },
            },
            shift = {
                [1] = { "Blood Presence" },
                [2] = { "Frost Presence" },
                [3] = { "Unholy Presence" },
                [4] = { "Icebound Fortitude", "Vampiric Blood" },
                [5] = { "Anti-Magic Shell" },
                [6] = { "Pillar of Frost", "Summon Gargoyle", "Dancing Rune Weapon" },
                [7] = { "Empower Rune Weapon", "Lichborne" },
                [8] = { "Dark Command", "Strangulate" },
            },
            ctrl = {
                [1] = { "Army of the Dead", "Raise Dead" },
                [2] = { "Death Pact", "Runetap" },
                [3] = { "Path of Frost" },
                [4] = { "Death Gate" },
                [5] = { "Acherus Deathcharger" },
                [6] = { "Raise Ally" },
                [7] = { "item:6948" },
                [8] = { "Control Undead" },
            },
        },
    },
}

-- --- Talent-Spec Detection & Spec-Tailored Crossbar Overrides ---

local CLASS_SPEC_TREES = {
    WARRIOR = {
        [1] = { key = "ARMS",          label = "Arms" },
        [2] = { key = "FURY",          label = "Fury" },
        [3] = { key = "PROTECTION",    label = "Protection" },
    },
    PALADIN = {
        [1] = { key = "HOLY",          label = "Holy" },
        [2] = { key = "PROTECTION",    label = "Protection" },
        [3] = { key = "RETRIBUTION",   label = "Retribution" },
    },
    HUNTER = {
        [1] = { key = "BEAST_MASTERY", label = "Beast Mastery" },
        [2] = { key = "MARKSMANSHIP",  label = "Marksmanship" },
        [3] = { key = "SURVIVAL",      label = "Survival" },
    },
    ROGUE = {
        [1] = { key = "ASSASSINATION", label = "Assassination" },
        [2] = { key = "COMBAT",        label = "Combat" },
        [3] = { key = "SUBTLETY",      label = "Subtlety" },
    },
    PRIEST = {
        [1] = { key = "DISCIPLINE",    label = "Discipline" },
        [2] = { key = "HOLY",          label = "Holy" },
        [3] = { key = "SHADOW",        label = "Shadow" },
    },
    SHAMAN = {
        [1] = { key = "ELEMENTAL",     label = "Elemental" },
        [2] = { key = "ENHANCEMENT",   label = "Enhancement" },
        [3] = { key = "RESTORATION",   label = "Restoration" },
    },
    MAGE = {
        [1] = { key = "ARCANE",        label = "Arcane" },
        [2] = { key = "FIRE",          label = "Fire" },
        [3] = { key = "FROST",         label = "Frost" },
    },
    WARLOCK = {
        [1] = { key = "AFFLICTION",    label = "Affliction" },
        [2] = { key = "DEMONOLOGY",    label = "Demonology" },
        [3] = { key = "DESTRUCTION",   label = "Destruction" },
    },
    DRUID = {
        [1] = { key = "BALANCE",       label = "Balance" },
        [2] = { key = "FERAL",         label = "Feral" },
        [3] = { key = "RESTORATION",   label = "Restoration" },
    },
    DEATHKNIGHT = {
        [1] = { key = "BLOOD",         label = "Blood" },
        [2] = { key = "FROST",         label = "Frost" },
        [3] = { key = "UNHOLY",        label = "Unholy" },
    },
}

-- Per-spec priority overrides merged onto the class base/shift bars.
local SPEC_BAR_OVERRIDES = {
    WARRIOR = {
        PROTECTION = {
            base = {
                [1] = { "Shield Slam", "Devastate", "Sunder Armor", "Heroic Strike", "Attack" },
                [2] = { "Revenge", "Heroic Strike", "Rend" },
                [3] = { "Thunder Clap", "Cleave", "Demoralizing Shout" },
                [4] = { "Shield Block", "Last Stand", "Shield Wall" },
                [5] = { "Taunt", "Mocking Blow" },
                [6] = { "Demoralizing Shout", "Disarm" },
            },
        },
        FURY = {
            base = {
                [1] = { "Bloodthirst", "Heroic Strike", "Attack" },
                [2] = { "Whirlwind", "Slam", "Heroic Strike" },
                [3] = { "Cleave", "Overpower", "Thunder Clap" },
                [4] = { "macro:PW_WAR_VR", "Execute", "Victory Rush" },
            },
        },
    },
    PALADIN = {
        HOLY = {
            base = {
                [1] = { "macro:PW_PAL_HEAL", "Flash of Light", "Holy Light" },
                [2] = { "Holy Shock", "Holy Light", "Judgement" },
                [3] = { "Holy Light", "Consecration" },
                [4] = { "macro:PW_PAL_CLN", "Cleanse", "Purify" },
                [5] = { "Divine Favor", "Blessing of Freedom" },
                [6] = { "Judgement", "Hammer of Justice" },
                [7] = { "Consecration", "Exorcism" },
                [8] = { "Seal of Wisdom", "Seal of Light", "Seal of Righteousness" },
            },
        },
        PROTECTION = {
            base = {
                [1] = { "Consecration", "Judgement", "Seal of Righteousness", "Attack" },
                [2] = { "Holy Shield", "Shield of the Righteous", "Seal of Righteousness" },
                [3] = { "Judgement", "Avenger's Shield", "Exorcism" },
                [4] = { "Hand of Reckoning", "Righteous Defense", "Hammer of Justice" },
                [5] = { "Seal of Wisdom", "Seal of Light", "Seal of Righteousness" },
                [6] = { "Righteous Fury", "Hammer of Justice" },
            },
        },
        RETRIBUTION = {
            base = {
                [1] = { "Crusader Strike", "Judgement", "Seal of Command", "Seal of Righteousness", "Attack" },
                [2] = { "Judgement", "Seal of Command", "Seal of Righteousness" },
                [3] = { "Consecration", "Exorcism", "Hammer of Justice" },
                [4] = { "Hammer of Wrath", "Repentance", "Exorcism" },
            },
        },
    },
    HUNTER = {
        SURVIVAL = {
            base = {
                [1] = { "Raptor Strike", "Auto Shot", "Attack" },
                [2] = { "Mongoose Bite", "Counterattack", "Arcane Shot" },
                [3] = { "Wing Clip", "Wyvern Sting", "Multi-Shot" },
                [4] = { "Explosive Trap", "Immolation Trap", "Serpent Sting" },
                [5] = { "Freezing Trap", "Concussive Shot" },
                [6] = { "Hunter's Mark" },
                [7] = { "Deterrence", "Disengage" },
                [8] = { "Scatter Shot", "Feign Death" },
            },
        },
    },
    PRIEST = {
        SHADOW = {
            base = {
                [1] = { "Mind Flay", "Mind Blast", "Smite" },
                [2] = { "Mind Blast", "Smite" },
                [3] = { "Shadow Word: Pain" },
                [4] = { "Devouring Plague", "Vampiric Embrace", "Power Word: Shield" },
                [5] = { "Silence", "Psychic Scream" },
                [6] = { "macro:PW_PRI_DISP", "Dispel Magic" },
                [7] = { "Shoot", "Smite" },
                [8] = { "Shadowform", "Fade" },
            },
        },
        HOLY = {
            base = {
                [1] = { "macro:PW_PRI_HEAL", "Flash Heal", "Lesser Heal" },
                [2] = { "Renew", "Penance" },
                [3] = { "Greater Heal", "Heal", "Lesser Heal" },
                [4] = { "macro:PW_PRI_SHLD", "Power Word: Shield" },
                [5] = { "Prayer of Healing", "Holy Nova" },
                [6] = { "macro:PW_PRI_DISP", "Dispel Magic" },
                [7] = { "Desperate Prayer", "Inner Focus" },
                [8] = { "Fade", "Smite" },
            },
        },
        DISCIPLINE = {
            base = {
                [1] = { "macro:PW_PRI_SHLD", "Power Word: Shield", "Flash Heal" },
                [2] = { "Penance", "macro:PW_PRI_HEAL", "Flash Heal", "Lesser Heal" },
                [3] = { "Renew", "Greater Heal", "Heal" },
                [4] = { "Power Infusion", "Inner Focus", "Smite" },
                [5] = { "Prayer of Healing", "Holy Nova" },
                [6] = { "macro:PW_PRI_DISP", "Dispel Magic" },
            },
        },
    },
    SHAMAN = {
        ELEMENTAL = {
            base = {
                [1] = { "Lightning Bolt", "Attack" },
                [2] = { "Chain Lightning", "Lava Burst", "Earth Shock" },
                [3] = { "Flame Shock", "Earth Shock" },
                [4] = { "Earth Shock", "Frost Shock", "Purge" },
                [5] = { "Elemental Mastery", "Searing Totem" },
                [6] = { "Grounding Totem", "Earthbind Totem" },
            },
        },
        ENHANCEMENT = {
            base = {
                [1] = { "Stormstrike", "Earth Shock", "Attack" },
                [2] = { "Earth Shock", "Flame Shock" },
                [3] = { "Flame Shock", "Frost Shock" },
                [4] = { "Shamanistic Rage", "Purge", "Lightning Shield" },
                [5] = { "Windfury Totem", "Strength of Earth Totem" },
                [6] = { "Searing Totem", "Fire Nova Totem", "Grounding Totem" },
            },
        },
        RESTORATION = {
            base = {
                [1] = { "macro:PW_SHM_HEAL", "Lesser Healing Wave", "Healing Wave" },
                [2] = { "Healing Wave", "Riptide" },
                [3] = { "Chain Heal", "Lesser Healing Wave" },
                [4] = { "Nature's Swiftness", "Earth Shield", "Water Shield" },
                [5] = { "Mana Spring Totem", "Healing Stream Totem" },
                [6] = { "Cure Poison", "Cure Disease", "Tremor Totem" },
                [7] = { "Earth Shock", "Purge" },
                [8] = { "Grounding Totem", "Mana Tide Totem" },
            },
        },
    },
    DRUID = {
        RESTORATION = {
            base = {
                [1] = { "macro:PW_DRU_HOT", "Rejuvenation", "Healing Touch" },
                [2] = { "Regrowth", "Healing Touch" },
                [3] = { "Healing Touch", "Swiftmend" },
                [4] = { "Swiftmend", "Nature's Swiftness", "Barkskin" },
                [5] = { "Innervate", "Tranquility" },
                [6] = { "Abolish Poison", "Cure Poison", "Remove Curse" },
                [7] = { "Entangling Roots", "Moonfire" },
                [8] = { "Barkskin", "Travel Form" },
            },
        },
        BALANCE = {
            base = {
                [1] = { "Starfire", "Wrath" },
                [2] = { "Wrath", "Moonfire" },
                [3] = { "Moonfire", "Insect Swarm" },
                [4] = { "Insect Swarm", "Hurricane", "macro:PW_DRU_HOT" },
                [5] = { "Moonkin Form", "Entangling Roots" },
                [6] = { "Faerie Fire", "Barkskin" },
            },
        },
        FERAL = {
            base = {
                [1] = { "Cat Form", "Wrath" },
                [2] = { "Dire Bear Form", "Bear Form", "Moonfire" },
                [3] = { "macro:PW_DRU_HOT", "Rejuvenation", "Regrowth" },
                [4] = { "Faerie Fire (Feral)", "Faerie Fire", "Entangling Roots" },
            },
        },
    },
    DEATHKNIGHT = {
        BLOOD = {
            base = {
                [1] = { "Heart Strike", "Blood Strike", "Attack" },
                [2] = { "Death Strike", "Rune Strike" },
                [3] = { "Blood Boil", "Death and Decay", "Icy Touch" },
                [4] = { "Rune Strike", "Death Coil" },
                [5] = { "Dark Command", "Death Grip" },
                [6] = { "Bone Shield", "Vampiric Blood" },
            },
        },
        FROST = {
            base = {
                [1] = { "Obliterate", "Plague Strike", "Attack" },
                [2] = { "Frost Strike", "Death Coil" },
                [3] = { "Howling Blast", "Icy Touch" },
                [4] = { "Pillar of Frost", "Death Strike" },
            },
        },
        UNHOLY = {
            base = {
                [1] = { "Scourge Strike", "Festering Strike", "Plague Strike", "Attack" },
                [2] = { "Death Coil", "Festering Strike" },
                [3] = { "Outbreak", "Icy Touch", "Pestilence" },
                [4] = { "Dark Transformation", "Summon Gargoyle", "Death Strike" },
            },
        },
    },
}

local function readTalentTabPoints(tabIndex)
    if not GetTalentTabInfo then return nil, 0 end
    local ok, r1, r2, r3, _, r5 = pcall(GetTalentTabInfo, tabIndex)
    if not ok then return nil, 0 end
    if type(r1) == "number" and type(r2) == "string" then
        -- Newer signature: id, name, description, iconTexture, pointsSpent
        return r2, tonumber(r5) or 0
    elseif type(r1) == "string" then
        -- Classic / Forever signature: name, iconTexture, pointsSpent, fileName
        return r1, tonumber(r3) or 0
    end
    return nil, 0
end

-- Returns canonical specKey (e.g. "PROTECTION"), displayLabel (e.g. "Protection (21 pts)"), points
-- Returns nil, nil, 0 when 0 talent points are spent (e.g. Levels 1-9).
local function detectActiveSpec(token)
    local trees = CLASS_SPEC_TREES[token]
    if not trees then return nil, nil, 0 end

    if GetNumTalentTabs and GetTalentTabInfo then
        local okNum, numTabs = pcall(GetNumTalentTabs)
        if okNum and type(numTabs) == "number" and numTabs > 0 then
            local bestIdx, bestPts, bestName = nil, 0, nil
            for i = 1, math.min(numTabs, 3) do
                local tabName, pts = readTalentTabPoints(i)
                if pts > bestPts then
                    bestPts = pts
                    bestIdx = i
                    bestName = tabName
                end
            end
            if bestIdx and bestPts > 0 and trees[bestIdx] then
                local label = (bestName and bestName ~= "") and bestName or trees[bestIdx].label
                return trees[bestIdx].key, string.format("%s (%d pts)", label, bestPts), bestPts
            end
            return nil, nil, 0
        end
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo then
        local okIdx, specIdx = pcall(C_SpecializationInfo.GetSpecialization)
        if okIdx and type(specIdx) == "number" and specIdx >= 1 and trees[specIdx] then
            local okInfo, _, specName = pcall(C_SpecializationInfo.GetSpecializationInfo, specIdx)
            local label = (okInfo and type(specName) == "string" and specName ~= "") and specName or trees[specIdx].label
            return trees[specIdx].key, label, 1
        end
    end

    return nil, nil, 0
end

local function resolveBarSpec(profile, token, specKey, barKey)
    local baseSpec = profile.bars and profile.bars[barKey]
    local specTbl = specKey and SPEC_BAR_OVERRIDES[token] and SPEC_BAR_OVERRIDES[token][specKey]
    local overrideSpec = specTbl and specTbl[barKey]
    if not overrideSpec then
        return baseSpec
    end
    local merged = {}
    if baseSpec then
        for i = 1, 8 do
            merged[i] = baseSpec[i]
        end
    end
    for i = 1, 8 do
        if overrideSpec[i] then
            merged[i] = overrideSpec[i]
        end
    end
    return merged
end

-- --- Live Spellbook Scanner (C_SpellBook + Classic 1.15 fallback) ---

local function scanKnownSpells()
    local spells = {}

    local function record(name, subName, slot, spellID, isPassive)
        if not name or name == "" or isPassive then return end
        local rankNum = 0
        if subName and subName ~= "" then
            local r = string.match(subName, "(%d+)")
            if r then rankNum = tonumber(r) or 0 end
        end
        local key = string.lower(name)
        local cur = spells[key]
        if not cur or rankNum >= cur.rank then
            spells[key] = {
                name = name,
                slot = slot,
                spellID = spellID,
                rank = rankNum,
            }
        end
    end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo
        and C_SpellBook.GetSpellBookItemInfo then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local spellType = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
        local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
        for i = 1, numLines do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if line and not line.isGuild then
                local offset = line.itemIndexOffset or 0
                local count = line.numSpellBookItems or 0
                for j = 1, count do
                    local slot = offset + j
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                    if info and info.itemType == spellType then
                        record(info.name, info.subName, slot, info.spellID or info.actionID, info.isPassive)
                    end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        local bookType = BOOKTYPE_SPELL or "spell"
        local numTabs = GetNumSpellTabs() or 0
        for i = 1, numTabs do
            local _, _, offset, numSlots = GetSpellTabInfo(i)
            if offset and numSlots then
                for j = 1, numSlots do
                    local slot = offset + j
                    local itemType = GetSpellBookItemInfo and GetSpellBookItemInfo(slot, bookType) or "SPELL"
                    if itemType == "SPELL" then
                        local name, subName, spellID = GetSpellBookItemName(slot, bookType)
                        local passive = IsPassiveSpell and IsPassiveSpell(slot, bookType) or false
                        record(name, subName, slot, spellID, passive)
                    end
                end
            end
        end
    end

    return spells
end

local function pickupEntry(entry, knownSpells)
    ClearCursor()

    if string.sub(entry, 1, 6) == "macro:" then
        local macroName = string.sub(entry, 7)
        local idx = GetMacroIndexByName and GetMacroIndexByName(macroName)
        if idx and idx > 0 and PickupMacro then
            PickupMacro(idx)
            if GetCursorInfo() ~= nil then
                return true, macroName
            end
        end
        return false, nil
    elseif string.sub(entry, 1, 5) == "item:" then
        local itemID = tonumber(string.sub(entry, 6))
        if itemID then
            local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID))
                or (GetItemCount and GetItemCount(itemID)) or 0
            if count > 0 then
                if C_Item and C_Item.PickupItem then
                    C_Item.PickupItem(itemID)
                elseif PickupItem then
                    PickupItem(itemID)
                end
                if GetCursorInfo() ~= nil then
                    return true, "Hearthstone"
                end
            end
        end
        return false, nil
    end

    local sp = knownSpells[string.lower(entry)]
    if not sp then return false, nil end

    if C_SpellBook and C_SpellBook.PickupSpellBookItem then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        pcall(C_SpellBook.PickupSpellBookItem, sp.slot, bank)
    elseif PickupSpellBookItem then
        pcall(PickupSpellBookItem, sp.slot, BOOKTYPE_SPELL or "spell")
    end

    if GetCursorInfo() == nil and sp.spellID then
        if C_Spell and C_Spell.PickupSpell then
            pcall(C_Spell.PickupSpell, sp.spellID)
        elseif PickupSpell then
            pcall(PickupSpell, sp.spellID)
        end
    end

    if GetCursorInfo() ~= nil then
        return true, sp.name
    end
    return false, nil
end

-- Maps logical slot index (1=B, 2=A, 3=Y, 4=X, 5=Up, 6=Right, 7=Down, 8=Left)
-- to WoW: Forever's GamepadMainActionBarFrame ActionButton index (1..8):
--   1=Left, 2=Up, 3=Right, 4=Down, 5=Y(Left), 6=X(Top), 7=A(Right), 8=B(Bottom)
local FOREVER_SLOT_TO_BTN = {
    [1] = 8, -- B (Bottom)
    [2] = 7, -- A (Right)
    [3] = 5, -- Y (Left)
    [4] = 6, -- X (Top)
    [5] = 2, -- D-Pad Up
    [6] = 3, -- D-Pad Right
    [7] = 4, -- D-Pad Down
    [8] = 1, -- D-Pad Left
}

local FOREVER_BARS = {
    right  = { prefix = "GamepadMainActionBarFramePageUnitRightCenteredAnchorRightBarActionButton",   fallbackOffset = 192, label = "ZR (Right)" },
    left   = { prefix = "GamepadMainActionBarFramePageUnitLeftCenteredAnchorLeftBarActionButton",     fallbackOffset = 184, label = "ZL (Left)" },
    bottom = { prefix = "GamepadMainActionBarFramePageUnitBottomCenteredAnchorBottomBarActionButton", fallbackOffset = 200, label = "ZL+ZR (Bottom)" },
}

local function getForeverActionSlot(barKey, logicalIdx)
    local meta = FOREVER_BARS[barKey]
    local btnIdx = FOREVER_SLOT_TO_BTN[logicalIdx]
    if not meta or not btnIdx then return nil end
    local frame = _G[meta.prefix .. tostring(btnIdx)]
    if frame and type(frame.action) == "number" and frame.action > 0 then
        return frame.action
    end
    return meta.fallbackOffset + btnIdx
end

local function activeBonusKeyForClass(token)
    if token == "ROGUE" and IsStealthed and IsStealthed() then
        return "bonus1", "Stealth"
    elseif token == "WARRIOR" and GetShapeshiftForm then
        local st = GetShapeshiftForm()
        if st == 2 then return "bonus2", "Defensive Stance"
        elseif st == 3 then return "bonus3", "Berserker Stance"
        elseif st == 1 then return "bonus1", "Battle Stance"
        end
    elseif token == "DRUID" and GetShapeshiftFormID then
        local fid = GetShapeshiftFormID()
        if fid == 1 then return "bonus1", "Cat Form"
        elseif fid == 5 or fid == 8 then return "bonus3", "Bear Form"
        end
    elseif token == "PRIEST" and GetShapeshiftForm and GetShapeshiftForm() == 1 then
        return "bonus1", "Shadowform"
    end
    return nil, nil
end

local function populateBars(token, fillOnly)
    if InCombatLockdown() then
        printMsg("Cannot assign action bars during combat. Try again after combat.")
        return 0
    end

    local profile = CLASS_PROFILES[token]
    if not profile or not profile.bars then
        return 0
    end

    local level = UnitLevel("player") or 1
    local specKey, specLabel = detectActiveSpec(token)
    local knownSpells = scanKnownSpells()
    local placed = 0
    local skippedOccupied = 0
    local usedMain = {}
    local summaryParts = {}
    local btnNames = { "B", "A", "Y", "X" }

    if isForeverGamepadUI() then
        -- WoW: Forever native Controller UI (GamepadMainActionBarFrame slots 185..208, stance-paged)
        local bonusKey, stanceLabel = activeBonusKeyForClass(token)
        local primarySpec = (bonusKey and resolveBarSpec(profile, token, specKey, bonusKey))
            or resolveBarSpec(profile, token, specKey, "base")
        local leftSpec   = resolveBarSpec(profile, token, specKey, "shift")
        local bottomSpec = resolveBarSpec(profile, token, specKey, "ctrl")

        -- Right bar (ZR) = primary combat (or active Stealth/Stance/Form bar)
        -- Left bar  (ZL) = secondary combat / defensives / utility
        -- Bottom bar (ZL+ZR) = cooldowns / macros / Hearthstone
        local plan = {
            { target = "right",  spec = primarySpec, isPrimary = true },
            { target = "left",   spec = leftSpec,    isPrimary = false },
            { target = "bottom", spec = bottomSpec,  isPrimary = false },
        }

        for _, p in ipairs(plan) do
            if p.spec then
                local usedSet = p.isPrimary and {} or usedMain
                for slotIdx = 1, 8 do
                    local candidates = p.spec[slotIdx]
                    local actionSlot = getForeverActionSlot(p.target, slotIdx)
                    if candidates and actionSlot then
                        if fillOnly and HasAction and HasAction(actionSlot) then
                            skippedOccupied = skippedOccupied + 1
                        else
                            for _, entry in ipairs(candidates) do
                                local normKey = string.lower(entry)
                                if not usedSet[normKey] and (p.isPrimary or not usedMain[normKey]) then
                                    local ok, label = pickupEntry(entry, knownSpells)
                                    if ok then
                                        PlaceAction(actionSlot)
                                        ClearCursor()
                                        usedSet[normKey] = true
                                        usedMain[normKey] = true
                                        placed = placed + 1
                                        if p.isPrimary and slotIdx <= 4 then
                                            table.insert(summaryParts, btnNames[slotIdx] .. "=" .. tostring(label))
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                ClearCursor()
            end
        end

        PadWakeProfilesCharDB = PadWakeProfilesCharDB or {}
        PadWakeProfilesCharDB.populatedStances = PadWakeProfilesCharDB.populatedStances or {}
        PadWakeProfilesCharDB.populatedStances[bonusKey or "base"] = true

        local modeLabel = fillOnly and " (empty slots only)" or ""
        local specNote = specLabel and (" [" .. specLabel .. "]") or ""
        local stanceNote = stanceLabel and (" [" .. stanceLabel .. "]") or ""
        printMsg(string.format("Assigned %d %s skills onto Forever Crossbar (ZR/ZL/ZL+ZR) for Level %d [%s]%s%s%s.",
            placed, profile.name, level, levelTierLabel(level), specNote, stanceNote, modeLabel))
        if #summaryParts > 0 then
            printMsg("ZR Primary diamond: " .. table.concat(summaryParts, " | "))
        end
        if token == "ROGUE" and not stanceLabel and not PadWakeProfilesCharDB.populatedStances["bonus1"] then
            printMsg("Tip: Press GL to enter Stealth and run '/padwake bars' once more to populate your Stealth ZR diamond too.")
        elseif (token == "WARRIOR" or token == "DRUID") and not stanceLabel then
            printMsg("Tip: Shift into another Stance/Form and run '/padwake bars' to populate that form's ZR diamond too.")
        end
        if skippedOccupied > 0 then
            printMsg(string.format("Kept %d existing occupied slot(s) (--fill mode).", skippedOccupied))
        end
        return placed
    end

    -- Classic desktop UI (InputDeviceInterfaceStyle = 0)
    local barOrder = { "base", "shift", "ctrl", "both", "bonus1", "bonus2", "bonus3" }

    for _, barKey in ipairs(barOrder) do
        local barSpec = resolveBarSpec(profile, token, specKey, barKey)
        local offset = BAR_OFFSETS[barKey]
        if barSpec and offset ~= nil then
            local isBonus = (barKey == "bonus1" or barKey == "bonus2" or barKey == "bonus3")
            local usedSet = isBonus and {} or usedMain

            for slotIdx = 1, 8 do
                local candidates = barSpec[slotIdx]
                if candidates then
                    local actionSlot = offset + slotIdx
                    if fillOnly and HasAction and HasAction(actionSlot) then
                        skippedOccupied = skippedOccupied + 1
                    else
                        for _, entry in ipairs(candidates) do
                            local normKey = string.lower(entry)
                            if not usedSet[normKey] then
                                local ok, label = pickupEntry(entry, knownSpells)
                                if ok then
                                    PlaceAction(actionSlot)
                                    ClearCursor()
                                    usedSet[normKey] = true
                                    placed = placed + 1
                                    if barKey == "base" and slotIdx <= 4 then
                                        table.insert(summaryParts, btnNames[slotIdx] .. "=" .. tostring(label))
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end
            ClearCursor()
        end
    end

    local modeLabel = fillOnly and " (empty slots only)" or ""
    local specNote = specLabel and (" [" .. specLabel .. "]") or ""
    printMsg(string.format("Assigned %d level-appropriate %s skills for Level %d [%s]%s%s.",
        placed, profile.name, level, levelTierLabel(level), specNote, modeLabel))
    if #summaryParts > 0 then
        printMsg("Base diamond: " .. table.concat(summaryParts, " | "))
    end
    if skippedOccupied > 0 then
        printMsg(string.format("Kept %d existing occupied slot(s) (--fill mode).", skippedOccupied))
    end
    return placed
end

local function runInspect()
    PadWakeProfilesCharDB = PadWakeProfilesCharDB or {}
    local dump = {
        level = UnitLevel("player") or 1,
        class = select(2, UnitClass("player")) or "?",
        inputStyle = GetCVar and GetCVar("InputDeviceInterfaceStyle") or "nil",
        slots = {},
        mouse = {},
        frames = {},
        apis = {},
    }

    -- 1. Scan action slots 1..300
    for s = 1, 300 do
        local actionType, id = GetActionInfo(s)
        if actionType then
            local name = tostring(actionType) .. ":" .. tostring(id)
            if actionType == "spell" and id then
                local sp = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
                    or (GetSpellInfo and GetSpellInfo(id))
                name = "spell:" .. tostring(sp or id)
            elseif actionType == "macro" and id then
                local m = GetMacroInfo and GetMacroInfo(id)
                name = "macro:" .. tostring(m or id)
            elseif actionType == "item" and id then
                local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
                    or (GetItemInfo and GetItemInfo(id))
                name = "item:" .. tostring(itemName or id)
            end
            dump.slots[s] = name
        end
    end

    -- 2. Inspect hovered frame + parent chain
    local focus = (GetMouseFoci and GetMouseFoci()[1]) or (GetMouseFocus and GetMouseFocus())
    local cur = focus
    local depth = 0
    while cur and depth < 5 do
        depth = depth + 1
        local info = {
            name = cur.GetName and cur:GetName() or "(unnamed)",
            objType = cur.GetObjectType and cur:GetObjectType() or "?",
            keys = {},
            attrs = {},
        }
        for k, v in pairs(cur) do
            if type(k) == "string" and (type(v) == "number" or type(v) == "string" or type(v) == "boolean") then
                info.keys[k] = v
            end
        end
        if cur.GetAttribute then
            for _, attr in ipairs({ "action", "type", "spell", "macro", "binding", "slot", "index", "button" }) do
                local av = cur:GetAttribute(attr)
                if av ~= nil then
                    info.attrs[attr] = tostring(av)
                end
            end
        end
        dump.mouse[depth] = info
        cur = cur.GetParent and cur:GetParent() or nil
    end

    -- 3. Find visible frames with action/gamepad/crossbar-like names or keys
    local f = EnumerateFrames and EnumerateFrames()
    local frameCount = 0
    while f and frameCount < 120 do
        if f.IsVisible and f:IsVisible() then
            local nm = f.GetName and f:GetName() or ""
            local pnm = (f.GetParent and f:GetParent() and f:GetParent().GetName and f:GetParent():GetName()) or ""
            local lnm = string.lower(nm .. " " .. pnm)
            if string.find(lnm, "pad") or string.find(lnm, "cross") or string.find(lnm, "action") or string.find(lnm, "controller") or string.find(lnm, "bar") then
                local act = f.action or f.actionID or f.slot or (f.GetAttribute and f:GetAttribute("action"))
                if act ~= nil or string.find(lnm, "pad") or string.find(lnm, "cross") or string.find(lnm, "controller") then
                    frameCount = frameCount + 1
                    dump.frames[frameCount] = string.format("%s (parent=%s, act=%s, id=%s)",
                        nm ~= "" and nm or "(unnamed)", pnm, tostring(act), tostring(f.GetID and f:GetID()))
                end
            end
        end
        f = EnumerateFrames(f)
    end

    -- 4. List relevant global C_ namespaces
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and string.sub(k, 1, 2) == "C_" then
            local lk = string.lower(k)
            if string.find(lk, "pad") or string.find(lk, "action") or string.find(lk, "input") or string.find(lk, "bar") or string.find(lk, "bind") then
                local fns = {}
                for fk, fv in pairs(v) do
                    if type(fv) == "function" then table.insert(fns, fk) end
                end
                table.sort(fns)
                dump.apis[k] = table.concat(fns, ", ")
            end
        end
    end

    PadWakeProfilesCharDB.inspect = dump
    local slotCount = 0
    for _ in pairs(dump.slots) do slotCount = slotCount + 1 end
    printMsg(string.format("Inspect saved! Found %d populated action slots & %d UI frames. Hover frame: %s. Now run '/reload' so it writes to disk.",
        slotCount, frameCount, dump.mouse[1] and dump.mouse[1].name or "none"))
end

local function describeSlot(slot)
    local actionType, id = GetActionInfo(slot)
    if not actionType then return "(empty)" end
    if actionType == "spell" and id then
        local spName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
            or (GetSpellInfo and GetSpellInfo(id))
        return spName or ("spell:" .. tostring(id))
    elseif actionType == "macro" and id then
        local mName = GetMacroInfo and GetMacroInfo(id)
        return "macro:" .. tostring(mName or id)
    elseif actionType == "item" and id then
        local iName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
            or (GetItemInfo and GetItemInfo(id))
        return tostring(iName or ("item:" .. tostring(id)))
    end
    return tostring(actionType)
end

local function printSlotDiagnostics()
    local level = UnitLevel("player") or 1
    local _, cls = UnitClass("player")
    if isForeverGamepadUI() then
        printMsg(string.format("Forever Crossbar slots — Level %d %s (InputDeviceInterfaceStyle=1):", level, tostring(cls or "?")))
        local labels = { "B", "A", "Y", "X" }
        for _, barKey in ipairs({ "right", "left", "bottom" }) do
            local items = {}
            for i = 1, 4 do
                local s = getForeverActionSlot(barKey, i)
                table.insert(items, labels[i] .. "(" .. tostring(s) .. ")=" .. describeSlot(s))
            end
            printMsg("  " .. FOREVER_BARS[barKey].label .. ": " .. table.concat(items, ", "))
        end
        return
    end

    local groups = {
        { label = "Base (1-4 B/A/Y/X)", offset = 0, count = 4 },
        { label = "ZL/SHIFT (61-64)",   offset = 60, count = 4 },
        { label = "ZR/CTRL (49-52)",    offset = 48, count = 4 },
        { label = "Bonus1 (73-76)",     offset = 72, count = 4 },
    }
    printMsg(string.format("Desktop slots — Level %d %s:", level, tostring(cls or "?")))
    for _, g in ipairs(groups) do
        local items = {}
        for i = 1, g.count do
            local slot = g.offset + i
            table.insert(items, tostring(slot) .. "=" .. describeSlot(slot))
        end
        printMsg("  " .. g.label .. ": " .. table.concat(items, ", "))
    end
end

-- --- Core Profile Appliers ---

local function resolveClassToken(argClass)
    if argClass and argClass ~= "" then
        local upper = string.upper(argClass)
        if CLASS_PROFILES[upper] then
            return upper
        end
        return nil
    end

    if ns.selectedPreset and ns.selectedPreset ~= "AUTO" then
        local preset = string.upper(ns.selectedPreset)
        if CLASS_PROFILES[preset] then
            return preset
        end
    end

    local _, playerClass = UnitClass("player")
    if playerClass and CLASS_PROFILES[playerClass] then
        return playerClass
    end
    return nil
end

local function applyCVars(token)
    local profile = CLASS_PROFILES[token]
    local applied = 0
    for k, v in pairs(BASE_CVARS) do
        if safeSetCVar(k, v) then applied = applied + 1 end
    end
    for k, v in pairs(profile.cvars) do
        if safeSetCVar(k, v) then applied = applied + 1 end
    end
    printMsg(string.format("Applied %d C_GamePad CVars for %s.", applied, profile.name))
end

local function applyMacros(token)
    if InCombatLockdown() then
        printMsg("Cannot create or edit macros during combat. Try again after combat.")
        return 0
    end
    local profile = CLASS_PROFILES[token]
    local created, updated, skipped = 0, 0, 0
    local maxChar = MAX_CHARACTER_MACROS or 18

    for _, m in ipairs(profile.macros) do
        local idx = GetMacroIndexByName(m.name)
        if idx and idx > 0 then
            EditMacro(idx, m.name, m.icon, m.body)
            updated = updated + 1
        else
            local _, numChar = GetNumMacros()
            if (numChar or 0) < maxChar then
                CreateMacro(m.name, m.icon, m.body, true)
                created = created + 1
            else
                skipped = skipped + 1
            end
        end
    end

    local note = string.format("%s macros: %d created, %d updated.", profile.name, created, updated)
    if skipped > 0 then
        note = note .. string.format(" (%d skipped — character macro tab is full)", skipped)
    end
    printMsg(note)
    return created + updated
end

local function enableClassicActionBars()
    if isForeverGamepadUI() or isConsolePortLoaded() or InCombatLockdown() then
        return
    end
    -- Show Bottom-Left (ZL/SHIFT), Bottom-Right (ZR/CTRL), and Right (ZL+ZR) bars in WoW Classic
    if SetActionBarToggles then
        pcall(SetActionBarToggles, 1, 1, 1, 0)
    end
    safeSetCVar("SHOW_MULTI_ACTIONBAR_1", "1")
    safeSetCVar("SHOW_MULTI_ACTIONBAR_2", "1")
    safeSetCVar("SHOW_MULTI_ACTIONBAR_3", "1")
    if MultiActionBar_Update then
        pcall(MultiActionBar_Update)
    end
end

local function applyBindings(token, forceBindings)
    if InCombatLockdown() then
        printMsg("Cannot modify keybindings during combat. Try again after combat.")
        return false
    end

    if isConsolePortLoaded() and not forceBindings then
        printMsg("ConsolePort detected — keeping ConsolePort's PAD* bindings intact (use '/padwake apply --force-bindings' to override).")
        return false
    end

    local profile = CLASS_PROFILES[token]
    if isForeverGamepadUI() and not forceBindings then
        -- Let WoW: Forever's native Controller UI manage ZL/ZR/ZL+ZR crossbar triggers & face buttons,
        -- clearing any stale desktop PAD1..4 overrides and binding only our rear paddles + C button.
        for _, pair in ipairs(BASE_BINDINGS) do
            if not string.find(pair[1], "PADPADDLE") then
                SetBinding(pair[1])
            end
        end
        SetBinding("PADPADDLE3", "TOGGLEWORLDMAP")
        SetBinding("SHIFT-PADPADDLE3", "OPENALLBAGS")
        SetBinding("CTRL-PADPADDLE3", "TOGGLECHARACTER0")
    else
        for _, pair in ipairs(BASE_BINDINGS) do
            SetBinding(pair[1], pair[2])
        end
        if profile.extraBindings then
            for _, pair in ipairs(profile.extraBindings) do
                SetBinding(pair[1], pair[2])
            end
        end
        enableClassicActionBars()
    end

    for _, pair in ipairs(profile.paddles) do
        if SetBindingMacro then
            SetBindingMacro(pair[1], pair[2])
        else
            SetBinding(pair[1], "MACRO " .. pair[2])
        end
    end

    SaveBindings(GetCurrentBindingSet())
    if isForeverGamepadUI() and not forceBindings then
        printMsg(string.format("Saved Forever Controller UI rear-paddle bindings (GR/GL/C) for %s.", profile.name))
    else
        printMsg(string.format("Saved WoW Classic / native PAD* + rear-paddle bindings for %s.", profile.name))
    end
    return true
end

local function resetPadBindings()
    if InCombatLockdown() then
        printMsg("Cannot reset bindings during combat.")
        return
    end
    for _, pair in ipairs(BASE_BINDINGS) do
        SetBinding(pair[1])
    end
    for _, key in ipairs({ "PADPADDLE1", "PADPADDLE2", "SHIFT-PADPADDLE1", "SHIFT-PADPADDLE2" }) do
        SetBinding(key)
    end
    SaveBindings(GetCurrentBindingSet())
    printMsg("Cleared PadWake PAD* bindings.")
end

local function printInfo(token)
    local profile = CLASS_PROFILES[token]
    local level = UnitLevel("player") or 1
    local _, specLabel = detectActiveSpec(token)
    local specSuffix = specLabel and (" · Spec: " .. specLabel) or ""
    printMsg(string.format("%s (Level %d — %s%s) | %s", profile.name, level, levelTierLabel(level), specSuffix, profile.summary))
    printMsg("Modifiers: Hold ZR = Primary Combat | Hold ZL = Secondary/Utility | ZL+ZR = Cooldowns | L = Interact | R = Target Nearest | R3 = Jump | L3 = Auto-Run | C = Map")
end

local function printHelp()
    local _, playerClass = UnitClass("player")
    local level = UnitLevel("player") or 1
    local uiMode = isConsolePortLoaded() and "ConsolePort"
        or (isForeverGamepadUI() and "Forever Crossbar UI" or "WoW Classic / Native C_GamePad")
    local _, specLabel = playerClass and detectActiveSpec(playerClass) or nil
    local specText = specLabel and (" [" .. specLabel .. "]") or ""
    printMsg(string.format("WoW Forever & Classic Profiles v1.4.1 | Level %d %s%s | Preset: %s | Mode: %s",
        level, tostring(playerClass or "?"), specText, tostring(ns.selectedPreset or "AUTO"), uiMode))
    printMsg("Commands:")
    printMsg("  /padwake apply [class] [--keep-bars] [--force-bindings]  Full setup: CVars, macros, bindings, DialogueUI Switch & level/spec bars")
    printMsg("  /padwake bars [class] [--fill]                           Auto-assign your best known skills for your current level & talent spec")
    printMsg("  /padwake dialogue                                        Set DialogueUI InputDevice to Switch (A=Accept, B=Exit)")
    printMsg("  /padwake cvars [class]                                   Apply only optimized C_GamePad CVars")
    printMsg("  /padwake macros [class]                                  Create/update only PW_* starter macros")
    printMsg("  /padwake info [class]                                    Show detected spec, paddle & layout cheat sheet")
    printMsg("  /padwake slots                                           Inspect current skills on controller bar slots")
    printMsg("  /padwake reset                                           Clear PadWake PAD* bindings")
end

local function handleSlash(msg)
    local args = {}
    for word in string.gmatch(msg or "", "%S+") do
        table.insert(args, word)
    end

    local sub = string.lower(args[1] or "help")
    local classArg = nil
    local forceBindings = false
    local keepBars = false
    local fillOnly = false

    for i = 2, #args do
        local a = string.lower(args[i])
        if a == "--force-bindings" or a == "--force" then
            forceBindings = true
        elseif a == "--keep-bars" then
            keepBars = true
        elseif a == "--fill" then
            fillOnly = true
        elseif not classArg then
            classArg = args[i]
        end
    end

    if sub == "help" or sub == "" then
        printHelp()
        return
    elseif sub == "reset" then
        resetPadBindings()
        return
    elseif sub == "slots" then
        printSlotDiagnostics()
        return
    elseif sub == "inspect" then
        runInspect()
        return
    elseif sub == "dialogue" then
        configureDialogueUISwitchMode(true)
        return
    end

    local token = resolveClassToken(classArg)
    if not token then
        printMsg("Unknown class '" .. tostring(classArg) .. "'. Valid: warrior, paladin, hunter, rogue, priest, deathknight, shaman, mage, warlock, druid.")
        return
    end

    if sub == "apply" then
        applyCVars(token)
        applyMacros(token)
        applyBindings(token, forceBindings)
        configureDialogueUISwitchMode(false)
        if not keepBars then
            populateBars(token, fillOnly)
        end
        printInfo(token)
        PadWakeProfilesCharDB = PadWakeProfilesCharDB or {}
        PadWakeProfilesCharDB.appliedClass = token
        PadWakeProfilesCharDB.appliedLevel = UnitLevel("player") or 1
    elseif sub == "bars" then
        applyMacros(token)
        populateBars(token, fillOnly)
        PadWakeProfilesCharDB = PadWakeProfilesCharDB or {}
        PadWakeProfilesCharDB.appliedLevel = UnitLevel("player") or 1
    elseif sub == "cvars" then
        applyCVars(token)
    elseif sub == "macros" then
        applyMacros(token)
    elseif sub == "info" then
        printInfo(token)
    else
        printHelp()
    end
end

SLASH_PADWAKE1 = "/padwake"
SLASH_PADWAKE2 = "/pw"
SlashCmdList["PADWAKE"] = handleSlash

local lastLearnHintTime = 0
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:SetScript("OnEvent", function(_, event, newLevel)
    PadWakeProfilesCharDB = PadWakeProfilesCharDB or {}
    if event == "PLAYER_LOGIN" then
        if not PadWakeProfilesCharDB.appliedClass then
            local token = resolveClassToken(nil)
            if token then
                local level = UnitLevel("player") or 1
                local mode = isConsolePortLoaded() and "ConsolePort mode"
                    or (isForeverGamepadUI() and "Forever Crossbar UI" or "Native C_GamePad mode")
                printMsg(string.format("Ready for Level %d %s (%s). Type '/padwake apply' to set CVars, bindings & auto-assign skills.",
                    level, CLASS_PROFILES[token].name, mode))
            end
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local lvl = tonumber(newLevel) or (UnitLevel("player") or 1)
        printMsg(string.format("Grats on Level %d! Visit your trainer and run '/padwake bars' to upgrade your controller skills.", lvl))
    elseif event == "LEARNED_SPELL_IN_TAB" then
        local now = GetTime and GetTime() or 0
        if now - lastLearnHintTime > 10 then
            lastLearnHintTime = now
            printMsg("New spell learned! Type '/padwake bars' (or '/padwake bars --fill') to place it on your controller.")
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        if not isForeverGamepadUI() or not PadWakeProfilesCharDB.appliedClass or InCombatLockdown() then
            return
        end
        local token = resolveClassToken(nil)
        if not token then return end
        local bonusKey, stanceLabel = activeBonusKeyForClass(token)
        if not bonusKey or not stanceLabel then return end
        PadWakeProfilesCharDB.populatedStances = PadWakeProfilesCharDB.populatedStances or {}
        PadWakeProfilesCharDB.promptedStances = PadWakeProfilesCharDB.promptedStances or {}
        if not PadWakeProfilesCharDB.populatedStances[bonusKey] and not PadWakeProfilesCharDB.promptedStances[bonusKey] then
            PadWakeProfilesCharDB.promptedStances[bonusKey] = true
            printMsg(string.format("Entered %s for the first time! Type '/padwake bars' to populate your %s ZR combat diamond.",
                stanceLabel, stanceLabel))
        end
    end
end)
