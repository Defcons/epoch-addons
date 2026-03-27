-- BuffWatcher.lua
-- Small "BuffWatcher" button that shows a buff/consume status popup on hover.
-- Checks all tracked group members against BW_Config (BuffWatcher_Config.lua).
--
-- Slash: /bw [check|zan|help]
-- Right-drag the button to reposition it.

BW = {}  -- global addon table

-- ============================================================
-- Class colours (RRGGBB, no alpha prefix)
-- ============================================================
local CLASS_COLORS = {
    WARRIOR     = "C69B6D",
    PALADIN     = "F48CBA",
    HUNTER      = "AAD372",
    ROGUE       = "FFF468",
    PRIEST      = "FFFFFF",
    DEATHKNIGHT = "C41E3A",
    SHAMAN      = "0070DE",
    MAGE        = "3FC7EB",
    WARLOCK     = "8788EE",
    DRUID       = "FF7C0A",
}

-- ============================================================
-- Helpers
-- ============================================================

local function C(text, hex)  -- Claude: colour-wrap helper
    return "|cff" .. hex .. text .. "|r"
end

local function ColorName(name, classFile)  -- Claude: class-coloured player name
    return C(name, CLASS_COLORS[classFile] or "FFFFFF")
end

-- Claude: loop UnitBuff indices (3.3.5 has no name-based lookup)
local function UnitHasBuff(unit, buffName)
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name == buffName then return true end
    end
    return false
end

-- Claude: check one config entry; returns true if the player has any listed buff,
-- or if the entry is Zandalar-flagged and Zandalar is disabled.
local function CheckEntry(unit, entry, useZandalar)
    if entry.zandalar and not useZandalar then return true end
    for i = 2, #entry do
        if UnitHasBuff(unit, entry[i]) then return true end
    end
    return false
end

-- Claude: build list of unit IDs covering the full group
local function GetGroupUnits()
    local units = {}
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            tinsert(units, "raid" .. i)
        end
    else
        local numParty = GetNumPartyMembers()
        for i = 1, numParty do
            tinsert(units, "party" .. i)
        end
        tinsert(units, "player")
    end
    return units
end

-- ============================================================
-- Core scan
-- ============================================================

function BW:Refresh()  -- Claude: scan all group members and categorise them
    local db  = BuffWatcherDB
    local cfg = BW_Config

    local mvps, greedy, missing = {}, {}, {}

    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            local _, classFile = UnitClass(unit)
            local classCfg = classFile and cfg[classFile]

            if classCfg then
                local missBufs, misCons = {}, {}
                local hasFlask = false

                -- Flask check
                for _, fn in ipairs(cfg.flasks) do
                    if UnitHasBuff(unit, fn) then
                        hasFlask = true
                        break
                    end
                end

                -- World-buff checks
                for _, entry in ipairs(classCfg.worldbuffs or {}) do
                    if not CheckEntry(unit, entry, db.useZandalar) then
                        tinsert(missBufs, entry[1])
                    end
                end

                -- Consumable checks
                for _, entry in ipairs(classCfg.consumes or {}) do
                    if not CheckEntry(unit, entry, db.useZandalar) then
                        tinsert(misCons, entry[1])
                    end
                end

                local colored = ColorName(name, classFile)

                -- Claude: categorise exactly as the original WA did:
                --   MVP    = flask + all worldbuffs + all consumes
                --   Greedy = no flask, but everything else present
                --   Bad    = anything else missing
                if hasFlask and #missBufs == 0 and #misCons == 0 then
                    tinsert(mvps, colored)
                elseif not hasFlask and #missBufs == 0 and #misCons == 0 then
                    tinsert(greedy, colored)
                else
                    local total = #missBufs + #misCons + (hasFlask and 0 or 1)
                    tinsert(missing, {
                        name  = colored,
                        total = total,
                        bufs  = missBufs,
                        cons  = misCons,
                        flask = hasFlask,
                    })
                end
            end
        end
    end

    self.mvps        = mvps
    self.greedy      = greedy
    self.missing     = missing
    self.lastRefresh = GetTime()

    self:UpdateDisplay()
end

-- ============================================================
-- Text builder
-- ============================================================

-- Claude: wrap a list of coloured names, 5 per line
local function NameBlock(list, indent)
    indent = indent or "  "
    local rows, row = {}, {}
    for i, v in ipairs(list) do
        tinsert(row, v)
        if i % 5 == 0 then
            tinsert(rows, indent .. table.concat(row, ", "))
            row = {}
        end
    end
    if #row > 0 then tinsert(rows, indent .. table.concat(row, ", ")) end
    return table.concat(rows, "\n")
end

function BW:BuildText()  -- Claude: produce the full status string
    if not self.lastRefresh then
        return C("Hover over the button or click it to scan.", "AAAAAA")
    end

    local ago  = math.floor(GetTime() - self.lastRefresh)
    local lines = {}
    local sep  = C(string.rep("-", 44), "334455")

    tinsert(lines, C("Buff Status", "88CCFF") .. C("  (" .. ago .. "s ago)", "556677"))
    tinsert(lines, sep)

    -- MVPs
    if #self.mvps > 0 then
        tinsert(lines, C("MVPs (" .. #self.mvps .. "):", "00FF00"))
        tinsert(lines, NameBlock(self.mvps))
        tinsert(lines, "")
    end

    -- Greedy (only missing flask)
    if #self.greedy > 0 then
        tinsert(lines, C("Greedy – no flask (" .. #self.greedy .. "):", "FFA500"))
        tinsert(lines, NameBlock(self.greedy))
        tinsert(lines, "")
    end

    -- Missing players
    if #self.missing > 0 then
        tinsert(lines, C("Missing (" .. #self.missing .. "):", "FF4444"))
        for _, p in ipairs(self.missing) do
            local flaskNote = p.flask and "" or C(" [no flask]", "FF8888")
            tinsert(lines, "  " .. p.name .. flaskNote
                           .. C(" — " .. p.total .. " missing", "888888"))
            if #p.bufs > 0 then
                tinsert(lines, "    " .. C("Buffs: ", "AAAAAA")
                               .. C(table.concat(p.bufs, ", "), "FF6666"))
            end
            if #p.cons > 0 then
                tinsert(lines, "    " .. C("Consumes: ", "AAAAAA")
                               .. C(table.concat(p.cons, ", "), "FF6666"))
            end
        end
    end

    -- Nothing to show
    if #self.mvps == 0 and #self.greedy == 0 and #self.missing == 0 then
        tinsert(lines, C("No tracked classes found in group.", "AAAAAA"))
    end

    return table.concat(lines, "\n")
end

-- ============================================================
-- Display update
-- ============================================================

function BW:UpdateDisplay()  -- Claude: set text and resize scroll child to fit
    if not self.textObj then return end
    self.textObj:SetText(self:BuildText())
    -- GetStringHeight only works after text is set and frame is shown
    local h = self.textObj:GetStringHeight() + 20
    self.scrollChild:SetHeight(math.max(h, self.scrollFrame:GetHeight()))
end

function BW:UpdateZanBtn()  -- Claude: sync the Zan button label to current state
    if not self.zanBtn then return end
    local label = BuffWatcherDB.useZandalar
        and C("Zan: ON", "00FF00")
        or  C("Zan: OFF", "FF4444")
    self.zanBtn:SetText(label)
end

-- ============================================================
-- UI creation
-- ============================================================

function BW:CreateUI()

    -- ── Small draggable button ────────────────────────────────
    local btn = CreateFrame("Button", "BWButton", UIParent)
    btn:SetWidth(90)
    btn:SetHeight(20)
    btn:SetFrameStrata("HIGH")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("RightButton")  -- Claude: right-drag to move

    -- Restore saved position or use default
    local pos = BuffWatcherDB.buttonPos
    if pos then
        btn:ClearAllPoints()
        btn:SetPoint(pos[1], UIParent, pos[3], pos[4], pos[5])
    else
        btn:SetPoint("TOP", UIParent, "TOP", 0, -220)
    end

    btn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        BuffWatcherDB.buttonPos = { p, "UIParent", rp, x, y }  -- Claude: persist position
    end)

    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0.06, 0.08, 0.14, 0.92)
    btn:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.85)

    local btnLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnLabel:SetPoint("CENTER")
    btnLabel:SetText(C("BuffWatcher", "88CCFF"))
    self.button = btn

    -- ── Status popup frame ────────────────────────────────────
    local sf = CreateFrame("Frame", "BWStatusFrame", UIParent)
    sf:SetWidth(340)
    sf:SetHeight(340)
    sf:SetFrameStrata("HIGH")
    sf:SetFrameLevel(btn:GetFrameLevel() + 5)
    sf:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 14,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    sf:SetBackdropColor(0.03, 0.04, 0.07, 0.97)
    sf:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.9)
    sf:SetPoint("BOTTOM", btn, "TOP", 0, 4)
    sf:EnableMouse(true)
    sf:Hide()
    self.statusFrame = sf

    -- Close button (X) top-right
    local closeBtn = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() sf:Hide() end)

    -- Refresh button
    local refBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    refBtn:SetWidth(68)
    refBtn:SetHeight(18)
    refBtn:SetPoint("TOPLEFT", sf, "TOPLEFT", 7, -6)
    refBtn:SetText("Refresh")
    refBtn:SetScript("OnClick", function() BW:Refresh() end)

    -- Zandalar toggle button
    local zanBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    zanBtn:SetWidth(80)
    zanBtn:SetHeight(18)
    zanBtn:SetPoint("LEFT", refBtn, "RIGHT", 4, 0)
    zanBtn:SetScript("OnClick", function()
        BuffWatcherDB.useZandalar = not BuffWatcherDB.useZandalar
        BW:UpdateZanBtn()
        BW:Refresh()
    end)
    self.zanBtn = zanBtn  -- Claude: stored so UpdateZanBtn() can reach it
    self:UpdateZanBtn()

    -- Thin divider line below the buttons
    local div = sf:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  sf, "TOPLEFT",  7, -28)
    div:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -28, -28)
    div:SetTexture(0.25, 0.45, 0.75, 0.4)

    -- Scroll frame (content area)
    local scrollFrame = CreateFrame("ScrollFrame", "BWScrollFrame", sf)
    scrollFrame:SetPoint("TOPLEFT",     sf, "TOPLEFT",     6, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -26, 6)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)  -- Claude: mouse-wheel scroll
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        v = math.max(0, math.min(max, v - delta * 28))
        self:SetVerticalScroll(v)
    end)
    self.scrollFrame = scrollFrame

    -- Scroll child (grows to fit text)
    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetWidth(scrollFrame:GetWidth() - 4)
    child:SetHeight(scrollFrame:GetHeight())
    scrollFrame:SetScrollChild(child)
    self.scrollChild = child

    -- FontString for the status text
    local txt = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -4)
    txt:SetWidth(child:GetWidth() - 8)
    txt:SetJustifyH("LEFT")
    txt:SetJustifyV("TOP")
    self.textObj = txt

    -- Scrollbar widget
    local sb = CreateFrame("Slider", "BWScrollBar", sf, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    3, -16)
    sb:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 3,  16)
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(20)
    sb:SetValue(0)
    sb:SetScript("OnValueChanged", function(self, v)
        scrollFrame:SetVerticalScroll(v)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(self, _, yRange)  -- Claude: keep scrollbar in sync
        local capped = math.max(yRange or 0, 0)
        sb:SetMinMaxValues(0, capped)
        if sb:GetValue() > capped then sb:SetValue(capped) end
    end)

    -- ── Hover / auto-hide logic ───────────────────────────────

    btn:SetScript("OnEnter", function()
        BW:Refresh()
        sf:ClearAllPoints()
        sf:SetPoint("BOTTOM", btn, "TOP", 0, 4)
        sf:Show()
        BW.hideDelay = nil
    end)
    btn:SetScript("OnLeave", function()
        BW.hideDelay = 0.4  -- Claude: short grace period before hiding
    end)

    sf:SetScript("OnEnter", function() BW.hideDelay = nil end)
    sf:SetScript("OnLeave", function() BW.hideDelay = 0.4 end)

    -- Left-click toggles the frame (useful when frame slid offscreen)
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if sf:IsShown() then
                sf:Hide()
            else
                BW:Refresh()
                sf:Show()
            end
        end
    end)

    -- ── OnUpdate: hide timer + auto-refresh every 5s ──────────
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, elapsed)
        -- Handle hide delay
        if BW.hideDelay then
            BW.hideDelay = BW.hideDelay - elapsed
            if BW.hideDelay <= 0 then
                BW.hideDelay = nil
                sf:Hide()
            end
        end

        -- Auto-refresh while the popup is visible  -- Claude: 5-second auto-refresh
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

-- ============================================================
-- Slash commands
-- ============================================================

local function HandleSlash(msg)
    msg = strtrim(string.lower(msg or ""))

    if msg == "zan" or msg == "zandalar" then
        BuffWatcherDB.useZandalar = not BuffWatcherDB.useZandalar
        BW:UpdateZanBtn()
        local state = BuffWatcherDB.useZandalar
            and C("ON", "00FF00") or C("OFF", "FF4444")
        print(C("BuffWatcher:", "88CCFF") .. " Zandalar requirement " .. state)
        if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end

    elseif msg == "check" then
        BW:Refresh()
        BW.statusFrame:Show()

    elseif msg == "help" or msg == "" then
        print(C("BuffWatcher", "88CCFF") .. " commands:")
        print("  /bw            — toggle the status window")
        print("  /bw check      — force an immediate scan")
        print("  /bw zan        — toggle Zandalar buff requirement")
        print("  /bw help       — show this list")

    else
        -- Unknown arg: just toggle
        if BW.statusFrame:IsShown() then
            BW.statusFrame:Hide()
        else
            BW:Refresh()
            BW.statusFrame:Show()
        end
    end
end

-- ============================================================
-- Initialisation
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    -- Init SavedVariables with defaults
    if not BuffWatcherDB then BuffWatcherDB = {} end
    if BuffWatcherDB.useZandalar == nil then
        BuffWatcherDB.useZandalar = true
    end

    -- Seed result tables so BuildText() never errors before first scan
    BW.mvps    = {}
    BW.greedy  = {}
    BW.missing = {}

    BW:CreateUI()

    -- Register slash commands
    SLASH_BUFFWATCHER1 = "/buffwatcher"
    SLASH_BUFFWATCHER2 = "/bw"
    SlashCmdList["BUFFWATCHER"] = HandleSlash

    print(C("BuffWatcher", "88CCFF") .. " loaded — " .. C("/bw help", "AAAAFF"))
end)
