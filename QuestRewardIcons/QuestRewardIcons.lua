-- QuestRewardIcons.lua
-- Claude: addon that overlays gold-coin and disenchant icons on quest choice items,
--         highlighting the best pick based on vendor sell price vs expected DE value.
--         Gold wins if its value is >= DE value + GOLD_THRESHOLD (default 30s).

local GOLD_THRESHOLD = 3000  -- Claude: 30s in copper; gold wins ties within this margin

local ICON_GOLD = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_DE   = "Interface\\Icons\\Ability_TradeskillEnchanting"

-- Claude: expected DE value in copper, by [quality][ilvl bracket]
-- quality: 2=Uncommon, 3=Rare, 4=Epic  (whites and greys can't be DE'd)
-- Adjust values here to match your server's enchanting mat prices.
local DE_VALUES = {
    [2] = {  -- Uncommon (green)
        { max =  15, val =  1500 },  -- Strange Dust          ~15s
        { max =  25, val =  3000 },  -- Soul Dust             ~30s
        { max =  35, val =  5000 },  -- Vision Dust           ~50s
        { max =  45, val = 12000 },  -- Dream Dust            ~1.2g
        { max =  51, val = 25000 },  -- Illusion Dust         ~2.5g
        { max =  57, val = 40000 },  -- Illusion Dust/GEE     ~4g
        { max =  65, val = 70000 },  -- Greater Eternal Ess.  ~7g
        { max = 999, val = 25000 },  -- Infinite Dust (WotLK) ~2.5g
    },
    [3] = {  -- Rare (blue)
        { max =  25, val =  15000 },  -- Small Radiant Shard  ~1.5g
        { max =  35, val =  30000 },  -- Large Radiant Shard  ~3g
        { max =  50, val =  60000 },  -- Large Brilliant Shard~6g
        { max =  60, val = 150000 },  -- Large Brilliant Shard~15g
        { max =  70, val = 250000 },  -- Void Crystal         ~25g
        { max = 999, val = 400000 },  -- Abyss Crystal        ~40g
    },
    [4] = {  -- Epic (purple)
        { max =  60, val =  300000 },  -- ~30g
        { max =  70, val =  800000 },  -- ~80g
        { max = 999, val = 1500000 },  -- ~150g
    },
}

-- Claude: icon overlay frames, keyed by "QuestInfoItemN_gold" / "QuestInfoItemN_de"
local overlays = {}

-- Claude: look up expected DE value from static table
local function GetDEValue(link)
    if not link then return 0 end
    local _, _, quality, ilvl = GetItemInfo(link)
    if not quality or not ilvl then return 0 end
    local tbl = DE_VALUES[quality]
    if not tbl then return 0 end
    for _, row in ipairs(tbl) do
        if ilvl <= row.max then return row.val end
    end
    return 0
end

-- Claude: get vendor sell price from GetItemInfo (index 11 in 3.3.5)
local function GetSellValue(link)
    if not link then return 0 end
    local info = { GetItemInfo(link) }
    return info[11] or 0
end

-- Claude: find the item icon frame/texture to use as position anchor
local function GetIconAnchor(btn)
    local name = btn:GetName()
    return _G[name .. "Icon"]
        or _G[name .. "IconTexture"]
        or btn:GetNormalTexture()
        or btn
end

-- Claude: get or create an overlay icon frame parented to a quest item button
local function GetOrCreate(btn, kind)
    local key = btn:GetName() .. "_" .. kind
    if overlays[key] then return overlays[key] end

    local f = CreateFrame("Frame", nil, btn)
    f:SetFrameLevel(btn:GetFrameLevel() + 10)

    -- dark background for contrast
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0, 0, 0, 0.8)
    f.bg = bg

    -- icon texture (gold coin or enchanting symbol)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -1)
    tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    tex:SetTexture(kind == "gold" and ICON_GOLD or ICON_DE)
    f.tex = tex

    overlays[key] = f
    return f
end

-- Claude: hide every overlay (called before each redraw)
local function HideAll()
    for _, f in pairs(overlays) do
        f:Hide()
    end
end

-- Claude: place and style one icon on a button
--   kind      = "gold" or "de"
--   xOffset   = horizontal shift (used to stack two icons on the same button)
--   isWinner  = true → large + bright; false → small + dimmed
local function PlaceIcon(btn, kind, xOffset, isWinner)
    local f    = GetOrCreate(btn, kind)
    local size = isWinner and 18 or 13

    f:SetWidth(size)
    f:SetHeight(size)
    f:ClearAllPoints()

    -- Claude: anchor to top-right of the item icon texture
    local anchor = GetIconAnchor(btn)
    f:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", xOffset, 0)

    if isWinner then
        -- Claude: winner: full alpha, coloured background (gold=yellow, de=blue)
        f.tex:SetAlpha(1.0)
        if kind == "gold" then
            f.bg:SetVertexColor(0.9, 0.75, 0.0)
        else
            f.bg:SetVertexColor(0.1, 0.2, 0.85)
        end
        f.bg:SetAlpha(0.85)
    else
        -- Claude: loser: dimmed, neutral background
        f.tex:SetAlpha(0.38)
        f.bg:SetVertexColor(0, 0, 0)
        f.bg:SetAlpha(0.7)
    end

    f:Show()
end

-- Claude: find the QuestInfoItemN button that corresponds to choice slot i.
--   Blizzard sets button.type = "choice" and button:GetID() = i on each button.
--   Falls back to positional order (choice items fill buttons 1..N first).
local function FindChoiceButton(i)
    for b = 1, 10 do
        local btn = _G["QuestInfoItem" .. b]
        if btn and btn:IsShown()
           and btn.type == "choice" and btn:GetID() == i then
            return btn
        end
    end
    -- Claude: fallback if .type is not set — assume choices occupy first N buttons
    local btn = _G["QuestInfoItem" .. i]
    if btn and btn:IsShown() then return btn end
end

-- Claude: main update — compute vendor/DE values, find winners, place icons
local function UpdateIcons()
    HideAll()

    local numChoices = GetNumQuestChoices()
    if numChoices < 2 then return end  -- nothing to compare

    -- Claude: gather values for every choice item
    local sellVals = {}
    local deVals   = {}
    for i = 1, numChoices do
        local link  = GetQuestItemLink("choice", i)
        sellVals[i] = GetSellValue(link)
        deVals[i]   = GetDEValue(link)
    end

    -- Claude: find the index with highest vendor value and highest DE value
    local bestSellIdx, bestSellVal = 1, sellVals[1] or 0
    local bestDEIdx,   bestDEVal   = 1, deVals[1]   or 0
    for i = 2, numChoices do
        if (sellVals[i] or 0) > bestSellVal then
            bestSellIdx = i
            bestSellVal = sellVals[i]
        end
        if (deVals[i] or 0) > bestDEVal then
            bestDEIdx = i
            bestDEVal = deVals[i]
        end
    end

    -- Claude: gold is the overall winner when its value exceeds DE by at least GOLD_THRESHOLD
    local goldWins = (bestSellVal >= bestDEVal + GOLD_THRESHOLD)

    -- Claude: place icons on each relevant button
    for i = 1, numChoices do
        local btn = FindChoiceButton(i)
        if not btn then break end

        local showGold = (i == bestSellIdx) and (bestSellVal > 0)
        local showDE   = (i == bestDEIdx)   and (bestDEVal   > 0)

        if showGold and showDE then
            -- Claude: both icons on same button — stack side by side, winner left-most
            PlaceIcon(btn, "gold", 0,  goldWins)
            PlaceIcon(btn, "de",  -(13 + 2), not goldWins)  -- Claude: 13px + 2px gap
        elseif showGold then
            PlaceIcon(btn, "gold", 0, goldWins)
        elseif showDE then
            PlaceIcon(btn, "de",  0, not goldWins)
        end
    end
end

-- Claude: defer one frame after event so Blizzard has finished populating the UI
local function UpdateAfterTick()
    local tick = CreateFrame("Frame")
    tick:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        UpdateIcons()
    end)
end

-- Claude: register events that open the quest reward frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:SetScript("OnEvent", UpdateAfterTick)

-- Claude: also hook QuestInfo_Display for cases where the frame redraws
--         without firing an event (e.g. scrolling between quest NPCs)
hooksecurefunc("QuestInfo_Display", UpdateIcons)
