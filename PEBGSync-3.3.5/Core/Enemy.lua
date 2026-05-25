-- Core/Enemy.lua
-- Opt-in enemy spot tracking. Default off (per spec); enable with
-- /pebg enemy on.
--
-- Mechanism: when enabled, scan nameplate frames + the local player's
-- current target each tick. Anything red (hostile) and player-class
-- (not a pet/totem) gets sampled and broadcast at the same per-mille
-- (x, y) resolution as teammate positions. Receivers store enemy spots
-- in a separate cache and draw them on the world map / minimap with a
-- hostile-red colour.
--
-- The "position" of an enemy is approximated as the local player's
-- position at the moment of the spot — nameplates don't carry world
-- coords. This is "close enough" since the local player IS within
-- combat range of the enemy when the nameplate is visible. Refines
-- when the enemy is also our current target (we know they're at our
-- combat radius).

local PEBG = PEBGSync
PEBG.Enemy = {}
local Enemy = PEBG.Enemy

PEBG.enemyCache = PEBG.enemyCache or {}

-- ----- receive ----------------------------------------------------------

function Enemy.OnReceive(records, sender)
    if not PEBGSyncDB or not PEBGSyncDB.profile or not PEBGSyncDB.profile.enemyEnabled then
        -- Don't store enemy spots if the local user has opt-in off.
        -- They'd be invisible anyway (no UI rendering when off), but
        -- skipping the cache writes saves a few cycles per packet.
        return
    end
    local now = GetTime()
    for i = 1, #records do
        local r = records[i]
        local key = r.name
        local entry = PEBG.enemyCache[key] or { name = r.name }
        entry.x          = r.x
        entry.y          = r.y
        entry.classToken = r.classToken
        entry.lastSeen   = now
        entry.observer   = sender
        PEBG.enemyCache[key] = entry
    end
end

-- ----- send ------------------------------------------------------------
-- Scan nameplate names (3.3.5 has GetNumNamePlates + GetNamePlateByIndex?
-- The cleanest path on 3.3.5 is hooking the CLEU + UnitName("target") +
-- a periodic UnitName("nameplate1..40") scan. We use the simplest path
-- first: target + mouseover + raid-target indicators. Future revision
-- could add nameplate frame enumeration.
--
-- Returns a list of enemy records observed THIS TICK. The broadcaster
-- only fires when PEBGSyncDB.profile.enemyEnabled is true.

local seenThisTick = {}

local function sampleEnemy(unit)
    if not UnitExists(unit) then return nil end
    if UnitIsFriend("player", unit) then return nil end
    if UnitIsPlayer(unit) == false then return nil end  -- skip pets/totems
    if UnitIsDeadOrGhost(unit) then return nil end
    local name = UnitName(unit)
    if not name then return nil end
    if seenThisTick[name] then return nil end
    seenThisTick[name] = true
    local _, class = UnitClass(unit)
    -- Approximate position with the LOCAL PLAYER's coords. The enemy
    -- is within range of `unit` to be readable, which means they're
    -- within ~40 yards of us. Good enough for "an enemy is near here".
    local px, py = GetPlayerMapPosition("player")
    return {
        name       = name,
        x          = px or 0,
        y          = py or 0,
        classToken = class or "?",
    }
end

local function collectEnemies()
    for k in pairs(seenThisTick) do seenThisTick[k] = nil end
    local records = {}
    local tryUnit = function(u)
        local r = sampleEnemy(u)
        if r then records[#records + 1] = r end
    end
    tryUnit("target")
    tryUnit("focus")
    tryUnit("mouseover")
    -- Raid target markers 1..8 — enemies the group has marked.
    for i = 1, 8 do tryUnit("raid" .. i .. "target") end
    -- Party target markers as a fallback when grouped without a raid.
    for i = 1, 4 do tryUnit("party" .. i .. "target") end
    return records
end

local broadcaster = CreateFrame("Frame")
broadcaster:Hide()
local enemyAccum = 0

local function shouldBroadcastEnemies()
    if not PEBGSyncDB or not PEBGSyncDB.profile then return false end
    if not PEBGSyncDB.profile.enabled then return false end
    if not PEBGSyncDB.profile.enemyEnabled then return false end
    if not PEBG.IsInBG() then return false end
    if not PEBG.IsGrouped() then return false end
    return true
end

broadcaster:SetScript("OnUpdate", function(self, elapsed)
    if not shouldBroadcastEnemies() then enemyAccum = 0; return end
    enemyAccum = enemyAccum + elapsed
    if enemyAccum < PEBG.ENEMY_INTERVAL then return end
    enemyAccum = 0
    local records = collectEnemies()
    if #records == 0 then return end
    local msg = PEBG.Protocol.encodeEnemyBatch(records)
    PEBG.Protocol.send(PEBG.PREFIX_E, msg)
end)

function Enemy.Start() broadcaster:Show() end
function Enemy.Stop()
    broadcaster:Hide()
    enemyAccum = 0
end

-- ----- prune -----------------------------------------------------------
-- Enemy entries stale faster than the global ENEMY_STALE_AFTER would
-- imply because positions are approximate. 15s is a balance between
-- "moved away" (stale) and "useful intel" (still on minimap).

local pruner = CreateFrame("Frame")
local pruneAccum = 0
pruner:SetScript("OnUpdate", function(self, elapsed)
    pruneAccum = pruneAccum + elapsed
    if pruneAccum < 1.0 then return end
    pruneAccum = 0
    local cutoff = GetTime() - PEBG.ENEMY_STALE_AFTER
    for name, entry in pairs(PEBG.enemyCache) do
        if (entry.lastSeen or 0) < cutoff then
            PEBG.enemyCache[name] = nil
        end
    end
end)

function Enemy.ForEachLive(cb)
    local cutoff = GetTime() - PEBG.ENEMY_STALE_AFTER
    for _, entry in pairs(PEBG.enemyCache) do
        if (entry.lastSeen or 0) >= cutoff then
            if cb(entry) == false then return end
        end
    end
end
