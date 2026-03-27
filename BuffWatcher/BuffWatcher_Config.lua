-- BuffWatcher_Config.lua
-- Configuration frame: per-class checkboxes for every buff/consume check.
-- Opened via the "Config" button on the status frame or /bw config.
-- Loaded before BuffWatcher.lua (see TOC), so BW:OpenConfig() is defined here.

-- ── SavedVar helpers ────────────────────────────────────────────────────────

-- Claude: returns true if the check is enabled (default when key is absent)
local function IsEnabled(classFile, section, id)
    local db = BuffWatcherDB
    if not db.checks then return true end
    local cc = db.checks[classFile]
    if not cc then return true end
    local sc = cc[section]
    if not sc then return true end
    return sc[id] ~= false  -- nil = enabled, false = disabled
end

-- Claude: store nil for true (matches default) to keep the DB compact
local function SetEnabled(classFile, section, id, value)
    local db = BuffWatcherDB
    if not db.checks then db.checks = {} end
    if not db.checks[classFile] then db.checks[classFile] = {} end
    if not db.checks[classFile][section] then db.checks[classFile][section] = {} end
    db.checks[classFile][section][id] = value and nil or false
end

-- expose for use in BuffWatcher.lua
BW_IsEnabled  = IsEnabled

-- ── Layout constants ─────────────────────────────────────────────────────────

local CFG_W        = 340   -- config frame outer width
local TAB_ROW1     = { "WARRIOR", "ROGUE", "HUNTER", "PALADIN", "PRIEST" }
local TAB_ROW2     = { "MAGE", "WARLOCK", "DRUID", "SHAMAN" }
local TAB_H        = 20    -- tab button height
local TAB_BTN_W    = 60    -- tab button width
local TAB_BTN_GAP  = 2     -- gap between tab buttons
local CONTENT_X    = 8     -- left padding for content
local CB_H         = 22    -- height per checkbox row
local HDR_H        = 18    -- height for section header text
local SECTION_GAP  = 6     -- vertical gap between sections

-- ── Checkbox pool ────────────────────────────────────────────────────────────
-- Pre-built pool of {cb, lbl} pairs — reused when switching class tabs
local cbPool        = {}
local sectionHdrs   = {}   -- FontString pool for section headers
local scrollChild   = nil  -- set during CreateConfigFrame
local currentClass  = nil  -- which class tab is currently shown

local function GetPoolCB(idx, parent)  -- Claude: grow pool on demand
    if not cbPool[idx] then
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 3, 0)
        lbl:SetWidth(CFG_W - CONTENT_X - 28)
        lbl:SetJustifyH("LEFT")
        cbPool[idx] = { cb = cb, lbl = lbl }
    end
    return cbPool[idx]
end

local function GetSectionHdr(idx, parent)  -- Claude: grow header pool on demand
    if not sectionHdrs[idx] then
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetWidth(CFG_W - CONTENT_X * 2)
        fs:SetJustifyH("LEFT")
        sectionHdrs[idx] = fs
    end
    return sectionHdrs[idx]
end

-- ── Content rebuild ──────────────────────────────────────────────────────────

local function RebuildContent(classFile)
    currentClass = classFile

    -- Hide everything in the pool
    for _, pair in ipairs(cbPool) do
        pair.cb:Hide()
        pair.lbl:Hide()
    end
    for _, fs in ipairs(sectionHdrs) do
        fs:Hide()
    end

    local classDef = BW_Data[classFile]
    if not classDef then return end

    local yOff   = 0
    local cbIdx  = 0
    local hdrIdx = 0

    local function AddSection(title, section, entries)
        if not entries or #entries == 0 then return end

        -- Section header
        hdrIdx = hdrIdx + 1
        local hdr = GetSectionHdr(hdrIdx, scrollChild)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_X, -yOff)
        hdr:SetText("|cff88CCFF" .. title .. "|r")
        hdr:Show()
        yOff = yOff + HDR_H + 2

        for _, entry in ipairs(entries) do
            cbIdx = cbIdx + 1
            local pair = GetPoolCB(cbIdx, scrollChild)
            local cb, lbl = pair.cb, pair.lbl

            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_X, -yOff)
            lbl:ClearAllPoints()
            lbl:SetPoint("LEFT", cb, "RIGHT", 3, 0)

            lbl:SetText(entry.label)
            cb:SetChecked(IsEnabled(classFile, section, entry.id) and 1 or nil)

            -- Claude: capture loop vars into locals to avoid Lua 5.1 closure bug
            local cf, sec, eid = classFile, section, entry.id
            cb:SetScript("OnClick", function(self)
                local checked = self:GetChecked() and true or false
                SetEnabled(cf, sec, eid, checked)
                -- Live-refresh the status table if it's open
                if BW and BW.statusFrame and BW.statusFrame:IsShown() then
                    BW:Refresh()
                end
            end)

            cb:Show()
            lbl:Show()
            yOff = yOff + CB_H
        end

        yOff = yOff + SECTION_GAP
    end

    AddSection("World Buffs", "worldbuffs", classDef.worldbuffs)
    AddSection("Consumes",    "consumes",   classDef.consumes)

    -- Resize scroll child to exact content height
    scrollChild:SetHeight(math.max(yOff + 4, CB_H))
end

-- ── Tab button highlight ─────────────────────────────────────────────────────

local tabBtns = {}

local function SelectTab(classFile)
    -- Update highlight state on all tab buttons
    for cf, btn in pairs(tabBtns) do
        if cf == classFile then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end
    RebuildContent(classFile)
end

-- ── Config frame creation ─────────────────────────────────────────────────────

function BW:CreateConfigFrame()
    local cf = CreateFrame("Frame", "BWConfigFrame", UIParent)
    cf:SetWidth(CFG_W)
    cf:SetHeight(500)  -- will resize after first tab click
    cf:SetFrameStrata("DIALOG")
    cf:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 14,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    cf:SetBackdropColor(0.04, 0.05, 0.09, 0.97)
    cf:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.9)
    cf:SetPoint("CENTER", UIParent, "CENTER", 200, 40)
    cf:SetMovable(true)
    cf:EnableMouse(true)
    cf:RegisterForDrag("LeftButton")
    cf:SetScript("OnDragStart", function(self) self:StartMoving() end)
    cf:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    cf:Hide()
    self.configFrame = cf

    -- Title
    local title = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", cf, "TOP", 0, -9)
    title:SetText("|cff88CCFFBuffWatcher|r |cffAAAAAAAA— Config|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, cf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() cf:Hide() end)

    -- Flask checkbox (global toggle, not per-class)
    local flaskCB = CreateFrame("CheckButton", nil, cf, "UICheckButtonTemplate")
    flaskCB:SetSize(18, 18)
    flaskCB:SetPoint("TOPLEFT", cf, "TOPLEFT", CONTENT_X, -28)
    flaskCB:SetChecked(BuffWatcherDB.checkFlask ~= false and 1 or nil)
    flaskCB:SetScript("OnClick", function(self)
        BuffWatcherDB.checkFlask = self:GetChecked() and true or false
        if BW and BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
    end)
    local flaskLbl = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flaskLbl:SetPoint("LEFT", flaskCB, "RIGHT", 3, 0)
    flaskLbl:SetText("|cffFFD700Require Flask|r")
    self.flaskCB = flaskCB  -- Claude: stored so init can sync it after DB load

    -- Thin divider below flask toggle
    local div1 = cf:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -50)
    div1:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -50)
    div1:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Tab row 1
    local row1Y = -55
    for i, classFile in ipairs(TAB_ROW1) do
        local btn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
        btn:SetSize(TAB_BTN_W, TAB_H)
        btn:SetPoint("TOPLEFT", cf, "TOPLEFT",
            CONTENT_X + (i - 1) * (TAB_BTN_W + TAB_BTN_GAP), row1Y)
        btn:SetText(BW_ClassLabel[classFile] or classFile)
        -- Claude: capture classFile into local for correct closure
        local cf_local = classFile
        btn:SetScript("OnClick", function() SelectTab(cf_local) end)
        tabBtns[classFile] = btn
    end

    -- Tab row 2
    local row2Y = row1Y - TAB_H - TAB_BTN_GAP
    for i, classFile in ipairs(TAB_ROW2) do
        local btn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
        btn:SetSize(TAB_BTN_W, TAB_H)
        btn:SetPoint("TOPLEFT", cf, "TOPLEFT",
            CONTENT_X + (i - 1) * (TAB_BTN_W + TAB_BTN_GAP), row2Y)
        btn:SetText(BW_ClassLabel[classFile] or classFile)
        local cf_local = classFile
        btn:SetScript("OnClick", function() SelectTab(cf_local) end)
        tabBtns[classFile] = btn
    end

    -- Thin divider below tabs
    local tabsBottom = row2Y - TAB_H - 4
    local div2 = cf:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, tabsBottom)
    div2:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, tabsBottom)
    div2:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Scroll frame (content area for checkboxes)
    local contentTopY  = tabsBottom - 4   -- a bit of breathing room
    local sfm = CreateFrame("ScrollFrame", nil, cf)
    sfm:SetPoint("TOPLEFT",     cf, "TOPLEFT",     CONTENT_X, contentTopY)
    sfm:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 8)
    sfm:EnableMouseWheel(true)
    sfm:SetScript("OnMouseWheel", function(self, delta)
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, v - delta * CB_H * 2)))
    end)

    -- Scroll child (grows to fit content)
    local sc = CreateFrame("Frame", nil, sfm)
    sc:SetWidth(CFG_W - CONTENT_X * 2)
    sc:SetHeight(CB_H)
    sfm:SetScrollChild(sc)
    scrollChild = sc  -- module-level ref for RebuildContent

    -- Claude: auto-resize the config frame when content changes height
    -- We resize it to fit, capped at 500px, so the user doesn't need to scroll for small classes
    cf:SetScript("OnShow", function(self)
        -- Re-sync the flask checkbox visual state on every open
        if BW and BW.flaskCB then
            BW.flaskCB:SetChecked(BuffWatcherDB.checkFlask ~= false and 1 or nil)
        end
    end)

    -- Show Warrior tab by default
    SelectTab("WARRIOR")
end

-- ── Public entry point ────────────────────────────────────────────────────────

function BW:OpenConfig()
    if not self.configFrame then return end
    if self.configFrame:IsShown() then
        self.configFrame:Hide()
    else
        self.configFrame:Show()
    end
end
