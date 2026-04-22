-- EpogArmory.lua
-- single-addon mesh gear inspector. Every client runs the same code:
-- scans self + groupmates in dungeons/raids, broadcasts chunked gear on the
-- "EpogArmory" addon-message prefix, receives other clients' broadcasts,
-- and stores latest gear per GUID in EpogArmoryDB for manual upload to
-- epoglogs.com.

local ADDON = "EpogArmory"
local PREFIX = "EpogArmory"
-- Wire protocol family. Bump only for breaking schema changes (field reorder /
-- semantic shift). Receivers accept any payload beginning with "v" .. PROTO and
-- ignore trailing tokens they don't understand, so additive changes (new fields
-- after gear slot 19, i.e. positions 31+) ride the same PROTO without breaking
-- older clients.
local PROTO = "1"
local ADDON_VERSION = GetAddOnMetadata(ADDON, "Version") or "0"
local RELEASES_URL = "https://github.com/Defcons/epogarmory-addon/releases/"

-- Tuning
local INSPECT_COOLDOWN      = 900
local OUT_OF_RANGE_COOLDOWN = 30     -- retry fast when CanInspect fails
local INSPECT_TIMEOUT       = 4
local INSPECT_INTERVAL      = 2.5
local BROADCAST_STAGGER     = 0.3
local MAX_CHUNK_BODY        = 200
local ROSTER_TICK           = 10
local MIN_INSPECT_LEVEL     = 60
local MIN_STORE_LEVEL       = 60
local MIN_STORE_EQUIPPED    = 10
local ASSEMBLY_TIMEOUT      = 60
local SCAN_FRESH_WINDOW     = 86400  -- 24h — skip re-inspecting a player anyone in the mesh scanned recently

-- Runtime config, persisted in EpogArmoryDB.config on logout.
local requireInstance = true

local UTILITY_ITEMS = {
    [11122] = "Carrot on a Stick",
    [25653] = "Riding Crop",
    [32863] = "Charm of Swift Flight",
    [46906] = "Argent War Horn",
    [6256]  = "Fishing Pole",
    [6365]  = "Strong Fishing Pole",
    [6366]  = "Darkwood Fishing Pole",
    [6367]  = "Big Iron Fishing Pole",
    [12225] = "Blump Family Fishing Pole",
    [19970] = "Arcanite Fishing Pole",
    [25978] = "Seth's Graphite Fishing Pole",
    [44050] = "Mastercraft Kalu'ak Fishing Pole",
    [45858] = "Nat's Lucky Fishing Pole",
    [45991] = "Bone Fishing Pole",
    [19972] = "Lucky Fishing Hat",
    [33820] = "Weather-Beaten Fishing Hat",
    [33864] = "Chef's Hat",
}

local UTILITY_ENCHANTS = {
    [464] = "Enchant Gloves - Riding Skill",
}

-- State
local queue, inQueue, seen = {}, {}, {}
local current = nil
local outQueue = {}
local nextInspectAt, nextSendAt, lastRoster = 0, 0, 0
local msgCounter = 0
local assembly = {}

-- Version ping: broadcast our ADDON_VERSION once at T+120s after login so
-- groupmates/guildmates running the addon learn when a newer release is out.
-- Listening is always-on via OnAddonMessage; the outbound ping is one-shot.
local VERSION_PING_DELAY = 120
local VERSION_PING_RETRY = 60 -- if no broadcast channel available (solo + no guild), defer
local versionPingAt      = 0
local versionPingSent    = false
local versionNotified    = false

-- item-info cache. EpogItemCacheDB is the persistent half; pendingCache
-- is the in-memory retry queue for items the client hasn't fetched yet.
local pendingCache = {} -- itemID -> firstSeenTime
local CACHE_RETRY_INTERVAL = 0.5
local CACHE_GIVE_UP        = 15

local function now() return GetTime() end

local function dprint(...)
    if EpogArmoryDebug then
        print("|cffffaa44EpogArmory|r", ...)
    end
end

local function markRetryIn(guid, retryIn)
    seen[guid] = now() - (INSPECT_COOLDOWN - retryIn)
end

local function ZoneType()
    local inInstance, instType = IsInInstance()
    if not inInstance then return "outdoor" end
    if instType == "raid" then return "raid" end
    if instType == "party" then return "party" end
    if instType == "pvp" then return "bg" end
    if instType == "arena" then return "arena" end
    return instType or "unknown"
end

local function IsInstanceZone()
    local z = ZoneType()
    return z == "party" or z == "raid"
end

local function ItemStringFromLink(link)
    if not link then return "" end
    local s = link:match("|Hitem:([%-%d:]+)|h")
    return s or ""
end

-- mark a GUID as inspected at unix timestamp `scanTime`. Called from
-- both local successful inspects and gossip-reassembled broadcasts. Keeps the
-- max of current vs new so older arrivals don't overwrite fresh data.
local function MarkInspected(guid, scanTime)
    if not guid or guid == "" or not scanTime or scanTime <= 0 then return end
    EpogArmoryDB = EpogArmoryDB or { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = {} }
    EpogArmoryDB.lastScanned = EpogArmoryDB.lastScanned or {}
    local existing = EpogArmoryDB.lastScanned[guid] or 0
    if scanTime > existing then
        EpogArmoryDB.lastScanned[guid] = scanTime
    end
end

local function HasFreshScan(guid)
    if not EpogArmoryDB or not EpogArmoryDB.lastScanned then return false end
    local t = EpogArmoryDB.lastScanned[guid]
    return t and (time() - t) < SCAN_FRESH_WINDOW
end

-- ---------------- Item-info cache ----------------
-- for every itemID we see on a scanned player, query GetItemInfo()
-- locally. If the client already has the item cached, we get
-- name/quality/itemLevel/texture and persist to EpogItemCacheDB so the web
-- site can render without needing external data sources. If the client hasn't
-- seen the item yet, we trigger a background fetch via a hidden tooltip and
-- retry from an OnUpdate poll. Covers Ascension-custom items that aren't in
-- Wowhead / TrinityCore data.

local cacheTip -- created lazily on first use

local function TriggerItemFetch(itemID)
    if not cacheTip then
        cacheTip = CreateFrame("GameTooltip", "EpogArmoryItemCacheTip", UIParent, "GameTooltipTemplate")
        cacheTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    cacheTip:ClearLines()
    cacheTip:SetHyperlink("item:" .. itemID)
    cacheTip:Hide()
end

-- returns true if GetItemInfo succeeded and we wrote to the cache,
-- false if still pending (client hasn't resolved the item yet).
local function CacheItemInfo(itemID)
    if not itemID or itemID <= 0 then return false end
    EpogItemCacheDB = EpogItemCacheDB or {}
    if EpogItemCacheDB[itemID] then return true end -- already cached, skip re-query

    local name, _, quality, itemLevel, _, _, _, _, _, texture = GetItemInfo(itemID)
    if not name then
        TriggerItemFetch(itemID)
        return false
    end
    -- texture is "Interface\Icons\INV_Sword_01" — we want the basename, lowercased.
    local icon = nil
    if texture then
        icon = texture:match("([^\\/]+)$") or texture
        icon = icon:lower()
    end
    EpogItemCacheDB[itemID] = {
        name = name,
        quality = quality or 0,
        itemLevel = itemLevel or 0,
        icon = icon,
        ts = floor(time()),
    }
    return true
end

local function MarkPendingCache(itemID)
    if not itemID or itemID <= 0 then return end
    if EpogItemCacheDB and EpogItemCacheDB[itemID] then return end
    if not pendingCache[itemID] then
        pendingCache[itemID] = now()
        TriggerItemFetch(itemID)
    end
end

local function TryCachePending()
    if not next(pendingCache) then return end
    local nowT = now()
    for iid, firstSeen in pairs(pendingCache) do
        if CacheItemInfo(iid) then
            pendingCache[iid] = nil
        elseif (nowT - firstSeen) > CACHE_GIVE_UP then
            pendingCache[iid] = nil -- server never responded; try again on next scan
        end
    end
end

-- iterate gear slots, ensure every itemID is either cached or queued.
local function CachePayloadItems(entry)
    if not entry or not entry.gear then return end
    for slot = 1, 19 do
        local raw = entry.gear[slot]
        if raw and raw ~= "" then
            local iid = tonumber(raw:match("^(%d+)"))
            if iid and iid > 0 then
                if not CacheItemInfo(iid) then MarkPendingCache(iid) end
            end
        end
    end
end

-- ---------------- Build + broadcast ----------------

local function BuildPayload(unit, guid)
    local name = UnitName(unit)
    if not name or name == "" or name == UNKNOWN then return nil, "name unresolved" end
    local realm = GetRealmName() or ""
    local _, classFile = UnitClass(unit)
    classFile = classFile or ""
    local level = UnitLevel(unit) or 0

    -- GetTalentTabInfo's second arg is the inspect flag — pass 1 when
    -- reading another unit's talents (after NotifyInspect), nil when reading
    -- our own talents from a direct "player" scan.
    local inspectFlag = UnitIsUnit(unit, "player") and nil or 1
    local s1 = select(3, GetTalentTabInfo(1, inspectFlag)) or 0
    local s2 = select(3, GetTalentTabInfo(2, inspectFlag)) or 0
    local s3 = select(3, GetTalentTabInfo(3, inspectFlag)) or 0

    local parts = {
        "v" .. PROTO,
        name, realm, classFile, tostring(level), guid or "",
        tostring(s1), tostring(s2), tostring(s3),
        tostring(floor(time())),
        ZoneType(),
    }
    local equipped = 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink(unit, slot)
        local istr = ItemStringFromLink(link)
        if istr ~= "" then equipped = equipped + 1 end
        parts[#parts + 1] = istr
    end
    if equipped < 10 then
        return nil, string.format("only %d slots equipped (inspect data incomplete?)", equipped)
    end
    return table.concat(parts, "^"), equipped
end

local function MakeChunks(payload, msgID)
    local body = MAX_CHUNK_BODY
    local count = math.ceil(#payload / body)
    if count < 1 then count = 1 end
    local out = {}
    for i = 1, count do
        local sub = payload:sub((i - 1) * body + 1, i * body)
        out[i] = string.format("%s^%d^%d^%s", msgID, i, count, sub)
    end
    return out
end

local function PickChannels()
    local list = {}
    if GetNumRaidMembers() > 0 then
        table.insert(list, "RAID")
    elseif GetNumPartyMembers() > 0 then
        table.insert(list, "PARTY")
    end
    if IsInGuild() then
        table.insert(list, "GUILD")
    end
    return list
end

local function EnqueueBroadcast(payload, targetName)
    local channels = PickChannels()
    if #channels == 0 then
        dprint(string.format("[send] %s: no channel available (solo + no guild)", targetName or "?"))
        return
    end
    msgCounter = msgCounter + 1
    local msgID = string.format("%x%x", math.floor(now() * 10) % 0xffff, msgCounter % 0xffff)
    local chunks = MakeChunks(payload, msgID)
    for _, ch in ipairs(channels) do
        for _, body in ipairs(chunks) do
            outQueue[#outQueue + 1] = { ch = ch, body = body }
        end
    end
    dprint(string.format("[send] %s: %d chunks x %d channels [%s] (%d bytes)",
        targetName or "?", #chunks, #channels, table.concat(channels, "+"), #payload))
end

-- ---------------- Receive: parse + store ----------------

local function ShouldStore(entry)
    if not entry then return false, "nil entry" end
    if (entry.level or 0) < MIN_STORE_LEVEL then
        return false, string.format("level %d < %d", entry.level or 0, MIN_STORE_LEVEL)
    end
    if requireInstance and entry.zone ~= "party" and entry.zone ~= "raid" then
        return false, string.format("zone=%s (requireInstance on)", tostring(entry.zone))
    end
    -- Ascension is classless: GetTalentTabInfo(tab, ...) returns 0 points-spent
    -- for every tab regardless of what the player actually specced, so we can't
    -- use spec distribution as a "committed player" gate here. The server-side
    -- validator in warcraftlogs-epog still has the final say on what gets
    -- published — we just collect everything gated by level + gear-equipped.
    local equipped = 0
    for i = 1, 19 do
        if entry.gear[i] and entry.gear[i] ~= "" then equipped = equipped + 1 end
    end
    if equipped < MIN_STORE_EQUIPPED then
        return false, string.format("only %d slots equipped", equipped)
    end
    for slot = 1, 19 do
        local s = entry.gear[slot]
        if s and s ~= "" then
            local iid, eid = s:match("^(%d+):(%-?%d+)")
            iid = tonumber(iid) or 0
            eid = tonumber(eid) or 0
            if UTILITY_ITEMS[iid] then
                return false, "utility item equipped: " .. UTILITY_ITEMS[iid]
            end
            if UTILITY_ENCHANTS[eid] then
                return false, "utility enchant: " .. UTILITY_ENCHANTS[eid]
            end
        end
    end
    return true
end

local function ParsePayload(payload)
    local t = { strsplit("^", payload) }
    -- Accept any payload in the same PROTO family: exact "v<PROTO>" or
    -- "v<PROTO>.<minor>" (future soft-bump). Reject a different major (e.g. "v2").
    -- Unknown trailing tokens past slot 19 (position 31+) are ignored — that's
    -- our forward-compat channel for additive changes.
    local tag = t[1]
    if not tag or (tag ~= ("v" .. PROTO) and not tag:match("^v" .. PROTO .. "%.")) then
        return nil
    end
    local entry = {
        name      = t[2] or "",
        realm     = t[3] or "",
        class     = t[4] or "",
        level     = tonumber(t[5]) or 0,
        guid      = t[6] or "",
        spec      = { tonumber(t[7]) or 0, tonumber(t[8]) or 0, tonumber(t[9]) or 0 },
        scanTime  = tonumber(t[10]) or 0,
        zone      = t[11] or "",
        gear      = {},
    }
    for i = 1, 19 do entry.gear[i] = t[11 + i] or "" end
    if entry.name == "" or entry.guid == "" then return nil end
    return entry
end

local function Ingest(payload, sender)
    local entry = ParsePayload(payload)
    if not entry then
        dprint("[store] REJECT: payload parse failed")
        return
    end

    -- Always update the "when was this GUID last inspected by anyone" clock
    -- so the 24h dedup works across the full mesh — even if this particular
    -- scan fails ShouldStore (utility gear, wrong zone, etc).
    MarkInspected(entry.guid, entry.scanTime)

    -- Populate the item-info cache from every scan we observe — even rejected
    -- ones give us valid itemIDs to enrich our DB.
    CachePayloadItems(entry)

    local ok, reason = ShouldStore(entry)
    if not ok then
        dprint(string.format("[store] REJECT: %s L%d — %s", entry.name, entry.level, reason))
        return
    end

    EpogArmoryDB = EpogArmoryDB or { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = {} }
    EpogArmoryDB.players = EpogArmoryDB.players or {}

    local existing = EpogArmoryDB.players[entry.guid]
    if existing and (existing.scanTime or 0) >= entry.scanTime then
        dprint(string.format("[store] SKIP: %s — existing snapshot is newer (%s vs %s)",
            entry.name,
            date("%H:%M:%S", existing.scanTime or 0),
            date("%H:%M:%S", entry.scanTime)))
        return
    end

    entry.scannedBy = sender or (UnitName("player") or "?")
    EpogArmoryDB.players[entry.guid] = entry
    dprint(string.format("[store] OK: %s L%d [%s] — scanned by %s at %s",
        entry.name, entry.level, entry.zone, entry.scannedBy,
        date("%H:%M:%S", entry.scanTime)))
end

-- Numeric-tuple semver compare. Returns 1 if a > b, -1 if a < b, 0 equal.
-- Non-numeric suffixes (e.g. "-beta") are ignored — only digit runs count.
local function CompareVersions(a, b)
    if a == b then return 0 end
    local function parts(v)
        local out = {}
        for n in tostring(v or ""):gmatch("(%d+)") do out[#out+1] = tonumber(n) end
        return out
    end
    local pa, pb = parts(a), parts(b)
    local len = math.max(#pa, #pb)
    for i = 1, len do
        local na, nb = pa[i] or 0, pb[i] or 0
        if na ~= nb then return na > nb and 1 or -1 end
    end
    return 0
end

local function HandleVersionPing(payload, sender)
    -- payload shape: "VER^<version>"
    local tag, senderVersion = strsplit("^", payload)
    if tag ~= "VER" or not senderVersion or senderVersion == "" then return end
    dprint(string.format("[version] %s is on v%s (we're v%s)",
        sender or "?", senderVersion, ADDON_VERSION))
    if versionNotified then return end
    if CompareVersions(senderVersion, ADDON_VERSION) <= 0 then return end
    versionNotified = true
    print(string.format("|cffffaa44EpogArmory|r: newer version |cff00ff00v%s|r available (you're on v%s). Download: %s",
        senderVersion, ADDON_VERSION, RELEASES_URL))
end

local function TrySendVersionPing()
    if versionPingSent then return end
    if now() < versionPingAt then return end
    local channels = PickChannels()
    if #channels == 0 then
        -- Solo + no guild: no one to ping yet. Defer and try again.
        versionPingAt = now() + VERSION_PING_RETRY
        return
    end
    versionPingSent = true
    msgCounter = msgCounter + 1
    local msgID = string.format("V%x", msgCounter % 0xffff)
    local body = string.format("%s^1^1^VER^%s", msgID, ADDON_VERSION)
    for _, ch in ipairs(channels) do
        outQueue[#outQueue + 1] = { ch = ch, body = body }
    end
    dprint(string.format("[version] pinging v%s on [%s]",
        ADDON_VERSION, table.concat(channels, "+")))
end

local function OnAddonMessage(prefix, body, channel, sender)
    if prefix ~= PREFIX then return end
    if not body or body == "" then return end
    local msgID, idx_s, total_s, data = body:match("^([^%^]+)%^([^%^]+)%^([^%^]+)%^(.*)$")
    local idx = tonumber(idx_s)
    local total = tonumber(total_s)
    if not msgID or not idx or not total or not data then return end

    local key = (sender or "?") .. "\001" .. msgID
    local asm = assembly[key]
    if not asm then
        asm = { chunks = {}, total = total, firstSeen = now() }
        assembly[key] = asm
        dprint(string.format("[recv] new scan from %s (chunk %d/%d, expecting %d more)",
            sender or "?", idx, total, total - 1))
    end
    if asm.chunks[idx] then return end
    asm.chunks[idx] = data

    local have = 0
    for i = 1, total do
        if asm.chunks[i] then have = have + 1 end
    end
    if have == total then
        local pieces = {}
        for i = 1, total do pieces[i] = asm.chunks[i] end
        local full = table.concat(pieces)
        assembly[key] = nil
        dprint(string.format("[recv] complete from %s — %d chunks assembled (%d bytes)",
            sender or "?", total, #full))
        -- Route VER pings separately from gear payloads; they share the reassembly
        -- framing but decode to a different shape.
        if full:sub(1, 4) == "VER^" then
            HandleVersionPing(full, sender)
        else
            Ingest(full, sender)
        end
    end
end

local function GCAssembly()
    local cutoff = now() - ASSEMBLY_TIMEOUT
    for k, v in pairs(assembly) do
        if v.firstSeen < cutoff then
            local have = 0
            for i = 1, v.total do if v.chunks[i] then have = have + 1 end end
            local senderName = k:match("^([^\001]+)") or "?"
            dprint(string.format("[asm] dropped partial from %s: got %d/%d chunks after %ds",
                senderName, have, v.total, ASSEMBLY_TIMEOUT))
            assembly[k] = nil
        end
    end
end

-- ---------------- Scan queue + inspect driver ----------------

local function AddUnit(unit)
    if not UnitExists(unit) then return end
    if UnitIsUnit(unit, "player") then return end
    if not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or guid == "" then return end
    if inQueue[guid] then return end
    local last = seen[guid]
    if last and (now() - last) < INSPECT_COOLDOWN then return end
    if HasFreshScan(guid) then return end -- someone in the mesh scanned this player <24h ago
    if (UnitLevel(unit) or 0) < MIN_INSPECT_LEVEL then return end
    queue[#queue + 1] = { guid = guid, unit = unit }
    inQueue[guid] = true
end

local function ScanRoster()
    lastRoster = now()
    if requireInstance and not IsInstanceZone() then return end
    local before = #queue
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do AddUnit("raid" .. i) end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, 4 do AddUnit("party" .. i) end
    end
    local added = #queue - before
    if added > 0 then
        dprint(string.format("[roster] +%d to queue (total %d pending)", added, #queue))
    end
end

local function ClearCurrent()
    current = nil
    nextInspectAt = now() + INSPECT_INTERVAL
end

local function TryInspect()
    if current then return end
    if now() < nextInspectAt then return end
    if #queue == 0 then return end
    if requireInstance and not IsInstanceZone() then return end
    if InCombatLockdown() then return end

    local entry = table.remove(queue, 1)
    inQueue[entry.guid] = nil
    local name = UnitName(entry.unit) or "?"
    if not UnitExists(entry.unit) or UnitGUID(entry.unit) ~= entry.guid then
        dprint(string.format("[inspect] SKIP: %s — raid slot reshuffled since queue time", name))
        return
    end
    if not CanInspect(entry.unit) then
        markRetryIn(entry.guid, OUT_OF_RANGE_COOLDOWN)
        dprint(string.format("[inspect] SKIP: %s — CanInspect=false (out of range / not visible). retry in %ds",
            name, OUT_OF_RANGE_COOLDOWN))
        return
    end
    current = { guid = entry.guid, unit = entry.unit, startedAt = now() }
    NotifyInspect(entry.unit)
    dprint(string.format("[inspect] START: %s L%d — NotifyInspect sent (%d left in queue)",
        name, UnitLevel(entry.unit) or 0, #queue))
end

local function CheckTimeout()
    if current and (now() - current.startedAt) > INSPECT_TIMEOUT then
        dprint(string.format("[inspect] TIMEOUT: %s — no INSPECT_TALENT_READY after %ds, retry in %ds",
            UnitName(current.unit) or "?", INSPECT_TIMEOUT, OUT_OF_RANGE_COOLDOWN))
        markRetryIn(current.guid, OUT_OF_RANGE_COOLDOWN) -- transient fail, short retry (not 15 min)
        ClearCurrent()
    end
end

local function OnInspectReady()
    if not current then return end
    local c = current
    if UnitGUID(c.unit) ~= c.guid then
        dprint("[inspect] READY fired but current GUID no longer matches — dropping")
        ClearCurrent()
        return
    end
    local tname = UnitName(c.unit) or "?"
    local tlvl = UnitLevel(c.unit) or 0
    local payload, info = BuildPayload(c.unit, c.guid)
    if payload then
        seen[c.guid] = now()
        MarkInspected(c.guid, floor(time()))
        dprint(string.format("[inspect] OK: %s L%d — %d slots equipped, payload %d bytes",
            tname, tlvl, info, #payload))
        EnqueueBroadcast(payload, tname)
        -- direct-ingest our own scan so we save data even when no one
        -- else is in our broadcast channels.
        Ingest(payload, UnitName("player"))
    else
        -- incomplete inspect data (0-9 slots) is usually transient —
        -- target moved out mid-response or server was slow. Short retry, not
        -- the 15-min full cooldown which is reserved for successful scans.
        markRetryIn(c.guid, OUT_OF_RANGE_COOLDOWN)
        dprint(string.format("[inspect] DROP: %s L%d — %s (retry in %ds)",
            tname, tlvl, info or "unknown", OUT_OF_RANGE_COOLDOWN))
    end
    if ClearInspectPlayer then ClearInspectPlayer() end
    ClearCurrent()
end

-- ---------------- Self-scan ----------------
-- scanning yourself is a free fast path — no NotifyInspect required,
-- GetInventoryItemLink("player", slot) works immediately. Triggered by
-- UNIT_INVENTORY_CHANGED (debounced 2s so equipping a set doesn't fire 19
-- times) and once on PLAYER_LOGIN after a 3s warmup for talent data.

local SELF_SCAN_DEBOUNCE = 2
local SELF_SCAN_LOGIN_DELAY = 3

local selfScanPending = false
local selfScanAt = 0

local function RequestSelfScan(delay)
    selfScanPending = true
    selfScanAt = now() + (delay or SELF_SCAN_DEBOUNCE)
end

local function TryScanSelf()
    if not selfScanPending then return end
    if now() < selfScanAt then return end
    if requireInstance and not IsInstanceZone() then
        -- Don't cancel — we want to scan the moment we zone into an instance.
        -- Just defer the deadline.
        selfScanAt = now() + SELF_SCAN_DEBOUNCE
        return
    end
    if InCombatLockdown() then
        selfScanAt = now() + SELF_SCAN_DEBOUNCE
        return
    end
    selfScanPending = false

    local playerGUID = UnitGUID("player")
    if not playerGUID then return end

    local payload, info = BuildPayload("player", playerGUID)
    if not payload then
        dprint(string.format("[self] scan skipped — %s", info or "unknown"))
        return
    end
    dprint(string.format("[self] scanned self — %d slots equipped, payload %d bytes",
        info, #payload))
    MarkInspected(playerGUID, floor(time()))
    EnqueueBroadcast(payload, UnitName("player"))
    Ingest(payload, UnitName("player"))
end

-- ---------------- Main loop + events ----------------

local acc, gcAcc = 0, 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc < 0.25 then return end
    acc = 0

    if (now() - lastRoster) > ROSTER_TICK then ScanRoster() end

    if #outQueue > 0 and now() >= nextSendAt then
        local item = table.remove(outQueue, 1)
        SendAddonMessage(PREFIX, item.body, item.ch)
        nextSendAt = now() + BROADCAST_STAGGER
    end

    CheckTimeout()
    TryInspect()
    TryScanSelf()
    TryCachePending()
    TrySendVersionPing()

    gcAcc = gcAcc + 0.25
    if gcAcc >= 10 then gcAcc = 0; GCAssembly() end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("INSPECT_TALENT_READY")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("UNIT_INVENTORY_CHANGED") -- self gear changes trigger a rescan of "player"

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EpogArmoryDB = EpogArmoryDB or { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = {} }
        EpogArmoryDB.players     = EpogArmoryDB.players     or {}
        EpogArmoryDB.lastScanned = EpogArmoryDB.lastScanned or {}
        EpogArmoryDB.config      = EpogArmoryDB.config      or {}
        if EpogArmoryDB.config.requireInstance == nil then
            EpogArmoryDB.config.requireInstance = true
        end
        requireInstance = EpogArmoryDB.config.requireInstance
        EpogItemCacheDB = EpogItemCacheDB or {}
        RequestSelfScan(SELF_SCAN_LOGIN_DELAY) -- initial self-scan after talent data warms up
        versionPingAt = now() + VERSION_PING_DELAY -- one-shot version broadcast, 2min after login
        return
    end
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    elseif event == "INSPECT_TALENT_READY" then
        OnInspectReady()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then RequestSelfScan() end
    else
        ScanRoster()
    end
end)

-- ---------------- Slash ----------------

local function CountStored()
    if not EpogArmoryDB or not EpogArmoryDB.players then return 0 end
    local n = 0
    for _ in pairs(EpogArmoryDB.players) do n = n + 1 end
    return n
end

local function CountTracked()
    if not EpogArmoryDB or not EpogArmoryDB.lastScanned then return 0 end
    local n = 0
    for _ in pairs(EpogArmoryDB.lastScanned) do n = n + 1 end
    return n
end

local function CountAssembly()
    local n = 0
    for _ in pairs(assembly) do n = n + 1 end
    return n
end

local function CountCache()
    if not EpogItemCacheDB then return 0 end
    local n = 0
    for _ in pairs(EpogItemCacheDB) do n = n + 1 end
    return n
end

local function CountPending()
    local n = 0
    for _ in pairs(pendingCache) do n = n + 1 end
    return n
end

-- iterate all stored players and feed every itemID through the cache.
-- Anything not cached locally gets queued for a SetHyperlink-triggered server
-- fetch; the OnUpdate poll picks them up over the next few seconds.
local function CacheBuildAll()
    if not EpogArmoryDB or not EpogArmoryDB.players then return 0, 0, 0 end
    local tried, hit, pended = 0, 0, 0
    for _, p in pairs(EpogArmoryDB.players) do
        if p.gear then
            for slot = 1, 19 do
                local raw = p.gear[slot]
                if raw and raw ~= "" then
                    local iid = tonumber(raw:match("^(%d+)"))
                    if iid and iid > 0 then
                        tried = tried + 1
                        if CacheItemInfo(iid) then
                            hit = hit + 1
                        else
                            MarkPendingCache(iid)
                            pended = pended + 1
                        end
                    end
                end
            end
        end
    end
    return tried, hit, pended
end

local function ShowHelp()
    print("|cffffaa44EpogArmory|r commands:")
    print("  /epogarmory show <name>   — open paperdoll for a stored player (or target + /epogarmory show)")
    print("  /epogarmory browse        — open the searchable armory browser")
    print("  /epogarmory status        — queue / broadcast / storage state")
    print("  /epogarmory debug         — toggle verbose chat logging")
    print("  /epogarmory list          — print every stored player")
    print("  /epogarmory wipe          — clear stored players (keeps config)")
    print("  /epogarmory instance on   — only scan/store inside dungeon/raid (default)")
    print("  /epogarmory instance off  — scan/store everywhere (testing)")
    print("  /epogarmory cache         — show item-info cache size")
    print("  /epogarmory cachebuild    — fill the cache from all stored players' gear (names/quality/ilvl)")
    print("  /epogarmory cachewipe     — clear the item-info cache")
end

SLASH_EPOGARMORY1 = "/epogarmory"
SlashCmdList["EPOGARMORY"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "debug" then
        EpogArmoryDebug = not EpogArmoryDebug
        print("|cffffaa44EpogArmory|r debug:",
            EpogArmoryDebug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
    elseif msg == "status" then
        print(string.format("|cffffaa44EpogArmory|r stored=%d tracked=%d cache=%d cachePending=%d queue=%d outPending=%d asm=%d currentInspect=%s requireInstance=%s inCombat=%s zone=%s",
            CountStored(), CountTracked(), CountCache(), CountPending(),
            #queue, #outQueue, CountAssembly(),
            current and UnitName(current.unit) or "none",
            tostring(requireInstance),
            tostring(InCombatLockdown()),
            ZoneType()))
    elseif msg == "cache" then
        print(string.format("|cffffaa44EpogArmory|r cache: %d items known, %d pending client fetch",
            CountCache(), CountPending()))
    elseif msg == "cachebuild" then
        local tried, hit, pended = CacheBuildAll()
        print(string.format("|cffffaa44EpogArmory|r cachebuild: %d items scanned, %d already known, %d queued for fetch (check /epogarmory cache in ~15s)",
            tried, hit, pended))
    elseif msg == "cachewipe" then
        EpogItemCacheDB = {}
        pendingCache = {}
        print("|cffffaa44EpogArmory|r: wiped item-info cache")
    elseif msg == "instance on" or msg == "instance true" then
        requireInstance = true
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        EpogArmoryDB.config.requireInstance = true
        print("|cffffaa44EpogArmory|r: requireInstance = |cff00ff00true|r (scan + store only in dungeon/raid)")
    elseif msg == "instance off" or msg == "instance false" then
        requireInstance = false
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        EpogArmoryDB.config.requireInstance = false
        print("|cffffaa44EpogArmory|r: requireInstance = |cffff0000false|r (scan + store everywhere — testing mode)")
    elseif msg == "wipe" then
        local kept = EpogArmoryDB and EpogArmoryDB.config or {}
        EpogArmoryDB = { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = kept }
        print("|cffffaa44EpogArmory|r: wiped players + lastScanned (kept config)")
    elseif msg == "list" then
        if not EpogArmoryDB or not EpogArmoryDB.players then print("empty") return end
        for guid, p in pairs(EpogArmoryDB.players) do
            print(string.format("  %s %s L%d [%s] — by %s at %s",
                p.class or "?", p.name or "?", p.level or 0, p.zone or "?",
                p.scannedBy or "?", date("%Y-%m-%d %H:%M", p.scanTime or 0)))
        end
    else
        ShowHelp()
    end
end
