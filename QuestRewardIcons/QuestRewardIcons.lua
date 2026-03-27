-- QuestRewardIcons.lua
-- Claude: overlays gold-coin and disenchant icons on quest choice reward items.
-- DE value is fetched from a configurable source: Aux, TSM, Static, or Auto.
--   Auto (default): tries Aux → TSM per mat, falls back to static bracket table.
--   Aux:    Aux weighted-median history prices only.
--   TSM:    TSM AuctionDB DBMarket prices only.
--   Static: hardcoded copper-value table by quality + ilvl bracket.
-- Gold wins the overall comparison if its value >= DE value + goldThreshold (default 30s).
--
-- Slash: /qri                                        → show current settings
--        /qri source <auto|aux|tsm|static>           → set DE price source
--        /qri threshold <silver>                     → gold preference margin
--        /qri static                                 → list all static bracket values
--        /qri static <green|blue|purple> <ilvl> <g>  → set a bracket (gold decimal, e.g. 4.5)
--        /qri static reset                           → restore static table to addon defaults

-- ─── SavedVariables defaults ──────────────────────────────────────────────────

-- QuestRewardIconsDB = { source = "auto", goldThreshold = 3000 }

local DEFAULTS = { source = "auto", goldThreshold = 3000 }

local function DB(key) -- Claude: safe accessor for SavedVariables with default fallback
    return (QuestRewardIconsDB and QuestRewardIconsDB[key] ~= nil)
           and QuestRewardIconsDB[key] or DEFAULTS[key]
end

-- Claude: deep-copy a nested table (used to seed SavedVariables from DE_STATIC defaults)
local function DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and DeepCopy(v) or v
    end
    return copy
end

-- ─── Icons ────────────────────────────────────────────────────────────────────

local ICON_GOLD = "Interface\\Icons\\INV_Misc_Coin_01"

-- Claude: get the Disenchant spell icon from the game's own spell DB (spell 13262 = Disenchant).
-- Avoids hardcoding a texture path that may not exist on this client.
local _deSpellIcon = select(3, GetSpellInfo(13262))
local ICON_DE = _deSpellIcon or "Interface\\Icons\\INV_Misc_Gem_01"

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

-- Claude: look up static DE value from SavedVariables (editable in-game via /qri static)
local function GetDEValue_Static(link)
    if not link then return 0 end
    local _, _, quality, ilvl = GetItemInfo(link)
    if not quality or not ilvl then return 0 end
    local sv  = QuestRewardIconsDB and QuestRewardIconsDB.staticValues
    local tbl = sv and sv[quality] or DE_STATIC[quality]  -- Claude: fallback to hardcoded if SV missing
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

-- Claude: width of the item icon square in quest reward buttons.
-- Quest item buttons are wide (icon + name text), so we anchor from TOPLEFT
-- using this offset to land inside the icon square, not past the text.
local ICON_BOX_W = 37

local overlays = {}

local function GetOrCreate(btn, kind)
    local key = btn:GetName() .. "_" .. kind
    if overlays[key] then return overlays[key] end

    local f = CreateFrame("Frame", nil, btn)
    f:SetFrameLevel(btn:GetFrameLevel() + 10)

    -- Claude: WHITE8X8 is the reliable 3.3.5 solid-colour texture (used by Aux, HCBreathBar)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAllPoints(f)
    f.bg = bg

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(kind == "gold" and ICON_GOLD or ICON_DE)
    -- Claude: clip the dark rounded outer border WoW bakes into all item/spell icons.
    -- Without this the icon looks dim; Aux uses the same 0.08/0.92 values.
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.tex = tex

    overlays[key] = f
    return f
end

local function HideAll()
    for _, f in pairs(overlays) do f:Hide() end
end

-- Claude: place and style one icon.
--   winner = large (22px), full alpha, bright vertex-colour tint on the icon itself
--   loser  = small (15px), 50% alpha, no tint
--   No coloured bg border — was causing a blue/yellow square when icon texture
--   was missing. Now bg is always a subtle dark backdrop for readability only.
--   stackOffset > 0 shifts the icon left (used when two icons share one button).
local function PlaceIcon(btn, kind, stackOffset, isWinner)
    local f    = GetOrCreate(btn, kind)
    local size = isWinner and 22 or 15

    f:SetWidth(size) ; f:SetHeight(size)
    f:ClearAllPoints()
    -- Claude: anchor inside the 37px icon square at the left of the quest button
    f:SetPoint("TOPLEFT", btn, "TOPLEFT", ICON_BOX_W - size - stackOffset, -1)

    -- Claude: icon always fills the frame — no inset, no coloured bg border
    f.tex:ClearAllPoints()
    f.tex:SetAllPoints(f)

    -- Claude: subtle dark backdrop so icon is readable on any item background
    f.bg:SetVertexColor(0, 0, 0)
    f.bg:SetAlpha(0.45)

    if isWinner then
        f.tex:SetAlpha(1.0)
        if kind == "gold" then
            -- Claude: bright gold tint — makes the coin icon look like actual gold
            f.tex:SetVertexColor(1.0, 0.88, 0.1)
        else
            -- Claude: soft blue-white tint for the DE icon
            f.tex:SetVertexColor(0.75, 0.92, 1.0)
        end
    else
        f.tex:SetAlpha(0.5)
        f.tex:SetVertexColor(1, 1, 1)  -- no tint for losers
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

    -- Claude: start at index 1 — if all values are equal every item ties,
    -- and we correctly mark item 1 for both gold and DE (first = default winner on tie)
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
            -- Claude: both icons on same item — stack side by side with no overlap.
            -- Gold sits at the right, DE shifts left by (goldSize + 2px gap).
            -- Sizes depend on who won overall, so compute dynamically.
            local goldSize = goldWins and 22 or 15  -- Claude: match PlaceIcon winner/loser sizes
            PlaceIcon(btn, "gold", 0,              goldWins)
            PlaceIcon(btn, "de",   goldSize + 2,   not goldWins)
        elseif showGold then
            PlaceIcon(btn, "gold", 0, goldWins)
        elseif showDE then
            PlaceIcon(btn, "de",   0, not goldWins)
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
    -- Claude: seed editable static table from hardcoded defaults on first install
    if not QuestRewardIconsDB.staticValues then
        QuestRewardIconsDB.staticValues = DeepCopy(DE_STATIC)
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

    elseif cmd == "static" then
        -- Claude: quality name → internal quality index
        local QMAP  = { green = 2, blue = 3, purple = 4 }
        local QLBL  = { [2] = "Green", [3] = "Blue", [4] = "Purple" }
        local sv    = QuestRewardIconsDB.staticValues

        local sub, qname, ilvlStr, goldStr = arg:match("^(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
        sub = (sub or ""):lower() ; qname = (qname or ""):lower()

        if sub == "reset" then
            -- Claude: restore all brackets to hardcoded DE_STATIC defaults
            QuestRewardIconsDB.staticValues = DeepCopy(DE_STATIC)
            print("|cff00ff00QuestRewardIcons:|r Static table reset to addon defaults.")

        elseif sub ~= "" and QMAP[sub] then
            -- Claude: /qri static <green|blue|purple> <maxilvl> <gold>
            local q     = QMAP[sub]
            local maxIlvl = tonumber(ilvlStr)
            local gold    = tonumber(goldStr)
            if not maxIlvl or not gold then
                print("|cff00ff00QuestRewardIcons:|r Usage: /qri static <green|blue|purple> <maxilvl> <gold>")
                print("  Example: /qri static green 60 4.5  (sets ilvl≤60 greens to 4g50s)")
            else
                local copper = math.floor(gold * 10000)
                local found  = false
                for _, row in ipairs(sv[q] or {}) do
                    if row.max == maxIlvl then
                        row.val = copper
                        found   = true
                        break
                    end
                end
                if found then
                    print("|cff00ff00QuestRewardIcons:|r " .. QLBL[q]
                          .. " ilvl≤" .. maxIlvl .. " → |cffffff00" .. gold .. "g|r")
                else
                    -- Claude: list valid maxilvl values for this quality
                    local valid = {}
                    for _, row in ipairs(sv[q] or {}) do tinsert(valid, row.max) end
                    print("|cff00ff00QuestRewardIcons:|r No bracket with maxilvl=" .. maxIlvl
                          .. " for " .. QLBL[q] .. ". Valid: " .. table.concat(valid, ", "))
                end
            end

        else
            -- Claude: /qri static — list all brackets with current values
            print("|cff00ff00QuestRewardIcons|r — Static DE table  (edit: /qri static <green|blue|purple> <maxilvl> <gold>)")
            for _, q in ipairs({2, 3, 4}) do
                local parts = {}
                for _, row in ipairs(sv[q] or {}) do
                    local g = string.format("%.2fg", row.val / 10000)
                    tinsert(parts, "ilvl≤" .. row.max .. "=" .. g)
                end
                print("  |cffffff00" .. QLBL[q] .. ":|r " .. table.concat(parts, "  "))
            end
            print("  Reset: /qri static reset")
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
