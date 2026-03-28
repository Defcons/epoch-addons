-- BuffWatcher_Config.lua
-- Configuration frame: editable two-column list mapping buff names to output labels.
-- Claude: Loaded after BuffWatcher.lua (see TOC). Attaches BW:CreateConfigFrame / BW:OpenConfig.

-- ── Layout constants ──────────────────────────────────────────────────────────

local CFG_W      = 490    -- config frame outer width
local CFG_H      = 480    -- config frame height
local CONTENT_X  = 10     -- left padding inside the frame content area

-- Claude: entry row column widths
local CB_SIZE    = 18     -- checkbox square
local BUFF_W     = 220    -- "Buff Name" EditBox width
local LABEL_W    = 130    -- "Output Label" EditBox width
local DEL_W      = 20     -- delete button
local COL_GAP    = 5      -- gap between columns
local ROW_H      = 24     -- height per config row

-- ── Styled EditBox helper ─────────────────────────────────────────────────────
-- Claude: avoids InputBoxTemplate entirely — that template's OnLoad script can
-- auto-focus the first box it creates and interfere with SetText during OnShow,
-- causing the first row to appear empty.  Plain EditBox + backdrop Frame is safe.

local function MakeEB(parent, w, maxChars)
    -- Visible wrapper frame gives the EditBox its dark border/background
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:SetSize(w, ROW_H - 2)
    wrap:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 4, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    wrap:SetBackdropColor(0.06, 0.07, 0.14, 0.92)
    wrap:SetBackdropBorderColor(0.28, 0.42, 0.65, 0.80)

    -- Plain EditBox has no template side-effects
    local eb = CreateFrame("EditBox", nil, wrap)
    eb:SetPoint("TOPLEFT",     wrap, "TOPLEFT",      4, -2)
    eb:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -4,  2)
    eb:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    eb:SetTextColor(0.90, 0.90, 0.90)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxChars or 128)

    return wrap, eb
end

-- ── Row pool ─────────────────────────────────────────────────────────────────

local rowPool     = {}
local scrollChild = nil   -- set inside CreateConfigFrame

-- Claude: grow pool on demand; rows are parented to scrollChild permanently
local function GetPoolRow(idx)
    if not rowPool[idx] then
        if not scrollChild then return nil end

        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(ROW_H)
        row:SetWidth(CB_SIZE + COL_GAP * 3 + BUFF_W + LABEL_W + DEL_W)

        -- Alternating row tint
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if idx % 2 == 0 then
            bg:SetTexture(0.10, 0.12, 0.20, 0.40)
        else
            bg:SetTexture(0.05, 0.06, 0.10, 0.20)
        end

        -- Enabled checkbox
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(CB_SIZE, CB_SIZE)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)

        -- Buff name EditBox (via wrapper)
        local buffWrap, buffEB = MakeEB(row, BUFF_W, 128)
        buffWrap:SetPoint("LEFT", cb, "RIGHT", COL_GAP, 0)

        -- Output label EditBox (via wrapper)
        local labelWrap, labelEB = MakeEB(row, LABEL_W, 64)
        labelWrap:SetPoint("LEFT", buffWrap, "RIGHT", COL_GAP, 0)

        -- Delete button
        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetSize(DEL_W, DEL_W)
        delBtn:SetPoint("LEFT", labelWrap, "RIGHT", COL_GAP, 0)
        delBtn:SetText("X")

        row.cb      = cb
        row.buffEB  = buffEB
        row.labelEB = labelEB
        row.delBtn  = delBtn

        rowPool[idx] = row
    end
    return rowPool[idx]
end

-- ── Config rebuild ────────────────────────────────────────────────────────────

local function RebuildConfig()
    if not scrollChild then return end

    -- Hide all rows and clear stale scripts before reassigning
    for _, row in ipairs(rowPool) do
        row:Hide()
        -- Claude: clear all scripts — prevents stale closures from firing after rebuild
        row.cb:SetScript("OnClick", nil)
        row.buffEB:SetScript("OnEditFocusLost",  nil)
        row.buffEB:SetScript("OnEnterPressed",   nil)
        row.buffEB:SetScript("OnEscapePressed",  nil)
        row.labelEB:SetScript("OnEditFocusLost", nil)
        row.labelEB:SetScript("OnEnterPressed",  nil)
        row.labelEB:SetScript("OnEscapePressed", nil)
        row.delBtn:SetScript("OnClick", nil)
    end

    local entries = BuffWatcherDB.entries or {}

    for i, entry in ipairs(entries) do
        local row = GetPoolRow(i)
        if not row then break end

        -- Claude: store index on the frame so closures can read the live value
        row.entryIndex = i
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_X, -(i - 1) * ROW_H)

        row.cb:SetChecked(entry.enabled ~= false and 1 or nil)
        row.buffEB:SetText(entry.buff   or "")
        row.labelEB:SetText(entry.label or "")

        -- Claude: capture row frame (not loop index i) so deletes that shift indices
        -- don't corrupt closures — closures re-read row.entryIndex at call time
        local capturedRow = row

        row.cb:SetScript("OnClick", function(self)
            local ent = BuffWatcherDB.entries[capturedRow.entryIndex]
            if ent then ent.enabled = (self:GetChecked() and true or false) end
            if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
        end)

        row.buffEB:SetScript("OnEditFocusLost", function(self)
            local ent = BuffWatcherDB.entries[capturedRow.entryIndex]
            if ent then ent.buff = self:GetText() end
        end)
        row.buffEB:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        row.buffEB:SetScript("OnEscapePressed", function(self)
            local ent = BuffWatcherDB.entries[capturedRow.entryIndex]
            if ent then self:SetText(ent.buff or "") end
            self:ClearFocus()
        end)

        row.labelEB:SetScript("OnEditFocusLost", function(self)
            local ent = BuffWatcherDB.entries[capturedRow.entryIndex]
            if ent then ent.label = self:GetText() end
            if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
        end)
        row.labelEB:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        row.labelEB:SetScript("OnEscapePressed", function(self)
            local ent = BuffWatcherDB.entries[capturedRow.entryIndex]
            if ent then self:SetText(ent.label or "") end
            self:ClearFocus()
        end)

        row.delBtn:SetScript("OnClick", function()
            table.remove(BuffWatcherDB.entries, capturedRow.entryIndex)
            RebuildConfig()
            if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
        end)

        row:Show()
    end

    -- Claude: explicitly clear focus from every EditBox after populating —
    -- prevents the first row from appearing empty due to auto-focus side effects
    for _, row in ipairs(rowPool) do
        row.buffEB:ClearFocus()
        row.labelEB:ClearFocus()
    end

    scrollChild:SetHeight(math.max(#entries * ROW_H + 4, ROW_H))
end

-- ── Config frame creation ─────────────────────────────────────────────────────

function BW:CreateConfigFrame()
    local cf = CreateFrame("Frame", "BWConfigFrame", UIParent)
    cf:SetWidth(CFG_W)
    cf:SetHeight(CFG_H)
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

    -- Claude: title used |cffAAAAAAAA (8 hex chars) before — WoW reads 6 so "AA" leaked as text
    local title = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", cf, "TOP", 0, -9)
    title:SetText("|cff88CCFFBuffWatcher|r |cffAAAAAA- Config|r")

    local closeBtn = CreateFrame("Button", nil, cf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() cf:Hide() end)

    -- Divider below title
    local divTop = cf:CreateTexture(nil, "ARTWORK")
    divTop:SetHeight(1)
    divTop:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -26)
    divTop:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -26)
    divTop:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Column headers
    -- Claude: replaced UTF-8 checkmark ✓ (U+2713) with WoW inline texture —
    -- the character is not in WoW 3.3.5's FRIZQT font and rendered as "?"
    local HDR_Y = -30
    local function MakeHdr(label, xOff, w, align)
        local fs = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", cf, "TOPLEFT", CONTENT_X + xOff, HDR_Y)
        fs:SetWidth(w)
        fs:SetJustifyH(align or "LEFT")
        fs:SetText("|cff8899BB" .. label .. "|r")
    end
    local hx = 0
    MakeHdr("|TInterface\\Buttons\\UI-CheckBox-Check:13:13|t", hx, CB_SIZE, "CENTER")
    hx = hx + CB_SIZE + COL_GAP
    MakeHdr("Buff Name",    hx, BUFF_W,  "LEFT")
    hx = hx + BUFF_W + COL_GAP
    MakeHdr("Output Label", hx, LABEL_W, "LEFT")

    -- Divider below headers
    local divHdr = cf:CreateTexture(nil, "ARTWORK")
    divHdr:SetHeight(1)
    divHdr:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -44)
    divHdr:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -44)
    divHdr:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Bottom buttons
    local addBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 20)
    addBtn:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", CONTENT_X, 8)
    addBtn:SetText("Add Row")
    addBtn:SetScript("OnClick", function()
        tinsert(BuffWatcherDB.entries, { buff = "", label = "", enabled = true })
        RebuildConfig()
        -- Claude: scroll to bottom so the user immediately sees the new empty row
        if BW._cfgScroll then
            BW._cfgScroll:SetVerticalScroll(BW._cfgScroll:GetVerticalScrollRange())
        end
    end)

    local resetBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 20)
    resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        -- Claude: deep-copy so in-game edits never corrupt BW.DefaultEntries
        BuffWatcherDB.entries = {}
        for _, e in ipairs(BW.DefaultEntries or {}) do
            tinsert(BuffWatcherDB.entries, { buff = e.buff, label = e.label, enabled = e.enabled })
        end
        RebuildConfig()
        if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
    end)

    -- Divider above bottom buttons
    local divBot = cf:CreateTexture(nil, "ARTWORK")
    divBot:SetHeight(1)
    divBot:SetPoint("BOTTOMLEFT",  cf, "BOTTOMLEFT",  CONTENT_X,  32)
    divBot:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 32)
    divBot:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Scroll frame
    local sfm = CreateFrame("ScrollFrame", nil, cf)
    sfm:SetPoint("TOPLEFT",     cf, "TOPLEFT",     CONTENT_X, -46)
    sfm:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 36)
    sfm:EnableMouseWheel(true)
    sfm:SetScript("OnMouseWheel", function(self, delta)
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, v - delta * ROW_H * 3)))
    end)
    BW._cfgScroll = sfm

    local sc = CreateFrame("Frame", nil, sfm)
    sc:SetWidth(CFG_W - CONTENT_X * 2 - 14)
    sc:SetHeight(ROW_H)
    sfm:SetScrollChild(sc)
    scrollChild = sc

    cf:SetScript("OnShow", function()
        RebuildConfig()
    end)
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
