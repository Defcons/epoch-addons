-- QuestRewardIcons.lua
-- Claude: addon that overlays gold-coin and disenchant icons on quest choice items,
--         highlighting the best pick based on vendor sell price vs expected DE value.
--         DE values use live Aux/TSM mat prices (mirrors aux.core.disenchant distribution).
--         Gold wins if its value is >= DE value + GOLD_THRESHOLD (default 30s).

local GOLD_THRESHOLD = 3000  -- Claude: 30s in copper; gold wins ties within this margin

local ICON_GOLD = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_DE   = "Interface\\Icons\\Ability_TradeskillEnchanting"

-- ─── Price Lookup (mirrors TitanGoldTracker / AuxTSMBridge pattern) ───────────

-- Claude: mat price session cache keyed by itemID (number)
local QRI_MatPriceCache = {}

local function QRI_GetFactionKey()
    local realm   = GetCVar("realmName")       or ""
    local faction = UnitFactionGroup("player") or ""
    return realm .. "|" .. faction
end

-- Claude: parse raw aux history string → daily_min, data_points table
local function QRI_ParseAuxRecord(str)
    if not str or str == "" then return nil, {} end
    local _, s2, s3 = str:match("^([^#]*)#([^#]*)#?(.*)")
    local daily_min = tonumber(s2)
    local pts = {}
    if s3 and s3 ~= "" then
        for entry in (s3 .. ";"):gmatch("([^;]+);") do
            local vs, ts = entry:match("^([^@]+)@(.+)$")
            local v, t = tonumber(vs), tonumber(ts)
            if v and t then tinsert(pts, { value = v, time = t }) end
        end
    end
    return daily_min, pts
end

-- Claude: weighted median from aux data points (same decay as aux itself)
local function QRI_WeightedMedian(pts)
    if not pts or #pts == 0 then return nil end
    local ref   = pts[1].time
    local decay = (aux and aux.account and type(aux.account.history_decay) == "number"
                   and aux.account.history_decay) or 0.75
    local W, wtbl = 0, {}
    for _, dp in ipairs(pts) do
        local days = floor((ref - dp.time) / 86400 + 0.5)
        local w    = decay ^ days
        W = W + w
        tinsert(wtbl, { value = dp.value, weight = w })
    end
    if W == 0 then return nil end
    table.sort(wtbl, function(a, b) return a.value < b.value end)
    local cum = 0
    for _, w in ipairs(wtbl) do
        cum = cum + w.weight / W
        if cum >= 0.5 then return w.value end
    end
    return wtbl[#wtbl] and wtbl[#wtbl].value
end

-- Claude: look up a single mat's AH price via direct aux history parse (no temp alloc)
local function QRI_AuxMatPrice(itemID)
    local fKey  = QRI_GetFactionKey()
    local hdata = aux and aux.faction and aux.faction[fKey] and aux.faction[fKey]["history"]
    if not hdata then return nil end
    local str = hdata[itemID .. ":0"]
    if not str then return nil end
    local daily_min, pts = QRI_ParseAuxRecord(str)
    if pts and #pts > 0 then return QRI_WeightedMedian(pts) end
    return daily_min
end

-- Claude: look up a single mat's price via TSM AuctionDB GetMarketValue
local function QRI_TSMMatPrice(itemID)
    if not TSMAPI then return nil end
    local ok, price = pcall(function()
        local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
        local adb      = AceAddon and AceAddon:GetAddon("TSM_AuctionDB", true)
        if adb then return adb:GetMarketValue(itemID) end
    end)
    return ok and type(price) == "number" and price > 0 and price or nil
end

-- Claude: get mat price in copper; Aux first, TSM fallback; cached for session
local function QRI_GetMatPrice(itemID)
    if QRI_MatPriceCache[itemID] ~= nil then
        return QRI_MatPriceCache[itemID] ~= 0 and QRI_MatPriceCache[itemID] or nil
    end
    local price = QRI_AuxMatPrice(itemID) or QRI_TSMMatPrice(itemID)
    QRI_MatPriceCache[itemID] = price or 0
    return price
end

-- ─── DE Distribution Table ────────────────────────────────────────────────────

-- Claude: equip slots that can be disenchanted (mirrors aux.core.disenchant)
local ARMOR_SLOTS = {
    INVTYPE_HEAD = true,   INVTYPE_NECK = true,     INVTYPE_SHOULDER = true,
    INVTYPE_BODY = true,   INVTYPE_CHEST = true,    INVTYPE_ROBE = true,
    INVTYPE_WAIST = true,  INVTYPE_LEGS = true,     INVTYPE_FEET = true,
    INVTYPE_WRIST = true,  INVTYPE_HAND = true,     INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true,INVTYPE_CLOAK = true,    INVTYPE_HOLDABLE = true,
}
local WEAPON_SLOTS = {
    INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPON = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true,
    INVTYPE_RANGED = true,   INVTYPE_RANGEDRIGHT = true,
}

-- Claude: returns list of {id, prob, minQ, maxQ} entries for a given item.
-- Directly mirrors the probability table in aux.core.disenchant (read from source)
-- using plain Lua tables instead of aux's temp-A/temp-O allocators.
-- slot = equipSlot string (e.g. "INVTYPE_HEAD"), quality = 2/3/4, level = ilvl
local function QRI_GetDistribution(slot, quality, level)
    if not ARMOR_SLOTS[slot] and not WEAPON_SLOTS[slot] then return {} end
    if not level or level == 0 then return {} end

    local isArmor = ARMOR_SLOTS[slot] and true or false
    local function p(pa, pw) return isArmor and pa or pw end

    local D = {}
    local function add(id, prob, minQ, maxQ)
        tinsert(D, { id = id, prob = prob, minQ = minQ, maxQ = maxQ })
    end

    if quality == 2 then  -- Uncommon (green)
        if     level <= 10 then
            add(10940, p(.80, .20), 1, 2)   -- Strange Dust / Lesser Magic Essence
            add(10938, p(.20, .80), 1, 2)
        elseif level <= 15 then
            add(10940, p(.75, .20), 2, 3)   -- Strange Dust / Greater Magic Essence / Small Glimm. Shard
            add(10939, p(.20, .75), 1, 2)
            add(10978, .05, 1, 1)
        elseif level <= 20 then
            add(10940, p(.75, .15), 4, 6)
            add(10998, p(.15, .75), 1, 2)
            add(10978, .10, 1, 1)
        elseif level <= 25 then
            add(11083, p(.75, .20), 1, 2)   -- Soul Dust / Lesser Astral Essence / Small Glowing Shard
            add(11082, p(.20, .75), 1, 2)
            add(11084, .05, 1, 1)
        elseif level <= 30 then
            add(11083, p(.75, .20), 2, 5)
            add(11134, p(.20, .75), 1, 2)
            add(11138, .05, 1, 1)
        elseif level <= 35 then
            add(11137, p(.75, .20), 1, 2)   -- Soul Dust / Greater Astral Essence / Large Glowing Shard
            add(11135, p(.20, .75), 1, 2)
            add(11139, .05, 1, 1)
        elseif level <= 40 then
            add(11137, p(.75, .20), 2, 5)
            add(11174, p(.20, .75), 1, 2)
            add(11177, .05, 1, 1)
        elseif level <= 45 then
            add(11176, p(.75, .20), 1, 2)   -- Vision Dust / Greater Mystic Ess. / Large Glowing Shard
            add(11175, p(.20, .75), 1, 2)
            add(11178, .05, 1, 1)
        elseif level <= 50 then
            add(11176, p(.75, .22), 2, 5)   -- Vision Dust / Lesser Eternal Essence / Small Radiant Shard
            add(16202, p(.20, .75), 1, 2)
            add(14343, p(.05, .03), 1, 1)
        elseif level <= 55 then
            add(16204, p(.75, .22), 1, 2)   -- Illusion Dust / Greater Eternal Essence / Large Radiant Shard
            add(16203, p(.20, .75), 1, 2)
            add(14344, p(.05, .03), 1, 1)
        elseif level <= 60 then
            add(16204, p(.75, .22), 2, 5)
            add(16203, p(.20, .75), 2, 3)
            add(14344, p(.05, .03), 1, 1)
        elseif level <= 65 then
            add(22445, p(.75, .22), 2, 3)   -- Arcane Dust / Lesser Planar Essence / Nightmare's Tear (TBC)
            add(22447, p(.22, .75), 2, 3)
            add(22448, .03, 1, 1)
        elseif level <= 70 then
            add(22445, p(.75, .22), 2, 3)
            add(22446, p(.22, .75), 1, 2)
            add(22445, p(.03, .03), 2, 5)
        elseif level <= 80 then             -- Claude: WotLK greens (approximate)
            add(34054, p(.75, .22), 2, 4)   -- Infinite Dust
            add(34055, p(.22, .75), 1, 2)   -- Lesser Cosmic Essence
            add(34052, .03, 1, 1)            -- Dream Shard
        end

    elseif quality == 3 then  -- Rare (blue)
        if     level <= 20 then add(10978, 1, 1, 1)
        elseif level <= 25 then add(11084, 1, 1, 1)
        elseif level <= 30 then add(11138, 1, 1, 1)
        elseif level <= 35 then add(11139, 1, 1, 1)
        elseif level <= 40 then add(11177, 1, 1, 1)
        elseif level <= 45 then add(11178, 1, 1, 1)
        elseif level <= 50 then add(14343, 1, 1, 1)
        elseif level <= 60 then
            add(14344, .995, 1, 1)           -- Large Brilliant Shard / Nexus Crystal
            add(20725, .005, 1, 1)
        elseif level <= 65 then
            add(22448, .995, 1, 1)
            add(20725, .005, 1, 1)
        elseif level <= 70 then
            add(22449, .995, 1, 1)           -- Void Crystal
            add(20725, .005, 1, 1)
        elseif level <= 80 then             -- Claude: WotLK blues (approximate)
            add(34052, 1, 1, 1)              -- Dream Shard
        end

    elseif quality == 4 then  -- Epic (purple)
        if     level <= 40 then add(11177, 1, 2, 4)
        elseif level <= 45 then add(11178, 1, 2, 4)
        elseif level <= 50 then add(14343, 1, 2, 4)
        elseif level <= 60 then add(20725, 1, 1, 2)  -- Nexus Crystal
        elseif level <= 65 then add(22450, 1, 1, 2)  -- Void Crystal
        elseif level <= 70 then add(22450, 1, 1, 2)
        elseif level <= 80 then add(34057, 1, 1, 1)  -- Abyss Crystal (approx.)
        end
    end

    return D
end

-- Claude: expected DE value in copper using live mat prices.
-- Returns 0 if item can't be DE'd or if any mat price is unknown.
local function GetDEValue(link)
    if not link then return 0 end
    local _, _, quality, ilvl, _, _, _, _, slot = GetItemInfo(link)
    if not quality or not ilvl or not slot then return 0 end

    local dist = QRI_GetDistribution(slot, quality, ilvl)
    if not dist or #dist == 0 then return 0 end

    local total = 0
    for _, entry in ipairs(dist) do
        local matPrice = QRI_GetMatPrice(entry.id)
        if not matPrice then return 0 end  -- Claude: unknown price → skip DE icon
        local avgQty = (entry.minQ + entry.maxQ) / 2
        total = total + entry.prob * avgQty * matPrice
    end
    return total
end

-- ─── Vendor Value ─────────────────────────────────────────────────────────────

-- Claude: get vendor sell price from GetItemInfo (sellPrice = index 11 in 3.3.5)
local function GetSellValue(link)
    if not link then return 0 end
    local info = { GetItemInfo(link) }
    return info[11] or 0
end

-- ─── Icon Overlay Frames ──────────────────────────────────────────────────────

-- Claude: overlay frames keyed by "QuestInfoItemN_gold" / "QuestInfoItemN_de"
local overlays = {}

-- Claude: find the item icon texture/frame to use as position anchor
local function GetIconAnchor(btn)
    local name = btn:GetName()
    return _G[name .. "Icon"]
        or _G[name .. "IconTexture"]
        or btn:GetNormalTexture()
        or btn
end

-- Claude: get or create a small icon overlay parented to a quest item button
local function GetOrCreate(btn, kind)
    local key = btn:GetName() .. "_" .. kind
    if overlays[key] then return overlays[key] end

    local f = CreateFrame("Frame", nil, btn)
    f:SetFrameLevel(btn:GetFrameLevel() + 10)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0, 0, 0, 0.8)
    f.bg = bg

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -1)
    tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)
    tex:SetTexture(kind == "gold" and ICON_GOLD or ICON_DE)
    f.tex = tex

    overlays[key] = f
    return f
end

local function HideAll()
    for _, f in pairs(overlays) do f:Hide() end
end

-- Claude: place and style one icon on a button
--   kind     = "gold" or "de"
--   xOffset  = horizontal shift for stacking two icons on the same button
--   isWinner = true → large + bright coloured bg; false → small + dimmed
local function PlaceIcon(btn, kind, xOffset, isWinner)
    local f    = GetOrCreate(btn, kind)
    local size = isWinner and 18 or 13

    f:SetWidth(size)
    f:SetHeight(size)
    f:ClearAllPoints()

    local anchor = GetIconAnchor(btn)
    f:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", xOffset, 0)

    if isWinner then
        f.tex:SetAlpha(1.0)
        if kind == "gold" then
            f.bg:SetVertexColor(0.9, 0.75, 0.0)  -- Claude: yellow bg for gold winner
        else
            f.bg:SetVertexColor(0.1, 0.2, 0.85)  -- Claude: blue bg for DE winner
        end
        f.bg:SetAlpha(0.85)
    else
        f.tex:SetAlpha(0.38)
        f.bg:SetVertexColor(0, 0, 0)
        f.bg:SetAlpha(0.7)
    end

    f:Show()
end

-- ─── Main Logic ───────────────────────────────────────────────────────────────

-- Claude: find the QuestInfoItemN button that maps to choice slot i.
-- Blizzard sets button.type = "choice" and button:GetID() = i on each button.
-- Falls back to positional order if .type is unset.
local function FindChoiceButton(i)
    for b = 1, 10 do
        local btn = _G["QuestInfoItem" .. b]
        if btn and btn:IsShown()
           and btn.type == "choice" and btn:GetID() == i then
            return btn
        end
    end
    local btn = _G["QuestInfoItem" .. i]  -- Claude: positional fallback
    if btn and btn:IsShown() then return btn end
end

-- Claude: main update — compute vendor/DE values, find winners, place icons
local function UpdateIcons()
    HideAll()

    local numChoices = GetNumQuestChoices()
    if numChoices < 2 then return end  -- Claude: nothing to compare

    local sellVals = {}
    local deVals   = {}
    for i = 1, numChoices do
        local link  = GetQuestItemLink("choice", i)
        sellVals[i] = GetSellValue(link)
        deVals[i]   = GetDEValue(link)
    end

    -- Claude: find index with highest vendor value and highest DE value
    local bestSellIdx, bestSellVal = 1, sellVals[1] or 0
    local bestDEIdx,   bestDEVal   = 1, deVals[1]   or 0
    for i = 2, numChoices do
        if (sellVals[i] or 0) > bestSellVal then
            bestSellIdx = i ; bestSellVal = sellVals[i]
        end
        if (deVals[i] or 0) > bestDEVal then
            bestDEIdx = i ; bestDEVal = deVals[i]
        end
    end

    -- Claude: gold wins overall when its value exceeds DE by at least GOLD_THRESHOLD (30s)
    local goldWins = (bestSellVal >= bestDEVal + GOLD_THRESHOLD)

    for i = 1, numChoices do
        local btn = FindChoiceButton(i)
        if not btn then break end

        local showGold = (i == bestSellIdx) and (bestSellVal > 0)
        local showDE   = (i == bestDEIdx)   and (bestDEVal   > 0)

        if showGold and showDE then
            -- Claude: both icons on same button — stack side by side
            PlaceIcon(btn, "gold", 0,         goldWins)
            PlaceIcon(btn, "de",  -(13 + 2),  not goldWins)
        elseif showGold then
            PlaceIcon(btn, "gold", 0,  goldWins)
        elseif showDE then
            PlaceIcon(btn, "de",   0,  not goldWins)
        end
    end
end

-- ─── Hooks & Events ───────────────────────────────────────────────────────────

-- Claude: defer one frame after event so Blizzard finishes populating the UI
local function UpdateAfterTick()
    local tick = CreateFrame("Frame")
    tick:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        UpdateIcons()
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:SetScript("OnEvent", UpdateAfterTick)

-- Claude: also hook QuestInfo_Display for redraws without an event firing
hooksecurefunc("QuestInfo_Display", UpdateIcons)
