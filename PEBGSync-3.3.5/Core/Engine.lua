-- Core/Engine.lua
-- Sampler + cache + broadcaster + receiver for the teammate channel.
-- The enemy-spot channel lives in Core/Enemy.lua and is opt-in.

local PEBG = PEBGSync
PEBG.Engine = {}
local E = PEBG.Engine

-- ----- cache -----------------------------------------------------------
-- Keyed by player name. Each entry holds the latest received state plus
-- a server-local last-seen timestamp (GetTime()) used for stale pruning
-- and for "latest wins" conflict resolution when multiple observers
-- broadcast the same target.
PEBG.cache = PEBG.cache or {}

-- Returns the cache entry for `name`, creating it on first sight.
local function ensure(name)
    local e = PEBG.cache[name]
    if not e then
        e = { name = name }
        PEBG.cache[name] = e
    end
    return e
end

-- Iterate live (non-stale) cache entries. Stops calling cb when cb
-- returns false. Used by the UI layer to refresh blips / HUD rows.
function E.ForEachLive(cb)
    local cutoff = GetTime() - PEBG.STALE_AFTER
    for _, entry in pairs(PEBG.cache) do
        if (entry.lastSeen or 0) >= cutoff then
            if cb(entry) == false then return end
        end
    end
end

function E.Get(name) return PEBG.cache[name] end

-- ----- sampler ---------------------------------------------------------

-- Builds per-tier observation record lists for the broadcaster. Includes
-- own state always, plus any raid/party member with UnitIsVisible == true
-- (which means default WoW has fresh data for them — exactly the data
-- the addon should relay to teammates the server has stopped updating
-- for). Stale "out-of-range" units are deliberately skipped so we don't
-- relay the same frozen data we're trying to work around.
local PLAYER_NAME

local function refreshPlayerName()
    PLAYER_NAME = UnitName("player")
end

local function unitFlagsByte(unit)
    local f = 0
    if UnitAffectingCombat(unit) then f = f + PEBG.FLAG_IN_COMBAT end
    if UnitIsDeadOrGhost(unit) then
        if UnitIsGhost and UnitIsGhost(unit) then
            f = f + PEBG.FLAG_GHOST
        else
            f = f + PEBG.FLAG_DEAD
        end
    end
    if IsMounted and unit == "player" and IsMounted() then
        f = f + PEBG.FLAG_MOUNTED
    end
    -- BG flag-carrier detection: the player carrying the WSG/EotS flag
    -- has a hidden buff "Warsong Flag" / "Alliance Flag" / "Horde Flag"
    -- / "Netherstorm Flag". Cheap to scan since these are tiny strings.
    for i = 1, 8 do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name == "Warsong Flag" or name == "Silverwing Flag"
            or name == "Alliance Flag" or name == "Horde Flag"
            or name == "Netherstorm Flag" then
            f = f + PEBG.FLAG_HAS_BG_FLAG
            break
        end
    end
    return f
end

local function sampleFastRecord(unit, name)
    local hpMax = UnitHealthMax(unit) or 1
    local hp    = UnitHealth(unit)    or 0
    local hpPct = (hpMax > 0) and (hp * 100 / hpMax) or 0
    local x, y  = GetPlayerMapPosition(unit)
    return {
        name  = name or UnitName(unit),
        hp    = hpPct,
        x     = x or 0,
        y     = y or 0,
        flags = unitFlagsByte(unit),
    }
end

local function sampleSlowRecord(unit, name)
    local mpMax = UnitManaMax(unit) or 1
    local mp    = UnitMana(unit)    or 0
    local mpPct = (mpMax > 0) and (mp * 100 / mpMax) or 0
    local _, classToken = UnitClass(unit)
    return {
        name       = name or UnitName(unit),
        mp         = mpPct,
        classToken = classToken or "?",
    }
end

-- Walks the local raid/party group and returns a list of fast OR slow
-- records to broadcast this tick. Own state is always included; group
-- members are included only when UnitIsVisible (i.e. we have fresh data).
local function collect(sampleFn)
    local records = {}
    if not PLAYER_NAME then refreshPlayerName() end
    records[#records + 1] = sampleFn("player", PLAYER_NAME)

    local nRaid = GetNumRaidMembers() or 0
    if nRaid > 0 then
        for i = 1, nRaid do
            local unit = "raid" .. i
            if UnitExists(unit)
                and UnitIsVisible(unit)
                and not UnitIsUnit(unit, "player") then
                local name = UnitName(unit)
                if name then
                    records[#records + 1] = sampleFn(unit, name)
                end
            end
        end
    else
        local nParty = GetNumPartyMembers() or 0
        for i = 1, nParty do
            local unit = "party" .. i
            if UnitExists(unit) and UnitIsVisible(unit) then
                local name = UnitName(unit)
                if name then
                    records[#records + 1] = sampleFn(unit, name)
                end
            end
        end
    end
    return records
end

-- ----- broadcaster -----------------------------------------------------
-- One OnUpdate frame drives both fast and slow ticks. We send everything
-- in one or two outbound messages per tier per tick: 2 + 0.5 = 2.5 msg/sec
-- worst-case, well under the 10 msg/sec outbound throttle on 3.3.5.

local broadcaster = CreateFrame("Frame")
broadcaster:Hide()

local fastAccum = 0
local slowAccum = 0

local function shouldBroadcast()
    if not PEBGSyncDB or not PEBGSyncDB.profile then return false end
    if not PEBGSyncDB.profile.enabled then return false end
    if not PEBG.IsInBG() then return false end
    if not PEBG.IsGrouped() then return false end
    return true
end

-- Cap on records per message — a single SendAddonMessage payload can't
-- exceed ~255 bytes. At ~30 bytes/record we cap at 6 to leave headroom.
local MAX_RECORDS_PER_MSG = 6

local function sendBatched(prefix, records, encoder)
    if #records == 0 then return end
    local chunk = {}
    for i = 1, #records do
        chunk[#chunk + 1] = records[i]
        if #chunk == MAX_RECORDS_PER_MSG then
            PEBG.Protocol.send(prefix, encoder(chunk))
            chunk = {}
        end
    end
    if #chunk > 0 then
        PEBG.Protocol.send(prefix, encoder(chunk))
    end
end

broadcaster:SetScript("OnUpdate", function(self, elapsed)
    if not shouldBroadcast() then
        fastAccum, slowAccum = 0, 0
        return
    end
    fastAccum = fastAccum + elapsed
    slowAccum = slowAccum + elapsed

    if fastAccum >= PEBG.FAST_INTERVAL then
        fastAccum = 0
        local records = collect(sampleFastRecord)
        sendBatched(PEBG.PREFIX_F, records, PEBG.Protocol.encodeFastBatch)
    end

    if slowAccum >= PEBG.SLOW_INTERVAL then
        slowAccum = 0
        local records = collect(sampleSlowRecord)
        sendBatched(PEBG.PREFIX_S, records, PEBG.Protocol.encodeSlowBatch)
    end
end)

function E.Start() broadcaster:Show() end
function E.Stop()  broadcaster:Hide(); fastAccum, slowAccum = 0, 0 end

-- ----- receiver --------------------------------------------------------
-- One frame for all three prefixes — branching on the prefix arg is
-- cheaper than three separate frames each filtering for one prefix.

local receiver = CreateFrame("Frame")
receiver:RegisterEvent("CHAT_MSG_ADDON")
receiver:RegisterEvent("PLAYER_LOGIN")
receiver:RegisterEvent("PARTY_MEMBERS_CHANGED")
receiver:RegisterEvent("RAID_ROSTER_UPDATE")

local fastBuf, slowBuf, enemyBuf = {}, {}, {}

local function applyFast(records, sender)
    local now = GetTime()
    for i = 1, #records do
        local r = records[i]
        local entry = ensure(r.name)
        entry.hp        = r.hp
        entry.x         = r.x
        entry.y         = r.y
        entry.flags     = r.flags
        entry.lastSeen  = now
        entry.observer  = sender
    end
end

local function applySlow(records, sender)
    local now = GetTime()
    for i = 1, #records do
        local r = records[i]
        local entry = ensure(r.name)
        entry.mp         = r.mp
        entry.classToken = r.classToken
        entry.lastSeen   = now
        entry.observer   = sender
    end
end

receiver:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
    if event == "PLAYER_LOGIN" then
        refreshPlayerName()
        return
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        -- Group composition changed; player_name doesn't but defensive.
        refreshPlayerName()
        return
    elseif event ~= "CHAT_MSG_ADDON" then return end

    if prefix == PEBG.PREFIX_F then
        for i = 1, #fastBuf do fastBuf[i] = nil end
        PEBG.Protocol.decodeFastBatch(msg, fastBuf)
        applyFast(fastBuf, sender)
    elseif prefix == PEBG.PREFIX_S then
        for i = 1, #slowBuf do slowBuf[i] = nil end
        PEBG.Protocol.decodeSlowBatch(msg, slowBuf)
        applySlow(slowBuf, sender)
    elseif prefix == PEBG.PREFIX_E then
        if PEBG.Enemy and PEBG.Enemy.OnReceive then
            for i = 1, #enemyBuf do enemyBuf[i] = nil end
            PEBG.Protocol.decodeEnemyBatch(msg, enemyBuf)
            PEBG.Enemy.OnReceive(enemyBuf, sender)
        end
    end
end)

-- ----- prune ------------------------------------------------------------
-- Stale entries linger forever otherwise — a player who leaves the raid
-- would keep showing on the map. A 1 Hz pass is plenty since the cache
-- check on read also handles this lazily.

local pruner = CreateFrame("Frame")
local pruneAccum = 0
pruner:SetScript("OnUpdate", function(self, elapsed)
    pruneAccum = pruneAccum + elapsed
    if pruneAccum < 1.0 then return end
    pruneAccum = 0
    local cutoff = GetTime() - PEBG.STALE_AFTER
    for name, entry in pairs(PEBG.cache) do
        if (entry.lastSeen or 0) < cutoff then
            PEBG.cache[name] = nil
        end
    end
end)
