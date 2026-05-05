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
-- Claude (v1.4.2): inspect frame widened 320→360, slot offsets pushed
-- inward 15→35 / -15→-35 so items have more breathing room outside.
-- Bottom row weapon slots also pushed inward 55→75 / -55→-75 to match.
local SLOT_POS = {
    [1]  = { "TOPLEFT",   35, -120 }, -- Head
    [2]  = { "TOPLEFT",   35, -164 }, -- Neck
    [3]  = { "TOPLEFT",   35, -208 }, -- Shoulder
    [15] = { "TOPLEFT",   35, -252 }, -- Back
    [5]  = { "TOPLEFT",   35, -296 }, -- Chest
    [4]  = { "TOPLEFT",   35, -340 }, -- Shirt
    [19] = { "TOPLEFT",   35, -384 }, -- Tabard
    [9]  = { "TOPLEFT",   35, -428 }, -- Wrist
    [10] = { "TOPRIGHT", -35, -120 }, -- Hands
    [6]  = { "TOPRIGHT", -35, -164 }, -- Waist
    [7]  = { "TOPRIGHT", -35, -208 }, -- Legs
    [8]  = { "TOPRIGHT", -35, -252 }, -- Feet
    [11] = { "TOPRIGHT", -35, -296 }, -- Finger 1
    [12] = { "TOPRIGHT", -35, -340 }, -- Finger 2
    [13] = { "TOPRIGHT", -35, -384 }, -- Trinket 1
    [14] = { "TOPRIGHT", -35, -428 }, -- Trinket 2
    [16] = { "BOTTOMLEFT",  75, 20 }, -- Main Hand
    [17] = { "BOTTOM",       0, 20 }, -- Off Hand
    [18] = { "BOTTOMRIGHT", -75, 20 }, -- Ranged
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

-- Confirmation popup when clicking a Scanner row in the browser. Triggers
-- /epogarmory syncfrom <name> with the default 7-day window. Peers' 1h
-- per-requester cooldown prevents accidental spam.
StaticPopupDialogs["EPOGARMORY_CONFIRM_SYNC"] = {
    text = "Request a sync from %s?\n\nThey'll replay their last 7 days of scans over guild chat. Drain takes ~20 minutes.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local name = self.data
        if name and SlashCmdList and SlashCmdList["EPOGARMORY"] then
            SlashCmdList["EPOGARMORY"]("syncfrom " .. name)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function BuildInspectFrame()
    local f = CreateFrame("Frame", "EpogArmoryInspectFrame", UIParent)
    -- Claude (v1.4.2): widened 320→360 for more breathing room around the
    -- slot icons (slot offsets pushed inward in SLOT_POS). Browser bumped
    -- 320→380 in parallel for the new Guild column. Height 540 unchanged.
    f:SetWidth(360); f:SetHeight(540)
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

    -- v1.3: opens the talent tree side-panel for the active player + spec.
    -- Talent metadata accumulates locally as users self-scan / inspect
    -- each class; when missing, the panel shows a "no metadata yet" hint.
    local talents = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    talents:SetWidth(52); talents:SetHeight(20)
    talents:SetPoint("TOPLEFT", delete, "BOTTOMLEFT", 0, -4)
    talents:SetText("Talents")
    talents:SetScript("OnClick", function()
        if not f.activePlayer then return end
        if _G.EpogArmory_OpenTalentsFor then
            _G.EpogArmory_OpenTalentsFor(f.activePlayer, f.activeGroup)
        end
    end)
    f.talentsBtn = talents

    -- Claude (v1.4.2): Stats button. Opens a side-panel showing aggregated
    -- item stats (base stats + Melee/Ranged/Spell/Defense ratings) for the
    -- inspected player. Anchors to the LEFT edge of the inspect frame so
    -- a fully-open layout reads: Stats | Inspect | Talents.
    -- Claude (v1.4.3): grouped horizontally next to Talents (LEFT-of-Talents
    -- RIGHT) instead of stacking below — stacking put it underneath the
    -- spec-tree tab buttons at y=-82.
    local stats = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    stats:SetWidth(52); stats:SetHeight(20)
    stats:SetPoint("LEFT", talents, "RIGHT", 4, 0)
    stats:SetText("Stats")
    stats:SetScript("OnClick", function()
        if not f.activePlayer then return end
        if _G.EpogArmory_OpenStatsFor then
            _G.EpogArmory_OpenStatsFor(f.activePlayer, f.activeGroup)
        end
    end)
    f.statsBtn = stats

    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.nameText:SetPoint("TOP", 0, -42)

    f.metaText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.metaText:SetPoint("TOP", 0, -62)
    f.metaText:SetWidth(270)
    f.metaText:SetJustifyH("CENTER")

    -- Spec switcher: 4 buttons between the meta text and the first slot row.
    -- Three for the class talent trees (keys 1, 2, 3) plus one for PvP
    -- (key "pvp" — scan detected as PvP when an Insignia trinket was
    -- equipped). Button labels are set in RenderActiveSet once we know the
    -- class. Empty sets (no scan yet for that key) stay disabled.
    --
    -- Width 72 is tight but fits in the 320-wide frame. Class-tree names
    -- longer than ~10 chars get auto-shortened ("Assassination" → "Assassina.")
    -- in RenderActiveSet.
    local SPEC_BUTTON_KEYS = { 1, 2, 3, "pvp" }
    f.specBtns = {}
    for i, key in ipairs(SPEC_BUTTON_KEYS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetWidth(72)
        b:SetHeight(20)
        -- Offsets from TOP center: -114, -38, +38, +114 (center-to-center 76)
        -- Claude (v1.4.3): y -82 → -92 to clear the Talents/Stats button
        -- row (which sits on the y=-63 to -83 band). 1px overlap before
        -- caused the Stats button to render behind the leftmost spec tab.
        b:SetPoint("TOP", f, "TOP", (i - 2.5) * 76, -92)
        b:SetText(key == "pvp" and "PvP" or ("Tree " .. i))
        b:SetScript("OnClick", function()
            if f.activePlayer and RenderActiveSet then
                f.activeGroup = key
                RenderActiveSet()
                -- Re-render icons for the newly-selected set. Any uncached
                -- items get picked up by the ticker loop started in ShowInspect;
                -- we don't need to restart the ticker here.
                RefreshIcons()
            end
        end)
        f.specBtns[key] = b
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

    -- Spec buttons: 3 class-tree keys + "pvp" key. Empty sets (no scan for
    -- that key yet) stay dimmed and disabled. Active set highlighted.
    local function fitLabel(text, max)
        if text and #text > max then return text:sub(1, max - 1) .. "." end
        return text
    end
    for _, key in ipairs({1, 2, 3, "pvp"}) do
        local b = inspectFrame.specBtns and inspectFrame.specBtns[key]
        if b then
            local label
            if key == "pvp" then
                label = "PvP"
            else
                label = (classTrees and classTrees[key]) or ("Tree " .. tostring(key))
                label = fitLabel(label, 11) -- "Assassination" → "Assassinat."
            end
            b:SetText(label)
            local hasSet = player.sets and player.sets[key] ~= nil
            if hasSet then
                b:Enable()
                b:SetAlpha(1.0)
            else
                b:Disable()
                b:SetAlpha(0.4)
            end
            if key == group then b:LockHighlight() else b:UnlockHighlight() end
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
        if group == "pvp" then
            -- PvP set: no per-class tab icon — show the same shield glyph
            -- the minimap uses, consistent branding.
            inspectFrame.specIcon:SetTexture("Interface\\Icons\\INV_Shield_06")
            inspectFrame.specIcon:Show()
            inspectFrame.specIconLabel:SetText("PvP")
        else
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
end

-- v1.3: in-game talent tree renderer. Anchored to the right of the
-- inspect frame when shown. Reads metadata from EpogTalentTreeDB
-- (populated locally as the user scans/inspects players of each class)
-- and rank distribution from set.talentRanks (wire pos 41).
--
-- v1.3+: visual upgrade to look like Blizzard's PlayerTalentFrame:
--   - class-themed background per spec (4-quadrant tiles loaded from
--     Interface\TalentFrame\<background>-TopLeft.blp etc., where
--     background comes from GetTalentTabInfo)
--   - tier labels (1-7) on the left
--   - prereq arrows drawn between dependent talents
--   - Blizzard-style rank overlay (small diamond texture)
local talentFrame
local function BuildTalentFrame()
    local TIERS = 9    -- Claude: Ascension has TBC trees with up to 9 tiers
    local COLS  = 4
    -- Claude (v1.4.5): bump cell size 36→40 and split GAP into horizontal
    -- and vertical components. The Blizzard talent panel has notably more
    -- vertical breathing room than horizontal — splitting matches that
    -- look without making the grid wider than the frame allows. Frame
    -- height bumped 540→600 to fit 9 rows at the new pitch.
    local CELL    = 40
    local GAP_H   = 12
    local GAP_V   = 14
    local TIER_LABEL_W = 20  -- column on left for tier numbers
    local GRID_LEFT = 14 + TIER_LABEL_W
    local GRID_TOP  = -86

    local GRID_W = COLS  * (CELL + GAP_H) - GAP_H
    local GRID_H = TIERS * (CELL + GAP_V) - GAP_V
    local t = CreateFrame("Frame", "EpogArmoryTalentFrame", UIParent)
    -- Claude (v1.4.5): height 540→600 to accommodate the larger cells +
    -- vertical breathing room. Width still matches the inspect frame.
    t:SetWidth(360); t:SetHeight(600)
    -- Claude (v1.4.2): re-center (tier labels + grid) horizontally inside
    -- the wider frame. Tier labels sit just left of the grid (offset of -4
    -- per the GRID_LEFT-4 anchor at line 678).
    GRID_LEFT = math.floor((360 - TIER_LABEL_W - GRID_W) / 2) + TIER_LABEL_W
    t:SetFrameStrata("DIALOG")
    t:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    -- Claude (v1.4.2): drag disabled — the talents frame is always anchored
    -- to the inspect frame's RIGHT edge in EpogArmory_OpenTalentsFor, so
    -- letting it move independently broke the "stick" relationship the
    -- user expects. Inspect frame is the only draggable surface; talents
    -- follows automatically.
    t:EnableMouse(true)
    t:Hide()

    t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t.title:SetPoint("TOP", 0, -16)
    t.title:SetText("Talents")

    local close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Subtitle: tab name + total points spent (e.g. "Holy 19")
    t.subtitle = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.subtitle:SetPoint("TOP", t.title, "BOTTOM", 0, -2)

    -- 3 tab buttons across the top, just under the subtitle
    t.tabBtns = {}
    for tabIdx = 1, 3 do
        local tb = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
        tb:SetWidth(60); tb:SetHeight(20)
        tb:SetPoint("TOP", t, "TOP", (tabIdx - 2) * 64, -56)
        tb:SetText("Tab " .. tabIdx)
        tb:SetScript("OnClick", function()
            if t.RenderTab then t.RenderTab(tabIdx) end
        end)
        t.tabBtns[tabIdx] = tb
    end

    -- v1.3+: class-themed background. Two halves cover the grid area.
    -- OVERLAY layer: above the dialog backdrop tile (BACKGROUND/BORDER),
    -- still below child frame buttons (child frames always win over parent).
    -- No subLevel arg — not supported in 3.3.5, silently dropped.
    -- Claude: OVERLAY, no subLevel — deterministic ordering in 3.3.5
    t.bgLeft = t:CreateTexture(nil, "OVERLAY")
    t.bgLeft:SetWidth(GRID_W / 2)
    t.bgLeft:SetHeight(GRID_H)
    t.bgLeft:SetPoint("TOPLEFT", t, "TOPLEFT", GRID_LEFT, GRID_TOP)

    t.bgRight = t:CreateTexture(nil, "OVERLAY")
    t.bgRight:SetWidth(GRID_W / 2)
    t.bgRight:SetHeight(GRID_H)
    t.bgRight:SetPoint("TOPLEFT", t, "TOPLEFT", GRID_LEFT + GRID_W / 2, GRID_TOP)

    -- Tier labels down the left side. 7 rows of "1" through "7" so the
    -- viewer immediately recognizes the talent-tree row structure.
    t.tierLabels = {}
    for tier = 1, TIERS do
        local label = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("RIGHT", t, "TOPLEFT",
            GRID_LEFT - 4,
            GRID_TOP - (tier - 1) * (CELL + GAP_V) - CELL / 2)
        label:SetText(tostring(tier))
        label:SetTextColor(0.7, 0.7, 0.4)
        label:SetShadowOffset(1, -1)
        t.tierLabels[tier] = label
    end

    -- Prereq-arrow texture pool. Blizzard composes arrows from many small
    -- branch textures; we approximate with simple straight-line segments
    -- rendered as ARTWORK textures behind the talent buttons. Rendered
    -- on demand in RenderTab and hidden when not in use.
    t.arrowPool = {}
    local function getArrow()
        for _, a in ipairs(t.arrowPool) do
            if not a:IsShown() then return a end
        end
        local a = t:CreateTexture(nil, "ARTWORK") -- Claude: subLevel arg silently dropped on 3.3.5 — removed (audit v1.3.4)
        a:SetTexture("Interface\\Buttons\\WHITE8X8")
        a:SetVertexColor(1, 0.85, 0.3, 0.9)
        a:Hide()
        t.arrowPool[#t.arrowPool + 1] = a
        return a
    end
    local function hideAllArrows()
        for _, a in ipairs(t.arrowPool) do a:Hide() end
    end

    -- Pre-create 4×9 grid of talent cells. Frame (not Button) — we only
    -- need hover/tooltip, not click. Frame + EnableMouse is the reliable
    -- pattern; Button internal hit-testing can eat OnEnter in 3.3.5.
    -- Claude: Frame not Button — avoids Button hit-test eating OnEnter
    t.gridCells = {}
    for tier = 1, TIERS do
        for col = 1, COLS do
            local b = CreateFrame("Frame", nil, t)
            b:EnableMouse(true)
            b:SetWidth(CELL); b:SetHeight(CELL)
            b:SetPoint("TOPLEFT", t, "TOPLEFT",
                GRID_LEFT + (col - 1) * (CELL + GAP_H),
                GRID_TOP - (tier - 1) * (CELL + GAP_V))

            -- Background texture fills the full button. Doubles as the "border"
            -- because the icon is inset 2px, leaving a 2px strip of bg color
            -- visible around the edge. Colored in RenderTab via SetVertexColor.
            -- Avoids SetBackdrop (can fail on Button frames in 3.3.5) entirely.
            -- Claude: CreateTexture bg replaces SetBackdrop — tooltip-safe, always works
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints(b)
            b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            b.bg:SetVertexColor(0.12, 0.12, 0.12, 1)

            -- Icon fills the interior (2px inset so bg strip shows as border)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 2, -2)
            b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Rank text at bottom-right corner, drawn above icon
            b.rankText = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.rankText:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
            b.rankText:SetShadowOffset(1, -1)

            b:SetScript("OnEnter", function(self)
                if not self.talentName then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.talentName, 1, 1, 1)
                if self.talentRank and self.talentRank > 0 then
                    GameTooltip:AddLine(string.format("Rank %d / %d",
                        self.talentRank, self.talentMaxRank or 0), 0.4, 1, 0.4)
                else
                    GameTooltip:AddLine(string.format("Not learned  (max %d)",
                        self.talentMaxRank or 0), 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            t.gridCells[tier .. "," .. col] = b
        end
    end

    -- Stash for use in RenderTab
    t._CELL = CELL
    t._GAP_H = GAP_H -- Claude (v1.4.5): split into horizontal/vertical
    t._GAP_V = GAP_V
    t._GRID_LEFT = GRID_LEFT
    t._GRID_TOP  = GRID_TOP
    t._getArrow = getArrow
    t._hideAllArrows = hideAllArrows

    -- "No metadata yet" placeholder, shown when EpogTalentTreeDB doesn't
    -- have data for this class+tab combo.
    t.emptyText = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.emptyText:SetPoint("CENTER", 0, -20)
    t.emptyText:SetWidth(180)
    t.emptyText:SetJustifyH("CENTER")
    t.emptyText:Hide()

    function t.RenderTab(tabIdx)
        t.activeTab = tabIdx
        for _, c in pairs(t.gridCells) do c:Hide() end
        t._hideAllArrows()
        t.emptyText:Hide()

        for i, btn in ipairs(t.tabBtns) do
            if i == tabIdx then btn:LockHighlight() else btn:UnlockHighlight() end
        end

        if not t.activePlayer then return end
        local cls   = t.activePlayer.class or ""
        local ranks = t.activeRanks and t.activeRanks[tabIdx] or {}
        local meta  = EpogTalentTreeDB and EpogTalentTreeDB[cls]
            and EpogTalentTreeDB[cls].tabs and EpogTalentTreeDB[cls].tabs[tabIdx]

        -- Claude: try class-specific L/R art; fall back to solid dark if missing/empty
        local bgBase = meta and meta.background
        if bgBase and bgBase ~= "" then
            local p = "Interface\\TalentFrame\\" .. bgBase
            t.bgLeft:SetTexture(p .. "-L")
            t.bgRight:SetTexture(p .. "-R")
            t.bgLeft:SetVertexColor(1, 1, 1, 1)
            t.bgRight:SetVertexColor(1, 1, 1, 1)
        else
            -- No class art available — render a solid dark panel so the grid
            -- area is visually distinct from the frame edge tile.
            t.bgLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
            t.bgRight:SetTexture("Interface\\Buttons\\WHITE8X8")
            t.bgLeft:SetVertexColor(0.06, 0.05, 0.04, 0.92)
            t.bgRight:SetVertexColor(0.06, 0.05, 0.04, 0.92)
        end

        -- Subtitle: spec name + points spent
        local pts = 0
        for _, r in ipairs(ranks) do pts = pts + r end
        local tabName = (meta and meta.name) or
            (t.activePlayer.tabNames and t.activePlayer.tabNames[tabIdx]) or
            ("Tab " .. tabIdx)
        t.subtitle:SetText(string.format("|cffffd200%s|r |cff888888%d points|r", tabName, pts))

        if not meta or not meta.talents or not next(meta.talents) then
            t.emptyText:SetText(string.format(
                "No talent metadata yet for |cffffd200%s|r — %s.\n\n|cff888888Self-scan as %s, or inspect a %s with the Reality Recalibrators aura, to populate.|r",
                cls, tabName, cls, cls))
            t.emptyText:Show()
            return
        end

        -- Render talents
        local CELL, GAP_H, GAP_V, GL, GT = t._CELL, t._GAP_H, t._GAP_V, t._GRID_LEFT, t._GRID_TOP
        for i, talent in pairs(meta.talents) do
            if talent.tier and talent.tier > 0 and talent.column and talent.column > 0 then
                local key = talent.tier .. "," .. talent.column
                local cell = t.gridCells[key]
                if cell then
                    -- Set data fields FIRST — tooltip reads these on hover
                    -- Claude: talentName assigned before any call that could error
                    cell.talentName    = talent.name
                    cell.talentRank    = ranks[i] or 0
                    cell.talentMaxRank = talent.maxRank or 0

                    local rank    = cell.talentRank
                    local maxRank = cell.talentMaxRank

                    cell.icon:SetTexture(
                        (talent.icon and talent.icon ~= "") and talent.icon
                        or "Interface\\Icons\\INV_Misc_QuestionMark")

                    -- bg:SetVertexColor colors the 2px border strip around icon.
                    -- Claude (v1.4.5): brighter golden for max-rank talents,
                    -- saturated green for partially-spent, near-black for
                    -- empty — closer to Blizzard's PlayerTalentFrame palette.
                    if rank > 0 then
                        cell.icon:SetDesaturated(false)
                        if rank >= maxRank then
                            cell.bg:SetVertexColor(1.0, 0.78, 0.18, 1)   -- bright gold (maxed)
                            cell.rankText:SetTextColor(1.0, 0.95, 0.55)
                        else
                            cell.bg:SetVertexColor(0.18, 0.78, 0.22, 1)  -- vibrant green (in progress)
                            cell.rankText:SetTextColor(0.5, 1, 0.5)
                        end
                        cell.rankText:SetText(tostring(rank))
                    else
                        cell.icon:SetDesaturated(true)
                        cell.bg:SetVertexColor(0.08, 0.08, 0.08, 1)      -- near-black (empty)
                        cell.rankText:SetTextColor(0.55, 0.55, 0.55)
                        cell.rankText:SetText("0")
                    end
                    cell:Show()
                end
            end
        end

        -- Draw prereq arrows: a colored line from each dependent talent's
        -- top edge to its prereq talent's bottom edge. Approximation of
        -- Blizzard's full arrow-segment composition — good enough to show
        -- the dependency structure. Color reflects whether the dependent
        -- is learnable: green if prereq is maxed, faded otherwise.
        for i, talent in pairs(meta.talents) do
            if talent.prereqTier and talent.prereqCol then
                -- Center coords of dependent and prereq cells
                local function cellCenter(tier, col)
                    return GL + (col - 1) * (CELL + GAP_H) + CELL / 2,
                           GT - (tier - 1) * (CELL + GAP_V) - CELL / 2
                end
                local dx, dy = cellCenter(talent.tier, talent.column)
                local px, py = cellCenter(talent.prereqTier, talent.prereqCol)

                -- Determine if prereq is satisfied (learned to max) — colors
                -- the arrow. Find the prereq talent's index by (tier, col).
                local prereqLearned = false
                for j, ot in pairs(meta.talents) do
                    if ot.tier == talent.prereqTier and ot.column == talent.prereqCol then
                        local r = ranks[j] or 0
                        prereqLearned = r >= (ot.maxRank or 0) and r > 0
                        break
                    end
                end

                if px == dx then
                    -- Vertical arrow (same column)
                    local arrow = t._getArrow()
                    arrow:ClearAllPoints()
                    arrow:SetWidth(3)
                    local top = math.max(py, dy) - CELL / 2
                    local bot = math.min(py, dy) + CELL / 2
                    arrow:SetHeight(top - bot)
                    arrow:SetPoint("CENTER", t, "TOPLEFT", dx, (top + bot) / 2)
                    if prereqLearned then
                        arrow:SetVertexColor(0.3, 1, 0.3, 0.85)
                    else
                        arrow:SetVertexColor(0.6, 0.6, 0.6, 0.65)
                    end
                    arrow:Show()
                elseif py == dy then
                    -- Horizontal arrow (same tier, same row)
                    local arrow = t._getArrow()
                    arrow:ClearAllPoints()
                    arrow:SetHeight(3)
                    local left  = math.min(px, dx) + CELL / 2
                    local right = math.max(px, dx) - CELL / 2
                    arrow:SetWidth(right - left)
                    arrow:SetPoint("CENTER", t, "TOPLEFT", (left + right) / 2, dy)
                    if prereqLearned then
                        arrow:SetVertexColor(0.3, 1, 0.3, 0.85)
                    else
                        arrow:SetVertexColor(0.6, 0.6, 0.6, 0.65)
                    end
                    arrow:Show()
                else
                    -- L-shaped arrow (different tier AND column). Draw two
                    -- segments: vertical from prereq down, then horizontal
                    -- across to the dependent. Matches Blizzard's pattern
                    -- for offset prereqs.
                    local color1, color2 = 0.6, 0.6
                    local va = t._getArrow()
                    va:ClearAllPoints()
                    va:SetWidth(3)
                    local top = math.max(py, dy) - CELL / 2
                    local bot = math.min(py, dy) + CELL / 2
                    va:SetHeight(top - bot)
                    va:SetPoint("CENTER", t, "TOPLEFT", px, (top + bot) / 2)
                    if prereqLearned then va:SetVertexColor(0.3, 1, 0.3, 0.85)
                    else va:SetVertexColor(0.6, 0.6, 0.6, 0.65) end
                    va:Show()

                    local ha = t._getArrow()
                    ha:ClearAllPoints()
                    ha:SetHeight(3)
                    local left  = math.min(px, dx) + CELL / 2
                    local right = math.max(px, dx) - CELL / 2
                    ha:SetWidth(right - left)
                    ha:SetPoint("CENTER", t, "TOPLEFT", (left + right) / 2, dy)
                    if prereqLearned then ha:SetVertexColor(0.3, 1, 0.3, 0.85)
                    else ha:SetVertexColor(0.6, 0.6, 0.6, 0.65) end
                    ha:Show()
                end
            end
        end
    end

    -- Update tab labels with the player's actual tree names whenever a new
    -- player is opened. Falls back to "Tab N" if names aren't available.
    function t.SetPlayer(player, group)
        t.activePlayer = player
        t.activeRanks  = nil
        if player and player.sets and player.sets[group] then
            t.activeRanks = player.sets[group].talentRanks
        end
        local names = (player and player.tabNames) or {}
        local cls   = (player and player.class) or ""
        local meta  = EpogTalentTreeDB and EpogTalentTreeDB[cls]
        for i = 1, 3 do
            local label = names[i] or (meta and meta.tabs and meta.tabs[i] and meta.tabs[i].name) or ("Tab " .. i)
            -- Trim long names to fit the 60-wide button
            if #label > 9 then label = label:sub(1, 8) .. "." end
            t.tabBtns[i]:SetText(label)
        end
        t.title:SetText(string.format("Talents — %s", (player and player.name) or "?"))
        -- Default to the dominant tree if we have spec data; otherwise tab 1
        local defaultTab = 1
        if player and player.spec then
            local maxV, maxI = 0, 1
            for i = 1, 3 do
                if (player.spec[i] or 0) > maxV then maxV, maxI = player.spec[i], i end
            end
            if maxV > 0 then defaultTab = maxI end
        end
        t.RenderTab(defaultTab)
    end

    tinsert(UISpecialFrames, "EpogArmoryTalentFrame") -- Esc closes
    return t
end

-- Public opener — called from the inspect frame's "Talents" button.
-- Claude (audit fix v1.3.4): build once, reuse on subsequent opens.
-- Claude (v1.4.2): clear anchor and re-anchor every open. Combined with
-- drag being disabled on the talents frame itself (see BuildTalentFrame),
-- this keeps the talents frame "stuck" to the right edge of the inspect
-- frame across moves — dragging the inspect frame carries talents along
-- because of the relative anchor.
function _G.EpogArmory_OpenTalentsFor(player, group)
    if not talentFrame then talentFrame = BuildTalentFrame() end
    talentFrame:ClearAllPoints()
    if inspectFrame and inspectFrame:IsShown() then
        talentFrame:SetPoint("TOPLEFT", inspectFrame, "TOPRIGHT", 4, 0)
    else
        talentFrame:SetPoint("CENTER")
    end
    talentFrame:Show()
    talentFrame.SetPlayer(player, group)
end

-- Claude (v1.4.2): Stats overview frame.
-- Aggregates item stats from EpogItemCacheDB across the active set's gear,
-- displays them grouped (Base / Melee / Ranged / Spell / Defense) with
-- rating→% conversion at L80 (WotLK constants). Anchors to the LEFT of
-- the inspect frame so when both Stats and Talents are open you get a
-- three-panel view: Stats | Inspect | Talents.
local statsFrame

-- Sum stats across all 19 slots' items. Pulls from BOTH:
--   entry.stats         — GetItemStats output (TBC+ rating system, keyed by
--                         ITEM_MOD_*_SHORT)
--   entry.tooltipStats  — pre-rating Vanilla "+1% crit" / "+5 mp5" stats
--                         parsed from tooltip text, keyed per
--                         TOOLTIP_STAT_PATTERNS (CRIT_PCT, MP5, etc.)
-- Both must be summed because a Vanilla-era L60 character has gear that
-- only populates the tooltip side, while a TBC+ character has gear that
-- populates the rating side. A mixed loadout uses both.
-- Claude (v1.4.3): tooltipStats was missing in v1.4.2 — a L60 hunter
-- showed all 0% because Vanilla items don't carry rating stats.
local function AggregateItemStats(gear)
    local out = { stats = {}, tooltip = {}, weapon = nil }
    if not gear then return out end
    local cache = EpogItemCacheDB or {}
    for slot = 1, 19 do
        local itemstr = gear[slot]
        if itemstr and itemstr ~= "" then
            local itemID = tonumber(itemstr:match("^(%d+)"))
            if itemID and cache[itemID] then
                local entry = cache[itemID]
                if entry.stats then
                    for k, v in pairs(entry.stats) do
                        if type(v) == "number" then
                            out.stats[k] = (out.stats[k] or 0) + v
                        end
                    end
                end
                if entry.tooltipStats then
                    for k, v in pairs(entry.tooltipStats) do
                        if type(v) == "number" then
                            out.tooltip[k] = (out.tooltip[k] or 0) + v
                        end
                    end
                end
                -- Capture mainhand weapon damage/speed for the Melee section
                if slot == 16 and entry.damage and entry.speed then
                    out.weapon = {
                        min   = entry.damage.min,
                        max   = entry.damage.max,
                        speed = entry.speed,
                    }
                end
            end
        end
    end
    return out
end

-- Claude (v1.4.3): combine rating-based and tooltip-based pcts into one
-- displayed percentage. Ratings get divided by the L80 conversion;
-- tooltip pcts are already in percentage units and add directly.
-- s = ratings table, t = tooltip table.
local function CombinePct(s, t, ratingKeys, tooltipKeys, perPct)
    local pct = 0
    if ratingKeys then
        for _, k in ipairs(ratingKeys) do
            pct = pct + (s[k] or 0) / perPct
        end
    end
    if tooltipKeys then
        for _, k in ipairs(tooltipKeys) do
            pct = pct + (t[k] or 0)
        end
    end
    return string.format("%.2f%%", pct)
end

-- WotLK rating-to-% conversion at L80. Used for displaying combat ratings
-- in their "% chance" form. Players below L80 see slightly inflated %s
-- (the constants are smaller at lower levels, but we can't reliably
-- compute them without a class-aware curve, and L80 is the common case
-- for raid-relevant scans).
local RATING_PER_PERCENT_L80 = {
    melee_hit       = 32.78,
    ranged_hit      = 32.78,
    spell_hit       = 26.23,
    melee_crit      = 45.91,
    ranged_crit     = 45.91,
    spell_crit      = 45.91,
    melee_haste     = 25.21,
    ranged_haste    = 25.21,
    spell_haste     = 32.79,
    expertise       = 8.197,   -- 1 expertise = 0.25% reduction; rating/8.197 = expertise points
    defense         = 4.92,    -- 1 defense skill = 0.04% misc; rating/4.92 = defense skill
    dodge           = 39.35,
    parry           = 49.18,
    block           = 16.39,
    resilience      = 94.28,
    armor_pen       = 13.99,
}

local function FmtNum(n)
    if not n or n == 0 then return "0" end
    return tostring(n)
end

local function BuildStatsFrame()
    local f = CreateFrame("Frame", "EpogArmoryStatsFrame", UIParent)
    -- Claude (v1.4.3): height 540 → 640 so all sections fit. The earlier
    -- 540 matched the inspect frame but the stat content (~35 rows + 5
    -- section headers) overflowed the bottom. Frame is now slightly taller
    -- than inspect; that's fine since they don't share a backdrop.
    f:SetWidth(360); f:SetHeight(640)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    -- Drag disabled so it stays anchored to the inspect frame's LEFT edge.
    f:EnableMouse(true)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16)
    f.title:SetText("Stats")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Two-column body: label on left, value right-aligned. Pre-allocate a
    -- pool of fontstring pairs and stack them vertically. Section headers
    -- are full-width single fontstrings.
    -- Claude (v1.4.3): line height reduced 16→14 so all sections fit
    -- comfortably within the 640-tall frame even on classes with full
    -- Defense/Spell stat representation.
    local LINE_H = 14
    local SECTION_GAP = 5
    local TOP = -54
    local LABEL_X = 22
    local VALUE_RIGHT = -22

    f.lines = {}
    -- factory: ensure pool[i] exists, return its line table
    local function ensureLine(i)
        local L = f.lines[i]
        if L then return L end
        L = {}
        L.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        L.label:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_X, TOP)
        L.label:SetJustifyH("LEFT")
        L.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        L.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", VALUE_RIGHT, TOP)
        L.value:SetJustifyH("RIGHT")
        f.lines[i] = L
        return L
    end

    -- Reposition + write line content. y is the running y offset (negative).
    local function placeLine(i, y, label, value, isHeader)
        local L = ensureLine(i)
        L.label:ClearAllPoints()
        L.value:ClearAllPoints()
        L.label:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_X, y)
        L.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", VALUE_RIGHT, y)
        if isHeader then
            L.label:SetText("|cffffd200" .. label .. "|r")
            L.value:SetText("")
        else
            L.label:SetText(label)
            L.value:SetText(value or "0")
        end
        L.label:Show()
        L.value:Show()
    end

    local function hideLinesFrom(i)
        local k = i
        while f.lines[k] do
            f.lines[k].label:Hide()
            f.lines[k].value:Hide()
            k = k + 1
        end
    end

    function f.SetPlayer(player, group)
        local hasSnapshot = player and player.sets and player.sets[group] and player.sets[group].charStats
        local titleSuffix = hasSnapshot and "" or "  |cff888888(item-only)|r"
        f.title:SetText(string.format("Stats — %s%s", (player and player.name) or "?", titleSuffix))
        if not player or not player.sets or not player.sets[group] then
            placeLine(1, TOP, "(no set data)", "", true)
            hideLinesFrom(2)
            return
        end
        local set = player.sets[group]
        local agg = AggregateItemStats(set.gear)
        local s = agg.stats   -- ratings (TBC+)
        local t = agg.tooltip -- pcts (Vanilla "+1% crit" etc.)
        -- Claude (v1.4.4): prefer the snapshot of live character stats
        -- captured at scan time. Fields populated here override the
        -- item-derived fallbacks below. cs may be nil for pre-v1.4.4
        -- entries — UI silently falls back.
        local cs = set.charStats

        -- Helper: prefer live snapshot value if present, else fall back to
        -- the item-derived computation. csKey is the charStats field name.
        local function csOr(csKey, fallback)
            if cs and cs[csKey] then return cs[csKey] end
            return fallback
        end
        -- For pct-typed fields, format the live snapshot value or the
        -- already-formatted fallback string.
        local function csPct(csKey, fallback)
            if cs and cs[csKey] then return string.format("%.2f%%", cs[csKey]) end
            return fallback
        end
        -- For numeric stat values: show the live snapshot if present
        -- (rounded to integer for display), else format the item-sum.
        local function csNum(csKey, fallback)
            if cs and cs[csKey] then return string.format("%d", cs[csKey]) end
            return fallback
        end

        local i = 0
        local y = TOP
        local function row(label, value, isHeader)
            i = i + 1
            placeLine(i, y, label, value, isHeader)
            y = y - (isHeader and (LINE_H + 2) or LINE_H)
        end
        local function gap()
            y = y - SECTION_GAP
        end

        -- Base Stats — prefer live snapshot (matches in-game character pane).
        row("Base Stats", nil, true)
        row("Strength",  csNum("str", FmtNum(s["ITEM_MOD_STRENGTH_SHORT"])))
        row("Agility",   csNum("agi", FmtNum(s["ITEM_MOD_AGILITY_SHORT"])))
        row("Stamina",   csNum("sta", FmtNum(s["ITEM_MOD_STAMINA_SHORT"])))
        row("Intellect", csNum("int", FmtNum(s["ITEM_MOD_INTELLECT_SHORT"])))
        row("Spirit",    csNum("spi", FmtNum(s["ITEM_MOD_SPIRIT_SHORT"])))
        -- Armor: live snapshot is the effective armor (UnitArmor's index 2),
        -- which includes base + items + buffs. Fallback is item-only sum.
        if cs and cs.armor then
            row("Armor", csNum("armor", "0"))
        else
            local armorFallback = (s["RESISTANCE0_NAME"] or s["ITEM_MOD_ARMOR"]
                or s["ITEM_MOD_RESISTANCE_BASE_SHORT"] or 0)
            row("Armor (bonus)", FmtNum(armorFallback))
        end
        gap()

        -- Melee — prefer live snapshot for Power/Hit/Crit/Haste/Expertise.
        row("Melee", nil, true)
        -- Weapon damage: live UnitDamage snapshot (includes AP scaling)
        -- preferred over the per-item min/max which is just weapon's
        -- intrinsic damage and ignores AP contribution.
        if cs and cs.wMin and cs.wMax then
            row("Damage", string.format("%d-%d", cs.wMin, cs.wMax))
        elseif agg.weapon then
            row("Damage", string.format("%.0f-%.0f", agg.weapon.min or 0, agg.weapon.max or 0))
        else
            row("Damage", "—")
        end
        row("Speed", agg.weapon and string.format("%.2f", agg.weapon.speed or 0) or "—")
        local meleeAP = (s["ITEM_MOD_ATTACK_POWER_SHORT"] or 0)
        local mp5_tt  = (t["MP5"] or 0) -- used in Spell section's Mana/5s row
        row("Power",       csNum("mAP", FmtNum(meleeAP)))
        row("Hit Chance",  csPct("mHit",
            CombinePct(s, t,
                { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT" },
                { "HIT_PCT", "HIT_MELEE_RANGED_PCT" },
                RATING_PER_PERCENT_L80.melee_hit)))
        row("Crit Chance", csPct("mCrit",
            CombinePct(s, t,
                { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT" },
                { "CRIT_PCT", "CRIT_MELEE_RANGED_PCT" },
                RATING_PER_PERCENT_L80.melee_crit)))
        row("Haste",       csPct("mHa",
            CombinePct(s, t,
                { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_MELEE_RATING_SHORT" }, nil,
                RATING_PER_PERCENT_L80.melee_haste)))
        row("Expertise",   csPct("exp",
            CombinePct(s, t,
                { "ITEM_MOD_EXPERTISE_RATING_SHORT" }, { "EXPERTISE_PCT" },
                RATING_PER_PERCENT_L80.expertise)))
        gap()

        -- Ranged
        row("Ranged", nil, true)
        local rangedAP = (s["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] or 0)
        row("Power",       csNum("rAP", FmtNum(rangedAP > 0 and rangedAP or meleeAP)))
        row("Hit Chance",  csPct("rHit",
            CombinePct(s, t,
                { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_RANGED_RATING_SHORT" },
                { "HIT_PCT", "HIT_MELEE_RANGED_PCT" },
                RATING_PER_PERCENT_L80.ranged_hit)))
        row("Crit Chance", csPct("rCrit",
            CombinePct(s, t,
                { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT" },
                { "CRIT_PCT", "CRIT_MELEE_RANGED_PCT" },
                RATING_PER_PERCENT_L80.ranged_crit)))
        row("Haste",       csPct("rHa",
            CombinePct(s, t,
                { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_RANGED_RATING_SHORT" }, nil,
                RATING_PER_PERCENT_L80.ranged_haste)))
        gap()

        -- Spell
        row("Spell", nil, true)
        local spellPow = (s["ITEM_MOD_SPELL_POWER_SHORT"] or 0) + (t["SPELL_POWER_FLAT"] or 0) + (t["SPELL_DAMAGE_FLAT"] or 0)
        row("Spell Power", csNum("sp", FmtNum(spellPow)))
        row("Hit Chance",  csPct("sHit",
            CombinePct(s, t,
                { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
                { "HIT_SPELL_PCT" },
                RATING_PER_PERCENT_L80.spell_hit)))
        row("Crit Chance", csPct("sCrit",
            CombinePct(s, t,
                { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
                { "CRIT_SPELL_PCT" },
                RATING_PER_PERCENT_L80.spell_crit)))
        row("Haste",       csPct("sHa",
            CombinePct(s, t,
                { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_SPELL_RATING_SHORT" }, nil,
                RATING_PER_PERCENT_L80.spell_haste)))
        row("Mana / 5s",   csNum("mp5", FmtNum((s["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + mp5_tt)))
        row("Penetration", FmtNum((s["ITEM_MOD_SPELL_PENETRATION_SHORT"] or 0) + (t["SPELL_PENETRATION_FLAT"] or 0)))
        gap()

        -- Defense
        row("Defense", nil, true)
        local defR     = (s["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] or 0)
        local defFlat  = (t["DEFENSE_FLAT"] or 0)
        local blockV   = (s["ITEM_MOD_BLOCK_VALUE_SHORT"] or 0) + (t["BLOCK_VALUE_FLAT"] or 0)
        -- Claude (v1.4.5): cs.def is now the total defense skill (UnitDefense
        -- base + modifier), not a rating-derived percent. Matches the
        -- in-game character pane's "Defense: 405" line. Fallback shows
        -- the rating-derived skill bonus when no live snapshot.
        if cs and cs.def then
            row("Defense", string.format("%d skill", cs.def))
        else
            row("Defense (rating)", string.format("%d (+%.0f skill)", defR, defR / RATING_PER_PERCENT_L80.defense + defFlat))
        end
        row("Dodge",       csPct("dod",
            CombinePct(s, t, { "ITEM_MOD_DODGE_RATING_SHORT" }, { "DODGE_PCT" },
                RATING_PER_PERCENT_L80.dodge)))
        row("Parry",       csPct("par",
            CombinePct(s, t, { "ITEM_MOD_PARRY_RATING_SHORT" }, { "PARRY_PCT" },
                RATING_PER_PERCENT_L80.parry)))
        row("Block",       csPct("blk",
            CombinePct(s, t, { "ITEM_MOD_BLOCK_RATING_SHORT" }, { "BLOCK_PCT" },
                RATING_PER_PERCENT_L80.block)))
        row("Block Value", FmtNum(blockV))
        row("Resilience",  csPct("res",
            CombinePct(s, t, { "ITEM_MOD_RESILIENCE_RATING_SHORT" }, nil,
                RATING_PER_PERCENT_L80.resilience)))
        row("Armor Pen",   csPct("arp",
            CombinePct(s, t, { "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT" }, nil,
                RATING_PER_PERCENT_L80.armor_pen)))

        hideLinesFrom(i + 1)
    end

    tinsert(UISpecialFrames, "EpogArmoryStatsFrame")
    return f
end

-- Public opener — called from the inspect frame's "Stats" button.
function _G.EpogArmory_OpenStatsFor(player, group)
    if not statsFrame then statsFrame = BuildStatsFrame() end
    statsFrame:ClearAllPoints()
    if inspectFrame and inspectFrame:IsShown() then
        statsFrame:SetPoint("TOPRIGHT", inspectFrame, "TOPLEFT", -4, 0)
    else
        statsFrame:SetPoint("CENTER")
    end
    statsFrame:Show()
    statsFrame.SetPlayer(player, group)
end

local function ShowInspect(player, group)
    if not inspectFrame then inspectFrame = BuildInspectFrame() end
    inspectFrame.activePlayer = player
    inspectFrame.activeGroup  = group or FindLatestGroup(player)

    RenderActiveSet()
    -- v1.3: if the talent frame is open, refresh it for the new player
    if talentFrame and talentFrame:IsShown() and _G.EpogArmory_OpenTalentsFor then
        talentFrame.SetPlayer(player, inspectFrame.activeGroup)
    end
    -- Claude (v1.4.2): if the stats frame is open, refresh it too.
    if statsFrame and statsFrame:IsShown() then
        statsFrame.SetPlayer(player, inspectFrame.activeGroup)
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

-- Browser + inspect share the same size (320x540) and swap in place so
-- navigating between them feels like one unified frame with two views.
local BROWSER_ROWS = 24
local BROWSER_ROW_HEIGHT = 18

local function BuildBrowser()
    local f = CreateFrame("Frame", "EpogArmoryBrowserFrame", UIParent)
    -- Claude (v1.4.2): widened 320→380 to fit the new Guild column in the
    -- Scanners view (and the Players view gets more name room as a bonus).
    f:SetWidth(380); f:SetHeight(540)
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

    -- v1.2: prominent aura status banner under the title. Visible at all
    -- times so the user immediately understands whether auto-inspect is
    -- functional. Without the Reality Recalibrators aura, inspect APIs
    -- return Ascension's transmog visuals instead of real gear — the
    -- addon pauses auto-scanning of groupmates when missing.
    f.auraStatus = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.auraStatus:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
    f.auraStatus:SetWidth(300)
    f.auraStatus:SetJustifyH("CENTER")

    local function RefreshAuraStatus()
        local has = (_G.EpogArmory and _G.EpogArmory.HasRealityAura
            and _G.EpogArmory.HasRealityAura()) or false
        local auraName = (_G.EpogArmory and _G.EpogArmory.RealityAuraName) or "Reality Recalibrators"
        -- Claude (v1.4.1 test): respect the aura interlock flag so the banner
        -- doesn't mislead users when the gate is disabled for testing.
        local requires = (_G.EpogArmory and _G.EpogArmory.RequiresRealityAura
            and _G.EpogArmory.RequiresRealityAura()) or false
        if has then
            f.auraStatus:SetText(string.format(
                "|cff66ff66✓ %s active|r |cff888888— auto-inspect enabled|r",
                auraName))
        elseif requires then
            f.auraStatus:SetText(string.format(
                "|cffff6666✗ %s missing|r |cffff9966— auto-inspect paused (transmog hides true gear)|r",
                auraName))
        else
            f.auraStatus:SetText(string.format(
                "|cffff6666✗ %s missing|r |cffffaa00— TEST MODE: scanning anyway|r",
                auraName))
        end
    end
    f.RefreshAuraStatus = RefreshAuraStatus
    RefreshAuraStatus()

    -- View-mode toggle: switches between "players" (default — searchable
    -- list of scanned players) and "scanners" (leaderboard of who's
    -- contributed the most sets, useful for picking a sync target).
    -- Positioned top-left per v0.38 feedback.
    f.viewMode = "players"
    local viewToggle = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    viewToggle:SetWidth(80); viewToggle:SetHeight(20)
    viewToggle:SetPoint("TOPLEFT", 14, -14)
    viewToggle:SetText("Scanners")
    f.viewToggle = viewToggle

    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- v1.2: pushed down from -46 → -60 to make room for the aura status banner.
    searchLabel:SetPoint("TOPLEFT", 22, -60)
    searchLabel:SetText("Search:")
    f.searchLabel = searchLabel

    local search = CreateFrame("EditBox", "EpogArmoryBrowserSearch", f, "InputBoxTemplate")
    -- Claude v0.48: shrunk from 180 → 100 to make room for the class filter
    -- button on the same row.
    search:SetWidth(100); search:SetHeight(20)
    search:SetPoint("TOPLEFT", searchLabel, "TOPRIGHT", 10, 3)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search

    -- Claude v0.48: class filter for the Players view. Stored as classFile
    -- (uppercase, English: "WARRIOR" etc.) on the frame; nil = no filter.
    -- Hidden in Scanners mode.
    f.classFilter = nil
    -- Claude v0.48.1: Ascension does not have Death Knight as a class
    -- (server doesn't ship the DK starting experience), so it's omitted.
    -- Nine vanilla classes, ordered alphabetically by display name.
    local CLASS_FILTER_ORDER = {
        "DRUID", "HUNTER", "MAGE", "PALADIN",
        "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
    }
    local function ClassDisplayName(classFile)
        if not classFile or classFile == "" then return "All" end
        local loc = (LOCALIZED_CLASS_NAMES_MALE or {})[classFile]
        if loc then return loc end
        -- Fallback: title-case (DEATHKNIGHT → Deathknight)
        return classFile:sub(1, 1) .. classFile:sub(2):lower()
    end
    local function ClassColorize(classFile, text)
        local c = (RAID_CLASS_COLORS or {})[classFile or ""]
        if not c then return text end
        return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
    end

    -- Hidden dropdown frame used to render the class-filter menu.
    local classFilterMenu = CreateFrame("Frame", "EpogArmoryClassFilterMenu", f, "UIDropDownMenuTemplate")

    f.classFilterBtn = CreateFrame("Button", "EpogArmoryClassFilterBtn", f, "UIPanelButtonTemplate")
    f.classFilterBtn:SetWidth(110); f.classFilterBtn:SetHeight(20)
    f.classFilterBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
    f.classFilterBtn:SetText("Class: All")

    local function RefreshClassFilterButtonText()
        if f.classFilter then
            f.classFilterBtn:SetText("Class: " .. ClassDisplayName(f.classFilter))
        else
            f.classFilterBtn:SetText("Class: All")
        end
    end

    -- Forward-declared; assigned to the real Update() further below so the
    -- dropdown callback can refresh the player list when the filter changes.
    local function NoOp() end
    f._refreshList = NoOp

    local function InitClassFilterMenu(self, level)
        local function addItem(label, classFile)
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.notCheckable = true
            info.func = function()
                f.classFilter = classFile
                RefreshClassFilterButtonText()
                f._refreshList()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
        addItem("All Classes", nil)
        for _, cls in ipairs(CLASS_FILTER_ORDER) do
            addItem(ClassColorize(cls, ClassDisplayName(cls)), cls)
        end
    end

    f.classFilterBtn:SetScript("OnClick", function(self)
        UIDropDownMenu_Initialize(classFilterMenu, InitClassFilterMenu, "MENU")
        ToggleDropDownMenu(1, nil, classFilterMenu, self, 0, 0)
    end)
    f.classFilterBtn:Hide() -- toggled on in Players mode below

    -- Scroll frame
    local scroll = CreateFrame("ScrollFrame", "EpogArmoryBrowserScroll", f, "FauxScrollFrameTemplate")
    -- v1.2: TOPLEFT pushed -80 → -94 to make room for the aura status banner.
    scroll:SetPoint("TOPLEFT", 18, -94)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    f.scroll = scroll

    -- Claude v0.48: column anchors for the Players-view table layout.
    -- Frame width 320; row content area roughly x=20 → x=286 (266 wide).
    -- Allocate: Name (left, ~110px), Class (middle, ~75px), Last Scan
    -- (right, ~70px). Header fontstrings are positioned over the gap
    -- between the search row and the scroll frame so we don't sacrifice
    -- scroll height.
    local COL_NAME_LEFT   = 6     -- offset from row LEFT
    local COL_CLASS_LEFT  = 116   -- name column width 110
    local COL_AGE_RIGHT   = -6    -- offset from row RIGHT (right-aligned)
    local COL_AGE_WIDTH   = 70

    -- Headers are anchored to the scroll frame; rows are inset 2px from scroll
    -- left/right (see row anchors below). Add the 2px so headers align with
    -- the column text exactly.
    f.colHeaderName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.colHeaderName:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", COL_NAME_LEFT + 2, 2)
    f.colHeaderName:SetText("|cffffd200Name|r")
    f.colHeaderName:Hide()

    f.colHeaderClass = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.colHeaderClass:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", COL_CLASS_LEFT + 2, 2)
    f.colHeaderClass:SetText("|cffffd200Class|r")
    f.colHeaderClass:Hide()

    f.colHeaderAge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.colHeaderAge:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", COL_AGE_RIGHT - 2, 2)
    f.colHeaderAge:SetText("|cffffd200Last Scan|r")
    f.colHeaderAge:Hide()

    -- Stash anchors on the frame so the row-creation loop below can use them.
    f._colNameLeft  = COL_NAME_LEFT
    f._colClassLeft = COL_CLASS_LEFT
    f._colAgeRight  = COL_AGE_RIGHT
    f._colAgeWidth  = COL_AGE_WIDTH

    -- Claude v0.49 / v1.4.2: column anchors for the Scanners-view table.
    -- Six columns now (added Guild between Name and Contrib in v1.4.2).
    -- Layout, row-relative, with the right-anchored columns expressed as
    -- offsets from row.RIGHT:
    --   Rank:     LEFT 4   width 24
    --   Name:     LEFT 30, RIGHT row.right - (guildLeft + 4)  ← flex
    --   Guild:    RIGHT -142, width 76
    --   Contrib:  RIGHT -98,  width 40
    --   DB:       RIGHT -58,  width 36
    --   Last:     RIGHT -4,   width 50
    -- The browser frame was widened 320→380 in v1.4.2 to accommodate the
    -- new Guild column without squeezing the others.
    local SCAN_RANK_LEFT     = 4
    local SCAN_NAME_LEFT     = 30
    local SCAN_GUILD_RIGHT   = -142  -- Claude (v1.4.2): new column
    local SCAN_GUILD_WIDTH   = 76
    local SCAN_CONTRIB_RIGHT = -98  -- offset from row RIGHT → right edge at 168
    local SCAN_CONTRIB_WIDTH = 40
    local SCAN_DB_RIGHT      = -58  -- right edge at 208
    local SCAN_DB_WIDTH      = 36
    local SCAN_LAST_RIGHT    = -4   -- right edge at 262
    local SCAN_LAST_WIDTH    = 50

    f.scanHeaderRank = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.scanHeaderRank:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", SCAN_RANK_LEFT + 2, 2)
    f.scanHeaderRank:SetText("|cffffd200#|r")
    f.scanHeaderRank:Hide()

    f.scanHeaderName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.scanHeaderName:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", SCAN_NAME_LEFT + 2, 2)
    f.scanHeaderName:SetText("|cffffd200Name|r")
    f.scanHeaderName:Hide()

    -- Claude (v1.4.2): Guild column header
    f.scanHeaderGuild = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.scanHeaderGuild:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", SCAN_GUILD_RIGHT - 2, 2)
    f.scanHeaderGuild:SetText("|cffffd200Guild|r")
    f.scanHeaderGuild:Hide()

    f.scanHeaderContrib = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.scanHeaderContrib:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", SCAN_CONTRIB_RIGHT - 2, 2)
    f.scanHeaderContrib:SetText("|cffffd200Contrib|r")
    f.scanHeaderContrib:Hide()

    f.scanHeaderDB = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.scanHeaderDB:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", SCAN_DB_RIGHT - 2, 2)
    f.scanHeaderDB:SetText("|cffffd200In DB|r")
    f.scanHeaderDB:Hide()

    f.scanHeaderLast = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.scanHeaderLast:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", SCAN_LAST_RIGHT - 2, 2)
    f.scanHeaderLast:SetText("|cffffd200Last|r")
    f.scanHeaderLast:Hide()

    f._scanRankLeft     = SCAN_RANK_LEFT
    f._scanNameLeft     = SCAN_NAME_LEFT
    f._scanGuildRight   = SCAN_GUILD_RIGHT   -- Claude (v1.4.2)
    f._scanGuildWidth   = SCAN_GUILD_WIDTH   -- Claude (v1.4.2)
    f._scanContribRight = SCAN_CONTRIB_RIGHT
    f._scanContribWidth = SCAN_CONTRIB_WIDTH
    f._scanDBRight      = SCAN_DB_RIGHT
    f._scanDBWidth      = SCAN_DB_WIDTH
    f._scanLastRight    = SCAN_LAST_RIGHT
    f._scanLastWidth    = SCAN_LAST_WIDTH

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

        -- Claude v0.48: per-row column fontstrings for the Players view.
        -- Visible only in players mode; row.text is hidden in that mode.
        -- Scanners mode keeps the existing single-line row.text rendering.
        row.colName = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.colName:SetPoint("LEFT", f._colNameLeft, 0)
        row.colName:SetPoint("RIGHT", row, "LEFT", f._colClassLeft - 4, 0)
        row.colName:SetJustifyH("LEFT")
        row.colName:Hide()

        row.colClass = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.colClass:SetPoint("LEFT", row, "LEFT", f._colClassLeft, 0)
        row.colClass:SetPoint("RIGHT", row, "RIGHT", f._colAgeRight - f._colAgeWidth - 4, 0)
        row.colClass:SetJustifyH("LEFT")
        row.colClass:Hide()

        row.colAge = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.colAge:SetPoint("RIGHT", f._colAgeRight, 0)
        row.colAge:SetWidth(f._colAgeWidth)
        row.colAge:SetJustifyH("RIGHT")
        row.colAge:Hide()

        -- Claude v0.49: per-row column FontStrings for the Scanners view.
        -- Visible only in scanners mode; row.text is hidden in that mode too
        -- (replaced by these five columns instead of a single concatenation).
        row.scanRank = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.scanRank:SetPoint("LEFT", f._scanRankLeft, 0)
        row.scanRank:SetWidth(f._scanNameLeft - f._scanRankLeft - 2)
        row.scanRank:SetJustifyH("LEFT")
        row.scanRank:Hide()

        row.scanName = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.scanName:SetPoint("LEFT", f._scanNameLeft, 0)
        -- Claude (v1.4.2): right-anchor pulled in to make room for the Guild
        -- column inserted between Name and Contrib.
        row.scanName:SetPoint("RIGHT", row, "RIGHT", f._scanGuildRight - f._scanGuildWidth - 4, 0)
        row.scanName:SetJustifyH("LEFT")
        row.scanName:Hide()

        -- Claude (v1.4.2): Guild column. Sourced from peerInfo[name].guild,
        -- which is populated from wire field 42 on every broadcast. Empty
        -- string for unguilded peers or older clients that didn't send it.
        row.scanGuild = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.scanGuild:SetPoint("RIGHT", row, "RIGHT", f._scanGuildRight, 0)
        row.scanGuild:SetWidth(f._scanGuildWidth)
        row.scanGuild:SetJustifyH("LEFT")
        row.scanGuild:Hide()

        row.scanContrib = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.scanContrib:SetPoint("RIGHT", f._scanContribRight, 0)
        row.scanContrib:SetWidth(f._scanContribWidth)
        row.scanContrib:SetJustifyH("RIGHT")
        row.scanContrib:Hide()

        row.scanDB = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.scanDB:SetPoint("RIGHT", f._scanDBRight, 0)
        row.scanDB:SetWidth(f._scanDBWidth)
        row.scanDB:SetJustifyH("RIGHT")
        row.scanDB:Hide()

        row.scanLast = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.scanLast:SetPoint("RIGHT", f._scanLastRight, 0)
        row.scanLast:SetWidth(f._scanLastWidth)
        row.scanLast:SetJustifyH("RIGHT")
        row.scanLast:Hide()

        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.hl:SetBlendMode("ADD")
        row.hl:SetAlpha(0.5)
        row.hl:SetAllPoints()

        row:SetScript("OnClick", function(self)
            if f.viewMode == "scanners" then
                if self.activeSync then
                    print("|cffffaa44EpogArmory|r: already syncing from this peer — wait for it to finish.")
                    return
                end
                if self.reachable == false then
                    print(string.format(
                        "|cffffaa44EpogArmory|r: %s is offline or not in your guild/group right now — can't sync.",
                        self.scannerName or "peer"))
                    return
                end
                if self.rowGreyed then
                    print(string.format("|cffffaa44EpogArmory|r: at the %d-sync limit. Wait for one to finish first.",
                        (_G.EpogArmory and _G.EpogArmory.SyncMaxConcurrent) or 3))
                    return
                end
                -- Clicked a scanner-leaderboard row → pop confirm + trigger sync
                if self.scannerName and self.scannerName ~= "" then
                    local dlg = StaticPopup_Show("EPOGARMORY_CONFIRM_SYNC", self.scannerName)
                    if dlg then dlg.data = self.scannerName end
                end
            else
                -- Clicked a player row → open inspect frame
                if self.player and OpenInspectFor then OpenInspectFor(self.player) end
            end
        end)

        f.rows[i] = row
    end

    f.countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.countLabel:SetPoint("BOTTOM", 0, 18)

    -- v0.37: accept-sync toggle shown only in Scanners mode. Lets the user
    -- opt out of responding to incoming SYNCREQ (emergency/paranoia toggle).
    -- Default enabled on first login; state persisted in EpogArmoryDB.config.
    -- v0.38: label is parented to the button itself so Hide() hides both.
    f.acceptSyncBtn = CreateFrame("CheckButton", "EpogArmoryAcceptSyncBtn", f, "UICheckButtonTemplate")
    f.acceptSyncBtn:SetWidth(20); f.acceptSyncBtn:SetHeight(20)
    f.acceptSyncBtn:SetPoint("BOTTOMLEFT", 18, 36)
    f.acceptSyncBtn.text = f.acceptSyncBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.acceptSyncBtn.text:SetPoint("LEFT", f.acceptSyncBtn, "RIGHT", 2, 1)
    -- Claude v0.47.1: shortened from "Accept sync requests from others"
    -- to make room for the Refresh Peers button on the same footer row.
    f.acceptSyncBtn.text:SetText("Accept sync requests")
    f.acceptSyncBtn:SetScript("OnClick", function(self)
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        EpogArmoryDB.config.acceptSync = self:GetChecked() and true or false
        if EpogArmoryDB.config.acceptSync then
            print("|cffffaa44EpogArmory|r: sync-response |cff00ff66ON|r")
        else
            print("|cffffaa44EpogArmory|r: sync-response |cffff6666OFF|r (will refuse incoming SYNCREQ)")
        end
    end)
    f.acceptSyncBtn:Hide()

    -- v0.47: "Refresh Peers" button, bottom-right of the Scanners view.
    -- Broadcasts a PEERPING that asks every guildmate running the addon
    -- to announce their identity + dbSize, so the leaderboard refreshes
    -- without waiting for organic gear-scan broadcasts. Cooldown enforced
    -- on the addon side (60s); this button just relays the result.
    f.refreshPeersBtn = CreateFrame("Button", "EpogArmoryRefreshPeersBtn", f, "UIPanelButtonTemplate")
    f.refreshPeersBtn:SetWidth(110); f.refreshPeersBtn:SetHeight(22)
    -- Claude v0.47.1: bottom-right of the footer row, paired with the
    -- (shortened) "Accept sync requests" checkbox on the same y so they
    -- read as one footer rather than stacked elements.
    f.refreshPeersBtn:SetPoint("BOTTOMRIGHT", -14, 33)
    f.refreshPeersBtn:SetText("Refresh Peers")
    f.refreshPeersBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine("Refresh Peers")
        GameTooltip:AddLine("Asks every guildmate running EpogArmory to send their current identity and DB size.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Use this to discover scanners you don't see yet, or to update their entry counts.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.refreshPeersBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.refreshPeersBtn:SetScript("OnClick", function(self)
        if not (_G.EpogArmory and _G.EpogArmory.RequestPeerRefresh) then return end
        local ok, info, extra = _G.EpogArmory.RequestPeerRefresh()
        if ok then
            print(string.format("|cffffaa44EpogArmory|r: peer refresh sent on %s — responses will arrive over the next ~5s.", info))
            -- Brief visual disable to communicate "request in flight"; the
            -- 30s ticker on the Scanners view will pick up incoming pongs.
            self:Disable()
            self._reenableAt = GetTime() + 5
        elseif info == "cooldown" then
            print(string.format("|cffffaa44EpogArmory|r: peer refresh on cooldown (%ds remaining).", extra))
        elseif info == "nochannel" then
            print("|cffffaa44EpogArmory|r: peer refresh requires being in a guild or group.")
        end
    end)
    -- Re-enable after the brief disable window. Cheap OnUpdate, only ticks
    -- while a press is in flight.
    f.refreshPeersBtn:SetScript("OnUpdate", function(self)
        if self._reenableAt and GetTime() >= self._reenableAt then
            self._reenableAt = nil
            self:Enable()
        end
    end)
    f.refreshPeersBtn:Hide()

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

    -- Aggregate scanner contributions from our own stored data. Each
    -- sets[group].scannedBy tells us who originally captured that set.
    -- Combined with peer-reported DB sizes (v0.36+ piggyback on scan
    -- broadcasts), this gives us a picture of who's worth requesting a
    -- sync from.
    local function AggregateScanners()
        local stats = {} -- name -> { contributed, lastContribution }
        if EpogArmoryDB and EpogArmoryDB.players then
            for _, p in pairs(EpogArmoryDB.players) do
                if p.sets then
                    for _, set in pairs(p.sets) do
                        local by = set.scannedBy
                        if by and by ~= "" and by ~= "?" then
                            if not stats[by] then
                                stats[by] = { contributed = 0, lastContribution = 0 }
                            end
                            stats[by].contributed = stats[by].contributed + 1
                            if (set.scanTime or 0) > stats[by].lastContribution then
                                stats[by].lastContribution = set.scanTime or 0
                            end
                        end
                    end
                end
            end
        end
        -- Merge in peer-reported DB sizes (from v0.36+ piggybacked wire
        -- field at position 38). Persisted in SavedVariables so the view
        -- is useful immediately on login before fresh broadcasts arrive.
        local peerInfo = (EpogArmoryDB and EpogArmoryDB.peerInfo) or {}
        for name, info in pairs(peerInfo) do
            if not stats[name] then
                stats[name] = { contributed = 0, lastContribution = 0 }
            end
            stats[name].reportedDB = info.dbSize
            stats[name].reportedAt = info.lastSeen
            stats[name].guild      = info.guild -- Claude (v1.4.2): Guild column source
        end
        -- Claude v0.52: peerInfo never tracks self (Ingest's
        -- `effectiveScanner ~= MyIdentity()` guard skips self-writes), so
        -- our own row would always show "—" in the In DB column. Compute
        -- it inline here from EpogArmoryDB.players. Only touch reportedDB
        -- — leave reportedAt alone so the Last column keeps using
        -- lastContribution (when we last self-scanned), which is the real
        -- meaningful value for self.
        local myIdentity = (_G.EpogArmory and _G.EpogArmory.MyIdentity)
            and _G.EpogArmory.MyIdentity() or UnitName("player")
        if myIdentity and myIdentity ~= "" and stats[myIdentity] then
            local myDBSize = 0
            if EpogArmoryDB and EpogArmoryDB.players then
                for _ in pairs(EpogArmoryDB.players) do myDBSize = myDBSize + 1 end
            end
            stats[myIdentity].reportedDB = myDBSize
            -- Claude (v1.4.2): self-row Guild column. peerInfo never tracks
            -- self (Ingest's `effectiveScanner ~= MyIdentity()` guard skips
            -- self-writes), so we populate the guild live from the API here.
            if GetGuildInfo then
                local g = GetGuildInfo("player")
                if type(g) == "string" and g ~= "" then
                    stats[myIdentity].guild = g
                end
            end
        end
        -- v0.45: drop scanners whose latest signal (last contribution OR
        -- last live broadcast we heard) is older than 30 days. Keeps the
        -- leaderboard focused on currently-active peers; entries get
        -- pruned automatically rather than accumulating forever.
        local staleCutoff = time() - 30 * 86400
        local list = {}
        for name, info in pairs(stats) do
            local mostRecent = math.max(info.lastContribution or 0, info.reportedAt or 0)
            if mostRecent >= staleCutoff then
                list[#list + 1] = {
                    name             = name,
                    contributed      = info.contributed,
                    lastContribution = info.lastContribution,
                    reportedDB       = info.reportedDB,
                    reportedAt       = info.reportedAt,
                    guild            = info.guild, -- Claude (v1.4.2)
                }
            end
        end
        -- Sort by reported DB size first (primary signal — how big is their
        -- DB right now, which is what you actually want for sync targeting),
        -- fall back to historical contribution count for peers we haven't
        -- heard from in this session.
        table.sort(list, function(a, b)
            local aSize = a.reportedDB or a.contributed
            local bSize = b.reportedDB or b.contributed
            if aSize == bSize then return (a.name or "") < (b.name or "") end
            return aSize > bSize
        end)
        return list
    end

    local function UpdatePlayersMode()
        local list = {}
        if EpogArmoryDB and EpogArmoryDB.players then
            local nameFilter  = (search:GetText() or ""):lower()
            local classFilter = f.classFilter -- Claude v0.48
            for _, p in pairs(EpogArmoryDB.players) do
                if p and p.name then
                    local nameOK  = nameFilter == "" or p.name:lower():find(nameFilter, 1, true)
                    local classOK = (not classFilter) or (p.class == classFilter) -- Claude v0.48
                    if nameOK and classOK then
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
                -- Claude v0.48: columnar layout. row.text stays hidden in
                -- Players mode; the three column fontstrings carry the data.
                -- Level dropped from display (everything stored is L60+ per
                -- MIN_STORE_LEVEL gate).
                local colorStr = ClassColorStr(p.class)
                row.colName:SetText(string.format("%s%s|r", colorStr, p.name or "?"))
                row.colClass:SetText(string.format("%s%s|r", colorStr, ClassDisplayName(p.class)))
                row.colAge:SetText(string.format("%s%s|r", AgeColor(p.scanTime), FormatAge(p.scanTime)))
                row.colName:Show(); row.colClass:Show(); row.colAge:Show()
                row.text:Hide()
                -- Claude v0.49: hide scanner-mode columns when in players mode
                row.scanRank:Hide(); row.scanName:Hide(); row.scanGuild:Hide(); row.scanContrib:Hide()
                row.scanDB:Hide(); row.scanLast:Hide()
                row.player = p
                row.scannerName = nil
                -- v0.42: reset alpha. Scanners view dims rows for unreachable
                -- peers (alpha 0.55); without this reset those alpha values
                -- leak into the next render when the user toggles back to
                -- Players view, making class-colored names look greyed for
                -- no apparent reason.
                row:SetAlpha(1.0)
                row:Show()
            else
                row:Hide()
                row.player = nil
                row.scannerName = nil
                row:SetAlpha(1.0)
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
                -- Claude v0.48: include filter context when filtered. Useful
                -- with the class dropdown so the count makes sense.
                local filterDesc = ""
                if f.classFilter then
                    filterDesc = string.format(" (%s)", ClassDisplayName(f.classFilter))
                end
                f.countLabel:SetText(string.format("%d of %d match%s", #list, total, filterDesc))
            end
        end
    end

    -- v0.38: build a set of peer names that are currently reachable — i.e.
    -- we could plausibly send a SYNCREQ to them right now. Combines:
    --   - guildmates marked online by the server's guild roster
    --   - current party/raid members (regardless of guild)
    -- Unreachable peers still appear in the Scanners list (leaderboard
    -- value) but render dim and aren't clickable.
    -- v0.43: Scanners view keys can be MAIN NAMES (configured by the peer
    -- via /epogarmory main), not just character names. If the main name
    -- doesn't itself match a reachable character, look up the peer's
    -- last-broadcasting character via peerInfo.lastCharName and check that.
    local function BuildReachableSet()
        local charSet = {}
        local me = UnitName("player")
        if me then charSet[me] = true end
        for i = 1, GetNumPartyMembers() do
            local n = UnitName("party" .. i)
            if n then charSet[n] = true end
        end
        for i = 1, GetNumRaidMembers() do
            local n = UnitName("raid" .. i)
            if n then charSet[n] = true end
        end
        if IsInGuild() then
            local n = GetNumGuildMembers and GetNumGuildMembers() or 0
            for i = 1, n do
                local gname, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
                if gname and online then charSet[gname] = true end
            end
        end
        -- charSet contains character names. Build the public reachable set:
        -- character matches first, then resolve main-name peers via their
        -- last-known broadcasting character.
        local reachable = {}
        for n in pairs(charSet) do reachable[n] = true end
        if EpogArmoryDB and EpogArmoryDB.peerInfo then
            for mainName, info in pairs(EpogArmoryDB.peerInfo) do
                if info.lastCharName and charSet[info.lastCharName] then
                    reachable[mainName] = true
                end
            end
        end
        return reachable
    end

    local function UpdateScannersMode()
        local list = AggregateScanners()
        local reachable = BuildReachableSet()

        FauxScrollFrame_Update(scroll, #list, BROWSER_ROWS, BROWSER_ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(scroll)

        -- v0.37: read sync state from EpogArmory namespace.
        local isActive = (_G.EpogArmory and _G.EpogArmory.IsPeerSyncActive) or function() return false end
        local syncEndsAt = (_G.EpogArmory and _G.EpogArmory.SyncEndTimeFor) or function() return nil end
        local activeCount = (_G.EpogArmory and _G.EpogArmory.ActiveSyncCount and _G.EpogArmory.ActiveSyncCount()) or 0
        local maxConcurrent = (_G.EpogArmory and _G.EpogArmory.SyncMaxConcurrent) or 3
        local atCap = activeCount >= maxConcurrent

        for i = 1, BROWSER_ROWS do
            local row = f.rows[i]
            local s = list[i + offset]
            if s then
                local rank      = i + offset -- leaderboard position (stable even when paginated)
                local active    = isActive(s.name)
                local isReach   = reachable[s.name] == true
                local clickable = isReach and not active and not atCap

                -- Claude v0.49: 5 columns instead of single concatenated text.
                -- Stat semantics:
                --   contributed = sets stored in MY DB that this scanner
                --                 originally captured (counted from
                --                 set.scannedBy on each stored set).
                --   reportedDB  = total entries in THEIR DB at last broadcast
                --                 (carried on wire position 38 of every scan).
                -- These are different — one is what they've added to my pool,
                -- the other is what they have to share with me.
                local nameColor = clickable and "|cffffffff" or "|cff777777"
                row:SetAlpha(clickable and 1.0 or 0.55)

                row.scanRank:SetText(string.format("|cffaaaaaa#%d|r", rank))
                row.scanName:SetText(nameColor .. (s.name or "?") .. "|r")
                -- Claude (v1.4.2): Guild column. Empty string for unguilded
                -- peers and pre-v1.4.2 senders; render as a soft em-dash so
                -- the column doesn't look broken when most rows are empty.
                local guildText = s.guild
                if not guildText or guildText == "" then
                    row.scanGuild:SetText("|cff666666—|r")
                else
                    row.scanGuild:SetText(string.format("|cffaaaaff%s|r", guildText))
                end
                row.scanContrib:SetText(string.format("|cffaaaaaa%d|r", s.contributed or 0))

                if active then
                    local remain = math.max(0, (syncEndsAt(s.name) or time()) - time())
                    row.scanDB:SetText("|cff66ffccsync|r")
                    row.scanLast:SetText(string.format("|cff888888~%dm|r", math.ceil(remain / 60)))
                else
                    if s.reportedDB then
                        row.scanDB:SetText(string.format("|cffffdd44%d|r", s.reportedDB))
                    else
                        row.scanDB:SetText("|cff666666—|r")
                    end
                    -- Most-recent signal we have from this peer:
                    --   reportedAt = last broadcast we heard from them
                    --   lastContribution = last set they captured that we hold
                    -- Take the max — both are "I know this peer was alive at T".
                    local lastT = math.max(s.lastContribution or 0, s.reportedAt or 0)
                    if lastT > 0 then
                        row.scanLast:SetText(string.format("|cff888888%s|r", FormatAge(lastT)))
                    else
                        row.scanLast:SetText("|cff666666—|r")
                    end
                end

                row.scanRank:Show(); row.scanName:Show(); row.scanGuild:Show(); row.scanContrib:Show()
                row.scanDB:Show(); row.scanLast:Show()
                row.text:Hide() -- single-line text replaced by the columns
                row.colName:Hide(); row.colClass:Hide(); row.colAge:Hide()
                row.player      = nil
                row.scannerName = s.name
                row.rowGreyed   = not clickable
                row.activeSync  = active
                row.reachable   = isReach
                row:Show()
            else
                row:Hide()
                row.player      = nil
                row.scannerName = nil
                row.rowGreyed   = false
                row.activeSync  = false
                row.reachable   = false
                row:SetAlpha(1.0)
            end
        end

        if #list == 0 then
            f.emptyHint:Show()
            f.countLabel:SetText("")
        else
            f.emptyHint:Hide()
            local reachCount = 0
            for _, s in ipairs(list) do if reachable[s.name] then reachCount = reachCount + 1 end end
            if atCap then
                f.countLabel:SetText(string.format(
                    "%d scanners (%d online) · |cffff9966sync limit reached (%d/%d)|r",
                    #list, reachCount, activeCount, maxConcurrent))
            else
                f.countLabel:SetText(string.format(
                    "%d scanners (%d online) · click to sync (%d/%d active)",
                    #list, reachCount, activeCount, maxConcurrent))
            end
        end
    end

    local function Update()
        if f.viewMode == "scanners" then
            UpdateScannersMode()
        else
            UpdatePlayersMode()
        end
    end
    f._refreshList = Update -- Claude v0.48: lets the class-filter dropdown refresh

    -- emptyHint text varies by mode — stash both and switch on toggle.
    local EMPTY_HINT_PLAYERS  = "No players stored yet.\n\n|cffaaaaaaJoin a group in a dungeon or raid — this client will inspect groupmates and store their gear here. Or type|r |cffffaa44/epogarmory show <name>|r |cffaaaaaaif you've scanned someone already.|r"
    local EMPTY_HINT_SCANNERS = "No scanners known yet.\n\n|cffaaaaaaOnce you and/or guildmates running the addon do some scans, this view will show who's contributing the most. Click a row to request a sync from them.|r"

    -- Toggle button cycles viewMode and re-renders. Also hides/shows the
    -- search box (not meaningful in scanners mode) and the accept-sync
    -- checkbox (only meaningful in scanners mode).
    viewToggle:SetScript("OnClick", function()
        if f.viewMode == "scanners" then
            f.viewMode = "players"
            viewToggle:SetText("Scanners")
            f.searchLabel:Show(); search:Show()
            f.classFilterBtn:Show()  -- Claude v0.48
            f.colHeaderName:Show()   -- Claude v0.48
            f.colHeaderClass:Show()  -- Claude v0.48
            f.colHeaderAge:Show()    -- Claude v0.48
            -- Claude v0.49: hide Scanners-mode column headers
            f.scanHeaderRank:Hide(); f.scanHeaderName:Hide(); f.scanHeaderGuild:Hide()
            f.scanHeaderContrib:Hide(); f.scanHeaderDB:Hide(); f.scanHeaderLast:Hide()
            f.acceptSyncBtn:Hide()
            f.refreshPeersBtn:Hide() -- Claude v0.47
            f.emptyHint:SetText(EMPTY_HINT_PLAYERS)
        else
            f.viewMode = "scanners"
            viewToggle:SetText("Players")
            f.searchLabel:Hide(); search:Hide()
            f.classFilterBtn:Hide()  -- Claude v0.48
            f.colHeaderName:Hide()   -- Claude v0.48
            f.colHeaderClass:Hide()  -- Claude v0.48
            f.colHeaderAge:Hide()    -- Claude v0.48
            -- Claude v0.49: show Scanners-mode column headers
            f.scanHeaderRank:Show(); f.scanHeaderName:Show(); f.scanHeaderGuild:Show()
            f.scanHeaderContrib:Show(); f.scanHeaderDB:Show(); f.scanHeaderLast:Show()
            -- Sync current state from SavedVariables into the checkbox UI.
            local accept = true
            if EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.acceptSync == false then
                accept = false
            end
            f.acceptSyncBtn:SetChecked(accept)
            f.acceptSyncBtn:Show()
            f.refreshPeersBtn:Show() -- Claude v0.47
            f.emptyHint:SetText(EMPTY_HINT_SCANNERS)
            -- v0.38: ask the server for a fresh guild roster so the
            -- "online" flag is current. GuildRoster() is rate-limited
            -- server-side (~10s) so spamming is harmless.
            if IsInGuild() and GuildRoster then GuildRoster() end
        end
        -- v0.45: reset scroll offset on mode switch. Otherwise the previous
        -- view's offset (e.g. row 50 of 100 players) leaks into the new
        -- view's render — if the new list is shorter than the old offset,
        -- list[i + offset] is nil for every i and all rows render hidden
        -- even though #list says e.g. "6 scanners".
        FauxScrollFrame_SetOffset(scroll, 0)
        if scroll.ScrollBar and scroll.ScrollBar.SetValue then
            scroll.ScrollBar:SetValue(0)
        end
        Update()
    end)

    scroll:SetScript("OnVerticalScroll", function(self, o)
        FauxScrollFrame_OnVerticalScroll(self, o, BROWSER_ROW_HEIGHT, Update)
    end)
    -- v0.38: mousewheel scroll (FauxScrollFrameTemplate doesn't enable it
    -- by default). Three rows per wheel tick, standard feel. Future-proof
    -- for lists of any size.
    -- v0.54: drive the scrollbar's SetValue instead of FauxScrollFrame_SetOffset
    -- directly. The old path updated the internal offset (so the list moved)
    -- but never told the scrollbar widget about it (so the thumb stayed
    -- frozen at the top). Routing through SetValue triggers OnValueChanged →
    -- OnVerticalScroll → FauxScrollFrame_OnVerticalScroll, which updates
    -- both offset AND visual thumb in one go.
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local sb = self.ScrollBar or _G[(self:GetName() or "") .. "ScrollBar"]
        if sb then
            local cur = sb:GetValue() or 0
            local step = 3 * BROWSER_ROW_HEIGHT -- 3 rows per wheel tick (in pixels)
            if delta > 0 then
                sb:SetValue(math.max(0, cur - step))
            else
                sb:SetValue(cur + step)
            end
        else
            -- Fallback if for some reason the scrollbar widget isn't there:
            -- preserve the old offset-only behavior so wheel still works.
            local off = FauxScrollFrame_GetOffset(self) or 0
            local step = 3
            if delta > 0 then
                FauxScrollFrame_SetOffset(self, math.max(0, off - step))
            else
                FauxScrollFrame_SetOffset(self, off + step)
            end
            Update()
        end
    end)
    search:SetScript("OnTextChanged", Update)
    f:SetScript("OnShow", function(self)
        ApplySavedPosition(self)
        -- Claude v0.48: ensure Players-mode UI elements start visible (default
        -- mode is "players"). Without this, column headers + class filter
        -- only appear after the first toggle round-trip.
        if self.viewMode == "players" then
            self.classFilterBtn:Show()
            self.colHeaderName:Show()
            self.colHeaderClass:Show()
            self.colHeaderAge:Show()
        end
        if self.RefreshAuraStatus then self.RefreshAuraStatus() end -- v1.2
        Update()
    end)

    -- v0.38: 30s ticker refreshes the Scanners view whenever it's open.
    -- Catches sync countdowns, newly-online guildmates, roster changes,
    -- and peerInfo updates from incoming broadcasts. Trivially cheap
    -- outside Scanners mode (just the increment + mode check).
    -- v1.2: also refreshes the aura status banner so it tracks gain/loss
    -- of the Reality Recalibrators aura while the Browser is open.
    f:SetScript("OnUpdate", function(self, elapsed)
        self._tickAcc = (self._tickAcc or 0) + elapsed
        if self._tickAcc < 30 then return end
        self._tickAcc = 0
        if self.RefreshAuraStatus then self.RefreshAuraStatus() end -- v1.2
        if f.viewMode == "scanners" then
            if IsInGuild() and GuildRoster then GuildRoster() end
            Update()
        end
    end)

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
    -- v1.3: hide the talent side-panel too — it has no meaning without
    -- the inspect frame providing context.
    if _G.EpogArmoryTalentFrame and _G.EpogArmoryTalentFrame:IsShown() then
        _G.EpogArmoryTalentFrame:Hide()
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
        -- v1.2: prominent aura status line so users see at-a-glance whether
        -- auto-inspect is functional just by hovering the minimap button.
        local has = (_G.EpogArmory and _G.EpogArmory.HasRealityAura
            and _G.EpogArmory.HasRealityAura()) or false
        local auraName = (_G.EpogArmory and _G.EpogArmory.RealityAuraName) or "Reality Recalibrators"
        -- Claude (v1.4.1 test): honor the aura interlock flag so the tooltip
        -- doesn't claim "auto-inspect paused" when the gate is disabled.
        local requires = (_G.EpogArmory and _G.EpogArmory.RequiresRealityAura
            and _G.EpogArmory.RequiresRealityAura()) or false
        if has then
            GameTooltip:AddLine(string.format("%s: ACTIVE", auraName), 0.4, 1, 0.4)
            GameTooltip:AddLine("auto-inspect of groupmates enabled", 0.6, 0.6, 0.6)
        elseif requires then
            GameTooltip:AddLine(string.format("%s: NOT ACTIVE", auraName), 1, 0.4, 0.4)
            GameTooltip:AddLine("auto-inspect paused — Ascension transmog", 1, 0.6, 0.4)
            GameTooltip:AddLine("hides true gear without this aura", 1, 0.6, 0.4)
        else
            GameTooltip:AddLine(string.format("%s: NOT ACTIVE", auraName), 1, 0.4, 0.4)
            GameTooltip:AddLine("TEST MODE — scanning anyway", 1, 0.7, 0.3)
            GameTooltip:AddLine("(v1.4.1 settle+verify validation)", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(" ")
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
