-- BuffWatcher.lua
-- Claude: core — spec detection, inspect queue, scan logic, status frame, export frame, button, slash commands, init.
-- Load order: BuffWatcher_Data.lua -> BuffWatcher.lua -> BuffWatcher_Config.lua

BW = BW or {}

-- ── Layout constants ─────────────────────────────────────────────────────────

local STATUS_W    = 540 -- Claude: wider to fit role column
local STATUS_H    = 360
local ROW_H       = 20
local COL_ROLE    = 60  -- Claude: new role column
local COL_NAME    = 120
local COL_MISSING = STATUS_W - 14 - COL_ROLE - COL_NAME -- Claude: remainder

local EXPORT_W    = 600
local EXPORT_H    = 400

local INSPECT_TIMEOUT = 3 -- Claude: seconds before falling back to class default

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function C(text, hex) -- Claude: inline WoW colour helper
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

-- ── Spec / Role detection ────────────────────────────────────────────────────

-- Claude: detect the player's own spec from talent tab point distribution (instant, no inspect)
local function GetPlayerRole()
    local classFile = select(2, UnitClass("player"))
    local specMap = BW.SPEC_ROLE_MAP[classFile]
    if not specMap then return BW.CLASS_DEFAULT_ROLE[classFile] or "Melee" end

    -- Claude: check for user overrides in SavedVariables
    local overrides = BuffWatcherDB and BuffWatcherDB.specRoles and BuffWatcherDB.specRoles[classFile]

    local maxPts, maxTab = 0, 1
    for tab = 1, 3 do
        local _, _, pts = GetTalentTabInfo(tab) -- Claude: no inspect flag = player's own talents
        if pts and pts > maxPts then
            maxPts = pts
            maxTab = tab
        end
    end

    if overrides and overrides[maxTab] then return overrides[maxTab] end -- Claude: user override
    return specMap[maxTab]
end

-- Claude: detect role from inspected talent data (called after INSPECT_TALENT_READY)
local function GetInspectRole(classFile)
    local specMap = BW.SPEC_ROLE_MAP[classFile]
    if not specMap then return BW.CLASS_DEFAULT_ROLE[classFile] or "Melee" end

    local overrides = BuffWatcherDB and BuffWatcherDB.specRoles and BuffWatcherDB.specRoles[classFile]

    local maxPts, maxTab = 0, 1
    for tab = 1, 3 do
        local _, _, pts = GetTalentTabInfo(tab, true) -- Claude: true = inspect data
        if pts and pts > maxPts then
            maxPts = pts
            maxTab = tab
        end
    end

    if overrides and overrides[maxTab] then return overrides[maxTab] end
    return specMap[maxTab]
end

-- Claude: get role for a unit from cache, or fallback to class default
local function GetUnitRole(unit)
    if UnitIsUnit(unit, "player") then return GetPlayerRole() end

    local guid = UnitGUID(unit)
    if guid and BW.inspectResults[guid] then
        return BW.inspectResults[guid].role
    end

    -- Claude: fallback to class default
    local classFile = select(2, UnitClass(unit))
    return BW.CLASS_DEFAULT_ROLE[classFile or "WARRIOR"] or "Melee"
end

-- ── Inspect queue ────────────────────────────────────────────────────────────
-- Claude: inspect raid members one at a time to detect their talent spec.
-- Results cached by GUID in BW.inspectResults.

BW.inspectQueue   = {} -- Claude: list of { unit, guid, classFile }
BW.inspectCurrent = nil -- Claude: currently inspecting entry
BW.inspectResults = {} -- Claude: guid -> { classFile, role }
BW.inspectTimer   = 0  -- Claude: timeout accumulator

local function InspectNext()
    -- Claude: pop next unit from queue
    while #BW.inspectQueue > 0 do
        local entry = table.remove(BW.inspectQueue, 1)
        -- Claude: skip if already cached or unit no longer exists
        if not BW.inspectResults[entry.guid] and UnitExists(entry.unit) and UnitIsConnected(entry.unit) then
            if CanInspect(entry.unit) then -- Claude: 3.3.5 API check
                BW.inspectCurrent = entry
                BW.inspectTimer = 0
                NotifyInspect(entry.unit)
                return
            else
                -- Claude: can't inspect (too far, etc.) — use class default
                BW.inspectResults[entry.guid] = {
                    classFile = entry.classFile,
                    role = BW.CLASS_DEFAULT_ROLE[entry.classFile] or "Melee",
                }
            end
        end
    end
    BW.inspectCurrent = nil
end

-- Claude: queue all group members for inspection
local function QueueGroupInspects()
    BW.inspectQueue = {}
    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local guid = UnitGUID(unit)
            if guid and not BW.inspectResults[guid] then
                local classFile = select(2, UnitClass(unit))
                tinsert(BW.inspectQueue, { unit = unit, guid = guid, classFile = classFile or "WARRIOR" })
            end
        end
    end
    if not BW.inspectCurrent then InspectNext() end
end

-- ── Inspect event handling ───────────────────────────────────────────────────

local inspectFrame = CreateFrame("Frame")
inspectFrame:RegisterEvent("INSPECT_TALENT_READY")
inspectFrame:SetScript("OnEvent", function()
    if not BW.inspectCurrent then return end

    local entry = BW.inspectCurrent
    local role = GetInspectRole(entry.classFile)
    BW.inspectResults[entry.guid] = { classFile = entry.classFile, role = role }
    BW.inspectCurrent = nil
    InspectNext()
end)

-- Claude: timeout ticker for inspect — if no response in INSPECT_TIMEOUT seconds, fall back
local inspectTicker = CreateFrame("Frame")
inspectTicker:SetScript("OnUpdate", function(self, elapsed)
    if not BW.inspectCurrent then return end
    BW.inspectTimer = BW.inspectTimer + elapsed
    if BW.inspectTimer >= INSPECT_TIMEOUT then
        -- Claude: timed out — use class default
        local entry = BW.inspectCurrent
        BW.inspectResults[entry.guid] = {
            classFile = entry.classFile,
            role = BW.CLASS_DEFAULT_ROLE[entry.classFile] or "Melee",
        }
        BW.inspectCurrent = nil
        InspectNext()
    end
end)

-- ── Build check map for a role ───────────────────────────────────────────────

-- Claude: build label->buffs map from enabled entries for a specific role
local function BuildCheckMap(role)
    local db = BuffWatcherDB
    if not db or not db.roles or not db.roles[role] then return {}, {} end

    local entries = db.roles[role].entries or {}
    local map   = {} -- label -> { buff1, buff2, ... }
    local order = {} -- labels in first-seen order
    local seen  = {}
    for _, e in ipairs(entries) do
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

-- ── Scan ─────────────────────────────────────────────────────────────────────

-- Claude: scan one unit against their role's check map
local function ScanUnit(unit, checkMap, labelOrder)
    if not UnitExists(unit) then return nil end

    -- Claude: snapshot all active buff names (max 40 in 3.3.5)
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

    local role = GetUnitRole(unit)

    return {
        name      = UnitName(unit) or "?",
        classFile = select(2, UnitClass(unit)) or "UNKNOWN",
        role      = role,
        missing   = missing,
    }
end

function BW:Refresh()
    local results = {}
    local total, ok = 0, 0

    -- Claude: pre-build check maps for all roles that have entries
    local checkMaps  = {} -- role -> map
    local labelOrders = {} -- role -> order
    for _, role in ipairs(BW.ROLES) do
        checkMaps[role], labelOrders[role] = BuildCheckMap(role)
    end

    -- Claude: collect all unique labels across all roles for export column ordering
    local allLabels = {}
    local allLabelSeen = {}
    for _, role in ipairs(BW.ROLES) do
        for _, lbl in ipairs(labelOrders[role] or {}) do
            if not allLabelSeen[lbl] then
                tinsert(allLabels, lbl)
                allLabelSeen[lbl] = true
            end
        end
    end

    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) then
            local role = GetUnitRole(unit)
            local cmap = checkMaps[role] or {}
            local lord = labelOrders[role] or {}
            local row  = ScanUnit(unit, cmap, lord)
            if row then
                total = total + 1
                tinsert(results, row)
                if #row.missing == 0 then ok = ok + 1 end
            end
        end
    end

    self.scanResults = results
    self.scanTotal   = total
    self.scanOK      = ok
    self.lastRefresh = GetTime()
    self.labelOrder  = allLabels -- Claude: union of all role labels for export
    self.checkMaps   = checkMaps
    self.labelOrders = labelOrders
    self:RebuildTable()
end

-- ── Status table row pool ────────────────────────────────────────────────────

local statusRowPool = {}

local function MakeStatusRow(parent, idx)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetWidth(COL_ROLE + COL_NAME + COL_MISSING)

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

    row.roleFStr = MakeFS(0,                          COL_ROLE,    "LEFT") -- Claude: role column
    row.nameFStr = MakeFS(COL_ROLE,                   COL_NAME,    "LEFT")
    row.missFStr = MakeFS(COL_ROLE + COL_NAME,        COL_MISSING, "LEFT")
    row:Hide()
    return row
end

-- ── Table rebuild ────────────────────────────────────────────────────────────

function BW:RebuildTable()
    if not self.scrollChild then return end

    local results = self.scanResults or {}
    local ago     = self.lastRefresh and math.floor(GetTime() - self.lastRefresh) or 0
    local okStr   = C(tostring(self.scanOK or 0) .. " OK", "44CC66")
    local badN    = self.scanTotal - (self.scanOK or 0)
    local badStr  = C(tostring(badN) .. " issues", badN > 0 and "FF5555" or "44CC66")
    local agoStr  = C("  (" .. ago .. "s ago)", "445566")
    self.summaryText:SetText(okStr .. "  " .. badStr .. agoStr)

    for _, row in ipairs(statusRowPool) do row:Hide() end

    -- Claude: filter to only players missing something
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

    local colors     = BW.ClassColors or {}
    local roleColors = BW.RoleColors  or {}
    for i, data in ipairs(displayed) do
        local row = statusRowPool[i]
        if not row then
            row = MakeStatusRow(self.scrollChild, i)
            row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
            statusRowPool[i] = row
        end
        row:Show()

        local roleHex  = roleColors[data.role] or "AAAAAA"
        local classHex = colors[data.classFile] or "FFFFFF"
        row.roleFStr:SetText(C(data.role or "?", roleHex))
        row.nameFStr:SetText(C(data.name, classHex))
        row.missFStr:SetText(C(table.concat(data.missing, ", "), "FF6655"))
    end

    self.scrollChild:SetHeight(#displayed * ROW_H + 2)
end

-- ── Status frame ─────────────────────────────────────────────────────────────

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

    -- Claude: top button row — Refresh, Config, Export
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

    local expBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    expBtn:SetSize(60, 20)
    expBtn:SetPoint("LEFT", cfgBtn, "RIGHT", 4, 0)
    expBtn:SetText("Export")
    expBtn:SetScript("OnClick", function() BW:OpenExport() end)

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

    -- Claude: column headers — Role, Player, Missing Buffs
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
    MakeHdr("Role",          0,                          COL_ROLE)
    MakeHdr("Player",        COL_ROLE,                   COL_NAME)
    MakeHdr("Missing Buffs", COL_ROLE + COL_NAME,        COL_MISSING)

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

-- ── Export frame ─────────────────────────────────────────────────────────────

function BW:CreateExportFrame()
    local ef = CreateFrame("Frame", "BWExportFrame", UIParent)
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

    local title = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", ef, "TOP", 0, -9)
    title:SetText("|cff88CCFFBuffWatcher|r |cffAAAAAA- Export|r")

    local closeBtn = CreateFrame("Button", nil, ef, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", ef, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() ef:Hide() end)

    local divTop = ef:CreateTexture(nil, "ARTWORK")
    divTop:SetHeight(1)
    divTop:SetPoint("TOPLEFT",  ef, "TOPLEFT",  10, -26)
    divTop:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -10, -26)
    divTop:SetTexture(0.25, 0.45, 0.75, 0.35)

    local instrText = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instrText:SetPoint("TOPLEFT", ef, "TOPLEFT", 12, -30)
    instrText:SetText(C("Ctrl+A to select all, then Ctrl+C to copy. Paste into Excel.", "88AACC"))

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

    local divBot = ef:CreateTexture(nil, "ARTWORK")
    divBot:SetHeight(1)
    divBot:SetPoint("BOTTOMLEFT",  ef, "BOTTOMLEFT",  10, 32)
    divBot:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -10, 32)
    divBot:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: scrollable multi-line EditBox for TSV output
    local sfm = CreateFrame("ScrollFrame", "BWExportScroll", ef, "UIPanelScrollFrameTemplate")
    sfm:SetPoint("TOPLEFT",     ef, "TOPLEFT",     12, -46)
    sfm:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -30, 36)

    local eb = CreateFrame("EditBox", "BWExportEditBox", sfm)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont("Fonts\\ARIALN.TTF", 11, "")
    eb:SetTextColor(0.85, 0.85, 0.85)
    eb:SetWidth(EXPORT_W - 50)

    eb:SetScript("OnEscapePressed", function() ef:Hide() end)

    -- Claude: "read-only" guard
    eb:SetScript("OnTextChanged", function(self)
        if BW._exportText and self:GetText() ~= BW._exportText then
            self:SetText(BW._exportText)
            self:HighlightText()
        end
    end)

    sfm:SetScrollChild(eb)
    self._exportEB = eb
end

-- ── Export text builder ──────────────────────────────────────────────────────

function BW:BuildExportText()
    local results    = self.scanResults or {}
    local labelOrder = self.labelOrder  or {}

    if #results == 0 then return "No group members found." end

    -- Claude: build per-player missing set for fast lookup
    local missingSet = {}
    for _, data in ipairs(results) do
        local s = {}
        for _, lbl in ipairs(data.missing) do s[lbl] = true end
        missingSet[data] = s
    end

    -- Claude: sort — most missing first, then alphabetical
    local sorted = {}
    for _, data in ipairs(results) do tinsert(sorted, data) end
    table.sort(sorted, function(a, b)
        local am, bm = #a.missing, #b.missing
        if am ~= bm then return am > bm end
        return (a.name or "") < (b.name or "")
    end)

    -- Claude: TSV header — includes Role column
    local lines = {}
    local hdr = "Player\tClass\tRole"
    for _, lbl in ipairs(labelOrder) do
        hdr = hdr .. "\t" .. lbl
    end
    tinsert(lines, hdr)

    -- Claude: one row per group member
    for _, data in ipairs(sorted) do
        local row = data.name .. "\t" .. data.classFile .. "\t" .. (data.role or "?")
        local ms  = missingSet[data]
        -- Claude: check against this player's role-specific labels
        local roleLabelOrder = self.labelOrders and self.labelOrders[data.role] or {}
        local roleLabelSet = {}
        for _, lbl in ipairs(roleLabelOrder) do roleLabelSet[lbl] = true end

        for _, lbl in ipairs(labelOrder) do
            if not roleLabelSet[lbl] then
                row = row .. "\t" .. "-" -- Claude: not applicable for this role
            elseif ms[lbl] then
                row = row .. "\t" .. "MISSING"
            else
                row = row .. "\t" .. "OK"
            end
        end
        tinsert(lines, row)
    end

    return table.concat(lines, "\n")
end

-- ── Export entry point ───────────────────────────────────────────────────────

function BW:OpenExport()
    if not self.exportFrame then return end
    self:Refresh()

    local text = self:BuildExportText()
    self._exportText = text

    self._exportEB:SetText(text)
    self.exportFrame:Show()

    self._exportEB:SetFocus()
    self._exportEB:HighlightText()
end

-- ── Button ───────────────────────────────────────────────────────────────────

function BW:CreateButton()
    local btn = CreateFrame("Button", "BWButton", UIParent)
    btn:SetSize(90, 20)
    btn:SetFrameStrata("HIGH")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("RightButton") -- Claude: right-drag to reposition

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

    -- Claude: hover opens status popup with immediate scan
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

    -- Claude: left-click toggles status frame
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

    -- Claude: OnUpdate ticker — 0.4s hide delay + 5s auto-refresh (no C_Timer in 3.3.5)
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

-- ── Init ─────────────────────────────────────────────────────────────────────

local function DeepCopyEntries(src)
    local out = {}
    for _, e in ipairs(src) do
        tinsert(out, { buff = e.buff, label = e.label, enabled = e.enabled })
    end
    return out
end

local function InitDB()
    -- Claude: migrate from old BuffWatcher2DB if it exists
    if BuffWatcher2DB and not BuffWatcherDB then
        BuffWatcherDB = {}
        -- Claude: old flat entries go into all roles as a starting point
        if type(BuffWatcher2DB.entries) == "table" and #BuffWatcher2DB.entries > 0 then
            BuffWatcherDB.roles = {}
            for _, role in ipairs(BW.ROLES) do
                BuffWatcherDB.roles[role] = { entries = DeepCopyEntries(BuffWatcher2DB.entries) }
            end
        end
        if BuffWatcher2DB.buttonPos then
            BuffWatcherDB.buttonPos = BuffWatcher2DB.buttonPos
        end
    end

    if not BuffWatcherDB then BuffWatcherDB = {} end
    local db = BuffWatcherDB

    -- Claude: ensure roles table exists with defaults
    if type(db.roles) ~= "table" then db.roles = {} end
    for _, role in ipairs(BW.ROLES) do
        if type(db.roles[role]) ~= "table" then
            db.roles[role] = {}
        end
        if type(db.roles[role].entries) ~= "table" or #db.roles[role].entries == 0 then
            local defaults = BW.DefaultRoleEntries[role]
            db.roles[role].entries = defaults and DeepCopyEntries(defaults) or {}
        end
    end

    -- Claude: ensure specRoles override table exists
    if type(db.specRoles) ~= "table" then db.specRoles = {} end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    InitDB()

    BW.scanResults  = {}
    BW.scanTotal    = 0
    BW.scanOK       = 0
    BW.labelOrder   = {}
    BW.labelOrders  = {} -- Claude: per-role label orders
    BW.checkMaps    = {}
    BW.inspectResults = {}

    BW:CreateStatusFrame()
    BW:CreateExportFrame()
    BW:CreateConfigFrame()
    BW:CreateButton()

    -- Claude: queue initial inspect of group members
    QueueGroupInspects()

    -- Claude: slash commands
    SLASH_BUFFWATCHER1 = "/buffwatcher"
    SLASH_BUFFWATCHER2 = "/bw"
    SlashCmdList["BUFFWATCHER"] = function(msg)
        msg = strtrim(string.lower(msg or ""))
        if msg == "config" or msg == "cfg" then
            BW:OpenConfig()
        elseif msg == "check" then
            QueueGroupInspects() -- Claude: re-inspect on manual check
            BW:Refresh()
            BW.statusFrame:Show()
        elseif msg == "export" then
            BW:OpenExport()
        elseif msg == "inspect" then
            -- Claude: force re-inspect all group members
            BW.inspectResults = {}
            QueueGroupInspects()
            print(C("BuffWatcher", "88CCFF") .. ": re-inspecting group members...")
        elseif msg == "help" then
            print(C("BuffWatcher", "88CCFF") .. " commands:")
            print("  /bw           - toggle status window")
            print("  /bw config    - open configuration panel")
            print("  /bw check     - force scan (re-inspects talents)")
            print("  /bw export    - export scan results (TSV for Excel)")
            print("  /bw inspect   - force re-inspect all group members")
            print("  /bw help      - this list")
        else
            if BW.statusFrame:IsShown() then
                BW.statusFrame:Hide()
            else
                BW:Refresh()
                BW.statusFrame:Show()
            end
        end
    end

    print(C("BuffWatcher", "88CCFF") .. " loaded - " .. C("/bw help", "AAAAFF"))
end)

-- Claude: re-inspect when group composition changes
local groupFrame = CreateFrame("Frame")
groupFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
groupFrame:RegisterEvent("RAID_ROSTER_UPDATE")
groupFrame:SetScript("OnEvent", function()
    QueueGroupInspects()
end)
