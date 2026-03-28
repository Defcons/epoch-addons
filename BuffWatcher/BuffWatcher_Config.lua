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

-- ── Row pool ─────────────────────────────────────────────────────────────────
-- Each slot holds a frame containing: checkbox, two EditBoxes, delete button.
-- Pool grows on demand and is never destroyed.

local rowPool     = {}
local scrollChild = nil   -- set inside CreateConfigFrame; used by GetPoolRow

-- Claude: create a new row frame parented to scrollChild; grows pool on demand
local function GetPoolRow(idx)
    if not rowPool[idx] then
        if not scrollChild then return nil end  -- safety: not yet initialised

        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(ROW_H)
        row:SetWidth(CB_SIZE + COL_GAP * 3 + BUFF_W + LABEL_W + DEL_W)

        -- Alternating row background
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

        -- Buff name EditBox
        local buffEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        buffEB:SetSize(BUFF_W, ROW_H - 4)
        buffEB:SetPoint("LEFT", cb, "RIGHT", COL_GAP, 0)
        buffEB:SetAutoFocus(false)
        buffEB:SetMaxLetters(128)

        -- Output label EditBox
        local labelEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        labelEB:SetSize(LABEL_W, ROW_H - 4)
        labelEB:SetPoint("LEFT", buffEB, "RIGHT", COL_GAP, 0)
        labelEB:SetAutoFocus(false)
        labelEB:SetMaxLetters(64)

        -- Delete button
        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetSize(DEL_W, DEL_W)
        delBtn:SetPoint("LEFT", labelEB, "RIGHT", COL_GAP, 0)
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

    -- Hide every pooled row and clear old scripts to prevent stale closures
    for _, row in ipairs(rowPool) do
        row:Hide()
        -- Claude: nil all handlers before re-assigning — avoids double-fire from stale closures
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
        if not row then break end  -- scrollChild not ready

        row.entryIndex = i  -- Claude: runtime index; closures read row.entryIndex, not captured i

        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_X, -(i - 1) * ROW_H)
        row.cb:SetChecked(entry.enabled ~= false and 1 or nil)
        row.buffEB:SetText(entry.buff  or "")
        row.labelEB:SetText(entry.label or "")

        -- Claude: capture the row frame object (not the loop index) into closures.
        -- row.entryIndex is updated each RebuildConfig so closures always see the live index.
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
        row.buffEB:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        row.buffEB:SetScript("OnEscapePressed", function(self)
            local ent = BuffWatcherDB.entries[capturedRow.entryIndex]
            if ent then self:SetText(ent.buff or "") end
            self:ClearFocus()
        end)

        row.labelEB:SetScript("OnEditFocusLost", function(self)
            local ent = BuffWatcherDB.entries[capturedRow.entryIndex]
            if ent then ent.label = self:GetText() end
            -- Claude: live-refresh the status table so label changes appear immediately
            if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
        end)
        row.labelEB:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
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

    -- Title
    local title = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", cf, "TOP", 0, -9)
    title:SetText("|cff88CCFFBuffWatcher|r |cffAAAAAAAA— Config|r")

    -- Close button
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
    local HDR_Y = -30
    local function MakeHdr(label, xOff, w, align)
        local fs = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", cf, "TOPLEFT", CONTENT_X + xOff, HDR_Y)
        fs:SetWidth(w)
        fs:SetJustifyH(align or "LEFT")
        fs:SetText("|cff8899BB" .. label .. "|r")
    end
    local xOff = 0
    MakeHdr("✓",            xOff, CB_SIZE,  "CENTER") ; xOff = xOff + CB_SIZE  + COL_GAP
    MakeHdr("Buff Name",     xOff, BUFF_W,   "LEFT")   ; xOff = xOff + BUFF_W   + COL_GAP
    MakeHdr("Output Label",  xOff, LABEL_W,  "LEFT")

    -- Divider below headers
    local divHdr = cf:CreateTexture(nil, "ARTWORK")
    divHdr:SetHeight(1)
    divHdr:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -44)
    divHdr:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -44)
    divHdr:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Bottom buttons: Add Row + Reset to Defaults
    local addBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 20)
    addBtn:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", CONTENT_X, 8)
    addBtn:SetText("Add Row")
    addBtn:SetScript("OnClick", function()
        tinsert(BuffWatcherDB.entries, { buff = "", label = "", enabled = true })
        RebuildConfig()
        -- Claude: scroll to bottom so user sees the freshly added empty row
        if BW._cfgScroll then
            BW._cfgScroll:SetVerticalScroll(BW._cfgScroll:GetVerticalScrollRange())
        end
    end)

    local resetBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 20)
    resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        -- Claude: deep-copy defaults so edits don't corrupt BW.DefaultEntries
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

    -- Scroll frame (entry rows live here)
    local sfm = CreateFrame("ScrollFrame", nil, cf)
    sfm:SetPoint("TOPLEFT",     cf, "TOPLEFT",     CONTENT_X, -46)
    sfm:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 36)
    sfm:EnableMouseWheel(true)
    sfm:SetScript("OnMouseWheel", function(self, delta)
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, v - delta * ROW_H * 3)))
    end)
    BW._cfgScroll = sfm  -- Claude: stored so Add Row can scroll to bottom

    local sc = CreateFrame("Frame", nil, sfm)
    sc:SetWidth(CFG_W - CONTENT_X * 2 - 14)
    sc:SetHeight(ROW_H)
    sfm:SetScrollChild(sc)
    scrollChild = sc  -- module-level ref used by GetPoolRow and RebuildConfig

    -- Claude: rebuild content each time the frame opens so edits from last session show
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
