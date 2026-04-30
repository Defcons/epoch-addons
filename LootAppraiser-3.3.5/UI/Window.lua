-- UI/Window.lua
-- Main session window. Movable, resizable-via-config-only (we keep a fixed
-- size to avoid the FauxScrollFrame anchoring complications). Header shows
-- live timer / GPH / total / item count. Body is a scroll list of loot rows.

LA = LA or {}
LA.UI = LA.UI or {}
local UI = LA.UI

local WINDOW_W, HEADER_H, FOOTER_H = 320, 92, 28
local ROW_H, MAX_ROWS = 14, 12
local WINDOW_H = HEADER_H + ROW_H * MAX_ROWS + FOOTER_H

local frame
local titleText, zoneText
local timerText, gphText, totalText, countText
local rows = {}        -- visual row frames
local scrollFrame
local pendingRefresh = false
local lastRefreshAt  = 0
local REFRESH_THROTTLE = 0.1

-- ----- copper formatting -------------------------------------------------
local function FormatMoney(c)
    c = math.floor(c or 0)
    if c == 0 then return "0c" end
    local g = math.floor(c / 10000)
    local s = math.floor((c - g * 10000) / 100)
    local cc = c - g * 10000 - s * 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, cc) end
    return cc .. "c"
end

local function FormatTimer(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- ----- visual row builder ------------------------------------------------
local function BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("LEFT", 4, 0)
    row:SetPoint("RIGHT", -4, 0)
    if index == 1 then
        row:SetPoint("TOP", parent, "TOP", 0, -1)
    else
        row:SetPoint("TOP", rows[index - 1], "BOTTOM", 0, 0)
    end

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(true)
    row.bg:SetTexture(0, 0, 0, 0.0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(200)

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetPoint("RIGHT", -2, 0)
    row.value:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
            self.bg:SetTexture(1, 1, 1, 0.05)
        end
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.bg:SetTexture(0, 0, 0, 0.0)
    end)
    row:SetScript("OnClick", function(self)
        if not self.link then return end
        if IsShiftKeyDown() and ChatEdit_GetActiveWindow() then
            ChatEdit_InsertLink(self.link)
        elseif IsControlKeyDown() then
            DressUpItemLink(self.link)
        end
    end)

    return row
end

-- ----- header refresh ----------------------------------------------------
local function RefreshHeader()
    if not LA.Session.IsRunning() then
        timerText:SetText("--:--")
        gphText:SetText("0g/h")
        totalText:SetText("0g")
        countText:SetText("0 items")
        zoneText:SetText("|cff999999not running|r")
        return
    end
    local snap = LA.Session.Snapshot()
    timerText:SetText(FormatTimer(snap.elapsed) .. (snap.isPaused and " |cffffff00(paused)|r" or ""))
    gphText:SetText(FormatMoney(snap.gph) .. "/h")
    totalText:SetText(FormatMoney(snap.lootTotal))
    countText:SetText(tostring(snap.itemCount) .. " items")
    zoneText:SetText("|cff999999" .. (snap.zone ~= "" and snap.zone or "?") .. "|r")
end

-- ----- body refresh ------------------------------------------------------
local function RefreshList()
    local data = LA.Session.GetRows() or {}
    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
    FauxScrollFrame_Update(scrollFrame, #data, MAX_ROWS, ROW_H)

    for i = 1, MAX_ROWS do
        local idx = i + offset
        local entry = data[idx]
        local row = rows[i]
        if entry then
            local color = LA_CONST.QUALITY_COLOR[entry.quality] or "|cffffffff"
            local nameTxt = entry.link:match("%[(.-)%]") or "?"
            local countSuffix = (entry.count and entry.count > 1) and ("x" .. entry.count) or ""
            local srcSuffix = "  |cff666666[" .. (LA_CONST.PRICE_LABEL[entry.src] or "?") .. "]|r"
            row.name:SetText(color .. nameTxt .. countSuffix .. "|r" .. srcSuffix)
            row.value:SetText(color .. FormatMoney(entry.value) .. "|r")
            row.link = entry.link
            row:Show()
        else
            row:Hide()
        end
    end
end

local function FullRefresh()
    RefreshHeader()
    RefreshList()
    lastRefreshAt = GetTime()
    pendingRefresh = false
end

-- Throttled refresh. Header retains the live ticker; the body only redraws
-- when loot is added or the user scrolls.
local function ThrottledRefresh()
    if (GetTime() - lastRefreshAt) >= REFRESH_THROTTLE then
        FullRefresh()
    else
        pendingRefresh = true
    end
end

-- ----- public hooks ------------------------------------------------------
function UI.OnLootAdded(entry)
    if frame and not frame:IsShown() then
        local db = LA.db and LA.db.profile or LA_DEFAULTS
        if db.showOnLoot then frame:Show() end
    end
    ThrottledRefresh()
end

function UI.RefreshUIs()
    FullRefresh()
end

function UI.Toggle()
    if not frame then UI.Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function UI.Show()
    if not frame then UI.Build() end
    frame:Show()
end

-- ----- frame construction ------------------------------------------------
function UI.Build()
    if frame then return frame end

    frame = CreateFrame("Frame", "LootAppraiserFrame", UIParent)
    frame:SetWidth(WINDOW_W)
    frame:SetHeight(WINDOW_H)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetClampedToScreen(true)

    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, (LA_DEFAULTS.windowAlpha or 0.85))
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    tinsert(UISpecialFrames, "LootAppraiserFrame")  -- escape closes

    -- Title
    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -8)
    titleText:SetText("|cff33ccffLoot Appraiser|r")

    zoneText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneText:SetPoint("TOP", titleText, "BOTTOM", 0, -2)

    -- Stats grid (2 rows x 2 columns), anchored to the frame so layout stays
    -- stable regardless of zone-name length.
    local function MakeLabel(text, x, y)
        local lab = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        lab:SetText("|cff999999" .. text .. "|r")
        local val = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        val:SetPoint("LEFT", lab, "RIGHT", 4, 0)
        val:SetText("--")
        return val
    end

    -- Header rows are inside the HEADER_H band; coordinates measured from frame TL.
    timerText = MakeLabel("Time:",   16, -52)
    gphText   = MakeLabel("GPH:",   170, -52)
    totalText = MakeLabel("Total:",  16, -68)
    countText = MakeLabel("Items:", 170, -68)

    -- Separator
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.4, 0.4, 0.4, 0.6)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 8, -HEADER_H + 4)
    sep:SetPoint("TOPRIGHT", -8, -HEADER_H + 4)

    -- Body: scroll frame + content
    scrollFrame = CreateFrame("ScrollFrame", "LootAppraiserFauxScroll", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -HEADER_H)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, FOOTER_H)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshList)
    end)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", scrollFrame)
    content:SetPoint("BOTTOMRIGHT", scrollFrame)
    for i = 1, MAX_ROWS do
        rows[i] = BuildRow(content, i)
    end

    -- Footer buttons
    local function MakeButton(label, anchor, xOff, onClick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetWidth(60); b:SetHeight(20)
        if anchor then
            b:SetPoint("LEFT", anchor, "RIGHT", xOff, 0)
        else
            b:SetPoint("BOTTOMLEFT", 8, 6)
        end
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    local btnStart = MakeButton("Start", nil, 0, function()
        if LA.Session.IsRunning() then
            LA.Session.End()
        else
            LA.Session.Start()
        end
        FullRefresh()
    end)
    local btnPause = MakeButton("Pause", btnStart, 4, function()
        if LA.Session.IsPaused() then LA.Session.Resume() else LA.Session.Pause() end
        FullRefresh()
    end)
    local btnReset = MakeButton("Reset", btnPause, 4, function()
        LA.Session.Start()
        FullRefresh()
    end)
    local btnHide = MakeButton("Hide", btnReset, 4, function()
        frame:Hide()
    end)

    UI._buttons = { start = btnStart, pause = btnPause, reset = btnReset, hide = btnHide }

    -- Live header ticker. Cheap (text-only) so we run it every 0.25s.
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._tickAcc = (self._tickAcc or 0) + elapsed
        if self._tickAcc >= 0.25 then
            self._tickAcc = 0
            RefreshHeader()
            -- Flush pending body refresh if it was throttled
            if pendingRefresh and (GetTime() - lastRefreshAt) >= REFRESH_THROTTLE then
                FullRefresh()
            end
            -- Update the Pause/Start labels to reflect current state
            if LA.Session.IsRunning() then
                btnStart:SetText("Stop")
                btnPause:SetText(LA.Session.IsPaused() and "Resume" or "Pause")
            else
                btnStart:SetText("Start")
                btnPause:SetText("Pause")
            end
        end
    end)

    FullRefresh()
    return frame
end
