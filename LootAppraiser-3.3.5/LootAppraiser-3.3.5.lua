-- LootAppraiser-3.3.5.lua
-- Main entry point. Initialises SavedVariables, registers slash commands,
-- and wires the AH-cache invalidation when an Aux/AH scan finishes.

LA = LA or {}

-- ----- SavedVariables defaults applied at PLAYER_LOGIN -------------------
local function ApplyDefaults(profile, defaults)
    for k, v in pairs(defaults) do
        if profile[k] == nil then profile[k] = v end
    end
end

-- One-shot migrations keyed off LootAppraiserDB._dbVersion. Bump this when
-- you change a default that existing installs should pick up automatically.
local DB_VERSION = 1.2

local function MigrateDB(db)
    local v = tonumber(db._dbVersion) or 0

    -- 1.0/1.1 -> 1.2: lower the quality-floor defaults to 0 (greys/whites).
    -- ApplyDefaults only fills nil keys, so existing installs kept the old
    -- minQuality=2 (uncommon+) until we explicitly migrate.
    if v < 1.2 then
        db.profile.minQuality        = 0
        db.profile.minQualityForList = 0
    end

    db._dbVersion = DB_VERSION
end

local function InitDB()
    LootAppraiserDB = LootAppraiserDB or {}
    LootAppraiserDB.profile = LootAppraiserDB.profile or {}
    ApplyDefaults(LootAppraiserDB.profile, LA_DEFAULTS)
    MigrateDB(LootAppraiserDB)
    LA.db = LootAppraiserDB
end

-- ----- /la slash command -------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[LootAppraiser]|r " .. tostring(msg))
end

local function HandleSlash(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        LA.UI.Toggle()
        return
    end
    if cmd == "start" then
        LA.Session.Start()
        LA.UI.Show(); LA.UI.RefreshUIs()
        Print("Session started.")
        return
    end
    if cmd == "stop" or cmd == "end" then
        LA.Session.End()
        LA.UI.RefreshUIs()
        Print("Session ended. Total: " .. ((LA.Session.LootTotal() or 0) > 0
            and (math.floor(LA.Session.LootTotal() / 10000) .. "g") or "0g"))
        return
    end
    if cmd == "pause" then
        LA.Session.Pause(); LA.UI.RefreshUIs(); Print("Paused."); return
    end
    if cmd == "resume" then
        LA.Session.Resume(); LA.UI.RefreshUIs(); Print("Resumed."); return
    end
    if cmd == "reset" then
        LA.Session.Start(); LA.UI.RefreshUIs(); Print("Session reset."); return
    end
    if cmd == "de" then
        LA.db.profile.useDisenchant = not LA.db.profile.useDisenchant
        Print("Disenchant pricing: " .. (LA.db.profile.useDisenchant and "ON" or "OFF"))
        return
    end
    if cmd == "soulbound" then
        LA.db.profile.ignoreSoulbound = not LA.db.profile.ignoreSoulbound
        Print("Ignore soulbound: " .. (LA.db.profile.ignoreSoulbound and "ON" or "OFF"))
        return
    end
    if cmd == "valuecat" then
        if rest == "" then
            Print("ArkInventory 'value' category name: '" .. tostring(LA.db.profile.arkInvValueCategory or "") .. "'  (set to '' to disable)")
        else
            LA.db.profile.arkInvValueCategory = rest
            LA.Pricing.WipeAHCache()
            Print("Value-category override set to '" .. rest .. "'.")
        end
        return
    end
    if cmd == "decat" then
        if rest == "" then
            Print("ArkInventory 'DE' category name: '" .. tostring(LA.db.profile.arkInvDECategory or "") .. "'  (set to '' to disable)")
        else
            LA.db.profile.arkInvDECategory = rest
            LA.Pricing.WipeAHCache()
            Print("DE-category override set to '" .. rest .. "'.")
        end
        return
    end
    if cmd == "quality" then
        local q = tonumber(rest)
        if q and q >= 0 and q <= 7 then
            LA.db.profile.minQualityForList = q
            LA.db.profile.minQuality = q
            Print("Quality threshold set to " .. q .. " (" ..
                ({"poor","common","uncommon","rare","epic","legendary","artifact","heirloom"})[q+1] .. ").")
        else
            Print("Usage: /la quality <0-7>  (current: " .. (LA.db.profile.minQualityForList or 2) .. ")")
        end
        return
    end
    if cmd == "wipe" or cmd == "wipecache" then
        LA.Pricing.WipeAHCache()
        Print("AH/DE price cache wiped — next loot will re-query.")
        return
    end
    if cmd == "help" or cmd == "?" then
        Print("Commands:")
        Print("  /la                — toggle window")
        Print("  /la start | stop   — control session")
        Print("  /la pause | resume — pause GPH timer")
        Print("  /la reset          — start a fresh session")
        Print("  /la de             — toggle disenchant pricing")
        Print("  /la soulbound      — toggle ignoring BoP items")
        Print("  /la quality <0-7>  — minimum quality (0=grey, 2=green, 3=blue ...)")
        Print("  /la valuecat <name>— ArkInventory category to force-AH-price (default: 'Value')")
        Print("  /la decat <name>   — ArkInventory category to force-DE-price (default: 'DE')")
        Print("  /la wipecache      — clear cached AH/DE prices")
        return
    end

    Print("Unknown command. /la help")
end

-- Register the slash names
SLASH_LOOTAPPRAISER1 = "/la"
SLASH_LOOTAPPRAISER2 = "/lootappraiser"
SlashCmdList["LOOTAPPRAISER"] = HandleSlash

-- ----- bootstrap on PLAYER_LOGIN -----------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
-- AUCTION_HOUSE_CLOSED is when Aux finishes a scan; wipe cache so the
-- session sees fresh prices going forward (within the same play session).
boot:RegisterEvent("AUCTION_HOUSE_CLOSED")
boot:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        InitDB()
        LA.UI.Build()
        -- Hide on login; user opens with /la.
        if LootAppraiserFrame then LootAppraiserFrame:Hide() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        LA.Pricing.WipeAHCache()
    end
end)
