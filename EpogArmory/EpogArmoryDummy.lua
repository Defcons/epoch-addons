-- ============================================================================
-- EpogArmoryDummy.lua — Dummy parse validation + combat log gating
-- ============================================================================
-- Detects when the player is fighting a Training Dummy in a city, runs a
-- 1:30 combat log on the player's behalf, checks player auras + target
-- debuffs continuously throughout the fight, and emits a Hearthstone
-- marker at 1:20 IF the fight stayed clean the whole time. The marker
-- appears in WoWCombatLog.txt as a SPELL_CAST_FAILED "Hearthstone" /
-- "Interrupted" line, which epoglogs.com uses to gate dummy parses.
--
-- Wire scheme (verified empirically against Epoch's combat log writer):
--     CastSpellByName("Hearthstone")  -> SPELL_CAST_START line
--     SpellStopCasting()              -> SPELL_CAST_FAILED line w/ "Interrupted"
-- Both lines carry source GUID = player, spell name = "Hearthstone".
-- ============================================================================

local floor = math.floor
local time, GetTime = time, GetTime

-- ============================================================================
-- Constants
-- ============================================================================

-- 90 seconds total log. Marker at 80s gives 10s headroom for the line to
-- flush to disk before LoggingCombat(false) closes the file.
local LOG_DURATION_SEC   = 90
local MARKER_TIME_SEC    = 80
local TICK_INTERVAL      = 0.25 -- 4Hz aura recheck + timer update

-- During the 1:20-1:30 "stopping" window, if the player hasn't damaged
-- the dummy for this many seconds, end the parse early and stop logging.
-- Lets the user disengage cleanly without sitting through the full 10s.
local IDLE_STOP_THRESHOLD = 3

-- Substring match on UnitName("target"). Catches all standard variants
-- ("Training Dummy", "Combat Training Dummy", "Expert's Training Dummy",
-- "Heroic Training Dummy") with one rule.
local DUMMY_NAME_PATTERN = "Training Dummy"

-- Marker: Fishing (spell ID 7620). Picked because:
--   - Universal (every character has it from level 1)
--   - Fails INSTANTLY with "Must have a Fishing Pole equipped" when no
--     pole is equipped (always true during a dummy parse — player has
--     their real weapon out)
--   - Single SPELL_CAST_FAILED log line, no SPELL_CAST_START / cast
--     bar / SpellStopCasting timing required
--   - No GCD, no resource cost, no visible cast bar
--   - Distinctive failure reason that won't be confused with anything else
-- Verified against user's empirical log:
--   SPELL_CAST_FAILED ... 7620,"Fishing","Must have a Fishing Pole equipped"
local MARKER_SPELL_ID    = 7620
local MARKER_SPELL_NAME  = "Fishing"

-- Allowed aura sources: self + own pets/summons + vehicle.
-- Class summons (Hunter pet, Warlock demon, Mage Water Elemental, Priest
-- Shadowfiend, Shaman Greater Elementals, DK Ghouls, Druid Treants) all
-- use the "pet" unit token regardless of class. Trinket guardians (if any)
-- use other tokens and are excluded automatically.
local ALLOWED_CASTERS = {
    ["player"]  = true,
    ["pet"]     = true,
    ["vehicle"] = true,
}

-- Consumable name patterns — auras matching these are REJECTED even when
-- self-cast. Most consumables are technically self-applied (you ate the
-- food, you drank the elixir) so the caster check alone isn't enough.
-- Mana potions don't create auras on Epoch (they're just SPELL_CAST_SUCCESS
-- + SPELL_ENERGIZE for "Restore Mana", verified empirically) so they
-- pass the aura check by not appearing in it at all — no special-case
-- needed. Substring match, case-sensitive.
local CONSUMABLE_PATTERNS = {
    "Flask of",          -- "Flask of Endless Rage", etc.
    "Elixir of",         -- "Elixir of Mighty Agility", "Elixir of the Mongoose"
    "Well Fed",          -- food buff
    "Sharpening Stone",  -- weapon stones
    "Weightstone",
    "Mana Oil",          -- weapon oils
    "Wizard Oil",
    "Scroll of",         -- "Scroll of Strength", etc.
    "Battle Squawk",     -- engineering noisemaker
    "Drums of",          -- leatherworking battle drums
    "Battle Standard",   -- guild banners
    "Toughness",         -- food (Spiced Mammoth Treats etc.)
    "Sanctified",        -- food
    "Mighty Rage",       -- berserker rage / similar potions
    "Haste Potion",      -- consumable haste pots
    "Indestructible",    -- defensive pots
    "Wild Magic",        -- combat-pot family
}

-- Persistence: cap the fight-history table at this many records.
local MAX_FIGHT_HISTORY = 50

-- ============================================================================
-- Module state
-- ============================================================================

local frame              = nil          -- the UI frame, lazily built
local state              = "idle"       -- "idle" | "armed" | "logging" | "stopping" | "stopped"
local fightStartTime     = nil          -- GetTime() when combat started
local validThroughout    = true         -- sticky false on any violation
local invalidReasons     = {}           -- set of reason strings
local markerEmitted      = false        -- true once EmitMarker() ran
local markerVerified     = false        -- true once SPELL_CAST_FAILED for our marker was seen in CLEU
local lastDummyName      = nil
local savedDummyGUID     = nil          -- saved at combat start
local lastDummyHitTime   = 0            -- GetTime() of last player/pet damage on dummy

-- Live aura listings for the UI. Recomputed each tick.
local currentPlayerAuras   = {}         -- list of { name, source, allowed }
local currentTargetDebuffs = {}

-- ============================================================================
-- Helpers: detection
-- ============================================================================

local function IsDummyTargeted()
    local name = UnitName("target")
    if not name then return false end
    return name:find(DUMMY_NAME_PATTERN, 1, true) ~= nil
end

local function IsCity()
    -- IsResting() returns true in all major cities + most inns. Simpler
    -- than maintaining a zone-name allowlist.
    if IsResting then return IsResting() end
    return false
end

-- Walk known unit tokens looking for one whose GUID matches savedDummyGUID.
-- The user might change target mid-fight; we still want to read the dummy's
-- debuffs. Returns the unit token or nil.
local function FindDummyToken()
    if not savedDummyGUID then return nil end
    if UnitGUID("target") == savedDummyGUID then return "target" end
    if UnitGUID("focus")  == savedDummyGUID then return "focus" end
    if UnitGUID("targettarget") == savedDummyGUID then return "targettarget" end
    -- Walk pet target, mouseover (cheap)
    if UnitGUID("pettarget") == savedDummyGUID then return "pettarget" end
    if UnitGUID("mouseover") == savedDummyGUID then return "mouseover" end
    return nil
end

-- ============================================================================
-- Helpers: aura validation
-- ============================================================================

-- Returns true, nil if the aura is allowed.
-- Returns false, reason-fragment string if rejected.
local function IsAllowedAura(name, source)
    -- Reject if name matches a consumable pattern, regardless of caster.
    -- Flasks/elixirs/food/oils are technically self-applied but the user
    -- doesn't want them in dummy parses.
    if name then
        for _, pat in ipairs(CONSUMABLE_PATTERNS) do
            if name:find(pat, 1, true) then
                return false, "consumable"
            end
        end
    end
    -- Allowed sources: player self, pets/summons (all class types use
    -- the "pet" token), vehicles.
    if source and ALLOWED_CASTERS[source] then
        return true
    end
    -- Anything else is a foreign caster.
    return false, "foreign"
end

local function ScanPlayerAuras()
    local list = {}
    for i = 1, 40 do
        -- UnitBuff (3.3.5): name, rank, icon, count, debuffType, duration,
        -- expirationTime, source (unitCaster), isStealable, ...
        local name, _, _, _, _, _, _, source = UnitBuff("player", i)
        if not name then break end
        local allowed, reasonTag = IsAllowedAura(name, source)
        list[#list + 1] = {
            name      = name,
            source    = source or "unknown",
            allowed   = allowed,
            reasonTag = reasonTag, -- "consumable" or "foreign" when not allowed
        }
    end
    return list
end

local function ScanTargetDebuffs(unitToken)
    local list = {}
    if not unitToken or not UnitExists(unitToken) then return list end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, source = UnitDebuff(unitToken, i)
        if not name then break end
        local allowed, reasonTag = IsAllowedAura(name, source)
        list[#list + 1] = {
            name      = name,
            source    = source or "unknown",
            allowed   = allowed,
            reasonTag = reasonTag,
        }
    end
    return list
end

-- Recompute the live aura snapshots. If any are disallowed and we're in
-- "logging" state, flip validThroughout false (sticky) and record the
-- reason. Returns true if everything is currently clean.
local function ValidateNow()
    currentPlayerAuras = ScanPlayerAuras()
    local dummyToken = FindDummyToken()
    currentTargetDebuffs = ScanTargetDebuffs(dummyToken)

    local nowClean = true
    for _, aura in ipairs(currentPlayerAuras) do
        if not aura.allowed then
            nowClean = false
            if state == "logging" then
                local reason
                if aura.reasonTag == "consumable" then
                    reason = string.format("consumable buff: %s", aura.name)
                else
                    reason = string.format("foreign buff on player: %s (from %s)",
                        aura.name, aura.source)
                end
                invalidReasons[reason] = true
            end
        end
    end
    for _, aura in ipairs(currentTargetDebuffs) do
        if not aura.allowed then
            nowClean = false
            if state == "logging" then
                local reason
                if aura.reasonTag == "consumable" then
                    reason = string.format("consumable debuff on target: %s", aura.name)
                else
                    reason = string.format("foreign debuff on target: %s (from %s)",
                        aura.name, aura.source)
                end
                invalidReasons[reason] = true
            end
        end
    end

    -- During logging, lost-dummy is also a violation (we can't validate
    -- the target's debuffs anymore).
    if state == "logging" and savedDummyGUID and not dummyToken then
        nowClean = false
        invalidReasons["lost sight of dummy mid-fight"] = true
    end

    if state == "logging" and not nowClean then
        validThroughout = false
    end
    return nowClean
end

-- ============================================================================
-- Marker emission
-- ============================================================================

-- Emit the validation marker into the combat log. The exact mechanism is
-- deliberately not surfaced to the user (we don't want people knowing
-- how to fake validation).
--
-- Fishing fails INSTANTLY with "Must have a Fishing Pole equipped" when
-- the player's main hand isn't a fishing pole (always true during dummy
-- parses — the player has their real weapon out). The fail produces a
-- single SPELL_CAST_FAILED log line, no SPELL_CAST_START, no cast bar,
-- no GCD, no SpellStopCasting timing dance. After the cast attempt,
-- the addon listens for the SPELL_CAST_FAILED line in CLEU and sets
-- markerVerified=true. CLEAN verdict requires markerVerified.

local _restoreUIErrors = CreateFrame("Frame")
_restoreUIErrors:Hide()
local _restoreElapsed = 0
_restoreUIErrors:SetScript("OnUpdate", function(self, e)
    _restoreElapsed = _restoreElapsed + e
    if _restoreElapsed >= 0.4 then
        self:Hide()
        _restoreElapsed = 0
        if UIErrorsFrame then UIErrorsFrame:Show() end
    end
end)

local function EmitMarker()
    -- Suppress the red "Must have a Fishing Pole equipped" flash. The
    -- failure happens within ~50ms; 0.4s suppression covers it.
    if UIErrorsFrame then UIErrorsFrame:Hide() end
    _restoreElapsed = 0
    _restoreUIErrors:Show()

    if CastSpellByName then CastSpellByName(MARKER_SPELL_NAME) end
end

-- ============================================================================
-- State transitions
-- ============================================================================

local function SetState(newState)
    state = newState
    if frame and frame.UpdateUI then frame.UpdateUI() end
end

-- CLEAN requires all three:
--   1. validThroughout: no foreign/consumable auras during the parse
--   2. markerEmitted:   we actually called EmitMarker (validThroughout
--                       was true at T+1:20)
--   3. markerVerified:  CLEU confirmed the SPELL_CAST_FAILED for our
--                       marker landed in the combat log file
-- The third check is critical — without it we'd declare CLEAN even if
-- the marker never actually reached the log file (which would cause
-- the website to reject the upload after the user thought it was valid).
local function IsCleanVerdict()
    return validThroughout and markerEmitted and markerVerified
end

local function PrintVerdict()
    -- Generic verdict text — doesn't reveal the marker mechanism.
    if IsCleanVerdict() then
        print("|cffffaa44EpogArmory|r: |cff66ff66CLEAN dummy parse|r - log is valid for upload.")
        return
    end
    print("|cffffaa44EpogArmory|r: |cffff6666INVALID dummy parse|r - log will be rejected. Reasons:")
    local count = 0
    for reason in pairs(invalidReasons) do
        print("  |cffaaaaaa-|r " .. reason)
        count = count + 1
    end
    -- Specific reason for marker-not-verified case (addon emitted but
    -- the line didn't make it to the combat log file).
    if validThroughout and markerEmitted and not markerVerified then
        print("  |cffaaaaaa-|r validation marker did not land in combat log (cast may have been blocked)")
        count = count + 1
    end
    if count == 0 then
        print("  |cffaaaaaa-|r (no specific reason captured)")
    end
end

local function SaveFightRecord()
    EpogArmoryDB = EpogArmoryDB or {}
    EpogArmoryDB.dummyFights = EpogArmoryDB.dummyFights or {}

    local reasonsList = {}
    for reason in pairs(invalidReasons) do
        reasonsList[#reasonsList + 1] = reason
    end

    local elapsed = (fightStartTime and (GetTime() - fightStartTime)) or 0
    table.insert(EpogArmoryDB.dummyFights, {
        endTime        = floor(time()),
        durationSec    = floor(elapsed),
        dummyName      = lastDummyName,
        dummyGUID      = savedDummyGUID,
        valid          = IsCleanVerdict(),
        invalidReasons = reasonsList,
        markerEmitted  = markerEmitted,
        markerVerified = markerVerified,
        addonVersion   = GetAddOnMetadata and GetAddOnMetadata("EpogArmory", "Version") or "?",
    })

    while #EpogArmoryDB.dummyFights > MAX_FIGHT_HISTORY do
        table.remove(EpogArmoryDB.dummyFights, 1)
    end
end

local function DoStartLogging()
    if not IsDummyTargeted() then return false end
    if not IsCity() then return false end

    fightStartTime    = GetTime()
    validThroughout   = true
    invalidReasons    = {}
    markerEmitted     = false
    markerVerified    = false
    lastDummyName     = UnitName("target")
    savedDummyGUID    = UnitGUID("target")
    lastDummyHitTime  = GetTime() -- count the start of combat as "just hit"

    -- Initial aura check (T+0). If we start with junk auras already on,
    -- validThroughout flips false immediately and the marker won't emit.
    if LoggingCombat then LoggingCombat(true) end
    SetState("logging")
    ValidateNow()
    return true
end

-- Stop the log and finalize the parse. Called from both the natural T+1:30
-- timer expiry AND the idle-detection early-exit in the stopping window.
-- 'reason' is added to invalidReasons (and flips validThroughout false)
-- only when non-nil — natural end passes nil to preserve the verdict.
local function FinishFight(reason)
    if state ~= "logging" and state ~= "stopping" then return end
    if LoggingCombat then LoggingCombat(false) end
    if reason and not invalidReasons[reason] then
        invalidReasons[reason] = true
        validThroughout = false
    end
    SetState("stopped")
    PrintVerdict()
    SaveFightRecord()
end

-- ============================================================================
-- Event callbacks
-- ============================================================================

local function OnEnterCombat()
    if state == "armed" then
        DoStartLogging()
        return
    end
    -- Auto-log path: user has the config option on, idle state, and
    -- conditions match.
    if state == "idle"
       and EpogArmoryDB and EpogArmoryDB.config
       and EpogArmoryDB.config.dummyAutoLog
       and IsDummyTargeted() and IsCity()
    then
        DoStartLogging()
    end
end

local function OnLeaveCombat()
    if state ~= "logging" and state ~= "stopping" then return end
    local elapsed = GetTime() - (fightStartTime or GetTime())
    if elapsed < MARKER_TIME_SEC then
        -- Fight ended before the marker would have fired. Treat as failed.
        FinishFight("fight ended before 1:20 — log truncated")
    end
    -- Between 1:20 and 1:30 (in "stopping" state): let the timer / idle
    -- detector finish naturally. The marker is already in the log file.
end

local function OnTick()
    if state == "armed" then
        -- Preview aura check so the user can see what's clean BEFORE
        -- starting the fight. Doesn't write to invalidReasons.
        ValidateNow()
        if frame and frame:IsShown() then frame.UpdateUI() end
        return
    end
    if state ~= "logging" and state ~= "stopping" then return end

    local elapsed = GetTime() - (fightStartTime or GetTime())

    -- Belt-and-suspenders aura recheck. UNIT_AURA also drives validation,
    -- this is the redundant timer-based check.
    ValidateNow()

    -- T+1:20 transition: logging -> stopping. If the fight stayed clean
    -- up to this point, also cast the marker. The CLEU handler will
    -- confirm it landed in the log via markerVerified. State check
    -- prevents re-entry on subsequent ticks.
    if state == "logging" and elapsed >= MARKER_TIME_SEC then
        if validThroughout then
            EmitMarker()
            markerEmitted = true
        end
        SetState("stopping")
    end

    -- Idle-detection early exit during the stopping window. If the player
    -- hasn't damaged the dummy for IDLE_STOP_THRESHOLD seconds AND we've
    -- passed the marker emission point, stop the log early. Lets the user
    -- disengage cleanly without sitting through the full 10s tail.
    if state == "stopping" then
        local idleFor = GetTime() - lastDummyHitTime
        if idleFor >= IDLE_STOP_THRESHOLD then
            FinishFight(nil)
            return
        end
    end

    -- Hard auto-stop at 1:30 regardless.
    if elapsed >= LOG_DURATION_SEC then
        FinishFight(nil)
        return
    end

    if frame and frame:IsShown() then frame.UpdateUI() end
end

-- ============================================================================
-- UI frame
-- ============================================================================

local function BuildFrame()
    local f = CreateFrame("Frame", "EpogArmoryDummyFrame", UIParent)
    -- Compact frame: 280 wide x 420 tall. Initial position is top-left of
    -- the screen; users can drag from there. Re-anchored to top-left on
    -- every Show (see EpogArmoryDummy_Toggle / OnEvent open paths).
    f:SetWidth(280); f:SetHeight(420)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    -- Bump strata above CombatLogQuickButtonFrame_Custom so its quick-
    -- control buttons (Stop/Pause/Reset/Hide) don't render over our
    -- aura list when /combatlog is active.
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
    f.title:SetText("EpogLogs - Dummy Parse")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Target line (compact)
    f.targetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.targetLabel:SetPoint("TOP", 0, -30)
    f.targetLabel:SetWidth(240)
    f.targetLabel:SetJustifyH("CENTER")

    -- State badge (use Large instead of Huge to compact)
    f.stateBadge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.stateBadge:SetPoint("TOP", 0, -48)

    -- Timer line
    f.timerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.timerLabel:SetPoint("TOP", 0, -72)
    f.timerLabel:SetText("0:00 / 1:30")

    -- Verdict text. Hidden until state transitions to "stopped". Shows
    -- "Log: CLEAN" (green) or "Log: INVALID" (red) so the user sees
    -- the final result in a dedicated line rather than buried in the
    -- state badge.
    f.verdictLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.verdictLabel:SetPoint("TOP", 0, -104)
    f.verdictLabel:Hide()

    -- Progress bar
    f.progressBg = f:CreateTexture(nil, "BACKGROUND")
    f.progressBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressBg:SetVertexColor(0.12, 0.12, 0.12, 0.85)
    f.progressBg:SetPoint("TOPLEFT", 16, -94)
    f.progressBg:SetPoint("TOPRIGHT", -16, -94)
    f.progressBg:SetHeight(6)

    f.progressFg = f:CreateTexture(nil, "ARTWORK")
    f.progressFg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressFg:SetVertexColor(0.2, 0.7, 0.2, 1)
    f.progressFg:SetPoint("TOPLEFT", 16, -94)
    f.progressFg:SetHeight(6)
    f.progressFg:SetWidth(1)

    -- Marker tick at the "validation point" on the progress bar
    f.progressMark = f:CreateTexture(nil, "OVERLAY")
    f.progressMark:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressMark:SetVertexColor(1, 0.85, 0.2, 1)
    f.progressMark:SetWidth(2); f.progressMark:SetHeight(10)
    f.progressMark:SetPoint("TOP", f.progressBg, "TOPLEFT",
        (280 - 32) * (MARKER_TIME_SEC / LOG_DURATION_SEC), 2)

    -- Player auras header
    f.playerAurasLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.playerAurasLabel:SetPoint("TOPLEFT", 14, -110)

    local PA_TOP = -124
    f.playerAurasTop = PA_TOP
    f.playerAuraTexts = {}

    -- Target debuffs header
    f.targetDebuffsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.targetDebuffsLabel:SetPoint("TOPLEFT", 14, -236)

    local TD_TOP = -250
    f.targetDebuffsTop = TD_TOP
    f.targetDebuffTexts = {}

    -- Auto-log checkbox (compact)
    f.autoLogCheck = CreateFrame("CheckButton", "EpogArmoryDummyAutoLog", f, "UICheckButtonTemplate")
    f.autoLogCheck:SetPoint("BOTTOMLEFT", 12, 46)
    f.autoLogCheck:SetWidth(20); f.autoLogCheck:SetHeight(20)
    f.autoLogCheck.text = f.autoLogCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.autoLogCheck.text:SetPoint("LEFT", f.autoLogCheck, "RIGHT", 2, 1)
    f.autoLogCheck.text:SetText("Auto-start log on combat")
    f.autoLogCheck:SetScript("OnClick", function(self)
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        EpogArmoryDB.config.dummyAutoLog = self:GetChecked() and true or false
    end)

    -- Action button (label changes with state)
    f.actionBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.actionBtn:SetWidth(120); f.actionBtn:SetHeight(24)
    f.actionBtn:SetPoint("BOTTOM", 0, 16)
    f.actionBtn:SetText("Ready")
    f.actionBtn:SetScript("OnClick", function()
        if state == "idle" then
            SetState("armed")
        elseif state == "armed" then
            SetState("idle")
        elseif state == "logging" or state == "stopping" then
            -- Manual stop. No marker (if not already emitted), no verdict
            -- print — the user knows they cancelled intentionally.
            if LoggingCombat then LoggingCombat(false) end
            SetState("idle")
        elseif state == "stopped" then
            SetState("idle")
        end
    end)

    function f.UpdateUI()
        -- Target line
        local tName = UnitName("target") or lastDummyName
        if tName then
            f.targetLabel:SetText("Target: |cffffd200" .. tName .. "|r")
        else
            f.targetLabel:SetText("Target: |cff888888(none)|r")
        end

        -- State badge + button label + verdict line.
        -- Verdict shows only in "stopped" state (Log: CLEAN/INVALID).
        f.verdictLabel:Hide()
        if state == "idle" then
            f.stateBadge:SetText("IDLE")
            f.stateBadge:SetTextColor(0.7, 0.7, 0.7)
            f.actionBtn:SetText("Ready")
        elseif state == "armed" then
            f.stateBadge:SetText("ARMED")
            f.stateBadge:SetTextColor(1, 0.8, 0.2)
            f.actionBtn:SetText("Cancel")
        elseif state == "logging" then
            f.stateBadge:SetText("LOGGING")
            f.stateBadge:SetTextColor(0.2, 0.9, 0.2)
            f.actionBtn:SetText("Stop")
        elseif state == "stopping" then
            -- T+1:20 to T+1:30 (or until idle 3s). Marker has been emitted
            -- (or skipped). Tail period before LoggingCombat(false).
            f.stateBadge:SetText("STOPPING...")
            f.stateBadge:SetTextColor(1, 0.7, 0.2)
            f.actionBtn:SetText("Stop")
        elseif state == "stopped" then
            f.stateBadge:SetText("STOPPED")
            f.stateBadge:SetTextColor(0.6, 0.6, 0.6)
            f.actionBtn:SetText("Reset")
            -- Verdict line. CLEAN requires markerVerified (see
            -- IsCleanVerdict — listens for the SPELL_CAST_FAILED line
            -- to confirm the marker actually reached the log file).
            if IsCleanVerdict() then
                f.verdictLabel:SetText("Log: |cff66ff66CLEAN|r - valid for upload")
            else
                f.verdictLabel:SetText("Log: |cffff6666INVALID|r - rejected on upload")
            end
            f.verdictLabel:Show()
        end

        -- Timer + progress bar
        local progressFraction = 0
        if (state == "logging" or state == "stopping") and fightStartTime then
            local elapsed = GetTime() - fightStartTime
            local capped = math.min(elapsed, LOG_DURATION_SEC)
            progressFraction = capped / LOG_DURATION_SEC
            f.timerLabel:SetText(string.format("%d:%02d / 1:30",
                floor(capped / 60), floor(capped % 60)))
            if state == "stopping" then
                -- Gold color during the tail. Doesn't reveal verdict yet.
                f.progressFg:SetVertexColor(1, 0.78, 0.18, 1)
            else
                f.progressFg:SetVertexColor(0.2, 0.7, 0.2, 1)
            end
        elseif state == "stopped" then
            progressFraction = 1
            f.timerLabel:SetText("1:30 / 1:30")
            if IsCleanVerdict() then
                f.progressFg:SetVertexColor(0.4, 1, 0.4, 1) -- green for clean
            else
                f.progressFg:SetVertexColor(1, 0.4, 0.4, 1) -- red for invalid
            end
        else
            f.timerLabel:SetText("0:00 / 1:30")
            f.progressFg:SetVertexColor(0.4, 0.4, 0.4, 1)
        end
        local barFull = f:GetWidth() - 40
        f.progressFg:SetWidth(math.max(1, barFull * progressFraction))

        -- Auto-log checkbox state from saved config
        local autoLog = (EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.dummyAutoLog) or false
        f.autoLogCheck:SetChecked(autoLog)

        -- Player auras list — ASCII markers, tighter rows.
        -- "[+]" green for allowed, "[x]" red for not allowed. 12px row pitch.
        local PA_MAX = 8
        local nP = #currentPlayerAuras
        f.playerAurasLabel:SetText(string.format("|cffffd200Player Auras|r |cff888888(%d)|r", nP))
        for i = 1, PA_MAX do
            local fs = f.playerAuraTexts[i]
            if not fs then
                fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", f, "TOPLEFT", 14, PA_TOP - (i - 1) * 12)
                fs:SetPoint("RIGHT", f, "RIGHT", -14, 0)
                fs:SetJustifyH("LEFT")
                f.playerAuraTexts[i] = fs
            end
            local a = currentPlayerAuras[i]
            if a then
                local marker = a.allowed and "|cff66ff66+|r" or "|cffff6666x|r"
                local nameColor = a.allowed and "|cffffffff" or "|cffff9999"
                fs:SetText(string.format("%s %s%s|r |cff888888(%s)|r",
                    marker, nameColor, a.name, a.source))
                fs:Show()
            else
                fs:Hide()
            end
        end

        -- Target debuffs list (max 4 rows, dummies typically have few)
        local TD_MAX = 4
        local nT = #currentTargetDebuffs
        f.targetDebuffsLabel:SetText(string.format("|cffffd200Target Debuffs|r |cff888888(%d)|r", nT))
        for i = 1, TD_MAX do
            local fs = f.targetDebuffTexts[i]
            if not fs then
                fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", f, "TOPLEFT", 14, TD_TOP - (i - 1) * 12)
                fs:SetPoint("RIGHT", f, "RIGHT", -14, 0)
                fs:SetJustifyH("LEFT")
                f.targetDebuffTexts[i] = fs
            end
            local a = currentTargetDebuffs[i]
            if a then
                local marker = a.allowed and "|cff66ff66+|r" or "|cffff6666x|r"
                local nameColor = a.allowed and "|cffffffff" or "|cffff9999"
                fs:SetText(string.format("%s %s%s|r |cff888888(%s)|r",
                    marker, nameColor, a.name, a.source))
                fs:Show()
            else
                fs:Hide()
            end
        end
    end

    return f
end

-- ============================================================================
-- Public toggle (called from /epogarmory dummy)
-- ============================================================================

-- Re-anchor to the top-left of the screen every time the frame is shown,
-- per user preference. Users can drag it during a session but next open
-- snaps back to top-left.
local function AnchorTopLeft(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
end

_G.EpogArmoryDummy_Toggle = function()
    if not frame then frame = BuildFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        -- Reset from "stopped" state so the new view starts fresh.
        -- "armed", "logging", "stopping" states are preserved (parse
        -- may still be ongoing in the background).
        if state == "stopped" then SetState("idle") end
        AnchorTopLeft(frame)
        ValidateNow()
        frame:Show()
        frame.UpdateUI()
    end
end

-- ============================================================================
-- Init + event wiring
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_AURA")
-- Claude (v1.6.1): hit detection for idle-stop during the 1:20-1:30
-- stopping window. Need to know when the player or pet last damaged
-- the dummy so we can early-out the parse if they disengage.
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- Sub-flag bit COMBATLOG_OBJECT_AFFILIATION_MINE = 0x1.
-- Set on combat log events sourced from the player or their pet/totem.
local AFFILIATION_MINE_BIT = 0x1

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        if EpogArmoryDB.config.dummyAutoLog == nil then
            EpogArmoryDB.config.dummyAutoLog = false
        end
        EpogArmoryDB.dummyFights = EpogArmoryDB.dummyFights or {}
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Auto-open the frame when the user targets a dummy in a rested
        -- area. Fires when state is "idle" OR "stopped" (re-target
        -- after a finished parse should re-open for a fresh run).
        -- Skipped during "armed", "logging", or "stopping" so we don't
        -- disturb an in-progress parse if the user briefly retargets
        -- something else and back.
        if IsDummyTargeted() and IsCity()
           and (state == "idle" or state == "stopped")
        then
            if state == "stopped" then SetState("idle") end
            if not frame then frame = BuildFrame() end
            if not frame:IsShown() then
                AnchorTopLeft(frame)
                frame:Show()
            end
            ValidateNow()
            frame.UpdateUI()
        end
        if frame and frame:IsShown() then
            -- Live target line update on every target change while open
            ValidateNow()
            frame.UpdateUI()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnEnterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnLeaveCombat()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player"
           or (savedDummyGUID and unit and UnitGUID(unit) == savedDummyGUID)
        then
            -- Inside logging/stopping, this re-evaluates and may flip
            -- validThroughout. Inside armed, it's a preview update.
            if state == "logging" or state == "stopping" or state == "armed" then
                ValidateNow()
                if frame and frame:IsShown() then frame.UpdateUI() end
            end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Hot path — fires many times per second in combat. Bail early.
        if state ~= "logging" and state ~= "stopping" then return end
        -- 3.3.5 signature: timestamp, subevent, sourceGUID, sourceName,
        -- sourceFlags, destGUID, destName, destFlags, spellID, spellName,
        -- spellSchool, [event-specific args]...
        local _, subevent, _, _, sourceFlags, destGUID, _, _, spellID, spellName = ...
        if not sourceFlags or bit.band(sourceFlags, AFFILIATION_MINE_BIT) == 0 then
            return
        end

        -- Marker verification: SPELL_CAST_FAILED for our marker spell from
        -- us means the cast attempt actually landed in the combat log.
        -- Match on spell ID (locale-independent) primarily, with name as
        -- a fallback in case Epoch reassigned the ID.
        if subevent == "SPELL_CAST_FAILED"
           and (spellID == MARKER_SPELL_ID or spellName == MARKER_SPELL_NAME)
        then
            markerVerified = true
            return -- not a hit on the dummy
        end

        -- Hit detection on the dummy (idle-stop trigger). Damage / miss
        -- events from us or our pet count as "still attacking".
        if not savedDummyGUID or destGUID ~= savedDummyGUID then return end
        if subevent == "SWING_DAMAGE"  or subevent == "SWING_MISSED"
        or subevent == "SPELL_DAMAGE"  or subevent == "SPELL_MISSED"
        or subevent == "RANGE_DAMAGE"  or subevent == "RANGE_MISSED"
        or subevent == "SPELL_PERIODIC_DAMAGE" then
            lastDummyHitTime = GetTime()
        end
    end
end)

local tickAcc = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    tickAcc = tickAcc + elapsed
    if tickAcc < TICK_INTERVAL then return end
    tickAcc = 0
    OnTick()
end)
