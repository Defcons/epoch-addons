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
-- Delay between consecutive addon-message sends from outQueue. Local inspect
-- + ingest is instant; this gate only affects how fast data chatters out to
-- peers. Peers don't need scans within seconds — eventually is fine, and
-- spreading sends keeps the outgoing byte-rate tiny (~45 B/s at 2.0) so we
-- never brush against Blizzard's ~800 B/s addon-message throttle in a churn
-- like raid-roster-formation.
local BROADCAST_STAGGER     = 2.0
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
    [464] = "Enchant Gloves - Riding Skill", -- Minor +mount speed
}

-- Item-name blacklist patterns, matched via GetItemInfo at store time. Used
-- for items whose IDs vary across Ascension's custom content but whose names
-- are stable.
local UTILITY_ITEM_NAMES_ANY_SLOT = {
    "Rugged Sandle",   -- user's spelling (exact)
    "Rugged Sandal",   -- alternate spelling ("Rugged Sandals")
}

-- Slot-restricted name patterns. Applied only when the item is in the listed
-- equipment slots. Keyed by slot index (13, 14 = trinket slots).
local UTILITY_ITEM_NAMES_BY_SLOT = {
    [13] = { "Insignia" }, -- PvP trinkets: "Insignia of the Alliance/Horde" etc.
    [14] = { "Insignia" },
}

-- Enchant-name patterns matched by tooltip text on specific slots. Used when
-- an enchant doesn't have a stable SpellItemEnchantment.dbc ID we can rely on
-- (e.g. Mithril Spurs — legacy engineering boot enchant). Only scanned on
-- slots in MOUNT_ENCHANT_SLOTS below, and only at BuildPayload time (sender
-- side) to avoid tooltip-scanning every received broadcast.
local UTILITY_ENCHANT_TOOLTIP_PATTERNS = {
    "Mithril Spurs",
}

local MOUNT_ENCHANT_SLOTS = { 8, 10 } -- feet, hands

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
-- Cache schema version. Bumped when the shape of EpogItemCacheDB[itemID]
-- changes in a way that requires re-fetching. Entries with a lower (or
-- missing) .v are treated as stale on the next touch, so pre-v0.22 entries
-- (no stats field) get a fresh GetItemStats call.
-- v1: name/quality/itemLevel/icon/ts
-- v2: + stats (v0.22)
local CACHE_SCHEMA = 2

local function now() return GetTime() end

-- Which of the 3 class talent trees has the most points. 1, 2, or 3. Used as
-- the per-player set key so a rogue's Assassination/Combat/Subtlety each get
-- their own gear snapshot. Matches the player's mental model of "spec"; works
-- regardless of Ascension's GetActiveTalentGroup quirks (which on a classless
-- client seem to always return 1 and aren't useful as a key here).
-- Ties break to the lowest index (arbitrary but stable).
local function DominantTree(spec)
    if not spec then return 1 end
    local maxIdx, maxVal = 1, spec[1] or 0
    for i = 2, 3 do
        if (spec[i] or 0) > maxVal then maxIdx, maxVal = i, spec[i] or 0 end
    end
    return maxIdx
end

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
-- itemLink (optional): the full "item:itemID:enchantID:gem1:..." string. Used
-- by GetItemStats below to capture Ascension's modified stat values. If
-- omitted, falls back to a bare "item:itemID" link which still returns the
-- base item's stats.
local function CacheItemInfo(itemID, itemLink)
    if not itemID or itemID <= 0 then return false end
    EpogItemCacheDB = EpogItemCacheDB or {}
    -- Skip only when we already have a current-schema entry. Pre-v0.22 entries
    -- (no .v, no stats) re-fetch here so they pick up GetItemStats data.
    local existing = EpogItemCacheDB[itemID]
    if existing and existing.v == CACHE_SCHEMA then return true end

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
    local entry = {
        v = CACHE_SCHEMA,
        name = name,
        quality = quality or 0,
        itemLevel = itemLevel or 0,
        icon = icon,
        ts = floor(time()),
    }

    -- v0.22: capture per-item stats via GetItemStats. Ascension modifies stats
    -- on most retail items and adds entirely server-custom items not in any
    -- TDB extract — the client API is the only authoritative source. Stored
    -- with the original ITEM_MOD_* keys so the site's ingest can map them
    -- via the same enum used for TDB merging. Random suffix variants are
    -- ignored per spec — first roll wins for a given itemID.
    if GetItemStats then
        local link = itemLink or ("item:" .. itemID)
        local stats = GetItemStats(link)
        if stats then
            local serial = {}
            for k, v in pairs(stats) do
                if type(v) == "number" and v ~= 0 then
                    serial[k] = v
                end
            end
            -- Skip empty {} for shirts/tabards etc. so a missing field reads
            -- as "no data captured" rather than "captured but empty".
            if next(serial) then
                entry.stats = serial
            end
        end
    end

    EpogItemCacheDB[itemID] = entry
    return true
end

local function MarkPendingCache(itemID, itemLink)
    if not itemID or itemID <= 0 then return end
    -- Only skip if a current-schema entry exists. Stale entries fall through
    -- so the pending retry loop eventually re-runs CacheItemInfo and upgrades.
    local existing = EpogItemCacheDB and EpogItemCacheDB[itemID]
    if existing and existing.v == CACHE_SCHEMA then return end
    if not pendingCache[itemID] then
        pendingCache[itemID] = { firstSeen = now(), link = itemLink }
        TriggerItemFetch(itemID)
    end
end

local function TryCachePending()
    if not next(pendingCache) then return end
    local nowT = now()
    for iid, info in pairs(pendingCache) do
        if CacheItemInfo(iid, info.link) then
            pendingCache[iid] = nil
        elseif (nowT - info.firstSeen) > CACHE_GIVE_UP then
            pendingCache[iid] = nil -- server never responded; try again on next scan
        end
    end
end

-- iterate gear slots, ensure every itemID is either cached or queued.
-- Passes the full itemstring as the hyperlink so GetItemStats can include
-- suffix-variant stats on the first scan that lands.
local function CachePayloadItems(entry)
    if not entry or not entry.gear then return end
    for slot = 1, 19 do
        local raw = entry.gear[slot]
        if raw and raw ~= "" then
            local iid = tonumber(raw:match("^(%d+)"))
            if iid and iid > 0 then
                local link = "item:" .. raw
                if not CacheItemInfo(iid, link) then MarkPendingCache(iid, link) end
            end
        end
    end
end

-- ---------------- Build + broadcast ----------------

-- Read the talent point distribution across the 3 tabs for a given unit.
-- Ascension's classless system sometimes returns 0 from GetTalentTabInfo's
-- pointsSpent field even when the player has real talents — so we also fall
-- back to summing pointsSpent across individual GetTalentInfo() reads. The
-- explicit talentGroup (from GetActiveTalentGroup) helps in cases where the
-- API doesn't default to the active group on Ascension.
-- Returns: s1, s2, s3, activeGroup (1-based, defaults to 1 when API missing).
local function ReadSpecPoints(unit)
    -- inspectFlag: 1 when reading another unit's talents (after NotifyInspect),
    -- nil for "player" — standard 3.3.5 GetTalentTabInfo convention.
    -- IMPORTANT: the idiom `cond and nil or 1` BREAKS when you want nil as the
    -- true branch — `true and nil` evaluates to `nil`, then `nil or 1` is `1`.
    -- Every self-scan from v0.3 through v0.15 was accidentally reading inspect
    -- data (isInspect=1) for "player", which returns 0 for every tab because
    -- you can't NotifyInspect yourself. That's why spec=0/0/0 on all self-scans.
    local isInspect
    if not UnitIsUnit(unit, "player") then isInspect = 1 end

    local function tabPoints(tabIndex)
        local pts = select(3, GetTalentTabInfo(tabIndex, isInspect)) or 0
        if pts > 0 then return pts end
        -- Fallback: iterate talents in this tab and sum pointsSpent directly.
        if GetNumTalents and GetTalentInfo then
            local n = GetNumTalents(tabIndex, isInspect) or 0
            local total = 0
            for i = 1, n do
                local _, _, _, _, spent = GetTalentInfo(tabIndex, i, isInspect)
                total = total + (spent or 0)
            end
            if total > 0 then return total end
        end
        return 0
    end

    return tabPoints(1), tabPoints(2), tabPoints(3)
end

-- Read the 3 class talent tabs' display names AND icon texture paths.
-- Ascension reorders tabs from retail WotLK on some classes, so we encode
-- this info per-scan into the payload rather than relying on a hardcoded
-- SPEC_TREE lookup. GetTalentTabInfo returns (name, iconTexture, pointsSpent,
-- background, previewPointsSpent, isUnlocked).
local function ReadTabInfo(unit)
    local isInspect
    if not UnitIsUnit(unit, "player") then isInspect = 1 end
    -- Defensive: strip the '^' separator and '|' (item-link escape) just in
    -- case a server-custom tab name or icon path contains them.
    local function clean(s) return (s or ""):gsub("[%^|]", "") end
    local names, icons = {}, {}
    for tab = 1, 3 do
        local n, i = GetTalentTabInfo(tab, isInspect)
        names[tab] = clean(n or "")
        icons[tab] = clean(i or "")
    end
    return names, icons
end

-- Scan the enchant description lines of an equipped item for blacklisted
-- patterns (Mithril Spurs etc.). Returns the first matching pattern or nil.
-- Only called on sender side (BuildPayload) so received broadcasts don't
-- pay the tooltip cost.
local enchantScanTip
local function ScanEnchantTooltip(link)
    if not link then return nil end
    if not enchantScanTip then
        enchantScanTip = CreateFrame("GameTooltip", "EpogArmoryEnchantScanTip", UIParent, "GameTooltipTemplate")
    end
    enchantScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    enchantScanTip:ClearLines()
    enchantScanTip:SetHyperlink(link)
    for i = 1, enchantScanTip:NumLines() do
        local fs = _G["EpogArmoryEnchantScanTipTextLeft" .. i]
        local text = fs and fs:GetText() or ""
        for _, pat in ipairs(UTILITY_ENCHANT_TOOLTIP_PATTERNS) do
            if text:find(pat, 1, true) then return pat end
        end
    end
    return nil
end

local function BuildPayload(unit, guid)
    local name = UnitName(unit)
    if not name or name == "" or name == UNKNOWN then return nil, "name unresolved" end
    local realm = GetRealmName() or ""
    local _, classFile = UnitClass(unit)
    classFile = classFile or ""
    local level = UnitLevel(unit) or 0

    local s1, s2, s3 = ReadSpecPoints(unit)
    local dominantTree = DominantTree({s1, s2, s3})
    local tabNames, tabIcons = ReadTabInfo(unit)

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

        -- Name-based item blacklist (sender side — receive side also checks)
        if link then
            local itemName = GetItemInfo(link)
            if itemName then
                for _, pat in ipairs(UTILITY_ITEM_NAMES_ANY_SLOT) do
                    if itemName:find(pat, 1, true) then
                        return nil, string.format("utility item '%s' in slot %d", itemName, slot)
                    end
                end
                local bySlot = UTILITY_ITEM_NAMES_BY_SLOT[slot]
                if bySlot then
                    for _, pat in ipairs(bySlot) do
                        if itemName:find(pat, 1, true) then
                            return nil, string.format("utility item '%s' in slot %d (blacklisted pattern '%s')", itemName, slot, pat)
                        end
                    end
                end
            end
        end

        parts[#parts + 1] = istr
    end
    -- Mount enchant tooltip scan on boots + gloves. Only runs once per scan
    -- per slot, only on sender side.
    for _, mountSlot in ipairs(MOUNT_ENCHANT_SLOTS) do
        local link = GetInventoryItemLink(unit, mountSlot)
        local bad = ScanEnchantTooltip(link)
        if bad then
            return nil, string.format("mount enchant '%s' on slot %d", bad, mountSlot)
        end
    end
    if equipped < 10 then
        return nil, string.format("only %d slots equipped (inspect data incomplete?)", equipped)
    end
    -- Append dominant-tree index at position 31 (per v0.7 append-only rule).
    -- v0.14+ receivers actually compute this locally from entry.spec, so the
    -- field is informational/forward-compat only. Old v0.12 clients ignore it.
    parts[#parts + 1] = tostring(dominantTree)
    -- Tab names at positions 32/33/34 so receivers can render class-tree
    -- labels that match the sender's actual client layout (Ascension reorders
    -- some classes vs retail WotLK). Older clients ignore the trailing fields.
    parts[#parts + 1] = tabNames[1]
    parts[#parts + 1] = tabNames[2]
    parts[#parts + 1] = tabNames[3]
    -- Tab icon paths at positions 35/36/37 (v0.18+) so the inspect-frame
    -- centerpiece icon exactly matches the server's spec icon.
    parts[#parts + 1] = tabIcons[1]
    parts[#parts + 1] = tabIcons[2]
    parts[#parts + 1] = tabIcons[3]
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
            -- Name-pattern blacklist (works across all Ascension custom item IDs).
            -- Only effective if GetItemInfo has cached the item — uncached items
            -- pass through this check. CachePayloadItems runs before ShouldStore
            -- so most will be resolved by now.
            if iid > 0 then
                local itemName = GetItemInfo(iid)
                if itemName then
                    for _, pat in ipairs(UTILITY_ITEM_NAMES_ANY_SLOT) do
                        if itemName:find(pat, 1, true) then
                            return false, "utility item name: " .. itemName
                        end
                    end
                    local bySlot = UTILITY_ITEM_NAMES_BY_SLOT[slot]
                    if bySlot then
                        for _, pat in ipairs(bySlot) do
                            if itemName:find(pat, 1, true) then
                                return false, string.format("utility item in slot %d: %s", slot, itemName)
                            end
                        end
                    end
                end
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
        name        = t[2] or "",
        realm       = t[3] or "",
        class       = t[4] or "",
        level       = tonumber(t[5]) or 0,
        guid        = t[6] or "",
        spec        = { tonumber(t[7]) or 0, tonumber(t[8]) or 0, tonumber(t[9]) or 0 },
        scanTime    = tonumber(t[10]) or 0,
        zone        = t[11] or "",
        gear        = {},
        talentGroup = tonumber(t[31]) or 1, -- v0.13+: position 31 is active talent group; v0.12 payloads default to 1
    }
    for i = 1, 19 do entry.gear[i] = t[11 + i] or "" end
    -- v0.17+: positions 32/33/34 carry class tab names ("Combat",
    -- "Assassination", "Subtlety"). Older payloads: tabNames stays nil and
    -- the UI falls back to SPEC_TREE[class].
    if t[32] and t[32] ~= "" then
        entry.tabNames = { t[32] or "", t[33] or "", t[34] or "" }
    end
    -- v0.18+: positions 35/36/37 carry tab icon texture paths for rendering
    -- the centerpiece spec icon in the inspect frame.
    if t[35] and t[35] ~= "" then
        entry.tabIcons = { t[35] or "", t[36] or "", t[37] or "" }
    end
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

    -- Set key = dominant tree (1=Arms/Assassination/etc, 2=Fury/Combat/..., 3=Prot/Subtlety/...).
    -- Computed locally from entry.spec, NOT read from wire position 31, so
    -- we're robust against sender bugs or clients using a different keying.
    local group = DominantTree(entry.spec)
    local scannedBy = sender or (UnitName("player") or "?")
    local existing = EpogArmoryDB.players[entry.guid]

    -- Per-spec dedup: only this tree's set is compared for staleness. A newer
    -- scan of a *different* tree set is never skipped here — different slot.
    if existing and existing.sets and existing.sets[group]
        and (existing.sets[group].scanTime or 0) >= entry.scanTime then
        dprint(string.format("[store] SKIP: %s (tree %d) — existing set is newer (%s vs %s)",
            entry.name, group,
            date("%H:%M:%S", existing.sets[group].scanTime or 0),
            date("%H:%M:%S", entry.scanTime)))
        return
    end

    -- Create or merge the player record, preserving sets for the other talent
    -- groups. Top-level `name/realm/class/level` always reflect the latest scan.
    existing = existing or { sets = {} }
    existing.sets  = existing.sets or {}
    existing.guid  = entry.guid -- v0.20: store guid on the record so the UI can pass it to DeletePlayer
    existing.name  = entry.name
    existing.realm = entry.realm
    existing.class = entry.class
    existing.level = entry.level
    if entry.tabNames then existing.tabNames = entry.tabNames end -- v0.17+
    if entry.tabIcons then existing.tabIcons = entry.tabIcons end -- v0.18+
    existing.sets[group] = {
        spec      = entry.spec,
        gear      = entry.gear,
        scanTime  = entry.scanTime,
        zone      = entry.zone,
        scannedBy = scannedBy,
    }

    -- Mirror the most-recently-scanned set to top-level fields for
    -- backward-compat with the UI (v0.14 UI reads directly from .sets and this
    -- mirror becomes redundant). Picks the highest-scanTime set across all
    -- stored talent groups.
    local latestSet, latestTime = nil, 0
    for _, s in pairs(existing.sets) do
        if (s.scanTime or 0) > latestTime then
            latestTime = s.scanTime or 0
            latestSet = s
        end
    end
    if latestSet then
        existing.spec      = latestSet.spec
        existing.gear      = latestSet.gear
        existing.scanTime  = latestSet.scanTime
        existing.zone      = latestSet.zone
        existing.scannedBy = latestSet.scannedBy
    end

    EpogArmoryDB.players[entry.guid] = existing
    dprint(string.format("[store] OK: %s L%d [tree %d / %s] — scanned by %s at %s",
        entry.name, entry.level, group, entry.zone, scannedBy,
        date("%H:%M:%S", entry.scanTime)))

    -- v0.21: notify the UI so an open browser list refreshes without the
    -- user having to close + reopen. Registered as a field on the shared
    -- namespace table; nil-safe if UI hasn't wired it up yet.
    if _G.EpogArmory and _G.EpogArmory.OnPlayerChanged then
        _G.EpogArmory.OnPlayerChanged(entry.guid)
    end
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
    -- Drop our own echoes. Addon messages broadcast on GUILD/PARTY/RAID always
    -- round-trip back to the sender's client, and when we broadcast to multiple
    -- channels (e.g. PARTY + GUILD) the payload echoes back once per channel.
    -- We already direct-ingest our own scans in TryScanSelf / OnInspectReady
    -- before broadcasting, so these echoes are pure spam — [recv] chunks,
    -- [store] SKIP, and duplicate [version] self-pings.
    if sender and sender == UnitName("player") then return end
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
-- Fingerprint of the last successfully-broadcast self-scan (level + talents
-- + gear itemStrings). On Ascension, UNIT_INVENTORY_CHANGED fires every ~15s
-- for reasons unrelated to real gear swaps (durability ticks, aura procs,
-- server-side refreshes), so without this check we'd rebroadcast the same
-- payload over and over. The fingerprint changes only when something that
-- actually matters to the mesh has changed.
local lastSelfFingerprint = ""

local function SelfFingerprint()
    local parts = { tostring(UnitLevel("player") or 0) }
    -- Spec points change on any talent shift → fingerprint differs → scan.
    -- No need to also include an "active group" field; the point distribution
    -- already captures what matters.
    local s1, s2, s3 = ReadSpecPoints("player")
    parts[#parts + 1] = string.format("%d:%d:%d", s1, s2, s3)
    for slot = 1, 19 do
        parts[#parts + 1] = ItemStringFromLink(GetInventoryItemLink("player", slot))
    end
    return table.concat(parts, "|")
end

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

    -- Silent short-circuit: nothing meaningful has changed since our last
    -- broadcast. UNIT_INVENTORY_CHANGED fires every ~15s on Ascension from
    -- durability/aura noise; unchanged fingerprint → no log, no work.
    -- Real changes (gear swap, respec, talent shift) bump the fingerprint
    -- and fall through to the actual scan. v0.13's per-active-group 24h
    -- gate is dropped — it was blocking legitimate respec scans because
    -- Ascension's classless GetActiveTalentGroup reports 1 unchanged, so
    -- the "active group" key never changed on a respec.
    local fp = SelfFingerprint()
    if fp == lastSelfFingerprint then return end

    local payload, info = BuildPayload("player", playerGUID)
    if not payload then
        dprint(string.format("[self] scan skipped — %s", info or "unknown"))
        return
    end
    lastSelfFingerprint = fp
    local _s1, _s2, _s3 = ReadSpecPoints("player")
    dprint(string.format("[self] scanned self — %d slots equipped, spec=%d/%d/%d tree=%d, payload %d bytes",
        info, _s1, _s2, _s3, DominantTree({_s1, _s2, _s3}), #payload))
    MarkInspected(playerGUID, floor(time()))
    EnqueueBroadcast(payload, UnitName("player"))
    Ingest(payload, UnitName("player"))
end

-- ---------------- Migration ----------------
-- v0.14 normalizes the per-player data model:
--   players[guid] = { name, realm, class, level,
--                     sets = { [dominantTree] = { spec, gear, scanTime, zone, scannedBy } },
--                     ...top-level mirror of latest set }
--
-- This runs once at login and handles two legacy shapes:
--   (a) Pre-v0.13 flat: { name, realm, class, level, spec, gear, scanTime, zone, scannedBy }
--       → wrap into sets[DominantTree(spec)].
--   (b) v0.13 sets keyed by activeTalentGroup (usually always 1 on Ascension)
--       → re-key by DominantTree(set.spec). If two entries collide, newest wins.
local function MigratePlayers()
    if not (EpogArmoryDB and EpogArmoryDB.players) then return end
    local migrated = 0
    for guid, p in pairs(EpogArmoryDB.players) do
        -- v0.20: backfill guid on the record. Pre-v0.20 entries didn't store
        -- it, so the UI's Delete button had nothing to pass to DeletePlayer.
        if not p.guid then p.guid = guid end
        if p.gear and not p.sets then
            -- (a) pre-v0.13 flat
            local tree = DominantTree(p.spec)
            p.sets = {
                [tree] = {
                    spec      = p.spec or { 0, 0, 0 },
                    gear      = p.gear,
                    scanTime  = p.scanTime or 0,
                    zone      = p.zone or "",
                    scannedBy = p.scannedBy or "?",
                }
            }
            migrated = migrated + 1
        elseif p.sets then
            -- (b) v0.13 sets → re-key under DominantTree if any entry's key
            -- disagrees with its spec's dominant tree.
            local rekeyed = {}
            local changed = false
            for oldKey, s in pairs(p.sets) do
                local newKey = DominantTree(s.spec)
                if newKey ~= oldKey then changed = true end
                if (not rekeyed[newKey]) or ((rekeyed[newKey].scanTime or 0) < (s.scanTime or 0)) then
                    rekeyed[newKey] = s
                end
            end
            if changed then
                p.sets = rekeyed
                migrated = migrated + 1
            end
        end
    end
    if migrated > 0 then
        dprint(string.format("[migrate] normalized %d player entries to DominantTree keys", migrated))
    end
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
f:RegisterEvent("PLAYER_TALENT_UPDATE")   -- respec / dual-spec switch triggers a rescan of "player"

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
        MigratePlayers() -- wrap pre-v0.13 flat entries into sets[1]
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
    elseif event == "PLAYER_TALENT_UPDATE" then
        RequestSelfScan()
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

-- Public namespace entry used by the UI's Delete button. Clears one player
-- from the local DB so the mesh can refill on the next scan from any peer.
-- Also resets the 24h HasFreshScan gate for this GUID (by wiping
-- lastScanned[guid]) and the in-memory 15min inspect cooldown (seen[guid]),
-- so *this client* can re-inspect immediately if they're in range. If the
-- user is deleting their own entry, force a fresh self-scan by clearing the
-- fingerprint and queueing RequestSelfScan.
_G.EpogArmory = _G.EpogArmory or {}
_G.EpogArmory.DeletePlayer = function(guid)
    if not guid or guid == "" then return end
    local name = "?"
    if EpogArmoryDB and EpogArmoryDB.players and EpogArmoryDB.players[guid] then
        name = EpogArmoryDB.players[guid].name or "?"
        EpogArmoryDB.players[guid] = nil
    end
    if EpogArmoryDB and EpogArmoryDB.lastScanned then
        EpogArmoryDB.lastScanned[guid] = nil
    end
    seen[guid] = nil
    if guid == UnitGUID("player") then
        lastSelfFingerprint = ""
        RequestSelfScan()
    end
    dprint(string.format("[delete] removed %s (%s) from local DB", name, guid))
end

-- iterate all stored players and feed every itemID through the cache.
-- Anything not cached locally gets queued for a SetHyperlink-triggered server
-- fetch; the OnUpdate poll picks them up over the next few seconds.
local function CacheBuildAll()
    if not EpogArmoryDB or not EpogArmoryDB.players then return 0, 0, 0 end
    local tried, hit, pended = 0, 0, 0
    local function processGear(gear)
        for slot = 1, 19 do
            local raw = gear[slot]
            if raw and raw ~= "" then
                local iid = tonumber(raw:match("^(%d+)"))
                if iid and iid > 0 then
                    tried = tried + 1
                    local link = "item:" .. raw
                    if CacheItemInfo(iid, link) then
                        hit = hit + 1
                    else
                        MarkPendingCache(iid, link)
                        pended = pended + 1
                    end
                end
            end
        end
    end
    for _, p in pairs(EpogArmoryDB.players) do
        -- v0.22: walk per-spec sets so stats get captured for every loadout,
        -- not just the latest-mirror p.gear. The CacheItemInfo dedup makes
        -- redundant calls cheap (early-out on EpogItemCacheDB[itemID]).
        if p.sets then
            for _, s in pairs(p.sets) do
                if s.gear then processGear(s.gear) end
            end
        elseif p.gear then
            processGear(p.gear)
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
    print("|cff888888  Source + releases: github.com/Defcons/epogarmory-addon|r")
    -- dumpspec left in place but not advertised — internal diagnostic.
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
        -- Clear in-memory self-scan dedup state too, otherwise the next scan
        -- short-circuits on a fingerprint match against the pre-wipe state and
        -- your own player never gets re-added to the freshly-wiped DB.
        lastSelfFingerprint = ""
        RequestSelfScan()
        print("|cffffaa44EpogArmory|r: wiped players + lastScanned (kept config) — self-scan queued")
    elseif msg == "list" then
        if not EpogArmoryDB or not EpogArmoryDB.players then print("empty") return end
        for guid, p in pairs(EpogArmoryDB.players) do
            print(string.format("  %s %s L%d [%s] — by %s at %s",
                p.class or "?", p.name or "?", p.level or 0, p.zone or "?",
                p.scannedBy or "?", date("%Y-%m-%d %H:%M", p.scanTime or 0)))
        end
    elseif msg == "dumpspec" or msg == "specs" then
        -- Diagnostic: shows every talent-API variant's read for each of the
        -- player's 3 tabs. Tells us which call style actually returns real
        -- points-spent on this Ascension client.
        print("|cffffaa44EpogArmory|r talent-read diagnostics for self:")
        local gatg = GetActiveTalentGroup and GetActiveTalentGroup() or nil
        local gntg = GetNumTalentGroups and GetNumTalentGroups() or nil
        print(string.format("  GetActiveTalentGroup() = %s    GetNumTalentGroups() = %s",
            tostring(gatg), tostring(gntg)))
        for tab = 1, 3 do
            local name1, _, pts1 = GetTalentTabInfo(tab)
            local name2, _, pts2 = GetTalentTabInfo(tab, nil)
            local _,     _, pts3 = GetTalentTabInfo(tab, nil, nil, 1)
            local _,     _, pts4 = GetTalentTabInfo(tab, nil, nil, 2)
            local nt = (GetNumTalents and GetNumTalents(tab)) or 0
            local sumDefault = 0
            for i = 1, nt do
                local _, _, _, _, spent = GetTalentInfo(tab, i)
                sumDefault = sumDefault + (spent or 0)
            end
            local sumGroup1 = 0
            for i = 1, nt do
                local _, _, _, _, spent = GetTalentInfo(tab, i, nil, nil, 1)
                sumGroup1 = sumGroup1 + (spent or 0)
            end
            print(string.format("  Tab %d [%s]: GTTI(1-arg)=%s  GTTI(nil)=%s  GTTI(grp=1)=%s  GTTI(grp=2)=%s  GTI-sum(default)=%d  GTI-sum(grp=1)=%d  over %d talents",
                tab, tostring(name1 or "?"),
                tostring(pts1 or "nil"), tostring(pts2 or "nil"),
                tostring(pts3 or "nil"), tostring(pts4 or "nil"),
                sumDefault, sumGroup1, nt))
        end
        local s1, s2, s3 = ReadSpecPoints("player")
        print(string.format("  ReadSpecPoints(player) = %d / %d / %d → DominantTree = %d",
            s1, s2, s3, DominantTree({s1, s2, s3})))
    else
        ShowHelp()
    end
end
