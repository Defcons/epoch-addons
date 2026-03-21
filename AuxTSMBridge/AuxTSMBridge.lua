-- AuxTSMBridge
-- Two-way price bridge between aux and TradeSkillMaster.
--
-- What this does:
--   1. Registers AuxMarket / AuxMinBuyout as TSM price sources usable in
--      any TSM formula (Auctioning, Shopping, Crafting, etc.)
--
--   2. SyncAuxToTSM() – pushes all aux scanned prices into TSM's AuctionDB
--      so that TSM tooltips show fresh values instead of "67 days ago" and
--      TSM's DBMarket / DBMinBuyout reflect what aux has scanned.
--      Runs automatically when you close the Auction House.
--
-- Slash commands:
--   /axtsm sync   – manual sync
--   /axtsm status – show item counts and last scan time
--
-- No existing addon files are modified.

-- -------------------------------------------------------------------------
-- Upvalues
-- -------------------------------------------------------------------------
local ADDON_NAME = "AuxTSMBridge"
local auxHistory = nil   -- aux.core.history public interface (for per-item TSM callbacks)
local adbModule  = nil   -- TSM_AuctionDB AceAddon object

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxTSMBridge]|r " .. tostring(msg))
end

local function GetItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function GetAuxItemKey(link)
    if not link then return nil end
    -- item link format: |Hitem:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID|h
    local itemID, suffixID = link:match("item:(%d+):%d+:%d+:%d+:%d+:%d+:(%-?%d+):?")
    if not itemID then return nil end
    return itemID .. ":" .. (suffixID or "0")
end

local function GetAuxFactionKey()
    local realm   = GetCVar("realmName")       or ""
    local faction = UnitFactionGroup("player") or ""
    return realm .. "|" .. faction
end

-- -------------------------------------------------------------------------
-- Raw aux history string parser — avoids aux's temp-table allocator.
--
-- Schema stored in aux.faction[key]["history"][item_key]:
--   "next_push#daily_min_buyout#val@time;val@time;..."
--   (daily_min_buyout may be empty string when no scan happened today)
--   (data_points section may be empty)
--
-- Returns: daily_min_buyout (number|nil), data_points (table of {value,time})
-- -------------------------------------------------------------------------
local function ParseAuxRecord(str)
    if not str or str == "" then return nil, nil end

    -- Split on the first two '#' delimiters only
    local s1, s2, s3 = str:match("^([^#]*)#([^#]*)#?(.*)")
    local daily_min = tonumber(s2)   -- may be nil if today has no scan

    local data_points = {}
    if s3 and s3 ~= "" then
        -- Each data point is "value@time", separated by ";"
        for entry in (s3 .. ";"):gmatch("([^;]+);") do
            local val_s, time_s = entry:match("^([^@]+)@([^@]+)$")
            local val  = tonumber(val_s)
            local t    = tonumber(time_s)
            if val and t then
                tinsert(data_points, { value = val, time = t })
            end
        end
    end

    return daily_min, data_points
end

-- Replicates aux's weighted_median calculation.
-- data_points[1] is most recent (aux inserts at index 1 via tinsert(t, 1, ...))
local function WeightedMedian(data_points)
    if not data_points or #data_points == 0 then return nil end

    local ref_time     = data_points[1].time
    local weighted     = {}
    local total_weight = 0

    for _, dp in ipairs(data_points) do
        local days_ago = floor((ref_time - dp.time) / 86400 + 0.5)
        local weight   = (0.99) ^ days_ago
        total_weight   = total_weight + weight
        tinsert(weighted, { value = dp.value, weight = weight })
    end

    if total_weight == 0 then return nil end

    table.sort(weighted, function(a, b) return a.value < b.value end)

    local cumulative = 0
    for _, w in ipairs(weighted) do
        cumulative = cumulative + w.weight / total_weight
        if cumulative >= 0.5 then
            return w.value
        end
    end
    return weighted[#weighted] and weighted[#weighted].value
end

-- High-level: return market value and min-buyout for an item_key using only
-- raw string parsing — no calls into aux's temp-table system.
local function GetAuxPricesDirect(item_key)
    local factionKey  = GetAuxFactionKey()
    local auxFaction  = aux and aux.faction and aux.faction[factionKey]
    local historyData = auxFaction and auxFaction["history"]
    if not historyData then return nil, nil end

    local str = historyData[item_key]
    if not str then return nil, nil end

    local daily_min, data_points = ParseAuxRecord(str)

    -- market value = weighted median of historical points (same as aux's value())
    -- fall back to daily_min if no history yet
    local market_value
    if #data_points > 0 then
        market_value = WeightedMedian(data_points)
    else
        market_value = daily_min
    end

    return market_value, daily_min
end

-- -------------------------------------------------------------------------
-- AUX price lookups for TSM price source callbacks.
-- These are called one item at a time by TSM — safe to use auxHistory here.
-- If auxHistory is unavailable, fall back to direct parsing.
-- -------------------------------------------------------------------------
local function GetAuxValue(link)
    local item_key = GetAuxItemKey(link)
    if not item_key then return nil end

    if auxHistory then
        local ok, v = pcall(auxHistory.value, item_key)
        if ok and type(v) == "number" and v > 0 then return v end
    end

    -- fallback: direct parse
    local mv = GetAuxPricesDirect(item_key)
    return (type(mv) == "number" and mv > 0) and mv or nil
end

local function GetAuxMinBuyout(link)
    local item_key = GetAuxItemKey(link)
    if not item_key then return nil end

    if auxHistory then
        local ok, v = pcall(auxHistory.market_value, item_key)
        if ok and type(v) == "number" and v > 0 then return v end
    end

    -- fallback: direct parse
    local _, mb = GetAuxPricesDirect(item_key)
    return (type(mb) == "number" and mb > 0) and mb or nil
end

-- -------------------------------------------------------------------------
-- SYNC: push all aux history into TSM AuctionDB using direct string parsing.
-- Does NOT call auxHistory.value() / market_value() in a loop — those use
-- aux's temp-table allocator which crashes when called thousands of times
-- synchronously from outside aux's own execution context.
-- -------------------------------------------------------------------------
local function SyncAuxToTSM()
    if not adbModule or not adbModule.data then
        Print("TSM AuctionDB not available.")
        return
    end

    local factionKey  = GetAuxFactionKey()
    local auxFaction  = aux and aux.faction and aux.faction[factionKey]
    local historyData = auxFaction and auxFaction["history"]

    if not historyData then
        Print("No aux price history found yet. Scan the AH with aux first.")
        return
    end

    local now     = time()
    local synced  = 0
    local skipped = 0

    for item_key, raw_str in pairs(historyData) do
        local itemID = tonumber(item_key:match("^(%d+):"))
        if itemID and raw_str and raw_str ~= "" then
            local market_value, daily_min = nil, nil
            local ok, a, b = pcall(ParseAuxRecord, raw_str)
            if ok then
                local dp_min = a      -- daily_min_buyout
                local dp_pts = b      -- data_points table
                if dp_pts and #dp_pts > 0 then
                    local okm, mv = pcall(WeightedMedian, dp_pts)
                    market_value = okm and mv or dp_min
                else
                    market_value = dp_min
                end
                daily_min = dp_min
            end

            if market_value or daily_min then
                -- Decode any existing TSM entry first (no-op if not yet encoded)
                adbModule:DecodeItemData(itemID)

                if not adbModule.data[itemID] then
                    adbModule.data[itemID] = { scans = {}, lastScan = 0, quantity = 0 }
                end

                local d = adbModule.data[itemID]
                if market_value then d.marketValue = market_value end
                if daily_min    then d.minBuyout   = daily_min    end
                d.lastScan = now
                if type(d.scans) ~= "table" then d.scans = {} end
                -- TSM's encode(0) stores "~" which decodes back to nil, crashing
                -- the tooltip's format("%d auctions", quantity). Keep existing
                -- quantity if valid, otherwise default to 1.
                d.quantity = (d.quantity and d.quantity > 0) and d.quantity or 1

                adbModule:EncodeItemData(itemID)
                synced = synced + 1
            else
                skipped = skipped + 1
            end
        end
    end

    -- Mark TSM as having a fresh complete scan
    if synced > 0 and adbModule.db and adbModule.db.factionrealm then
        adbModule.db.factionrealm.lastCompleteScan = now
    end

    Print(format("Synced %d items from aux into TSM AuctionDB.%s",
        synced,
        skipped > 0 and (" (%d had no price data)"):format(skipped) or ""))
end

-- -------------------------------------------------------------------------
-- Register with TSM as a module providing AuxMarket / AuxMinBuyout
-- -------------------------------------------------------------------------
local function RegisterWithTSM()
    if not LibStub or not TSMAPI then return false end
    local AceAddon = LibStub("AceAddon-3.0", true)
    if not AceAddon then return false end

    local Bridge = AceAddon:NewAddon(ADDON_NAME)
    Bridge.priceSources = {
        {
            key      = "AuxMarket",
            label    = "Aux - Market Value (weighted median)",
            callback = function(itemLink) return GetAuxValue(itemLink) end,
        },
        {
            key      = "AuxMinBuyout",
            label    = "Aux - Min Buyout (today)",
            callback = function(itemLink) return GetAuxMinBuyout(itemLink) end,
        },
    }

    local ok, err = pcall(TSMAPI.NewModule, TSMAPI, Bridge)
    if not ok then
        Print("Failed to register TSM price sources: " .. tostring(err))
        return false
    end

    return true
end

-- -------------------------------------------------------------------------
-- Slash commands
-- -------------------------------------------------------------------------
SLASH_AUXTSMBRIDGE1 = "/axtsm"
SLASH_AUXTSMBRIDGE2 = "/auxtsmbridge"
SlashCmdList["AUXTSMBRIDGE"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "sync" then
        SyncAuxToTSM()
    elseif msg == "status" then
        local factionKey  = GetAuxFactionKey()
        local auxFaction  = aux and aux.faction and aux.faction[factionKey]
        local historyData = auxFaction and auxFaction["history"]
        local count = 0
        if historyData then
            for _ in pairs(historyData) do count = count + 1 end
        end
        Print("aux has price history for " .. count .. " items  [" .. factionKey .. "]")
        if adbModule and adbModule.db and adbModule.db.factionrealm then
            local last = adbModule.db.factionrealm.lastCompleteScan or 0
            if last > 0 then
                Print("TSM AuctionDB last sync: " .. SecondsToTime(time() - last) .. " ago")
            else
                Print("TSM AuctionDB: no sync recorded yet")
            end
        end
    else
        Print("Commands:  /axtsm sync  |  /axtsm status")
    end
end

-- -------------------------------------------------------------------------
-- Initialization
-- -------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        -- Initialize SavedVariable (populated by WoW before PLAYER_LOGIN)
        AuxTSMBridgeDB = AuxTSMBridgeDB or {}
        AuxTSMBridgeDB.lastSyncTime = AuxTSMBridgeDB.lastSyncTime or 0

        -- Grab aux history interface for single-item TSM callbacks
        if type(require) == "function" then
            local ok, hist = pcall(require, "aux.core.history")
            if ok and hist then
                auxHistory = hist
            end
            -- Not fatal if unavailable; GetAuxValue/GetAuxMinBuyout fall back to direct parsing
        end

        -- Grab TSM_AuctionDB module for direct data writes
        if LibStub then
            local AceAddon = LibStub("AceAddon-3.0", true)
            if AceAddon then
                local ok2, mod = pcall(AceAddon.GetAddon, AceAddon, "TSM_AuctionDB", true)
                if ok2 and mod then
                    adbModule = mod
                else
                    Print("TSM_AuctionDB not found. Is TradeSkillMaster_AuctionDB loaded?")
                end
            end
        end

        RegisterWithTSM()

    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- Only sync if it has been at least 12 real hours since the last sync.
        -- AuxTSMBridgeDB persists across reloads and logins so the timer
        -- survives session boundaries.
        local now = time()
        if AuxTSMBridgeDB and now - (AuxTSMBridgeDB.lastSyncTime or 0) >= 12 * 60 * 60 then
            AuxTSMBridgeDB.lastSyncTime = now
            SyncAuxToTSM()
        end
    end
end)
