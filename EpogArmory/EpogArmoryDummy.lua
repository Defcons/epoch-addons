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

-- Substring match on UnitName("target"). Catches all standard variants
-- ("Training Dummy", "Combat Training Dummy", "Expert's Training Dummy",
-- "Heroic Training Dummy") with one rule.
local DUMMY_NAME_PATTERN = "Training Dummy"

-- Marker spell. CastSpellByName uses this exact string.
local MARKER_SPELL_NAME  = "Hearthstone"

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
local state              = "idle"       -- "idle" | "armed" | "logging" | "complete"
local fightStartTime     = nil          -- GetTime() when combat started
local validThroughout    = true         -- sticky false on any violation
local invalidReasons     = {}           -- set of reason strings
local markerEmitted      = false        -- true once we've attempted the cast
local lastDummyName      = nil
local savedDummyGUID     = nil          -- saved at combat start

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
-- how to fake validation). What's visible: brief red error flash + a
-- short interrupt sound.
--
-- CRITICAL: the cast and the stop MUST happen across separate frames.
-- WoW's client queues spell casts to send to the server on the next
-- network tick. If we call CastSpellByName + SpellStopCasting in the
-- same Lua frame, the client cancels the queued cast BEFORE sending
-- anything to the server — no SPELL_CAST_START event, no log line.
-- The marker silently fails. (Verified empirically: the first test
-- run produced "CLEAN" verdict but the log file had zero Hearthstone
-- lines.) We defer the stop by ~150ms via an OnUpdate timer so the
-- start has time to round-trip.

local _restoreUIErrors = CreateFrame("Frame")
_restoreUIErrors:Hide()
local _restoreElapsed = 0
_restoreUIErrors:SetScript("OnUpdate", function(self, e)
    _restoreElapsed = _restoreElapsed + e
    if _restoreElapsed >= 0.6 then
        self:Hide()
        _restoreElapsed = 0
        if UIErrorsFrame then UIErrorsFrame:Show() end
    end
end)

local _stopCastFrame = CreateFrame("Frame")
_stopCastFrame:Hide()
local _stopElapsed = 0
_stopCastFrame:SetScript("OnUpdate", function(self, e)
    _stopElapsed = _stopElapsed + e
    if _stopElapsed >= 0.15 then
        self:Hide()
        _stopElapsed = 0
        if SpellStopCasting then SpellStopCasting() end
    end
end)

local function EmitMarker()
    -- Suppress the error-text flash for 0.6s (covers cast + stop + a bit).
    if UIErrorsFrame then UIErrorsFrame:Hide() end
    _restoreElapsed = 0
    _restoreUIErrors:Show()

    -- Start the cast. Server receives it on next network tick.
    if CastSpellByName then CastSpellByName(MARKER_SPELL_NAME) end

    -- Schedule the stop ~150ms later so the START event has a chance to
    -- reach the server and be echoed back into the combat log file before
    -- the stop cancels it.
    _stopElapsed = 0
    _stopCastFrame:Show()
end

-- ============================================================================
-- State transitions
-- ============================================================================

local function SetState(newState)
    state = newState
    if frame and frame.UpdateUI then frame.UpdateUI() end
end

local function PrintVerdict()
    -- Generic verdict that doesn't reveal the marker mechanism. Users
    -- should only see "your parse was clean" or "your parse was invalid
    -- with these reasons" — not the internal validation trick.
    if validThroughout and markerEmitted then
        print("|cffffaa44EpogArmory|r: |cff66ff66CLEAN dummy parse|r - log is valid for upload.")
    else
        print("|cffffaa44EpogArmory|r: |cffff6666INVALID dummy parse|r - log will be rejected. Reasons:")
        local count = 0
        for reason in pairs(invalidReasons) do
            print("  |cffaaaaaa-|r " .. reason)
            count = count + 1
        end
        if count == 0 then
            print("  |cffaaaaaa-|r (no specific reason captured)")
        end
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
        valid          = (validThroughout and markerEmitted) or false,
        invalidReasons = reasonsList,
        markerEmitted  = markerEmitted,
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
    lastDummyName     = UnitName("target")
    savedDummyGUID    = UnitGUID("target")

    -- Initial aura check (T+0). If we start with junk auras already on,
    -- validThroughout flips false immediately and the marker won't emit.
    if LoggingCombat then LoggingCombat(true) end
    SetState("logging")
    ValidateNow()
    return true
end

local function FinishFight(reason)
    if state ~= "logging" then return end
    if LoggingCombat then LoggingCombat(false) end
    if reason and not invalidReasons[reason] then
        invalidReasons[reason] = true
        validThroughout = false
    end
    SetState("complete")
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
    if state ~= "logging" then return end
    local elapsed = GetTime() - (fightStartTime or GetTime())
    if elapsed < MARKER_TIME_SEC then
        -- Fight ended before the marker would have fired. Treat as failed.
        FinishFight("fight ended before 1:20 — log truncated")
    end
    -- Between 1:20 and 1:30: let the timer run out (marker is already
    -- in the log file).
end

local function OnTick()
    if state == "armed" then
        -- Preview aura check so the user can see what's clean BEFORE
        -- starting the fight. Doesn't write to invalidReasons.
        ValidateNow()
        if frame and frame:IsShown() then frame.UpdateUI() end
        return
    end
    if state ~= "logging" then return end

    local elapsed = GetTime() - (fightStartTime or GetTime())

    -- Belt-and-suspenders aura recheck. UNIT_AURA also drives validation,
    -- this is the redundant timer-based check.
    ValidateNow()

    -- Marker emission at 1:20 (only if the fight stayed clean).
    if elapsed >= MARKER_TIME_SEC and not markerEmitted then
        if validThroughout then
            EmitMarker()
        end
        markerEmitted = true -- "attempted", don't retry even if conditions degrade
    end

    -- Auto-stop logging at 1:30.
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
        elseif state == "logging" then
            -- Manual stop. No marker, no verdict print (user knows they cancelled).
            if LoggingCombat then LoggingCombat(false) end
            SetState("idle")
        elseif state == "complete" then
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

        -- State badge + button label
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
        elseif state == "complete" then
            -- Plain ASCII text. The default WoW fonts in 3.3.5 don't
            -- include the Unicode check/cross glyphs (they rendered as
            -- "?" before this change).
            if validThroughout and markerEmitted then
                f.stateBadge:SetText("CLEAN")
                f.stateBadge:SetTextColor(0.4, 1, 0.4)
            else
                f.stateBadge:SetText("INVALID")
                f.stateBadge:SetTextColor(1, 0.4, 0.4)
            end
            f.actionBtn:SetText("Reset")
        end

        -- Timer + progress bar
        local progressFraction = 0
        if state == "logging" and fightStartTime then
            local elapsed = GetTime() - fightStartTime
            local capped = math.min(elapsed, LOG_DURATION_SEC)
            progressFraction = capped / LOG_DURATION_SEC
            f.timerLabel:SetText(string.format("%d:%02d / 1:30",
                floor(capped / 60), floor(capped % 60)))
            if elapsed >= MARKER_TIME_SEC then
                f.progressFg:SetVertexColor(1, 0.78, 0.18, 1)
            else
                f.progressFg:SetVertexColor(0.2, 0.7, 0.2, 1)
            end
        elseif state == "complete" then
            progressFraction = 1
            f.timerLabel:SetText("1:30 / 1:30")
            if validThroughout and markerEmitted then
                f.progressFg:SetVertexColor(1, 0.85, 0.2, 1)
            else
                f.progressFg:SetVertexColor(0.9, 0.3, 0.3, 1)
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
        -- Reset from "complete" state so the new view starts fresh.
        -- "armed" and "logging" states are preserved (parse may still be
        -- ongoing in the background).
        if state == "complete" then SetState("idle") end
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
        -- area. Fires when state is "idle" OR "complete" (re-target
        -- after a finished parse should re-open for a fresh run).
        -- Skipped during "armed" or "logging" so we don't disturb an
        -- in-progress parse if the user briefly retargets something else
        -- and back.
        if IsDummyTargeted() and IsCity()
           and (state == "idle" or state == "complete")
        then
            if state == "complete" then SetState("idle") end
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
            -- Inside logging, this re-evaluates and may flip validThroughout.
            -- Inside armed, it's a preview update.
            if state == "logging" or state == "armed" then
                ValidateNow()
                if frame and frame:IsShown() then frame.UpdateUI() end
            end
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
