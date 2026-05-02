-- Core/Const.lua
-- Constants and default settings for LootAppraiser-3.3.5.
--
-- Globals exposed: LA_CONST, LA_DEFAULTS, LA (the addon namespace table).

LA = LA or {}

LA_CONST = {
    -- Quality thresholds (matches Blizzard's quality enum)
    QUALITY_POOR      = 0,  -- grey
    QUALITY_COMMON    = 1,  -- white
    QUALITY_UNCOMMON  = 2,  -- green
    QUALITY_RARE      = 3,  -- blue
    QUALITY_EPIC      = 4,  -- purple
    QUALITY_LEGENDARY = 5,  -- orange
    QUALITY_ARTIFACT  = 6,
    QUALITY_HEIRLOOM  = 7,

    -- Per-quality coloured prefix used in the loot list
    QUALITY_COLOR = {
        [0] = "|cff9d9d9d", -- grey
        [1] = "|cffffffff", -- white
        [2] = "|cff1eff00", -- green
        [3] = "|cff0070dd", -- blue
        [4] = "|cffa335ee", -- purple
        [5] = "|cffff8000", -- orange
        [6] = "|cffe6cc80",
        [7] = "|cff00ccff",
    },

    -- Pricing sources, in fallback order
    PRICE_AUX     = "AUX",
    PRICE_TSM     = "TSM",
    PRICE_DE      = "DE",
    PRICE_VENDOR  = "VENDOR",

    -- Loot row types
    SOURCE_SOLO   = "solo",
    SOURCE_GROUP  = "group",

    -- Bind status returned by Pricing.IsBoP
    BIND_FREE     = 0,
    BIND_BOP      = 1,
    BIND_QUEST    = 2,

    -- Maximum entries kept in the live loot list (older entries scroll off)
    MAX_LOOT_ROWS = 200,
}

LA_DEFAULTS = {
    -- Filtering
    minQuality        = LA_CONST.QUALITY_POOR,  -- include greys/whites by default
    minQualityForList = LA_CONST.QUALITY_POOR,  -- show every quality in the list too
    minValueCopper    = 0,        -- skip items worth less than this for the list (not totals)
    ignoreSoulbound   = false,    -- if true, BoP items are excluded from totals entirely
    useDisenchant     = true,     -- BoP green/blue: substitute DE expected value when AH unknown

    -- ArkInventory category overrides. When ArkInventory is loaded and a
    -- looted item has been manually assigned to a custom category whose
    -- name matches one of these strings (case-insensitive, comma-separated
    -- lists supported), the default pricing chain is overridden:
    --   * arkInvValueCategory  -> force the Aux/TSM AH price
    --                            (whites/greys you treat as AH-saleable)
    --   * arkInvDECategory     -> force the disenchant expected value
    --                            (greens/blues you always DE)
    --   * arkInvVendorCategory -> force the vendor sell price
    --                            (Junk/Trash that you always vendor; this
    --                            bypasses any incidental AH listing)
    -- Set any to "" to disable that override entirely.
    arkInvValueCategory  = "Value",
    arkInvDECategory     = "DE",
    arkInvVendorCategory = "Junk,Trash",

    -- Drop entries whose final priced value is 0 copper. Mostly catches
    -- vendor-fallback items with a vendor price of 0 (white poor quality
    -- vendor trash, certain quest items, etc).
    skipZeroValueRows    = true,

    -- Display
    autoStart         = true,     -- start a session automatically on first /la or first loot
    showOnLoot        = true,     -- pop the window on first loot if hidden
    windowAlpha       = 0.85,
    rowHeight         = 14,

    -- Persistence
    rememberLastSession = true,   -- restore last session totals on /reload (within the same play session)
}
