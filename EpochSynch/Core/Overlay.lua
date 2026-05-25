-- Core/Overlay.lua
-- Claude: in-BG global override so default raid frames + every other UI
-- raid-frame addon (Grid, HealBot, ShadowedUF, ...) and the default
-- world map/minimap blips reflect the broadcast HP/MP/position for
-- teammates the server has stopped updating (UnitIsVisible == false).
--
-- We wrap UnitHealth / UnitHealthMax / UnitMana / UnitManaMax /
-- GetPlayerMapPosition. The wrapper falls through to the original in
-- every case EXCEPT: caller is asking about a non-player teammate, we
-- have a fresh cache entry for them, AND UnitIsVisible(unit) == false
-- (i.e. the server is NOT sending data — exactly the gap we want to
-- fill). When the server has fresh data, the original wins.
--
-- Install / uninstall is gated on (a) profile.overlay being true AND
-- (b) the player being inside a battleground. Outside BG the globals
-- point at the unmodified Blizzard functions, so out-of-BG play has
-- zero taint surface from this addon.
--
-- Taint note: replacing UnitHealth/UnitMana causes a small amount of
-- taint to flow into any secure code that reads them — most visibly
-- the raid-frame right-click dropdown menu becoming unreliable in
-- combat. The tradeoff is universal raid-frame compatibility with no
-- per-UI shim. Toggleable via /synch overlay on|off.
--
-- Chain-hook caveat: we capture the originals on first Install(). If
-- another addon hooks one of these globals BEFORE our first install,
-- their hook is preserved (we call through to it). If another addon
-- hooks AFTER us, our Uninstall() will restore our captured original
-- and lose their hook. In practice nothing in this addon pack hooks
-- these functions, so this is documented but unmitigated.

local ES = EpochSynch
ES.Overlay = {}
local O = ES.Overlay

local orig = {}            -- Claude: original function refs, captured on first Install()
local installed = false    -- Claude: tracks current swap state

-- Returns a live cache entry for `unit` only when override is appropriate.
-- Hot path — called many times per frame by raid-frame redraws, so the
-- checks are ordered cheapest-first.
local function broadcastFor(unit)
    if not unit then return nil end
    -- Never override the local player; the live API has perfect data.
    if UnitIsUnit(unit, "player") then return nil end
    local name = UnitName(unit)
    if not name then return nil end
    local cache = ES.cache
    local entry = cache and cache[name]
    if not entry then return nil end
    if (entry.lastSeen or 0) < (GetTime() - ES.STALE_AFTER) then return nil end
    -- If the server is sending data for this unit, use it — it's
    -- first-hand, more recent than anything we could relay.
    if UnitIsVisible(unit) then return nil end
    return entry
end

-- ----- wrapped functions ----------------------------------------------
-- HP/MP travel as percent (0..100) on the wire. We return the percent
-- as the "current" value and 100 as "max" so any consumer doing
-- value/max gets a correct 0..1 fill ratio. Absolute HP/MP values are
-- not preserved — but for out-of-range units the original calls were
-- already returning 0, so this is strictly an improvement.

local function wUnitHealth(unit)
    local e = broadcastFor(unit)
    if e and e.hp then return math.floor(e.hp + 0.5) end
    return orig.UnitHealth(unit)
end

local function wUnitHealthMax(unit)
    local e = broadcastFor(unit)
    if e and e.hp then return 100 end
    return orig.UnitHealthMax(unit)
end

local function wUnitMana(unit)
    local e = broadcastFor(unit)
    if e and e.mp then return math.floor(e.mp + 0.5) end
    return orig.UnitMana(unit)
end

local function wUnitManaMax(unit)
    local e = broadcastFor(unit)
    if e and e.mp then return 100 end
    return orig.UnitManaMax(unit)
end

-- GetPlayerMapPosition returns (0, 0) for out-of-range units on 3.3.5.
-- We pass through to the original and only substitute cached coords
-- when the real call returned (0, 0). That way any non-zero real
-- position from the server wins over our relayed value.
local function wGetPlayerMapPosition(unit)
    local x, y = orig.GetPlayerMapPosition(unit)
    if x == 0 and y == 0 then
        local e = broadcastFor(unit)
        if e and e.x and e.y then return e.x, e.y end
    end
    return x, y
end

-- ----- install / uninstall --------------------------------------------

local function captureOrigOnce()
    if orig.UnitHealth then return end
    orig.UnitHealth           = UnitHealth
    orig.UnitHealthMax        = UnitHealthMax
    orig.UnitMana             = UnitMana
    orig.UnitManaMax          = UnitManaMax
    orig.GetPlayerMapPosition = GetPlayerMapPosition
end

function O.Install()
    if installed then return end
    captureOrigOnce()
    UnitHealth           = wUnitHealth            -- Claude: swap globals
    UnitHealthMax        = wUnitHealthMax
    UnitMana             = wUnitMana
    UnitManaMax          = wUnitManaMax
    GetPlayerMapPosition = wGetPlayerMapPosition
    installed = true
end

function O.Uninstall()
    if not installed then return end
    UnitHealth           = orig.UnitHealth        -- Claude: restore originals
    UnitHealthMax        = orig.UnitHealthMax
    UnitMana             = orig.UnitMana
    UnitManaMax          = orig.UnitManaMax
    GetPlayerMapPosition = orig.GetPlayerMapPosition
    installed = false
end

function O.IsInstalled() return installed end

-- ----- state sync -----------------------------------------------------
-- Driven by BG enter/exit events and by the /synch overlay slash
-- command. Idempotent — safe to call multiple times.

function O.SyncState()
    if not EpochSynchDB or not EpochSynchDB.profile then return end
    if EpochSynchDB.profile.overlay and ES.IsInBG() then
        O.Install()
    else
        O.Uninstall()
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
watcher:SetScript("OnEvent", O.SyncState)
