-- UI/Minimap.lua
-- Minimap dots for teammates that the default raid-marker system can't
-- track (out of "visible" range, but our cache has fresh coords from
-- a relay).
--
-- 3.3.5 minimap is rotation-aware. Computing the dot position requires
-- knowing the player's world position + heading. We use the standard
-- approach: place the dot relative to Minimap's centre using a small-
-- circle approximation. This trades absolute precision for simplicity
-- and works fine for the "is my teammate behind me, ahead of me, or
-- to the side" awareness use case.
--
-- For BG context the player and teammates share a single zone map, so
-- (delta-x, delta-y) in zone-percent maps directly to (offsetX, offsetY)
-- once we know the zone's yardage. Approximating without yardage by
-- using a per-BG scale factor still gives directionally-correct dots.

local PEBG = PEBGSync
PEBG.Minimap = {}
local M = PEBG.Minimap

local UPDATE_HZ = 5
local DOT_SIZE  = 7
local MAX_RANGE_FACTOR = 0.45  -- clamp dots within 45% of minimap radius

local pool = {}
local active = {}
local lastDraw = 0

local function classColor(token)
    local c = PEBG.CLASS_COLOR[token or ""]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

local function acquire()
    local d = table.remove(pool)
    if not d then
        d = CreateFrame("Frame", nil, Minimap)
        d:SetWidth(DOT_SIZE); d:SetHeight(DOT_SIZE)
        d:SetFrameStrata("HIGH")
        d.tex = d:CreateTexture(nil, "OVERLAY")
        d.tex:SetAllPoints(d)
        d.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    d:Show()
    return d
end

local function release(d)
    if not d then return end
    d:Hide()
    pool[#pool + 1] = d
end

local function redraw()
    if not PEBGSyncDB or not PEBGSyncDB.profile then return end
    if not PEBGSyncDB.profile.minimapBlips then
        for i = #active, 1, -1 do release(active[i]); active[i] = nil end
        return
    end
    if not Minimap or not Minimap:IsShown() then return end

    -- Player's own position to anchor relative offsets against.
    local px, py = GetPlayerMapPosition("player")
    if not px or (px == 0 and py == 0) then return end

    local radius = Minimap:GetWidth() / 2

    -- Recycle previous frame's dots.
    for i = #active, 1, -1 do release(active[i]); active[i] = nil end

    PEBG.Engine.ForEachLive(function(entry)
        if not entry.x or not entry.y then return end
        if entry.x <= 0 and entry.y <= 0 then return end
        if entry.name == UnitName("player") then return end

        -- Delta in zone-percent. We multiply by a small fudge factor to
        -- approximately match minimap pixels — exact conversion would
        -- need the BG's known yardage, which varies per BG and isn't
        -- worth hardcoding. The clamp below caps the dot inside the
        -- minimap circle, so even on misaligned scales the direction
        -- (which is what matters for "where is my flag carrier")
        -- stays correct.
        local dx = (entry.x - px)
        local dy = (entry.y - py)
        local distPct = math.sqrt(dx * dx + dy * dy)
        local scale = radius * 5  -- empirical: 1.0 zone-percent ≈ half the map
        local ox = dx * scale
        local oy = -dy * scale  -- WoW Y is inverted

        -- Clamp to a fraction of the minimap radius so out-of-minimap
        -- dots still show as direction indicators on the edge.
        local mag = math.sqrt(ox * ox + oy * oy)
        local maxR = radius * MAX_RANGE_FACTOR
        if mag > maxR and mag > 0 then
            ox = ox * (maxR / mag)
            oy = oy * (maxR / mag)
        end

        local d = acquire()
        d:ClearAllPoints()
        d:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
        local r, g, b = classColor(entry.classToken)
        local hp = entry.hp or 100
        local tint = 0.6 + 0.4 * (hp / 100)
        d.tex:SetVertexColor(r * tint, g * tint, b * tint, 1)
        active[#active + 1] = d
    end)
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    lastDraw = lastDraw + elapsed
    if lastDraw < (1.0 / UPDATE_HZ) then return end
    lastDraw = 0
    redraw()
end)

function M.Redraw() redraw() end
