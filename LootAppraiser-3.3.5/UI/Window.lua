-- UI/Window.lua
-- Main session window. Movable, resizable-via-config-only (we keep a fixed
-- size to avoid the FauxScrollFrame anchoring complications). Header shows
-- live timer / GPH / total / item count. Body is a scroll list of loot rows.

LA = LA or {}
LA.UI = LA.UI or {}
local UI = LA.UI

-- Compact single-line header. Frame width sized to fit exactly 4 footer
-- buttons (56px each + 4px gaps + 6px outer margin = 248). The frame is
-- resizable via a bottom-right corner grip — drag it to grow the row
-- count, NOT to scale things bigger. Each additional ROW_H pixels of
-- height adds one more visible row.
--   width   = 6 + 56*4 + 4*3 + 6 = 248
--   default = 18 (single header line) + 8*12 (rows) + 22 (footer) = 136
--   minimum = 18 + 3*12 + 22 = 76 (3 rows)
local WINDOW_W, HEADER_H, FOOTER_H = 248, 18, 22
local ROW_H, MAX_ROWS = 12, 8
local DEFAULT_WINDOW_H = HEADER_H + ROW_H * MAX_ROWS + FOOTER_H
local MIN_VISIBLE_ROWS = 3
local MIN_WINDOW_H     = HEADER_H + ROW_H * MIN_VISIBLE_ROWS + FOOTER_H
local content                       -- content frame (parent of all row widgets)

local frame
local headerText
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

    -- Value sits flush right; name expands from the left edge to the value's
    -- left edge so it adjusts dynamically with the value's width and truncates
    -- gracefully on long item names instead of overflowing into the value column.
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetPoint("RIGHT", -2, 0)
    row.value:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

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
-- Single-line summary:
--   "Zone · M:SS · TotalValue · GPH/h · Nx"
--
-- TotalValue is `lootTotal + goldDelta` — the full session value. Gold
-- and silver looted directly from mob corpses (which arrive as currency
-- via GetMoney(), not as item rows) ARE counted: GoldDelta = current
-- money − money at session start, so any coin pickup increments it.
-- Vendoring an item also increases GoldDelta but lootTotal drops by the
-- same amount via `Session.ReconcileBags`, so the sum stays consistent
-- (no double count).
local function RefreshHeader()
    if not LA.Session.IsRunning() then
        headerText:SetText("|cff999999not running — /la start|r")
        return
    end
    local snap = LA.Session.Snapshot()
    local zone   = (snap.zone ~= "" and snap.zone) or "?"
    local timeS  = FormatTimer(snap.elapsed)
    if snap.isPaused then timeS = timeS .. "|cffffff00*|r" end
    local sessionValue = (snap.lootTotal or 0) + (snap.goldDelta or 0)
    headerText:SetText(string.format(
        "|cffaaaaaa%s|r |cff666666·|r |cffeeeeee%s|r |cff666666·|r |cffeeeeee%s|r |cff666666·|r |cff66ff66%s/h|r |cff666666·|r |cff999999%dx|r",
        zone, timeS, FormatMoney(sessionValue), FormatMoney(snap.gph), snap.itemCount))
end

-- ----- body refresh ------------------------------------------------------
-- Iterates every physical row widget (including ones beyond the current
-- MAX_ROWS — those exist when the user has shrunk the frame after
-- previously resizing it larger; we hide them here). FauxScrollFrame's
-- numToDisplay parameter still uses MAX_ROWS so the scrollbar tracks
-- correctly against the live visible-rows count.
local function RefreshList()
    if not scrollFrame then return end
    local data = LA.Session.GetRows() or {}
    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
    FauxScrollFrame_Update(scrollFrame, #data, MAX_ROWS, ROW_H)

    for i = 1, #rows do
        local row = rows[i]
        if not row then break end
        if i <= MAX_ROWS then
            local entry = data[i + offset]
            if entry then
                local color = LA_CONST.QUALITY_COLOR[entry.quality] or "|cffffffff"
                local nameTxt = entry.link:match("%[(.-)%]") or "?"
                local countSuffix = (entry.count and entry.count > 1) and ("x" .. entry.count) or ""
                -- Item level after the name (and stack count) so rows
                -- sharing a display name but with different itemIDs/ilvls
                -- can be told apart at a glance. Closes the row's quality
                -- colour first so the ilvl can have its own muted grey.
                local ilvlSuffix = (entry.ilvl and entry.ilvl > 0)
                    and (" |cff888888(" .. entry.ilvl .. ")|r") or ""
                local srcSuffix = "  |cff666666[" .. (LA_CONST.PRICE_LABEL[entry.src] or "?") .. "]|r"
                row.name:SetText(color .. nameTxt .. countSuffix .. "|r" .. ilvlSuffix .. srcSuffix)
                row.value:SetText(color .. FormatMoney(entry.value) .. "|r")
                row.link = entry.link
                row:Show()
            else
                row:Hide()
            end
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
    frame:SetHeight(DEFAULT_WINDOW_H)
    frame:SetMovable(true)
    frame:SetResizable(true)
    -- Width is fixed at WINDOW_W (sized to the four footer buttons); only
    -- height is user-controlled. Setting min and max width to the same
    -- value enforces this.
    frame:SetMinResize(WINDOW_W, MIN_WINDOW_H)
    frame:SetMaxResize(WINDOW_W, math.huge)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Persist the window's anchor point + offset so the next
        -- /reload (or fresh login) opens at the same spot.
        if LA.db and LA.db.profile then
            local point, _, _, x, y = self:GetPoint()
            local saved = LA.db.profile.windowPos or {}
            saved.point, saved.x, saved.y = point, x, y
            LA.db.profile.windowPos = saved
        end
    end)
    frame:SetClampedToScreen(true)

    -- Restore the saved position + size if we have one; otherwise centre
    -- the window at the default size. SetClampedToScreen() above keeps it
    -- visible even if the saved coordinates are now offscreen (e.g. after
    -- a resolution change).
    local pos = LA.db and LA.db.profile and LA.db.profile.windowPos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", 0, 0)
    end
    if pos and pos.h and pos.h >= MIN_WINDOW_H then
        frame:SetHeight(pos.h)
    end

    -- Apply saved visibility BEFORE wiring OnShow/OnHide so the initial
    -- state-restore doesn't itself trigger a save. A frame is created
    -- shown by default; if the user had it hidden last session we need
    -- to honour that.
    local wasShown = LA.db and LA.db.profile and LA.db.profile.windowShown
    if wasShown then frame:Show() else frame:Hide() end
    frame:SetScript("OnShow", function()
        if LA.db and LA.db.profile then LA.db.profile.windowShown = true  end
    end)
    frame:SetScript("OnHide", function()
        if LA.db and LA.db.profile then LA.db.profile.windowShown = false end
    end)

    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, (LA_DEFAULTS.windowAlpha or 0.85))
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    tinsert(UISpecialFrames, "LootAppraiserFrame")  -- escape closes

    -- Single-line summary header. Anchored across the full top of the
    -- frame; centre-justified keeps the layout balanced as values change
    -- length. No title or subtitle — the frame border identifies the
    -- addon and the chat-loaded `[LA dump]` slash output names it explicitly.
    headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
    headerText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -4)
    headerText:SetJustifyH("CENTER")
    headerText:SetText("--")

    -- Separator under the header band.
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.4, 0.4, 0.4, 0.6)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 6, -HEADER_H + 1)
    sep:SetPoint("TOPRIGHT", -6, -HEADER_H + 1)

    -- Body: scroll frame + content
    scrollFrame = CreateFrame("ScrollFrame", "LootAppraiserFauxScroll", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -HEADER_H)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, FOOTER_H)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshList)
    end)

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", scrollFrame)
    content:SetPoint("BOTTOMRIGHT", scrollFrame)
    for i = 1, MAX_ROWS do
        rows[i] = BuildRow(content, i)
    end

    -- Footer buttons (compact). Sized so 4 buttons fill the 248-px frame
    -- exactly: 6 (left margin) + 56*4 (buttons) + 4*3 (gaps) + 6 (right
    -- margin) = 248. UIPanelButtonTemplate's font is fixed; small labels
    -- still fit within 56×18.
    local function MakeButton(label, anchor, xOff, onClick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetWidth(56); b:SetHeight(18)
        if anchor then
            b:SetPoint("LEFT", anchor, "RIGHT", xOff, 0)
        else
            b:SetPoint("BOTTOMLEFT", 6, 4)
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

    -- ----- resize grip ---------------------------------------------------
    -- Sits inside the bottom-right corner. Drag to grow the row count,
    -- not to scale; on release we snap the height to a clean multiple
    -- of ROW_H so no row is half-clipped, and persist the new size.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetFrameLevel(frame:GetFrameLevel() + 5) -- sit above the bottom button
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp",   function()
        frame:StopMovingOrSizing()
        -- Snap height to an integer row count.
        local fit = math.max(MIN_VISIBLE_ROWS,
                             math.floor((frame:GetHeight() - HEADER_H - FOOTER_H) / ROW_H))
        frame:SetHeight(HEADER_H + fit * ROW_H + FOOTER_H)
        -- Persist size alongside position.
        if LA.db and LA.db.profile then
            local saved = LA.db.profile.windowPos or {}
            local point, _, _, x, y = frame:GetPoint()
            saved.point, saved.x, saved.y = point, x, y
            saved.h = frame:GetHeight()
            LA.db.profile.windowPos = saved
        end
    end)

    -- Resizing causes OnSizeChanged to fire repeatedly during the drag.
    -- Recompute MAX_ROWS, lazily build any new row widgets we need, and
    -- repaint. Cheap: BuildRow allocates one font string per call.
    frame:SetScript("OnSizeChanged", function(self, _, h)
        if not (content and scrollFrame) then return end -- not built yet
        local newMax = math.max(1, math.floor((h - HEADER_H - FOOTER_H) / ROW_H))
        while #rows < newMax do
            rows[#rows + 1] = BuildRow(content, #rows + 1)
        end
        MAX_ROWS = newMax
        RefreshList()
    end)

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

    -- If we restored a saved height larger than DEFAULT, the OnSizeChanged
    -- script wasn't yet wired when the height was applied — invoke it once
    -- now so MAX_ROWS and any extra row widgets catch up before the first
    -- FullRefresh.
    local sz = frame:GetScript("OnSizeChanged")
    if sz then sz(frame, frame:GetWidth(), frame:GetHeight()) end

    FullRefresh()
    return frame
end
