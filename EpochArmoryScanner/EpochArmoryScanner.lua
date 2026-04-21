-- EpochArmoryScanner.lua
-- Claude: scanner-only addon. Inspects group/raid/guildmates, broadcasts gear
-- chunks over the "EpArmr" addon prefix. A Collector elsewhere will receive
-- and persist the data. Does not write any SavedVariables beyond config flags.
--
-- NOTE: this file's core logic is duplicated inside EpochArmoryCollector.lua.
-- If you change protocol constants or scan behavior, update both.

local ADDON = "EpochArmoryScanner"
local PREFIX = "EpArmr"
local PROTO = "1"

-- Tuning
local INSPECT_COOLDOWN      = 900    -- Claude: 15 min before rescanning same GUID after a successful scan
local OUT_OF_RANGE_COOLDOWN = 30     -- Claude: retry 30s later when CanInspect fails (range/visibility)
local INSPECT_TIMEOUT       = 4      -- Claude: give up after 4s of no INSPECT_TALENT_READY
local INSPECT_INTERVAL      = 2.5    -- Claude: delay between successive NotifyInspect calls
local BROADCAST_STAGGER     = 0.3    -- Claude: delay between addon-message chunk sends
local MAX_CHUNK_BODY        = 200    -- Claude: keep well below 255-byte chat msg limit
local ROSTER_TICK           = 10     -- Claude: re-scan group roster every 10s
local MIN_INSPECT_LEVEL     = 60     -- Claude: skip sub-cap alts; collector rejects <60 anyway

-- Claude: runtime config, persisted in EpochArmoryScannerDB on logout.
-- Default true; toggle via /epocharmoryscanner instance on|off for testing.
local requireInstance = true

-- State
local queue         = {}
local inQueue       = {}
local seen          = {} -- Claude: guid -> lastScanTime (epoch-style via GetTime)
local current       = nil
local outQueue      = {}
local nextInspectAt = 0
local nextSendAt    = 0
local lastRoster    = 0
local msgCounter    = 0

local function now() return GetTime() end

local function dprint(...)
    if EpochArmoryScannerDebug then
        print("|cff00ff88EpArmrS|r", ...)
    end
end

-- Claude: bump last-seen timestamp so AddUnit will skip this GUID until
-- `retryIn` seconds from now. Reuses the single `seen` table (no separate
-- retry table needed).
local function markRetryIn(guid, retryIn)
    seen[guid] = now() - (INSPECT_COOLDOWN - retryIn)
end

local function ScannerDisabled()
    if IsAddOnLoaded("EpochArmoryCollector") then return true end
    return false
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

-- Claude: returns (payload, equippedCount) on success, (nil, reason) on failure.
local function BuildPayload(unit, guid)
    local name = UnitName(unit)
    if not name or name == "" or name == UNKNOWN then return nil, "name unresolved" end
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
        dprint(string.format("[inspect] TIMEOUT: %s — no INSPECT_TALENT_READY after %ds, moving on",
            UnitName(current.unit) or "?", INSPECT_TIMEOUT))
        seen[current.guid] = now()
        ClearCurrent()
    end
end

local function OnInspectReady()
    if not current then return end
    local c = current
    if UnitGUID(c.unit) ~= c.guid then
        dprint("[inspect] READY fired but current inspect GUID no longer matches — dropping")
        ClearCurrent()
        return
    end
    local tname = UnitName(c.unit) or "?"
    local tlvl = UnitLevel(c.unit) or 0
    local payload, info = BuildPayload(c.unit, c.guid)
    if payload then
        seen[c.guid] = now()
        dprint(string.format("[inspect] OK: %s L%d — %d slots equipped, payload %d bytes",
            tname, tlvl, info, #payload))
        EnqueueBroadcast(payload, tname)
    else
        seen[c.guid] = now()
        dprint(string.format("[inspect] DROP: %s L%d — %s", tname, tlvl, info or "unknown"))
    end
    if ClearInspectPlayer then ClearInspectPlayer() end
    ClearCurrent()
end

local acc = 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(self, elapsed)
    if ScannerDisabled() then return end
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
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("INSPECT_TALENT_READY")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EpochArmoryScannerDB = EpochArmoryScannerDB or {}
        if EpochArmoryScannerDB.requireInstance == nil then
            EpochArmoryScannerDB.requireInstance = true
        end
        requireInstance = EpochArmoryScannerDB.requireInstance
    end
    if ScannerDisabled() then return end
    if event == "INSPECT_TALENT_READY" then
        OnInspectReady()
    else
        ScanRoster()
    end
end)

local function ShowHelp()
    print("|cff00ff88EpochArmoryScanner|r:")
    print("  /epocharmoryscanner status        — show queue/broadcast state")
    print("  /epocharmoryscanner debug         — toggle verbose chat logging")
    print("  /epocharmoryscanner instance on   — only scan inside dungeon/raid (default)")
    print("  /epocharmoryscanner instance off  — scan everywhere (for testing)")
end

SLASH_EPOCHARMORYSCANNER1 = "/epocharmoryscanner"
SlashCmdList["EPOCHARMORYSCANNER"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "debug" then
        EpochArmoryScannerDebug = not EpochArmoryScannerDebug
        print("|cff00ff88EpArmrS|r debug:", EpochArmoryScannerDebug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
    elseif msg == "status" then
        print(string.format("|cff00ff88EpArmrS|r queue=%d outPending=%d currentInspect=%s disabled=%s requireInstance=%s inCombat=%s zone=%s",
            #queue, #outQueue,
            current and UnitName(current.unit) or "none",
            tostring(ScannerDisabled()),
            tostring(requireInstance),
            tostring(InCombatLockdown()),
            ZoneType()))
    elseif msg == "instance on" or msg == "instance true" then
        requireInstance = true
        EpochArmoryScannerDB = EpochArmoryScannerDB or {}
        EpochArmoryScannerDB.requireInstance = true
        print("|cff00ff88EpArmrS|r: requireInstance = |cff00ff00true|r (scan only inside dungeon/raid)")
    elseif msg == "instance off" or msg == "instance false" then
        requireInstance = false
        EpochArmoryScannerDB = EpochArmoryScannerDB or {}
        EpochArmoryScannerDB.requireInstance = false
        print("|cff00ff88EpArmrS|r: requireInstance = |cffff0000false|r (scan everywhere — testing mode)")
    else
        ShowHelp()
    end
end
