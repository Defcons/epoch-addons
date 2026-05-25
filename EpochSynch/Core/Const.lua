-- Core/Const.lua
-- Shared constants + defaults for EpochSynch.

EpochSynch = EpochSynch or {}
local ES = EpochSynch

ES.VERSION = "0.3"  -- Claude: v0.3 adds in-BG global override (Core/Overlay.lua)

-- Addon-channel prefix. ≤16 chars per Blizzard's protocol cap.
ES.PREFIX_F = "EpochSynch_F"  -- fast tier: HP + position + flags
ES.PREFIX_S = "EpochSynch_S"  -- slow tier: MP + secondary
ES.PREFIX_E = "EpochSynch_E"  -- enemy spots (opt-in)

-- Tick intervals. Fast = HP/pos/flags every 0.5s; Slow = MP/etc every 2s.
-- Both well under the ~10 msg/sec outbound throttle even when batched.
ES.FAST_INTERVAL = 0.5
ES.SLOW_INTERVAL = 2.0
ES.ENEMY_INTERVAL = 1.0  -- enemy-spot tier (only when enabled)

-- Cache entries older than this are considered stale (player offline,
-- left raid, observer lost line-of-visibility). Pruned from display.
ES.STALE_AFTER = 5.0
ES.ENEMY_STALE_AFTER = 15.0  -- enemy spots stay relevant longer

-- Flag bits packed into the per-record byte (sent as digit 0-31 in wire
-- to keep printable ASCII; receiver decodes).
ES.FLAG_IN_COMBAT     = 0x01
ES.FLAG_HAS_BG_FLAG   = 0x02
ES.FLAG_DEAD          = 0x04
ES.FLAG_GHOST         = 0x08
ES.FLAG_MOUNTED       = 0x10

-- Class colours for the roster and map blips. Same hex as WoW's
-- RAID_CLASS_COLORS so the addon agrees visually with default UI.
ES.CLASS_COLOR = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    MAGE        = { 0.41, 0.80, 0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    DRUID       = { 1.00, 0.49, 0.04 },
}

-- Default profile values applied to EpochSynchDB.profile on first load.
ES.DEFAULTS = {
    enabled       = true,  -- master toggle
    enemyEnabled  = false, -- opt-in per spec
    rosterShown   = true,  -- show the HP/MP HUD frame
    worldMapBlips = true,  -- draw teammate dots on world map
    minimapBlips  = true,  -- draw teammate dots on minimap
    overlay       = true,  -- Claude: in-BG override of UnitHealth/Mana/Position globals
    -- Window position. Saved on drag-stop; nil = first install centred.
    rosterPos     = nil,
}

-- Returns true while the player is inside any battleground / arena.
-- UnitInBattleground returns the player's BG index, or nil if not in one.
-- GetBattlefieldStatus walks queue slots looking for "active" status as
-- a backup signal for some Ascension edge cases.
function ES.IsInBG()
    if UnitInBattleground and UnitInBattleground("player") then return true end
    for i = 1, (MAX_BATTLEFIELD_QUEUES or 3) do
        local status = GetBattlefieldStatus and GetBattlefieldStatus(i)
        if status == "active" then return true end
    end
    return false
end

-- Returns true if the local player is in a raid OR party group. The
-- addon only sends in groups (no self-talk needed).
function ES.IsGrouped()
    local n = (GetNumRaidMembers and GetNumRaidMembers() or 0)
            + (GetNumPartyMembers and GetNumPartyMembers() or 0)
    return n > 0
end
