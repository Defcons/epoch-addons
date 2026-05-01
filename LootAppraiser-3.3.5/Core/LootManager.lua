-- Core/LootManager.lua
-- Loot detection on 3.3.5.
--
-- We use the LOOT_OPENED + GetLootSlotInfo / GetLootSlotLink path rather
-- than CHAT_MSG_LOOT alone. CHAT_MSG_LOOT misses items that disappear from
-- the loot frame after autoloot, and it doesn't fire for currency. The
-- LOOT_OPENED snapshot also gives us reliable item counts and a single
-- iteration site (no per-line regex parsing).
--
-- We also subscribe to CHAT_MSG_LOOT as a backup and de-dupe via a small
-- "recently seen" buffer keyed by (link, count, time-floor).

LA = LA or {}
LA.LootManager = {}
local LM = LA.LootManager

local recent = {}  -- { ["link|count|tslot"] = expireTime }
local DEDUP_WINDOW = 1.5  -- seconds

local function MarkSeen(key)
    recent[key] = GetTime() + DEDUP_WINDOW
end

local function AlreadySeen(key)
    local exp = recent[key]
    if not exp then return false end
    if exp < GetTime() then
        recent[key] = nil
        return false
    end
    return true
end

local function PruneRecent()
    local now = GetTime()
    for k, exp in pairs(recent) do
        if exp < now then recent[k] = nil end
    end
end

-- Returns whether the loot row should be kept (quality & soulbound filter)
-- and whether it should appear in the visible list (vs. counted in totals).
local function ShouldRecord(link, quality)
    local db = LA.db and LA.db.profile or LA_DEFAULTS

    -- Quality threshold for value totals. Below the floor we ignore entirely.
    if (quality or 0) < (db.minQuality or LA_DEFAULTS.minQuality) then
        return false, false
    end

    -- ignoreSoulbound: drop BoP items entirely
    if db.ignoreSoulbound and LA.Pricing.IsBindOnPickup(link) then
        return false, false
    end

    local inList = (quality or 0) >= (db.minQualityForList or LA_DEFAULTS.minQualityForList)
    return true, inList
end

local function PriceItem(link)
    local db = LA.db and LA.db.profile or LA_DEFAULTS
    local copper, src, isBoP = LA.Pricing.GetItemValue(link, {
        useDisenchant = db.useDisenchant,
    })
    return copper or 0, src, isBoP
end

-- Build a session row entry from a single looted stack.
local function BuildEntry(link, count, source)
    local quality = select(3, GetItemInfo(link)) or 0
    local copper, src, isBoP = PriceItem(link)
    local total = copper * (count or 1)
    return {
        link    = link,
        count   = count or 1,
        quality = quality,
        unit    = copper,        -- per-item value
        value   = total,         -- stack value
        src     = src,           -- price source tag
        isBoP   = isBoP,
        source  = source or LA_CONST.SOURCE_SOLO,
        time    = GetTime(),
    }
end

-- Public: ingest one looted stack. De-dupes against the recent-seen buffer.
function LM.IngestLoot(link, count, source)
    if not link then return end
    PruneRecent()
    local key = link .. "|" .. tostring(count) .. "|" .. tostring(math.floor(GetTime() * 4))
    if AlreadySeen(key) then return end
    MarkSeen(key)

    local quality = select(3, GetItemInfo(link)) or 0
    local keep, _ = ShouldRecord(link, quality)
    if not keep then return end

    -- Auto-start a session if the user enabled it
    local db = LA.db and LA.db.profile or LA_DEFAULTS
    if db.autoStart and not LA.Session.IsRunning() then
        LA.Session.Start()
    end
    if not LA.Session.IsRunning() then return end

    local entry = BuildEntry(link, count, source)
    LA.Session.AddLoot(entry)

    -- Notify the UI for incremental refresh; the window debounces internally.
    if LA.UI and LA.UI.OnLootAdded then
        LA.UI.OnLootAdded(entry)
    end
end

-- ----- LOOT_OPENED scan --------------------------------------------------
-- Walks every loot slot, captures item link + count, then ingests. Plays
-- nicely with both manual loot and autoloot — the loot frame is created
-- and torn down identically in both modes; LOOT_OPENED fires once per loot.
local function HandleLootOpened()
    local n = GetNumLootItems() or 0
    for slot = 1, n do
        local _, _, qty, _, locked, _, _, _, isQuestItem = GetLootSlotInfo(slot)
        local link = GetLootSlotLink(slot)
        if link and qty and qty > 0 and not locked then
            LM.IngestLoot(link, qty, LA_CONST.SOURCE_SOLO)
        end
    end
end

-- ----- CHAT_MSG_LOOT backup ----------------------------------------------
-- Catches: group loot ("Player receives loot: [Item] x2"), bonus rolls,
-- crafted-item drops on close-target loot. Solo loot has already been
-- counted via LOOT_OPENED, but the time-bucketed dedup key catches doubles.
local LOOT_PATTERNS = nil
local function BuildPatterns()
    if LOOT_PATTERNS then return end
    -- The Blizzard global pattern strings have %s placeholders. Convert them
    -- to Lua captures by substituting (.+) for %s and %%s placeholder forms.
    local function toLua(p)
        if not p then return nil end
        p = p:gsub("%(", "%%("):gsub("%)", "%%)")
        p = p:gsub("%%s", "(.+)")
        p = p:gsub("%%d", "(%%d+)")
        return "^" .. p .. "$"
    end
    -- Strict "items I personally looted from corpses" mode. LOOT_OPENED
    -- already captures every corpse the player clicks (autoloot or manual),
    -- so we deliberately ignore everything from CHAT_MSG_LOOT *except*
    -- self-create — crafted items don't open a loot window so they have
    -- no LOOT_OPENED signal.
    --
    -- Explicitly NOT parsed:
    --   * LOOT_ITEM / _MULTIPLE  — other players' group-loot wins
    --   * LOOT_ITEM_SELF / _MULTIPLE — the player's own group/Need/Greed
    --     wins. Those are deliveries from a roll, not items the player
    --     looted off a corpse.
    LOOT_PATTERNS = {
        -- "You create: [item]." (LOOT_ITEM_CREATED_SELF)
        { p = toLua(LOOT_ITEM_CREATED_SELF),        self = true,  multi = false },
        -- "You create: [item]xN." (LOOT_ITEM_CREATED_SELF_MULTIPLE)
        { p = toLua(LOOT_ITEM_CREATED_SELF_MULTIPLE), self = true, multi = true,  countLast = true },
    }
end

local function ParseChatLoot(msg)
    BuildPatterns()
    for _, pat in ipairs(LOOT_PATTERNS) do
        if pat.p then
            local a, b, c = msg:match(pat.p)
            if a then
                local link, count, source
                if pat.self then
                    if pat.multi then
                        link, count = a, tonumber(b) or 1
                    else
                        link = a
                        count = 1
                    end
                    source = LA_CONST.SOURCE_SOLO
                else
                    -- group loot: a=playerName, b=link, c=count(if multi)
                    if pat.multi then
                        link, count = b, tonumber(c) or 1
                    else
                        link, count = b, 1
                    end
                    source = LA_CONST.SOURCE_GROUP
                end
                return link, count, source
            end
        end
    end
end

local function HandleChatMsgLoot(msg)
    if not msg then return end
    local link, count, source = ParseChatLoot(msg)
    if not link then return end
    LM.IngestLoot(link, count, source)
end

-- ----- event hookup ------------------------------------------------------
local frame = CreateFrame("Frame", "LA_LootEventFrame")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:SetScript("OnEvent", function(self, event, msg)
    if event == "LOOT_OPENED" then
        HandleLootOpened()
    elseif event == "CHAT_MSG_LOOT" then
        HandleChatMsgLoot(msg)
    end
end)
