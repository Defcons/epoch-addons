-- BuffWatcher2.lua
-- Claude: core — scan logic, status frame, export frame, button, slash commands, init.
-- Load order: BuffWatcher2_Data.lua -> BuffWatcher2.lua -> BuffWatcher2_Config.lua

BW2 = BW2 or {}

-- ── Layout constants ─────────────────────────────────────────────────────────

local STATUS_W    = 500
local STATUS_H    = 340
local ROW_H       = 20
local COL_NAME    = 140
local COL_MISSING = 344   -- Claude: STATUS_W - 16px borders - COL_NAME

local EXPORT_W    = 600
local EXPORT_H    = 400

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function C(text, hex)  -- Claude: inline WoW colour helper
    return "|cff" .. hex .. text .. "|r"
end

-- Claude: build ordered unit ID list — raid > party > solo
local function GetGroupUnits()
    local units = {}
    local nr = GetNumRaidMembers()
    if nr > 0 then
        for i = 1, nr do tinsert(units, "raid" .. i) end
    else
        local np = GetNumPartyMembers()
        for i = 1, np do tinsert(units, "party" .. i) end
        tinsert(units, "player")
    end
    return units
end

-- Claude: build label->buffs map from enabled entries; preserve label insertion order
local function BuildCheckMap()
    local map   = {}   -- label -> { buff1, buff2, ... }
    local order = {}   -- labels in first-seen order
    local seen  = {}
    for _, e in ipairs(BuffWatcher2DB.entries or {}) do
        if e.enabled ~= false then
            local lbl = e.label or ""
            local buf = e.buff  or ""
            if lbl ~= "" and buf ~= "" then
                if not seen[lbl] then
                    tinsert(order, lbl)
                    seen[lbl] = true
                    map[lbl]  = {}
                end
                tinsert(map[lbl], buf)
            end
        end
    end
    return map, order
end

-- Claude: scan one unit — returns row data for ALL existing units (not just missing)
-- so Export can produce complete OK/MISSING grid for everyone in the group
local function ScanUnit(unit, checkMap, labelOrder)
    if not UnitExists(unit) then return nil end

    -- Claude: snapshot all active buff names into a lookup set (max 40 in 3.3.5)
    local unitBuffs = {}
    for i = 1, 40 do
        local bname = UnitBuff(unit, i)
        if not bname then break end
        unitBuffs[bname] = true
    end

    local missing = {}
    for _, lbl in ipairs(labelOrder) do
        local found = false
        for _, bn in ipairs(checkMap[lbl]) do
            if unitBuffs[bn] then found = true; break end
        end
        if not found then tinsert(missing, lbl) end
    end

    -- Claude: return for ALL units — status frame filters, export needs everyone
    return {
        name      = UnitName(unit) or "?",
        classFile = select(2, UnitClass(unit)) or "UNKNOWN",
        missing   = missing,
    }
end

-- ── Scan ──────────────────────────────────────────────────────────────────────

function BW2:Refresh()
    local checkMap, labelOrder = BuildCheckMap()
    local results = {}
    local total, ok = 0, 0

    for _, unit in ipairs(GetGroupUnits()) do
        local row = ScanUnit(unit, checkMap, labelOrder)
        if row then
            total = total + 1
            tinsert(results, row)
            if #row.missing == 0 then ok = ok + 1 end
        end
    end

    self.scanResults = results
    self.scanTotal   = total
    self.scanOK      = ok
    self.lastRefresh = GetTime()
    self.labelOrder  = labelOrder  -- Claude: stored for Export TSV columns
    self:RebuildTable()
end

-- ── Status table row pool ────────────────────────────────────────────────────

local statusRowPool = {}

local function MakeStatusRow(parent, idx)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetWidth(COL_NAME + COL_MISSING)

    -- Claude: alternating background tint
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if idx % 2 == 0 then
        bg:SetTexture(0.12, 0.14, 0.22, 0.55)
    else
        bg:SetTexture(0.06, 0.07, 0.12, 0.35)
    end

    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, 0)
    line:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    line:SetTexture(0.15, 0.25, 0.45, 0.4)

    local function MakeFS(xOff, w, align)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", row, "LEFT", xOff + 3, 0)
        fs:SetWidth(w - 6)
        fs:SetHeight(ROW_H)
        fs:SetJustifyH(align or "LEFT")
        fs:SetJustifyV("MIDDLE")
        return fs
    end

    row.nameFStr = MakeFS(0,        COL_NAME,    "LEFT")
    row.missFStr = MakeFS(COL_NAME, COL_MISSING, "LEFT")
    row:Hide()
    return row
end

-- ── Table rebuild ─────────────────────────────────────────────────────────────

function BW2:RebuildTable()
    if not self.scrollChild then return end

    local results = self.scanResults or {}
    local ago     = self.lastRefresh and math.floor(GetTime() - self.lastRefresh) or 0
    local okStr   = C(tostring(self.scanOK or 0) .. " OK", "44CC66")
    local badN    = self.scanTotal - (self.scanOK or 0)
    local badStr  = C(tostring(badN) .. " issues", badN > 0 and "FF5555" or "44CC66")
    local agoStr  = C("  (" .. ago .. "s ago)", "445566")
    self.summaryText:SetText(okStr .. "  " .. badStr .. agoStr)

    for _, row in ipairs(statusRowPool) do row:Hide() end

    -- Claude: filter to only players missing something for the quick-glance view
    local displayed = {}
    for _, data in ipairs(results) do
        if #data.missing > 0 then tinsert(displayed, data) end
    end

    if #displayed == 0 then
        self.emptyLabel:Show()
        self.scrollChild:SetHeight(ROW_H)
        return
    end
    self.emptyLabel:Hide()

    local colors = BW2.ClassColors or {}
    for i, data in ipairs(displayed) do
        local row = statusRowPool[i]
        if not row then
            row = MakeStatusRow(self.scrollChild, i)
            row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
            statusRowPool[i] = row
        end
        row:Show()

        local hex = colors[data.classFile] or "FFFFFF"
        row.nameFStr:SetText(C(data.name, hex))
        row.missFStr:SetText(C(table.concat(data.missing, ", "), "FF6655"))
    end

    self.scrollChild:SetHeight(#displayed * ROW_H + 2)
end

-- ── Status frame ──────────────────────────────────────────────────────────────

function BW2:CreateStatusFrame()
    local sf = CreateFrame("Frame", "BW2StatusFrame", UIParent)
    sf:SetWidth(STATUS_W)
    sf:SetHeight(STATUS_H)
    sf:SetFrameStrata("HIGH")
    sf:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 14,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    sf:SetBackdropColor(0.03, 0.04, 0.07, 0.97)
    sf:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.9)
    sf:EnableMouse(true)
    sf:Hide()
    self.statusFrame = sf

    local closeBtn = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() sf:Hide() end)

    -- Claude: top button row — Refresh, Config, Export
    local refBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    refBtn:SetSize(70, 20)
    refBtn:SetPoint("TOPLEFT", sf, "TOPLEFT", 7, -6)
    refBtn:SetText("Refresh")
    refBtn:SetScript("OnClick", function() BW2:Refresh() end)

    local cfgBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    cfgBtn:SetSize(60, 20)
    cfgBtn:SetPoint("LEFT", refBtn, "RIGHT", 4, 0)
    cfgBtn:SetText("Config")
    cfgBtn:SetScript("OnClick", function() BW2:OpenConfig() end)

    local expBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    expBtn:SetSize(60, 20)
    expBtn:SetPoint("LEFT", cfgBtn, "RIGHT", 4, 0)
    expBtn:SetText("Export")
    expBtn:SetScript("OnClick", function() BW2:OpenExport() end)

    local sumText = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sumText:SetPoint("LEFT",  expBtn,   "RIGHT",  8, 0)
    sumText:SetPoint("RIGHT", closeBtn, "LEFT",  -4, 0)
    sumText:SetJustifyH("RIGHT")
    sumText:SetText(C("0 OK", "44CC66") .. "  " .. C("0 issues", "44CC66"))
    self.summaryText = sumText

    local div1 = sf:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  sf, "TOPLEFT",   7, -30)
    div1:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -28, -30)
    div1:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: column headers
    local hdrFrame = CreateFrame("Frame", nil, sf)
    hdrFrame:SetPoint("TOPLEFT",  sf, "TOPLEFT",  8, -32)
    hdrFrame:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -8, -32)
    hdrFrame:SetHeight(16)

    local function MakeHdr(label, xOff, w)
        local fs = hdrFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", hdrFrame, "LEFT", xOff + 3, 0)
        fs:SetWidth(w - 6)
        fs:SetJustifyH("LEFT")
        fs:SetText(C(label, "8899BB"))
    end
    MakeHdr("Player",        0,        COL_NAME)
    MakeHdr("Missing Buffs", COL_NAME, COL_MISSING)

    local div2 = sf:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT",  sf, "TOPLEFT",  7, -49)
    div2:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -7, -49)
    div2:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Claude: scroll frame for player rows
    local sfm = CreateFrame("ScrollFrame", nil, sf)
    sfm:SetPoint("TOPLEFT",     sf, "TOPLEFT",      7, -51)
    sfm:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -7,   7)
    sfm:EnableMouseWheel(true)
    sfm:SetScript("OnMouseWheel", function(self, delta)
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, v - delta * ROW_H * 3)))
    end)

    local sc = CreateFrame("Frame", nil, sfm)
    sc:SetWidth(STATUS_W - 14)
    sc:SetHeight(ROW_H)
    sfm:SetScrollChild(sc)
    self.scrollChild = sc

    local empty = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOP", sc, "TOP", 0, -12)
    empty:SetText(C("Everyone is fully buffed!", "44CC44"))
    empty:Hide()
    self.emptyLabel = empty
end

-- ── Export frame ──────────────────────────────────────────────────────────────

function BW2:CreateExportFrame()
    local ef = CreateFrame("Frame", "BW2ExportFrame", UIParent)
    ef:SetWidth(EXPORT_W)
    ef:SetHeight(EXPORT_H)
    ef:SetFrameStrata("DIALOG")
    ef:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 14,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    ef:SetBackdropColor(0.04, 0.05, 0.09, 0.97)
    ef:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.9)
    ef:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ef:SetMovable(true)
    ef:EnableMouse(true)
    ef:RegisterForDrag("LeftButton")
    ef:SetScript("OnDragStart", function(self) self:StartMoving() end)
    ef:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    ef:Hide()
    self.exportFrame = ef

    -- Claude: title
    local title = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", ef, "TOP", 0, -9)
    title:SetText("|cff88CCFFBuffWatcher|r |cffAAAAAA- Export|r")

    local closeBtn = CreateFrame("Button", nil, ef, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", ef, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() ef:Hide() end)

    -- Claude: divider below title
    local divTop = ef:CreateTexture(nil, "ARTWORK")
    divTop:SetHeight(1)
    divTop:SetPoint("TOPLEFT",  ef, "TOPLEFT",  10, -26)
    divTop:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -10, -26)
    divTop:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: instructions text
    local instrText = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instrText:SetPoint("TOPLEFT", ef, "TOPLEFT", 12, -30)
    instrText:SetText(C("Ctrl+A to select all, then Ctrl+C to copy. Paste into Excel.", "88AACC"))

    -- Claude: divider below instructions
    local divInstr = ef:CreateTexture(nil, "ARTWORK")
    divInstr:SetHeight(1)
    divInstr:SetPoint("TOPLEFT",  ef, "TOPLEFT",  10, -44)
    divInstr:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -10, -44)
    divInstr:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Claude: bottom button row
    local selectBtn = CreateFrame("Button", nil, ef, "UIPanelButtonTemplate")
    selectBtn:SetSize(80, 20)
    selectBtn:SetPoint("BOTTOMLEFT", ef, "BOTTOMLEFT", 10, 8)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        if self._exportEB then
            self._exportEB:SetFocus()
            self._exportEB:HighlightText()
        end
    end)

    local closeBtn2 = CreateFrame("Button", nil, ef, "UIPanelButtonTemplate")
    closeBtn2:SetSize(60, 20)
    closeBtn2:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -10, 8)
    closeBtn2:SetText("Close")
    closeBtn2:SetScript("OnClick", function() ef:Hide() end)

    -- Claude: divider above bottom buttons
    local divBot = ef:CreateTexture(nil, "ARTWORK")
    divBot:SetHeight(1)
    divBot:SetPoint("BOTTOMLEFT",  ef, "BOTTOMLEFT",  10, 32)
    divBot:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -10, 32)
    divBot:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: scrollable multi-line EditBox for TSV output
    -- WoW 3.3.5 has no clipboard API, so user must Ctrl+A, Ctrl+C from an EditBox
    local sfm = CreateFrame("ScrollFrame", "BW2ExportScroll", ef, "UIPanelScrollFrameTemplate")
    sfm:SetPoint("TOPLEFT",     ef, "TOPLEFT",     12, -46)
    sfm:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -30, 36)

    local eb = CreateFrame("EditBox", "BW2ExportEditBox", sfm)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont("Fonts\\ARIALN.TTF", 11, "")
    eb:SetTextColor(0.85, 0.85, 0.85)
    eb:SetWidth(EXPORT_W - 50)  -- Claude: account for scrollbar width
    eb:SetScript("OnEscapePressed", function() ef:Hide() end)

    -- Claude: "read-only" guard — WoW 3.3.5 has no SetEnabled(false) that allows selection
    -- so we reset the text on every change attempt, preventing edits but allowing Ctrl+A/C
    eb:SetScript("OnTextChanged", function(self)
        if BW2._exportText and self:GetText() ~= BW2._exportText then
            self:SetText(BW2._exportText)
            self:HighlightText()
        end
    end)

    sfm:SetScrollChild(eb)
    self._exportEB = eb
end

-- ── Export text builder ───────────────────────────────────────────────────────

function BW2:BuildExportText()
    local results    = self.scanResults or {}
    local labelOrder = self.labelOrder  or {}

    if #results == 0 then return "No group members found." end

    -- Claude: build a set of missing labels per player for fast lookup
    local missingSet = {}
    for _, data in ipairs(results) do
        local s = {}
        for _, lbl in ipairs(data.missing) do s[lbl] = true end
        missingSet[data] = s
    end

    -- Claude: sort — most missing first, then alphabetical name
    local sorted = {}
    for _, data in ipairs(results) do tinsert(sorted, data) end
    table.sort(sorted, function(a, b)
        local am, bm = #a.missing, #b.missing
        if am ~= bm then return am > bm end
        return (a.name or "") < (b.name or "")
    end)

    -- Claude: TSV header — tabs between columns so Excel auto-splits
    local lines = {}
    local hdr = "Player\tClass"
    for _, lbl in ipairs(labelOrder) do
        hdr = hdr .. "\t" .. lbl
    end
    tinsert(lines, hdr)

    -- Claude: one row per group member, OK or MISSING per label
    for _, data in ipairs(sorted) do
        local row = data.name .. "\t" .. data.classFile
        local ms  = missingSet[data]
        for _, lbl in ipairs(labelOrder) do
            row = row .. "\t" .. (ms[lbl] and "MISSING" or "OK")
        end
        tinsert(lines, row)
    end

    return table.concat(lines, "\n")
end

-- ── Export entry point ────────────────────────────────────────────────────────

function BW2:OpenExport()
    if not self.exportFrame then return end

    -- Claude: always do a fresh scan before exporting
    self:Refresh()

    local text = self:BuildExportText()
    self._exportText = text  -- Claude: stored so OnTextChanged guard can reset to it

    self._exportEB:SetText(text)
    self.exportFrame:Show()

    -- Claude: auto-focus and highlight so user can immediately Ctrl+C
    self._exportEB:SetFocus()
    self._exportEB:HighlightText()
end

-- ── Button ────────────────────────────────────────────────────────────────────

function BW2:CreateButton()
    local btn = CreateFrame("Button", "BW2Button", UIParent)
    btn:SetSize(90, 20)
    btn:SetFrameStrata("HIGH")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("RightButton")  -- Claude: right-drag to reposition

    local pos = BuffWatcher2DB.buttonPos
    if pos then
        btn:SetPoint(pos[1], UIParent, pos[3], pos[4], pos[5])
    else
        btn:SetPoint("TOP", UIParent, "TOP", 0, -220)
    end

    btn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        BuffWatcher2DB.buttonPos = { p, "UIParent", rp, x, y }
    end)

    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0.06, 0.08, 0.14, 0.92)
    btn:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.85)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER")
    lbl:SetText(C("BuffWatcher", "88CCFF"))
    self.button = btn

    local sf = self.statusFrame

    -- Claude: hover opens status popup with immediate scan
    btn:SetScript("OnEnter", function()
        BW2:Refresh()
        sf:ClearAllPoints()
        sf:SetPoint("BOTTOM", btn, "TOP", 0, 4)
        sf:Show()
        BW2.hideDelay = nil
    end)
    btn:SetScript("OnLeave", function() BW2.hideDelay = 0.4 end)

    sf:SetScript("OnEnter", function() BW2.hideDelay = nil end)
    sf:SetScript("OnLeave", function() BW2.hideDelay = 0.4 end)

    -- Claude: left-click toggles status frame
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if sf:IsShown() then
                sf:Hide()
            else
                BW2:Refresh()
                sf:ClearAllPoints()
                sf:SetPoint("BOTTOM", btn, "TOP", 0, 4)
                sf:Show()
            end
        end
    end)

    -- Claude: OnUpdate ticker — 0.4s hide delay + 5s auto-refresh (no C_Timer in 3.3.5)
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, elapsed)
        if BW2.hideDelay then
            BW2.hideDelay = BW2.hideDelay - elapsed
            if BW2.hideDelay <= 0 then
                BW2.hideDelay = nil
                sf:Hide()
            end
        end
        if sf:IsShown() then
            BW2.autoRefresh = (BW2.autoRefresh or 0) + elapsed
            if BW2.autoRefresh >= 5 then
                BW2.autoRefresh = 0
                BW2:Refresh()
            end
        else
            BW2.autoRefresh = 0
        end
    end)
end

-- ── Init ──────────────────────────────────────────────────────────────────────

local function InitDB()
    if not BuffWatcher2DB then BuffWatcher2DB = {} end
    local db = BuffWatcher2DB
    -- Claude: seed default entries on first login or when table is missing/empty
    if type(db.entries) ~= "table" or #db.entries == 0 then
        db.entries = {}
        for _, e in ipairs(BW2.DefaultEntries or {}) do
            tinsert(db.entries, { buff = e.buff, label = e.label, enabled = e.enabled })
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    InitDB()

    BW2.scanResults = {}
    BW2.scanTotal   = 0
    BW2.scanOK      = 0
    BW2.labelOrder  = {}

    BW2:CreateStatusFrame()
    BW2:CreateExportFrame()
    BW2:CreateConfigFrame()
    BW2:CreateButton()

    -- Claude: slash commands
    SLASH_BUFFWATCHER21 = "/buffwatcher2"
    SLASH_BUFFWATCHER22 = "/bw2"
    SlashCmdList["BUFFWATCHER2"] = function(msg)
        msg = strtrim(string.lower(msg or ""))
        if msg == "config" or msg == "cfg" then
            BW2:OpenConfig()
        elseif msg == "check" then
            BW2:Refresh()
            BW2.statusFrame:Show()
        elseif msg == "export" then
            BW2:OpenExport()
        elseif msg == "help" or msg == "" then
            print(C("BuffWatcher2", "88CCFF") .. " commands:")
            print("  /bw2           - toggle status window")
            print("  /bw2 config    - open configuration panel")
            print("  /bw2 check     - force immediate scan")
            print("  /bw2 export    - export scan results (TSV for Excel)")
            print("  /bw2 help      - this list")
        else
            if BW2.statusFrame:IsShown() then
                BW2.statusFrame:Hide()
            else
                BW2:Refresh()
                BW2.statusFrame:Show()
            end
        end
    end

    print(C("BuffWatcher2", "88CCFF") .. " loaded - " .. C("/bw2 help", "AAAAFF"))
end)
