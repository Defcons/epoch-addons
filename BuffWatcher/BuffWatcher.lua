-- BuffWatcher.lua
-- Core: scan logic, status table frame, button, slash commands, init.
-- Loaded after BuffWatcher_Data.lua and BuffWatcher_Config.lua (see TOC).

BW = BW or {}

-- ── Layout constants ─────────────────────────────────────────────────────────
local STATUS_W   = 500    -- status frame outer width
local STATUS_H   = 340    -- status frame outer height
local ROW_H      = 20     -- height per player row in the table
local MAX_ROWS   = 40     -- pre-build pool up to full raid size

-- Column widths (must total STATUS_W - 16px border = 484)
local COL_NAME   = 140
local COL_WB     = 170
local COL_CONS   = 130
local COL_FLASK  = 44

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function C(text, hex)  -- Claude: colour helper
    return "|cff" .. hex .. text .. "|r"
end

-- Claude: loop UnitBuff by index — 3.3.5 has no name-based lookup
local function UnitHasBuff(unit, buffName)
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name == buffName then return true end
    end
    return false
end

-- Claude: build list of group unit IDs (raid → party → solo)
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

-- Claude: scan a single unit; returns a row-data table or nil if fully buffed
local function ScanUnit(unit)
    if not UnitExists(unit) then return nil end

    local name = UnitName(unit)
    local _, classFile = UnitClass(unit)  -- Claude: 3.3.5 returns only 2 values
    local classDef = classFile and BW_Data[classFile]
    if not classDef then return nil end

    local db         = BuffWatcherDB
    local missWB     = {}
    local missCons   = {}

    -- Flask (always scanned regardless of checkFlask; column just dims when not required)
    local hasFlask = false
    for _, fn in ipairs(BW_Data.flasks) do
        if UnitHasBuff(unit, fn) then hasFlask = true; break end
    end

    -- World buff checks — skip if disabled in config
    for _, entry in ipairs(classDef.worldbuffs or {}) do
        if BW_IsEnabled(classFile, "worldbuffs", entry.id) then
            local found = false
            for _, bn in ipairs(entry.buffs) do
                if UnitHasBuff(unit, bn) then found = true; break end
            end
            if not found then tinsert(missWB, entry.label) end
        end
    end

    -- Consume checks — skip if disabled in config
    for _, entry in ipairs(classDef.consumes or {}) do
        if BW_IsEnabled(classFile, "consumes", entry.id) then
            local found = false
            for _, bn in ipairs(entry.buffs) do
                if UnitHasBuff(unit, bn) then found = true; break end
            end
            if not found then tinsert(missCons, entry.label) end
        end
    end

    -- Only include in the table if something is wrong
    local flaskRequired = (db.checkFlask ~= false)
    local flaskIssue    = flaskRequired and not hasFlask
    if #missWB == 0 and #missCons == 0 and not flaskIssue then return nil end

    return {
        name      = name,
        classFile = classFile,
        missWB    = missWB,
        missCons  = missCons,
        hasFlask  = hasFlask,
    }
end

-- ── Scan ──────────────────────────────────────────────────────────────────────

function BW:Refresh()  -- Claude: iterate group, collect problem rows, rebuild table
    local results = {}
    local total, ok = 0, 0

    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) then
            local _, classFile = UnitClass(unit)
            if classFile and BW_Data[classFile] then
                total = total + 1
                local row = ScanUnit(unit)
                if row then
                    tinsert(results, row)
                else
                    ok = ok + 1
                end
            end
        end
    end

    self.scanResults  = results
    self.scanTotal    = total
    self.scanOK       = ok
    self.lastRefresh  = GetTime()
    self:RebuildTable()
end

-- ── Status table row pool ────────────────────────────────────────────────────

local rowPool = {}  -- Claude: pre-built row frames, reused on every Refresh

local function MakeRow(parent, idx)  -- Claude: build one reusable table row
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetWidth(COL_NAME + COL_WB + COL_CONS + COL_FLASK)

    -- Alternating background texture
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if idx % 2 == 0 then
        bg:SetTexture(0.12, 0.14, 0.22, 0.55)
    else
        bg:SetTexture(0.06, 0.07, 0.12, 0.35)
    end
    row.bg = bg

    -- Thin top-border line for visual separation
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, 0)
    line:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    line:SetTexture(0.15, 0.25, 0.45, 0.4)

    local function MakeFS(xOff, w, align)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", row, "LEFT", xOff + 3, 0)
        fs:SetWidth(w - 6)
        fs:SetJustifyH(align or "LEFT")
        fs:SetHeight(ROW_H)
        fs:SetJustifyV("MIDDLE")
        return fs
    end

    row.nameFStr  = MakeFS(0,                              COL_NAME,  "LEFT")
    row.wbFStr    = MakeFS(COL_NAME,                       COL_WB,    "LEFT")
    row.consFStr  = MakeFS(COL_NAME + COL_WB,              COL_CONS,  "LEFT")
    row.flaskFStr = MakeFS(COL_NAME + COL_WB + COL_CONS,  COL_FLASK, "CENTER")

    row:Hide()
    return row
end

-- ── Table rebuild ─────────────────────────────────────────────────────────────

function BW:RebuildTable()  -- Claude: populate row pool from latest scan results
    if not self.scrollChild then return end

    local results = self.scanResults or {}
    local db      = BuffWatcherDB
    local flaskRequired = (db.checkFlask ~= false)

    -- Update summary line
    local ago = self.lastRefresh and math.floor(GetTime() - self.lastRefresh) or 0
    local okStr = C(tostring(self.scanOK or 0) .. " OK", "44CC66")
    local badStr = C(tostring(#results) .. " issues", #results > 0 and "FF5555" or "44CC66")
    local agoStr = C("  (" .. ago .. "s ago)", "445566")
    self.summaryText:SetText(okStr .. "  " .. badStr .. agoStr)

    -- Hide all pooled rows
    for _, row in ipairs(rowPool) do row:Hide() end

    -- Empty state
    if #results == 0 then
        self.emptyLabel:Show()
        self.scrollChild:SetHeight(ROW_H)
        return
    end
    self.emptyLabel:Hide()

    -- Populate and show rows
    for i, data in ipairs(results) do
        local row = rowPool[i]
        if not row then
            row = MakeRow(self.scrollChild, i)
            row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
            rowPool[i] = row
        end
        row:Show()

        -- Name (class-coloured)
        local hex = BW_ClassColors[data.classFile] or "FFFFFF"
        row.nameFStr:SetText(C(data.name, hex))

        -- Missing world buffs: red list, or green "(ok)"
        if #data.missWB > 0 then
            row.wbFStr:SetText(C(table.concat(data.missWB, ", "), "FF6655"))
        else
            row.wbFStr:SetText(C("ok", "44AA55"))
        end

        -- Missing consumes: red list, or green "(ok)"
        if #data.missCons > 0 then
            row.consFStr:SetText(C(table.concat(data.missCons, ", "), "FF6655"))
        else
            row.consFStr:SetText(C("ok", "44AA55"))
        end

        -- Flask column: green + / red X / grey - (when not required)
        if data.hasFlask then
            row.flaskFStr:SetText(C("+", "44CC44"))
        elseif flaskRequired then
            row.flaskFStr:SetText(C("X", "FF4444"))
        else
            row.flaskFStr:SetText(C("-", "666666"))
        end
    end

    -- Resize scroll child
    self.scrollChild:SetHeight(#results * ROW_H + 2)
end

-- ── Status frame ──────────────────────────────────────────────────────────────

function BW:CreateStatusFrame()
    local sf = CreateFrame("Frame", "BWStatusFrame", UIParent)
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

    -- Close button
    local closeBtn = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() sf:Hide() end)

    -- Refresh button
    local refBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    refBtn:SetSize(70, 20)
    refBtn:SetPoint("TOPLEFT", sf, "TOPLEFT", 7, -6)
    refBtn:SetText("Refresh")
    refBtn:SetScript("OnClick", function() BW:Refresh() end)

    -- Config button
    local cfgBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    cfgBtn:SetSize(60, 20)
    cfgBtn:SetPoint("LEFT", refBtn, "RIGHT", 4, 0)
    cfgBtn:SetText("Config")
    cfgBtn:SetScript("OnClick", function() BW:OpenConfig() end)

    -- Summary text (right of buttons, left of close)
    local sumText = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sumText:SetPoint("LEFT",  cfgBtn,   "RIGHT",    8, 0)
    sumText:SetPoint("RIGHT", closeBtn, "LEFT",    -4, 0)
    sumText:SetJustifyH("RIGHT")
    sumText:SetText(C("0 OK", "44CC66") .. "  " .. C("0 issues", "44CC66"))
    self.summaryText = sumText

    -- Divider below top bar
    local div1 = sf:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  sf, "TOPLEFT",  7, -30)
    div1:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -28, -30)
    div1:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Column header row
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
    MakeHdr("Player",      0,                            COL_NAME)
    MakeHdr("World Buffs", COL_NAME,                     COL_WB)
    MakeHdr("Consumes",    COL_NAME + COL_WB,            COL_CONS)
    MakeHdr("Flsk",        COL_NAME + COL_WB + COL_CONS, COL_FLASK)

    -- Thin column-header divider
    local div2 = sf:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT",  sf, "TOPLEFT",  7, -49)
    div2:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -7, -49)
    div2:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Scroll frame (player rows)
    local sfm = CreateFrame("ScrollFrame", nil, sf)
    sfm:SetPoint("TOPLEFT",     sf, "TOPLEFT",     7, -51)
    sfm:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -7, 7)
    sfm:EnableMouseWheel(true)
    sfm:SetScript("OnMouseWheel", function(self, delta)
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, v - delta * ROW_H * 3)))
    end)

    -- Scroll child
    local sc = CreateFrame("Frame", nil, sfm)
    sc:SetWidth(STATUS_W - 14)
    sc:SetHeight(ROW_H)
    sfm:SetScrollChild(sc)
    self.scrollChild = sc

    -- Empty state label
    local empty = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOP", sc, "TOP", 0, -12)
    empty:SetText(C("Everyone is fully buffed!", "44CC44"))
    empty:Hide()
    self.emptyLabel = empty
end

-- ── Button ────────────────────────────────────────────────────────────────────

function BW:CreateButton()
    local btn = CreateFrame("Button", "BWButton", UIParent)
    btn:SetSize(90, 20)
    btn:SetFrameStrata("HIGH")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("RightButton")  -- Claude: right-drag to move

    -- Restore saved position or use default
    local pos = BuffWatcherDB.buttonPos
    if pos then
        btn:SetPoint(pos[1], UIParent, pos[3], pos[4], pos[5])
    else
        btn:SetPoint("TOP", UIParent, "TOP", 0, -220)
    end

    btn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        BuffWatcherDB.buttonPos = { p, "UIParent", rp, x, y }
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

    -- Hover: open popup and scan
    btn:SetScript("OnEnter", function()
        BW:Refresh()
        sf:ClearAllPoints()
        sf:SetPoint("BOTTOM", btn, "TOP", 0, 4)
        sf:Show()
        BW.hideDelay = nil
    end)
    btn:SetScript("OnLeave", function() BW.hideDelay = 0.4 end)

    -- Keep frame open while mouse is inside it
    sf:SetScript("OnEnter", function() BW.hideDelay = nil end)
    sf:SetScript("OnLeave", function() BW.hideDelay = 0.4 end)

    -- Left-click: toggle
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if sf:IsShown() then
                sf:Hide()
            else
                BW:Refresh()
                sf:ClearAllPoints()
                sf:SetPoint("BOTTOM", btn, "TOP", 0, 4)
                sf:Show()
            end
        end
    end)

    -- Claude: OnUpdate ticker — hide delay + 5s auto-refresh (no C_Timer in 3.3.5)
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, elapsed)
        if BW.hideDelay then
            BW.hideDelay = BW.hideDelay - elapsed
            if BW.hideDelay <= 0 then
                BW.hideDelay = nil
                sf:Hide()
            end
        end
        if sf:IsShown() then
            BW.autoRefresh = (BW.autoRefresh or 0) + elapsed
            if BW.autoRefresh >= 5 then
                BW.autoRefresh = 0
                BW:Refresh()
            end
        else
            BW.autoRefresh = 0
        end
    end)
end

-- ── Init ──────────────────────────────────────────────────────────────────────

local function InitDB()
    if not BuffWatcherDB then BuffWatcherDB = {} end
    local db = BuffWatcherDB
    if type(db.checks) ~= "table" then db.checks     = {} end
    if db.checkFlask   == nil     then db.checkFlask  = true end
    -- buttonPos: left nil until first drag
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    InitDB()

    -- Seed result state so RebuildTable() never errors before first scan
    BW.scanResults = {}
    BW.scanTotal   = 0
    BW.scanOK      = 0

    BW:CreateStatusFrame()
    BW:CreateConfigFrame()
    BW:CreateButton()

    -- Sync flask checkbox with loaded DB value
    if BW.flaskCB then
        BW.flaskCB:SetChecked(BuffWatcherDB.checkFlask ~= false and 1 or nil)
    end

    -- Slash commands
    SLASH_BUFFWATCHER1 = "/buffwatcher"
    SLASH_BUFFWATCHER2 = "/bw"
    SlashCmdList["BUFFWATCHER"] = function(msg)
        msg = strtrim(string.lower(msg or ""))
        if msg == "config" or msg == "cfg" then
            BW:OpenConfig()
        elseif msg == "check" then
            BW:Refresh()
            BW.statusFrame:Show()
        elseif msg == "help" or msg == "" then
            print(C("BuffWatcher", "88CCFF") .. " commands:")
            print("  /bw           — toggle status window")
            print("  /bw config    — open configuration panel")
            print("  /bw check     — force immediate scan")
            print("  /bw help      — this list")
        else
            if BW.statusFrame:IsShown() then
                BW.statusFrame:Hide()
            else
                BW:Refresh()
                BW.statusFrame:Show()
            end
        end
    end

    print(C("BuffWatcher", "88CCFF") .. " loaded — " .. C("/bw help", "AAAAFF"))
end)
