-- EpogArmoryUI.lua
-- in-game UI for EpogArmoryDB:
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

-- map each slotID to the Blizzard empty-slot texture name.
-- Used as the dim background showing which slot is which when empty.
local SLOT_BG_MAP = {
    [1]="Head", [2]="Neck", [3]="Shoulder", [4]="Shirt", [5]="Chest",
    [6]="Waist", [7]="Legs", [8]="Feet", [9]="Wrist", [10]="Hands",
    [11]="Finger", [12]="Finger", [13]="Trinket", [14]="Trinket",
    [15]="Back", [16]="MainHand", [17]="SecondaryHand", [18]="Ranged", [19]="Tabard",
}

-- Two-column paperdoll layout: 8 slots left, 8 slots right, 3 weapons bottom.
-- All TOP-anchored rows shifted by -30 vs original to make room for the
-- spec-switcher button row at y=-82 (added in v0.13). Bottom weapons are
-- unchanged (anchored to frame bottom).
local SLOT_POS = {
    [1]  = { "TOPLEFT",   15, -120 }, -- Head
    [2]  = { "TOPLEFT",   15, -164 }, -- Neck
    [3]  = { "TOPLEFT",   15, -208 }, -- Shoulder
    [15] = { "TOPLEFT",   15, -252 }, -- Back
    [5]  = { "TOPLEFT",   15, -296 }, -- Chest
    [4]  = { "TOPLEFT",   15, -340 }, -- Shirt
    [19] = { "TOPLEFT",   15, -384 }, -- Tabard
    [9]  = { "TOPLEFT",   15, -428 }, -- Wrist
    [10] = { "TOPRIGHT", -15, -120 }, -- Hands
    [6]  = { "TOPRIGHT", -15, -164 }, -- Waist
    [7]  = { "TOPRIGHT", -15, -208 }, -- Legs
    [8]  = { "TOPRIGHT", -15, -252 }, -- Feet
    [11] = { "TOPRIGHT", -15, -296 }, -- Finger 1
    [12] = { "TOPRIGHT", -15, -340 }, -- Finger 2
    [13] = { "TOPRIGHT", -15, -384 }, -- Trinket 1
    [14] = { "TOPRIGHT", -15, -428 }, -- Trinket 2
    [16] = { "BOTTOMLEFT",  55, 20 }, -- Main Hand
    [17] = { "BOTTOM",       0, 20 }, -- Off Hand
    [18] = { "BOTTOMRIGHT", -55, 20 }, -- Ranged
}

-- Fallback tree names, used only when a stored player record has no
-- player.tabNames (pre-v0.17 scans, or a scanner that couldn't read tab
-- names for some reason). v0.17+ sends real tab names on the wire from
-- GetTalentTabInfo, so this map's ordering only matters for un-rescanned
-- legacy entries. ROGUE is listed in Ascension's actual server order
-- (Combat, Assassination, Subtlety) since Ascension reorders it vs retail.
-- Other classes: retail WotLK order. If any turn out to be reordered on
-- Ascension, they'll self-correct on first v0.17 scan anyway.
local SPEC_TREE = {
    DEATHKNIGHT = {"Blood", "Frost", "Unholy"},
    DRUID       = {"Balance", "Feral", "Restoration"},
    HUNTER      = {"Beast Mastery", "Marksmanship", "Survival"},
    MAGE        = {"Arcane", "Fire", "Frost"},
    PALADIN     = {"Holy", "Protection", "Retribution"},
    PRIEST      = {"Discipline", "Holy", "Shadow"},
    ROGUE       = {"Combat", "Assassination", "Subtlety"},
    SHAMAN      = {"Elemental", "Enhancement", "Restoration"},
    WARLOCK     = {"Affliction", "Demonology", "Destruction"},
    WARRIOR     = {"Arms", "Fury", "Protection"},
}

-- Resolve the 3-tree name array for a player: prefer the per-player names
-- captured on the wire (v0.17+), fall back to the class map above.
local function ResolveTrees(player)
    if player.tabNames and player.tabNames[1] and player.tabNames[1] ~= "" then
        return player.tabNames
    end
    return SPEC_TREE[player.class or ""]
end

local function FormatAge(unixTime)
    local d = time() - (unixTime or 0)
    if d < 0 then d = 0 end
    if d < 60 then return string.format("%ds ago", d) end
    if d < 3600 then return string.format("%dm ago", math.floor(d / 60)) end
    if d < 86400 then return string.format("%dh ago", math.floor(d / 3600)) end
    return string.format("%dd ago", math.floor(d / 86400))
end

local function FormatSpec(trees, spec)
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

-- hidden tooltip used to force the client to cache item data for
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
            -- Check if the client has resolved this itemID yet. If not,
            -- SetHyperlink would show a half-empty tooltip; show a friendly
            -- "Loading..." placeholder instead and trigger the fetch.
            local iid = tonumber(self.itemString:match("^(%d+)"))
            local resolved = iid and GetItemInfo(iid)
            if resolved then
                GameTooltip:SetHyperlink("item:" .. self.itemString)
            else
                GameTooltip:SetText(SLOT_LABELS[self.slotID] or "?")
                GameTooltip:AddLine("|cffffdd44Loading item info...|r", 1, 1, 0.3)
                GameTooltip:AddLine("Hover again in a moment.", 0.7, 0.7, 0.7)
                -- Kick off the fetch via hidden tooltip; the cache will
                -- populate over the next ~1s and next hover will succeed.
                if iid then
                    cacheTip:ClearLines()
                    cacheTip:SetHyperlink("item:" .. iid)
                    cacheTip:Hide()
                end
            end
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

-- Forward declarations: defined later in the file but referenced by OnClick
-- / OnShow / OnDragStop closures inside BuildInspectFrame / BuildBrowser.
-- Lua 5.1 resolves unresolved names in closures at compile time, so without
-- the forward `local`, these would bind to globals (= nil at runtime).
local RenderActiveSet
local RefreshIcons
local BackToBrowser     -- inspect → browser navigation (Back button)
local OpenInspectFor    -- browser row → inspect navigation (swaps in place)
local SaveFramePosition -- write frame position to SavedVariables on drag-stop
local ApplySavedPosition-- read frame position from SavedVariables on show

-- Confirmation popup for the Delete button. The deleted entry is gone from
-- THIS client's DB only; any peer with it still holds their copy, and a
-- future scan will refill ours. Clearing lastScanned[guid] (done inside
-- EpogArmory.DeletePlayer) also opens our 24h mesh-dedup gate immediately.
StaticPopupDialogs["EPOGARMORY_CONFIRM_DELETE"] = {
    text = "Delete %s from your local armory DB?\n\nThe mesh will refill this player on the next scan from any peer.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local guid = self.data
        if _G.EpogArmory and _G.EpogArmory.DeletePlayer then
            _G.EpogArmory.DeletePlayer(guid)
        end
        if BackToBrowser then BackToBrowser() end
        if browserFrame and browserFrame.Refresh then browserFrame.Refresh() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function BuildInspectFrame()
    local f = CreateFrame("Frame", "EpogArmoryInspectFrame", UIParent)
    -- Width 320 matches the browser frame so swapping between them feels
    -- like one unified window. Height 540 is unchanged from v0.13.
    f:SetWidth(320); f:SetHeight(540)
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
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveFramePosition(self) end)
    f:SetScript("OnShow", function(self) ApplySavedPosition(self) end)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16)
    f.title:SetText("EpogArmory")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Back button: returns to the browser list (preserving the frame's
    -- on-screen position so it feels like one unified window with two views).
    local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    back:SetWidth(52); back:SetHeight(20)
    back:SetPoint("TOPLEFT", 14, -15)
    back:SetText("Back")
    back:SetScript("OnClick", function() BackToBrowser() end)
    f.back = back

    -- Delete button: removes the currently-viewed player from this client's
    -- local DB. Stacked directly below Back (same width) so it doesn't
    -- crowd the header row. Red-tinted text to signal destructive action;
    -- confirmation popup prevents accidental clicks.
    local delete = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    delete:SetWidth(52); delete:SetHeight(20)
    delete:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -4)
    delete:SetText("Delete")
    local dtext = delete:GetFontString()
    if dtext then dtext:SetTextColor(1, 0.4, 0.4) end
    delete:SetScript("OnClick", function()
        if not f.activePlayer then return end
        local p = f.activePlayer
        local dialog = StaticPopup_Show("EPOGARMORY_CONFIRM_DELETE", p.name or "?")
        if dialog then dialog.data = p.guid end
    end)
    f.delete = delete

    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.nameText:SetPoint("TOP", 0, -42)

    f.metaText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.metaText:SetPoint("TOP", 0, -62)
    f.metaText:SetWidth(270)
    f.metaText:SetJustifyH("CENTER")

    -- Spec switcher: 3 buttons between the meta text and the first slot row.
    -- Each button toggles which talent-group's set is rendered in the slots.
    -- Empty sets (no scan yet for that group) keep their button disabled.
    f.specBtns = {}
    for g = 1, 3 do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        -- Width 90 fits the longest class-tree names ("Assassination",
        -- "Beast Mastery", "Marksmanship"). RenderActiveSet sets the text.
        b:SetWidth(90)
        b:SetHeight(20)
        b:SetPoint("TOP", f, "TOP", (g - 2) * 94, -82)
        b:SetText("Tree " .. g)
        b:SetScript("OnClick", function()
            if f.activePlayer and RenderActiveSet then
                f.activeGroup = g
                RenderActiveSet()
                -- Re-render icons for the newly-selected set. Any uncached
                -- items get picked up by the ticker loop started in ShowInspect;
                -- we don't need to restart the ticker here.
                RefreshIcons()
            end
        end)
        f.specBtns[g] = b
    end

    f.slots = {}
    for slotID, pos in pairs(SLOT_POS) do
        local btn = MakeSlotButton(f, slotID)
        btn:SetPoint(pos[1], f, pos[1], pos[2], pos[3])
        f.slots[slotID] = btn
    end

    -- Centerpiece: class icon above, spec icon below. Fills the empty space
    -- between the two slot columns so the frame feels less sparse.
    f.classIcon = f:CreateTexture(nil, "ARTWORK")
    f.classIcon:SetWidth(64); f.classIcon:SetHeight(64)
    f.classIcon:SetPoint("TOP", f, "TOP", 0, -220)
    f.classIconLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.classIconLabel:SetPoint("TOP", f.classIcon, "BOTTOM", 0, -2)

    f.specIcon = f:CreateTexture(nil, "ARTWORK")
    f.specIcon:SetWidth(56); f.specIcon:SetHeight(56)
    f.specIcon:SetPoint("TOP", f.classIconLabel, "BOTTOM", 0, -10)
    -- Keep icons visually tidy by cropping Blizzard's built-in border pixels
    f.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.specIconLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.specIconLabel:SetPoint("TOP", f.specIcon, "BOTTOM", 0, -2)

    tinsert(UISpecialFrames, "EpogArmoryInspectFrame")
    return f
end

-- (forward-declared above BuildInspectFrame)
function RefreshIcons()
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

-- Pick the talent group with the most recent scan — used as the default
-- displayed set when the inspect window opens.
local function FindLatestGroup(player)
    if not (player and player.sets) then return 1 end
    local latestGroup, latestTime = nil, 0
    for g, s in pairs(player.sets) do
        if (s.scanTime or 0) > latestTime then
            latestGroup, latestTime = g, s.scanTime or 0
        end
    end
    return latestGroup or 1
end

-- Render whichever player + talent group is currently marked active on the
-- inspect frame. Called on initial open AND every time a spec button is
-- clicked. All the rendering logic lives here so the spec-switcher only has
-- to flip `inspectFrame.activeGroup` and call this.
RenderActiveSet = function()
    if not inspectFrame or not inspectFrame.activePlayer then return end
    local player = inspectFrame.activePlayer
    local group  = inspectFrame.activeGroup or 1
    local set    = (player.sets and player.sets[group]) or nil

    -- Fallback: if this group has no set (shouldn't happen for the default
    -- since we pick FindLatestGroup), use the top-level mirror so the frame
    -- still renders rather than going blank.
    local spec      = (set and set.spec)      or player.spec     or {0,0,0}
    local gear      = (set and set.gear)      or player.gear     or {}
    local scanTime  = (set and set.scanTime)  or player.scanTime or 0
    local zone      = (set and set.zone)      or player.zone     or ""
    local scannedBy = (set and set.scannedBy) or player.scannedBy or "?"

    local cls = player.class or ""
    local c = (RAID_CLASS_COLORS or {})[cls]
    if c then
        inspectFrame.nameText:SetTextColor(c.r, c.g, c.b)
    else
        inspectFrame.nameText:SetTextColor(1, 1, 1)
    end
    inspectFrame.nameText:SetText(string.format("%s  (L%d %s)",
        player.name or "?", player.level or 0, cls))

    -- Prefer per-player tab names (v0.17+ wire field) over the hardcoded
    -- SPEC_TREE fallback. This makes Ascension's reordered tabs (e.g.
    -- rogue Combat/Assassination/Subtlety) render correctly.
    local classTrees = ResolveTrees(player)

    local specText = FormatSpec(classTrees, spec)
    local line2 = string.format("Scanned %s [%s] by %s",
        FormatAge(scanTime), zone, scannedBy)
    if specText ~= "" then
        inspectFrame.metaText:SetText(specText .. "\n" .. line2)
    else
        inspectFrame.metaText:SetText(line2)
    end

    -- Spec buttons: label = class tree name. Empty trees (no scan) are
    -- dimmed + disabled. Active tree is highlighted.
    for g = 1, 3 do
        local b = inspectFrame.specBtns and inspectFrame.specBtns[g]
        if b then
            local label = (classTrees and classTrees[g]) or ("Tree " .. g)
            b:SetText(label)
            local hasSet = player.sets and player.sets[g] ~= nil
            if hasSet then
                b:Enable()
                b:SetAlpha(1.0)
            else
                b:Disable()
                b:SetAlpha(0.4)
            end
            if g == group then b:LockHighlight() else b:UnlockHighlight() end
        end
    end

    for slotID, btn in pairs(inspectFrame.slots) do
        btn.itemString = gear[slotID] or ""
        btn.link = nil
    end

    -- Centerpiece icons. Class icon uses the built-in atlas with per-class
    -- UV coords; spec icon uses the tab's iconTexture captured at scan time
    -- (player.tabIcons, v0.18+). Falls back to blank textures if the data
    -- isn't available yet.
    if inspectFrame.classIcon then
        local tc = (CLASS_ICON_TCOORDS or {})[cls]
        if tc then
            inspectFrame.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            inspectFrame.classIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            inspectFrame.classIcon:Show()
        else
            inspectFrame.classIcon:SetTexture(nil)
            inspectFrame.classIcon:Hide()
        end
        -- Class label below the class icon, e.g. "Rogue"
        local niceClass = cls:sub(1,1):upper() .. cls:sub(2):lower()
        inspectFrame.classIconLabel:SetText(niceClass)
    end
    if inspectFrame.specIcon then
        local iconPath = player.tabIcons and player.tabIcons[group]
        if iconPath and iconPath ~= "" then
            inspectFrame.specIcon:SetTexture(iconPath)
            inspectFrame.specIcon:Show()
        else
            inspectFrame.specIcon:SetTexture(nil)
            inspectFrame.specIcon:Hide()
        end
        -- Spec label below the spec icon, e.g. "Combat"
        local treeName = classTrees and classTrees[group] or ""
        inspectFrame.specIconLabel:SetText(treeName)
    end
end

local function ShowInspect(player, group)
    if not inspectFrame then inspectFrame = BuildInspectFrame() end
    inspectFrame.activePlayer = player
    inspectFrame.activeGroup  = group or FindLatestGroup(player)

    RenderActiveSet()

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

-- Browser + inspect share the same size (320x540) and swap in place so
-- navigating between them feels like one unified frame with two views.
local BROWSER_ROWS = 24
local BROWSER_ROW_HEIGHT = 18

local function BuildBrowser()
    local f = CreateFrame("Frame", "EpogArmoryBrowserFrame", UIParent)
    f:SetWidth(320); f:SetHeight(540)
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
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveFramePosition(self) end)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16)
    f.title:SetText("EpogArmory")

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
            if self.player and OpenInspectFor then OpenInspectFor(self.player) end
        end)

        f.rows[i] = row
    end

    f.countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.countLabel:SetPoint("BOTTOM", 0, 18)

    -- First-time / empty-DB hint. Shown only when the user has nothing
    -- stored yet. Sits over the scroll frame area so it reads as "here's
    -- where your data will appear" rather than a random floating message.
    f.emptyHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.emptyHint:SetPoint("TOP", scroll, "TOP", 0, -40)
    f.emptyHint:SetWidth(260)
    f.emptyHint:SetJustifyH("CENTER")
    f.emptyHint:SetText("No players stored yet.\n\n|cffaaaaaaJoin a group in a dungeon or raid — this client will inspect groupmates and store their gear here. Or type|r |cffffaa44/epogarmory show <name>|r |cffaaaaaaif you've scanned someone already.|r")
    f.emptyHint:Hide()

    -- Pick an age-tinted color for a given scanTime. Green = fresh (<1h),
    -- yellow = today (<24h), gray = stale. Helps the user spot which
    -- entries are worth trusting at a glance.
    local function AgeColor(t)
        local d = time() - (t or 0)
        if d < 3600 then return "|cff00ff55" end   -- fresh green
        if d < 86400 then return "|cffffdd44" end  -- today yellow
        return "|cff888888"                         -- stale gray
    end

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
                local ageColor = AgeColor(p.scanTime)
                row.text:SetText(string.format("%s%s|r  |cff888888L%d %s|r  %s%s|r",
                    colorStr, p.name or "?", p.level or 0, p.class or "", ageColor, age))
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
        if total == 0 then
            f.emptyHint:Show()
            f.countLabel:SetText("")
        else
            f.emptyHint:Hide()
            if #list == total then
                f.countLabel:SetText(string.format("%d players stored", total))
            else
                f.countLabel:SetText(string.format("%d of %d match", #list, total))
            end
        end
    end

    scroll:SetScript("OnVerticalScroll", function(self, o)
        FauxScrollFrame_OnVerticalScroll(self, o, BROWSER_ROW_HEIGHT, Update)
    end)
    search:SetScript("OnTextChanged", Update)
    f:SetScript("OnShow", function(self) ApplySavedPosition(self); Update() end)

    f.Refresh = Update

    tinsert(UISpecialFrames, "EpogArmoryBrowserFrame")

    -- Auto-refresh when Ingest stores a new scan. Only does work if the
    -- browser is actually visible, so no cost when the window is closed.
    _G.EpogArmory = _G.EpogArmory or {}
    _G.EpogArmory.OnPlayerChanged = function()
        if f:IsShown() and f.Refresh then f.Refresh() end
    end

    return f
end

local function ToggleBrowser()
    if not browserFrame then browserFrame = BuildBrowser() end
    if browserFrame:IsShown() or (inspectFrame and inspectFrame:IsShown()) then
        if browserFrame:IsShown() then browserFrame:Hide() end
        if inspectFrame and inspectFrame:IsShown() then inspectFrame:Hide() end
    else
        browserFrame:Show()
    end
end

-- Copy the on-screen position of one frame to another so the hide/show pair
-- reads as a single frame that changed contents, not two separate frames.
-- WoW stores a frame's position as its first SetPoint tuple; we read that
-- and replay it on the target.
local function CopyFramePosition(src, dst)
    if not (src and dst) then return end
    local p, rel, relP, x, y = src:GetPoint(1)
    if not p then return end
    dst:ClearAllPoints()
    dst:SetPoint(p, rel or UIParent, relP or p, x or 0, y or 0)
end

-- Persist the frame's on-screen position to SavedVariables so dragging
-- survives /reload and logout. Stored as { point, relativePoint, x, y }
-- relative to UIParent. Both browser and inspect read/write the same slot
-- since they're meant to look like one unified frame.
-- (Forward-declared above so OnDragStop / OnShow closures inside the Build
-- functions can resolve the upvalue at compile time.)
SaveFramePosition = function(frame)
    if not frame then return end
    local p, _, rp, x, y = frame:GetPoint(1)
    if not p then return end
    EpogArmoryDB = EpogArmoryDB or {}
    EpogArmoryDB.config = EpogArmoryDB.config or {}
    EpogArmoryDB.config.framePos = { p, rp or p, x or 0, y or 0 }
end

ApplySavedPosition = function(frame)
    if not frame then return end
    local fp = EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.framePos
    if not fp then return end
    frame:ClearAllPoints()
    frame:SetPoint(fp[1], UIParent, fp[2], fp[3], fp[4])
end

-- Inspect → browser (the Back button on the inspect frame).
BackToBrowser = function()
    if not browserFrame then browserFrame = BuildBrowser() end
    if inspectFrame then
        CopyFramePosition(inspectFrame, browserFrame)
        inspectFrame:Hide()
    end
    browserFrame:Show()
end

-- Browser row → inspect. Swap in place, preserving any user drag.
OpenInspectFor = function(player)
    if not inspectFrame then inspectFrame = BuildInspectFrame() end
    if browserFrame and browserFrame:IsShown() then
        CopyFramePosition(browserFrame, inspectFrame)
        browserFrame:Hide()
    end
    ShowInspect(player)
end

-- ---------------- Minimap button ----------------

local MINIMAP_ICON = "Interface\\Icons\\INV_Shield_06"
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

    -- UIDropDownMenu used for the right-click context menu. Created lazily
    -- so we don't pay for the frame allocation on clients that never use it.
    local minimapMenu = CreateFrame("Frame", "EpogArmoryMinimapMenu", UIParent, "UIDropDownMenuTemplate")
    local function InitMinimapMenu(self, level)
        local function add(text, fn, isTitle)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.notCheckable = true   -- 3.3.5: required for plain action items
            if isTitle then
                info.isTitle = true
            else
                info.func = fn
            end
            UIDropDownMenu_AddButton(info, level)
        end
        add("EpogArmory", nil, true)
        add("Open Armory",  function() ToggleBrowser() end)
        add("Status",       function() SlashCmdList["EPOGARMORY"]("status") end)
        add("Toggle Debug", function() SlashCmdList["EPOGARMORY"]("debug") end)
        add("Help",         function() SlashCmdList["EPOGARMORY"]("") end)
        add("Wipe DB",      function() SlashCmdList["EPOGARMORY"]("wipe") end)
        add("Cancel",       function() CloseDropDownMenus() end)
    end

    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            UIDropDownMenu_Initialize(minimapMenu, InitMinimapMenu, "MENU")
            ToggleDropDownMenu(1, nil, minimapMenu, "cursor", 0, 0)
        else
            ToggleBrowser()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("EpogArmory")
        GameTooltip:AddLine("Left-click: open the armory browser", 1, 1, 1)
        GameTooltip:AddLine("Right-click: menu (status, debug, wipe...)", 1, 1, 1)
        GameTooltip:AddLine("Drag: reposition around the minimap", 0.7, 0.7, 0.7)
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
        OpenInspectFor(player)
        return
    elseif lcmd == "browse" or lcmd == "browser" or lcmd == "search" then
        ToggleBrowser()
        return
    end
    if origHandler then origHandler(msg) end
end
