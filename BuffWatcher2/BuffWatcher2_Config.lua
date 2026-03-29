-- BuffWatcher2_Config.lua
-- Claude: configuration frame — editable two-column list of buff name -> label mappings.
-- Loaded after BuffWatcher2.lua (see TOC). Attaches BW2:CreateConfigFrame / BW2:OpenConfig.

-- ── Layout constants ──────────────────────────────────────────────────────────

local CFG_W      = 490
local CFG_H      = 480
local CONTENT_X  = 10

-- Claude: entry row column widths
local CB_SIZE    = 18
local BUFF_W     = 220
local LABEL_W    = 130
local DEL_W      = 20
local COL_GAP    = 5
local ROW_H      = 24

-- ── Styled EditBox helper ─────────────────────────────────────────────────────
-- Claude: plain EditBox + backdrop wrapper avoids InputBoxTemplate's auto-focus
-- side effects that caused the first row to appear empty in BuffWatcher v2.

local function MakeEB(parent, w, maxChars)
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
local scrollChild = nil  -- Claude: set inside CreateConfigFrame

local function GetPoolRow(idx)
    if not rowPool[idx] then
        if not scrollChild then return nil end

        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(ROW_H)
        row:SetWidth(CB_SIZE + COL_GAP * 3 + BUFF_W + LABEL_W + DEL_W)

        -- Claude: alternating row tint
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if idx % 2 == 0 then
            bg:SetTexture(0.10, 0.12, 0.20, 0.40)
        else
            bg:SetTexture(0.05, 0.06, 0.10, 0.20)
        end

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(CB_SIZE, CB_SIZE)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)

        local buffWrap, buffEB = MakeEB(row, BUFF_W, 128)
        buffWrap:SetPoint("LEFT", cb, "RIGHT", COL_GAP, 0)

        local labelWrap, labelEB = MakeEB(row, LABEL_W, 64)
        labelWrap:SetPoint("LEFT", buffWrap, "RIGHT", COL_GAP, 0)

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

    -- Claude: hide all rows and clear old scripts to prevent stale closures
    for _, row in ipairs(rowPool) do
        row:Hide()
        row.cb:SetScript("OnClick", nil)
        row.buffEB:SetScript("OnEditFocusLost",  nil)
        row.buffEB:SetScript("OnEnterPressed",   nil)
        row.buffEB:SetScript("OnEscapePressed",  nil)
        row.labelEB:SetScript("OnEditFocusLost", nil)
        row.labelEB:SetScript("OnEnterPressed",  nil)
        row.labelEB:SetScript("OnEscapePressed", nil)
        row.delBtn:SetScript("OnClick", nil)
    end

    local entries = BuffWatcher2DB.entries or {}

    for i, entry in ipairs(entries) do
        local row = GetPoolRow(i)
        if not row then break end

        row.entryIndex = i  -- Claude: runtime index read by closures at call time
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_X, -(i - 1) * ROW_H)

        row.cb:SetChecked(entry.enabled ~= false and 1 or nil)
        row.buffEB:SetText(entry.buff   or "")
        row.labelEB:SetText(entry.label or "")

        -- Claude: capture the row frame so closures read row.entryIndex at call time
        local capturedRow = row

        row.cb:SetScript("OnClick", function(self)
            local ent = BuffWatcher2DB.entries[capturedRow.entryIndex]
            if ent then ent.enabled = (self:GetChecked() and true or false) end
            if BW2.statusFrame and BW2.statusFrame:IsShown() then BW2:Refresh() end
        end)

        row.buffEB:SetScript("OnEditFocusLost", function(self)
            local ent = BuffWatcher2DB.entries[capturedRow.entryIndex]
            if ent then ent.buff = self:GetText() end
        end)
        row.buffEB:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        row.buffEB:SetScript("OnEscapePressed", function(self)
            local ent = BuffWatcher2DB.entries[capturedRow.entryIndex]
            if ent then self:SetText(ent.buff or "") end
            self:ClearFocus()
        end)

        row.labelEB:SetScript("OnEditFocusLost", function(self)
            local ent = BuffWatcher2DB.entries[capturedRow.entryIndex]
            if ent then ent.label = self:GetText() end
            if BW2.statusFrame and BW2.statusFrame:IsShown() then BW2:Refresh() end
        end)
        row.labelEB:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        row.labelEB:SetScript("OnEscapePressed", function(self)
            local ent = BuffWatcher2DB.entries[capturedRow.entryIndex]
            if ent then self:SetText(ent.label or "") end
            self:ClearFocus()
        end)

        row.delBtn:SetScript("OnClick", function()
            table.remove(BuffWatcher2DB.entries, capturedRow.entryIndex)
            RebuildConfig()
            if BW2.statusFrame and BW2.statusFrame:IsShown() then BW2:Refresh() end
        end)

        row:Show()
    end

    -- Claude: clear focus from all EditBoxes to prevent auto-focus side effects
    for _, row in ipairs(rowPool) do
        row.buffEB:ClearFocus()
        row.labelEB:ClearFocus()
    end

    scrollChild:SetHeight(math.max(#entries * ROW_H + 4, ROW_H))
end

-- ── StaticPopup for reset confirmation ────────────────────────────────────────

StaticPopupDialogs["BUFFWATCHER2_RESET_CONFIRM"] = {
    text = "Reset all BuffWatcher entries to defaults?\nThis cannot be undone.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        -- Claude: deep-copy defaults so in-game edits never corrupt BW2.DefaultEntries
        BuffWatcher2DB.entries = {}
        for _, e in ipairs(BW2.DefaultEntries or {}) do
            tinsert(BuffWatcher2DB.entries, { buff = e.buff, label = e.label, enabled = e.enabled })
        end
        RebuildConfig()
        if BW2.statusFrame and BW2.statusFrame:IsShown() then BW2:Refresh() end
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

-- ── Config frame creation ─────────────────────────────────────────────────────

function BW2:CreateConfigFrame()
    local cf = CreateFrame("Frame", "BW2ConfigFrame", UIParent)
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

    -- Claude: fixed title (no AAAAAAAA colour code leak, no unsupported UTF-8 chars)
    local title = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", cf, "TOP", 0, -9)
    title:SetText("|cff88CCFFBuffWatcher|r |cffAAAAAA- Config|r")

    local closeBtn = CreateFrame("Button", nil, cf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() cf:Hide() end)

    local divTop = cf:CreateTexture(nil, "ARTWORK")
    divTop:SetHeight(1)
    divTop:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -26)
    divTop:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -26)
    divTop:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: column headers — use WoW inline texture for checkmark (UTF-8 not in FRIZQT font)
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

    local divHdr = cf:CreateTexture(nil, "ARTWORK")
    divHdr:SetHeight(1)
    divHdr:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -44)
    divHdr:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -44)
    divHdr:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Claude: bottom buttons
    local addBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 20)
    addBtn:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", CONTENT_X, 8)
    addBtn:SetText("Add Row")
    addBtn:SetScript("OnClick", function()
        tinsert(BuffWatcher2DB.entries, { buff = "", label = "", enabled = true })
        RebuildConfig()
        if BW2._cfgScroll then
            BW2._cfgScroll:SetVerticalScroll(BW2._cfgScroll:GetVerticalScrollRange())
        end
    end)

    -- Claude: Reset shows StaticPopup confirmation instead of wiping immediately
    local resetBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 20)
    resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("BUFFWATCHER2_RESET_CONFIRM")
    end)

    local divBot = cf:CreateTexture(nil, "ARTWORK")
    divBot:SetHeight(1)
    divBot:SetPoint("BOTTOMLEFT",  cf, "BOTTOMLEFT",  CONTENT_X,  32)
    divBot:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 32)
    divBot:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: scroll frame for entry rows
    local sfm = CreateFrame("ScrollFrame", nil, cf)
    sfm:SetPoint("TOPLEFT",     cf, "TOPLEFT",     CONTENT_X, -46)
    sfm:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 36)
    sfm:EnableMouseWheel(true)
    sfm:SetScript("OnMouseWheel", function(self, delta)
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, v - delta * ROW_H * 3)))
    end)
    BW2._cfgScroll = sfm

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

function BW2:OpenConfig()
    if not self.configFrame then return end
    if self.configFrame:IsShown() then
        self.configFrame:Hide()
    else
        self.configFrame:Show()
    end
end
