-- PEBGSync-3.3.5.lua
-- Main entry: registers the addon-message prefixes, applies defaults,
-- wires the slash command, and kicks off the engine.

local PEBG = PEBGSync

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[PEBG]|r " .. tostring(msg))
end

local function ApplyDefaults(profile, defaults)
    for k, v in pairs(defaults) do
        if profile[k] == nil then profile[k] = v end
    end
end

local function InitDB()
    PEBGSyncDB = PEBGSyncDB or {}
    PEBGSyncDB.profile = PEBGSyncDB.profile or {}
    ApplyDefaults(PEBGSyncDB.profile, PEBG.DEFAULTS)
end

-- ----- slash command ---------------------------------------------------

local function HandleSlash(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd or ""
    local profile = PEBGSyncDB.profile

    if cmd == "" or cmd == "show" then
        PEBG.Roster.Show()
        Print("Roster shown.")
        return
    end
    if cmd == "hide" then
        PEBG.Roster.Hide()
        profile.rosterShown = false
        Print("Roster hidden. /pebg show to bring it back.")
        return
    end
    if cmd == "toggle" then
        PEBG.Roster.Toggle()
        profile.rosterShown = PEBG.Roster.IsShown() and true or false
        return
    end
    if cmd == "on" then
        profile.enabled = true
        PEBG.Engine.Start()
        Print("Broadcasting |cff66ff66ON|r.")
        return
    end
    if cmd == "off" then
        profile.enabled = false
        PEBG.Engine.Stop()
        Print("Broadcasting |cffff5555OFF|r. (Receive still active.)")
        return
    end
    if cmd == "enemy" then
        if rest == "on" then
            profile.enemyEnabled = true
            PEBG.Enemy.Start()
            Print("Enemy tracking |cff66ff66ON|r — your spots will be broadcast and incoming spots shown.")
        elseif rest == "off" then
            profile.enemyEnabled = false
            PEBG.Enemy.Stop()
            -- Clear any cached enemy state immediately.
            for k in pairs(PEBG.enemyCache) do PEBG.enemyCache[k] = nil end
            Print("Enemy tracking |cffff5555OFF|r (default).")
        else
            Print("Enemy tracking: " .. (profile.enemyEnabled and "ON" or "OFF"))
            Print("Usage: /pebg enemy on|off")
        end
        return
    end
    if cmd == "worldmap" then
        profile.worldMapBlips = not profile.worldMapBlips
        Print("World map blips: " .. (profile.worldMapBlips and "ON" or "OFF"))
        return
    end
    if cmd == "minimap" then
        profile.minimapBlips = not profile.minimapBlips
        Print("Minimap blips: " .. (profile.minimapBlips and "ON" or "OFF"))
        return
    end
    if cmd == "status" then
        local cacheN = 0
        for _ in pairs(PEBG.cache) do cacheN = cacheN + 1 end
        local enemyN = 0
        for _ in pairs(PEBG.enemyCache) do enemyN = enemyN + 1 end
        Print("Master:    " .. (profile.enabled and "ON" or "OFF"))
        Print("In BG:     " .. tostring(PEBG.IsInBG()))
        Print("Grouped:   " .. tostring(PEBG.IsGrouped()))
        Print("Roster:    " .. (PEBG.Roster.IsShown() and "shown" or "hidden"))
        Print("WorldMap:  " .. (profile.worldMapBlips and "ON" or "OFF"))
        Print("Minimap:   " .. (profile.minimapBlips and "ON" or "OFF"))
        Print("Enemy:     " .. (profile.enemyEnabled and "ON" or "OFF"))
        Print("Cached teammates: " .. cacheN)
        Print("Cached enemies:   " .. enemyN)
        return
    end
    if cmd == "help" or cmd == "?" then
        Print("Commands:")
        Print("  /pebg                  — show roster HUD")
        Print("  /pebg hide / toggle    — hide / toggle roster HUD")
        Print("  /pebg on / off         — master broadcast toggle")
        Print("  /pebg enemy on|off     — enemy spot tracking (default off)")
        Print("  /pebg worldmap         — toggle world-map blips")
        Print("  /pebg minimap          — toggle minimap blips")
        Print("  /pebg status           — current state + cache counts")
        return
    end
    Print("Unknown command. /pebg help")
end

SLASH_PEBGSYNC1 = "/pebg"
SLASH_PEBGSYNC2 = "/pebgsync"
SlashCmdList["PEBGSYNC"] = HandleSlash

-- ----- bootstrap -------------------------------------------------------
-- One frame for the few addon-lifecycle events we need to hook. The
-- broadcaster/receiver/UI subsystems own their own frames internally.

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    InitDB()

    -- Register addon-message prefixes. On 3.3.5 RegisterAddonMessagePrefix
    -- doesn't exist — addon messages broadcast freely without prefix
    -- registration. Belt-and-suspenders: if a future Ascension server
    -- introduces it, the call here is forward-compat.
    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PEBG.PREFIX_F)
        RegisterAddonMessagePrefix(PEBG.PREFIX_S)
        RegisterAddonMessagePrefix(PEBG.PREFIX_E)
    end

    -- Kick off the broadcasters. They self-gate on profile.enabled /
    -- IsInBG / IsGrouped, so calling Start() unconditionally is safe.
    PEBG.Engine.Start()
    if PEBGSyncDB.profile.enemyEnabled then PEBG.Enemy.Start() end

    -- Show the roster if the user had it visible last session AND we're
    -- in a BG. Outside BG it stays hidden until the BG watcher in
    -- UI/Roster.lua flips it on at zone-in.
    if PEBGSyncDB.profile.rosterShown and PEBG.IsInBG() then
        PEBG.Roster.Show()
    end

    Print("v" .. PEBG.VERSION .. " loaded. /pebg help.")
end)
