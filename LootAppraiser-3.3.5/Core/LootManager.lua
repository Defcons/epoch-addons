-- Core/LootManager.lua
-- Loot detection on 3.3.5.
--
-- Single source of truth: CHAT_MSG_LOOT's "You receive loot:" patterns.
-- These fire only when an item actually lands in the player's bags, so we
-- trust them unconditionally — regardless of whether the item came from a
-- corpse loot, a Need/Greed roll win, master-loot assignment, an auto-
-- granted quest reward, or a crafted-item creation.
--
-- Patterns that fire on someone-else-receives-loot (LOOT_ITEM /
-- LOOT_ITEM_MULTIPLE) are deliberately NOT parsed — those are other
-- players' wins, never the local player's.
--
-- Earlier versions tried to gate LOOT_ITEM_SELF on a "loot window recently
-- open" flag (set by LOOT_OPENED, cleared after LOOT_CLOSED) to filter
-- out group-roll deliveries. That was wrong: greed-wins fire
-- LOOT_ITEM_SELF without ever opening a loot window, so the gate
-- silently dropped items the player actually received. Gate removed.
LA = LA or {}
LA.LootManager = {}
local LM = LA.LootManager

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
    if LA._verboseLoot then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r   ingest q=" .. tostring(quality) .. " keep=" .. tostring(keep))
    end
    if not keep then return end

    local entry = BuildEntry(link, count, source)

    -- Drop entries with no realisable value (vendor 0 + no AH/DE source).
    -- These are typically vendor-0 quest items, certain crafted reagents
    -- with no economy value, or anything the user has dumped into a
    -- "Junk" category that also vendors for nothing.
    local db = LA.db and LA.db.profile or LA_DEFAULTS
    if LA._verboseLoot then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r   entry.unit=" .. tostring(entry.unit) .. " src=" .. tostring(entry.src))
    end
    if (db.skipZeroValueRows ~= false) and (not entry.unit or entry.unit <= 0) then
        if LA._verboseLoot then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r   DROPPED: zero value")
        end
        return
    end

    -- Auto-start a session if the user enabled it
    if db.autoStart and not LA.Session.IsRunning() then
        LA.Session.Start()
    end
    if not LA.Session.IsRunning() then
        if LA._verboseLoot then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r   DROPPED: session not running")
        end
        return
    end

    if LA._verboseLoot then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r   ADDED to session")
    end

    LA.Session.AddLoot(entry)

    if LA.UI and LA.UI.OnLootAdded then
        LA.UI.OnLootAdded(entry)
    end
end

-- ----- CHAT_MSG_LOOT (sole loot signal) ----------------------------------
-- Catches: group loot ("Player receives loot: [Item] x2"), bonus rolls,
-- crafted-item drops on close-target loot. Solo loot has already been
-- counted via LOOT_OPENED, but the time-bucketed dedup key catches doubles.
local LOOT_PATTERNS  = nil
local CRAFT_PATTERNS = nil
-- After a "You create:" CHAT_MSG_LOOT line, suppress reconcile-debit until
-- this timestamp. Long enough to cover a typical craft sequence (BAG_UPDATE
-- bursts complete and the 0.3s reconcile timer fires) without bleeding
-- much into unrelated bag activity.
local craftingWindowUntil  = 0
local CRAFT_WINDOW_DURATION = 0.7
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
    -- All "you receive" / "you create" self patterns are trusted equally.
    -- LOOT_ITEM (other-player) patterns are intentionally absent — those
    -- never represent the local player's loot.
    --
    -- Ascension addendum: the server emits a custom CHAT_MSG_LOOT line
    -- "You won: [Item]" when the player wins a Need/Greed roll. Retail
    -- 3.3.5 normally fires LOOT_ITEM_SELF for those wins, but Ascension's
    -- modified server replaces it with the custom string. We add a
    -- literal Lua pattern (not a Blizzard global) to catch it.
    -- Pattern ordering matters: stack-aware (multi) variants must come
    -- BEFORE their single-item counterparts. Lua's regex engine returns
    -- the FIRST matching pattern, so a single "You won: (.+)$" placed
    -- first would gobble "[Item]x5" as the link and lose the count.
    -- Crafted items ("You create:" patterns) are intentionally NOT in
    -- LOOT_PATTERNS — they aren't real loot, they're transformations of
    -- mats the player already had. Adding the bandage to the session on
    -- top of the runecloth that produced it visually double-counts the
    -- value. We do still match those messages separately (CRAFT_PATTERNS
    -- below) so we can arm a short "craft window" that tells
    -- ReconcileBags to skip its debit pass; otherwise the consumed mats
    -- would be subtracted from session totals, making the displayed
    -- value drop whenever the player crafts.
    LOOT_PATTERNS = {
        -- "You receive loot: [item]xN." (LOOT_ITEM_SELF_MULTIPLE) — stacks
        { p = toLua(LOOT_ITEM_SELF_MULTIPLE),         multi = true },
        -- "You receive loot: [item]." (LOOT_ITEM_SELF) — single
        { p = toLua(LOOT_ITEM_SELF),                  multi = false },
        -- Ascension custom: "You won: [Item]xN" for stack wins (e.g.
        -- a stack of Runecloth via Greed). The greedy `.+` backtracks
        -- until `x(%d+)$` matches at the end, so the link itself can
        -- contain the letter 'x' inside its name without confusion —
        -- only a trailing "xN<eol>" is consumed as the count.
        { p = "^You won: (.+)x(%d+)$",                multi = true },
        -- Ascension custom: "You won: [Item]" for single-item wins
        { p = "^You won: (.+)$",                      multi = false },
    }
    -- Craft signals: matched solely to set craftingWindowUntil. Captured
    -- groups discarded.
    CRAFT_PATTERNS = {
        toLua(LOOT_ITEM_CREATED_SELF_MULTIPLE),
        toLua(LOOT_ITEM_CREATED_SELF),
    }
end

-- Returns: link, count (or nil if no pattern matched)
local function ParseChatLoot(msg)
    BuildPatterns()
    for _, pat in ipairs(LOOT_PATTERNS) do
        if pat.p then
            local a, b = msg:match(pat.p)
            if a then
                if pat.multi then
                    return a, tonumber(b) or 1
                else
                    return a, 1
                end
            end
        end
    end
end

-- Returns true if `msg` is a "You create:" line. Discards captures.
local function IsCraftMessage(msg)
    BuildPatterns()
    for _, p in ipairs(CRAFT_PATTERNS or {}) do
        if p and msg:match(p) then return true end
    end
    return false
end

local function HandleChatMsgLoot(msg)
    if not msg then return end

    -- "You create:" → arm craft window so ReconcileBags skips the debit
    -- pass for the imminent BAG_UPDATEs (consumed mats + new crafted item).
    -- We do NOT ingest the crafted item itself: it's a transformation, not
    -- new gain — counting it would visually double up alongside the mats
    -- the player just gathered.
    if IsCraftMessage(msg) then
        craftingWindowUntil = GetTime() + CRAFT_WINDOW_DURATION
        if LA._verboseLoot then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r craft msg: " .. tostring(msg) .. " (debit-skip window armed)")
        end
        return
    end

    local link, count = ParseChatLoot(msg)
    if LA._verboseLoot then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r CHAT_MSG_LOOT: " .. tostring(msg))
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r   matched? link=" .. tostring(link) .. " count=" .. tostring(count))
    end
    if not link then return end
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
-- CHAT_MSG_LOOT → the loot signal (see comment block at top of file)
-- BAG_UPDATE   → mark a reconciliation pass needed (debounced via OnUpdate)
-- UNIT_SPELLCAST_SUCCEEDED → also trigger a reconcile when the player casts
--                a destructive consumable spell (Disenchant, Mill, Prospect).
--                These spells consume an item and produce mats in a single
--                client tick; hooking the spell directly is the most
--                robust signal for triggering reconciliation, even if
--                BAG_UPDATE order is unusual.
local CONSUMING_SPELLS = {
    [13262] = true,  -- Disenchant
    [51005] = true,  -- Milling
    [31252] = true,  -- Prospecting
}
local frame = CreateFrame("Frame", "LA_LootEventFrame")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:SetScript("OnEvent", function(self, event, msg, _, _, _, spellID)
    if event == "CHAT_MSG_LOOT" then
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

    -- Within a craft window, skip the debit pass entirely. The recent
    -- BAG_UPDATEs were the spell consuming mats and producing the new
    -- item; we don't want session totals to drop just because the
    -- player crafted from their gathered loot. The pendingReconcile
    -- flag is reset above so any *future* (post-window) BAG_UPDATE
    -- still re-arms the timer cleanly.
    if GetTime() < craftingWindowUntil then
        if LA._verboseLoot then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA verbose]|r reconcile: SKIPPED (craft window)")
        end
        return
    end

    if LA.Session and LA.Session.IsRunning() then
        local lossChanged    = LA.Session.ReconcileBags()
        -- Re-price recently-ingested vendor rows. ArkInventory has
        -- (probably) finished its bag scan by now and rule-classified
        -- categories are visible — so a row that priced as "default"
        -- → vendor on first ingest can be promoted to its proper
        -- AH / DE / vendor source here.
        local repriced = LA.Session.RepriceRecentVendor and LA.Session.RepriceRecentVendor()
        if (lossChanged or repriced) and LA.UI and LA.UI.RefreshUIs then
            LA.UI.RefreshUIs()
        end
    end
end)
