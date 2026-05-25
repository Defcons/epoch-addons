-- UI/WorldMap.lua
-- Teammate (and opt-in enemy) blips on the WoW world map (M key).
--
-- The blip frames are children of WorldMapDetailFrame so they auto-
-- scale + clip with the map texture as the user pans/zooms (the
-- map already supports group-member dots — these just add more
-- dots for teammates the server isn't sending us data for).
--
-- Coordinates: cache entries carry (x, y) as 0..1 floats from
-- GetPlayerMapPosition. WorldMapDetailFrame is the same coord
-- space, so we just convert percent → pixel:
--   pixelX = x * detailW
--   pixelY = -y * detailH
-- (Negative Y because WoW frame anchors grow downward from TOPLEFT.)

local PEBG = PEBGSync
PEBG.WorldMap = {}
local WM = PEBG.WorldMap

local TEAM_BLIP_SIZE  = 10
local ENEMY_BLIP_SIZE = 9
local UPDATE_HZ       = 4  -- world map updates infrequent; 4 Hz is plenty

local teamPool, enemyPool = {}, {}

local function acquireBlip(pool, parent, sizePx)
    local b = table.remove(pool)
    if not b then
        b = CreateFrame("Frame", nil, parent)
        b:SetWidth(sizePx); b:SetHeight(sizePx)
        b.tex = b:CreateTexture(nil, "OVERLAY")
        b.tex:SetAllPoints(b)
        b.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    b:SetParent(parent)
    b:Show()
    return b
end

local function releaseBlip(pool, b)
    if not b then return end
    b:Hide()
    pool[#pool + 1] = b
end

local activeTeam, activeEnemy = {}, {}

local function classColor(token)
    local c = PEBG.CLASS_COLOR[token or ""]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

local lastDraw = 0
local function redraw()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    if not PEBGSyncDB or not PEBGSyncDB.profile then return end
    if not PEBGSyncDB.profile.worldMapBlips then
        -- Stop drawing and release any active blips.
        for i = #activeTeam, 1, -1 do
            releaseBlip(teamPool, activeTeam[i]); activeTeam[i] = nil
        end
        for i = #activeEnemy, 1, -1 do
            releaseBlip(enemyPool, activeEnemy[i]); activeEnemy[i] = nil
        end
        return
    end

    local parent = WorldMapDetailFrame or WorldMapFrame
    local detailW = (WorldMapDetailFrame and WorldMapDetailFrame:GetWidth())  or parent:GetWidth()
    local detailH = (WorldMapDetailFrame and WorldMapDetailFrame:GetHeight()) or parent:GetHeight()
    if not detailW or detailW <= 0 then return end

    -- Recycle previous blips back to the pool. Simpler than diffing —
    -- count is small (<=40 per side).
    for i = #activeTeam, 1, -1 do
        releaseBlip(teamPool, activeTeam[i]); activeTeam[i] = nil
    end
    for i = #activeEnemy, 1, -1 do
        releaseBlip(enemyPool, activeEnemy[i]); activeEnemy[i] = nil
    end

    -- Team blips.
    PEBG.Engine.ForEachLive(function(entry)
        if not entry.x or not entry.y then return end
        if entry.x <= 0 and entry.y <= 0 then return end  -- "unknown"
        local b = acquireBlip(teamPool, parent, TEAM_BLIP_SIZE)
        local px = entry.x * detailW
        local py = -entry.y * detailH
        b:ClearAllPoints()
        b:SetPoint("CENTER", parent, "TOPLEFT", px, py)
        local r, g, bl = classColor(entry.classToken)
        -- Modulate brightness by HP%: low-HP teammates flash brighter
        -- against a darker base, making them pop on the map.
        local hp = entry.hp or 100
        local tint = 0.6 + 0.4 * (hp / 100)
        b.tex:SetVertexColor(r * tint, g * tint, bl * tint, 1)
        b:SetFrameLevel(parent:GetFrameLevel() + 5)
        activeTeam[#activeTeam + 1] = b
    end)

    -- Enemy blips — only when opt-in is on.
    if PEBGSyncDB.profile.enemyEnabled and PEBG.Enemy and PEBG.Enemy.ForEachLive then
        PEBG.Enemy.ForEachLive(function(entry)
            if not entry.x or not entry.y then return end
            if entry.x <= 0 and entry.y <= 0 then return end
            local b = acquireBlip(enemyPool, parent, ENEMY_BLIP_SIZE)
            local px = entry.x * detailW
            local py = -entry.y * detailH
            b:ClearAllPoints()
            b:SetPoint("CENTER", parent, "TOPLEFT", px, py)
            b.tex:SetVertexColor(1, 0.2, 0.2, 0.9)
            b:SetFrameLevel(parent:GetFrameLevel() + 4)
            activeEnemy[#activeEnemy + 1] = b
        end)
    end
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    lastDraw = lastDraw + elapsed
    if lastDraw < (1.0 / UPDATE_HZ) then return end
    lastDraw = 0
    redraw()
end)

-- Force a redraw the first time the map opens after addon load.
local w = CreateFrame("Frame")
w:RegisterEvent("WORLD_MAP_UPDATE")
w:SetScript("OnEvent", redraw)

function WM.Redraw() redraw() end
