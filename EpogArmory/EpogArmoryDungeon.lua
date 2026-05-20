-- ============================================================================
-- EpogArmoryDungeon.lua — Dungeon speedrun tracker frame
-- ============================================================================
-- Detects when the player enters a tracked dungeon (per the epoglogs.com
-- leaderboard's supported set), opens a small status frame showing the
-- boss roster + kill progress + run timer + /combatlog status. Prompts
-- the user once on entry to start logging.
--
-- Passive validation: boss UNIT_DIED events in the log ARE the proof
-- the run is real — no Validate button, no marker. The site parses the
-- log for the expected boss kill sequence and accepts based on that.
-- (Matches how Warcraftlogs treats raid logs.)
--
-- Stratholme side detection: GetInstanceInfo returns "Stratholme" for
-- both Live and Undead sides. We pick the side on first-boss-kill and
-- lock it in for the rest of the run.
-- ============================================================================
-- Claude (v1.7.3 internal): new module — dungeon speedrun status frame
-- ============================================================================

local floor = math.floor
local time, GetTime = time, GetTime

-- ============================================================================
-- Dungeon roster — keyed by GetInstanceInfo() name
-- ============================================================================

-- Roster source: epoglogs.com leaderboard rules (pasted 2026-05-20).
-- Boss names are exact, case-sensitive — they must match UNIT_DIED's
-- destName from CLEU. If the server has localized boss names different
-- from these, the kill won't register. (No locale issues expected on
-- Project Epoch since the server uses English globally.)
--
-- NOT included in this first cut: trash bucket requirements from the
-- epoglogs rules. Those need OR-group tracking which adds ~200 lines
-- of UI/state. Boss tracking covers the primary user need ("which
-- bosses did I kill, which am I missing"). Add trash in v1.7.4 if
-- the user asks.
-- Multi-variant pattern: some instances share one GetInstanceInfo() name
-- but map to multiple leaderboard dungeons. The "variants" field signals
-- DetectDungeon that a side/variant choice is needed:
--   "Blackrock Spire" → variants { lbrs, ubrs }
--   "Stratholme"      → variants { live, undead }
-- For these, the user picks a variant via buttons in the frame (or it
-- auto-resolves on the first boss kill that uniquely belongs to one side).
-- Single-variant dungeons just have a top-level `bosses` array.
local DUNGEONS = {
    ["Blackrock Depths"] = {
        displayName = "Blackrock Depths",
        bosses = {
            "Lord Incendius",
            "Magmus",
            "Emperor Dagran Thaurissan",
            "Princess Moira Bronzebeard",
        },
    },
    ["Blackrock Spire"] = {
        displayName = "Blackrock Spire (variant: select below)",
        variants = {
            lbrs = {
                displayName = "Lower Blackrock Spire",
                shortName   = "LBRS",
                bosses = {
                    "Highlord Omokk",
                    "Shadow Hunter Vosh'gajin",
                    "War Master Voone",
                    "Mother Smolderweb",
                    "Halycon",
                    "Overlord Wyrmthalak",
                },
            },
            ubrs = {
                displayName = "Upper Blackrock Spire",
                shortName   = "UBRS",
                bosses = {
                    "Warchief Rend Blackhand",
                    "Gyth",
                    "The Beast",
                    "General Drakkisath",
                },
            },
        },
    },
    ["Scholomance"] = {
        displayName = "Scholomance",
        bosses = {
            "Rattlegore",
            "Instructor Malicia",
            "Doctor Theolen Krastinov",
            "Lorekeeper Polkelt",
            "The Ravenian",
            "Lord Alexei Barov",
            "Lady Illucia Barov",
            "Darkmaster Gandling",
        },
    },
    ["Stratholme"] = {
        displayName = "Stratholme (variant: select below)",
        variants = {
            live = {
                displayName = "Stratholme — Live",
                shortName   = "Live",
                bosses = {
                    "Archivist Galford",
                    "Balnazzar",
                    "Timmy the Cruel",
                    "The Unforgiven",
                },
            },
            undead = {
                displayName = "Stratholme — Undead",
                shortName   = "Undead",
                bosses = {
                    "Magistrate Barthilas",
                    "Nerub'enkan",
                    "Maleki the Pallid",
                    "Baroness Anastari",
                    "Ramstein the Gorger",
                    "Lord Aurius Rivendare",
                },
            },
        },
    },
    ["Baradin Hold"] = {
        displayName = "Baradin Hold",
        bosses = {
            "Glagut",
            "Nazrasash",
            "Calypso",
            "Pirate Lord Blackstone",
        },
    },
}

-- Per-dungeon reverse lookup: boss name → variant key. Built once at
-- file load so OnBossKilled can O(1) auto-resolve the variant for
-- multi-variant dungeons. Single-variant dungeons get no entry here.
-- Example: BOSS_TO_VARIANT["Blackrock Spire"]["Highlord Omokk"] = "lbrs"
local BOSS_TO_VARIANT = {}
for dungeonKey, def in pairs(DUNGEONS) do
    if def.variants then
        BOSS_TO_VARIANT[dungeonKey] = {}
        for variantKey, variantDef in pairs(def.variants) do
            for _, bossName in ipairs(variantDef.bosses) do
                BOSS_TO_VARIANT[dungeonKey][bossName] = variantKey
            end
        end
    end
end

-- ============================================================================
-- Module state
-- ============================================================================

local frame              = nil          -- the UI frame, lazily built
local currentDungeon     = nil          -- key into DUNGEONS, or nil if not in a tracked dungeon
local currentVariant          = nil          -- variant key (e.g. "lbrs", "ubrs", "live", "undead") for multi-variant dungeons; nil when not yet resolved
local dungeonStartTime   = nil          -- GetTime() when entered
local bossKills          = {}           -- set: bossName → true once UNIT_DIED fires
local loggingActive      = false        -- mirror of LoggingCombat() state — set by us, never read from API (no getter)
local promptShown        = false        -- per-run flag: have we already shown the Yes/No prompt?
local userDeclinedLog    = false        -- per-run: user clicked "No" on the prompt — don't re-ask this run

-- ============================================================================
-- Helpers
-- ============================================================================

-- Returns the dungeon key (matching DUNGEONS) for the current instance,
-- or nil if the player is not in a tracked dungeon. Multi-variant
-- dungeons (Blackrock Spire, Stratholme) return their shared name
-- even though we don't yet know the variant; that gets resolved
-- either by user button click or by first boss kill.
local function DetectDungeon()
    if not IsInInstance or not GetInstanceInfo then return nil end
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return nil end
    -- Both 5-mans (party) and raid (Baradin Hold) are accepted.
    if instanceType ~= "party" and instanceType ~= "raid" then return nil end
    local name = GetInstanceInfo()
    if name and DUNGEONS[name] then return name end
    return nil
end

-- Returns the list of bosses for the current dungeon. For multi-variant
-- dungeons, returns the resolved variant's roster, or a synthetic
-- combined "all variants" preview before resolution.
local function GetCurrentBosses()
    if not currentDungeon then return {} end
    local def = DUNGEONS[currentDungeon]
    if def.variants then
        if currentVariant then
            return def.variants[currentVariant].bosses
        else
            -- Variant undetected: return ALL variants' bosses concatenated
            -- so the UI can show them tagged + greyed until the user picks.
            local combined = {}
            for _, variantDef in pairs(def.variants) do
                for _, b in ipairs(variantDef.bosses) do combined[#combined+1] = b end
            end
            return combined
        end
    end
    return def.bosses
end

-- Returns the human-friendly name for the current dungeon, including
-- the resolved variant if known.
local function GetCurrentDisplayName()
    if not currentDungeon then return "(not in a dungeon)" end
    local def = DUNGEONS[currentDungeon]
    if def.variants then
        if currentVariant then return def.variants[currentVariant].displayName end
        return def.displayName -- "<Name> (variant: select below)"
    end
    return def.displayName
end

-- Format elapsed seconds as "M:SS" or "H:MM:SS" for longer runs.
local function FormatElapsed(seconds)
    seconds = floor(seconds)
    local h = floor(seconds / 3600)
    local m = floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

local function IsBossOfCurrent(destName)
    if not currentDungeon or not destName then return false end
    local def = DUNGEONS[currentDungeon]
    if def.variants then
        -- For multi-variant dungeons, ANY variant's boss counts as
        -- "boss of current" — we use the kill to auto-resolve the
        -- variant if it wasn't manually selected.
        local map = BOSS_TO_VARIANT[currentDungeon]
        return map and map[destName] ~= nil
    end
    for _, b in ipairs(def.bosses) do
        if b == destName then return true end
    end
    return false
end

-- ============================================================================
-- State transitions
-- ============================================================================

-- Forward declarations so functions defined earlier can call functions
-- defined further down. Without these, the names are looked up as
-- globals at call time and resolve to nil. Common Lua scoping gotcha.
--
-- Required for:
--   BuildFrame  -- called from OnEnterDungeon (lazy build on entry)
--                  and from _G.EpogArmoryDungeon_Toggle.
--   AnchorTopLeft -- called from OnEnterDungeon (re-anchor on entry).
--                    Bug fix v1.7.4: crashed PLAYER_ENTERING_WORLD
--                    with "attempt to call global 'AnchorTopLeft'".
local BuildFrame
local AnchorTopLeft

local function ResetRun()
    currentDungeon    = nil
    currentVariant         = nil
    dungeonStartTime  = nil
    bossKills         = {}
    promptShown       = false
    userDeclinedLog   = false
    -- Don't touch loggingActive — that mirrors a global setting the
    -- user may have started themselves. Only StopLogging/StartLogging
    -- below modify it.
end

local function StartLogging()
    if LoggingCombat then LoggingCombat(true) end
    loggingActive = true
    print("|cffffaa44EpogArmory|r: |cff66ff66/combatlog started|r for this dungeon run.")
end

local function StopLogging()
    if LoggingCombat then LoggingCombat(false) end
    loggingActive = false
    print("|cffffaa44EpogArmory|r: /combatlog stopped.")
end

local function OnEnterDungeon(dungeonKey)
    if currentDungeon == dungeonKey then return end -- already in this one
    ResetRun()
    currentDungeon   = dungeonKey
    dungeonStartTime = GetTime()
    -- Auto-open the frame so the user sees the prompt + roster. Build
    -- it lazily on first entry — BuildFrame defined further down so we
    -- assume it's available by the time OnEnterDungeon ever fires
    -- (PLAYER_ENTERING_WORLD comes well after file load).
    if not frame then frame = BuildFrame() end
    AnchorTopLeft(frame)
    if not frame:IsShown() then frame:Show() end
    frame.UpdateUI()
end

local function OnLeaveDungeon()
    -- Don't auto-stop logging on zone change — the user may have
    -- intentionally started /combatlog for cross-instance reasons.
    -- We only stop logging that WE started, and only via the Stop
    -- button in the frame.
    --
    -- Keep the frame visible briefly so the user can see the final
    -- state before resetting. (Actual reset happens on next dungeon
    -- entry, or on /epogarmory dungeon toggle.)
    if frame and frame.UpdateUI then frame.UpdateUI() end
end

local function OnBossKilled(bossName)
    if not currentDungeon then return end
    if bossKills[bossName] then return end -- already recorded
    bossKills[bossName] = true

    -- Multi-variant auto-resolution: if the user hasn't picked a variant
    -- yet, lock it in based on which variant this boss belongs to.
    local def = DUNGEONS[currentDungeon]
    if def.variants and not currentVariant then
        local map = BOSS_TO_VARIANT[currentDungeon]
        currentVariant = map and map[bossName]
        if currentVariant then
            print(string.format("|cffffaa44EpogArmory|r: variant auto-detected from boss kill: |cffffd200%s|r",
                def.variants[currentVariant].displayName))
        end
    end

    print(string.format("|cffffaa44EpogArmory|r: |cff66ff66boss down|r - %s", bossName))

    if frame and frame.UpdateUI then frame.UpdateUI() end
end

-- ============================================================================
-- UI frame
-- ============================================================================

-- Anchor helper mirrors the dummy frame's approach: pin to top-left
-- of UIParent on every Show so a panel rearrange doesn't lose the
-- frame off-screen. Assigned to the forward-declared local (see top
-- of state-transitions section).
AnchorTopLeft = function(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
end

-- Assign via expression rather than `function BuildFrame()` so the
-- forward-declared local is unambiguously the assignment target. The
-- bare-function-syntax should work in Lua 5.1 but has bit users on
-- WoW 3.3.5 before; explicit assignment removes the doubt.
BuildFrame = function()
    local f = CreateFrame("Frame", "EpogArmoryDungeonFrame", UIParent)
    -- Width matches the dummy frame (280) for visual consistency.
    -- Height bumped from 400 -> 432 in v1.7.4 to absorb the new
    -- variant-selection row inserted between dungeonLabel and the
    -- timer (Blackrock Spire LBRS/UBRS, Stratholme Live/Undead).
    f:SetWidth(280); f:SetHeight(432)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText("EpogLogs - Dungeon Run")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Dungeon name (resolved + variant)
    f.dungeonLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.dungeonLabel:SetPoint("TOP", 0, -32)
    f.dungeonLabel:SetWidth(252)
    f.dungeonLabel:SetJustifyH("CENTER")

    -- Variant selection container (v1.7.4). Shown only when the
    -- current dungeon has variants AND no variant is yet resolved.
    -- Holds up to 2 buttons side-by-side (LBRS/UBRS or Live/Undead).
    -- Buttons get repopulated each time the container is shown to
    -- match the current dungeon's variants.
    f.variantContainer = CreateFrame("Frame", nil, f)
    f.variantContainer:SetPoint("TOP", 0, -52)
    f.variantContainer:SetWidth(252)
    f.variantContainer:SetHeight(24)
    f.variantContainer:Hide()
    f.variantBtns = {} -- variantKey -> button, populated lazily

    -- Timer (Huge font; shifted from -56 to -88 in v1.7.4 to make
    -- room for the variant row above).
    f.timerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.timerLabel:SetPoint("TOP", 0, -88)

    -- Run status (IN PROGRESS / COMPLETE / IDLE)
    f.statusBadge = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.statusBadge:SetPoint("TOP", f.timerLabel, "BOTTOM", 0, -2)

    -- Logging status row
    f.logStatusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.logStatusLabel:SetPoint("TOP", f.statusBadge, "BOTTOM", 0, -8)

    -- Prompt: shown once on dungeon entry. Two buttons (Yes/No), an
    -- explanatory label. Non-secure — LoggingCombat is unprotected.
    -- Position shifted from -130 to -162 in v1.7.4 to follow the
    -- timer's new y position.
    f.prompt = CreateFrame("Frame", nil, f)
    f.prompt:SetPoint("TOPLEFT", 16, -162)
    f.prompt:SetPoint("TOPRIGHT", -16, -162)
    f.prompt:SetHeight(54)
    f.prompt:Hide()
    f.prompt.bg = f.prompt:CreateTexture(nil, "BACKGROUND")
    f.prompt.bg:SetAllPoints()
    f.prompt.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.prompt.bg:SetVertexColor(0.15, 0.15, 0.18, 0.7)
    f.prompt.text = f.prompt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.prompt.text:SetPoint("TOP", 0, -4)
    f.prompt.text:SetText("Start /combatlog for this run?")
    f.prompt.yes = CreateFrame("Button", nil, f.prompt, "UIPanelButtonTemplate")
    f.prompt.yes:SetSize(80, 22); f.prompt.yes:SetText("Yes")
    f.prompt.yes:SetPoint("BOTTOMLEFT", 20, 4)
    f.prompt.yes:SetScript("OnClick", function()
        StartLogging()
        f.prompt:Hide()
        if frame and frame.UpdateUI then frame.UpdateUI() end
    end)
    f.prompt.no = CreateFrame("Button", nil, f.prompt, "UIPanelButtonTemplate")
    f.prompt.no:SetSize(80, 22); f.prompt.no:SetText("No")
    f.prompt.no:SetPoint("BOTTOMRIGHT", -20, 4)
    f.prompt.no:SetScript("OnClick", function()
        userDeclinedLog = true
        f.prompt:Hide()
        if frame and frame.UpdateUI then frame.UpdateUI() end
    end)

    -- Boss list header (shifted from -200 to -232 in v1.7.4)
    f.bossesLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.bossesLabel:SetPoint("TOPLEFT", 14, -232)
    f.bossesLabel:SetText("|cffffd200Bosses|r")

    -- Pre-create 12 boss text rows (max we'd ever need = combined
    -- multi-variant preview = up to 10, leave some headroom).
    -- Boss row top shifted from -216 to -248 in v1.7.4.
    local BOSS_TOP   = -248
    local BOSS_PITCH = 12
    f.bossTexts = {}
    for i = 1, 12 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 18, BOSS_TOP - (i - 1) * BOSS_PITCH)
        fs:SetWidth(244)
        fs:SetJustifyH("LEFT")
        fs:Hide()
        f.bossTexts[i] = fs
    end

    -- Bottom action button: toggle log start/stop manually if the
    -- user wants to control it after dismissing the prompt.
    f.logToggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.logToggleBtn:SetSize(140, 22)
    f.logToggleBtn:SetPoint("BOTTOM", 0, 14)
    f.logToggleBtn:SetScript("OnClick", function()
        if loggingActive then
            StopLogging()
        else
            StartLogging()
        end
        if frame and frame.UpdateUI then frame.UpdateUI() end
    end)

    -- ----------------------------------------------------------------
    -- UpdateUI — full redraw, called from event handlers + tick.
    -- ----------------------------------------------------------------
    function f.UpdateUI()
        f.dungeonLabel:SetText(GetCurrentDisplayName())

        -- Timer + status
        if currentDungeon and dungeonStartTime then
            local elapsed = GetTime() - dungeonStartTime
            f.timerLabel:SetText(FormatElapsed(elapsed))
            f.timerLabel:SetTextColor(1, 1, 1)
            local bosses = GetCurrentBosses()
            local killed = 0
            for _, b in ipairs(bosses) do
                if bossKills[b] then killed = killed + 1 end
            end
            local total = #bosses
            -- "Both sides" preview for Stratholme pre-resolution counts
            -- against the larger combined list, so use the SIDE total
            -- (whichever side we'll likely lock to) if any kills exist.
            if total > 0 and killed == total then
                f.statusBadge:SetText("|cff66ff66COMPLETE|r")
            else
                f.statusBadge:SetText(string.format("|cffffd200IN PROGRESS|r |cff888888(%d / %d bosses)|r",
                    killed, total))
            end
        else
            f.timerLabel:SetText("--:--")
            f.timerLabel:SetTextColor(0.5, 0.5, 0.5)
            f.statusBadge:SetText("|cff888888IDLE|r")
        end

        -- Logging status
        if loggingActive then
            f.logStatusLabel:SetText("Logging: |cff66ff66ACTIVE|r")
        else
            f.logStatusLabel:SetText("Logging: |cffff6666OFF|r")
        end

        -- Prompt visibility — show ONLY on first entry into a dungeon
        -- if we haven't yet asked AND user hasn't already declined AND
        -- logging isn't already going.
        if currentDungeon
           and not promptShown
           and not userDeclinedLog
           and not loggingActive
        then
            f.prompt:Show()
            promptShown = true
        elseif not currentDungeon then
            f.prompt:Hide()
        end

        -- Variant selection buttons (v1.7.4). Shown only when the
        -- current dungeon has variants AND the variant isn't yet
        -- resolved. Lazily creates one button per variant the first
        -- time we see this dungeon. Buttons are positioned within
        -- variantContainer (252px wide, 24px tall) — for 2 variants,
        -- each gets ~120px wide centered side-by-side.
        do
            local def = currentDungeon and DUNGEONS[currentDungeon] or nil
            if def and def.variants and not currentVariant then
                -- Build button per variant if not yet created. We'd build
                -- once per dungeon, so we check by key. This is robust
                -- against the user re-entering a different multi-variant
                -- dungeon (Strat -> BRS) — different keys, fresh buttons.
                local variantKeys = {}
                for vk in pairs(def.variants) do variantKeys[#variantKeys+1] = vk end
                table.sort(variantKeys) -- deterministic order
                local n = #variantKeys
                local btnWidth = math.floor((252 - 8 * (n - 1)) / n) -- 8px gap between buttons
                for i, vk in ipairs(variantKeys) do
                    local btn = f.variantBtns[vk]
                    if not btn then
                        btn = CreateFrame("Button", nil, f.variantContainer, "UIPanelButtonTemplate")
                        btn:SetHeight(22)
                        btn:SetScript("OnClick", function(self)
                            -- Capture the variant key from the closure
                            currentVariant = self._variantKey
                            print(string.format("|cffffaa44EpogArmory|r: variant selected: |cffffd200%s|r",
                                def.variants[currentVariant].displayName))
                            if frame and frame.UpdateUI then frame.UpdateUI() end
                        end)
                        f.variantBtns[vk] = btn
                    end
                    btn._variantKey = vk
                    btn:SetWidth(btnWidth)
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", f.variantContainer, "LEFT",
                        (i - 1) * (btnWidth + 8), 0)
                    btn:SetText(def.variants[vk].shortName or vk)
                    btn:Show()
                end
                -- Hide any leftover buttons from a previous dungeon's
                -- variants that aren't in the current set.
                for vk, btn in pairs(f.variantBtns) do
                    if not def.variants[vk] then btn:Hide() end
                end
                f.variantContainer:Show()
            else
                f.variantContainer:Hide()
            end
        end

        -- Boss list. Build the text per-row with +/- markers.
        local bosses = GetCurrentBosses()
        local def = DUNGEONS[currentDungeon] -- may be nil if no dungeon
        local variantMap = currentDungeon and BOSS_TO_VARIANT[currentDungeon] or nil
        for i = 1, #f.bossTexts do
            local row = f.bossTexts[i]
            local bossName = bosses[i]
            if bossName then
                local variantTag = ""
                if def and def.variants and not currentVariant and variantMap then
                    -- Annotate which variant each boss belongs to since
                    -- both lists are mixed in pre-resolution.
                    local v = variantMap[bossName]
                    if v then
                        local short = def.variants[v].shortName or v
                        variantTag = string.format(" |cff888888(%s)|r", short)
                    end
                end
                if bossKills[bossName] then
                    row:SetText(string.format("|cff66ff66+|r %s%s", bossName, variantTag))
                else
                    row:SetText(string.format("|cffaaaaaa-|r |cff888888%s%s|r", bossName, variantTag))
                end
                row:Show()
            else
                row:Hide()
            end
        end

        -- Action button label reflects current logging state
        if loggingActive then
            f.logToggleBtn:SetText("Stop logging")
        else
            f.logToggleBtn:SetText("Start logging")
        end
    end

    -- Tick for the live timer. 0.5s is enough granularity for a
    -- minute-scale timer and is light on CPU.
    local lastTick = 0
    f:SetScript("OnUpdate", function(self, e)
        lastTick = lastTick + (e or 0)
        if lastTick < 0.5 then return end
        lastTick = 0
        if currentDungeon then f.UpdateUI() end
    end)

    return f
end

-- ============================================================================
-- Public functions
-- ============================================================================

_G.EpogArmoryDungeon_Toggle = function()
    if not frame then frame = BuildFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        AnchorTopLeft(frame)
        frame:Show()
        frame.UpdateUI()
    end
end

-- Claude v1.7.3: diagnostic dump for when the auto-open isn't firing.
-- Tells us exactly what GetInstanceInfo returns, whether the name is
-- in the DUNGEONS table, and current module state. Wired to
-- /epogarmory dungeondebug.
_G.EpogArmoryDungeon_Debug = function()
    print("|cffffaa44EpogArmory|r [dungeon-debug] dumping detection state:")
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        print(string.format("  IsInInstance: %s, type: %s",
            tostring(inInstance), tostring(instanceType)))
    else
        print("  IsInInstance: API not available")
    end
    if GetInstanceInfo then
        local name, instanceType, difficulty, difficultyName, maxPlayers = GetInstanceInfo()
        print(string.format("  GetInstanceInfo: name='%s' type='%s' difficulty=%s difficultyName='%s' maxPlayers=%s",
            tostring(name), tostring(instanceType), tostring(difficulty),
            tostring(difficultyName), tostring(maxPlayers)))
        if name and DUNGEONS[name] then
            print(string.format("  |cff66ff66MATCH|r DUNGEONS['%s'] found", name))
        elseif name then
            print(string.format("  |cffff6666NO MATCH|r in DUNGEONS table for name='%s'", name))
            print("  known keys: Blackrock Depths, Lower Blackrock Spire, Upper Blackrock Spire, Scholomance, Stratholme, Baradin Hold")
        end
    else
        print("  GetInstanceInfo: API not available")
    end
    print(string.format("  module state: currentDungeon=%s, currentVariant=%s, dungeonStartTime=%s",
        tostring(currentDungeon), tostring(currentVariant), tostring(dungeonStartTime)))
    print(string.format("  frame: built=%s, shown=%s",
        tostring(frame ~= nil), tostring(frame and frame:IsShown())))
    print(string.format("  logging: active=%s, promptShown=%s, userDeclined=%s",
        tostring(loggingActive), tostring(promptShown), tostring(userDeclinedLog)))
    print(string.format("  GetRealZoneText='%s', GetSubZoneText='%s'",
        tostring(GetRealZoneText and GetRealZoneText() or "?"),
        tostring(GetSubZoneText and GetSubZoneText() or "?")))
end

-- ============================================================================
-- Event wiring
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
       or event == "ZONE_CHANGED_NEW_AREA"
    then
        local detected = DetectDungeon()
        if detected then
            if currentDungeon ~= detected then
                OnEnterDungeon(detected)
            end
        else
            -- Left the tracked dungeon; clear state lazily so the
            -- frame retains the last view until user dismisses or
            -- enters a new dungeon.
            if currentDungeon then OnLeaveDungeon() end
        end
        if frame and frame:IsShown() then frame.UpdateUI() end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not currentDungeon then return end
        local _, subevent, _, _, _, _, destName = ...
        if subevent ~= "UNIT_DIED" or not destName then return end
        if IsBossOfCurrent(destName) then
            OnBossKilled(destName)
        end
        return
    end
end)
