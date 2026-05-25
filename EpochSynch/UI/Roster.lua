-- UI/Roster.lua
-- Standalone HP/MP HUD frame listing teammates. Movable, no dependency
-- on Grid/HealBot etc. — works alongside the default raid frames as an
-- overlay. Auto-shows in battlegrounds and auto-hides when leaving so
-- it doesn't clutter the world UI.

local ES = EpochSynch
ES.Roster = {}
local R = ES.Roster

local ROW_H        = 16
local ROW_W        = 180
local MAX_ROWS     = 40   -- 40-player AV cap
local UPDATE_HZ    = 5    -- redraw rate (0.2s); enough for visible HP changes

local frame, rows
local lastDraw = 0

local function classColor(token)
    local c = ES.CLASS_COLOR[token or ""]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

local function buildRow(parent, index)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(ROW_W)
    f:SetHeight(ROW_H)
    if index == 1 then
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -20)
    else
        f:SetPoint("TOPLEFT", rows[index - 1], "BOTTOMLEFT", 0, -1)
    end

    -- Background HP bar (full-width) + foreground bar that scales by HP%.
    f.hpBg = f:CreateTexture(nil, "BACKGROUND")
    f.hpBg:SetAllPoints(f)
    f.hpBg:SetTexture(0.1, 0.1, 0.1, 0.7)

    f.hpFg = f:CreateTexture(nil, "ARTWORK")
    f.hpFg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.hpFg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.hpFg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.hpFg:SetWidth(ROW_W) -- adjusted per update

    -- Mana bar is just a thin strip at the bottom edge.
    f.mpFg = f:CreateTexture(nil, "OVERLAY")
    f.mpFg:SetTexture(0.2, 0.4, 0.9, 0.9)
    f.mpFg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.mpFg:SetHeight(2)
    f.mpFg:SetWidth(0)

    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.nameText:SetPoint("LEFT", 4, 0)
    f.nameText:SetJustifyH("LEFT")
    f.nameText:SetWidth(ROW_W * 0.6)

    f.hpText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hpText:SetPoint("RIGHT", -4, 0)
    f.hpText:SetJustifyH("RIGHT")

    -- Flag icon — small textured square overlaid on the leftmost edge
    -- when the player carries a BG flag. Lazily created.
    f.flagIcon = f:CreateTexture(nil, "OVERLAY")
    f.flagIcon:SetTexture("Interface\\PVPFrame\\PvP-Currency-Alliance")
    f.flagIcon:SetWidth(12); f.flagIcon:SetHeight(12)
    f.flagIcon:SetPoint("LEFT", -1, 0)
    f.flagIcon:Hide()

    return f
end

local function ensureFrame()
    if frame then return end
    frame = CreateFrame("Frame", "EpochSynchRoster", UIParent)
    frame:SetWidth(ROW_W + 8)
    frame:SetHeight(ROW_H * 8 + 26)   -- room for 8 rows; resizes dynamically
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.7)
    frame:SetBackdropBorderColor(0.3, 0.5, 0.8, 1)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if EpochSynchDB and EpochSynchDB.profile then
            local point, _, _, x, y = self:GetPoint()
            EpochSynchDB.profile.rosterPos = { point = point, x = x, y = y }
        end
    end)
    frame:SetClampedToScreen(true)

    -- Restore saved position; fall back to top-left default.
    local pos = EpochSynchDB and EpochSynchDB.profile and EpochSynchDB.profile.rosterPos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -200)
    end

    -- Title bar — also serves as drag handle visual cue.
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOP", 0, -4)
    frame.title:SetText("|cff66ccffEpochSynch Roster|r")

    rows = {}
    for i = 1, MAX_ROWS do
        rows[i] = buildRow(frame, i)
        rows[i]:Hide()
    end
    frame:Hide()
end

-- Sort the cache snapshot for stable row order. By HP% ascending so the
-- player most in danger floats to the top — that's the row you care
-- about as a healer / FC backup. Ties broken by name for stable order.
local snapshot = {}
local function refreshSnapshot()
    for i = #snapshot, 1, -1 do snapshot[i] = nil end
    ES.Engine.ForEachLive(function(entry)
        snapshot[#snapshot + 1] = entry
    end)
    table.sort(snapshot, function(a, b)
        local ha = a.hp or 100
        local hb = b.hp or 100
        if ha ~= hb then return ha < hb end
        return (a.name or "") < (b.name or "")
    end)
end

local function redraw()
    if not frame or not frame:IsShown() then return end
    refreshSnapshot()
    local n = math.min(#snapshot, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local row = rows[i]
        local e = snapshot[i]
        if i <= n and e then
            local hp = math.max(0, math.min(100, e.hp or 0))
            local mp = math.max(0, math.min(100, e.mp or 0))
            local r, g, b = classColor(e.classToken)

            row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r",
                r * 255, g * 255, b * 255, e.name or "?"))
            row.hpText:SetText(string.format("%d%%", hp))
            row.hpFg:SetWidth(math.max(1, ROW_W * hp / 100))
            -- HP fill colour interpolates green→yellow→red.
            local hpR, hpG = 1, 1
            if hp > 50 then
                hpR = (100 - hp) / 50
                hpG = 1
            else
                hpR = 1
                hpG = hp / 50
            end
            row.hpFg:SetVertexColor(hpR, hpG, 0.1, 0.85)
            row.mpFg:SetWidth(math.max(0, ROW_W * mp / 100))

            local flags = e.flags or 0
            if ES.bit and ES.bit.band then
                -- not used; we rely on Blizzard's bit lib below
            end
            if bit and bit.band(flags, ES.FLAG_HAS_BG_FLAG) ~= 0 then
                row.flagIcon:Show()
            else
                row.flagIcon:Hide()
            end

            row:Show()
        else
            row:Hide()
        end
    end
    -- Tighten frame height to actual row count + header.
    frame:SetHeight(24 + math.max(1, n) * (ROW_H + 1))
end

-- ----- public ----------------------------------------------------------

function R.Show()
    ensureFrame()
    frame:Show()
end

function R.Hide()
    if frame then frame:Hide() end
end

function R.Toggle()
    ensureFrame()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function R.IsShown() return frame and frame:IsShown() end

-- ----- ticker ----------------------------------------------------------
-- One persistent OnUpdate paces redraws at UPDATE_HZ. Cheap when the
-- roster is hidden (early-return on the IsShown check inside redraw).

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    lastDraw = lastDraw + elapsed
    if lastDraw < (1.0 / UPDATE_HZ) then return end
    lastDraw = 0
    redraw()
end)

-- Auto-show / auto-hide on BG transitions so the user doesn't see the
-- HUD when not in a BG.
local bgWatcher = CreateFrame("Frame")
bgWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
bgWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
bgWatcher:SetScript("OnEvent", function()
    if not EpochSynchDB or not EpochSynchDB.profile then return end
    if not EpochSynchDB.profile.rosterShown then return end
    if ES.IsInBG() then R.Show() else R.Hide() end
end)
