-- EpochArmoryCollector.lua
-- Claude: collector addon. Does everything the Scanner does (inspect groupmates,
-- broadcast chunked gear over "EpArmr" addon prefix) AND listens on the same
-- prefix to reassemble chunks from other senders, saving latest gear per GUID
-- to EpochArmoryDB for manual upload to epochlogs.com.
--
-- NOTE: the "scanner" half duplicates EpochArmoryScanner.lua. If you change the
-- protocol or scan behavior, update both files.

local ADDON = "EpochArmoryCollector"
local PREFIX = "EpArmr"
local PROTO = "1"

-- Tuning
local INSPECT_COOLDOWN   = 900
local INSPECT_TIMEOUT    = 4
local INSPECT_INTERVAL   = 2.5
local BROADCAST_STAGGER  = 0.3
local MAX_CHUNK_BODY     = 200
local ROSTER_TICK        = 10
local MIN_INSPECT_LEVEL  = 10      -- Claude: scanner-side min level (skip naked alts at source)
local MIN_STORE_LEVEL    = 70      -- Claude: collector rejects saves below this (adjust for server cap)
local MIN_STORE_EQUIPPED = 10      -- Claude: drop snapshots with fewer equipped slots
local ASSEMBLY_TIMEOUT   = 60      -- Claude: drop partially-received messages after 60s

-- ---------------- State: scanner half ----------------
local queue, inQueue, seen = {}, {}, {}
local current = nil
local outQueue = {}
local nextInspectAt, nextSendAt, lastRoster = 0, 0, 0
local msgCounter = 0

-- ---------------- State: receiver half ---------------
local assembly = {} -- Claude: key "sender\001msgID" -> {chunks, total, firstSeen}

local function now() return GetTime() end

local function dprint(...)
    if EpochArmoryCollectorDebug then
        print("|cff88ccffEpArmrC|r:", ...)
    end
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

local function InPvPZone()
    local z = ZoneType()
    return z == "bg" or z == "arena"
end

local function ItemStringFromLink(link)
    if not link then return "" end
    local s = link:match("|Hitem:([%-%d:]+)|h")
    return s or ""
end

-- ---------------- Scanner: build + broadcast ----------------

local function BuildPayload(unit, guid)
    local name = UnitName(unit)
    if not name or name == "" or name == UNKNOWN then return nil end
    local realm = GetRealmName() or ""
    local _, classFile = UnitClass(unit)
    classFile = classFile or ""
    local level = UnitLevel(unit) or 0

    local s1 = select(3, GetTalentTabInfo(1, true)) or 0
    local s2 = select(3, GetTalentTabInfo(2, true)) or 0
    local s3 = select(3, GetTalentTabInfo(3, true)) or 0

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
    if equipped < 10 then return nil end
    return table.concat(parts, "^")
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

local function EnqueueBroadcast(payload)
    local channels = PickChannels()
    if #channels == 0 then return end
    msgCounter = msgCounter + 1
    local msgID = string.format("%x%x", math.floor(now() * 10) % 0xffff, msgCounter % 0xffff)
    local chunks = MakeChunks(payload, msgID)
    for _, ch in ipairs(channels) do
        for _, body in ipairs(chunks) do
            outQueue[#outQueue + 1] = { ch = ch, body = body }
        end
    end
    dprint(string.format("queued %d chunks x %d channels", #chunks, #channels))
end

-- ---------------- Receiver: parse + store ----------------

-- Claude: drop PvP/low/naked scans at the collector boundary too (defense in depth).
local function ShouldStore(entry)
    if not entry then return false end
    if (entry.level or 0) < MIN_STORE_LEVEL then return false end
    if entry.zone == "bg" or entry.zone == "arena" then return false end
    local equipped = 0
    for i = 1, 19 do
        if entry.gear[i] and entry.gear[i] ~= "" then equipped = equipped + 1 end
    end
    if equipped < MIN_STORE_EQUIPPED then return false end
    return true
end

local function ParsePayload(payload)
    local t = { strsplit("^", payload) }
    if t[1] ~= ("v" .. PROTO) then return nil end
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
    if not entry then return end
    if not ShouldStore(entry) then
        dprint("rejected:", entry.name, "L" .. entry.level, entry.zone)
        return
    end

    EpochArmoryDB = EpochArmoryDB or { meta = { version = 1, created = time() }, players = {} }
    EpochArmoryDB.players = EpochArmoryDB.players or {}

    local existing = EpochArmoryDB.players[entry.guid]
    if existing and (existing.scanTime or 0) >= entry.scanTime then
        return -- Claude: we already have equal-or-newer data
    end

    entry.scannedBy = sender or (UnitName("player") or "?")
    EpochArmoryDB.players[entry.guid] = entry
    dprint("stored", entry.name, "L" .. entry.level, entry.zone, "by", entry.scannedBy)
end

local function OnAddonMessage(prefix, body, channel, sender)
    if prefix ~= PREFIX then return end
    if not body or body == "" then return end
    -- Claude: 3.3.5 strsplit has no limit param; payload chunks legitimately contain
    -- '^', so parse the 3-field header + rest via string.match instead.
    local msgID, idx_s, total_s, data = body:match("^([^%^]+)%^([^%^]+)%^([^%^]+)%^(.*)$")
    local idx = tonumber(idx_s)
    local total = tonumber(total_s)
    if not msgID or not idx or not total or not data then return end

    local key = (sender or "?") .. "\001" .. msgID
    local asm = assembly[key]
    if not asm then
        asm = { chunks = {}, total = total, firstSeen = now() }
        assembly[key] = asm
    end
    if asm.chunks[idx] then return end -- Claude: duplicate chunk
    asm.chunks[idx] = data

    local have = 0
    for i = 1, total do
        if asm.chunks[i] then have = have + 1 end
    end
    if have == total then
        local pieces = {}
        for i = 1, total do pieces[i] = asm.chunks[i] end
        assembly[key] = nil
        Ingest(table.concat(pieces), sender)
    end
end

local function GCAssembly()
    local cutoff = now() - ASSEMBLY_TIMEOUT
    for k, v in pairs(assembly) do
        if v.firstSeen < cutoff then assembly[k] = nil end
    end
end

-- ---------------- Scanner: queue + inspect driver ----------------

local function AddUnit(unit)
    if not UnitExists(unit) then return end
    if UnitIsUnit(unit, "player") then return end
    if not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or guid == "" then return end
    if inQueue[guid] then return end
    local last = seen[guid]
    if last and (now() - last) < INSPECT_COOLDOWN then return end
    if (UnitLevel(unit) or 0) < MIN_INSPECT_LEVEL then return end
    queue[#queue + 1] = { guid = guid, unit = unit }
    inQueue[guid] = true
end

local function ScanRoster()
    lastRoster = now()
    if InPvPZone() then return end
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do AddUnit("raid" .. i) end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, 4 do AddUnit("party" .. i) end
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
    if InPvPZone() then return end

    local entry = table.remove(queue, 1)
    inQueue[entry.guid] = nil
    if not UnitExists(entry.unit) or UnitGUID(entry.unit) ~= entry.guid then
        return
    end
    if not CanInspect(entry.unit) then
        seen[entry.guid] = now()
        return
    end
    current = { guid = entry.guid, unit = entry.unit, startedAt = now() }
    NotifyInspect(entry.unit)
    dprint("NotifyInspect", UnitName(entry.unit))
end

local function CheckTimeout()
    if current and (now() - current.startedAt) > INSPECT_TIMEOUT then
        dprint("inspect timeout", current.unit)
        seen[current.guid] = now()
        ClearCurrent()
    end
end

local function OnInspectReady()
    if not current then return end
    local c = current
    if UnitGUID(c.unit) ~= c.guid then
        ClearCurrent()
        return
    end
    local payload = BuildPayload(c.unit, c.guid)
    if payload then
        seen[c.guid] = now()
        EnqueueBroadcast(payload)
        -- Claude: direct-ingest our own scan so we save data even when we don't
        -- receive our own addon-msg echo (e.g. zero group members present).
        Ingest(payload, UnitName("player"))
    else
        seen[c.guid] = now()
    end
    if ClearInspectPlayer then ClearInspectPlayer() end
    ClearCurrent()
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

    gcAcc = gcAcc + 0.25
    if gcAcc >= 10 then gcAcc = 0; GCAssembly() end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("INSPECT_TALENT_READY")
f:RegisterEvent("CHAT_MSG_ADDON")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    elseif event == "INSPECT_TALENT_READY" then
        OnInspectReady()
    else
        ScanRoster()
    end
end)

-- ---------------- Slash ----------------

local function CountStored()
    if not EpochArmoryDB or not EpochArmoryDB.players then return 0 end
    local n = 0
    for _ in pairs(EpochArmoryDB.players) do n = n + 1 end
    return n
end

SLASH_EPARMRC1 = "/eparmr"
SLASH_EPARMRC2 = "/eparmrc"
SlashCmdList["EPARMRC"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "debug" then
        EpochArmoryCollectorDebug = not EpochArmoryCollectorDebug
        print("EpArmrC debug:", EpochArmoryCollectorDebug and "on" or "off")
    elseif msg == "status" then
        print(string.format("EpArmrC stored=%d queue=%d out=%d asm=%d cur=%s",
            CountStored(), #queue, #outQueue,
            (function() local n = 0 for _ in pairs(assembly) do n = n + 1 end return n end)(),
            current and UnitName(current.unit) or "none"))
    elseif msg == "wipe" then
        EpochArmoryDB = { meta = { version = 1, created = time() }, players = {} }
        print("EpArmrC: wiped database")
    elseif msg == "list" then
        if not EpochArmoryDB or not EpochArmoryDB.players then print("empty") return end
        for guid, p in pairs(EpochArmoryDB.players) do
            print(string.format("  %s %s L%d %s (by %s, %s)",
                p.class or "?", p.name or "?", p.level or 0, p.zone or "?",
                p.scannedBy or "?", date("%Y-%m-%d %H:%M", p.scanTime or 0)))
        end
    else
        print("EpochArmoryCollector: /eparmrc status | debug | list | wipe")
    end
end
