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

-- Marker: Fishing primary, Basic Campfire fallback.
--
-- Primary: `/cast Fishing` produces SPELL_CAST_FAILED with reason
-- "Must have a Fishing Pole equipped" — verified empirically. Fails
-- INSTANTLY — single log line, no SpellStopCasting timing required.
-- Universal: every character can attempt `/cast Fishing` (spell id 7620
-- is hardcoded in the client, not gated by learning the profession).
--
-- Edge case: if the player has a Fishing Pole equipped, /cast Fishing
-- SUCCEEDS instead of failing — producing SPELL_CAST_START not FAILED.
-- That breaks our marker. Real-world likelihood is tiny (no DPS spec
-- equips a pole), but the fallback covers it for players who also
-- have Cooking learned: `/cast Basic Campfire` will fail with its own
-- SPELL_CAST_FAILED ("You can't do that here" / "Try this outside")
-- in a city near a dummy.
--
-- The macro chains both lines. Both /cast lines execute in sequence;
-- whichever produces a SPELL_CAST_FAILED is accepted as the marker.
-- The MARKER_SPELL_NAMES table is keyed by name for O(1) lookup in CLEU.
--
-- The marker fires via a SecureActionButtonTemplate that the user clicks.
-- Addon-script CastSpellByName silently fails on Epoch (proven by the
-- 21:00 /epogtest run: GetSpellInfo='Fishing' resolved but no CLEU
-- event after CastSpellByName call). The protection model requires a
-- hardware event (button click / keypress on secure button) to elevate
-- the call to a secure execution context. So the addon UI prompts the
-- user to click a button at the end of the parse — that single click
-- is the only manual step.
local MARKER_SPELL_NAMES        = {
    ["Fishing"]        = true,  -- Claude v1.7.1: primary marker, fails on no pole
    ["Basic Campfire"] = true,  -- Claude v1.7.1: fallback for pole-equipped + Cooking-learned players
}
local MARKER_MACROTEXT          = "/cast Fishing\n/cast Basic Campfire"  -- Claude v1.7.1: chain both attempts; either FAILED line is a valid marker
local MARKER_VERIFY_TIMEOUT     = 3.0  -- seconds to wait for CLEU after click
-- Claude v1.7.2: strict 10s validate window. Was POST_COMBAT_HARD_TIMEOUT=120
-- which gave the user effectively unlimited time to click; in practice the
-- 90s log file would close cleanly but the marker could land ~100s+ in
-- (epoglogs report: marker at T+103s). The site now caps every parse at
-- a canonical 90s for leaderboard fairness, so the addon's job is purely
-- UX: make it OBVIOUS when the click window opens and closes.
--
-- Window matches LOG_DURATION_SEC - MARKER_TIME_SEC (90 - 80 = 10).
-- Hard-fail at end of window with "LOG FAILED - click Reset to try again".
local VALIDATE_WINDOW_SEC       = LOG_DURATION_SEC - MARKER_TIME_SEC

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
local state              = "idle"       -- "idle" | "armed" | "logging" | "stopping" | "stopped" | "practice"
local wasPractice        = false        -- v1.7.10: true when current "stopped" state came from practice (not a real log)
local fightStartTime     = nil          -- GetTime() when combat started
local validThroughout    = true         -- sticky false on any violation
local invalidReasons     = {}           -- set of reason strings
local markerEmitted      = false        -- true once EmitMarker() ran
local markerVerified     = false        -- true once SPELL_CAST_FAILED/START for our marker was seen in CLEU
local pendingMarker      = false        -- true after T+1:20 if validThroughout — emit on combat end
local lastDummyName      = nil
local savedDummyGUID     = nil          -- saved at combat start
local lastDummyHitTime   = 0            -- GetTime() of last player/pet damage on dummy
local stoppingStartTime  = nil          -- GetTime() when state entered "stopping" (for hard timeout)
local fightTotalDamage   = 0            -- sum of damage from player+pet to dummy this fight
local logFilename        = nil          -- expected combat-log filename, computed when LoggingCombat(true) fires
local testMode           = false        -- Claude v1.7.1: /epogarmory testvalidate — short-circuit straight to "stopping" so user can click Validate without doing a full parse

-- ----- AoE-dummy detection (epoglogs v0.86.6+ server rejection mirror) -----
-- Server-side parser (js/parser.js ~140-158, ~1240) rejects any upload
-- whose log contains a fight where the player damaged 2+ training
-- dummies. The dummy leaderboards on epoglogs.com/dummy-stats are
-- single-target only — Expert's (L60) and Heroic (L63) have very
-- different EHP curves, so AoE rotations would pollute rankings.
--
-- Local mirror: track every distinct dummy GUID destName-matched
-- during a fight that isn't savedDummyGUID. If at least one extra
-- dummy was hit, the fight is AoE; on Project Epoch we skip the
-- save entirely (matches server intent: don't record what won't
-- upload). On CoA the same fight stays a valid capture — AoE
-- rotations are legitimate content there.
local aoeExtraDummyGUIDs = {}           -- {[guid]=true} dummies OTHER than savedDummyGUID
local aoeExtraDummyName  = nil          -- first extra dummy name seen — popup detail
-- Realm gating. Override list lives in EpogArmoryDB.skipAoERealms when
-- the user needs to add an exact realm string the defaults miss; the
-- login chat message in EpogArmory.lua surfaces the resolved realm so
-- the user can copy/paste it.
local DEFAULT_SKIP_AOE_REALMS = {
    ["Project Epoch"] = true,
    ["Epoch"]         = true,
    ["ProjectEpoch"]  = true,
}
local function ShouldSkipAoEOnThisRealm()
    local realm = (GetRealmName and GetRealmName()) or ""
    local override = EpogArmoryDB and EpogArmoryDB.skipAoERealms
    if type(override) == "table" then
        return override[realm] == true
    end
    return DEFAULT_SKIP_AOE_REALMS[realm] == true
end
local function CountKeys(t)
    if not t then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

StaticPopupDialogs["EPOGARMORY_AOE_DUMMY_REJECTED"] = {
    text = "EpogArmory: AoE dummy session ignored.\n\nepoglogs.com leaderboards are single-target only. Hit one Training Dummy at a time for valid uploads.",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

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

-- Marker emission now happens via the user clicking a SecureActionButton
-- created in BuildFrame. The button's macrotext is "/cast Fishing", which
-- when triggered by hardware-event click executes in a secure context and
-- produces a SPELL_CAST_FAILED line in the combat log file. The CLEU
-- handler listens for that line and sets markerVerified=true.
--
-- See `EpogArmoryValidateButton` creation in BuildFrame for the actual
-- secure-button wiring.

local function _DebugPrint(msg)
    if EpogArmoryDebug then
        print("|cffffaa44EpogArmory|r |cff888888[dummy-debug]|r " .. msg)
    end
end

-- Compact integer formatter with thousands-separator commas. 12345 → "12,345".
-- Used by the DPS / total-damage UI line.
local function FmtNum(n)
    n = math.floor(tonumber(n) or 0)
    if n < 1000 then return tostring(n) end
    local s = tostring(n)
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- UIErrorsFrame suppression around the button click. Hides the red
-- "Must have a Fishing Pole equipped" flash so the user (and any
-- onlookers) don't see what the button actually does. The button's
-- PreClick handler hides UIErrorsFrame and shows _restoreUIErrors;
-- the OnUpdate timer below restores UIErrorsFrame after 0.8s.
local _restoreUIErrors = CreateFrame("Frame")
_restoreUIErrors:Hide()
local _restoreElapsed = 0
_restoreUIErrors:SetScript("OnUpdate", function(self, e)
    _restoreElapsed = _restoreElapsed + e
    if _restoreElapsed >= 0.8 then
        self:Hide()
        _restoreElapsed = 0
        if UIErrorsFrame then UIErrorsFrame:Show() end
    end
end)

-- Kept for diagnostic / debug print path. The actual cast happens via
-- the secure button's macrotext attribute when the user clicks it.
local function EmitMarker()
    _DebugPrint("EmitMarker invoked (note: actual cast comes from secure button click)")
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
        if logFilename then
            print("  |cffaaaaaa-|r upload this file: |cffffd200" .. logFilename .. "|r")
        end
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

    -- AoE-dummy detection. Two-stage gate:
    --   1. Did we damage any dummy OTHER than savedDummyGUID this
    --      fight? (aoeExtraDummyGUIDs is non-empty)
    --   2. Is this realm one where the epoglogs server rejects AoE?
    --
    -- Both true → skip the save entirely and warn the user. The session
    -- never lands in EpogArmoryDB.dummyFights, so it can't be exported
    -- or accidentally uploaded. Matches server-side rejection (parser
    -- regex /\bTraining Dummy\b/ on destName, set-size >= 2).
    --
    -- One true (AoE on non-PE realm like CoA) → save normally but tag
    -- with aoe = true and aoeExtraDummyCount so downstream analytics
    -- can distinguish ST runs from AoE training.
    local extraDummyCount = CountKeys(aoeExtraDummyGUIDs)
    if extraDummyCount > 0 and ShouldSkipAoEOnThisRealm() then
        print("|cffffaa44EpogArmory|r: |cffff5555AoE dummy session ignored|r — "
            .. "hit " .. (extraDummyCount + 1) .. " dummies (e.g. "
            .. (aoeExtraDummyName or "?") .. "). "
            .. "epoglogs accepts single-target only.")
        StaticPopup_Show("EPOGARMORY_AOE_DUMMY_REJECTED")
        return
    end

    local reasonsList = {}
    for reason in pairs(invalidReasons) do
        reasonsList[#reasonsList + 1] = reason
    end

    local elapsed = (fightStartTime and (GetTime() - fightStartTime)) or 0
    local cappedSecs = math.min(elapsed, LOG_DURATION_SEC)
    local recordedDps = cappedSecs > 0 and (fightTotalDamage / cappedSecs) or 0
    table.insert(EpogArmoryDB.dummyFights, {
        endTime        = floor(time()),
        durationSec    = floor(elapsed),
        dummyName      = lastDummyName,
        dummyGUID      = savedDummyGUID,
        valid          = IsCleanVerdict(),
        invalidReasons = reasonsList,
        markerEmitted  = markerEmitted,
        markerVerified = markerVerified,
        totalDamage    = floor(fightTotalDamage),
        dps            = floor(recordedDps + 0.5),
        logFilename    = logFilename,
        addonVersion   = GetAddOnMetadata and GetAddOnMetadata("EpogArmory", "Version") or "?",
        -- AoE metadata (only populated when the fight actually hit
        -- multiple dummies AND we didn't skip the save above — i.e.
        -- the AoE-allowed-on-this-realm path). Lets epoglogs / offline
        -- parsers tell ST runs apart from AoE training.
        aoe                  = extraDummyCount > 0 or nil,
        aoeExtraDummyCount   = extraDummyCount > 0 and extraDummyCount or nil,
        aoeExtraDummyName    = extraDummyCount > 0 and aoeExtraDummyName or nil,
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
    pendingMarker     = false
    stoppingStartTime = nil
    fightTotalDamage  = 0
    lastDummyName     = UnitName("target")
    savedDummyGUID    = UnitGUID("target")
    lastDummyHitTime  = GetTime() -- count the start of combat as "just hit"
    wasPractice       = false    -- v1.7.10: defensive — real log clears the practice flag
    aoeExtraDummyGUIDs = {}      -- per-fight AoE-dummy detection set
    aoeExtraDummyName  = nil

    -- Initial aura check (T+0). If we start with junk auras already on,
    -- validThroughout flips false immediately and the marker won't emit.
    if LoggingCombat then LoggingCombat(true) end
    -- Capture the expected combat-log filename. WoW's client opens the
    -- log file with a timestamp matching the moment /combatlog fires,
    -- formatted as "YYYY-MM-DD-HH.MM.SS WoWCombatLog.txt" on Epoch.
    -- Captured immediately after LoggingCombat(true) so our timestamp
    -- is within ~1s of the actual file's timestamp.
    logFilename = date("Logs/%Y-%m-%d-%H.%M.%S WoWCombatLog.txt")
    SetState("logging")
    ValidateNow()
    return true
end

-- v1.7.10: practice mode. When the user attacks a dummy without
-- having opted into real logging (config.dummyAutoLog == false), we
-- still want to show DPS + timer + auras as a free DPS meter. This
-- function mirrors DoStartLogging's state setup but skips the actual
-- LoggingCombat call — no file is written, no marker fires, no
-- 1:30 limit is enforced.
--
-- State transitions:
--   idle -(combat with dummy, auto-log OFF)-> practice
--   practice -(combat ends OR Stop clicked)-> stopped (with wasPractice=true)
--   stopped -(Reset)-> idle
local function DoStartPractice()
    if not IsDummyTargeted() then return false end
    if not IsCity() then return false end

    fightStartTime    = GetTime()
    validThroughout   = true   -- not validated in practice; reset for consistency
    invalidReasons    = {}
    markerEmitted     = false
    markerVerified    = false
    pendingMarker     = false
    stoppingStartTime = nil
    fightTotalDamage  = 0
    lastDummyName     = UnitName("target")
    savedDummyGUID    = UnitGUID("target")
    lastDummyHitTime  = GetTime()
    logFilename       = nil    -- no file in practice mode
    wasPractice       = false  -- gets flipped true when practice transitions to stopped
    aoeExtraDummyGUIDs = {}    -- per-fight AoE-dummy detection set (mirrored from real-log path)
    aoeExtraDummyName  = nil

    -- The key difference from DoStartLogging: NO LoggingCombat(true).
    -- /combatlog stays in whatever state the user had it in (almost
    -- always off, since practice is the no-log path).

    SetState("practice")
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
    -- Claude v1.7.1: testMode prints its own verdict (focused on whether
    -- the marker round-trip worked, not the parse verdict) and does NOT
    -- save to history. Clear the flag at the end so future real parses
    -- run normally.
    if testMode then
        if markerVerified then
            print("|cffffaa44EpogArmory|r [testvalidate]: |cff66ff66MARKER VERIFIED|r — the secure-button mechanism works on this client.")
            if logFilename then
                print("  |cffaaaaaa-|r marker line is in: |cffffd200" .. logFilename .. "|r")
            end
        else
            print("|cffffaa44EpogArmory|r [testvalidate]: |cffff6666MARKER NOT VERIFIED|r — Validate was not clicked, or the cast produced no CLEU event.")
            print("  |cffaaaaaa-|r if you didn't click Validate, run /epogarmory testvalidate again and click the green button before it times out.")
            print("  |cffaaaaaa-|r if you DID click and still see this, the marker mechanism is broken on this client — report it.")
        end
        testMode = false
        return
    end
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
    -- v1.7.10: from idle + dummy + city, branch on dummyAutoLog:
    --   ON  → real /combatlog session (DoStartLogging)
    --   OFF → practice mode (DPS meter without log file)
    -- Practice fires by default if the user hasn't opted into logging,
    -- so the addon doubles as a free DPS readout when they're just
    -- training on a dummy.
    if state == "idle" and IsDummyTargeted() and IsCity() then
        local autoLog = EpogArmoryDB and EpogArmoryDB.config
            and EpogArmoryDB.config.dummyAutoLog
        if autoLog then
            DoStartLogging()
        else
            DoStartPractice()
        end
    end
end

-- After the secure button click fires the cast, wait briefly for CLEU
-- to confirm the SPELL_CAST_FAILED line landed in the log file. Then
-- stop logging.
local _markerVerifyFrame = CreateFrame("Frame")
_markerVerifyFrame:Hide()
local _verifyStartTime = 0
local function StartMarkerVerifyWait()
    _verifyStartTime = GetTime()
    markerEmitted = true
    _markerVerifyFrame:Show()
end
_markerVerifyFrame:SetScript("OnUpdate", function(self)
    local waited = GetTime() - _verifyStartTime
    if markerVerified or waited >= MARKER_VERIFY_TIMEOUT then
        _DebugPrint(string.format("marker verify wait ended after %.2fs, markerVerified=%s",
            waited, tostring(markerVerified)))
        self:Hide()
        FinishFight(nil)
    end
end)

local function OnLeaveCombat()
    _DebugPrint(string.format("PLAYER_REGEN_ENABLED fired. state=%s, elapsed=%.1f",
        state, fightStartTime and (GetTime() - fightStartTime) or -1))
    -- v1.7.10: practice mode terminates cleanly on combat end. No log
    -- to stop, no verdict to compute — just freeze the final DPS and
    -- transition to "stopped" so the user can see the result.
    if state == "practice" then
        wasPractice = true
        SetState("stopped")
        return
    end
    if state ~= "logging" and state ~= "stopping" then return end
    local elapsed = GetTime() - (fightStartTime or GetTime())

    if elapsed < MARKER_TIME_SEC then
        -- Fight ended before T+1:20 — too short for a valid parse.
        -- No marker, no chance to verify. Stop the log immediately.
        FinishFight("fight ended before 1:20 — log truncated")
        return
    end

    -- We're past T+1:20 and out of combat. The validate button becomes
    -- clickable now — user must click to emit the marker. We do NOT
    -- auto-emit because CastSpellByName from addon code doesn't produce
    -- combat-log entries on Epoch (protection model requires a hardware
    -- event). The user's click on the secure button is that event.
    --
    -- If they don't click within VALIDATE_WINDOW_SEC seconds of
    -- entering stopping, OnTick force-finishes with no marker and
    -- shows "LOG FAILED - click Reset to try again".
    if frame and frame:IsShown() then frame.UpdateUI() end
end

local function OnTick()
    if state == "armed" then
        -- Preview aura check so the user can see what's clean BEFORE
        -- starting the fight. Doesn't write to invalidReasons.
        ValidateNow()
        if frame and frame:IsShown() then frame.UpdateUI() end
        return
    end
    -- v1.7.10: practice mode tick — refresh UI for live DPS/timer,
    -- update aura listings, but DON'T enforce 1:30 or run the marker
    -- flow. Practice runs as long as combat lasts.
    if state == "practice" then
        ValidateNow() -- updates currentPlayerAuras/currentTargetDebuffs for display
        if frame and frame:IsShown() then frame.UpdateUI() end
        return
    end
    if state ~= "logging" and state ~= "stopping" then return end

    local elapsed = GetTime() - (fightStartTime or GetTime())

    -- Claude v1.7.1: testMode short-circuits both aura validation and
    -- the post-combat timeout. The test is purely about exercising
    -- the marker round-trip (click -> /cast Fishing -> CLEU FAILED ->
    -- markerVerified), not about validating a real parse. Skip the
    -- normal tick logic entirely; the user clicks Validate at their
    -- leisure and the existing PostClick + StartMarkerVerifyWait
    -- handles the rest.
    if testMode then
        if frame and frame:IsShown() then frame.UpdateUI() end
        return
    end

    -- Belt-and-suspenders aura recheck. UNIT_AURA also drives validation,
    -- this is the redundant timer-based check.
    ValidateNow()

    -- T+1:20 transition: logging -> stopping. We DON'T emit the marker
    -- here — combat lockdown blocks CastSpellByName from addon scripts.
    -- Instead, set pendingMarker so OnLeaveCombat (out of combat, no
    -- lockdown) can emit it. The site only needs the marker to be
    -- somewhere in the /combatlog window, not at a specific timestamp.
    if state == "logging" and elapsed >= MARKER_TIME_SEC then
        if validThroughout then
            pendingMarker = true
        end
        stoppingStartTime = GetTime()
        SetState("stopping")
    end

    -- Stopping window: T+1:20 -> T+1:30. The user has VALIDATE_WINDOW_SEC
    -- (10s) to click the Validate button. If they click, PostClick fires
    -- the marker and StartMarkerVerifyWait calls FinishFight. If they
    -- don't click, we hard-fail here at the end of the window — log stops,
    -- no marker, "LOG FAILED" verdict shown so the user knows to Reset.
    --
    -- Claude v1.7.2: tightened from 120s open window to 10s strict.
    -- See VALIDATE_WINDOW_SEC comment above.
    if state == "stopping" and not markerEmitted then
        local stoppingFor = GetTime() - (stoppingStartTime or GetTime())
        if stoppingFor >= VALIDATE_WINDOW_SEC then
            FinishFight("validate window expired (10s)")
            return
        end
    end

    if frame and frame:IsShown() then frame.UpdateUI() end
end

-- ============================================================================
-- UI frame
-- ============================================================================

local function BuildFrame()
    local f = CreateFrame("Frame", "EpogArmoryDummyFrame", UIParent)
    -- Frame: 280 wide x 460 tall. Initial position is top-left of the
    -- screen; users can drag from there. Re-anchored to top-left on
    -- every Show (see EpogArmoryDummy_Toggle / OnEvent open paths).
    -- Height bumped from 420 to 460 to give the focal DPS display
    -- proper breathing room above the auras section.
    f:SetWidth(280); f:SetHeight(460)
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
    -- Persistent single-target reminder built into the title — epoglogs
    -- leaderboards on https://epoglogs.com/dummy-stats only accept ST
    -- parses, and the parser silently rejects any upload that contains
    -- 2+ dummies in one fight. Carrying that message into the always-
    -- visible title prevents the user from training AoE rotations and
    -- being surprised when their upload bounces.
    f.title:SetText("EpogLogs · Dummy Parse · |cffaaaaaaSingle-Target Only|r")

    -- AoE warning — hidden until the CLEU handler detects damage on a
    -- second Training Dummy GUID during the fight. Once shown it stays
    -- shown for the rest of the fight (and through "stopped" so the
    -- user sees the verdict) and gets cleared on the next start.
    f.aoeWarnLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.aoeWarnLabel:SetPoint("TOP", 0, -65)
    f.aoeWarnLabel:SetWidth(252)
    f.aoeWarnLabel:SetJustifyH("CENTER")
    f.aoeWarnLabel:SetText("|cffff5555Multi-target damage detected — fight invalidated|r")
    f.aoeWarnLabel:Hide()

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Target line (compact)
    f.targetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.targetLabel:SetPoint("TOP", 0, -30)
    f.targetLabel:SetWidth(240)
    f.targetLabel:SetJustifyH("CENTER")

    -- State badge
    f.stateBadge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.stateBadge:SetPoint("TOP", 0, -48)

    -- BIG DPS — focal element. GameFontNormalHuge (~32pt). Shown
    -- prominently above the progress bar so the user can see the
    -- live DPS at a glance.
    f.dpsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.dpsLabel:SetPoint("TOP", 0, -78)
    f.dpsLabel:SetText("")

    -- Total damage subtitle, small text directly under the big DPS.
    f.totalLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.totalLabel:SetPoint("TOP", f.dpsLabel, "BOTTOM", 0, -2)
    f.totalLabel:SetText("")

    -- Timer line (smaller, just for reference of where we are in the
    -- 1:30 window). The progress bar carries most of the visual signal.
    f.timerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.timerLabel:SetPoint("TOP", 0, -148)
    f.timerLabel:SetText("0:00 / 1:30")

    -- Verdict text. Hidden until state transitions to "stopped". Shows
    -- "Log: CLEAN" (green) or "Log: INVALID" (red).
    -- Anchored to the empty space between Target Debuffs section and
    -- the Auto-start checkbox so it doesn't overlap the aura lists.
    -- Width-constrained + centered so long strings wrap cleanly.
    f.verdictLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.verdictLabel:SetPoint("TOP", 0, -360)
    f.verdictLabel:SetWidth(252)
    f.verdictLabel:SetJustifyH("CENTER")
    f.verdictLabel:Hide()

    -- Validate button. SecureActionButtonTemplate + macrotext "/cast Fishing".
    -- Hardware click puts the cast on the secure execution path, which
    -- produces a SPELL_CAST_FAILED line in the combat log file. The
    -- addon's automatic CastSpellByName won't do this on Epoch — the
    -- protection model requires a hardware event to elevate the call.
    --
    -- IMPORTANT: Show/Hide on frames containing secure children is
    -- protected during combat lockdown. Empirically verified in user's
    -- 21:40 debug log: container.IsShown=nil after Show() in combat.
    -- Workaround: container is shown ONCE at creation (out of combat)
    -- and stays shown forever. Visibility is toggled via SetAlpha which
    -- is unprotected.
    f.validateContainer = CreateFrame("Frame", nil, f)
    f.validateContainer:SetWidth(180); f.validateContainer:SetHeight(36)
    f.validateContainer:SetPoint("TOP", 0, -340)
    f.validateContainer:Show() -- always shown; alpha controls visibility
    f.validateContainer:SetAlpha(0) -- start invisible

    f.validateBtn = CreateFrame("Button", "EpogArmoryValidateButton",
        f.validateContainer, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    f.validateBtn:SetAllPoints(f.validateContainer)
    f.validateBtn:SetText("VALIDATE PARSE")
    -- IMPORTANT: SetAttribute on SecureActionButton is protected in
    -- combat. If BuildFrame runs while user is in combat, these
    -- silently fail and the button has no action set up.
    if InCombatLockdown and InCombatLockdown() then
        _DebugPrint("WARNING: BuildFrame ran during combat lockdown — secure attributes will not be set!")
    end
    f.validateBtn:SetAttribute("type", "macro")
    f.validateBtn:SetAttribute("macrotext", MARKER_MACROTEXT)
    f.validateBtn:RegisterForClicks("AnyUp")

    -- PreClick (insecure, runs BEFORE the secure attribute fires):
    -- hide UIErrorsFrame so the "Must have a Fishing Pole equipped"
    -- error text doesn't flash and reveal what the button does.
    -- Restored 0.8s later by the _restoreUIErrors OnUpdate.
    f.validateBtn:SetScript("PreClick", function(self)
        if UIErrorsFrame then UIErrorsFrame:Hide() end
        _restoreElapsed = 0
        _restoreUIErrors:Show()
    end)

    f.validateBtn:SetScript("PostClick", function(self)
        -- Secure macrotext just fired. Combat log should capture the
        -- SPELL_CAST_FAILED line for Fishing within ~50ms. Start the
        -- verifier; FinishFight runs when it sees the CLEU event.
        _DebugPrint("validate button PostClick fired — starting verify wait")
        StartMarkerVerifyWait()
    end)

    -- Validate hint label (shown next to the button to explain it)
    f.validateHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.validateHint:SetPoint("TOP", f.validateContainer, "BOTTOM", 0, -2)
    f.validateHint:SetWidth(252)
    f.validateHint:SetJustifyH("CENTER")
    f.validateHint:Hide()

    -- Progress bar. Bumped from height 6 to 12 so it's a more prominent
    -- visual signal alongside the big DPS number above it.
    local PROGRESS_BAR_Y = -128
    local PROGRESS_BAR_HEIGHT = 12
    f.progressBg = f:CreateTexture(nil, "BACKGROUND")
    f.progressBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressBg:SetVertexColor(0.12, 0.12, 0.12, 0.85)
    f.progressBg:SetPoint("TOPLEFT", 16, PROGRESS_BAR_Y)
    f.progressBg:SetPoint("TOPRIGHT", -16, PROGRESS_BAR_Y)
    f.progressBg:SetHeight(PROGRESS_BAR_HEIGHT)

    f.progressFg = f:CreateTexture(nil, "ARTWORK")
    f.progressFg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressFg:SetVertexColor(0.2, 0.7, 0.2, 1)
    f.progressFg:SetPoint("TOPLEFT", 16, PROGRESS_BAR_Y)
    f.progressFg:SetHeight(PROGRESS_BAR_HEIGHT)
    f.progressFg:SetWidth(1)

    -- Marker tick at the "validation point" on the progress bar
    f.progressMark = f:CreateTexture(nil, "OVERLAY")
    f.progressMark:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressMark:SetVertexColor(1, 0.85, 0.2, 1)
    f.progressMark:SetWidth(2); f.progressMark:SetHeight(PROGRESS_BAR_HEIGHT + 6)
    f.progressMark:SetPoint("TOP", f.progressBg, "TOPLEFT",
        (280 - 32) * (MARKER_TIME_SEC / LOG_DURATION_SEC), 3)

    -- Player auras header. Shifted down 50px to make room for the
    -- new prominent DPS/progress section at the top.
    f.playerAurasLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.playerAurasLabel:SetPoint("TOPLEFT", 14, -164)

    local PA_TOP = -178
    f.playerAurasTop = PA_TOP
    f.playerAuraTexts = {}

    -- Target debuffs header
    f.targetDebuffsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.targetDebuffsLabel:SetPoint("TOPLEFT", 14, -286)

    local TD_TOP = -300
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
        elseif state == "practice" then
            -- v1.7.10: stop practice early. No log to close, just freeze
            -- the DPS readout by transitioning to stopped with the
            -- wasPractice flag.
            wasPractice = true
            SetState("stopped")
        elseif state == "stopped" then
            wasPractice = false
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

        -- AoE warning. Stays visible once tripped — including through
        -- the "stopped" verdict so the user sees why the fight was
        -- marked invalid. Cleared on the next DoStartLogging /
        -- DoStartPractice when aoeExtraDummyGUIDs resets to {}.
        if CountKeys(aoeExtraDummyGUIDs) > 0 then
            f.aoeWarnLabel:Show()
        else
            f.aoeWarnLabel:Hide()
        end

        -- State badge + button label + verdict line.
        -- Verdict shows only in "stopped" state (Log: CLEAN/INVALID).
        -- Validate container is always shown (set up at creation); we
        -- toggle SetAlpha to control visibility. Show/Hide on frames
        -- with secure children is protected during combat lockdown,
        -- but SetAlpha is not.
        f.verdictLabel:Hide()
        f.validateContainer:SetAlpha(0)
        f.validateHint:Hide()
        if state ~= "stopping" then f._lastStoppingSubState = nil end
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
        elseif state == "practice" then
            -- v1.7.10: practice mode — DPS meter without /combatlog file.
            -- Shown in cyan to clearly differentiate from the green
            -- "LOGGING" state that produces a real log for upload.
            f.stateBadge:SetText("PRACTICE")
            f.stateBadge:SetTextColor(0.3, 0.85, 1)
            f.actionBtn:SetText("Stop")
        elseif state == "stopping" then
            -- Past T+1:20 — user clicks VALIDATE to stamp the log AND
            -- force-stop logging.
            f.stateBadge:SetText("STOPPING...")
            f.stateBadge:SetTextColor(1, 0.7, 0.2)
            -- Action button reads "Reset" here (was "Stop") since it
            -- cancels the parse and returns to idle — "Reset" maps
            -- more cleanly to that action than "Stop" did.
            f.actionBtn:SetText("Reset")
            local subState
            if markerEmitted then
                subState = "verifying"
                f.verdictLabel:SetTextColor(1, 1, 1)
                f.verdictLabel:SetText("|cff66ff66verifying marker...|r")
                f.verdictLabel:Show()
            elseif not validThroughout then
                subState = "invalidated"
                f.verdictLabel:SetTextColor(1, 1, 1)
                f.verdictLabel:SetText("|cffff6666parse invalidated - click Reset|r")
                f.verdictLabel:Show()
            else
                subState = "show-button"
                f.validateContainer:SetAlpha(1) -- visible
                -- Claude v1.7.2: live countdown on the button label so the
                -- user can see exactly how much time they have to click.
                -- ceil() so "1" still shows during the final ~1s before
                -- FinishFight fires at the window boundary. math.max(1, ...)
                -- so it never reads "0" or negative — at the moment the
                -- window expires, OnTick triggers FinishFight in the same
                -- frame and the button disappears.
                local stoppingFor = GetTime() - (stoppingStartTime or GetTime())
                local remaining = math.max(1, math.ceil(VALIDATE_WINDOW_SEC - stoppingFor))
                f.validateBtn:SetText(string.format("VALIDATE (%d)", remaining))
                f.validateHint:SetText("|cff888888click to stamp the log and stop logging|r")
                f.validateHint:Show()
            end
            -- Debug: only print when sub-state transitions (not every tick)
            if subState ~= f._lastStoppingSubState then
                f._lastStoppingSubState = subState
                _DebugPrint(string.format("stopping sub-state -> %s (markerEmitted=%s, validThroughout=%s, container.alpha=%s, InCombat=%s)",
                    subState, tostring(markerEmitted), tostring(validThroughout),
                    tostring(f.validateContainer and f.validateContainer:GetAlpha()),
                    tostring(InCombatLockdown and InCombatLockdown())))
            end
        elseif state == "stopped" then
            f.stateBadge:SetText("STOPPED")
            f.stateBadge:SetTextColor(0.6, 0.6, 0.6)
            f.actionBtn:SetText("Reset")
            -- Verdict line. CLEAN requires markerVerified — see
            -- IsCleanVerdict above. Reset SetTextColor to white so the
            -- inline color codes show through cleanly.
            f.verdictLabel:SetTextColor(1, 1, 1)
            if wasPractice then
                -- v1.7.10: practice ended (combat ended or user clicked
                -- Stop). No upload-related verdict — just acknowledge
                -- the run. Final DPS is still shown by the dpsLabel
                -- below.
                f.verdictLabel:SetText("|cff66ccffPractice complete|r - no log file written")
            elseif IsCleanVerdict() then
                f.verdictLabel:SetText("Log: |cff66ff66CLEAN|r - valid for upload")
            elseif invalidReasons["validate window expired (10s)"] then
                -- Claude v1.7.2: explicit failure mode for the strict
                -- 10s validate window. User missed the click; prompt
                -- them clearly to Reset and try again.
                f.verdictLabel:SetText("|cffff6666LOG FAILED|r - click Reset to try again")
            else
                f.verdictLabel:SetText("Log: |cffff6666INVALID|r - rejected on upload")
            end
            f.verdictLabel:Show()
        end

        -- Big DPS focal + total damage subtitle + progress bar + timer
        local progressFraction = 0
        if (state == "logging" or state == "stopping") and fightStartTime then
            local elapsed = GetTime() - fightStartTime
            local capped = math.min(elapsed, LOG_DURATION_SEC)
            progressFraction = capped / LOG_DURATION_SEC
            f.timerLabel:SetText(string.format("%d:%02d / 1:30",
                floor(capped / 60), floor(capped % 60)))
            if state == "stopping" then
                f.progressFg:SetVertexColor(1, 0.78, 0.18, 1)
            else
                f.progressFg:SetVertexColor(0.2, 0.7, 0.2, 1)
            end
            -- Live DPS — keep it readable in the first second by clamping
            local secs = math.max(elapsed, 1)
            local dps = fightTotalDamage / secs
            f.dpsLabel:SetText(string.format("|cffaaccff%s|r |cffffffffDPS|r", FmtNum(dps)))
            f.totalLabel:SetText(string.format("|cff888888%s damage|r", FmtNum(fightTotalDamage)))
        elseif state == "practice" and fightStartTime then
            -- v1.7.10: practice mode timer counts up without a target.
            -- Format "M:SS" rather than "M:SS / 1:30" since no fixed
            -- limit applies. Progress bar shown in cyan to differentiate
            -- from the green/yellow logging/stopping shades.
            local elapsed = GetTime() - fightStartTime
            f.timerLabel:SetText(string.format("%d:%02d",
                floor(elapsed / 60), floor(elapsed % 60)))
            -- Bar grows over the 1:30 reference window then caps. Even in
            -- practice this is a useful visual of "how long have I been
            -- swinging" without us needing extra UI.
            progressFraction = math.min(elapsed / LOG_DURATION_SEC, 1)
            f.progressFg:SetVertexColor(0.3, 0.7, 1, 1) -- cyan
            local secs = math.max(elapsed, 1)
            local dps = fightTotalDamage / secs
            f.dpsLabel:SetText(string.format("|cffaaccff%s|r |cffffffffDPS|r", FmtNum(dps)))
            f.totalLabel:SetText(string.format("|cff888888%s damage (practice)|r", FmtNum(fightTotalDamage)))
        elseif state == "stopped" then
            local elapsed = fightStartTime and (GetTime() - fightStartTime) or 0
            if wasPractice then
                -- v1.7.10: practice run ended. Show actual elapsed (not
                -- capped to 1:30) and a cyan bar so the final state is
                -- clearly distinct from a real log's CLEAN/INVALID.
                progressFraction = math.min(elapsed / LOG_DURATION_SEC, 1)
                f.timerLabel:SetText(string.format("%d:%02d",
                    floor(elapsed / 60), floor(elapsed % 60)))
                f.progressFg:SetVertexColor(0.3, 0.7, 1, 1) -- cyan
            else
                progressFraction = 1
                f.timerLabel:SetText("1:30 / 1:30")
                if IsCleanVerdict() then
                    f.progressFg:SetVertexColor(0.4, 1, 0.4, 1) -- green for clean
                else
                    f.progressFg:SetVertexColor(1, 0.4, 0.4, 1) -- red for invalid
                end
            end
            local secs = wasPractice
                and math.max(elapsed, 1)
                or math.min(elapsed > 0 and elapsed or LOG_DURATION_SEC, LOG_DURATION_SEC)
            local dps = secs > 0 and (fightTotalDamage / secs) or 0
            f.dpsLabel:SetText(string.format("|cffaaccff%s|r |cffffffffDPS|r", FmtNum(dps)))
            f.totalLabel:SetText(string.format("|cff888888%s damage%s|r",
                FmtNum(fightTotalDamage), wasPractice and " (practice)" or ""))
        else
            f.timerLabel:SetText("0:00 / 1:30")
            f.progressFg:SetVertexColor(0.4, 0.4, 0.4, 1)
            f.dpsLabel:SetText("")
            f.totalLabel:SetText("")
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

-- ============================================================================
-- Diagnostic: test-cast slash command
-- ============================================================================
-- Lets the user verify whether CastSpellByName from addon code actually
-- produces a combat log entry on Epoch. Bypasses the dummy-parse
-- lifecycle entirely. Usage:
--   /epogtest Hearthstone         (default — 150ms then SpellStopCasting)
--   /epogtest Fishing             (instant fail, no stop needed)
--   /epogtest "Some Spell"        (any spell name)
--   /epogtest                     (defaults to Hearthstone)
-- Prints what was called, then waits up to 3s for a CLEU event with the
-- spell name and reports whether it landed.

local _testStopFrame = CreateFrame("Frame")
_testStopFrame:Hide()
local _testStopElapsed = 0
_testStopFrame:SetScript("OnUpdate", function(self, e)
    _testStopElapsed = _testStopElapsed + e
    if _testStopElapsed >= 0.15 then
        self:Hide()
        _testStopElapsed = 0
        if SpellStopCasting then
            SpellStopCasting()
            print("|cffffaa44EpogArmory|r [testcast] SpellStopCasting() called")
        end
    end
end)

local _testWatchFrame = CreateFrame("Frame")
_testWatchFrame:Hide()
local _testWatchStart = 0
local _testWatchSpellName = ""
local _testWatchSeen = false
_testWatchFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
_testWatchFrame:SetScript("OnEvent", function(self, event, ...)
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then return end
    local _, subevent, _, _, sourceFlags, _, _, _, spellID, spellName = ...
    if not sourceFlags or bit.band(sourceFlags, 0x1) == 0 then return end
    if spellName == _testWatchSpellName then
        if not _testWatchSeen then
            print(string.format("|cffffaa44EpogArmory|r [testcast] |cff66ff66LANDED|r in CLEU after %.2fs: %s spellID=%s",
                GetTime() - _testWatchStart, subevent, tostring(spellID)))
            _testWatchSeen = true
        end
    end
end)
_testWatchFrame:SetScript("OnUpdate", function(self, e)
    local waited = GetTime() - _testWatchStart
    if waited >= 3.0 then
        self:Hide()
        if not _testWatchSeen then
            print(string.format("|cffffaa44EpogArmory|r [testcast] |cffff6666DID NOT LAND|r — no CLEU event for '%s' in 3s",
                _testWatchSpellName))
        end
    end
end)

_G.EpogArmoryDummy_TestCast = function(spellName, stopAfter)
    spellName = (spellName and spellName ~= "") and spellName or "Hearthstone"
    print(string.format("|cffffaa44EpogArmory|r [testcast] starting test for '%s'", spellName))
    print(string.format("|cffffaa44EpogArmory|r [testcast]   InCombatLockdown=%s, GetSpellInfo='%s'",
        tostring(InCombatLockdown and InCombatLockdown() or "?"),
        tostring(GetSpellInfo and GetSpellInfo(spellName) or "nil")))

    -- Start CLEU watcher
    _testWatchSpellName = spellName
    _testWatchSeen = false
    _testWatchStart = GetTime()
    _testWatchFrame:Show()

    if not CastSpellByName then
        print("|cffffaa44EpogArmory|r [testcast] |cffff6666CastSpellByName is nil!|r")
        return
    end
    CastSpellByName(spellName)
    print(string.format("|cffffaa44EpogArmory|r [testcast]   CastSpellByName('%s') returned, no error",
        spellName))

    if stopAfter then
        _testStopElapsed = 0
        _testStopFrame:Show()
    end
end

-- Keybind support: register a binding header + a named binding for the
-- secure validate button. Users go to Keybindings UI -> EpogArmory
-- Dummy Parse -> Validate Parse to assign a hotkey.
_G["BINDING_HEADER_EPOGARMORY_DUMMY"] = "EpogArmory Dummy Parse"
_G["BINDING_NAME_CLICK EpogArmoryValidateButton:LeftButton"] = "Validate Parse"

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

-- Claude v1.7.1: /epogarmory testvalidate — exercise the marker click
-- round-trip without doing a full 1:30 dummy parse. Sets state to
-- "stopping" with the validate button visible immediately. User clicks
-- it; CLEU listens for SPELL_CAST_FAILED on Fishing/Basic Campfire; the
-- existing PostClick + StartMarkerVerifyWait + FinishFight handles the
-- rest. Skips aura validation and the post-combat hard timeout via the
-- testMode flag in OnTick. Combat log IS started so the user can also
-- verify by hand that the marker line lands in the .txt file.
_G.EpogArmoryDummy_TestValidate = function()
    if state == "logging" or state == "stopping" then
        print("|cffffaa44EpogArmory|r [testvalidate]: a real parse is in progress — refusing to start test mode. Click Reset/Stop first.")
        return
    end
    if not frame then frame = BuildFrame() end

    -- Set up the same module state DoStartLogging would, minus the
    -- city/dummy gates and minus capturing a real dummy GUID.
    testMode          = true
    validThroughout   = true
    invalidReasons    = {}
    markerEmitted     = false
    markerVerified    = false
    pendingMarker     = false
    fightTotalDamage  = 0
    lastDummyName     = "(test mode)"
    savedDummyGUID    = nil
    fightStartTime    = GetTime() - MARKER_TIME_SEC  -- pretend it's already past 1:20
    stoppingStartTime = GetTime()
    lastDummyHitTime  = GetTime()

    -- Start /combatlog so the marker line actually lands in a file
    -- the user can inspect. Capture the filename the same way
    -- DoStartLogging does.
    if LoggingCombat then LoggingCombat(true) end
    logFilename = date("Logs/%Y-%m-%d-%H.%M.%S WoWCombatLog.txt")

    -- Open the frame and jump straight to "stopping" — that's the
    -- only state where the validate button is shown at alpha 1.
    AnchorTopLeft(frame)
    frame:Show()
    SetState("stopping")
    frame.UpdateUI()

    print("|cffffaa44EpogArmory|r [testvalidate]: |cffffd200test mode active.|r")
    print("  |cffaaaaaa-|r combat log started: |cffffd200" .. logFilename .. "|r")
    print("  |cffaaaaaa-|r click the green |cff66ff66Validate|r button in the dummy frame to fire the marker.")
    print("  |cffaaaaaa-|r a CLEAN result means the secure-button + /cast Fishing mechanism produced a SPELL_CAST_FAILED CLEU line.")
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
        -- 3.3.5 signature: timestamp, subevent, sourceGUID, sourceName,
        -- sourceFlags, destGUID, destName, destFlags, [event-specific args]...
        -- Pull 12 args so we can read the damage amount in either layout:
        --   SWING_DAMAGE:     arg9 = amount
        --   SPELL_DAMAGE etc: arg9 = spellID, arg10 = spellName, arg11 = school, arg12 = amount
        local _, subevent, _, _, sourceFlags, destGUID, destName, _, p9, p10, _, p12 = ...
        if not sourceFlags or bit.band(sourceFlags, AFFILIATION_MINE_BIT) == 0 then
            return
        end

        -- AoE-dummy detection. Any time we (player or pet) act on a
        -- Training Dummy that ISN'T the dummy we locked onto at
        -- combat-start, remember the GUID. The first such hit also
        -- invalidates the fight in real time on PE-skip realms — the
        -- user sees the red "Multi-target damage detected" line
        -- IMMEDIATELY in the frame, plus the verdict at end-of-fight,
        -- plus SaveFightRecord skips the save entirely.
        --
        -- Plain-substring match — Lua doesn't have \b but no real-world
        -- NPC name has "Training Dummy" as a non-dummy substring, so
        -- the parser's `\bTraining Dummy\b` and our `find(.., true)`
        -- agree in practice.
        if state == "logging" or state == "stopping" or state == "practice" then
            if destName and destGUID and destGUID ~= savedDummyGUID
                    and not aoeExtraDummyGUIDs[destGUID]
                    and string.find(destName, DUMMY_NAME_PATTERN, 1, true) then
                local firstHit = (next(aoeExtraDummyGUIDs) == nil)
                aoeExtraDummyGUIDs[destGUID] = true
                aoeExtraDummyName = aoeExtraDummyName or destName
                -- Realtime invalidation. Only on realms where the
                -- server will reject the upload — on CoA-style realms
                -- AoE is valid content, so we keep the fight valid
                -- and just tag it with aoe=true at save time.
                if ShouldSkipAoEOnThisRealm() and not invalidReasons["multi-target damage — single-target only"] then
                    invalidReasons["multi-target damage — single-target only"] = true
                    validThroughout = false
                end
                if firstHit and frame and frame:IsShown() and frame.UpdateUI then
                    frame.UpdateUI()
                end
            end
        end
        -- p10 carries spellName for SPELL_/RANGE_ events; for SWING events p10
        -- is the overkill amount but doesn't matter for marker check below.
        local spellName = p10

        -- Marker verification accepted in ANY state — the marker might
        -- arrive late, after we've already transitioned to "stopped".
        -- We still want to confirm it landed in the log file. State
        -- gate removed for this check.
        --
        -- Claude v1.7.1: FAILED-only (was START-or-FAILED). The site
        -- contract only accepts SPELL_CAST_FAILED, so the addon's
        -- in-game verdict needs to match — a SPELL_CAST_START from a
        -- pole-equipped Fishing channel is NOT a valid marker even
        -- though the log line exists, because the site won't accept it.
        --
        -- Claude v1.7.1: also accept any spell name in MARKER_SPELL_NAMES
        -- to cover the Basic Campfire fallback for pole-equipped players.
        if subevent == "SPELL_CAST_FAILED" and MARKER_SPELL_NAMES[spellName] then
            if not markerVerified then
                _DebugPrint(string.format("marker observed in CLEU: %s '%s' (state=%s)",
                    subevent, spellName, state))
                markerVerified = true
            end
            return
        end

        -- Hit + damage tracking matters during logging/stopping (real
        -- parse) AND during practice mode (DPS meter without log).
        if state ~= "logging" and state ~= "stopping" and state ~= "practice" then return end

        -- Hit + damage tracking on the dummy.
        if not savedDummyGUID or destGUID ~= savedDummyGUID then return end
        if subevent == "SWING_DAMAGE"  or subevent == "SWING_MISSED"
        or subevent == "SPELL_DAMAGE"  or subevent == "SPELL_MISSED"
        or subevent == "RANGE_DAMAGE"  or subevent == "RANGE_MISSED"
        or subevent == "SPELL_PERIODIC_DAMAGE" then
            lastDummyHitTime = GetTime()
        end
        -- Damage amount: SWING_DAMAGE has it in arg9 (which we called p9
        -- locally); SPELL_DAMAGE / RANGE_DAMAGE / SPELL_PERIODIC_DAMAGE
        -- have spellID/Name/School first, so amount is at arg12 (p12).
        local amount
        if subevent == "SWING_DAMAGE" then
            amount = p9
        elseif subevent == "SPELL_DAMAGE"
            or subevent == "RANGE_DAMAGE"
            or subevent == "SPELL_PERIODIC_DAMAGE" then
            amount = p12
        end
        if amount and type(amount) == "number" then
            fightTotalDamage = fightTotalDamage + amount
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

-- ============================================================================
-- Slash command for isolation-testing the marker cast.
-- ============================================================================
-- Usage:
--   /epogtest                  (defaults to "Hearthstone" with auto-stop)
--   /epogtest hearth           (Hearthstone + 150ms SpellStopCasting)
--   /epogtest fish             (Fishing — no stop needed, fails instantly)
--   /epogtest mount            (Summon mount via name)
--   /epogtest "Some Spell"     (any spell name verbatim)
--   /epogtest +nostop fish     (Fishing without auto-stop)
SLASH_EPOGTEST1 = "/epogtest"
SlashCmdList["EPOGTEST"] = function(msg)
    msg = msg or ""
    local nostop = msg:find("+nostop", 1, true) ~= nil
    if nostop then msg = msg:gsub("%+nostop", "") end
    local arg = msg:match("^%s*(.-)%s*$") or ""

    local spellName
    local stopAfter
    if arg == "" or arg:lower() == "hearth" or arg:lower() == "hearthstone" then
        spellName = "Hearthstone"
        stopAfter = not nostop
    elseif arg:lower() == "fish" or arg:lower() == "fishing" then
        spellName = "Fishing"
        stopAfter = false -- Fishing fails instantly, no need to stop
    elseif arg:lower() == "mount" then
        -- Try to use the player's currently-equipped mount if API exists
        spellName = arg
        stopAfter = not nostop
    else
        spellName = arg
        stopAfter = not nostop
    end

    if _G.EpogArmoryDummy_TestCast then
        _G.EpogArmoryDummy_TestCast(spellName, stopAfter)
    else
        print("|cffffaa44EpogArmory|r [testcast] module not loaded")
    end
end
