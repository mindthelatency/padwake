-- PadWakeProfiles.lua
-- Lightweight, zero-dependency companion addon for PadWake (057E:2069 USB Gamepad).
-- Applies World of Warcraft: Forever class-optimized C_GamePad CVars, native PAD*
-- bindings (immune to synchronizeBindings cloud overwrites), and starter macros.

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

local function safeSetCVar(key, value)
    if C_CVar and C_CVar.GetCVarInfo then
        if C_CVar.GetCVarInfo(key) == nil then
            return false
        end
    end
    local ok = pcall(SetCVar, key, tostring(value))
    return ok
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

-- Universal 4-layer ConsolePort-compatible crossbar bindings (32+ combat slots)
local BASE_BINDINGS = {
    -- Base layer (Action Bar 1)
    { "PAD1", "ACTIONBUTTON1" },
    { "PAD2", "ACTIONBUTTON2" },
    { "PAD3", "ACTIONBUTTON3" },
    { "PAD4", "ACTIONBUTTON4" },
    { "PADDUP", "ACTIONBUTTON5" },
    { "PADDRIGHT", "ACTIONBUTTON6" },
    { "PADDDOWN", "ACTIONBUTTON7" },
    { "PADDLEFT", "ACTIONBUTTON8" },

    -- SHIFT layer (Hold ZL / PADLTRIGGER -> Bottom-Left Action Bar)
    { "SHIFT-PAD1", "MULTIACTIONBAR1BUTTON1" },
    { "SHIFT-PAD2", "MULTIACTIONBAR1BUTTON2" },
    { "SHIFT-PAD3", "MULTIACTIONBAR1BUTTON3" },
    { "SHIFT-PAD4", "MULTIACTIONBAR1BUTTON4" },
    { "SHIFT-PADDUP", "MULTIACTIONBAR1BUTTON5" },
    { "SHIFT-PADDRIGHT", "MULTIACTIONBAR1BUTTON6" },
    { "SHIFT-PADDDOWN", "MULTIACTIONBAR1BUTTON7" },
    { "SHIFT-PADDLEFT", "MULTIACTIONBAR1BUTTON8" },

    -- CTRL layer (Hold ZR / PADRTRIGGER -> Bottom-Right Action Bar)
    { "CTRL-PAD1", "MULTIACTIONBAR2BUTTON1" },
    { "CTRL-PAD2", "MULTIACTIONBAR2BUTTON2" },
    { "CTRL-PAD3", "MULTIACTIONBAR2BUTTON3" },
    { "CTRL-PAD4", "MULTIACTIONBAR2BUTTON4" },
    { "CTRL-PADDUP", "MULTIACTIONBAR2BUTTON5" },
    { "CTRL-PADDRIGHT", "MULTIACTIONBAR2BUTTON6" },
    { "CTRL-PADDDOWN", "MULTIACTIONBAR2BUTTON7" },
    { "CTRL-PADDLEFT", "MULTIACTIONBAR2BUTTON8" },

    -- SHIFT+CTRL layer (Hold ZL + ZR -> Right Action Bar)
    { "SHIFT-CTRL-PAD1", "MULTIACTIONBAR3BUTTON1" },
    { "SHIFT-CTRL-PAD2", "MULTIACTIONBAR3BUTTON2" },
    { "SHIFT-CTRL-PAD3", "MULTIACTIONBAR3BUTTON3" },
    { "SHIFT-CTRL-PAD4", "MULTIACTIONBAR3BUTTON4" },

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

-- All 9 World of Warcraft: Forever class profiles
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
            { name = "PW_ROG_STL",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip\n/cast [nocombat] !Stealth; Vanish" },
            { name = "PW_ROG_SPR",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Sprint\n/cast Sprint" },
            { name = "PW_ROG_SAP",  icon = "INV_MISC_QUESTIONMARK", body = "#showtooltip Sap\n/cleartarget\n/targetenemy\n/cast Sap" },
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
    },
}

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
    for _, pair in ipairs(BASE_BINDINGS) do
        SetBinding(pair[1], pair[2])
    end
    if profile.extraBindings then
        for _, pair in ipairs(profile.extraBindings) do
            SetBinding(pair[1], pair[2])
        end
    end
    for _, pair in ipairs(profile.paddles) do
        if SetBindingMacro then
            SetBindingMacro(pair[1], pair[2])
        else
            SetBinding(pair[1], "MACRO " .. pair[2])
        end
    end

    SaveBindings(GetCurrentBindingSet())
    printMsg(string.format("Saved native PAD* + rear-paddle bindings for %s.", profile.name))
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
    printMsg(string.format("%s Profile — %s", profile.name, profile.summary))
    printMsg("Modifiers: Hold ZL = SHIFT (Bar 2) | Hold ZR = CTRL (Bar 3) | ZL+ZR = Bar 4 | L = Interact | R = Target Nearest | R3 = Jump | L3 = Auto-Run | C = Map")
end

local function printHelp()
    local _, playerClass = UnitClass("player")
    local cpState = isConsolePortLoaded() and "Loaded (bindings preserved)" or "Not loaded (native C_GamePad)"
    printMsg(string.format("WoW: Forever Profiles v1.0.0 | Class: %s | Preset: %s | ConsolePort: %s",
        tostring(playerClass or "?"), tostring(ns.selectedPreset or "AUTO"), cpState))
    printMsg("Commands:")
    printMsg("  /padwake apply [class] [--force-bindings]  Apply CVars, starter macros, and PAD* bindings")
    printMsg("  /padwake cvars [class]                     Apply only optimized C_GamePad CVars")
    printMsg("  /padwake macros [class]                    Create/update only PW_* starter macros")
    printMsg("  /padwake info [class]                      Show paddle & layout cheat sheet")
    printMsg("  /padwake reset                             Clear PadWake PAD* bindings")
end

local function handleSlash(msg)
    local args = {}
    for word in string.gmatch(msg or "", "%S+") do
        table.insert(args, word)
    end

    local sub = string.lower(args[1] or "help")
    local classArg = nil
    local forceBindings = false
    for i = 2, #args do
        local a = string.lower(args[i])
        if a == "--force-bindings" or a == "--force" then
            forceBindings = true
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
    end

    local token = resolveClassToken(classArg)
    if not token then
        printMsg("Unknown class '" .. tostring(classArg) .. "'. Valid: warrior, paladin, hunter, rogue, priest, shaman, mage, warlock, druid.")
        return
    end

    if sub == "apply" then
        applyCVars(token)
        applyMacros(token)
        applyBindings(token, forceBindings)
        printInfo(token)
        PadWakeProfilesCharDB = PadWakeProfilesCharDB or {}
        PadWakeProfilesCharDB.appliedClass = token
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    PadWakeProfilesCharDB = PadWakeProfilesCharDB or {}
    if not PadWakeProfilesCharDB.appliedClass then
        local token = resolveClassToken(nil)
        if token then
            local mode = isConsolePortLoaded() and "ConsolePort mode" or "Native C_GamePad mode"
            printMsg(string.format("Ready for %s (%s). Type '/padwake apply' to install optimized CVars, macros & bindings.",
                CLASS_PROFILES[token].name, mode))
        end
    end
end)
