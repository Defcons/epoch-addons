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
    ["Lower Blackrock Spire"] = {
        displayName = "Lower Blackrock Spire",
        bosses = {
            "Highlord Omokk",
            "Shadow Hunter Vosh'gajin",
            "War Master Voone",
            "Mother Smolderweb",
            "Halycon",
            "Overlord Wyrmthalak",
        },
    },
    ["Upper Blackrock Spire"] = {
        displayName = "Upper Blackrock Spire",
        bosses = {
            "Warchief Rend Blackhand",
            "Gyth",
            "The Beast",
            "General Drakkisath",
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
    -- Stratholme is two dungeons sharing one instance name. The "sides"
    -- field signals to the rest of the module that DetectDungeon needs
    -- to defer side resolution until the first boss kill.
    ["Stratholme"] = {
        displayName = "Stratholme (side: detecting…)",
        sides = {
            live = {
                displayName = "Stratholme — Live",
                bosses = {
                    "Archivist Galford",
                    "Balnazzar",
                    "Timmy the Cruel",
                    "The Unforgiven",
                },
            },
            undead = {
                displayName = "Stratholme — Undead",
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

-- Reverse lookup: boss name → side key for Stratholme. Built once at file
-- load so the CLEU handler can O(1) detect the side on first boss kill.
local STRAT_BOSS_TO_SIDE = {}
for sideKey, sideDef in pairs(DUNGEONS["Stratholme"].sides) do
    for _, bossName in ipairs(sideDef.bosses) do
        STRAT_BOSS_TO_SIDE[bossName] = sideKey
    end
end

-- ============================================================================
-- Module state
-- ============================================================================

local frame              = nil          -- the UI frame, lazily built
local currentDungeon     = nil          -- key into DUNGEONS, or nil if not in a tracked dungeon
local stratSide          = nil          -- "live" | "undead" | nil when in Stratholme but unresolved
local dungeonStartTime   = nil          -- GetTime() when entered
local bossKills          = {}           -- set: bossName → true once UNIT_DIED fires
local loggingActive      = false        -- mirror of LoggingCombat() state — set by us, never read from API (no getter)
local promptShown        = false        -- per-run flag: have we already shown the Yes/No prompt?
local userDeclinedLog    = false        -- per-run: user clicked "No" on the prompt — don't re-ask this run

-- ============================================================================
-- Helpers
-- ============================================================================

-- Returns the dungeon key (matching DUNGEONS) for the current instance,
-- or nil if the player is not in a tracked dungeon. Stratholme returns
-- "Stratholme" even though we don't yet know the side; the side gets
-- resolved later on first boss kill.
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

-- Returns the list of bosses for the current dungeon. For Stratholme,
-- returns the side's roster once stratSide is resolved, or a synthetic
-- combined "both sides" preview before resolution.
local function GetCurrentBosses()
    if not currentDungeon then return {} end
    local def = DUNGEONS[currentDungeon]
    if def.sides then
        if stratSide then
            return def.sides[stratSide].bosses
        else
            -- Side undetected: return BOTH lists concatenated so the
            -- UI can show them all greyed out as "side TBD".
            local combined = {}
            for _, b in ipairs(def.sides.live.bosses) do combined[#combined+1] = b end
            for _, b in ipairs(def.sides.undead.bosses) do combined[#combined+1] = b end
            return combined
        end
    end
    return def.bosses
end

-- Returns the human-friendly name for the current dungeon, including
-- the resolved Stratholme side if known.
local function GetCurrentDisplayName()
    if not currentDungeon then return "(not in a dungeon)" end
    local def = DUNGEONS[currentDungeon]
    if def.sides then
        if stratSide then return def.sides[stratSide].displayName end
        return def.displayName -- "Stratholme (side: detecting…)"
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
    if def.sides then
        -- For Stratholme, both sides' bosses count as "boss of current"
        -- whether or not the side is resolved.
        return STRAT_BOSS_TO_SIDE[destName] ~= nil
    end
    for _, b in ipairs(def.bosses) do
        if b == destName then return true end
    end
    return false
end

-- ============================================================================
-- State transitions
-- ============================================================================

-- Forward declaration so OnEnterDungeon (which lazily builds the frame
-- on first dungeon entry) can refer to BuildFrame defined further down.
-- Without this, BuildFrame is looked up as a global at call time and
-- resolves to nil. Common Lua scoping gotcha.
local BuildFrame

local function ResetRun()
    currentDungeon    = nil
    stratSide         = nil
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

    -- Stratholme side resolution: lock in the side based on which
    -- list this boss belongs to.
    local def = DUNGEONS[currentDungeon]
    if def.sides and not stratSide then
        stratSide = STRAT_BOSS_TO_SIDE[bossName]
        if stratSide then
            print(string.format("|cffffaa44EpogArmory|r: Stratholme side detected: |cffffd200%s|r",
                def.sides[stratSide].displayName))
        end
    end

    print(string.format("|cffffaa44EpogArmory|r: |cff66ff66boss down|r — %s", bossName))

    if frame and frame.UpdateUI then frame.UpdateUI() end
end

-- ============================================================================
-- UI frame
-- ============================================================================

-- Anchor helper mirrors the dummy frame's approach: pin to top-left
-- of UIParent on every Show so a panel rearrange doesn't lose the
-- frame off-screen.
local function AnchorTopLeft(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
end

function BuildFrame()
    local f = CreateFrame("Frame", "EpogArmoryDungeonFrame", UIParent)
    -- Width matches the dummy frame (280) for visual consistency.
    -- Height set so the largest roster (Stratholme combined preview =
    -- 10 boss rows at 12px pitch) plus the bottom toggle button fit
    -- without overlap. Computed: header (~200) + 10 rows × 12 (120)
    -- + bottom button area (~40) + 40 padding = ~400.
    f:SetWidth(280); f:SetHeight(400)
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

    -- Dungeon name (resolved + side)
    f.dungeonLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.dungeonLabel:SetPoint("TOP", 0, -32)
    f.dungeonLabel:SetWidth(252)
    f.dungeonLabel:SetJustifyH("CENTER")

    -- Timer
    f.timerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.timerLabel:SetPoint("TOP", 0, -56)

    -- Run status (IN PROGRESS / COMPLETE / IDLE)
    f.statusBadge = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.statusBadge:SetPoint("TOP", f.timerLabel, "BOTTOM", 0, -2)

    -- Logging status row
    f.logStatusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.logStatusLabel:SetPoint("TOP", f.statusBadge, "BOTTOM", 0, -8)

    -- Prompt: shown once on dungeon entry. Two buttons (Yes/No), an
    -- explanatory label. Non-secure — LoggingCombat is unprotected.
    f.prompt = CreateFrame("Frame", nil, f)
    f.prompt:SetPoint("TOPLEFT", 16, -130)
    f.prompt:SetPoint("TOPRIGHT", -16, -130)
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

    -- Boss list header
    f.bossesLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.bossesLabel:SetPoint("TOPLEFT", 14, -200)
    f.bossesLabel:SetText("|cffffd200Bosses|r")

    -- Pre-create 12 boss text rows (max we'd ever need = Strat both
    -- sides = 10, leave some headroom). Show/hide on demand.
    local BOSS_TOP   = -216
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

        -- Boss list. Build the text per-row with ✓/✗ + colored name.
        local bosses = GetCurrentBosses()
        for i = 1, #f.bossTexts do
            local row = f.bossTexts[i]
            local bossName = bosses[i]
            if bossName then
                local def = DUNGEONS[currentDungeon] -- may be nil if no dungeon
                local sideTag = ""
                if def and def.sides and not stratSide then
                    -- Annotate which side each boss belongs to since
                    -- both lists are mixed in pre-resolution.
                    local s = STRAT_BOSS_TO_SIDE[bossName]
                    if s then sideTag = string.format(" |cff888888(%s)|r", s) end
                end
                if bossKills[bossName] then
                    row:SetText(string.format("|cff66ff66+|r %s%s", bossName, sideTag))
                else
                    row:SetText(string.format("|cffaaaaaa-|r |cff888888%s%s|r", bossName, sideTag))
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
