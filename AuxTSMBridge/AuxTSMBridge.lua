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

-- Claude: Ascension uses a single unified cross-faction AH. Aux still stores
-- history under the scanning character's faction key, so we merge every
-- faction scope on this realm when reading. (Old single-faction helper
-- GetAuxFactionKey removed — all callers moved to the multi-faction path.)
local function GetAuxFactionTablesForRealm()
    local realm  = GetCVar("realmName") or ""
    local prefix = realm .. "|"
    local out    = {}
    if aux and aux.faction then
        for key, tbl in pairs(aux.faction) do
            if type(key) == "string" and type(tbl) == "table"
                and key:sub(1, #prefix) == prefix then
                tinsert(out, tbl)
            end
        end
    end
    return out
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

-- Claude: read decay from aux config so sync matches aux's own % Hist. Value column
local function GetDecay()
    if auxHistory and auxHistory.get_decay then -- Claude: prefer aux's live config
        local ok, v = pcall(auxHistory.get_decay)
        if ok and type(v) == "number" then return v end
    end
    return (aux and aux.account and aux.account.history_decay) or 0.75 -- Claude: fallback to aux default
end

-- Replicates aux's weighted_median calculation.
-- data_points[1] is most recent (aux inserts at index 1 via tinsert(t, 1, ...))
local function WeightedMedian(data_points)
    if not data_points or #data_points == 0 then return nil end

    local ref_time     = data_points[1].time
    local weighted     = {}
    local total_weight = 0
    local decay        = GetDecay() -- Claude: use aux's configured decay instead of hardcoded 0.99

    for _, dp in ipairs(data_points) do
        local days_ago = floor((ref_time - dp.time) / 86400 + 0.5)
        local weight   = decay ^ days_ago -- Claude: was hardcoded (0.99)
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
-- Claude: merge history from every faction table on this realm (unified AH).
local function GetAuxPricesDirect(item_key)
    local merged_points = {} -- Claude: union of data points across factions
    local best_daily    = nil -- Claude: min(daily_min) across factions

    for _, auxFaction in ipairs(GetAuxFactionTablesForRealm()) do
        local historyData = auxFaction["history"]
        local str         = historyData and historyData[item_key]
        if str then
            local daily_min, data_points = ParseAuxRecord(str)
            if type(daily_min) == "number"
                and (not best_daily or daily_min < best_daily) then
                best_daily = daily_min
            end
            if data_points then
                for _, dp in ipairs(data_points) do
                    tinsert(merged_points, dp)
                end
            end
        end
    end

    if #merged_points == 0 and not best_daily then
        return nil, nil
    end

    -- Claude: WeightedMedian uses data_points[1].time as its reference point,
    -- so sort the merged list newest-first to match aux's own insertion order.
    if #merged_points > 1 then
        table.sort(merged_points, function(a, b) return a.time > b.time end)
    end

    local market_value
    if #merged_points > 0 then
        market_value = WeightedMedian(merged_points)
    else
        market_value = best_daily
    end

    return market_value, best_daily
end

-- -------------------------------------------------------------------------
-- AUX price lookups for TSM price source callbacks (one item at a time).
-- Claude: aux's own value()/market_value() only read the current faction,
-- so we skip them and use the cross-faction merged direct parser for both
-- live TSM tooltip callbacks and the bulk sync. auxHistory is still used
-- via GetDecay() for the decay config.
-- -------------------------------------------------------------------------
local function GetAuxValue(link)
    local item_key = GetAuxItemKey(link)
    if not item_key then return nil end
    local mv = GetAuxPricesDirect(item_key) -- Claude: cross-faction merged
    return (type(mv) == "number" and mv > 0) and mv or nil
end

local function GetAuxMinBuyout(link)
    local item_key = GetAuxItemKey(link)
    if not item_key then return nil end
    local _, mb = GetAuxPricesDirect(item_key) -- Claude: cross-faction merged
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

    -- Claude: collect item_keys across every faction table on this realm
    -- (Ascension's unified AH means Horde/Alliance scans cover the same market).
    local factionTables = GetAuxFactionTablesForRealm()
    if #factionTables == 0 then
        Print("No aux price history found yet. Scan the AH with aux first.")
        return
    end

    local allKeys = {} -- Claude: dedup union of item_keys across factions
    for _, auxFaction in ipairs(factionTables) do
        local historyData = auxFaction["history"]
        if historyData then
            for item_key in pairs(historyData) do
                allKeys[item_key] = true
            end
        end
    end

    local now     = time()
    local synced  = 0
    local skipped = 0

    for item_key in pairs(allKeys) do -- Claude: iterate merged key set
        local itemID = tonumber(item_key:match("^(%d+):"))
        if itemID then
            -- Claude: GetAuxPricesDirect already merges across factions
            local ok, mv, mb = pcall(GetAuxPricesDirect, item_key)
            local market_value = ok and mv or nil
            local daily_min    = ok and mb or nil

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
        -- Claude: report per-faction counts plus merged unique-item total
        local realm  = GetCVar("realmName") or ""
        local prefix = realm .. "|"
        local merged = {}
        if aux and aux.faction then
            for key, tbl in pairs(aux.faction) do
                if type(key) == "string" and type(tbl) == "table"
                    and key:sub(1, #prefix) == prefix then
                    local historyData = tbl["history"]
                    local count = 0
                    if historyData then
                        for item_key in pairs(historyData) do
                            merged[item_key] = true
                            count = count + 1
                        end
                    end
                    Print(format("  [%s] %d items", key, count))
                end
            end
        end
        local mergedCount = 0
        for _ in pairs(merged) do mergedCount = mergedCount + 1 end
        Print(format("Cross-faction merged: %d unique items on %s", mergedCount, realm))
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
