-- EpogArmoryUI.lua
-- Claude: in-game UI for EpogArmoryDB:
--   * Paperdoll inspect frame for a single stored player (/epogarmory show)
--   * Browser frame with search-filtered list of all stored players
--   * Minimap button that toggles the browser
--
-- Loaded after EpogArmory.lua (TOC order) so SlashCmdList["EPOGARMORY"]
-- already exists when this file runs.

local inspectFrame = nil
local browserFrame = nil
local refreshTicker = nil

local SLOT_LABELS = {
    [1]="Head",[2]="Neck",[3]="Shoulder",[4]="Shirt",[5]="Chest",
    [6]="Waist",[7]="Legs",[8]="Feet",[9]="Wrist",[10]="Hands",
    [11]="Finger 1",[12]="Finger 2",[13]="Trinket 1",[14]="Trinket 2",
    [15]="Back",[16]="Main Hand",[17]="Off Hand",[18]="Ranged",[19]="Tabard",
}

-- Claude: map each slotID to the Blizzard empty-slot texture name.
-- Used as the dim background showing which slot is which when empty.
local SLOT_BG_MAP = {
    [1]="Head", [2]="Neck", [3]="Shoulder", [4]="Shirt", [5]="Chest",
    [6]="Waist", [7]="Legs", [8]="Feet", [9]="Wrist", [10]="Hands",
    [11]="Finger", [12]="Finger", [13]="Trinket", [14]="Trinket",
    [15]="Back", [16]="MainHand", [17]="SecondaryHand", [18]="Ranged", [19]="Tabard",
}

-- Two-column paperdoll layout: 8 slots left, 8 slots right, 3 weapons bottom.
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

local function ClassColorStr(class)
    local c = (RAID_CLASS_COLORS or {})[class or ""]
    if not c then return "|cffffffff" end
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function FindPlayer(name)
    if not name or name == "" then return nil end
    if not EpogArmoryDB or not EpogArmoryDB.players then return nil end
    local low = name:lower()
    for _, p in pairs(EpogArmoryDB.players) do
        if (p.name or ""):lower() == low then return p end
    end
    return nil
end

-- Claude: hidden tooltip used to force the client to cache item data for
-- uncached itemIDs. GetItemInfo returns nil until the client has seen the
-- item; SetHyperlink triggers the background fetch.
local cacheTip = CreateFrame("GameTooltip", "EpogArmoryCacheTip", UIParent, "GameTooltipTemplate")
cacheTip:SetOwner(UIParent, "ANCHOR_NONE")
cacheTip:Hide()

-- ---------------- Slot button ----------------

local function MakeEdge(parent)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\ChatFrame\\ChatFrameBackground") -- solid white, vertex-color-friendly
    t:Hide()
    return t
end

local function MakeSlotButton(parent, slotID)
    local b = CreateFrame("Button", "EpogArmorySlotBtn" .. slotID, parent)
    b:SetWidth(40); b:SetHeight(40)
    b.slotID = slotID

    -- Slot background: dim empty-slot glyph so users see what each slot is
    -- for, and the icon covers it when equipped.
    b.slotBg = b:CreateTexture(nil, "BACKGROUND")
    b.slotBg:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (SLOT_BG_MAP[slotID] or "Head"))
    b.slotBg:SetAllPoints()
    b.slotBg:SetAlpha(0.55)

    -- Item icon
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Quality border: 4 thin rectangles framing the slot exactly.
    b.bTop = MakeEdge(b)
    b.bTop:SetPoint("TOPLEFT", 0, 0)
    b.bTop:SetPoint("TOPRIGHT", 0, 0)
    b.bTop:SetHeight(2)

    b.bBot = MakeEdge(b)
    b.bBot:SetPoint("BOTTOMLEFT", 0, 0)
    b.bBot:SetPoint("BOTTOMRIGHT", 0, 0)
    b.bBot:SetHeight(2)

    b.bLeft = MakeEdge(b)
    b.bLeft:SetPoint("TOPLEFT", 0, 0)
    b.bLeft:SetPoint("BOTTOMLEFT", 0, 0)
    b.bLeft:SetWidth(2)

    b.bRight = MakeEdge(b)
    b.bRight:SetPoint("TOPRIGHT", 0, 0)
    b.bRight:SetPoint("BOTTOMRIGHT", 0, 0)
    b.bRight:SetWidth(2)

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

local function SetQualityColor(btn, r, g, b, a)
    for _, edge in ipairs({btn.bTop, btn.bBot, btn.bLeft, btn.bRight}) do
        edge:SetVertexColor(r, g, b, a or 1)
        edge:Show()
    end
end

local function HideQualityBorder(btn)
    btn.bTop:Hide(); btn.bBot:Hide(); btn.bLeft:Hide(); btn.bRight:Hide()
end

-- ---------------- Paperdoll inspect frame ----------------

local function BuildInspectFrame()
    local f = CreateFrame("Frame", "EpogArmoryInspectFrame", UIParent)
    f:SetWidth(290); f:SetHeight(500)
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
    f.title:SetText("EpogArmory")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.nameText:SetPoint("TOP", 0, -42)

    f.metaText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.metaText:SetPoint("TOP", 0, -62)
    f.metaText:SetWidth(270)
    f.metaText:SetJustifyH("CENTER")

    f.slots = {}
    for slotID, pos in pairs(SLOT_POS) do
        local btn = MakeSlotButton(f, slotID)
        btn:SetPoint(pos[1], f, pos[1], pos[2], pos[3])
        f.slots[slotID] = btn
    end

    tinsert(UISpecialFrames, "EpogArmoryInspectFrame")
    return f
end

local function RefreshIcons()
    if not inspectFrame then return 0 end
    local pending = 0
    for _, btn in pairs(inspectFrame.slots) do
        local itemString = btn.itemString or ""
        if itemString ~= "" then
            local itemID = tonumber(itemString:match("^(%d+)")) or 0
            local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
            if texture then
                btn.icon:SetTexture(texture)
                btn.slotBg:Hide() -- hide the dim empty-slot glyph
                btn.link = link
                if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                    local c = ITEM_QUALITY_COLORS[quality]
                    SetQualityColor(btn, c.r, c.g, c.b, 1)
                else
                    HideQualityBorder(btn)
                end
            else
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                btn.slotBg:Hide()
                HideQualityBorder(btn)
                pending = pending + 1
                cacheTip:ClearLines()
                cacheTip:SetHyperlink("item:" .. itemString)
                cacheTip:Hide()
            end
        else
            btn.icon:SetTexture(nil)
            btn.slotBg:Show() -- re-show empty-slot glyph
            btn.link = nil
            HideQualityBorder(btn)
        end
    end
    return pending
end

local function ShowInspect(player)
    if not inspectFrame then inspectFrame = BuildInspectFrame() end

    local cls = player.class or ""
    local c = (RAID_CLASS_COLORS or {})[cls]
    if c then
        inspectFrame.nameText:SetTextColor(c.r, c.g, c.b)
    else
        inspectFrame.nameText:SetTextColor(1, 1, 1)
    end
    inspectFrame.nameText:SetText(string.format("%s  (L%d %s)",
        player.name or "?", player.level or 0, cls))

    local spec = FormatSpec(cls, player.spec)
    local line2 = string.format("Scanned %s [%s]  by %s",
        FormatAge(player.scanTime), player.zone or "?", player.scannedBy or "?")
    if spec ~= "" then
        inspectFrame.metaText:SetText(spec .. "\n" .. line2)
    else
        inspectFrame.metaText:SetText(line2)
    end

    for slotID, btn in pairs(inspectFrame.slots) do
        btn.itemString = (player.gear or {})[slotID] or ""
        btn.link = nil
    end

    local pending = RefreshIcons()
    inspectFrame:Show()

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

-- ---------------- Browser frame (searchable list) ----------------

local BROWSER_ROWS = 18
local BROWSER_ROW_HEIGHT = 18

local function BuildBrowser()
    local f = CreateFrame("Frame", "EpogArmoryBrowserFrame", UIParent)
    f:SetWidth(320); f:SetHeight(450)
    f:SetPoint("CENTER", UIParent, "CENTER", -180, 0)
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
    f.title:SetText("EpogArmory Browser")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 22, -46)
    searchLabel:SetText("Search:")

    local search = CreateFrame("EditBox", "EpogArmoryBrowserSearch", f, "InputBoxTemplate")
    search:SetWidth(220); search:SetHeight(20)
    search:SetPoint("TOPLEFT", searchLabel, "TOPRIGHT", 10, 3)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search

    -- Scroll frame
    local scroll = CreateFrame("ScrollFrame", "EpogArmoryBrowserScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -80)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    f.scroll = scroll

    f.rows = {}
    for i = 1, BROWSER_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(BROWSER_ROW_HEIGHT)
        row:SetPoint("LEFT", scroll, "LEFT", 2, 0)
        row:SetPoint("RIGHT", scroll, "RIGHT", -2, 0)
        if i == 1 then
            row:SetPoint("TOP", scroll, "TOP", 0, -2)
        else
            row:SetPoint("TOP", f.rows[i-1], "BOTTOM", 0, 0)
        end

        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")

        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.hl:SetBlendMode("ADD")
        row.hl:SetAlpha(0.5)
        row.hl:SetAllPoints()

        row:SetScript("OnClick", function(self)
            if self.player then ShowInspect(self.player) end
        end)

        f.rows[i] = row
    end

    f.countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.countLabel:SetPoint("BOTTOM", 0, 18)

    local function Update()
        local list = {}
        if EpogArmoryDB and EpogArmoryDB.players then
            local filter = (search:GetText() or ""):lower()
            for _, p in pairs(EpogArmoryDB.players) do
                if p and p.name then
                    if filter == "" or p.name:lower():find(filter, 1, true) then
                        list[#list + 1] = p
                    end
                end
            end
            table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
        end

        FauxScrollFrame_Update(scroll, #list, BROWSER_ROWS, BROWSER_ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(scroll)

        for i = 1, BROWSER_ROWS do
            local row = f.rows[i]
            local p = list[i + offset]
            if p then
                local colorStr = ClassColorStr(p.class)
                local age = FormatAge(p.scanTime)
                row.text:SetText(string.format("%s%s|r  |cff888888L%d %s|r  |cffaaaaaa%s|r",
                    colorStr, p.name or "?", p.level or 0, p.class or "", age))
                row.player = p
                row:Show()
            else
                row:Hide()
                row.player = nil
            end
        end

        local total = 0
        if EpogArmoryDB and EpogArmoryDB.players then
            for _ in pairs(EpogArmoryDB.players) do total = total + 1 end
        end
        if #list == total then
            f.countLabel:SetText(string.format("%d players stored", total))
        else
            f.countLabel:SetText(string.format("%d of %d match", #list, total))
        end
    end

    scroll:SetScript("OnVerticalScroll", function(self, o)
        FauxScrollFrame_OnVerticalScroll(self, o, BROWSER_ROW_HEIGHT, Update)
    end)
    search:SetScript("OnTextChanged", Update)
    f:SetScript("OnShow", Update)

    f.Refresh = Update

    tinsert(UISpecialFrames, "EpogArmoryBrowserFrame")
    return f
end

local function ToggleBrowser()
    if not browserFrame then browserFrame = BuildBrowser() end
    if browserFrame:IsShown() then
        browserFrame:Hide()
    else
        browserFrame:Show()
    end
end

-- ---------------- Minimap button ----------------

local MINIMAP_ICON = "Interface\\Icons\\Achievement_Character_Human_Male"
local minimapBtn

local function UpdateMinimapPos(angle)
    if not minimapBtn then return end
    local radius = 80
    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function BuildMinimapButton()
    if not Minimap then return end
    local b = CreateFrame("Button", "EpogArmoryMinimapButton", Minimap)
    b:SetWidth(32); b:SetHeight(32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetTexture(MINIMAP_ICON)
    b.icon:SetWidth(20); b.icon:SetHeight(20)
    b.icon:SetPoint("CENTER", 0, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.border:SetWidth(54); b.border:SetHeight(54)
    b.border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Right click also toggles for accessibility
            ToggleBrowser()
        else
            ToggleBrowser()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("EpogArmory")
        GameTooltip:AddLine("Click to open the armory browser", 1, 1, 1)
        GameTooltip:AddLine("Drag to reposition around the minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            if not mx then return end
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local dx = px / scale - mx
            local dy = py / scale - my
            local angle = math.atan2(dy, dx)
            EpogArmoryDB = EpogArmoryDB or {}
            EpogArmoryDB.config = EpogArmoryDB.config or {}
            EpogArmoryDB.config.minimapAngle = angle
            UpdateMinimapPos(angle)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return b
end

-- Defer minimap button creation until PLAYER_LOGIN so the config SV is loaded.
local mmInit = CreateFrame("Frame")
mmInit:RegisterEvent("PLAYER_LOGIN")
mmInit:SetScript("OnEvent", function()
    minimapBtn = BuildMinimapButton()
    local angle = (EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.minimapAngle)
        or math.rad(15) -- default near top-right of minimap
    UpdateMinimapPos(angle)
end)

-- ---------------- Slash hook ----------------

local origHandler = SlashCmdList["EPOGARMORY"]
SlashCmdList["EPOGARMORY"] = function(msg)
    msg = msg or ""
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    local lcmd = (cmd or ""):lower()
    if lcmd == "show" or lcmd == "inspect" then
        local name = (arg and arg ~= "") and arg or (UnitName("target") or "")
        if name == "" then
            print("|cffffaa44EpogArmory|r: usage — /epogarmory show <name>  (or target a player first)")
            return
        end
        local player = FindPlayer(name)
        if not player then
            print(string.format("|cffffaa44EpogArmory|r: no stored snapshot for '%s'", name))
            return
        end
        ShowInspect(player)
        return
    elseif lcmd == "browse" or lcmd == "browser" or lcmd == "search" then
        ToggleBrowser()
        return
    end
    if origHandler then origHandler(msg) end
end
