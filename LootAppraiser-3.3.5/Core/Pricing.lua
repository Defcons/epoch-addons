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
-- Resolves a category id "type!code" to its (lower-cased) display name.
local function ResolveCatID(catID)
    local catType, catCode = tostring(catID):match("^(%d+)!(%d+)$")
    catType, catCode = tonumber(catType), tonumber(catCode)
    if not catType or not catCode then return nil end
    local glob = ArkInventory.db and ArkInventory.db.global
    local data = glob and glob.option and glob.option.category
                 and glob.option.category[catType]
                 and glob.option.category[catType].data
                 and glob.option.category[catType].data[catCode]
    local name = data and data.name
    if type(name) == "string" and name ~= "" then return name:lower() end
    return nil
end

-- Walk ArkInventory's per-character bag storage looking for a slot whose
-- itemID matches. Returns the lower-cased category name from the slot's
-- cached classification, or nil. This is the path that finds rule-based
-- classifications: ArkInventory writes the rule's resolved category id to
-- `slot.cat` during its bag scan, but never persists that to
-- `db.profile.option.category` — so the explicit-assignment lookup misses
-- rule-classified items entirely.
--
-- Caveat: there's a timing race for fresh loot. CHAT_MSG_LOOT fires before
-- ArkInventory has run its bag scan for the new item, so on the very
-- first lookup we'll usually miss. The next BAG_UPDATE → reconcile tick
-- (~0.3s later) doesn't currently re-price existing rows, so a
-- rule-classified item that arrives via group loot may price as "default"
-- (vendor) on its first row. Re-pricing on reconcile is on the v1.11+
-- backlog.
local function GetArkInvCategoryNameFromBags(itemID)
    if not itemID then return nil end
    if not (ArkInventory and ArkInventory.db and ArkInventory.db.realm
            and ArkInventory.Global and ArkInventory.Global.Me
            and ArkInventory.Global.Me.info
            and ArkInventory.Const and ArkInventory.Const.Location) then
        return nil
    end
    local pid = ArkInventory.Global.Me.info.player_id
    local pdata = pid and ArkInventory.db.realm.player and ArkInventory.db.realm.player.data
                       and ArkInventory.db.realm.player.data[pid]
    local bagLoc = pdata and pdata.location and pdata.location[ArkInventory.Const.Location.Bag]
    if not bagLoc or not bagLoc.bag then return nil end
    for _, bag in pairs(bagLoc.bag) do
        if bag.slot then
            for _, slot in pairs(bag.slot) do
                if slot.h and slot.cat then
                    local sid = tonumber(slot.h:match("|Hitem:(%d+)") or slot.h:match("item:(%d+)"))
                    if sid == itemID then
                        return ResolveCatID(slot.cat)
                    end
                end
            end
        end
    end
    return nil
end

-- Returns the (lower-cased) category name for a looted item, or nil if
-- ArkInventory isn't loaded.
--
-- Lookup chain:
--   1. Explicit manual assignment in `db.profile.option.category[key]`.
--      This catches items dragged into Custom categories in the bag UI.
--   2. Bag-scan fallback (`GetArkInvCategoryNameFromBags`). This catches
--      items whose category was assigned dynamically by an ArkInventory
--      Rule — those resolutions live on `slot.cat` after a bag scan,
--      not in the persistent profile.option.category.
--   3. If neither hits, return "default" so the vendor-override list can
--      opt to absorb all uncategorised items.
local function GetArkInvCategoryName(itemID, isBoP)
    if not itemID then return nil end
    if not (ArkInventory and ArkInventory.db) then return nil end
    local sb = isBoP and 1 or 0
    local cacheKey = string.format("item:%d:%d", itemID, sb)
    local prof = ArkInventory.db.profile
    local catID = prof and prof.option and prof.option.category
                  and prof.option.category[cacheKey]
    if catID then
        local name = ResolveCatID(catID)
        if name then return name end
    end

    -- Fallback to ArkInventory's bag scan for rule-classified items.
    local bagsName = GetArkInvCategoryNameFromBags(itemID)
    if bagsName then return bagsName end

    -- Last resort: surface "default" so the vendor list can catch it.
    return "default"
end

-- ----- top-level: GetItemValue -------------------------------------------

-- Returns true if `catName` (already lower-cased) appears in `csv`, where
-- csv is a comma-separated case-insensitive list (e.g. "Junk, Trash"). An
-- empty/nil csv always returns false — that's how callers disable an
-- override entirely (set the config string to "").
local function CatNameInList(catName, csv)
    if not catName or not csv or csv == "" then return false end
    for entry in csv:gmatch("[^,]+") do
        local trimmed = entry:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if trimmed ~= "" and catName == trimmed then return true end
    end
    return false
end

-- Returns: copper, sourceTag, isBoP
function Pricing.GetItemValue(link, opts)
    if not link then return 0, LA_CONST.PRICE_VENDOR, false end
    opts = opts or {}
    local key   = ItemKeyFromLink(link)
    local id    = ItemIDFromLink(link)
    local isBoP = Pricing.IsBindOnPickup(link)

    -- ----- ArkInventory category override -------------------------------
    -- Three lists of category names (each comma-separated, case-insensitive):
    --   * valueCategory  → force the AH chain (whites you AH-sell)
    --   * deCategory     → force disenchant expected value
    --   * vendorCategory → force vendor sell (Junk/Trash you always vendor;
    --                       skips even an incidental AH listing)
    -- Each branch falls through to the default chain if its preferred
    -- price source returns nil / 0 — useful for new items the AH hasn't
    -- yet seen, or items in "DE" that aren't actually disenchantable.
    local valueCat  = opts.valueCategory  or ""
    local deCat     = opts.deCategory     or ""
    local vendorCat = opts.vendorCategory or ""
    local needLookup = valueCat ~= "" or deCat ~= "" or vendorCat ~= ""
    local catName  = needLookup and GetArkInvCategoryName(id, isBoP) or nil
    if catName then
        if CatNameInList(catName, valueCat) then
            local ah = key and GetAHPrice(key)
            if ah and ah > 0 then return ah, LA_CONST.PRICE_AUX, isBoP end
            -- AH unknown for this item — fall through to vendor floor below
        elseif CatNameInList(catName, deCat) then
            local de = Pricing.GetDisenchantValue(link)
            if de and de > 0 then return de, LA_CONST.PRICE_DE, isBoP end
            -- DE produced nothing — fall through
        elseif CatNameInList(catName, vendorCat) then
            -- Force vendor; bypass AH/DE entirely. Returning the vendor
            -- price (even 0) is intentional — IngestLoot's zero-value
            -- filter is what suppresses 0-copper rows from the list.
            return Pricing.GetVendorPrice(link), LA_CONST.PRICE_VENDOR, isBoP
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

-- ----- debug dump --------------------------------------------------------
-- Comprehensive single-item diagnostic. Output is grouped into sections so
-- a paste from chat is easy to read:
--   * Identity      — link, itemID, key, BoP, quality, GetItemInfo basics
--   * ArkInventory  — cache key, explicit assignment, bag-scan slot.cat,
--                     resolver result. Includes which bag/slot the item
--                     was found in (if any) — useful for "the item should
--                     be in DE rule, why is it priced as vendor".
--   * Config        — the four pricing options as actually loaded from
--                     LootAppraiserDB.profile (not LA_DEFAULTS).
--   * Pricing       — raw AH/DE/vendor numbers + the final decision.
--   * Session       — whether a session is running, matching rows already
--                     ingested, and the bag-tracking ledger entries.
--
-- Helper formatting for copper amounts.
local function FormatCopper(c)
    if not c or c == 0 then return tostring(c or 0) .. "c (0)" end
    local g = math.floor(c / 10000)
    local s = math.floor((c - g * 10000) / 100)
    local cc = c - g * 10000 - s * 100
    if g > 0 then return string.format("%dc (%dg %ds %dc)", c, g, s, cc) end
    if s > 0 then return string.format("%dc (%ds %dc)",     c, s, cc)   end
    return c .. "c"
end

-- Find which bag/slot currently contains a given itemID. Returns
-- (bagID, slotID, count) or nil. Skips bag -2 (keyring) and bag -1.
local function FindItemInBags(itemID)
    if not itemID then return nil end
    for bag = 0, NUM_BAG_SLOTS do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id == itemID then
                    local _, count = GetContainerItemInfo(bag, slot)
                    return bag, slot, (count or 1)
                end
            end
        end
    end
    return nil
end

function Pricing.DumpItem(link, opts)
    opts = opts or {}
    local function out(s) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LA dump]|r " .. tostring(s)) end
    if not link then out("no link") return end

    local id    = ItemIDFromLink(link)
    local key   = ItemKeyFromLink(link)
    local isBoP = Pricing.IsBindOnPickup(link)

    out("=== " .. (link:match("%[(.-)%]") or "?") .. " (id " .. tostring(id) .. ") ===")

    -- ----- Identity ------------------------------------------------------
    out(" identity:")
    out("   link        = " .. tostring(link))
    out("   itemKey     = " .. tostring(key) .. "   (itemID:suffixID)")
    out("   isBoP       = " .. tostring(isBoP))
    do
        local name, _, quality, ilvl, _, class, sub, _, _, _, vendor =
            GetItemInfo(link)
        out("   GetItemInfo:")
        out("     name        = " .. tostring(name))
        out("     quality     = " .. tostring(quality)
            .. (LA_CONST.QUALITY_COLOR[quality or -1]
                and ("  " .. (LA_CONST.QUALITY_COLOR[quality] or "") .. "(swatch)|r")
                or ""))
        out("     itemLevel   = " .. tostring(ilvl))
        out("     class/sub   = " .. tostring(class) .. " / " .. tostring(sub))
        out("     vendorPrice = " .. FormatCopper(vendor))
    end

    -- ----- ArkInventory --------------------------------------------------
    out(" ArkInventory:")
    if not (ArkInventory and ArkInventory.db) then
        out("   (not loaded)")
    else
        local sb = isBoP and 1 or 0
        local cacheKey = id and string.format("item:%d:%d", id, sb) or "(no id)"
        out("   cacheKey                       = " .. cacheKey)
        local prof = ArkInventory.db.profile
        local raw = prof and prof.option and prof.option.category
                    and prof.option.category[cacheKey]
        out("   profile.option.category[key]   = " .. tostring(raw))
        if raw then
            local t, c = tostring(raw):match("^(%d+)!(%d+)$")
            t, c = tonumber(t), tonumber(c)
            out("     decoded type/code            = " .. tostring(t) .. " / " .. tostring(c))
            if t and c and ArkInventory.db.global and ArkInventory.db.global.option
               and ArkInventory.db.global.option.category and ArkInventory.db.global.option.category[t]
               and ArkInventory.db.global.option.category[t].data then
                local d = ArkInventory.db.global.option.category[t].data[c]
                out("     global cat[t][c].name       = " .. tostring(d and d.name))
            end
        end

        -- Bag scan: what does ArkInventory's slot.cat say (rule-classified
        -- items live here, not in profile.option.category)?
        local bagsName = id and GetArkInvCategoryNameFromBags(id) or nil
        out("   bag-scan slot.cat resolves to  = " .. tostring(bagsName))
        out("   resolver returns               = " .. tostring(GetArkInvCategoryName(id, isBoP)))
    end

    -- ----- Config --------------------------------------------------------
    out(" config (live profile):")
    local db = LA.db and LA.db.profile or {}
    out("   arkInvValueCategory   = '" .. tostring(db.arkInvValueCategory  or opts.valueCategory  or "") .. "'")
    out("   arkInvDECategory      = '" .. tostring(db.arkInvDECategory     or opts.deCategory     or "") .. "'")
    out("   arkInvVendorCategory  = '" .. tostring(db.arkInvVendorCategory or opts.vendorCategory or "") .. "'")
    out("   useDisenchant         = " .. tostring(db.useDisenchant))
    out("   skipZeroValueRows     = " .. tostring(db.skipZeroValueRows))
    out("   minQuality            = " .. tostring(db.minQuality))
    out("   minQualityForList     = " .. tostring(db.minQualityForList))

    -- ----- Pricing -------------------------------------------------------
    out(" pricing:")
    do
        local ah = key and GetAHPrice(key)
        local de = Pricing.GetDisenchantValue(link)
        local v  = Pricing.GetVendorPrice(link)
        out("   AH (Aux merged + TSM)  = " .. FormatCopper(ah))
        out("   DE expected            = " .. FormatCopper(de))
        out("   Vendor sell            = " .. FormatCopper(v))
        local copper, src, bop = Pricing.GetItemValue(link, opts)
        out("   FINAL                  = " .. FormatCopper(copper)
            .. "   source = " .. tostring(src) .. "   isBoP = " .. tostring(bop))
    end

    -- ----- Session -------------------------------------------------------
    out(" session:")
    if not (LA.Session and LA.Session.IsRunning and LA.Session.IsRunning()) then
        out("   (not running)")
    else
        local snap = LA.Session.Snapshot()
        out("   running     = true   zone = " .. tostring(snap.zone))
        out("   total looted= " .. FormatCopper(snap.lootTotal))
        out("   GPH         = " .. FormatCopper(snap.gph) .. "/h")
        local rows = LA.Session.GetRows() or {}
        local matched = 0
        for i, row in ipairs(rows) do
            local rid = tonumber((row.link or ""):match("item:(%d+)"))
            if rid == id then
                matched = matched + 1
                if matched <= 5 then
                    out(string.format("   row[%d]: count=%s unit=%s value=%s src=%s age=%.1fs",
                        i, tostring(row.count), FormatCopper(row.unit),
                        FormatCopper(row.value), tostring(row.src),
                        GetTime() - (row.time or 0)))
                end
            end
        end
        out("   matching rows in session = " .. matched)
        if LA.Session.GetBagLedger then
            local base, own, cur = LA.Session.GetBagLedger(id)
            out(string.format("   bag ledger: baseline=%s bagOwn=%s currentBags=%s",
                tostring(base), tostring(own), tostring(cur)))
        end
    end

    -- ----- Bag location --------------------------------------------------
    local bag, slot, count = FindItemInBags(id)
    if bag then
        out(string.format(" current bag location: bag %d slot %d (count %d)", bag, slot, count))
    else
        out(" current bag location: not in bags")
    end

    out("=== end ===")
end

-- For the UI: short label for the source tag
LA_CONST.PRICE_LABEL = {
    [LA_CONST.PRICE_AUX]    = "ah",
    [LA_CONST.PRICE_TSM]    = "tsm",
    [LA_CONST.PRICE_DE]     = "de",
    [LA_CONST.PRICE_VENDOR] = "v",
}
