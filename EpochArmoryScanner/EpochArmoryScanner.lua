-- EpochArmoryScanner.lua
-- Claude: scanner-only addon. Inspects group/raid/guildmates, broadcasts gear
-- chunks over the "EpArmr" addon prefix. A Collector elsewhere will receive
-- and persist the data. Does not write any SavedVariables itself.
--
-- NOTE: this file's core logic is duplicated inside EpochArmoryCollector.lua.
-- If you change protocol constants or scan behavior, update both.

local ADDON = "EpochArmoryScanner"
local PREFIX = "EpArmr"
local PROTO = "1"

-- Tuning
local INSPECT_COOLDOWN  = 900    -- Claude: 15 min before rescanning same GUID
local INSPECT_TIMEOUT   = 4      -- Claude: give up after 4s of no INSPECT_TALENT_READY
local INSPECT_INTERVAL  = 2.5    -- Claude: delay between successive NotifyInspect calls
local BROADCAST_STAGGER = 0.3    -- Claude: delay between addon-message chunk sends
local MAX_CHUNK_BODY    = 200    -- Claude: keep well below 255-byte chat msg limit
local ROSTER_TICK       = 10     -- Claude: re-scan group roster every 10s
local MIN_INSPECT_LEVEL = 60     -- Claude: skip sub-cap alts; collector rejects <60 anyway

-- State
local queue         = {}          -- Claude: pending inspect targets (list)
local inQueue       = {}          -- Claude: guid -> true (dedupe)
local seen          = {}          -- Claude: guid -> lastScanTime
local current       = nil         -- Claude: {guid, unit, startedAt}
local outQueue      = {}          -- Claude: pending addon-message chunks
local nextInspectAt = 0
local nextSendAt    = 0
local lastRoster    = 0
local msgCounter    = 0

local function now() return GetTime() end

local function dprint(...)
    if EpochArmoryScannerDebug then
        print("|cff00ff88EpArmrS|r:", ...)
    end
end

-- Claude: skip all scan/broadcast work if the Collector is loaded; it handles both.
local function ScannerDisabled()
    if IsAddOnLoaded("EpochArmoryCollector") then return true end
    return false
end

-- Claude: return the zone context type for filtering on the webpage side.
local function ZoneType()
    local inInstance, instType = IsInInstance()
    if not inInstance then return "outdoor" end
    if instType == "raid" then return "raid" end
    if instType == "party" then return "party" end
    if instType == "pvp" then return "bg" end
    if instType == "arena" then return "arena" end
    return instType or "unknown"
end

-- Claude: only scan when inside a 5-man or raid instance — collector rejects
-- everything else, so don't waste inspect bandwidth elsewhere.
local function IsInstanceZone()
    local z = ZoneType()
    return z == "party" or z == "raid"
end

-- Claude: strip localized name, keep the itemString portion (e.g. "3184:0:0:...").
local function ItemStringFromLink(link)
    if not link then return "" end
    local s = link:match("|Hitem:([%-%d:]+)|h")
    return s or ""
end

-- Claude: build the pipe-separated gear payload for a unit.
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
    -- Claude: drop naked/low-gear scans at source to cut noise
    if equipped < 10 then return nil end
    return table.concat(parts, "^")
end

-- Claude: split a payload into body chunks sized to fit under the 255-byte msg cap.
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

-- Claude: pick channel(s). Prefer the group the target is in; also fan out to GUILD.
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
    if not IsInstanceZone() then return end
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
    if not IsInstanceZone() then return end
    if InCombatLockdown() then return end -- Claude: defer inspects until out of combat

    local entry = table.remove(queue, 1)
    inQueue[entry.guid] = nil
    if not UnitExists(entry.unit) or UnitGUID(entry.unit) ~= entry.guid then
        return -- Claude: raid slot shuffled; will be re-enqueued on next roster tick
    end
    if not CanInspect(entry.unit) then
        seen[entry.guid] = now() -- Claude: avoid tight retry loop
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
    else
        seen[c.guid] = now() -- Claude: don't retry bad/naked scans immediately
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
    if ScannerDisabled() then return end
    if event == "INSPECT_TALENT_READY" then
        OnInspectReady()
    else
        ScanRoster()
    end
end)

SLASH_EPARMRS1 = "/eparmrs"
SlashCmdList["EPARMRS"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "debug" then
        EpochArmoryScannerDebug = not EpochArmoryScannerDebug
        print("EpArmrS debug:", EpochArmoryScannerDebug and "on" or "off")
    elseif msg == "status" then
        print(string.format("EpArmrS queue=%d out=%d cur=%s disabled=%s",
            #queue, #outQueue,
            current and UnitName(current.unit) or "none",
            tostring(ScannerDisabled())))
    else
        print("EpochArmoryScanner: /eparmrs debug | status")
    end
end
