-- EpochArmoryUI.lua
-- Claude: paperdoll-style inspect frame rendering the latest stored snapshot
-- for any player by name, reading from EpochArmoryDB.players[guid]. Hooks
-- into the /epocharmory slash command to add the `show` / `inspect` verb.
--
-- Loaded after EpochArmory.lua (TOC order) so SlashCmdList["EPOCHARMORY"]
-- already exists when this file runs.

local frame = nil
local refreshTicker = nil

local SLOT_LABELS = {
    [1]="Head",[2]="Neck",[3]="Shoulder",[4]="Shirt",[5]="Chest",
    [6]="Waist",[7]="Legs",[8]="Feet",[9]="Wrist",[10]="Hands",
    [11]="Finger 1",[12]="Finger 2",[13]="Trinket 1",[14]="Trinket 2",
    [15]="Back",[16]="Main Hand",[17]="Off Hand",[18]="Ranged",[19]="Tabard",
}

-- Two-column paperdoll layout: 8 slots left, 8 slots right, 3 weapons bottom.
-- {anchorFromFrame, xOffset, yOffset}
local SLOT_POS = {
    [1]  = { "TOPLEFT",   15,  -90 }, -- Head
    [2]  = { "TOPLEFT",   15, -134 }, -- Neck
    [3]  = { "TOPLEFT",   15, -178 }, -- Shoulder
    [15] = { "TOPLEFT",   15, -222 }, -- Back
    [5]  = { "TOPLEFT",   15, -266 }, -- Chest
    [4]  = { "TOPLEFT",   15, -310 }, -- Shirt
    [19] = { "TOPLEFT",   15, -354 }, -- Tabard
    [9]  = { "TOPLEFT",   15, -398 }, -- Wrist
    [10] = { "TOPRIGHT", -15,  -90 }, -- Hands
    [6]  = { "TOPRIGHT", -15, -134 }, -- Waist
    [7]  = { "TOPRIGHT", -15, -178 }, -- Legs
    [8]  = { "TOPRIGHT", -15, -222 }, -- Feet
    [11] = { "TOPRIGHT", -15, -266 }, -- Finger 1
    [12] = { "TOPRIGHT", -15, -310 }, -- Finger 2
    [13] = { "TOPRIGHT", -15, -354 }, -- Trinket 1
    [14] = { "TOPRIGHT", -15, -398 }, -- Trinket 2
    [16] = { "BOTTOMLEFT",  55, 20 }, -- Main Hand
    [17] = { "BOTTOM",       0, 20 }, -- Off Hand
    [18] = { "BOTTOMRIGHT", -55, 20 }, -- Ranged
}

local SPEC_TREE = {
    DEATHKNIGHT = {"Blood", "Frost", "Unholy"},
    DRUID       = {"Balance", "Feral", "Restoration"},
    HUNTER      = {"Beast Mastery", "Marksmanship", "Survival"},
    MAGE        = {"Arcane", "Fire", "Frost"},
    PALADIN     = {"Holy", "Protection", "Retribution"},
    PRIEST      = {"Discipline", "Holy", "Shadow"},
    ROGUE       = {"Assassination", "Combat", "Subtlety"},
    SHAMAN      = {"Elemental", "Enhancement", "Restoration"},
    WARLOCK     = {"Affliction", "Demonology", "Destruction"},
    WARRIOR     = {"Arms", "Fury", "Protection"},
}

local function FormatAge(unixTime)
    local d = time() - (unixTime or 0)
    if d < 0 then d = 0 end
    if d < 60 then return string.format("%ds ago", d) end
    if d < 3600 then return string.format("%dm ago", math.floor(d / 60)) end
    if d < 86400 then return string.format("%dh ago", math.floor(d / 3600)) end
    return string.format("%dd ago", math.floor(d / 86400))
end

local function FormatSpec(class, spec)
    local trees = SPEC_TREE[class or ""]
    if not trees or not spec then return "" end
    local maxIdx, maxVal = 1, spec[1] or 0
    for i = 2, 3 do
        if (spec[i] or 0) > maxVal then maxIdx, maxVal = i, spec[i] or 0 end
    end
    if maxVal == 0 then return "" end
    return string.format("%s %d/%d/%d", trees[maxIdx] or "?",
        spec[1] or 0, spec[2] or 0, spec[3] or 0)
end

local function FindPlayer(name)
    if not name or name == "" then return nil end
    if not EpochArmoryDB or not EpochArmoryDB.players then return nil end
    local low = name:lower()
    for _, p in pairs(EpochArmoryDB.players) do
        if (p.name or ""):lower() == low then return p end
    end
    return nil
end

-- Hidden tooltip used to force the client to cache item data for itemIDs that
-- aren't yet in memory. GetItemInfo returns nil until the client has seen the
-- item; SetHyperlink triggers a background fetch.
local cacheTip = CreateFrame("GameTooltip", "EpochArmoryCacheTip", UIParent, "GameTooltipTemplate")
cacheTip:SetOwner(UIParent, "ANCHOR_NONE")
cacheTip:Hide()

local function MakeSlotButton(parent, slotID)
    local b = CreateFrame("Button", "EpochArmorySlotBtn" .. slotID, parent)
    b:SetWidth(37); b:SetHeight(37)
    b.slotID = slotID

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(0, 0, 0, 0.6)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b.border:SetPoint("TOPLEFT", -3, 3)
    b.border:SetPoint("BOTTOMRIGHT", 3, -3)
    b.border:Hide()

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemString and self.itemString ~= "" then
            GameTooltip:SetHyperlink("item:" .. self.itemString)
        else
            GameTooltip:SetText(SLOT_LABELS[self.slotID] or "?")
            GameTooltip:AddLine("(empty)", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnClick", function(self)
        if self.link and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
            ChatEdit_InsertLink(self.link)
        end
    end)

    return b
end

local function BuildFrame()
    local f = CreateFrame("Frame", "EpochArmoryInspectFrame", UIParent)
    f:SetWidth(280); f:SetHeight(500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16)
    f.title:SetText("EpochArmory")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.nameText:SetPoint("TOP", 0, -42)

    f.metaText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.metaText:SetPoint("TOP", 0, -62)
    f.metaText:SetWidth(260)
    f.metaText:SetJustifyH("CENTER")

    f.slots = {}
    for slotID, pos in pairs(SLOT_POS) do
        local btn = MakeSlotButton(f, slotID)
        btn:SetPoint(pos[1], f, pos[1], pos[2], pos[3])
        f.slots[slotID] = btn
    end

    tinsert(UISpecialFrames, "EpochArmoryInspectFrame")
    return f
end

-- Claude: re-read textures/quality from GetItemInfo. Returns the number of
-- slots still missing data (so the caller can keep polling until they resolve).
local function RefreshIcons()
    if not frame then return 0 end
    local pending = 0
    for _, btn in pairs(frame.slots) do
        local itemString = btn.itemString or ""
        if itemString ~= "" then
            local itemID = tonumber(itemString:match("^(%d+)")) or 0
            local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
            if texture then
                btn.icon:SetTexture(texture)
                btn.link = link
                if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                    local c = ITEM_QUALITY_COLORS[quality]
                    btn.border:SetVertexColor(c.r, c.g, c.b, 0.85)
                    btn.border:Show()
                else
                    btn.border:Hide()
                end
            else
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                btn.border:Hide()
                pending = pending + 1
                -- Trigger client-side fetch so it lands in the cache.
                cacheTip:ClearLines()
                cacheTip:SetHyperlink("item:" .. itemString)
                cacheTip:Hide()
            end
        else
            btn.icon:SetTexture(nil)
            btn.link = nil
            btn.border:Hide()
        end
    end
    return pending
end

local function Show(player)
    if not frame then frame = BuildFrame() end

    local cls = player.class or ""
    local colors = RAID_CLASS_COLORS or {}
    local c = colors[cls]
    if c then
        frame.nameText:SetTextColor(c.r, c.g, c.b)
    else
        frame.nameText:SetTextColor(1, 1, 1)
    end
    frame.nameText:SetText(string.format("%s  (L%d %s)",
        player.name or "?", player.level or 0, cls))

    local spec = FormatSpec(cls, player.spec)
    local line2 = string.format("Scanned %s [%s]  by %s",
        FormatAge(player.scanTime), player.zone or "?", player.scannedBy or "?")
    if spec ~= "" then
        frame.metaText:SetText(spec .. "\n" .. line2)
    else
        frame.metaText:SetText(line2)
    end

    for slotID, btn in pairs(frame.slots) do
        btn.itemString = (player.gear or {})[slotID] or ""
        btn.link = nil
    end

    local pending = RefreshIcons()
    frame:Show()

    -- Deferred re-refresh while items resolve in the client cache.
    -- 3.3.5 has no GET_ITEM_INFO_RECEIVED event, so poll GetItemInfo.
    if refreshTicker then refreshTicker:SetScript("OnUpdate", nil) end
    if pending > 0 then
        refreshTicker = refreshTicker or CreateFrame("Frame")
        refreshTicker.acc = 0
        refreshTicker.total = 0
        refreshTicker:SetScript("OnUpdate", function(self, e)
            self.acc = self.acc + e
            self.total = self.total + e
            if self.acc < 0.3 then return end
            self.acc = 0
            local p = RefreshIcons()
            if p == 0 or self.total > 4 then self:SetScript("OnUpdate", nil) end
        end)
    end
end

-- Hook the existing /epocharmory handler to add `show` / `inspect` verbs.
local origHandler = SlashCmdList["EPOCHARMORY"]
SlashCmdList["EPOCHARMORY"] = function(msg)
    msg = msg or ""
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    local lcmd = (cmd or ""):lower()
    if lcmd == "show" or lcmd == "inspect" then
        local name = (arg and arg ~= "") and arg or (UnitName("target") or "")
        if name == "" then
            print("|cffffaa44EpArmr|r: usage — /epocharmory show <name>  (or target a player first)")
            return
        end
        local player = FindPlayer(name)
        if not player then
            print(string.format("|cffffaa44EpArmr|r: no stored snapshot for '%s'", name))
            return
        end
        Show(player)
        return
    end
    if origHandler then origHandler(msg) end
end
