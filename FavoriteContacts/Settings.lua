local ADDON_NAME, ADDON = ...

FavoriteContactsSettings = FavoriteContactsSettings or {}

local defaultSettings = {
    contacts = {},
    columnCount = 2,
    rowCount = 9,
    position = "RIGHT",
    scale = 0.75,   -- "AUTO" scales to fill MailFrame height; 0.75 gives compact ~27px buttons
    clickToSend = false,
    locked = true,  -- true = anchored to MailFrame; false = free-floating, right-click bg to toggle
    posX = false,   -- saved TOPLEFT X when free-floating (false = not yet set)
    posY = false,   -- saved TOPLEFT Y when free-floating (false = not yet set)
}

function ADDON:ResetUISettings()
    ADDON.settings.columnCount = 2
    ADDON.settings.rowCount = 9
    ADDON.settings.position = "RIGHT"
    ADDON.settings.scale = 0.75
    ADDON.settings.clickToSend = false
    ADDON.settings.locked = true
    ADDON.settings.posX = false
    ADDON.settings.posY = false
end

local function CombineSettings(settings, defaultSettings)
    for key, value in pairs(defaultSettings) do
        if (settings[key] == nil) then
            settings[key] = value
        elseif (type(value) == "table") and next(value) ~= nil then
            if type(settings[key]) ~= "table" then
                settings[key] = {}
            end
            CombineSettings(settings[key], value)
        end
    end

    -- cleanup old still existing settings
    for key, _ in pairs(settings) do
        if (defaultSettings[key] == nil) then
            settings[key] = nil
        end
    end
end

-- Settings have to be loaded during PLAYER_LOGIN
ADDON:RegisterLoginCallback(function()
    local realmName = "realm_" .. GetRealmName()

    if not FavoriteContactsSettings[realmName] then
        FavoriteContactsSettings[realmName] = {}
    end

    CombineSettings(FavoriteContactsSettings[realmName], defaultSettings)
    ADDON.settings = FavoriteContactsSettings[realmName]
end)
