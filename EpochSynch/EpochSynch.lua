-- EpochSynch.lua
-- Main entry: registers the addon-message prefixes, applies defaults,
-- wires the slash command, and kicks off the engine.

local ES = EpochSynch

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[EpochSynch]|r " .. tostring(msg))
end

local function ApplyDefaults(profile, defaults)
    for k, v in pairs(defaults) do
        if profile[k] == nil then profile[k] = v end
    end
end

local function InitDB()
    -- One-shot migration from the pre-rename SavedVariables key. The
    -- v0.1 release named the global PEBGSyncDB; only a handful of
    -- testers ever wrote to it so this is mostly cosmetic, but it
    -- carries any saved profile fields (roster position, enemy opt-in,
    -- etc.) across the rename without re-prompting.
    if PEBGSyncDB and not EpochSynchDB then
        EpochSynchDB = PEBGSyncDB
        PEBGSyncDB   = nil
    end
    EpochSynchDB = EpochSynchDB or {}
    EpochSynchDB.profile = EpochSynchDB.profile or {}
    ApplyDefaults(EpochSynchDB.profile, ES.DEFAULTS)
end

-- ----- slash command ---------------------------------------------------

local function HandleSlash(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd or ""
    local profile = EpochSynchDB.profile

    if cmd == "" or cmd == "show" then
        ES.Roster.Show()
        Print("Roster shown.")
        return
    end
    if cmd == "hide" then
        ES.Roster.Hide()
        profile.rosterShown = false
        Print("Roster hidden. /synch show to bring it back.")
        return
    end
    if cmd == "toggle" then
        ES.Roster.Toggle()
        profile.rosterShown = ES.Roster.IsShown() and true or false
        return
    end
    if cmd == "on" then
        profile.enabled = true
        ES.Engine.Start()
        Print("Broadcasting |cff66ff66ON|r.")
        return
    end
    if cmd == "off" then
        profile.enabled = false
        ES.Engine.Stop()
        Print("Broadcasting |cffff5555OFF|r. (Receive still active.)")
        return
    end
    if cmd == "enemy" then
        if rest == "on" then
            profile.enemyEnabled = true
            ES.Enemy.Start()
            Print("Enemy tracking |cff66ff66ON|r — your spots will be broadcast and incoming spots shown.")
        elseif rest == "off" then
            profile.enemyEnabled = false
            ES.Enemy.Stop()
            -- Clear any cached enemy state immediately.
            for k in pairs(ES.enemyCache) do ES.enemyCache[k] = nil end
            Print("Enemy tracking |cffff5555OFF|r (default).")
        else
            Print("Enemy tracking: " .. (profile.enemyEnabled and "ON" or "OFF"))
            Print("Usage: /synch enemy on|off")
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
        for _ in pairs(ES.cache) do cacheN = cacheN + 1 end
        local enemyN = 0
        for _ in pairs(ES.enemyCache) do enemyN = enemyN + 1 end
        Print("Master:    " .. (profile.enabled and "ON" or "OFF"))
        Print("In BG:     " .. tostring(ES.IsInBG()))
        Print("Grouped:   " .. tostring(ES.IsGrouped()))
        Print("Roster:    " .. (ES.Roster.IsShown() and "shown" or "hidden"))
        Print("WorldMap:  " .. (profile.worldMapBlips and "ON" or "OFF"))
        Print("Minimap:   " .. (profile.minimapBlips and "ON" or "OFF"))
        Print("Enemy:     " .. (profile.enemyEnabled and "ON" or "OFF"))
        Print("Cached teammates: " .. cacheN)
        Print("Cached enemies:   " .. enemyN)
        return
    end
    if cmd == "help" or cmd == "?" then
        Print("Commands:")
        Print("  /synch                  — show roster HUD")
        Print("  /synch hide / toggle    — hide / toggle roster HUD")
        Print("  /synch on / off         — master broadcast toggle")
        Print("  /synch enemy on|off     — enemy spot tracking (default off)")
        Print("  /synch worldmap         — toggle world-map blips")
        Print("  /synch minimap          — toggle minimap blips")
        Print("  /synch status           — current state + cache counts")
        return
    end
    Print("Unknown command. /synch help")
end

SLASH_EPOCHSYNCH1 = "/synch"
SLASH_EPOCHSYNCH2 = "/epochsynch"
SlashCmdList["EPOCHSYNCH"] = HandleSlash

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
        RegisterAddonMessagePrefix(ES.PREFIX_F)
        RegisterAddonMessagePrefix(ES.PREFIX_S)
        RegisterAddonMessagePrefix(ES.PREFIX_E)
    end

    -- Kick off the broadcasters. They self-gate on profile.enabled /
    -- IsInBG / IsGrouped, so calling Start() unconditionally is safe.
    ES.Engine.Start()
    if EpochSynchDB.profile.enemyEnabled then ES.Enemy.Start() end

    -- Show the roster if the user had it visible last session AND we're
    -- in a BG. Outside BG it stays hidden until the BG watcher in
    -- UI/Roster.lua flips it on at zone-in.
    if EpochSynchDB.profile.rosterShown and ES.IsInBG() then
        ES.Roster.Show()
    end

    Print("v" .. ES.VERSION .. " loaded. /synch help.")
end)
