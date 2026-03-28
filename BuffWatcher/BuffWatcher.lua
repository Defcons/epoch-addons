-- BuffWatcher.lua
-- Core: scan logic, status table frame, button, slash commands, init.
-- Load order: BuffWatcher_Data.lua → BuffWatcher.lua → BuffWatcher_Config.lua

BW = BW or {}

-- ── Layout constants ─────────────────────────────────────────────────────────
local STATUS_W   = 500
local STATUS_H   = 340
local ROW_H      = 20

-- Claude: two-column layout — Player name + wide Missing Buffs
local COL_NAME    = 140
local COL_MISSING = 344   -- STATUS_W - 16px borders - COL_NAME

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function C(text, hex)  -- Claude: inline colour helper
    return "|cff" .. hex .. text .. "|r"
end

-- Claude: build group unit list: raid → party → solo
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

-- Claude: build label→buffs map from currently enabled entries in the DB.
-- Also returns an ordered label list so output order matches entry order.
local function BuildCheckMap()
    local map   = {}   -- label → { buff1, buff2, ... }
    local order = {}   -- labels in first-seen insertion order
    local seen  = {}
    for _, e in ipairs(BuffWatcherDB.entries or {}) do
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

-- Claude: scan one unit; returns a row-data table or nil when fully buffed
local function ScanUnit(unit, checkMap, labelOrder)
    if not UnitExists(unit) then return nil end

    -- Snapshot all active buff names for this unit into a lookup set
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

    if #missing == 0 then return nil end

    return {
        name      = UnitName(unit),
        classFile = select(2, UnitClass(unit)),  -- Claude: 3.3.5 UnitClass returns 2 values
        missing   = missing,
    }
end

-- ── Scan ──────────────────────────────────────────────────────────────────────

function BW:Refresh()
    local checkMap, labelOrder = BuildCheckMap()
    local results = {}
    local total, ok = 0, 0

    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) then
            total = total + 1
            local row = ScanUnit(unit, checkMap, labelOrder)
            if row then
                tinsert(results, row)
            else
                ok = ok + 1
            end
        end
    end

    self.scanResults = results
    self.scanTotal   = total
    self.scanOK      = ok
    self.lastRefresh = GetTime()
    self:RebuildTable()
end

-- ── Status table row pool ────────────────────────────────────────────────────

local rowPool = {}  -- Claude: pre-built row frames, reused on every Refresh

local function MakeRow(parent, idx)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetWidth(COL_NAME + COL_MISSING)

    -- Alternating background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if idx % 2 == 0 then
        bg:SetTexture(0.12, 0.14, 0.22, 0.55)
    else
        bg:SetTexture(0.06, 0.07, 0.12, 0.35)
    end

    -- Thin top-border separator
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

function BW:RebuildTable()
    if not self.scrollChild then return end

    local results = self.scanResults or {}
    local ago     = self.lastRefresh and math.floor(GetTime() - self.lastRefresh) or 0
    local okStr   = C(tostring(self.scanOK or 0) .. " OK", "44CC66")
    local badStr  = C(tostring(#results) .. " issues", #results > 0 and "FF5555" or "44CC66")
    local agoStr  = C("  (" .. ago .. "s ago)", "445566")
    self.summaryText:SetText(okStr .. "  " .. badStr .. agoStr)

    for _, row in ipairs(rowPool) do row:Hide() end

    if #results == 0 then
        self.emptyLabel:Show()
        self.scrollChild:SetHeight(ROW_H)
        return
    end
    self.emptyLabel:Hide()

    -- Claude: resolved at runtime so Data.lua load failures degrade gracefully
    local colors = BW.ClassColors or {}

    for i, data in ipairs(results) do
        local row = rowPool[i]
        if not row then
            row = MakeRow(self.scrollChild, i)
            row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
            rowPool[i] = row
        end
        row:Show()

        local hex = colors[data.classFile] or "FFFFFF"
        row.nameFStr:SetText(C(data.name or "?", hex))
        row.missFStr:SetText(C(table.concat(data.missing, ", "), "FF6655"))
    end

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

    local closeBtn = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() sf:Hide() end)

    local refBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    refBtn:SetSize(70, 20)
    refBtn:SetPoint("TOPLEFT", sf, "TOPLEFT", 7, -6)
    refBtn:SetText("Refresh")
    refBtn:SetScript("OnClick", function() BW:Refresh() end)

    local cfgBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    cfgBtn:SetSize(60, 20)
    cfgBtn:SetPoint("LEFT", refBtn, "RIGHT", 4, 0)
    cfgBtn:SetText("Config")
    cfgBtn:SetScript("OnClick", function() BW:OpenConfig() end)

    local sumText = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sumText:SetPoint("LEFT",  cfgBtn,   "RIGHT",  8, 0)
    sumText:SetPoint("RIGHT", closeBtn, "LEFT",  -4, 0)
    sumText:SetJustifyH("RIGHT")
    sumText:SetText(C("0 OK", "44CC66") .. "  " .. C("0 issues", "44CC66"))
    self.summaryText = sumText

    local div1 = sf:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT",  sf, "TOPLEFT",   7, -30)
    div1:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -28, -30)
    div1:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Column headers
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

-- ── Button ────────────────────────────────────────────────────────────────────

function BW:CreateButton()
    local btn = CreateFrame("Button", "BWButton", UIParent)
    btn:SetSize(90, 20)
    btn:SetFrameStrata("HIGH")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("RightButton")  -- Claude: right-drag to reposition

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

    btn:SetScript("OnEnter", function()
        BW:Refresh()
        sf:ClearAllPoints()
        sf:SetPoint("BOTTOM", btn, "TOP", 0, 4)
        sf:Show()
        BW.hideDelay = nil
    end)
    btn:SetScript("OnLeave", function() BW.hideDelay = 0.4 end)

    sf:SetScript("OnEnter", function() BW.hideDelay = nil end)
    sf:SetScript("OnLeave", function() BW.hideDelay = 0.4 end)

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

    -- Claude: OnUpdate ticker — hide-delay + 5s auto-refresh (no C_Timer in 3.3.5)
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
    -- Claude: seed default entries on first login or when the table is missing/empty
    if type(db.entries) ~= "table" or #db.entries == 0 then
        db.entries = {}
        for _, e in ipairs(BW.DefaultEntries or {}) do
            tinsert(db.entries, { buff = e.buff, label = e.label, enabled = e.enabled })
        end
    end
    -- buttonPos: left nil until first drag
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    InitDB()

    BW.scanResults = {}
    BW.scanTotal   = 0
    BW.scanOK      = 0

    BW:CreateStatusFrame()
    BW:CreateConfigFrame()
    BW:CreateButton()

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
