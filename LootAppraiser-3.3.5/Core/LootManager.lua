-- Core/LootManager.lua
-- Loot detection on 3.3.5.
--
-- We use CHAT_MSG_LOOT's LOOT_ITEM_SELF as the *single* source of truth for
-- "an item just landed in my bags". LOOT_OPENED is unreliable for tracking
-- because it fires whenever a loot window appears — including when the
-- player merely peeks at a mob and closes without looting, or repeatedly
-- opens the same corpse. Items in the frame would get counted whether
-- they were actually taken or not.
--
-- LOOT_ITEM_SELF alone over-counts in the opposite direction though: it
-- also fires for Need/Greed roll deliveries, which the user explicitly
-- doesn't want tracked. So we GATE LOOT_ITEM_SELF on a "loot window
-- recently open" flag set by LOOT_OPENED and cleared shortly after
-- LOOT_CLOSED. Net result:
--
--   loot window opened → all CHAT_MSG_LOOT self-loot lines counted
--   roll-delivered     → no loot window → flag never set → ignored
--   crafting           → no loot window, but LOOT_ITEM_CREATED_SELF
--                        is counted unconditionally (no loot frame
--                        exists for crafting)
LA = LA or {}
LA.LootManager = {}
local LM = LA.LootManager

local lootWindowOpenUntil = 0  -- GetTime() until which we trust self-loot lines
local LOOT_CLOSE_GRACE    = 0.5  -- seconds after LOOT_CLOSED to still accept trailing messages

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
        useDisenchant   = db.useDisenchant,
        valueCategory   = db.arkInvValueCategory,
        deCategory      = db.arkInvDECategory,
        vendorCategory  = db.arkInvVendorCategory,
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

-- Public: ingest one looted stack. With our single-event-source design
-- (CHAT_MSG_LOOT only) there's no need for a dedup buffer.
function LM.IngestLoot(link, count, source)
    if not link then return end

    local quality = select(3, GetItemInfo(link)) or 0
    local keep, _ = ShouldRecord(link, quality)
    if not keep then return end

    local entry = BuildEntry(link, count, source)

    -- Drop entries with no realisable value (vendor 0 + no AH/DE source).
    -- These are typically vendor-0 quest items, certain crafted reagents
    -- with no economy value, or anything the user has dumped into a
    -- "Junk" category that also vendors for nothing.
    local db = LA.db and LA.db.profile or LA_DEFAULTS
    if (db.skipZeroValueRows ~= false) and (not entry.unit or entry.unit <= 0) then
        return
    end

    -- Auto-start a session if the user enabled it
    if db.autoStart and not LA.Session.IsRunning() then
        LA.Session.Start()
    end
    if not LA.Session.IsRunning() then return end

    LA.Session.AddLoot(entry)

    if LA.UI and LA.UI.OnLootAdded then
        LA.UI.OnLootAdded(entry)
    end
end

-- ----- CHAT_MSG_LOOT (sole loot signal) ----------------------------------
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
    -- Two pattern groups, with different gating behaviour:
    --   * needsWindow=true  — only ingested when a loot window was recently
    --                        open. Distinguishes corpse-loot from
    --                        Need/Greed-roll deliveries.
    --   * needsWindow=false — always ingested. Crafting fires
    --                        LOOT_ITEM_CREATED_SELF without ever opening
    --                        a loot frame, so we can't gate it.
    --
    -- Explicitly NOT parsed:
    --   * LOOT_ITEM / _MULTIPLE — other players' loot. Never tracked.
    LOOT_PATTERNS = {
        -- "You receive loot: [item]." (LOOT_ITEM_SELF)
        { p = toLua(LOOT_ITEM_SELF),                  self = true, multi = false, needsWindow = true },
        -- "You receive loot: [item]xN." (LOOT_ITEM_SELF_MULTIPLE)
        { p = toLua(LOOT_ITEM_SELF_MULTIPLE),         self = true, multi = true,  countLast = true, needsWindow = true },
        -- "You create: [item]." (LOOT_ITEM_CREATED_SELF)
        { p = toLua(LOOT_ITEM_CREATED_SELF),          self = true, multi = false, needsWindow = false },
        -- "You create: [item]xN." (LOOT_ITEM_CREATED_SELF_MULTIPLE)
        { p = toLua(LOOT_ITEM_CREATED_SELF_MULTIPLE), self = true, multi = true,  countLast = true, needsWindow = false },
    }
end

-- Returns: link, count, needsWindow (or nil if no pattern matched)
local function ParseChatLoot(msg)
    BuildPatterns()
    for _, pat in ipairs(LOOT_PATTERNS) do
        if pat.p then
            local a, b = msg:match(pat.p)
            if a then
                local link, count
                if pat.multi then
                    link, count = a, tonumber(b) or 1
                else
                    link, count = a, 1
                end
                return link, count, pat.needsWindow
            end
        end
    end
end

local function HandleChatMsgLoot(msg)
    if not msg then return end
    local link, count, needsWindow = ParseChatLoot(msg)
    if not link then return end
    -- Gate corpse-loot lines on a recent loot window. Crafted-item lines
    -- bypass the gate (no loot window ever opens for crafting).
    if needsWindow and GetTime() > lootWindowOpenUntil then return end
    LM.IngestLoot(link, count, LA_CONST.SOURCE_SOLO)
end

-- ----- BAG_UPDATE → debounced reconciliation -----------------------------
-- BAG_UPDATE fires repeatedly during a single inventory change (often once
-- per affected slot). Coalesce all of them into a single reconciliation
-- pass ~0.3s after the burst settles. The pass scans bags, debits any
-- loss against state.bagOwn / lootRows, and asks the UI to re-render.
local BAG_DEBOUNCE = 0.3
local pendingReconcile = false
local reconcileAccum = 0

-- ----- event hookup ------------------------------------------------------
-- LOOT_OPENED  → arm the gate (math.huge = trust messages while window is open)
-- LOOT_CLOSED  → disarm with a small grace so trailing CHAT_MSG_LOOT lines
--                that the server may emit slightly after the close packet
--                still get counted
-- CHAT_MSG_LOOT → the actual loot signal; gated via needsWindow
-- BAG_UPDATE   → mark a reconciliation pass needed (debounced via OnUpdate)
-- UNIT_SPELLCAST_SUCCEEDED → also trigger a reconcile when the player casts
--                a destructive consumable spell (Disenchant, Mill, Prospect,
--                Smelt). Belt-and-suspenders against any path where the
--                BAG_UPDATE order can leave an item undebited while the
--                produced mats are already ingested — the user-visible
--                symptom would be the source item still hanging in the
--                row list while the mats also appear.
local CONSUMING_SPELLS = {
    [13262] = true,  -- Disenchant
    [51005] = true,  -- Milling
    [31252] = true,  -- Prospecting
}
local frame = CreateFrame("Frame", "LA_LootEventFrame")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:SetScript("OnEvent", function(self, event, msg, _, _, _, spellID)
    if event == "LOOT_OPENED" then
        lootWindowOpenUntil = math.huge
    elseif event == "LOOT_CLOSED" then
        lootWindowOpenUntil = GetTime() + LOOT_CLOSE_GRACE
    elseif event == "CHAT_MSG_LOOT" then
        HandleChatMsgLoot(msg)
    elseif event == "BAG_UPDATE" then
        pendingReconcile = true
        reconcileAccum   = 0
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg1 (here `msg`) is the unit; spellID is the 4th vararg in 3.3.5.
        if msg == "player" and spellID and CONSUMING_SPELLS[spellID] then
            pendingReconcile = true
            reconcileAccum   = 0
        end
    end
end)
frame:SetScript("OnUpdate", function(self, elapsed)
    if not pendingReconcile then return end
    reconcileAccum = reconcileAccum + elapsed
    if reconcileAccum < BAG_DEBOUNCE then return end
    pendingReconcile = false
    reconcileAccum   = 0
    if LA.Session and LA.Session.IsRunning() then
        local changed = LA.Session.ReconcileBags()
        if changed and LA.UI and LA.UI.RefreshUIs then
            LA.UI.RefreshUIs()
        end
    end
end)
