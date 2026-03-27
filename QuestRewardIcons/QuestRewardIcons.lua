-- QuestRewardIcons.lua
-- Claude: overlays gold-coin and disenchant icons on quest choice reward items.
-- DE value is fetched from a configurable source: Aux, TSM, Static, or Auto.
--   Auto (default): tries Aux → TSM per mat, falls back to static bracket table.
--   Aux:    Aux weighted-median history prices only.
--   TSM:    TSM AuctionDB DBMarket prices only.
--   Static: hardcoded copper-value table by quality + ilvl bracket.
-- Gold wins the overall comparison if its value >= DE value + goldThreshold (default 30s).
--
-- Slash: /qri              → show current settings
--        /qri source <auto|aux|tsm|static>
--        /qri threshold <silver>   (e.g. /qri threshold 50 = 50s preference for gold)

-- ─── SavedVariables defaults ──────────────────────────────────────────────────

-- QuestRewardIconsDB = { source = "auto", goldThreshold = 3000 }

local DEFAULTS = { source = "auto", goldThreshold = 3000 }

local function DB(key) -- Claude: safe accessor for SavedVariables with default fallback
    return (QuestRewardIconsDB and QuestRewardIconsDB[key] ~= nil)
           and QuestRewardIconsDB[key] or DEFAULTS[key]
end

-- ─── Icons ────────────────────────────────────────────────────────────────────

local ICON_GOLD = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_DE   = "Interface\\Icons\\Ability_TradeskillEnchanting"

-- ─── Static DE Value Table ────────────────────────────────────────────────────

-- Claude: fallback copper values when Aux/TSM prices are unavailable.
-- Adjust to match your server's enchanting mat economy.
-- quality: 2=Uncommon(green), 3=Rare(blue), 4=Epic(purple)
local DE_STATIC = {
    [2] = {  -- Uncommon (green)
        { max =  15, val =  1500 },  -- Strange Dust          ~15s
        { max =  25, val =  3000 },  -- Soul Dust             ~30s
        { max =  35, val =  5000 },  -- Vision Dust           ~50s
        { max =  45, val = 12000 },  -- Dream Dust            ~1.2g
        { max =  51, val = 25000 },  -- Illusion Dust         ~2.5g
        { max =  57, val = 40000 },  -- Illusion Dust/GEE     ~4g
        { max =  65, val = 70000 },  -- Greater Eternal Ess.  ~7g
        { max =  70, val = 30000 },  -- Arcane Dust (TBC)     ~3g
        { max = 999, val = 25000 },  -- Infinite Dust (WotLK) ~2.5g
    },
    [3] = {  -- Rare (blue)
        { max =  25, val =  15000 },  -- Small Glowing Shard    ~1.5g
        { max =  35, val =  30000 },  -- Large Glowing Shard    ~3g
        { max =  50, val =  60000 },  -- Small/Large Rad. Shard ~6g
        { max =  60, val = 150000 },  -- Large Brilliant Shard  ~15g
        { max =  65, val = 100000 },  -- Nexus Crystal          ~10g
        { max =  70, val = 250000 },  -- Void Crystal           ~25g
        { max = 999, val = 400000 },  -- Abyss Crystal          ~40g
    },
    [4] = {  -- Epic (purple)
        { max =  60, val =  300000 },  -- Nexus Crystal  ~30g
        { max =  70, val =  800000 },  -- Void Crystal   ~80g
        { max = 999, val = 1500000 },  -- Abyss Crystal  ~150g
    },
}

-- Claude: look up static DE value from bracket table (quality + ilvl)
local function GetDEValue_Static(link)
    if not link then return 0 end
    local _, _, quality, ilvl = GetItemInfo(link)
    if not quality or not ilvl then return 0 end
    local tbl = DE_STATIC[quality]
    if not tbl then return 0 end
    for _, row in ipairs(tbl) do
        if ilvl <= row.max then return row.val end
    end
    return 0
end

-- ─── Live DE Value (Aux / TSM mat prices) ─────────────────────────────────────

-- Claude: equip slots eligible for disenchanting (mirrors aux.core.disenchant)
local ARMOR_SLOTS = {
    INVTYPE_HEAD = true,    INVTYPE_NECK = true,     INVTYPE_SHOULDER = true,
    INVTYPE_BODY = true,    INVTYPE_CHEST = true,    INVTYPE_ROBE = true,
    INVTYPE_WAIST = true,   INVTYPE_LEGS = true,     INVTYPE_FEET = true,
    INVTYPE_WRIST = true,   INVTYPE_HAND = true,     INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true, INVTYPE_CLOAK = true,    INVTYPE_HOLDABLE = true,
}
local WEAPON_SLOTS = {
    INVTYPE_2HWEAPON = true,      INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPON = true,        INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true,        INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
}

-- Claude: mat price session cache keyed by "itemID_source"
local QRI_MatPriceCache = {}

local function QRI_GetFactionKey()
    return (GetCVar("realmName") or "") .. "|" .. (UnitFactionGroup("player") or "")
end

-- Claude: parse raw aux history string "next_push#daily_min#val@time;..."
local function QRI_ParseAuxRecord(str)
    if not str or str == "" then return nil, {} end
    local _, s2, s3 = str:match("^([^#]*)#([^#]*)#?(.*)")
    local pts = {}
    if s3 and s3 ~= "" then
        for entry in (s3 .. ";"):gmatch("([^;]+);") do
            local vs, ts = entry:match("^([^@]+)@(.+)$")
            local v, t = tonumber(vs), tonumber(ts)
            if v and t then tinsert(pts, { value = v, time = t }) end
        end
    end
    return tonumber(s2), pts
end

-- Claude: weighted median from aux data points, honouring aux's own decay setting
local function QRI_WeightedMedian(pts)
    if not pts or #pts == 0 then return nil end
    local ref   = pts[1].time
    local decay = (aux and aux.account and type(aux.account.history_decay) == "number"
                   and aux.account.history_decay) or 0.75
    local W, wtbl = 0, {}
    for _, dp in ipairs(pts) do
        local w = decay ^ floor((ref - dp.time) / 86400 + 0.5)
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

-- Claude: single mat price from Aux history (direct string parse, no temp alloc)
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

-- Claude: single mat price from TSM AuctionDB GetMarketValue
local function QRI_TSMMatPrice(itemID)
    if not TSMAPI then return nil end
    local ok, price = pcall(function()
        local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
        local adb      = AceAddon and AceAddon:GetAddon("TSM_AuctionDB", true)
        if adb then return adb:GetMarketValue(itemID) end
    end)
    return ok and type(price) == "number" and price > 0 and price or nil
end

-- Claude: get mat price for a given source ("aux", "tsm", or "auto" = Aux→TSM);
--         cached per session per source to avoid re-parsing history repeatedly
local function QRI_GetMatPrice(itemID, source)
    local cacheKey = itemID .. "_" .. source
    if QRI_MatPriceCache[cacheKey] ~= nil then
        return QRI_MatPriceCache[cacheKey] ~= 0 and QRI_MatPriceCache[cacheKey] or nil
    end
    local price
    if source == "aux" then
        price = QRI_AuxMatPrice(itemID)
    elseif source == "tsm" then
        price = QRI_TSMMatPrice(itemID)
    else  -- "auto": Aux first, TSM fallback
        price = QRI_AuxMatPrice(itemID) or QRI_TSMMatPrice(itemID)
    end
    QRI_MatPriceCache[cacheKey] = price or 0
    return price
end

-- Claude: DE distribution table mirrored from aux.core.disenchant (plain Lua tables).
-- Returns {id, prob, minQ, maxQ} entries. Empty table = item cannot be DE'd.
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
            add(10940, p(.80,.20), 1,2) ; add(10938, p(.20,.80), 1,2)
        elseif level <= 15 then
            add(10940, p(.75,.20), 2,3) ; add(10939, p(.20,.75), 1,2) ; add(10978, .05, 1,1)
        elseif level <= 20 then
            add(10940, p(.75,.15), 4,6) ; add(10998, p(.15,.75), 1,2) ; add(10978, .10, 1,1)
        elseif level <= 25 then
            add(11083, p(.75,.20), 1,2) ; add(11082, p(.20,.75), 1,2) ; add(11084, .05, 1,1)
        elseif level <= 30 then
            add(11083, p(.75,.20), 2,5) ; add(11134, p(.20,.75), 1,2) ; add(11138, .05, 1,1)
        elseif level <= 35 then
            add(11137, p(.75,.20), 1,2) ; add(11135, p(.20,.75), 1,2) ; add(11139, .05, 1,1)
        elseif level <= 40 then
            add(11137, p(.75,.20), 2,5) ; add(11174, p(.20,.75), 1,2) ; add(11177, .05, 1,1)
        elseif level <= 45 then
            add(11176, p(.75,.20), 1,2) ; add(11175, p(.20,.75), 1,2) ; add(11178, .05, 1,1)
        elseif level <= 50 then
            add(11176, p(.75,.22), 2,5) ; add(16202, p(.20,.75), 1,2) ; add(14343, p(.05,.03), 1,1)
        elseif level <= 55 then
            add(16204, p(.75,.22), 1,2) ; add(16203, p(.20,.75), 1,2) ; add(14344, p(.05,.03), 1,1)
        elseif level <= 60 then
            add(16204, p(.75,.22), 2,5) ; add(16203, p(.20,.75), 2,3) ; add(14344, p(.05,.03), 1,1)
        elseif level <= 65 then
            add(22445, p(.75,.22), 2,3) ; add(22447, p(.22,.75), 2,3) ; add(22448, .03, 1,1)
        elseif level <= 70 then
            add(22445, p(.75,.22), 2,3) ; add(22446, p(.22,.75), 1,2) ; add(22445, p(.03,.03), 2,5)
        elseif level <= 80 then  -- Claude: WotLK approx.
            add(34054, p(.75,.22), 2,4) ; add(34055, p(.22,.75), 1,2) ; add(34052, .03, 1,1)
        end
    elseif quality == 3 then  -- Rare (blue)
        if     level <= 20 then add(10978, 1, 1,1)
        elseif level <= 25 then add(11084, 1, 1,1)
        elseif level <= 30 then add(11138, 1, 1,1)
        elseif level <= 35 then add(11139, 1, 1,1)
        elseif level <= 40 then add(11177, 1, 1,1)
        elseif level <= 45 then add(11178, 1, 1,1)
        elseif level <= 50 then add(14343, 1, 1,1)
        elseif level <= 60 then add(14344, .995, 1,1) ; add(20725, .005, 1,1)
        elseif level <= 65 then add(22448, .995, 1,1) ; add(20725, .005, 1,1)
        elseif level <= 70 then add(22449, .995, 1,1) ; add(20725, .005, 1,1)
        elseif level <= 80 then add(34052, 1, 1,1)  -- Dream Shard
        end
    elseif quality == 4 then  -- Epic (purple)
        if     level <= 40 then add(11177, 1, 2,4)
        elseif level <= 45 then add(11178, 1, 2,4)
        elseif level <= 50 then add(14343, 1, 2,4)
        elseif level <= 60 then add(20725, 1, 1,2)
        elseif level <= 70 then add(22450, 1, 1,2)
        elseif level <= 80 then add(34057, 1, 1,1)
        end
    end
    return D
end

-- Claude: expected DE value via live mat prices for a given source
--         returns 0 if any mat price is missing (to avoid partial calculations)
local function GetDEValue_Live(link, source)
    if not link then return 0 end
    local _, _, quality, ilvl, _, _, _, _, slot = GetItemInfo(link)
    if not quality or not ilvl or not slot then return 0 end

    local dist = QRI_GetDistribution(slot, quality, ilvl)
    if not dist or #dist == 0 then return 0 end

    local total = 0
    for _, entry in ipairs(dist) do
        local matPrice = QRI_GetMatPrice(entry.id, source)
        if not matPrice then return 0 end
        total = total + entry.prob * ((entry.minQ + entry.maxQ) / 2) * matPrice
    end
    return total
end

-- Claude: master DE value dispatcher — routes to correct source per DB config
local function GetDEValue(link)
    local source = DB("source")

    if source == "static" then
        return GetDEValue_Static(link)
    end

    -- Claude: for aux/tsm use live prices only; for auto try live then static fallback
    local val = GetDEValue_Live(link, source)
    if source == "auto" and val == 0 then
        return GetDEValue_Static(link)  -- Claude: auto falls back to static table
    end
    return val
end

-- ─── Vendor Value ─────────────────────────────────────────────────────────────

-- Claude: vendor sell price from GetItemInfo index 11 (3.3.5 return order)
local function GetSellValue(link)
    if not link then return 0 end
    local info = { GetItemInfo(link) }
    return info[11] or 0
end

-- ─── Icon Overlay Frames ──────────────────────────────────────────────────────

local overlays = {}

local function GetIconAnchor(btn)
    local name = btn:GetName()
    return _G[name .. "Icon"] or _G[name .. "IconTexture"]
        or btn:GetNormalTexture() or btn
end

local function GetOrCreate(btn, kind)
    local key = btn:GetName() .. "_" .. kind
    if overlays[key] then return overlays[key] end

    local f = CreateFrame("Frame", nil, btn)
    f:SetFrameLevel(btn:GetFrameLevel() + 10)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f) ; bg:SetTexture(0, 0, 0, 0.8)
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

-- Claude: place and style one icon; winner = large + coloured bg, loser = small + dimmed
local function PlaceIcon(btn, kind, xOffset, isWinner)
    local f    = GetOrCreate(btn, kind)
    local size = isWinner and 18 or 13

    f:SetWidth(size) ; f:SetHeight(size)
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", GetIconAnchor(btn), "TOPRIGHT", xOffset, 0)

    if isWinner then
        f.tex:SetAlpha(1.0)
        if kind == "gold" then
            f.bg:SetVertexColor(0.9, 0.75, 0.0)  -- Claude: yellow for gold winner
        else
            f.bg:SetVertexColor(0.1, 0.2, 0.85)  -- Claude: blue for DE winner
        end
        f.bg:SetAlpha(0.85)
    else
        f.tex:SetAlpha(0.38)
        f.bg:SetVertexColor(0, 0, 0) ; f.bg:SetAlpha(0.7)
    end
    f:Show()
end

-- ─── Main Logic ───────────────────────────────────────────────────────────────

-- Claude: find QuestInfoItemN button for choice slot i
local function FindChoiceButton(i)
    for b = 1, 10 do
        local btn = _G["QuestInfoItem" .. b]
        if btn and btn:IsShown() and btn.type == "choice" and btn:GetID() == i then
            return btn
        end
    end
    local btn = _G["QuestInfoItem" .. i]  -- positional fallback
    if btn and btn:IsShown() then return btn end
end

local function UpdateIcons()
    HideAll()
    local numChoices = GetNumQuestChoices()
    if numChoices < 2 then return end

    local sellVals, deVals = {}, {}
    for i = 1, numChoices do
        local link  = GetQuestItemLink("choice", i)
        sellVals[i] = GetSellValue(link)
        deVals[i]   = GetDEValue(link)
    end

    local bestSellIdx, bestSellVal = 1, sellVals[1] or 0
    local bestDEIdx,   bestDEVal   = 1, deVals[1]   or 0
    for i = 2, numChoices do
        if (sellVals[i] or 0) > bestSellVal then bestSellIdx = i ; bestSellVal = sellVals[i] end
        if (deVals[i]   or 0) > bestDEVal   then bestDEIdx   = i ; bestDEVal   = deVals[i]   end
    end

    -- Claude: gold wins overall when its value exceeds DE by at least goldThreshold
    local goldWins = (bestSellVal >= bestDEVal + DB("goldThreshold"))

    for i = 1, numChoices do
        local btn      = FindChoiceButton(i)
        if not btn then break end
        local showGold = (i == bestSellIdx) and (bestSellVal > 0)
        local showDE   = (i == bestDEIdx)   and (bestDEVal   > 0)

        if showGold and showDE then
            PlaceIcon(btn, "gold", 0,       goldWins)
            PlaceIcon(btn, "de",  -(13+2),  not goldWins)
        elseif showGold then
            PlaceIcon(btn, "gold", 0, goldWins)
        elseif showDE then
            PlaceIcon(btn, "de",  0, not goldWins)
        end
    end
end

local function UpdateAfterTick()
    local tick = CreateFrame("Frame")
    tick:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil) ; UpdateIcons()
    end)
end

-- ─── SavedVariables Init ──────────────────────────────────────────────────────

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= "QuestRewardIcons" then return end
    if not QuestRewardIconsDB then QuestRewardIconsDB = {} end
    for k, v in pairs(DEFAULTS) do
        if QuestRewardIconsDB[k] == nil then QuestRewardIconsDB[k] = v end
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

-- ─── Slash Commands ───────────────────────────────────────────────────────────

-- Claude: /qri source <auto|aux|tsm|static>  — choose DE price source
--         /qri threshold <silver>            — gold preference margin
--         /qri                               — show current settings
SLASH_QUESTREWARDICONS1 = "/qri"
SlashCmdList["QUESTREWARDICONS"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)")
    cmd = (cmd or ""):lower() ; arg = (arg or ""):lower()

    if cmd == "source" then
        local valid = { auto=true, aux=true, tsm=true, static=true }
        if valid[arg] then
            QuestRewardIconsDB.source = arg
            QRI_MatPriceCache = {}  -- Claude: clear cache when source changes
            print("|cff00ff00QuestRewardIcons:|r DE price source set to |cffffff00" .. arg .. "|r")
        else
            print("|cff00ff00QuestRewardIcons:|r Valid sources: |cffffff00auto|r, |cffffff00aux|r, |cffffff00tsm|r, |cffffff00static|r")
        end

    elseif cmd == "threshold" then
        local silver = tonumber(arg)
        if silver and silver >= 0 then
            QuestRewardIconsDB.goldThreshold = math.floor(silver * 100)
            print("|cff00ff00QuestRewardIcons:|r Gold threshold set to |cffffff00" .. silver .. "s|r")
        else
            print("|cff00ff00QuestRewardIcons:|r Usage: /qri threshold <silver>  (e.g. 30)")
        end

    else
        local src    = DB("source")
        local thresh = DB("goldThreshold") / 100
        print("|cff00ff00QuestRewardIcons|r")
        print("  DE source  : |cffffff00" .. src    .. "|r  — /qri source <auto|aux|tsm|static>")
        print("  Gold margin: |cffffff00" .. thresh .. "s|r — /qri threshold <silver>")
        print("  Sources: auto = Aux→TSM→Static; aux/tsm = live only; static = table only")
    end
end

-- ─── Hooks & Events ───────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:SetScript("OnEvent", UpdateAfterTick)

hooksecurefunc("QuestInfo_Display", UpdateIcons)
