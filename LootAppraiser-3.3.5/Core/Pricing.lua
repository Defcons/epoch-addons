-- Core/Pricing.lua
-- Item pricing chain for LootAppraiser-3.3.5.
--
--   1. Aux merged price across factions (the most accurate source on Ascension's
--      unified AH; mirrors AuxTSMBridge's logic without depending on the bridge
--      having run a TSM sync yet).
--   2. TSM2 DBMarket via TSMAPI:GetItemValue / TSM_AuctionDB.
--   3. Disenchant expected value (computed against TSM2's enchanting yield
--      tables priced through the Aux/TSM lookups above) — only used for BoP
--      uncommons or rares when the user has DE on.
--   4. Vendor sell price as the universal fallback.
--
-- Public API:
--   LA.Pricing.GetItemValue(itemLink, opts)   -> copper, sourceTag, isBoP
--   LA.Pricing.GetVendorPrice(itemLink)       -> copper
--   LA.Pricing.GetDisenchantValue(itemLink)   -> copper or nil
--   LA.Pricing.IsBindOnPickup(itemLink)       -> bool

LA = LA or {}
LA.Pricing = {}
local Pricing = LA.Pricing

-- ----- internal caches (session-local) -----------------------------------
local priceCache    = {}  -- [itemString] = copper
local deCache       = {}  -- [itemID]     = copper (DE expected value)
local bindCache     = {}  -- [itemID]     = bool   (true = BoP)
local vendorCache   = {}  -- [itemID]     = copper (sell)
local scanTooltip          -- lazy hidden tooltip for BoP detection

-- ----- helpers ------------------------------------------------------------

local function ItemKeyFromLink(link)
    if not link then return nil end
    local itemID, suffixID = link:match("item:(%d+):%d+:%d+:%d+:%d+:%d+:(%-?%d+):?")
    if not itemID then return nil end
    return itemID .. ":" .. (suffixID or "0")
end

local function ItemIDFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- ----- aux merged price (cross-faction) ----------------------------------
local function ParseAuxRecord(str)
    if not str or str == "" then return nil, {} end
    local _, daily, points = str:match("^([^#]*)#([^#]*)#?(.*)")
    local pts = {}
    if points and points ~= "" then
        for entry in (points .. ";"):gmatch("([^;]+);") do
            local v, t = entry:match("^([^@]+)@(.+)$")
            v, t = tonumber(v), tonumber(t)
            if v and t then table.insert(pts, { value = v, time = t }) end
        end
    end
    return tonumber(daily), pts
end

local function WeightedMedian(points)
    if not points or #points == 0 then return nil end
    local refTime = points[1].time
    local decay   = (aux and aux.account and tonumber(aux.account.history_decay)) or 0.75
    local total   = 0
    local list    = {}
    for _, dp in ipairs(points) do
        local days = math.floor((refTime - dp.time) / 86400 + 0.5)
        local w    = decay ^ days
        total = total + w
        table.insert(list, { value = dp.value, weight = w })
    end
    if total == 0 then return nil end
    table.sort(list, function(a, b) return a.value < b.value end)
    local cum = 0
    for _, e in ipairs(list) do
        cum = cum + e.weight / total
        if cum >= 0.5 then return e.value end
    end
    return list[#list] and list[#list].value
end

-- Merge aux history across every faction scope on this realm.
local function GetAuxPrice(itemKey)
    if not (aux and aux.faction) then return nil end
    local realm  = GetCVar("realmName") or ""
    local prefix = realm .. "|"
    local merged = {}
    local bestDaily
    for key, t in pairs(aux.faction) do
        if type(key) == "string" and type(t) == "table"
            and key:sub(1, #prefix) == prefix then
            local hist = t.history and t.history[itemKey]
            if hist then
                local daily, pts = ParseAuxRecord(hist)
                if daily and (not bestDaily or daily < bestDaily) then bestDaily = daily end
                for _, dp in ipairs(pts or {}) do table.insert(merged, dp) end
            end
        end
    end
    if #merged > 1 then
        table.sort(merged, function(a, b) return a.time > b.time end)
    end
    if #merged > 0 then return WeightedMedian(merged) end
    return bestDaily
end

-- ----- TSM2 DBMarket fallback --------------------------------------------
local function GetTSMPrice(itemKey)
    if not TSMAPI then return nil end
    local itemID = tonumber(itemKey:match("^(%d+):"))
    if not itemID then return nil end
    if LibStub then
        local ace = LibStub("AceAddon-3.0", true)
        local adb = ace and ace:GetAddon("TSM_AuctionDB", true)
        if adb and adb.GetMarketValue then
            local ok, v = pcall(adb.GetMarketValue, adb, itemID)
            if ok and type(v) == "number" and v > 0 then return v end
        end
    end
    return nil
end

-- ----- vendor sell price -------------------------------------------------
function Pricing.GetVendorPrice(link)
    local id = ItemIDFromLink(link)
    if not id then return 0 end
    if vendorCache[id] ~= nil then return vendorCache[id] end
    local price = select(11, GetItemInfo(link))
    vendorCache[id] = price or 0
    return vendorCache[id]
end

-- ----- BoP detection -----------------------------------------------------
function Pricing.IsBindOnPickup(link)
    local id = ItemIDFromLink(link)
    if not id then return false end
    if bindCache[id] ~= nil then return bindCache[id] end

    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "LA_ScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    local bop = false
    local ok = pcall(function()
        scanTooltip:ClearLines()
        scanTooltip:SetHyperlink(link)
    end)
    if ok then
        for i = 1, math.min(5, scanTooltip:NumLines()) do
            local line = _G["LA_ScanTooltipTextLeft" .. i]
            local txt  = line and line:GetText() or ""
            if txt == ITEM_BIND_ON_PICKUP
                or (ITEM_CLASS_QUESTITEM and txt == ITEM_CLASS_QUESTITEM) then
                bop = true
                break
            end
        end
    end
    bindCache[id] = bop
    return bop
end

-- ----- AH price (Aux merged → TSM) ---------------------------------------
local function GetAHPrice(itemKey)
    if priceCache[itemKey] ~= nil then
        return priceCache[itemKey] ~= 0 and priceCache[itemKey] or nil
    end
    local price = GetAuxPrice(itemKey) or GetTSMPrice(itemKey)
    priceCache[itemKey] = price or 0
    return price
end

-- ----- Disenchant expected value -----------------------------------------
-- TSM2 ships the full pre-Cata DE yield table in TradeSkillMaster\Data\Disenchanting.lua.
-- TSMAPI:GetEnchantingTargetItems returns the list of DE *materials* (Strange Dust
-- "item:10940:0:0:0:0:0:0", Lesser Magic Essence, ...). For a given input item we ask
-- TSMAPI:GetEnchantingConversionNum(materialItemString, inputItemID) — non-nil yield
-- means that material is one possible result, with `amountOfMats` already representing
-- the average yield (probability * mean count).
function Pricing.GetDisenchantValue(link)
    local id = ItemIDFromLink(link)
    if not id then return nil end
    if deCache[id] ~= nil then
        return deCache[id] > 0 and deCache[id] or nil
    end
    if not (TSMAPI and TSMAPI.GetEnchantingTargetItems and TSMAPI.GetEnchantingConversionNum) then
        deCache[id] = 0
        return nil
    end
    local total = 0
    local matList = TSMAPI:GetEnchantingTargetItems()
    for _, matString in ipairs(matList or {}) do
        local ok, yield = pcall(TSMAPI.GetEnchantingConversionNum, TSMAPI, matString, id)
        if ok and type(yield) == "number" and yield > 0 then
            local matKey = matString:match("^item:(%d+:%-?%d+)")
                       or  matString:match("^item:(%d+)")
            if matKey and not matKey:find(":") then matKey = matKey .. ":0" end
            local matPrice = matKey and GetAHPrice(matKey)
            if not matPrice or matPrice == 0 then
                local matID = tonumber(matString:match("item:(%d+)"))
                matPrice = matID and (select(11, GetItemInfo(matID)) or 0) or 0
            end
            total = total + yield * matPrice
        end
    end
    deCache[id] = total
    return total > 0 and total or nil
end

-- ----- ArkInventory category lookup --------------------------------------
-- Returns the (lower-cased) category name a looted item has been manually
-- assigned to in ArkInventory's profile, or nil if ArkInventory isn't loaded
-- or the item has no explicit assignment.
--
-- Lookup chain mirrors ArkInventory's own ItemCategoryGetPrimary:
--   profile.option.category["item:<id>:<sb>"]   -> "<type>!<code>" string
--   global.option.category[<type>].data[<code>] -> { name = "Value", ... }
--
-- Only explicit Custom/Rule assignments are returned — ArkInventory's rule
-- engine classifies items dynamically and keeps the result on the in-bag
-- `i.cat` field, which we don't have for a fresh loot row.
local function GetArkInvCategoryName(itemID, isBoP)
    if not itemID then return nil end
    if not (ArkInventory and ArkInventory.db) then return nil end
    local sb = isBoP and 1 or 0
    local cacheKey = string.format("item:%d:%d", itemID, sb)
    local prof = ArkInventory.db.profile
    local catID = prof and prof.option and prof.option.category
                  and prof.option.category[cacheKey]
    if not catID then return nil end
    local catType, catCode = catID:match("^(%d+)!(%d+)$")
    catType, catCode = tonumber(catType), tonumber(catCode)
    if not catType or not catCode then return nil end
    local glob = ArkInventory.db.global
    local data = glob and glob.option and glob.option.category
                 and glob.option.category[catType]
                 and glob.option.category[catType].data
                 and glob.option.category[catType].data[catCode]
    local name = data and data.name
    return (type(name) == "string" and name ~= "") and name:lower() or nil
end

-- ----- top-level: GetItemValue -------------------------------------------
-- Returns: copper, sourceTag, isBoP
function Pricing.GetItemValue(link, opts)
    if not link then return 0, LA_CONST.PRICE_VENDOR, false end
    opts = opts or {}
    local key   = ItemKeyFromLink(link)
    local id    = ItemIDFromLink(link)
    local isBoP = Pricing.IsBindOnPickup(link)

    -- ----- ArkInventory category override -------------------------------
    -- "Value" (or whatever name the user configured) forces the AH chain
    -- even for greys/whites the user has marked AH-saleable. "DE" forces
    -- disenchant expected value regardless of bind/quality. Both fall back
    -- to the rest of the chain if the override path can't produce a price.
    local valueCat = (opts.valueCategory or ""):lower()
    local deCat    = (opts.deCategory    or ""):lower()
    local catName  = (valueCat ~= "" or deCat ~= "") and GetArkInvCategoryName(id, isBoP) or nil
    if catName then
        if valueCat ~= "" and catName == valueCat then
            local ah = key and GetAHPrice(key)
            if ah and ah > 0 then return ah, LA_CONST.PRICE_AUX, isBoP end
            -- AH unknown for this item — fall through to vendor floor below
        elseif deCat ~= "" and catName == deCat then
            local de = Pricing.GetDisenchantValue(link)
            if de and de > 0 then return de, LA_CONST.PRICE_DE, isBoP end
            -- DE produced nothing — fall through
        end
    end

    -- Tradeable (not BoP, not quest) → AH price chain
    if not isBoP and key then
        local ah = GetAHPrice(key)
        if ah and ah > 0 then return ah, LA_CONST.PRICE_AUX, false end
    end

    -- BoP item: try DE if the user opted in and the item qualifies (uncommon+)
    if isBoP and opts.useDisenchant then
        local q = select(3, GetItemInfo(link)) or 0
        if q >= LA_CONST.QUALITY_UNCOMMON and q <= LA_CONST.QUALITY_EPIC then
            local de = Pricing.GetDisenchantValue(link)
            if de and de > 0 then return de, LA_CONST.PRICE_DE, true end
        end
    end

    -- Universal fallback
    local vendor = Pricing.GetVendorPrice(link)
    return vendor or 0, LA_CONST.PRICE_VENDOR, isBoP
end

-- ----- cache invalidation ------------------------------------------------
function Pricing.WipeAHCache()
    priceCache = {}
    deCache    = {}  -- DE values reference AH prices, so invalidate together
end

-- For the UI: short label for the source tag
LA_CONST.PRICE_LABEL = {
    [LA_CONST.PRICE_AUX]    = "ah",
    [LA_CONST.PRICE_TSM]    = "tsm",
    [LA_CONST.PRICE_DE]     = "de",
    [LA_CONST.PRICE_VENDOR] = "v",
}
