-- EpogArmory.lua
-- single-addon mesh gear inspector. Every client runs the same code:
-- scans self + groupmates in dungeons/raids, broadcasts chunked gear on the
-- "EpogArmory" addon-message prefix, receives other clients' broadcasts,
-- and stores latest gear per GUID in EpogArmoryDB for manual upload to
-- epoglogs.com.

local ADDON = "EpogArmory"
local PREFIX = "EpogArmory"

-- ============================================================================
-- FORWARD COMPATIBILITY — READ BEFORE EDITING THE WIRE FORMAT OR DB SHAPES
-- ============================================================================
-- The mesh must accept any version of the addon talking to any other. The
-- protections:
--
-- 1. APPEND-ONLY WIRE FORMAT. Positions 1..30 of the caret-delimited payload
--    are frozen forever (proto tag, name, realm, class, level, guid, spec,
--    scanTime, zone, gear slots 1..19). New fields land at position 31+.
--    Receivers silently drop unknown trailing tokens, so old clients never
--    reject new payloads — they just miss fields they don't know.
--
-- 2. PROTO LENIENCY. ParsePayload accepts "v<PROTO>" exactly AND
--    "v<PROTO>.<minor>". Lets us nudge the protocol subtly without breaking
--    old parsers (e.g. "v1.2" won't be rejected by a "v1"-only reader).
--
-- 3. ITEM DATA IS LOCAL, NOT TRANSMITTED. stats / tooltipStats / setBonuses /
--    damage / speed / tooltipExtras are all computed locally from
--    GetItemStats and tooltip scans — they never cross the mesh. Adding new
--    captured fields does NOT require mesh coordination. Each client resolves
--    items independently from its own live game data.
--
-- Rules (never break these):
--   a. Never reorder existing wire positions. Only append at position 31+.
--   b. Never change a field's semantics. If ITEM_MOD_STRENGTH_SHORT is
--      strength today, it's strength forever. Add new fields instead.
--   c. Never remove fields — old clients may read them. Set to nil, let
--      absence signal unavailable.
--
-- ESCAPE HATCH: if a change is genuinely impossible additively, bump
-- PROTO = "1" to "2". The new client emits BOTH v1 and v2 payloads during a
-- transition window (months); v2 receivers prefer v2, fall back to v1. After
-- widespread adoption, drop v1 emit. Much later, drop v1 receive. No public
-- release has needed this yet.
--
-- ON-DISK MIGRATIONS:
--   * EpogArmoryDB — MigratePlayers() runs every PLAYER_LOGIN and reshapes
--     older per-player records idempotently. Add new migration branches
--     there when changing the record shape.
--   * EpogItemCacheDB — every entry carries `v = CACHE_SCHEMA`. Bump the
--     constant when the entry shape changes; stale entries re-fetch on next
--     touch. See CACHE_SCHEMA's own comment block for the schema version log.
-- ============================================================================
local PROTO = "1"
local ADDON_VERSION = GetAddOnMetadata(ADDON, "Version") or "0"
local RELEASES_URL = "https://github.com/Defcons/epogarmory-addon/releases/"

-- Tuning
local INSPECT_COOLDOWN      = 900
local OUT_OF_RANGE_COOLDOWN = 30     -- retry fast when CanInspect fails
local INSPECT_TIMEOUT       = 4
local INSPECT_INTERVAL      = 2.5
-- Delay between consecutive addon-message sends from outQueue. Local inspect
-- + ingest is instant; this gate only affects how fast data chatters out to
-- peers. Peers don't need scans within seconds — eventually is fine, and
-- spreading sends keeps the outgoing byte-rate tiny (~45 B/s at 2.0) so we
-- never brush against Blizzard's ~800 B/s addon-message throttle in a churn
-- like raid-roster-formation.
local BROADCAST_STAGGER     = 2.0
local MAX_CHUNK_BODY        = 200
local ROSTER_TICK           = 10
local MIN_INSPECT_LEVEL     = 60
local MIN_STORE_LEVEL       = 60
local MIN_STORE_EQUIPPED    = 10
local ASSEMBLY_TIMEOUT      = 60
-- v0.34: reduced from 24h to 4h. AddUnit only ever fires for groupmates
-- (called from ScanRoster's party/raid iteration), so this window controls
-- how often we re-inspect teammates to catch spec / gear / PvP-trinket swaps
-- that happen mid-session. Still shared mesh-wide via lastScanned, so when
-- one client inspects and broadcasts, every peer's window restarts together
-- and traffic converges to "one inspect per target per 4h across the mesh".
-- Traffic impact: ~6x v0.33, which in a 40-player raid is roughly 6 × 12s
-- of per-target broadcast drain ≈ 1 minute per target per day. Acceptable.
local SCAN_FRESH_WINDOW     = 14400

-- Runtime config, persisted in EpogArmoryDB.config on logout.
-- v0.40: zone restriction removed. PvP loadouts now route to sets["pvp"]
-- and the mount-gear filter (UTILITY_ITEMS / UTILITY_ITEM_NAMES_ANY_SLOT /
-- tooltip enchant scan for Mithril Spurs etc.) catches bank-alt / show-off
-- loadouts regardless of zone. No longer need to gate on instance-only.

local UTILITY_ITEMS = {
    [11122] = "Carrot on a Stick",
    [25653] = "Riding Crop",
    [32863] = "Charm of Swift Flight",
    [46906] = "Argent War Horn",
    [6256]  = "Fishing Pole",
    [6365]  = "Strong Fishing Pole",
    [6366]  = "Darkwood Fishing Pole",
    [6367]  = "Big Iron Fishing Pole",
    [12225] = "Blump Family Fishing Pole",
    [19970] = "Arcanite Fishing Pole",
    [25978] = "Seth's Graphite Fishing Pole",
    [44050] = "Mastercraft Kalu'ak Fishing Pole",
    [45858] = "Nat's Lucky Fishing Pole",
    [45991] = "Bone Fishing Pole",
    [19972] = "Lucky Fishing Hat",
    [33820] = "Weather-Beaten Fishing Hat",
    [33864] = "Chef's Hat",
}

local UTILITY_ENCHANTS = {
    [464] = "Enchant Gloves - Riding Skill", -- Minor +mount speed
}

-- Item-name blacklist patterns, matched via GetItemInfo at store time. Used
-- for items whose IDs vary across Ascension's custom content but whose names
-- are stable.
local UTILITY_ITEM_NAMES_ANY_SLOT = {
    "Rugged Sandle",   -- user's spelling (exact)
    "Rugged Sandal",   -- alternate spelling ("Rugged Sandals")
}

-- Slot-restricted name patterns. Applied only when the item is in the listed
-- equipment slots. v0.33: Insignia patterns moved out — an Insignia trinket
-- no longer rejects the scan; instead it marks the scan as a PvP loadout
-- and routes gear into sets["pvp"] alongside the talent-tree sets.
local UTILITY_ITEM_NAMES_BY_SLOT = {
    -- (empty for now — future slot-specific utility patterns go here)
}

-- PvP loadout detection: an Insignia trinket in slot 13 or 14 flags the
-- whole equipped set as a PvP loadout. Scanned as a distinct set keyed
-- sets["pvp"] on the player record.
local PVP_TRINKET_NAME_PATTERNS = { "Insignia" }
local TRINKET_SLOTS = { 13, 14 }

local function GearLooksPvP(gearLookup)
    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemName = gearLookup(slot)
        if itemName then
            for _, pat in ipairs(PVP_TRINKET_NAME_PATTERNS) do
                if itemName:find(pat, 1, true) then return true end
            end
        end
    end
    return false
end

-- Live-unit variant: queries GetInventoryItemLink + GetItemInfo. Used in
-- BuildPayload when we're the scanner.
local function UnitLooksPvP(unit)
    return GearLooksPvP(function(slot)
        local link = GetInventoryItemLink(unit, slot)
        return link and GetItemInfo(link) or nil
    end)
end

-- Gear-table variant: reads itemstrings from a parsed payload. Used in
-- Ingest when we're the receiver.
local function EntryGearLooksPvP(gear)
    if not gear then return false end
    return GearLooksPvP(function(slot)
        local str = gear[slot]
        if not str or str == "" then return nil end
        local iid = tonumber(str:match("^(%d+)"))
        return iid and GetItemInfo(iid) or nil
    end)
end

-- Enchant-name patterns matched by tooltip text on specific slots. Used when
-- an enchant doesn't have a stable SpellItemEnchantment.dbc ID we can rely on
-- (e.g. Mithril Spurs — legacy engineering boot enchant). Only scanned on
-- slots in MOUNT_ENCHANT_SLOTS below, and only at BuildPayload time (sender
-- side) to avoid tooltip-scanning every received broadcast.
local UTILITY_ENCHANT_TOOLTIP_PATTERNS = {
    "Mithril Spurs",
}

local MOUNT_ENCHANT_SLOTS = { 8, 10 } -- feet, hands

-- State
local queue, inQueue, seen = {}, {}, {}
local current = nil
local outQueue = {}
local nextInspectAt, nextSendAt, lastRoster = 0, 0, 0
local msgCounter = 0
local assembly = {}

-- Version ping: broadcast our ADDON_VERSION once at T+120s after login so
-- groupmates/guildmates running the addon learn when a newer release is out.
-- Listening is always-on via OnAddonMessage; the outbound ping is one-shot.
local VERSION_PING_DELAY = 120
local VERSION_PING_RETRY = 60 -- if no broadcast channel available (solo + no guild), defer
local versionPingAt      = 0
local versionPingSent    = false
local versionNotified    = false

-- Admin sync protocol (v0.35): a targeted peer can request another peer's
-- recent stored scans for bulk-catch-up. Hidden slash command:
--   /epogarmory syncfrom <playerName> [days]
-- Receiver broadcasts a SYNCREQ; the named target replays their stored
-- set.rawPayload blobs back through the normal outQueue. Other guildmates
-- ingest the replays too (free benefit — their DBs also catch up).
local SYNC_RESPONSE_COOLDOWN     = 3600        -- 1h per requester
local SYNC_MAX_SETS_PER_RESPONSE = 200         -- cap drain at ~20min even for huge DBs
local lastSyncResponseTo         = {}          -- in-memory: requesterName -> time() of last response

-- v0.37: requester-side cap — 3 concurrent outgoing syncs max. Each tracked
-- with an estimated end time (~25 min per sync, conservative vs the 20 min
-- full-drain at MAX_SETS_PER_RESPONSE). UI greys rows while a sync is
-- active. Tracker is in-memory; /reload resets it (which also wipes
-- outQueue, so both sides stay consistent).
local SYNC_MAX_CONCURRENT = 3
local SYNC_EST_DURATION   = 25 * 60
local activeSyncs         = {} -- peerName -> estimatedEndTime

-- v0.37: responder-side defense-in-depth. Global cooldown across ALL sync
-- responses means even a multi-attacker bomb (10 requesters from 10 alts)
-- only triggers ONE response per 15 min. Combined with the per-requester
-- 1h cooldown, caps the victim's outQueue load at one 20-min drain at a
-- time, not N × drain in parallel.
local SYNC_GLOBAL_COOLDOWN = 900 -- 15 min between any sync responses
local lastSyncResponseAt   = 0   -- any-peer global timestamp of last response

-- v0.47: lightweight "who's out there" peer refresh. Lets the UI button in
-- the Scanners view actively poll the guild for current identity + dbSize
-- instead of waiting for organic gear-scan broadcasts. PEERPING is a tiny
-- request; each receiver replies PEERPONG with their MyIdentity, dbSize,
-- version, and current character name. Responses update peerInfo, which
-- the Scanners leaderboard reads.
local PEER_PING_COOLDOWN     = 60   -- user can press Refresh Peers at most every 60s
local PEER_RESPONSE_COOLDOWN = 60   -- don't respond to same requester twice in 1 min
local lastPeerPingSentAt     = 0    -- in-memory: last time WE sent a PEERPING
local lastPeerPongTo         = {}   -- in-memory: requesterName -> time() of last PEERPONG sent

local function CleanExpiredSyncs()
    local t = time()
    for name, endT in pairs(activeSyncs) do
        if endT <= t then activeSyncs[name] = nil end
    end
end
local function CountActiveSyncs()
    CleanExpiredSyncs()
    local n = 0
    for _ in pairs(activeSyncs) do n = n + 1 end
    return n
end

-- item-info cache. EpogItemCacheDB is the persistent half; pendingCache
-- is the in-memory retry queue for items the client hasn't fetched yet.
local pendingCache = {} -- itemID -> firstSeenTime
local CACHE_RETRY_INTERVAL = 0.5
local CACHE_GIVE_UP        = 15
-- Cache schema version. Bumped when the shape of EpogItemCacheDB[itemID]
-- changes in a way that requires re-fetching. Entries with a lower (or
-- missing) .v are treated as stale on the next touch.
-- v1: name/quality/itemLevel/icon/ts
-- v2: + stats (v0.22)
-- v3: + tooltipStats for percent-based bonuses on old (pre-rating)
--     items like Darkmantle. v0.26 release.
-- v4: + Ascension PvP percent patterns (DAMAGE_VS_PLAYERS_PCT etc.) +
--     hardened Set-bonus filter that catches "(N) Set:" piece-count lines
--     in addition to plain "Set:" prefixes. v0.27 release.
-- v5: + tooltipExtras array carrying raw "Chance on hit:" / "Use:" lines
--     verbatim, so the site's armory tooltip can render item flavor text
--     (procs, use-effects) that don't reduce to numeric stats. v0.28.
-- v6: + setBonuses array carrying each "Set:" / "(N) Set:" line as a
--     structured { pieces, text } entry so the armory tooltip can render
--     the full set bonus block. Previously filtered out entirely. v0.29.
-- v7: + damage range { min, max, school } + speed for weapons (GetItemStats
--     only exposes DPS, not min/max or speed), and "Equip:" added to the
--     tooltipExtras prefix whitelist so proc-style Equip lines (Hand of
--     Justice etc.) get captured as flavor text. v0.30.
-- v8: bug fix — the tooltipExtras prefix check used string.find with the
--     plain=true flag combined with a `^` anchor, which doesn't anchor
--     (plain=true disables pattern metacharacters). No extras were being
--     captured since v0.28. Fixed with sub-and-equal compare. Schema bump
--     forces re-fetch of v7 entries that silently captured nothing. v0.31.
-- v9: + IsStatLikeEquipLine filter — Equip lines that describe pure stats
--     already captured by GetItemStats ("Equip: +20 Attack Power." /
--     "Equip: Increases critical strike rating by 20.") no longer land in
--     tooltipExtras. Avoids rendering the same stat twice on the site.
--     Proc lines with "chance" / "on hit" / "for N sec" / etc. are NOT
--     stat-like and continue to be preserved. v0.32.
-- v10: + TOOLTIP_STAT_REDUNDANT_WITH dedup — tooltip patterns like
--      SPELL_POWER_FLAT / HEALING_FLAT that have an ITEM_MOD_* equivalent
--      in GetItemStats now skip the tooltipStats write when the
--      equivalent is already present in stats. Was double-rendering
--      on the site (once from stats, once from tooltipStats) for any
--      modern item that has both. v0.40.
local CACHE_SCHEMA = 10

-- Tooltip-text patterns for percent-based stats that predate the rating
-- system and aren't in GetItemStats' enum. Keys are plain uppercase tokens
-- (deliberately NOT ITEM_MOD_* prefixed — the site's ingest maps these in
-- a separate handler from the GetItemStats fields). Order matters: more
-- specific patterns come first so they match before the generic fallbacks.
-- Ordering matters here — more-specific patterns come first so they win the
-- first-match break. Example: "damage and healing done by magical spells"
-- must be tried before "healing done by magical spells" so a line with both
-- concepts maps to SPELL_POWER_FLAT instead of HEALING_FLAT.
local TOOLTIP_STAT_PATTERNS = {
    -- ---------- Percent-based offensive (crit / hit) ----------
    { "critical strike with melee and ranged attacks by (%-?%d+)%%", "CRIT_MELEE_RANGED_PCT" },
    { "critical strike with spells by (%-?%d+)%%",                   "CRIT_SPELL_PCT" },
    { "critical strike chance by (%-?%d+)%%",                        "CRIT_PCT" },
    { "critical strike by (%-?%d+)%%",                               "CRIT_PCT" },
    { "hit with melee and ranged attacks by (%-?%d+)%%",             "HIT_MELEE_RANGED_PCT" },
    { "hit with spells by (%-?%d+)%%",                               "HIT_SPELL_PCT" },
    { "Improves your chance to hit by (%-?%d+)%%",                   "HIT_PCT" },
    { "be dodged or parried by (%-?%d+)%%",                          "EXPERTISE_PCT" },
    -- ---------- Percent-based defensive (dodge / parry / block) ----------
    { "chance to dodge an attack by (%-?%d+)%%",                     "DODGE_PCT" },
    { "chance to parry an attack by (%-?%d+)%%",                     "PARRY_PCT" },
    { "chance to block an attack by (%-?%d+)%%",                     "BLOCK_PCT" },
    -- ---------- Flat regen (pre-rating) ----------
    { "Restores (%d+) mana per 5 sec",                               "MP5" },
    { "Restores (%d+) health per 5 sec",                             "HP5" },
    -- ---------- Flat spell power / damage / healing (TBC-era items) ----------
    -- "damage and healing" beats "healing" / "damage" alone.
    { "damage and healing done by magical spells and effects by up to (%d+)", "SPELL_POWER_FLAT" },
    { "damage and healing done by magical spells by up to (%d+)",    "SPELL_POWER_FLAT" },
    { "healing done by magical spells and effects by up to (%d+)",   "HEALING_FLAT" },
    { "healing done by magical spells by up to (%d+)",               "HEALING_FLAT" },
    { "damage done by magical spells and effects by up to (%d+)",    "SPELL_DAMAGE_FLAT" },
    { "damage done by magical spells by up to (%d+)",                "SPELL_DAMAGE_FLAT" },
    -- Per-school (rare on WotLK gear but still present on some TBC drops)
    { "damage done by Arcane spells and effects by up to (%d+)",     "SPELL_DAMAGE_ARCANE" },
    { "damage done by Fire spells and effects by up to (%d+)",       "SPELL_DAMAGE_FIRE" },
    { "damage done by Frost spells and effects by up to (%d+)",      "SPELL_DAMAGE_FROST" },
    { "damage done by Nature spells and effects by up to (%d+)",     "SPELL_DAMAGE_NATURE" },
    { "damage done by Shadow spells and effects by up to (%d+)",     "SPELL_DAMAGE_SHADOW" },
    { "damage done by Holy spells and effects by up to (%d+)",       "SPELL_DAMAGE_HOLY" },
    -- ---------- Other pre-rating flats ----------
    { "Increased Defense %+(%d+)",                                   "DEFENSE_FLAT" },
    { "Spell Penetration %+(%d+)",                                   "SPELL_PENETRATION_FLAT" },
    { "Increases the block value of your shield by (%d+)",           "BLOCK_VALUE_FLAT" },
    -- ---------- PvP-specific percent (Ascension "Rival's" gear etc.) ----------
    -- Values stored as the positive raw number. Sign is implicit in the key
    -- name: DAMAGE_VS_PLAYERS increases outgoing; DAMAGE_REDUCTION reduces
    -- incoming (both are player buffs even though the tooltip verb differs).
    { "damage dealt against other players by (%-?%d+)%%",            "DAMAGE_VS_PLAYERS_PCT" },
    { "damage taken from other players by (%-?%d+)%%",               "DAMAGE_REDUCTION_VS_PLAYERS_PCT" },
}

-- Prefixes that mark "special" tooltip lines worth preserving verbatim into
-- entry.tooltipExtras — procs, activated trinket effects, and other flavor
-- text the site's armory tooltip renders as-is.
local TOOLTIP_EXTRA_PREFIXES = {
    "Chance on hit:",
    "Use:",
    "Equip:", -- v0.30: catch proc-style Equip lines (Hand of Justice etc.)
}

-- v0.40: dedup map — tooltip stat keys that GetItemStats already captures
-- via an ITEM_MOD_* enum on modern items. When GetItemStats HAS the
-- equivalent, skip the tooltip capture to avoid rendering the same stat
-- twice on the armory site (once from stats, once from tooltipStats).
-- Pre-rating items (vanilla/TBC) that lack the ITEM_MOD_* still get the
-- tooltip capture — the dedup only triggers when BOTH would be present.
--
-- Percent-based keys (CRIT_*_PCT, HIT_*_PCT, DODGE_PCT, etc.) and
-- per-school spell damage (SPELL_DAMAGE_FIRE etc.) are NOT in the
-- GetItemStats enum on any item, so no redundancy check is needed for
-- them — they always flow to tooltipStats.
local TOOLTIP_STAT_REDUNDANT_WITH = {
    SPELL_POWER_FLAT       = "ITEM_MOD_SPELL_POWER_SHORT",
    HEALING_FLAT           = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    SPELL_DAMAGE_FLAT      = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    MP5                    = "ITEM_MOD_MANA_REGENERATION_SHORT",
    HP5                    = "ITEM_MOD_HEALTH_REGEN_SHORT",
    DEFENSE_FLAT           = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    SPELL_PENETRATION_FLAT = "ITEM_MOD_SPELL_PENETRATION_SHORT",
    BLOCK_VALUE_FLAT       = "ITEM_MOD_BLOCK_VALUE_SHORT",
}

-- v0.32: stat-like Equip lines (e.g. "Equip: +20 Attack Power." or
-- "Equip: Increases attack power by 20.") describe numeric stats that
-- GetItemStats already captured into entry.stats. Including them in
-- tooltipExtras would render the stat twice on the site's armory tooltip.
-- This filter skips them; actual procs (containing "chance" / "on hit" /
-- "for N sec" / etc.) do NOT match these patterns and still land in extras.
local EQUIP_STAT_LINE_PATTERNS = {
    "^Equip: %+%-?%d+ ",                        -- "Equip: +20 Attack Power."
    "^Equip: Increases [%w ]+by %-?%d+%.?$",    -- "Equip: Increases attack power by 20."
    "^Equip: Increases your [%w ]+by %-?%d+%.?$", -- "Equip: Increases your crit rating by 20."
    "^Equip: Decreases your [%w ]+by %-?%d+%.?$", -- rare but possible
    "^Equip: Restores %d+ [%w ]+per 5 sec%.?$",   -- "Equip: Restores 10 mana per 5 sec."
}
local function IsStatLikeEquipLine(text)
    if not text then return false end
    for _, pat in ipairs(EQUIP_STAT_LINE_PATTERNS) do
        if text:match(pat) then return true end
    end
    return false
end

-- Parse a possible set-bonus line. Returns (pieces, description) if the line
-- is a set bonus, or nil if it's not. Handles three formats seen in the wild:
--   "Set: <desc>"               — no piece count (Ascension's Darkmantle etc.)
--   "(N) Set: <desc>"           — N pieces required (Eskhandar's)
--   "(N/M) Set: <desc>"         — N of M pieces active (some servers)
local function ParseSetBonusLine(text)
    if not text then return nil end
    -- Try "(N/M) Set: ..." and "(N) Set: ..." — leading digits captured, any
    -- trailing "/M" consumed by [/%d]*
    local pieces, desc = text:match("^%((%d+)[/%d]*%)%s*Set:%s*(.+)$")
    if pieces then return tonumber(pieces) or 0, desc end
    -- Plain "Set: ..." format, no piece count
    desc = text:match("^Set:%s*(.+)$")
    if desc then return 0, desc end
    return nil
end

-- Parse a weapon damage line. Three shapes:
--   "9 - 17 Damage"              — plain physical
--   "12 - 19 Holy Damage"        — pure elemental weapon
--   "9 - 17 Damage\n+5 Fire"     — physical with elemental bonus (two lines;
--                                   we capture the main range only)
-- Returns (min, max, school) or nil. school is nil for plain physical.
local function ParseDamageLine(text)
    if not text then return nil end
    local dmin, dmax, school = text:match("^(%d+)%s*%-%s*(%d+)%s+(%a*)%s*Damage$")
    if not dmin then return nil end
    dmin, dmax = tonumber(dmin), tonumber(dmax)
    if not (dmin and dmax) then return nil end
    if school == "" then school = nil end
    return dmin, dmax, school
end

-- Parse a weapon speed line. The tooltip puts speed on the equip-slot line
-- (e.g. "Main Hand<tab>Speed 2.80") or on its own. Capture the decimal.
local function ParseSpeedLine(text)
    if not text then return nil end
    local s = text:match("Speed%s+(%d+%.?%d*)")
    return s and tonumber(s) or nil
end

local tooltipScanTip
-- Scan an item's tooltip once and return (stats, extras, setBonuses, damage, speed):
--   stats       — percent-based / pre-rating stat table keyed by TOOLTIP_STAT_PATTERNS
--   extras      — array of raw tooltip lines matching TOOLTIP_EXTRA_PREFIXES
--   setBonuses  — array of { pieces, text } set-bonus entries
--   damage      — { min, max, school? } for weapons (nil for armor)
--   speed       — attack speed in seconds, e.g. 2.8 (nil for non-weapons)
-- Any may be nil if nothing matched in that category.
-- `fromGetStats` (v0.40, optional) — the entry.stats table populated by
-- GetItemStats earlier in CacheItemInfo. Used to dedup tooltip captures
-- that would duplicate an already-present ITEM_MOD_* (e.g. don't emit
-- SPELL_POWER_FLAT=29 to tooltipStats when stats.ITEM_MOD_SPELL_POWER_SHORT=29
-- already exists).
local function ScanTooltip(link, fromGetStats)
    if not link then return nil, nil, nil, nil, nil end
    if not tooltipScanTip then
        tooltipScanTip = CreateFrame("GameTooltip", "EpogArmoryTooltipStatsTip", UIParent, "GameTooltipTemplate")
    end
    tooltipScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltipScanTip:ClearLines()
    tooltipScanTip:SetHyperlink(link)

    local stats, extras, setBonuses, damage, speed = nil, nil, nil, nil, nil
    for i = 2, tooltipScanTip:NumLines() do
        local fs = _G["EpogArmoryTooltipStatsTipTextLeft" .. i]
        local text = fs and fs:GetText()
        -- Also scan the right-column text since weapons put Speed there,
        -- aligned with the equip-slot label on the left.
        local fsR = _G["EpogArmoryTooltipStatsTipTextRight" .. i]
        local textR = fsR and fsR:GetText()
        if text then
            -- Weapon damage + speed: captured once per scan. Speed can
            -- appear in either column depending on server/client layout.
            if not damage then
                local dmin, dmax, school = ParseDamageLine(text)
                if dmin then damage = { min = dmin, max = dmax, school = school } end
            end
            if not speed then
                speed = ParseSpeedLine(text) or ParseSpeedLine(textR)
            end

            -- Set-bonus lines: captured structurally, not filtered.
            local pieces, desc = ParseSetBonusLine(text)
            if desc then
                setBonuses = setBonuses or {}
                setBonuses[#setBonuses + 1] = { pieces = pieces, text = desc }
            else
                -- First try stat patterns. Matches "consume" the line
                -- regardless of whether we actually store the value — so
                -- a redundant-with-GetItemStats line doesn't then leak
                -- into tooltipExtras. v0.40: if the equivalent ITEM_MOD_*
                -- is already in fromGetStats, skip the tooltipStats write
                -- to prevent double-stat rendering on the site.
                local matched = false
                for _, pat in ipairs(TOOLTIP_STAT_PATTERNS) do
                    local n = text:match(pat[1])
                    if n then
                        n = tonumber(n)
                        if n and n ~= 0 then
                            local redundant = TOOLTIP_STAT_REDUNDANT_WITH[pat[2]]
                            if not (redundant and fromGetStats and fromGetStats[redundant]) then
                                stats = stats or {}
                                stats[pat[2]] = (stats[pat[2]] or 0) + n
                            end
                            matched = true
                            break
                        end
                    end
                end
                -- If the line didn't resolve to a stat, check whether it's a
                -- special-effect line worth preserving verbatim. We use a
                -- direct prefix compare instead of string.find with a `^`
                -- anchor — combining `^` with plain=true doesn't anchor
                -- (plain=true disables pattern metacharacters) and combining
                -- `^` without plain=true requires escaping `-` / `(` / `)`
                -- in the prefix strings. sub-and-equal is simpler and right.
                if not matched then
                    for _, prefix in ipairs(TOOLTIP_EXTRA_PREFIXES) do
                        if text:sub(1, #prefix) == prefix then
                            -- v0.32: skip Equip lines that are pure stat
                            -- descriptions — GetItemStats already captured
                            -- the numeric value into entry.stats; duplicating
                            -- the raw text would double-render on the site.
                            if not (prefix == "Equip:" and IsStatLikeEquipLine(text)) then
                                extras = extras or {}
                                extras[#extras + 1] = text
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    return stats, extras, setBonuses, damage, speed
end

local function now() return GetTime() end

-- v0.43: resolve "who are we, identity-wise" for cross-alt consolidation.
-- Returns the configured main name if set, otherwise the live character
-- name. Used when broadcasting and answering "is this SYNCREQ targeting me".
local function MyIdentity()
    if EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.mainName
        and EpogArmoryDB.config.mainName ~= "" then
        return EpogArmoryDB.config.mainName
    end
    return UnitName("player") or "?"
end

-- Which of the 3 class talent trees has the most points. 1, 2, or 3. Used as
-- the per-player set key so a rogue's Assassination/Combat/Subtlety each get
-- their own gear snapshot. Matches the player's mental model of "spec"; works
-- regardless of Ascension's GetActiveTalentGroup quirks (which on a classless
-- client seem to always return 1 and aren't useful as a key here).
-- Ties break to the lowest index (arbitrary but stable).
local function DominantTree(spec)
    if not spec then return 1 end
    local maxIdx, maxVal = 1, spec[1] or 0
    for i = 2, 3 do
        if (spec[i] or 0) > maxVal then maxIdx, maxVal = i, spec[i] or 0 end
    end
    return maxIdx
end

local function dprint(...)
    if EpogArmoryDebug then
        print("|cffffaa44EpogArmory|r", ...)
    end
end

local function markRetryIn(guid, retryIn)
    seen[guid] = now() - (INSPECT_COOLDOWN - retryIn)
end

local function ZoneType()
    local inInstance, instType = IsInInstance()
    if not inInstance then return "outdoor" end
    if instType == "raid" then return "raid" end
    if instType == "party" then return "party" end
    if instType == "pvp" then return "bg" end
    if instType == "arena" then return "arena" end
    return instType or "unknown"
end


local function ItemStringFromLink(link)
    if not link then return "" end
    local s = link:match("|Hitem:([%-%d:]+)|h")
    return s or ""
end

-- mark a GUID as inspected at unix timestamp `scanTime`. Called from
-- both local successful inspects and gossip-reassembled broadcasts. Keeps the
-- max of current vs new so older arrivals don't overwrite fresh data.
local function MarkInspected(guid, scanTime)
    if not guid or guid == "" or not scanTime or scanTime <= 0 then return end
    EpogArmoryDB = EpogArmoryDB or { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = {} }
    EpogArmoryDB.lastScanned = EpogArmoryDB.lastScanned or {}
    local existing = EpogArmoryDB.lastScanned[guid] or 0
    if scanTime > existing then
        EpogArmoryDB.lastScanned[guid] = scanTime
    end
end

local function HasFreshScan(guid)
    if not EpogArmoryDB or not EpogArmoryDB.lastScanned then return false end
    local t = EpogArmoryDB.lastScanned[guid]
    return t and (time() - t) < SCAN_FRESH_WINDOW
end

-- ---------------- Item-info cache ----------------
-- for every itemID we see on a scanned player, query GetItemInfo()
-- locally. If the client already has the item cached, we get
-- name/quality/itemLevel/texture and persist to EpogItemCacheDB so the web
-- site can render without needing external data sources. If the client hasn't
-- seen the item yet, we trigger a background fetch via a hidden tooltip and
-- retry from an OnUpdate poll. Covers Ascension-custom items that aren't in
-- Wowhead / TrinityCore data.

local cacheTip -- created lazily on first use

local function TriggerItemFetch(itemID)
    if not cacheTip then
        cacheTip = CreateFrame("GameTooltip", "EpogArmoryItemCacheTip", UIParent, "GameTooltipTemplate")
        cacheTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    cacheTip:ClearLines()
    cacheTip:SetHyperlink("item:" .. itemID)
    cacheTip:Hide()
end

-- returns true if GetItemInfo succeeded and we wrote to the cache,
-- false if still pending (client hasn't resolved the item yet).
-- itemLink (optional): the full "item:itemID:enchantID:gem1:..." string. Used
-- by GetItemStats below to capture Ascension's modified stat values. If
-- omitted, falls back to a bare "item:itemID" link which still returns the
-- base item's stats.
local function CacheItemInfo(itemID, itemLink)
    if not itemID or itemID <= 0 then return false end
    EpogItemCacheDB = EpogItemCacheDB or {}
    -- Skip only when we already have a current-schema entry. Pre-v0.22 entries
    -- (no .v, no stats) re-fetch here so they pick up GetItemStats data.
    local existing = EpogItemCacheDB[itemID]
    if existing and existing.v == CACHE_SCHEMA then return true end

    local name, _, quality, itemLevel, _, _, _, _, _, texture = GetItemInfo(itemID)
    if not name then
        TriggerItemFetch(itemID)
        return false
    end
    -- texture is "Interface\Icons\INV_Sword_01" — we want the basename, lowercased.
    local icon = nil
    if texture then
        icon = texture:match("([^\\/]+)$") or texture
        icon = icon:lower()
    end
    local entry = {
        v = CACHE_SCHEMA,
        name = name,
        quality = quality or 0,
        itemLevel = itemLevel or 0,
        icon = icon,
        ts = floor(time()),
    }

    -- v0.22: capture per-item stats via GetItemStats. Ascension modifies stats
    -- on most retail items and adds entirely server-custom items not in any
    -- TDB extract — the client API is the only authoritative source. Stored
    -- with the original ITEM_MOD_* keys so the site's ingest can map them
    -- via the same enum used for TDB merging. Random suffix variants are
    -- ignored per spec — first roll wins for a given itemID.
    local link = itemLink or ("item:" .. itemID)
    if GetItemStats then
        local stats = GetItemStats(link)
        if stats then
            local serial = {}
            for k, v in pairs(stats) do
                if type(v) == "number" and v ~= 0 then
                    serial[k] = v
                end
            end
            -- Skip empty {} for shirts/tabards etc. so a missing field reads
            -- as "no data captured" rather than "captured but empty".
            if next(serial) then
                entry.stats = serial
            end
        end
    end

    -- v0.26+: tooltip-scan. Returns five fields:
    --   tooltipStats  — percent-based / pre-rating stats (Darkmantle "+1%
    --                   crit", Rival's "+3% player damage") that GetItemStats
    --                   doesn't expose in its enum.
    --   tooltipExtras — raw flavor/proc lines like Eskhandar's "Chance on
    --                   hit: Slows enemy's movement by 60%..." which aren't
    --                   numeric stats but belong on the armory tooltip.
    --   setBonuses    — each "Set:" / "(N) Set:" line as { pieces, text }.
    --                   Same bonus block appears on every item in the set;
    --                   site-side can dedup by itemSet later.
    --   damage        — weapon damage range { min, max, school? } (GetItemStats
    --                   only exposes DPS; the min/max and elemental school
    --                   live only in tooltip text).
    --   speed         — weapon attack speed as a decimal (e.g. 2.8).
    -- Any may be nil if not applicable to the item; site's ingest handles
    -- each in its own display path.
    local tooltipStats, tooltipExtras, setBonuses, damage, speed = ScanTooltip(link, entry.stats)
    if tooltipStats  then entry.tooltipStats  = tooltipStats  end
    if tooltipExtras then entry.tooltipExtras = tooltipExtras end
    if setBonuses    then entry.setBonuses    = setBonuses    end
    if damage        then entry.damage        = damage        end
    if speed         then entry.speed         = speed         end

    EpogItemCacheDB[itemID] = entry
    return true
end

local function MarkPendingCache(itemID, itemLink)
    if not itemID or itemID <= 0 then return end
    -- Only skip if a current-schema entry exists. Stale entries fall through
    -- so the pending retry loop eventually re-runs CacheItemInfo and upgrades.
    local existing = EpogItemCacheDB and EpogItemCacheDB[itemID]
    if existing and existing.v == CACHE_SCHEMA then return end
    if not pendingCache[itemID] then
        pendingCache[itemID] = { firstSeen = now(), link = itemLink }
        TriggerItemFetch(itemID)
    end
end

local function TryCachePending()
    if not next(pendingCache) then return end
    local nowT = now()
    for iid, info in pairs(pendingCache) do
        if CacheItemInfo(iid, info.link) then
            pendingCache[iid] = nil
        elseif (nowT - info.firstSeen) > CACHE_GIVE_UP then
            pendingCache[iid] = nil -- server never responded; try again on next scan
        end
    end
end

-- iterate gear slots, ensure every itemID is either cached or queued.
-- Passes the full itemstring as the hyperlink so GetItemStats can include
-- suffix-variant stats on the first scan that lands.
local function CachePayloadItems(entry)
    if not entry or not entry.gear then return end
    for slot = 1, 19 do
        local raw = entry.gear[slot]
        if raw and raw ~= "" then
            local iid = tonumber(raw:match("^(%d+)"))
            if iid and iid > 0 then
                local link = "item:" .. raw
                if not CacheItemInfo(iid, link) then MarkPendingCache(iid, link) end
            end
        end
    end
end

-- ---------------- Build + broadcast ----------------

-- Read the talent point distribution across the 3 tabs for a given unit.
-- Ascension's classless system sometimes returns 0 from GetTalentTabInfo's
-- pointsSpent field even when the player has real talents — so we also fall
-- back to summing pointsSpent across individual GetTalentInfo() reads. The
-- explicit talentGroup (from GetActiveTalentGroup) helps in cases where the
-- API doesn't default to the active group on Ascension.
-- Returns: s1, s2, s3, activeGroup (1-based, defaults to 1 when API missing).
local function ReadSpecPoints(unit)
    -- inspectFlag: 1 when reading another unit's talents (after NotifyInspect),
    -- nil for "player" — standard 3.3.5 GetTalentTabInfo convention.
    -- IMPORTANT: the idiom `cond and nil or 1` BREAKS when you want nil as the
    -- true branch — `true and nil` evaluates to `nil`, then `nil or 1` is `1`.
    -- Every self-scan from v0.3 through v0.15 was accidentally reading inspect
    -- data (isInspect=1) for "player", which returns 0 for every tab because
    -- you can't NotifyInspect yourself. That's why spec=0/0/0 on all self-scans.
    local isInspect
    if not UnitIsUnit(unit, "player") then isInspect = 1 end

    local function tabPoints(tabIndex)
        local pts = select(3, GetTalentTabInfo(tabIndex, isInspect)) or 0
        if pts > 0 then return pts end
        -- Fallback: iterate talents in this tab and sum pointsSpent directly.
        if GetNumTalents and GetTalentInfo then
            local n = GetNumTalents(tabIndex, isInspect) or 0
            local total = 0
            for i = 1, n do
                local _, _, _, _, spent = GetTalentInfo(tabIndex, i, isInspect)
                total = total + (spent or 0)
            end
            if total > 0 then return total end
        end
        return 0
    end

    return tabPoints(1), tabPoints(2), tabPoints(3)
end

-- Read the 3 class talent tabs' display names AND icon texture paths.
-- Ascension reorders tabs from retail WotLK on some classes, so we encode
-- this info per-scan into the payload rather than relying on a hardcoded
-- SPEC_TREE lookup. GetTalentTabInfo returns (name, iconTexture, pointsSpent,
-- background, previewPointsSpent, isUnlocked).
local function ReadTabInfo(unit)
    local isInspect
    if not UnitIsUnit(unit, "player") then isInspect = 1 end
    -- Defensive: strip the '^' separator and '|' (item-link escape) just in
    -- case a server-custom tab name or icon path contains them.
    local function clean(s) return (s or ""):gsub("[%^|]", "") end
    local names, icons = {}, {}
    for tab = 1, 3 do
        local n, i = GetTalentTabInfo(tab, isInspect)
        names[tab] = clean(n or "")
        icons[tab] = clean(i or "")
    end
    return names, icons
end

-- Scan the enchant description lines of an equipped item for blacklisted
-- patterns (Mithril Spurs etc.). Returns the first matching pattern or nil.
-- Only called on sender side (BuildPayload) so received broadcasts don't
-- pay the tooltip cost.
local enchantScanTip
local function ScanEnchantTooltip(link)
    if not link then return nil end
    if not enchantScanTip then
        enchantScanTip = CreateFrame("GameTooltip", "EpogArmoryEnchantScanTip", UIParent, "GameTooltipTemplate")
    end
    enchantScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    enchantScanTip:ClearLines()
    enchantScanTip:SetHyperlink(link)
    for i = 1, enchantScanTip:NumLines() do
        local fs = _G["EpogArmoryEnchantScanTipTextLeft" .. i]
        local text = fs and fs:GetText() or ""
        for _, pat in ipairs(UTILITY_ENCHANT_TOOLTIP_PATTERNS) do
            if text:find(pat, 1, true) then return pat end
        end
    end
    return nil
end

local function BuildPayload(unit, guid)
    local name = UnitName(unit)
    if not name or name == "" or name == UNKNOWN then return nil, "name unresolved" end
    local realm = GetRealmName() or ""
    local _, classFile = UnitClass(unit)
    classFile = classFile or ""
    local level = UnitLevel(unit) or 0

    local s1, s2, s3 = ReadSpecPoints(unit)
    local dominantTree = DominantTree({s1, s2, s3})
    local tabNames, tabIcons = ReadTabInfo(unit)
    -- v0.33: PvP loadouts (Insignia trinket equipped) get routed to
    -- sets["pvp"] on the player record instead of sets[dominantTree].
    -- Group key is stringified: "1" / "2" / "3" / "pvp". Receivers compute
    -- their own group locally from entry.gear, so the wire value is mostly
    -- informational/forward-compat.
    local groupKey = UnitLooksPvP(unit) and "pvp" or tostring(dominantTree)

    local parts = {
        "v" .. PROTO,
        name, realm, classFile, tostring(level), guid or "",
        tostring(s1), tostring(s2), tostring(s3),
        tostring(floor(time())),
        ZoneType(),
    }
    local equipped = 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink(unit, slot)
        local istr = ItemStringFromLink(link)
        if istr ~= "" then equipped = equipped + 1 end

        -- Name-based item blacklist (sender side — receive side also checks)
        if link then
            local itemName = GetItemInfo(link)
            if itemName then
                for _, pat in ipairs(UTILITY_ITEM_NAMES_ANY_SLOT) do
                    if itemName:find(pat, 1, true) then
                        return nil, string.format("utility item '%s' in slot %d", itemName, slot)
                    end
                end
                local bySlot = UTILITY_ITEM_NAMES_BY_SLOT[slot]
                if bySlot then
                    for _, pat in ipairs(bySlot) do
                        if itemName:find(pat, 1, true) then
                            return nil, string.format("utility item '%s' in slot %d (blacklisted pattern '%s')", itemName, slot, pat)
                        end
                    end
                end
            end
        end

        parts[#parts + 1] = istr
    end
    -- Mount enchant tooltip scan on boots + gloves. Only runs once per scan
    -- per slot, only on sender side.
    for _, mountSlot in ipairs(MOUNT_ENCHANT_SLOTS) do
        local link = GetInventoryItemLink(unit, mountSlot)
        local bad = ScanEnchantTooltip(link)
        if bad then
            return nil, string.format("mount enchant '%s' on slot %d", bad, mountSlot)
        end
    end
    if equipped < 10 then
        return nil, string.format("only %d slots equipped (inspect data incomplete?)", equipped)
    end
    -- Append dominant-tree index at position 31 (per v0.7 append-only rule).
    -- v0.14+ receivers actually compute this locally from entry.spec, so the
    -- field is informational/forward-compat only. Old v0.12 clients ignore it.
    parts[#parts + 1] = groupKey -- v0.33: "1"/"2"/"3" or "pvp" (was dominantTree numeric)
    -- Tab names at positions 32/33/34 so receivers can render class-tree
    -- labels that match the sender's actual client layout (Ascension reorders
    -- some classes vs retail WotLK). Older clients ignore the trailing fields.
    parts[#parts + 1] = tabNames[1]
    parts[#parts + 1] = tabNames[2]
    parts[#parts + 1] = tabNames[3]
    -- Tab icon paths at positions 35/36/37 (v0.18+) so the inspect-frame
    -- centerpiece icon exactly matches the server's spec icon.
    parts[#parts + 1] = tabIcons[1]
    parts[#parts + 1] = tabIcons[2]
    parts[#parts + 1] = tabIcons[3]
    -- v0.36: piggyback our local DB size (count of stored players) so the
    -- browser's Scanners view can show peers ordered by "how much data they
    -- have to share". Cheap — one small integer per broadcast, always
    -- additive at the tail per the append-only wire rule.
    local dbSize = 0
    if EpogArmoryDB and EpogArmoryDB.players then
        for _ in pairs(EpogArmoryDB.players) do dbSize = dbSize + 1 end
    end
    parts[#parts + 1] = tostring(dbSize)
    -- v0.43: emit our configured main-name identity at position 39. Empty
    -- string when not configured — receivers fall back to the wire sender
    -- character name. Lets the user consolidate scans from all their alts
    -- under one identity.
    local myMain = (EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.mainName) or ""
    -- Strip wire-control chars defensively (^ separator, | item-link escape)
    myMain = myMain:gsub("[%^|]", "")
    parts[#parts + 1] = myMain
    return table.concat(parts, "^"), equipped
end

local function MakeChunks(payload, msgID)
    local body = MAX_CHUNK_BODY
    local count = math.ceil(#payload / body)
    if count < 1 then count = 1 end
    local out = {}
    for i = 1, count do
        local sub = payload:sub((i - 1) * body + 1, i * body)
        out[i] = string.format("%s^%d^%d^%s", msgID, i, count, sub)
    end
    return out
end

local function PickChannels()
    local list = {}
    if GetNumRaidMembers() > 0 then
        table.insert(list, "RAID")
    elseif GetNumPartyMembers() > 0 then
        table.insert(list, "PARTY")
    end
    if IsInGuild() then
        table.insert(list, "GUILD")
    end
    return list
end

local function EnqueueBroadcast(payload, targetName)
    local channels = PickChannels()
    if #channels == 0 then
        dprint(string.format("[send] %s: no channel available (solo + no guild)", targetName or "?"))
        return
    end
    msgCounter = msgCounter + 1
    local msgID = string.format("%x%x", math.floor(now() * 10) % 0xffff, msgCounter % 0xffff)
    local chunks = MakeChunks(payload, msgID)
    for _, ch in ipairs(channels) do
        for _, body in ipairs(chunks) do
            outQueue[#outQueue + 1] = { ch = ch, body = body }
        end
    end
    dprint(string.format("[send] %s: %d chunks x %d channels [%s] (%d bytes)",
        targetName or "?", #chunks, #channels, table.concat(channels, "+"), #payload))
end

-- ---------------- Receive: parse + store ----------------

local function ShouldStore(entry)
    if not entry then return false, "nil entry" end
    if (entry.level or 0) < MIN_STORE_LEVEL then
        return false, string.format("level %d < %d", entry.level or 0, MIN_STORE_LEVEL)
    end
    -- Ascension is classless: GetTalentTabInfo(tab, ...) returns 0 points-spent
    -- for every tab regardless of what the player actually specced, so we can't
    -- use spec distribution as a "committed player" gate here. The server-side
    -- validator in warcraftlogs-epog still has the final say on what gets
    -- published — we just collect everything gated by level + gear-equipped.
    local equipped = 0
    for i = 1, 19 do
        if entry.gear[i] and entry.gear[i] ~= "" then equipped = equipped + 1 end
    end
    if equipped < MIN_STORE_EQUIPPED then
        return false, string.format("only %d slots equipped", equipped)
    end
    for slot = 1, 19 do
        local s = entry.gear[slot]
        if s and s ~= "" then
            local iid, eid = s:match("^(%d+):(%-?%d+)")
            iid = tonumber(iid) or 0
            eid = tonumber(eid) or 0
            if UTILITY_ITEMS[iid] then
                return false, "utility item equipped: " .. UTILITY_ITEMS[iid]
            end
            if UTILITY_ENCHANTS[eid] then
                return false, "utility enchant: " .. UTILITY_ENCHANTS[eid]
            end
            -- Name-pattern blacklist (works across all Ascension custom item IDs).
            -- Only effective if GetItemInfo has cached the item — uncached items
            -- pass through this check. CachePayloadItems runs before ShouldStore
            -- so most will be resolved by now.
            if iid > 0 then
                local itemName = GetItemInfo(iid)
                if itemName then
                    for _, pat in ipairs(UTILITY_ITEM_NAMES_ANY_SLOT) do
                        if itemName:find(pat, 1, true) then
                            return false, "utility item name: " .. itemName
                        end
                    end
                    local bySlot = UTILITY_ITEM_NAMES_BY_SLOT[slot]
                    if bySlot then
                        for _, pat in ipairs(bySlot) do
                            if itemName:find(pat, 1, true) then
                                return false, string.format("utility item in slot %d: %s", slot, itemName)
                            end
                        end
                    end
                end
            end
        end
    end
    return true
end

local function ParsePayload(payload)
    local t = { strsplit("^", payload) }
    -- Accept any payload in the same PROTO family: exact "v<PROTO>" or
    -- "v<PROTO>.<minor>" (future soft-bump). Reject a different major (e.g. "v2").
    -- Unknown trailing tokens past slot 19 (position 31+) are ignored — that's
    -- our forward-compat channel for additive changes.
    local tag = t[1]
    if not tag or (tag ~= ("v" .. PROTO) and not tag:match("^v" .. PROTO .. "%.")) then
        return nil
    end
    local entry = {
        name        = t[2] or "",
        realm       = t[3] or "",
        class       = t[4] or "",
        level       = tonumber(t[5]) or 0,
        guid        = t[6] or "",
        spec        = { tonumber(t[7]) or 0, tonumber(t[8]) or 0, tonumber(t[9]) or 0 },
        scanTime    = tonumber(t[10]) or 0,
        zone        = t[11] or "",
        gear        = {},
        -- Position 31 — v0.13+ carries the sender's group key. Value is
        -- numeric "1"/"2"/"3" for class trees or "pvp" for PvP loadouts
        -- (v0.33+). Kept as a string here for forward-compat; Ingest
        -- computes its own group key locally from entry.gear + spec, so
        -- this field is informational only.
        groupKey    = t[31] or "1",
    }
    for i = 1, 19 do entry.gear[i] = t[11 + i] or "" end
    -- v0.17+: positions 32/33/34 carry class tab names ("Combat",
    -- "Assassination", "Subtlety"). Older payloads: tabNames stays nil and
    -- the UI falls back to SPEC_TREE[class].
    if t[32] and t[32] ~= "" then
        entry.tabNames = { t[32] or "", t[33] or "", t[34] or "" }
    end
    -- v0.18+: positions 35/36/37 carry tab icon texture paths for rendering
    -- the centerpiece spec icon in the inspect frame.
    if t[35] and t[35] ~= "" then
        entry.tabIcons = { t[35] or "", t[36] or "", t[37] or "" }
    end
    -- v0.36+: position 38 carries the sender's own DB size (count of stored
    -- players). Used by the browser's Scanners view to rank peers by "how
    -- much data they have to share". Absent on older payloads.
    if t[38] and t[38] ~= "" then
        entry.senderDBSize = tonumber(t[38])
    end
    -- v0.43+: position 39 carries the sender's configured main-name identity.
    -- Used as the canonical scanner identity (scannedBy + peerInfo key) so
    -- scans broadcast from multiple alts of the same user consolidate under
    -- one name. Absent or empty on older payloads / unconfigured clients,
    -- in which case the receiver falls back to the wire sender character
    -- name.
    if t[39] and t[39] ~= "" then
        entry.senderMain = t[39]
    end
    if entry.name == "" or entry.guid == "" then return nil end
    return entry
end

local function Ingest(payload, sender)
    local entry = ParsePayload(payload)
    if not entry then
        dprint("[store] REJECT: payload parse failed")
        return
    end

    -- Always update the "when was this GUID last inspected by anyone" clock
    -- so the 24h dedup works across the full mesh — even if this particular
    -- scan fails ShouldStore (utility gear, wrong zone, etc).
    MarkInspected(entry.guid, entry.scanTime)

    -- v0.36: record the sender's reported DB size. Persisted in
    -- EpogArmoryDB.peerInfo so the Scanners view works immediately on
    -- login (before any fresh broadcasts arrive) based on the latest
    -- counts we heard last session.
    -- v0.43: key by the sender's main-name identity (entry.senderMain) when
    -- they have one set, so all alts of the same user consolidate into one
    -- Scanners-view entry. Track lastCharName so reachability checks have
    -- a real character name to look up in guild/group rosters.
    local effectiveScanner = (entry.senderMain ~= nil and entry.senderMain ~= "") and entry.senderMain or sender
    if entry.senderDBSize and effectiveScanner and effectiveScanner ~= "" and effectiveScanner ~= MyIdentity() then
        EpogArmoryDB.peerInfo = EpogArmoryDB.peerInfo or {}
        EpogArmoryDB.peerInfo[effectiveScanner] = {
            dbSize       = entry.senderDBSize,
            lastSeen     = entry.scanTime or time(),
            lastCharName = sender, -- character actually broadcasting (for reachability lookups)
        }
    end

    -- Populate the item-info cache from every scan we observe — even rejected
    -- ones give us valid itemIDs to enrich our DB.
    CachePayloadItems(entry)

    local ok, reason = ShouldStore(entry)
    if not ok then
        dprint(string.format("[store] REJECT: %s L%d — %s", entry.name, entry.level, reason))
        return
    end

    EpogArmoryDB = EpogArmoryDB or { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = {} }
    EpogArmoryDB.players = EpogArmoryDB.players or {}

    -- Set key — computed locally, NOT read from wire position 31, so we're
    -- robust against sender bugs and older clients that key differently.
    -- If the scanned player has an Insignia trinket equipped (slot 13/14)
    -- the loadout is a PvP set and routes to sets["pvp"]. Otherwise it goes
    -- to sets[DominantTree(spec)] for 1/2/3 class-tree keying.
    local group
    if EntryGearLooksPvP(entry.gear) then
        group = "pvp"
    else
        group = DominantTree(entry.spec)
    end
    -- v0.43: prefer the broadcaster's main-name identity (entry.senderMain)
    -- so set.scannedBy reads as the consolidated user name across alts.
    -- Fall back to wire sender for older clients without the field, and
    -- finally to MyIdentity() (covers the local direct-ingest path where
    -- sender == self and we want our own configured main name applied).
    local scannedBy = entry.senderMain
    if not scannedBy or scannedBy == "" then scannedBy = sender end
    if not scannedBy or scannedBy == "" then scannedBy = MyIdentity() end
    local existing = EpogArmoryDB.players[entry.guid]

    -- Per-spec dedup: only this tree's set is compared for staleness. A newer
    -- scan of a *different* tree set is never skipped here — different slot.
    if existing and existing.sets and existing.sets[group]
        and (existing.sets[group].scanTime or 0) >= entry.scanTime then
        dprint(string.format("[store] SKIP: %s (set %s) — existing set is newer (%s vs %s)",
            entry.name, tostring(group),
            date("%H:%M:%S", existing.sets[group].scanTime or 0),
            date("%H:%M:%S", entry.scanTime)))
        return
    end

    -- Create or merge the player record, preserving sets for the other talent
    -- groups. Top-level `name/realm/class/level` always reflect the latest scan.
    existing = existing or { sets = {} }
    existing.sets  = existing.sets or {}
    existing.guid  = entry.guid -- v0.20: store guid on the record so the UI can pass it to DeletePlayer
    existing.name  = entry.name
    existing.realm = entry.realm
    existing.class = entry.class
    existing.level = entry.level
    if entry.tabNames then existing.tabNames = entry.tabNames end -- v0.17+
    if entry.tabIcons then existing.tabIcons = entry.tabIcons end -- v0.18+
    existing.sets[group] = {
        spec       = entry.spec,
        gear       = entry.gear,
        scanTime   = entry.scanTime,
        zone       = entry.zone,
        scannedBy  = scannedBy,
        -- v0.35: stash the raw wire payload so an admin running
        -- /epogarmory syncfrom <us> can replay it verbatim without
        -- having to reconstruct the wire format from structured fields.
        -- Keeps the sync protocol drift-proof as BuildPayload evolves.
        rawPayload = payload,
    }

    -- Mirror the most-recently-scanned set to top-level fields for
    -- backward-compat with the UI (v0.14 UI reads directly from .sets and this
    -- mirror becomes redundant). Picks the highest-scanTime set across all
    -- stored talent groups.
    local latestSet, latestTime = nil, 0
    for _, s in pairs(existing.sets) do
        if (s.scanTime or 0) > latestTime then
            latestTime = s.scanTime or 0
            latestSet = s
        end
    end
    if latestSet then
        existing.spec      = latestSet.spec
        existing.gear      = latestSet.gear
        existing.scanTime  = latestSet.scanTime
        existing.zone      = latestSet.zone
        existing.scannedBy = latestSet.scannedBy
    end

    EpogArmoryDB.players[entry.guid] = existing
    dprint(string.format("[store] OK: %s L%d [set %s / %s] — scanned by %s at %s",
        entry.name, entry.level, tostring(group), entry.zone, scannedBy,
        date("%H:%M:%S", entry.scanTime)))

    -- v0.21: notify the UI so an open browser list refreshes without the
    -- user having to close + reopen. Registered as a field on the shared
    -- namespace table; nil-safe if UI hasn't wired it up yet.
    if _G.EpogArmory and _G.EpogArmory.OnPlayerChanged then
        _G.EpogArmory.OnPlayerChanged(entry.guid)
    end
end

-- Numeric-tuple semver compare. Returns 1 if a > b, -1 if a < b, 0 equal.
-- Non-numeric suffixes (e.g. "-beta") are ignored — only digit runs count.
local function CompareVersions(a, b)
    if a == b then return 0 end
    local function parts(v)
        local out = {}
        for n in tostring(v or ""):gmatch("(%d+)") do out[#out+1] = tonumber(n) end
        return out
    end
    local pa, pb = parts(a), parts(b)
    local len = math.max(#pa, #pb)
    for i = 1, len do
        local na, nb = pa[i] or 0, pb[i] or 0
        if na ~= nb then return na > nb and 1 or -1 end
    end
    return 0
end

local function HandleVersionPing(payload, sender)
    -- payload shape: "VER^<version>"
    local tag, senderVersion = strsplit("^", payload)
    if tag ~= "VER" or not senderVersion or senderVersion == "" then return end
    dprint(string.format("[version] %s is on v%s (we're v%s)",
        sender or "?", senderVersion, ADDON_VERSION))
    if versionNotified then return end
    if CompareVersions(senderVersion, ADDON_VERSION) <= 0 then return end
    versionNotified = true
    print(string.format("|cffffaa44EpogArmory|r: newer version |cff00ff00v%s|r available (you're on v%s). Download: %s",
        senderVersion, ADDON_VERSION, RELEASES_URL))
end

local function TrySendVersionPing()
    if versionPingSent then return end
    if now() < versionPingAt then return end
    local channels = PickChannels()
    if #channels == 0 then
        -- Solo + no guild: no one to ping yet. Defer and try again.
        versionPingAt = now() + VERSION_PING_RETRY
        return
    end
    versionPingSent = true
    msgCounter = msgCounter + 1
    local msgID = string.format("V%x", msgCounter % 0xffff)
    local body = string.format("%s^1^1^VER^%s", msgID, ADDON_VERSION)
    for _, ch in ipairs(channels) do
        outQueue[#outQueue + 1] = { ch = ch, body = body }
    end
    dprint(string.format("[version] pinging v%s on [%s]",
        ADDON_VERSION, table.concat(channels, "+")))
end

-- v0.47: Peer refresh ping. Asks every guildmate running the addon to
-- announce their identity + dbSize so the Scanners leaderboard refreshes
-- without having to wait for organic gear-scan broadcasts. Triggered by
-- the "Refresh Peers" button in the Scanners view (and /epogarmory
-- refreshpeers). Returns true on send; false + reason string on cooldown.
local function BroadcastPeerPing()
    local nowT = time()
    local since = nowT - lastPeerPingSentAt
    if since < PEER_PING_COOLDOWN then
        local wait = PEER_PING_COOLDOWN - since
        return false, "cooldown", wait
    end
    local channels = PickChannels()
    if #channels == 0 then
        return false, "nochannel"
    end
    msgCounter = msgCounter + 1
    local msgID = string.format("P%x", msgCounter % 0xffff)
    -- Identity field lets responders skip self-echoes if they happen to
    -- have us configured as their own main alias (paranoia — sender-name
    -- echo drop in OnAddonMessage already covers the normal case).
    local body = string.format("%s^1^1^PEERPING^%s", msgID, MyIdentity())
    for _, ch in ipairs(channels) do
        outQueue[#outQueue + 1] = { ch = ch, body = body }
    end
    lastPeerPingSentAt = nowT
    dprint(string.format("[peerping] sent on [%s]", table.concat(channels, "+")))
    return true, table.concat(channels, "+")
end

-- v0.47: respond to an incoming PEERPING. Lightweight: announce identity,
-- dbSize, version, current character name. Replies go on the SAME channel
-- the request arrived on so requester gets them via the same chat envelope.
-- Per-requester cooldown prevents looping if a misbehaving client spams.
local function HandlePeerPing(payload, sender, channel)
    if channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" then return end
    local tag, requester = strsplit("^", payload)
    if tag ~= "PEERPING" then return end
    requester = requester or sender or "?"
    -- Per-requester cooldown
    local last = lastPeerPongTo[requester] or 0
    if (time() - last) < PEER_RESPONSE_COOLDOWN then
        dprint(string.format("[peerping] decline %s — cooldown (%ds since last pong)",
            requester, time() - last))
        return
    end
    -- Compute our current dbSize
    local dbSize = 0
    if EpogArmoryDB and EpogArmoryDB.players then
        for _ in pairs(EpogArmoryDB.players) do dbSize = dbSize + 1 end
    end
    local me = UnitName("player") or "?"
    local identity = MyIdentity()
    msgCounter = msgCounter + 1
    local msgID = string.format("p%x", msgCounter % 0xffff)
    -- PEERPONG^<identity>^<dbSize>^<version>^<charName>
    local body = string.format("%s^1^1^PEERPONG^%s^%d^%s^%s",
        msgID, identity, dbSize, ADDON_VERSION, me)
    outQueue[#outQueue + 1] = { ch = channel, body = body }
    lastPeerPongTo[requester] = time()
    dprint(string.format("[peerping] replied to %s on %s (dbSize=%d, identity=%s)",
        requester, channel, dbSize, identity))
end

-- v0.47: ingest an incoming PEERPONG. Updates peerInfo so the Scanners
-- leaderboard reflects the responder's current dbSize + last-seen.
local function HandlePeerPong(payload, sender)
    local tag, identity, dbSizeStr, version, charName = strsplit("^", payload)
    if tag ~= "PEERPONG" then return end
    if not identity or identity == "" then identity = sender or "?" end
    local dbSize = tonumber(dbSizeStr) or 0
    EpogArmoryDB = EpogArmoryDB or {}
    EpogArmoryDB.peerInfo = EpogArmoryDB.peerInfo or {}
    EpogArmoryDB.peerInfo[identity] = {
        dbSize       = dbSize,
        lastSeen     = time(),
        lastCharName = charName or sender,
        version      = version,
    }
    dprint(string.format("[peerping] got pong from %s (identity=%s, dbSize=%d, v%s)",
        sender or "?", identity, dbSize, version or "?"))
end

-- v0.46: build a compact manifest of "what we already have" for the
-- requester side of syncfrom. Format: "guid:group:scanTime;..." per stored
-- (player, set) tuple. Sent inside the SYNCREQ at position 5; the
-- responder parses it and skips sending any (guid, group) entries the
-- requester already has at >= our scanTime — eliminating the dominant
-- "[store] SKIP: existing set is newer (T vs T)" duplicate-send waste.
--
-- Size: each entry ~30 bytes. 100 stored players × 1.5 sets avg ≈ 4.5 KB.
-- Carries fine over the existing chunked addon-message pipeline.
local function BuildSyncManifest()
    if not (EpogArmoryDB and EpogArmoryDB.players) then return "" end
    local pieces = {}
    for guid, p in pairs(EpogArmoryDB.players) do
        if guid and guid ~= "" and p.sets then
            for setKey, set in pairs(p.sets) do
                if set.scanTime and set.scanTime > 0 then
                    pieces[#pieces + 1] = guid .. ":" .. tostring(setKey) .. ":" .. tostring(set.scanTime)
                end
            end
        end
    end
    return table.concat(pieces, ";")
end

local function ParseSyncManifest(s)
    local out = {}
    if not s or s == "" then return out end
    for entry in s:gmatch("([^;]+)") do
        local guid, group, t = entry:match("^([^:]+):([^:]+):(%d+)$")
        if guid and group and t then
            out[guid] = out[guid] or {}
            out[guid][group] = tonumber(t)
        end
    end
    return out
end

-- v0.35: handle an incoming SYNCREQ. Only responds if:
--   1. The request targets this client specifically (by name match)
--   2. Arrived on GUILD channel (so we're not responding to random whispers)
--   3. We haven't responded to this requester within SYNC_RESPONSE_COOLDOWN
-- When responding, we iterate stored sets with scanTime > sinceTS and replay
-- their raw wire payloads via the outQueue — bounded to
-- SYNC_MAX_SETS_PER_RESPONSE to cap drain duration. The normal 2s broadcast
-- stagger paces these so the guild channel isn't saturated.
local function HandleSyncRequest(payload, sender, channel)
    -- v0.37: accept from guild, party, or raid. Same trust envelope — WoW
    -- fills in sender name on receive, and addon-messages on these channels
    -- are only deliverable by peers actually in that group/guild.
    if channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" then
        dprint(string.format("[sync] ignore request from %s — bad channel (%s)", sender or "?", channel or "?"))
        return
    end
    -- v0.46: position 5 is an optional manifest "guid:group:scanTime;..."
    -- Old (≤v0.45) requesters omit it → manifestStr is nil → ParseSyncManifest
    -- returns empty table → behavior identical to v0.45 (send everything).
    local tag, requester, target, sinceStr, manifestStr = strsplit("^", payload)
    if tag ~= "SYNCREQ" then return end
    if not target or target == "" then return end
    -- v0.43: accept either our character name OR our configured main name.
    -- Lets an admin do `syncfrom <main>` and reach whichever alt the user
    -- is currently on with that mainName configured.
    local me = UnitName("player")
    local myMain = (EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.mainName) or nil
    if target ~= me and target ~= myMain then
        -- Request is for someone else; silently ignore.
        return
    end
    -- v0.37: user-toggleable opt-out. Default is to accept; syncoff disables
    -- responding entirely for the rest of the session (until /reload or
    -- re-toggle). Useful as emergency escape if getting sync-bombed.
    if EpogArmoryDB and EpogArmoryDB.config and EpogArmoryDB.config.acceptSync == false then
        dprint(string.format("[sync] decline %s — user has syncoff enabled", requester or "?"))
        return
    end
    -- v0.37: global response cooldown — caps aggregate outQueue load even
    -- when multiple attackers each have their own per-requester cooldown
    -- slots. One response per 15 min across all requesters.
    if (time() - lastSyncResponseAt) < SYNC_GLOBAL_COOLDOWN then
        dprint(string.format("[sync] decline %s — global cooldown (%.1fm since last response)",
            requester or "?", (time() - lastSyncResponseAt) / 60))
        return
    end
    -- Rate-limit per requester to prevent a single requester from looping.
    local last = lastSyncResponseTo[requester or ""] or 0
    if (time() - last) < SYNC_RESPONSE_COOLDOWN then
        dprint(string.format("[sync] decline %s — responded %.1fh ago (cooldown 1h)",
            requester or "?", (time() - last) / 3600))
        return
    end
    local sinceTS = tonumber(sinceStr) or 0
    if not (EpogArmoryDB and EpogArmoryDB.players) then return end

    -- v0.46: parse manifest of what the requester already has. Skip any
    -- (guid, setKey) where their stored scanTime >= ours — they would just
    -- log "[store] SKIP: existing set is newer". Saves the bandwidth.
    local requesterHas = ParseSyncManifest(manifestStr or "") -- Claude v0.46

    local queued, skipped = 0, 0
    for _, p in pairs(EpogArmoryDB.players) do
        if queued >= SYNC_MAX_SETS_PER_RESPONSE then break end
        if p.sets and p.guid then
            local mineForGuid = requesterHas[p.guid]
            for setKey, set in pairs(p.sets) do
                if queued >= SYNC_MAX_SETS_PER_RESPONSE then break end
                if set.rawPayload and (set.scanTime or 0) > sinceTS then
                    -- v0.46: manifest-based dedup. setKey can be number (1/2/3)
                    -- or "pvp" string; manifest entries are normalized via
                    -- tostring on both sides.
                    local theirT = mineForGuid and mineForGuid[tostring(setKey)]
                    if theirT and theirT >= (set.scanTime or 0) then
                        skipped = skipped + 1 -- Claude v0.46: skip duplicate
                    else
                        -- Chunk + enqueue with a fresh msgID so receivers see
                        -- this as a new broadcast (different assembly key).
                        msgCounter = msgCounter + 1
                        local msgID = string.format("%x%x",
                            math.floor(now() * 10) % 0xffff, msgCounter % 0xffff)
                        local chunks = MakeChunks(set.rawPayload, msgID)
                        for _, chunk in ipairs(chunks) do
                            outQueue[#outQueue + 1] = { ch = "GUILD", body = chunk }
                        end
                        queued = queued + 1
                    end
                end
            end
        end
    end
    lastSyncResponseTo[requester or ""] = time()
    lastSyncResponseAt = time() -- v0.37: stamp global cooldown
    dprint(string.format("[sync] responding to %s: queued %d, skipped %d (already fresh) since %s (max %d)",
        requester or "?", queued, skipped,
        sinceTS > 0 and date("%Y-%m-%d %H:%M", sinceTS) or "epoch",
        SYNC_MAX_SETS_PER_RESPONSE))
end

local function OnAddonMessage(prefix, body, channel, sender)
    if prefix ~= PREFIX then return end
    -- Drop our own echoes. Addon messages broadcast on GUILD/PARTY/RAID always
    -- round-trip back to the sender's client, and when we broadcast to multiple
    -- channels (e.g. PARTY + GUILD) the payload echoes back once per channel.
    -- We already direct-ingest our own scans in TryScanSelf / OnInspectReady
    -- before broadcasting, so these echoes are pure spam — [recv] chunks,
    -- [store] SKIP, and duplicate [version] self-pings.
    if sender and sender == UnitName("player") then return end
    if not body or body == "" then return end
    local msgID, idx_s, total_s, data = body:match("^([^%^]+)%^([^%^]+)%^([^%^]+)%^(.*)$")
    local idx = tonumber(idx_s)
    local total = tonumber(total_s)
    if not msgID or not idx or not total or not data then return end

    local key = (sender or "?") .. "\001" .. msgID
    local asm = assembly[key]
    if not asm then
        asm = { chunks = {}, total = total, firstSeen = now() }
        assembly[key] = asm
        dprint(string.format("[recv] new scan from %s (chunk %d/%d, expecting %d more)",
            sender or "?", idx, total, total - 1))
    end
    if asm.chunks[idx] then return end
    asm.chunks[idx] = data

    local have = 0
    for i = 1, total do
        if asm.chunks[i] then have = have + 1 end
    end
    if have == total then
        local pieces = {}
        for i = 1, total do pieces[i] = asm.chunks[i] end
        local full = table.concat(pieces)
        assembly[key] = nil
        dprint(string.format("[recv] complete from %s — %d chunks assembled (%d bytes)",
            sender or "?", total, #full))
        -- Route VER pings separately from gear payloads; they share the reassembly
        -- framing but decode to a different shape.
        if full:sub(1, 4) == "VER^" then
            HandleVersionPing(full, sender)
        elseif full:sub(1, 8) == "SYNCREQ^" then
            HandleSyncRequest(full, sender, channel)
        elseif full:sub(1, 9) == "PEERPING^" then -- Claude v0.47
            HandlePeerPing(full, sender, channel)
        elseif full:sub(1, 9) == "PEERPONG^" then -- Claude v0.47
            HandlePeerPong(full, sender)
        else
            Ingest(full, sender)
        end
    end
end

local function GCAssembly()
    local cutoff = now() - ASSEMBLY_TIMEOUT
    for k, v in pairs(assembly) do
        if v.firstSeen < cutoff then
            local have = 0
            for i = 1, v.total do if v.chunks[i] then have = have + 1 end end
            local senderName = k:match("^([^\001]+)") or "?"
            dprint(string.format("[asm] dropped partial from %s: got %d/%d chunks after %ds",
                senderName, have, v.total, ASSEMBLY_TIMEOUT))
            assembly[k] = nil
        end
    end
end

-- ---------------- Scan queue + inspect driver ----------------

local function AddUnit(unit)
    if not UnitExists(unit) then return end
    if UnitIsUnit(unit, "player") then return end
    if not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or guid == "" then return end
    if inQueue[guid] then return end
    local last = seen[guid]
    if last and (now() - last) < INSPECT_COOLDOWN then return end
    if HasFreshScan(guid) then return end -- someone in the mesh scanned this player <24h ago
    if (UnitLevel(unit) or 0) < MIN_INSPECT_LEVEL then return end
    queue[#queue + 1] = { guid = guid, unit = unit }
    inQueue[guid] = true
end

local function ScanRoster()
    lastRoster = now()
    local before = #queue
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do AddUnit("raid" .. i) end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, 4 do AddUnit("party" .. i) end
    end
    local added = #queue - before
    if added > 0 then
        dprint(string.format("[roster] +%d to queue (total %d pending)", added, #queue))
    end
end

local function ClearCurrent()
    current = nil
    nextInspectAt = now() + INSPECT_INTERVAL
end

local function TryInspect()
    if current then return end
    if now() < nextInspectAt then return end
    if #queue == 0 then return end
    if InCombatLockdown() then return end

    local entry = table.remove(queue, 1)
    inQueue[entry.guid] = nil
    local name = UnitName(entry.unit) or "?"
    if not UnitExists(entry.unit) or UnitGUID(entry.unit) ~= entry.guid then
        dprint(string.format("[inspect] SKIP: %s — raid slot reshuffled since queue time", name))
        return
    end
    if not CanInspect(entry.unit) then
        markRetryIn(entry.guid, OUT_OF_RANGE_COOLDOWN)
        dprint(string.format("[inspect] SKIP: %s — CanInspect=false (out of range / not visible). retry in %ds",
            name, OUT_OF_RANGE_COOLDOWN))
        return
    end
    current = { guid = entry.guid, unit = entry.unit, startedAt = now() }
    NotifyInspect(entry.unit)
    dprint(string.format("[inspect] START: %s L%d — NotifyInspect sent (%d left in queue)",
        name, UnitLevel(entry.unit) or 0, #queue))
end

local function CheckTimeout()
    if current and (now() - current.startedAt) > INSPECT_TIMEOUT then
        dprint(string.format("[inspect] TIMEOUT: %s — no INSPECT_TALENT_READY after %ds, retry in %ds",
            UnitName(current.unit) or "?", INSPECT_TIMEOUT, OUT_OF_RANGE_COOLDOWN))
        markRetryIn(current.guid, OUT_OF_RANGE_COOLDOWN) -- transient fail, short retry (not 15 min)
        ClearCurrent()
    end
end

local function OnInspectReady()
    if not current then return end
    local c = current
    if UnitGUID(c.unit) ~= c.guid then
        dprint("[inspect] READY fired but current GUID no longer matches — dropping")
        ClearCurrent()
        return
    end
    local tname = UnitName(c.unit) or "?"
    local tlvl = UnitLevel(c.unit) or 0
    local payload, info = BuildPayload(c.unit, c.guid)
    if payload then
        seen[c.guid] = now()
        MarkInspected(c.guid, floor(time()))
        dprint(string.format("[inspect] OK: %s L%d — %d slots equipped, payload %d bytes",
            tname, tlvl, info, #payload))
        EnqueueBroadcast(payload, tname)
        -- direct-ingest our own scan so we save data even when no one
        -- else is in our broadcast channels.
        Ingest(payload, UnitName("player"))
    else
        -- incomplete inspect data (0-9 slots) is usually transient —
        -- target moved out mid-response or server was slow. Short retry, not
        -- the 15-min full cooldown which is reserved for successful scans.
        markRetryIn(c.guid, OUT_OF_RANGE_COOLDOWN)
        dprint(string.format("[inspect] DROP: %s L%d — %s (retry in %ds)",
            tname, tlvl, info or "unknown", OUT_OF_RANGE_COOLDOWN))
    end
    if ClearInspectPlayer then ClearInspectPlayer() end
    ClearCurrent()
end

-- ---------------- Self-scan ----------------
-- scanning yourself is a free fast path — no NotifyInspect required,
-- GetInventoryItemLink("player", slot) works immediately. Triggered by
-- UNIT_INVENTORY_CHANGED (debounced 2s so equipping a set doesn't fire 19
-- times) and once on PLAYER_LOGIN after a 3s warmup for talent data.

local SELF_SCAN_DEBOUNCE = 2
local SELF_SCAN_LOGIN_DELAY = 3

local selfScanPending = false
local selfScanAt = 0
-- Fingerprint of the last successfully-broadcast self-scan (level + talents
-- + gear itemStrings). On Ascension, UNIT_INVENTORY_CHANGED fires every ~15s
-- for reasons unrelated to real gear swaps (durability ticks, aura procs,
-- server-side refreshes), so without this check we'd rebroadcast the same
-- payload over and over. The fingerprint changes only when something that
-- actually matters to the mesh has changed.
local lastSelfFingerprint = ""

local function SelfFingerprint()
    local parts = { tostring(UnitLevel("player") or 0) }
    -- Spec points change on any talent shift → fingerprint differs → scan.
    -- No need to also include an "active group" field; the point distribution
    -- already captures what matters.
    local s1, s2, s3 = ReadSpecPoints("player")
    parts[#parts + 1] = string.format("%d:%d:%d", s1, s2, s3)
    for slot = 1, 19 do
        parts[#parts + 1] = ItemStringFromLink(GetInventoryItemLink("player", slot))
    end
    return table.concat(parts, "|")
end

local function RequestSelfScan(delay)
    selfScanPending = true
    selfScanAt = now() + (delay or SELF_SCAN_DEBOUNCE)
end

local function TryScanSelf()
    if not selfScanPending then return end
    if now() < selfScanAt then return end
    if InCombatLockdown() then
        selfScanAt = now() + SELF_SCAN_DEBOUNCE
        return
    end
    selfScanPending = false

    local playerGUID = UnitGUID("player")
    if not playerGUID then return end

    -- v0.43: don't waste mesh bandwidth on self-scans below MIN_STORE_LEVEL.
    -- Receivers' ShouldStore would reject them anyway (level < 60), and
    -- without this gate every peer sees a "[store] REJECT: <name> L33 —
    -- level 33 < 60" debug line for every alt-broadcast cycle. Inspect-
    -- side already gates via MIN_INSPECT_LEVEL in AddUnit; this matches
    -- the symmetric self-side gate.
    local myLevel = UnitLevel("player") or 0
    if myLevel < MIN_STORE_LEVEL then
        dprint(string.format("[self] skip — level %d < %d (no broadcast from low-level alts)",
            myLevel, MIN_STORE_LEVEL))
        return
    end

    -- Silent short-circuit: nothing meaningful has changed since our last
    -- broadcast. UNIT_INVENTORY_CHANGED fires every ~15s on Ascension from
    -- durability/aura noise; unchanged fingerprint → no log, no work.
    -- Real changes (gear swap, respec, talent shift) bump the fingerprint
    -- and fall through to the actual scan. v0.13's per-active-group 24h
    -- gate is dropped — it was blocking legitimate respec scans because
    -- Ascension's classless GetActiveTalentGroup reports 1 unchanged, so
    -- the "active group" key never changed on a respec.
    local fp = SelfFingerprint()
    if fp == lastSelfFingerprint then return end

    local payload, info = BuildPayload("player", playerGUID)
    if not payload then
        dprint(string.format("[self] scan skipped — %s", info or "unknown"))
        return
    end
    lastSelfFingerprint = fp
    local _s1, _s2, _s3 = ReadSpecPoints("player")
    dprint(string.format("[self] scanned self — %d slots equipped, spec=%d/%d/%d tree=%d, payload %d bytes",
        info, _s1, _s2, _s3, DominantTree({_s1, _s2, _s3}), #payload))
    MarkInspected(playerGUID, floor(time()))
    EnqueueBroadcast(payload, UnitName("player"))
    Ingest(payload, UnitName("player"))
end

-- ---------------- Migration ----------------
-- v0.14 normalizes the per-player data model:
--   players[guid] = { name, realm, class, level,
--                     sets = { [dominantTree] = { spec, gear, scanTime, zone, scannedBy } },
--                     ...top-level mirror of latest set }
--
-- This runs once at login and handles two legacy shapes:
--   (a) Pre-v0.13 flat: { name, realm, class, level, spec, gear, scanTime, zone, scannedBy }
--       → wrap into sets[DominantTree(spec)].
--   (b) v0.13 sets keyed by activeTalentGroup (usually always 1 on Ascension)
--       → re-key by DominantTree(set.spec). If two entries collide, newest wins.
local function MigratePlayers()
    if not (EpogArmoryDB and EpogArmoryDB.players) then return end
    local migrated = 0
    for guid, p in pairs(EpogArmoryDB.players) do
        -- v0.20: backfill guid on the record. Pre-v0.20 entries didn't store
        -- it, so the UI's Delete button had nothing to pass to DeletePlayer.
        if not p.guid then p.guid = guid end
        if p.gear and not p.sets then
            -- (a) pre-v0.13 flat
            local tree = DominantTree(p.spec)
            p.sets = {
                [tree] = {
                    spec      = p.spec or { 0, 0, 0 },
                    gear      = p.gear,
                    scanTime  = p.scanTime or 0,
                    zone      = p.zone or "",
                    scannedBy = p.scannedBy or "?",
                }
            }
            migrated = migrated + 1
        elseif p.sets then
            -- (b) v0.13 sets → re-key under DominantTree if any entry's key
            -- disagrees with its spec's dominant tree.
            local rekeyed = {}
            local changed = false
            for oldKey, s in pairs(p.sets) do
                local newKey = DominantTree(s.spec)
                if newKey ~= oldKey then changed = true end
                if (not rekeyed[newKey]) or ((rekeyed[newKey].scanTime or 0) < (s.scanTime or 0)) then
                    rekeyed[newKey] = s
                end
            end
            if changed then
                p.sets = rekeyed
                migrated = migrated + 1
            end
        end
    end
    if migrated > 0 then
        dprint(string.format("[migrate] normalized %d player entries to DominantTree keys", migrated))
    end
end

-- ---------------- Main loop + events ----------------

local acc, gcAcc = 0, 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc < 0.25 then return end
    acc = 0

    if (now() - lastRoster) > ROSTER_TICK then ScanRoster() end

    if #outQueue > 0 and now() >= nextSendAt then
        local item = table.remove(outQueue, 1)
        SendAddonMessage(PREFIX, item.body, item.ch)
        nextSendAt = now() + BROADCAST_STAGGER
    end

    CheckTimeout()
    TryInspect()
    TryScanSelf()
    TryCachePending()
    TrySendVersionPing()

    gcAcc = gcAcc + 0.25
    if gcAcc >= 10 then gcAcc = 0; GCAssembly() end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("INSPECT_TALENT_READY")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("UNIT_INVENTORY_CHANGED") -- self gear changes trigger a rescan of "player"
f:RegisterEvent("PLAYER_TALENT_UPDATE")   -- respec / dual-spec switch triggers a rescan of "player"

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EpogArmoryDB = EpogArmoryDB or { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = {} }
        EpogArmoryDB.players     = EpogArmoryDB.players     or {}
        EpogArmoryDB.lastScanned = EpogArmoryDB.lastScanned or {}
        EpogArmoryDB.config      = EpogArmoryDB.config      or {}
        EpogArmoryDB.peerInfo    = EpogArmoryDB.peerInfo    or {}
        -- v0.43: track every character that's logged into this account so
        -- /epogarmory main can validate against the list. SavedVariables is
        -- account-scoped, so this set accumulates across alts naturally.
        EpogArmoryDB.knownChars  = EpogArmoryDB.knownChars  or {}
        local me = UnitName("player")
        if me and me ~= "" then EpogArmoryDB.knownChars[me] = true end
        -- v0.40: zone restriction removed; any lingering requireInstance
        -- in old SavedVariables is just a vestigial dead field.
        EpogArmoryDB.config.requireInstance = nil
        -- v0.37: responder-side sync opt-in defaults to true.
        if EpogArmoryDB.config.acceptSync == nil then
            EpogArmoryDB.config.acceptSync = true
        end
        -- v0.43: optional main-name identity. When set, all broadcasts from
        -- this client carry it at wire position 39. Receivers use it as the
        -- canonical scanner identity, consolidating alts under the main.
        -- Default nil = use character name (no consolidation, current behavior).
        --
        -- v0.45: auto-default mainName to the FIRST L60 character to log in.
        -- Most users want consolidation; auto-defaulting on the first L60
        -- saves them from having to discover and run /epogarmory main. Once
        -- set, it sticks (account-wide via SavedVariables) — subsequent
        -- logins on different characters don't change it.
        if not EpogArmoryDB.config.mainName then
            local lvl = UnitLevel("player") or 0
            if me and me ~= "" and lvl >= MIN_STORE_LEVEL then
                EpogArmoryDB.config.mainName = me
                print(string.format("|cffffaa44EpogArmory|r: auto-set main identity to |cff00ff66%s|r (first L60 to log in). Change with /epogarmory main.",
                    me))
            end
        end

        -- v0.45: auto-prune peerInfo entries that haven't been heard from
        -- in 30+ days. Keeps the Scanners view focused on currently-active
        -- peers and prevents the table from accumulating orphan rows
        -- forever. Contributor-only entries (no peerInfo) are filtered
        -- by AggregateScanners at display time using the same cutoff.
        local staleCutoff = time() - 30 * 86400
        local pruned = 0
        for name, info in pairs(EpogArmoryDB.peerInfo) do
            if (info.lastSeen or 0) < staleCutoff then
                EpogArmoryDB.peerInfo[name] = nil
                pruned = pruned + 1
            end
        end
        if pruned > 0 then
            dprint(string.format("[migrate] pruned %d stale peerInfo entries (>30d)", pruned))
        end

        EpogItemCacheDB = EpogItemCacheDB or {}
        MigratePlayers() -- wrap pre-v0.13 flat entries into sets[1]
        RequestSelfScan(SELF_SCAN_LOGIN_DELAY) -- initial self-scan after talent data warms up
        versionPingAt = now() + VERSION_PING_DELAY -- one-shot version broadcast, 2min after login
        return
    end
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    elseif event == "INSPECT_TALENT_READY" then
        OnInspectReady()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then RequestSelfScan() end
    elseif event == "PLAYER_TALENT_UPDATE" then
        RequestSelfScan()
    else
        ScanRoster()
    end
end)

-- ---------------- Slash ----------------

local function CountStored()
    if not EpogArmoryDB or not EpogArmoryDB.players then return 0 end
    local n = 0
    for _ in pairs(EpogArmoryDB.players) do n = n + 1 end
    return n
end

local function CountTracked()
    if not EpogArmoryDB or not EpogArmoryDB.lastScanned then return 0 end
    local n = 0
    for _ in pairs(EpogArmoryDB.lastScanned) do n = n + 1 end
    return n
end

local function CountAssembly()
    local n = 0
    for _ in pairs(assembly) do n = n + 1 end
    return n
end

local function CountCache()
    if not EpogItemCacheDB then return 0 end
    local n = 0
    for _ in pairs(EpogItemCacheDB) do n = n + 1 end
    return n
end

local function CountPending()
    local n = 0
    for _ in pairs(pendingCache) do n = n + 1 end
    return n
end

-- Public namespace — used by the UI for cross-file access to helpers that
-- need to live in EpogArmory.lua (for scoping / state reasons).
_G.EpogArmory = _G.EpogArmory or {}

-- v0.37: expose sync-state accessors for the UI's Scanners view.
_G.EpogArmory.IsPeerSyncActive = function(name)
    CleanExpiredSyncs()
    return activeSyncs[name] ~= nil
end
_G.EpogArmory.SyncEndTimeFor = function(name)
    CleanExpiredSyncs()
    return activeSyncs[name]
end
_G.EpogArmory.ActiveSyncCount = function()
    return CountActiveSyncs()
end
_G.EpogArmory.SyncMaxConcurrent = SYNC_MAX_CONCURRENT
-- v0.47: Refresh Peers button calls this. Returns (true, channels) on send,
-- (false, "cooldown", secondsRemaining) on cooldown, (false, "nochannel") if
-- not in guild/group.
_G.EpogArmory.RequestPeerRefresh = function() -- Claude v0.47
    return BroadcastPeerPing()
end
-- Also resets the 24h HasFreshScan gate for this GUID (by wiping
-- lastScanned[guid]) and the in-memory 15min inspect cooldown (seen[guid]),
-- so *this client* can re-inspect immediately if they're in range. If the
-- user is deleting their own entry, force a fresh self-scan by clearing the
-- fingerprint and queueing RequestSelfScan.
_G.EpogArmory = _G.EpogArmory or {}
_G.EpogArmory.DeletePlayer = function(guid)
    if not guid or guid == "" then return end
    local name = "?"
    if EpogArmoryDB and EpogArmoryDB.players and EpogArmoryDB.players[guid] then
        name = EpogArmoryDB.players[guid].name or "?"
        EpogArmoryDB.players[guid] = nil
    end
    if EpogArmoryDB and EpogArmoryDB.lastScanned then
        EpogArmoryDB.lastScanned[guid] = nil
    end
    seen[guid] = nil
    if guid == UnitGUID("player") then
        lastSelfFingerprint = ""
        RequestSelfScan()
    end
    dprint(string.format("[delete] removed %s (%s) from local DB", name, guid))
end

-- iterate all stored players and feed every itemID through the cache.
-- Anything not cached locally gets queued for a SetHyperlink-triggered server
-- fetch; the OnUpdate poll picks them up over the next few seconds.
local function CacheBuildAll()
    if not EpogArmoryDB or not EpogArmoryDB.players then return 0, 0, 0 end
    local tried, hit, pended = 0, 0, 0
    local function processGear(gear)
        for slot = 1, 19 do
            local raw = gear[slot]
            if raw and raw ~= "" then
                local iid = tonumber(raw:match("^(%d+)"))
                if iid and iid > 0 then
                    tried = tried + 1
                    local link = "item:" .. raw
                    if CacheItemInfo(iid, link) then
                        hit = hit + 1
                    else
                        MarkPendingCache(iid, link)
                        pended = pended + 1
                    end
                end
            end
        end
    end
    for _, p in pairs(EpogArmoryDB.players) do
        -- v0.22: walk per-spec sets so stats get captured for every loadout,
        -- not just the latest-mirror p.gear. The CacheItemInfo dedup makes
        -- redundant calls cheap (early-out on EpogItemCacheDB[itemID]).
        if p.sets then
            for _, s in pairs(p.sets) do
                if s.gear then processGear(s.gear) end
            end
        elseif p.gear then
            processGear(p.gear)
        end
    end
    return tried, hit, pended
end

local function ShowHelp()
    print("|cffffaa44EpogArmory|r commands:")
    print("  /epogarmory show <name>   — open paperdoll for a stored player (or target + /epogarmory show)")
    print("  /epogarmory browse        — open the searchable armory browser")
    print("  /epogarmory status        — queue / broadcast / storage state")
    print("  /epogarmory debug         — toggle verbose chat logging")
    print("  /epogarmory list          — print every stored player")
    print("  /epogarmory wipe          — clear stored players (keeps config)")
    print("  /epogarmory cache         — show item-info cache size")
    print("  /epogarmory cachebuild    — fill the cache from all stored players' gear (names/quality/ilvl)")
    print("  /epogarmory cachewipe     — clear the item-info cache")
    print("  /epogarmory main [name]   — set/show your main-character identity (consolidates alts in the mesh)")
    print("  /epogarmory merge <newname> <alias1> [alias2] ... — locally re-attribute scans from peer aliases to one canonical name")
    print("  /epogarmory refreshpeers  — ping guildmates for fresh identity + DB-size info (Scanners-view leaderboard)")
    print("|cff888888  Source + releases: github.com/Defcons/epogarmory-addon|r")
    -- dumpspec left in place but not advertised — internal diagnostic.
end

SLASH_EPOGARMORY1 = "/epogarmory"
SlashCmdList["EPOGARMORY"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "debug" then
        EpogArmoryDebug = not EpogArmoryDebug
        print("|cffffaa44EpogArmory|r debug:",
            EpogArmoryDebug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
    elseif msg == "status" then
        print(string.format("|cffffaa44EpogArmory|r stored=%d tracked=%d cache=%d cachePending=%d queue=%d outPending=%d asm=%d currentInspect=%s inCombat=%s zone=%s",
            CountStored(), CountTracked(), CountCache(), CountPending(),
            #queue, #outQueue, CountAssembly(),
            current and UnitName(current.unit) or "none",
            tostring(InCombatLockdown()),
            ZoneType()))
    elseif msg == "cache" then
        print(string.format("|cffffaa44EpogArmory|r cache: %d items known, %d pending client fetch",
            CountCache(), CountPending()))
    elseif msg == "cachebuild" then
        local tried, hit, pended = CacheBuildAll()
        print(string.format("|cffffaa44EpogArmory|r cachebuild: %d items scanned, %d already known, %d queued for fetch (check /epogarmory cache in ~15s)",
            tried, hit, pended))
    elseif msg == "cachewipe" then
        EpogItemCacheDB = {}
        pendingCache = {}
        print("|cffffaa44EpogArmory|r: wiped item-info cache")
    elseif msg == "wipe" then
        local kept = EpogArmoryDB and EpogArmoryDB.config or {}
        EpogArmoryDB = { meta = { version = 1, created = time() }, players = {}, lastScanned = {}, config = kept }
        -- Clear in-memory self-scan dedup state too, otherwise the next scan
        -- short-circuits on a fingerprint match against the pre-wipe state and
        -- your own player never gets re-added to the freshly-wiped DB.
        lastSelfFingerprint = ""
        RequestSelfScan()
        print("|cffffaa44EpogArmory|r: wiped players + lastScanned (kept config) — self-scan queued")
    elseif msg == "list" then
        if not EpogArmoryDB or not EpogArmoryDB.players then print("empty") return end
        for guid, p in pairs(EpogArmoryDB.players) do
            print(string.format("  %s %s L%d [%s] — by %s at %s",
                p.class or "?", p.name or "?", p.level or 0, p.zone or "?",
                p.scannedBy or "?", date("%Y-%m-%d %H:%M", p.scanTime or 0)))
        end
    elseif msg == "dumpspec" or msg == "specs" then
        -- Diagnostic: shows every talent-API variant's read for each of the
        -- player's 3 tabs. Tells us which call style actually returns real
        -- points-spent on this Ascension client.
        print("|cffffaa44EpogArmory|r talent-read diagnostics for self:")
        local gatg = GetActiveTalentGroup and GetActiveTalentGroup() or nil
        local gntg = GetNumTalentGroups and GetNumTalentGroups() or nil
        print(string.format("  GetActiveTalentGroup() = %s    GetNumTalentGroups() = %s",
            tostring(gatg), tostring(gntg)))
        for tab = 1, 3 do
            local name1, _, pts1 = GetTalentTabInfo(tab)
            local name2, _, pts2 = GetTalentTabInfo(tab, nil)
            local _,     _, pts3 = GetTalentTabInfo(tab, nil, nil, 1)
            local _,     _, pts4 = GetTalentTabInfo(tab, nil, nil, 2)
            local nt = (GetNumTalents and GetNumTalents(tab)) or 0
            local sumDefault = 0
            for i = 1, nt do
                local _, _, _, _, spent = GetTalentInfo(tab, i)
                sumDefault = sumDefault + (spent or 0)
            end
            local sumGroup1 = 0
            for i = 1, nt do
                local _, _, _, _, spent = GetTalentInfo(tab, i, nil, nil, 1)
                sumGroup1 = sumGroup1 + (spent or 0)
            end
            print(string.format("  Tab %d [%s]: GTTI(1-arg)=%s  GTTI(nil)=%s  GTTI(grp=1)=%s  GTTI(grp=2)=%s  GTI-sum(default)=%d  GTI-sum(grp=1)=%d  over %d talents",
                tab, tostring(name1 or "?"),
                tostring(pts1 or "nil"), tostring(pts2 or "nil"),
                tostring(pts3 or "nil"), tostring(pts4 or "nil"),
                sumDefault, sumGroup1, nt))
        end
        local s1, s2, s3 = ReadSpecPoints("player")
        print(string.format("  ReadSpecPoints(player) = %d / %d / %d → DominantTree = %d",
            s1, s2, s3, DominantTree({s1, s2, s3})))
    elseif msg == "refreshpeers" or msg == "refresh" then
        -- v0.47: ask everyone in guild/group "give me your latest info".
        -- Each peer running v0.47+ replies with identity + dbSize + version
        -- so the Scanners leaderboard gets fresh data without having to
        -- wait for organic gear-scan broadcasts.
        local ok, info, extra = BroadcastPeerPing()
        if ok then
            print(string.format("|cffffaa44EpogArmory|r: peer refresh sent on %s — responses will arrive over the next ~5s.", info))
        elseif info == "cooldown" then
            print(string.format("|cffffaa44EpogArmory|r: peer refresh on cooldown (%ds remaining).", extra))
        elseif info == "nochannel" then
            print("|cffffaa44EpogArmory|r: peer refresh requires being in a guild or group.")
        end
    elseif msg:sub(1, 8) == "syncfrom" then
        -- Hidden admin command: request another peer to replay their recent
        -- stored scans. v0.37: extended to party + raid + guild channels.
        -- Usage:
        --   /epogarmory syncfrom <playerName>         (default: last 7 days)
        --   /epogarmory syncfrom <playerName> 30      (last 30 days)
        --   /epogarmory syncfrom <playerName> 0       (everything the peer has)
        -- Capped at SYNC_MAX_CONCURRENT (3) simultaneous active syncs so the
        -- inbound data stream stays manageable.
        local argStr = msg:sub(10) -- everything after "syncfrom "
        local name, daysStr = argStr:match("^%s*(%S+)%s*(%S*)%s*$")
        if not name or name == "" then
            print("|cffffaa44EpogArmory|r: usage — /epogarmory syncfrom <playerName> [days]")
            return
        end
        -- Canonical name casing (peer compares UnitName("player") == name exactly)
        name = name:sub(1, 1):upper() .. name:sub(2):lower()
        -- Active-sync cap (requester side).
        CleanExpiredSyncs()
        if activeSyncs[name] then
            local remain = math.max(0, activeSyncs[name] - time())
            print(string.format("|cffffaa44EpogArmory|r: already syncing from |cff00ff00%s|r — ~%dm remaining",
                name, math.ceil(remain / 60)))
            return
        end
        if CountActiveSyncs() >= SYNC_MAX_CONCURRENT then
            -- v0.50: don't quote a fixed "~25 min" anymore — actual time
            -- depends on peer DB size. Just say "wait for one to finish".
            print(string.format("|cffffaa44EpogArmory|r: already at %d concurrent syncs. Wait for one to finish (varies by peer DB size — see Scanners view for countdowns).",
                SYNC_MAX_CONCURRENT))
            return
        end
        local days = tonumber(daysStr) or 7
        local sinceTS = days > 0 and (time() - days * 86400) or 0
        local channels = PickChannels()
        if #channels == 0 then
            print("|cffffaa44EpogArmory|r: sync requires being in a guild or group (request is sent via addon-message channel)")
            return
        end
        msgCounter = msgCounter + 1
        local msgID = string.format("S%x", msgCounter % 0xffff)
        -- v0.43: requester field uses MyIdentity (configured main name or
        -- character name fallback). Per-requester cooldowns on the responder
        -- side now consolidate across all alts of the same admin.
        -- v0.46: append a manifest of (guid:group:scanTime;...) so the
        -- responder can skip sets we already have at >= their scanTime.
        -- Eliminates the dominant duplicate-send waste from full-DB syncs.
        -- Manifest can be ~4.5 KB for 100 players, so chunk via MakeChunks.
        local manifest = BuildSyncManifest() -- Claude v0.46: include manifest
        local fullPayload = string.format("SYNCREQ^%s^%s^%d^%s",
            MyIdentity(), name, sinceTS, manifest)
        local chunks = MakeChunks(fullPayload, msgID) -- Claude v0.46: multi-chunk
        for _, ch in ipairs(channels) do
            for _, chunk in ipairs(chunks) do
                outQueue[#outQueue + 1] = { ch = ch, body = chunk }
            end
        end
        -- v0.50: estimate sync duration from peerInfo.dbSize instead of
        -- always advertising 25 min (the worst-case 200-set cap). Each set
        -- ≈ 4 chunks × 2s stagger ≈ 8s; manifest dedup may shrink the
        -- actual count further but we don't know what they have, so the
        -- upper bound here is min(reportedDB, SYNC_MAX_SETS_PER_RESPONSE).
        -- 60s safety buffer for any drift.
        local estimatedSets = SYNC_MAX_SETS_PER_RESPONSE
        if EpogArmoryDB and EpogArmoryDB.peerInfo and EpogArmoryDB.peerInfo[name]
           and EpogArmoryDB.peerInfo[name].dbSize then
            estimatedSets = math.min(EpogArmoryDB.peerInfo[name].dbSize,
                                     SYNC_MAX_SETS_PER_RESPONSE)
        end
        local etaSeconds = estimatedSets * 8 + 60
        local etaMinutes = math.max(1, math.ceil(etaSeconds / 60))
        activeSyncs[name] = time() + etaSeconds
        print(string.format("|cffffaa44EpogArmory|r: requested sync from |cff00ff00%s|r (last %d days) via %s. ETA ~%d min (peer has ~%d entries).",
            name, days, table.concat(channels, "+"), etaMinutes, estimatedSets))
        local manifestEntries = 0
        if manifest ~= "" then
            -- count separators + 1 (entries are joined by ";")
            local _, n = manifest:gsub(";", ";")
            manifestEntries = n + 1
        end
        dprint(string.format("[sync] sent SYNCREQ in %d chunk(s), manifest = %d bytes (%d entries)",
            #chunks, #manifest, manifestEntries))
        -- Refresh the browser scanners view if it's open so the row dims.
        if _G.EpogArmoryBrowserFrame and _G.EpogArmoryBrowserFrame:IsShown()
            and _G.EpogArmoryBrowserFrame.Refresh then
            _G.EpogArmoryBrowserFrame.Refresh()
        end
    elseif msg == "main" or msg:sub(1, 5) == "main " then
        -- v0.43: pick which of your characters is your "main" identity.
        -- v0.44: account-wide persistence (SavedVariables already is, just
        -- makes that clear in messaging). On rename, retro-rewrite local
        -- DB scannedBy/peerInfo entries from the old main (or any of your
        -- known characters) to the new main, so the Scanners view
        -- consolidates instead of continuing to show stale separate rows.
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        EpogArmoryDB.knownChars = EpogArmoryDB.knownChars or {}
        local arg = msg:match("^main%s+(.+)$")

        local function knownList()
            local names = {}
            for n, _ in pairs(EpogArmoryDB.knownChars) do names[#names + 1] = n end
            table.sort(names)
            return names
        end

        if not arg then
            local current = EpogArmoryDB.config.mainName
            local me = UnitName("player") or "?"
            if current then
                print(string.format("|cffffaa44EpogArmory|r: main identity = |cff00ff66%s|r |cff888888(account-wide, persists across all your characters)|r",
                    current))
            else
                print(string.format("|cffffaa44EpogArmory|r: main identity = |cffff9966NOT SET|r |cff888888— broadcasts will attribute to whichever character is currently logged in (now: %s).|r",
                    me))
            end
            print("|cff888888  Your known characters:|r " .. table.concat(knownList(), ", "))
            print("|cff888888  Set:|r /epogarmory main <character>   |cff888888|   Clear:|r /epogarmory main clear")
        elseif arg == "clear" or arg == "none" then
            local oldMain = EpogArmoryDB.config.mainName
            EpogArmoryDB.config.mainName = nil
            print("|cffffaa44EpogArmory|r: main identity cleared — broadcasts now attribute to current character name")
            if oldMain then
                print(string.format("|cff888888  Past scans attributed to '%s' keep that name. Future broadcasts use current character name.|r",
                    oldMain))
            end
        else
            local pick = arg:sub(1, 1):upper() .. arg:sub(2):lower()
            if not EpogArmoryDB.knownChars[pick] then
                print(string.format("|cffffaa44EpogArmory|r: |cffff6666%s|r isn't one of your known characters. Log in once on that character first.",
                    pick))
                print("|cff888888  Your known:|r " .. table.concat(knownList(), ", "))
                return
            end
            local oldMain = EpogArmoryDB.config.mainName
            EpogArmoryDB.config.mainName = pick

            -- v0.44: consolidate prior scans under the new main. Rewrite any
            -- scannedBy and peerInfo entries that match (a) the previous
            -- mainName or (b) any of YOUR known character names — these all
            -- represent "you" in the mesh, just under different names.
            -- Other players' scannedBy values are NOT rewritten; this is
            -- purely a local reattribution of YOUR contributions.
            local rewriteSet = {}
            if oldMain and oldMain ~= pick then rewriteSet[oldMain] = true end
            for charName in pairs(EpogArmoryDB.knownChars) do
                if charName ~= pick then rewriteSet[charName] = true end
            end

            local rewroteScans = 0
            if EpogArmoryDB.players then
                for _, p in pairs(EpogArmoryDB.players) do
                    if p.sets then
                        for _, s in pairs(p.sets) do
                            if s.scannedBy and rewriteSet[s.scannedBy] then
                                s.scannedBy = pick
                                rewroteScans = rewroteScans + 1
                            end
                        end
                    end
                end
            end

            local mergedPeers = 0
            if EpogArmoryDB.peerInfo then
                for aliasName in pairs(rewriteSet) do
                    local info = EpogArmoryDB.peerInfo[aliasName]
                    if info then
                        EpogArmoryDB.peerInfo[pick] = EpogArmoryDB.peerInfo[pick] or { dbSize = 0, lastSeen = 0 }
                        local target = EpogArmoryDB.peerInfo[pick]
                        if (info.dbSize or 0) > (target.dbSize or 0) then
                            target.dbSize = info.dbSize
                        end
                        if (info.lastSeen or 0) > (target.lastSeen or 0) then
                            target.lastSeen = info.lastSeen
                            target.lastCharName = info.lastCharName or aliasName
                        end
                        EpogArmoryDB.peerInfo[aliasName] = nil
                        mergedPeers = mergedPeers + 1
                    end
                end
            end

            -- Force fresh self-scan so the new identity hits the wire on the
            -- next broadcast cycle without waiting for a fingerprint change.
            lastSelfFingerprint = ""
            RequestSelfScan()

            print(string.format("|cffffaa44EpogArmory|r: main identity = |cff00ff66%s|r |cff888888(account-wide; broadcasts from any of your characters will attribute to this name)|r",
                pick))
            if rewroteScans > 0 or mergedPeers > 0 then
                print(string.format("|cff888888  Consolidated: %d stored scans + %d peer entries from your alts → %s|r",
                    rewroteScans, mergedPeers, pick))
            end
            if _G.EpogArmoryBrowserFrame and _G.EpogArmoryBrowserFrame:IsShown()
                and _G.EpogArmoryBrowserFrame.Refresh then
                _G.EpogArmoryBrowserFrame.Refresh()
            end
        end
    elseif msg:sub(1, 6) == "merge " or msg == "merge" then
        -- v0.44: admin tool — locally consolidate multiple peer aliases under
        -- one canonical name. Useful when you can see "Yippee" / "Yippie" /
        -- "Yiippee" in the Scanners view and know they're the same player
        -- but they haven't set their main yet. Only affects YOUR local DB.
        local args = {}
        for word in (msg:sub(7) or ""):gmatch("%S+") do
            args[#args + 1] = word
        end
        if #args < 2 then
            print("|cffffaa44EpogArmory|r: usage — /epogarmory merge <newname> <alias1> [alias2] ...")
            print("|cff888888  Example:|r /epogarmory merge Yippie Yiippee Yippee")
            print("|cff888888  Locally rewrites scannedBy + peerInfo from aliases into <newname>. Other guildies still see the original names until they run merge too.|r")
            return
        end
        local newName = args[1]:sub(1, 1):upper() .. args[1]:sub(2):lower()
        local rewriteSet = {}
        for i = 2, #args do
            local alias = args[i]:sub(1, 1):upper() .. args[i]:sub(2):lower()
            if alias ~= newName then rewriteSet[alias] = true end
        end
        local rewroteScans = 0
        if EpogArmoryDB and EpogArmoryDB.players then
            for _, p in pairs(EpogArmoryDB.players) do
                if p.sets then
                    for _, s in pairs(p.sets) do
                        if s.scannedBy and rewriteSet[s.scannedBy] then
                            s.scannedBy = newName
                            rewroteScans = rewroteScans + 1
                        end
                    end
                end
            end
        end
        local mergedPeers = 0
        if EpogArmoryDB and EpogArmoryDB.peerInfo then
            for aliasName in pairs(rewriteSet) do
                local info = EpogArmoryDB.peerInfo[aliasName]
                if info then
                    EpogArmoryDB.peerInfo[newName] = EpogArmoryDB.peerInfo[newName] or { dbSize = 0, lastSeen = 0 }
                    local target = EpogArmoryDB.peerInfo[newName]
                    if (info.dbSize or 0) > (target.dbSize or 0) then
                        target.dbSize = info.dbSize
                    end
                    if (info.lastSeen or 0) > (target.lastSeen or 0) then
                        target.lastSeen = info.lastSeen
                        target.lastCharName = info.lastCharName or aliasName
                    end
                    EpogArmoryDB.peerInfo[aliasName] = nil
                    mergedPeers = mergedPeers + 1
                end
            end
        end
        print(string.format("|cffffaa44EpogArmory|r: merged %d scan attributions + %d peer entries → |cff00ff66%s|r",
            rewroteScans, mergedPeers, newName))
        print("|cff888888  Local-only — other guildies still see the original names until they merge too.|r")
        if _G.EpogArmoryBrowserFrame and _G.EpogArmoryBrowserFrame:IsShown()
            and _G.EpogArmoryBrowserFrame.Refresh then
            _G.EpogArmoryBrowserFrame.Refresh()
        end
    elseif msg == "syncoff" or msg == "syncon" then
        -- Toggle the responder-side opt-out. When "off", we refuse any
        -- incoming SYNCREQ regardless of requester. Persists in
        -- EpogArmoryDB.config.acceptSync.
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        if msg == "syncoff" then
            EpogArmoryDB.config.acceptSync = false
            print("|cffffaa44EpogArmory|r: sync-response |cffff6666OFF|r — will refuse incoming SYNCREQ. /epogarmory syncon to re-enable.")
        else
            EpogArmoryDB.config.acceptSync = true
            print("|cffffaa44EpogArmory|r: sync-response |cff00ff66ON|r — accepting incoming SYNCREQ again.")
        end
        if _G.EpogArmoryBrowserFrame and _G.EpogArmoryBrowserFrame:IsShown()
            and _G.EpogArmoryBrowserFrame.Refresh then
            _G.EpogArmoryBrowserFrame.Refresh()
        end
    elseif msg:sub(1, 9) == "dumpstats" then
        -- Diagnostic: print GetItemStats + tooltip lines for equipped slots.
        -- Lets us see exactly which keys Ascension's client returns for a
        -- problem item (e.g. items with percent-based custom stats that might
        -- or might not be in the standard ITEM_MOD_* enum). Usage:
        --   /epogarmory dumpstats        → all 19 slots
        --   /epogarmory dumpstats 10     → just hands
        local arg = msg:match("^dumpstats%s+(%d+)")
        local target = tonumber(arg)
        local slots = target and { target } or {1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19} -- skip 4=shirt
        local tip = CreateFrame("GameTooltip", "EpogArmoryDumpStatsTip", UIParent, "GameTooltipTemplate")
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        for _, slot in ipairs(slots) do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local name = GetItemInfo(link) or "?"
                print(string.format("|cffffaa44EpogArmory|r slot %d [%s]", slot, name))
                local stats = GetItemStats and GetItemStats(link)
                if stats then
                    local anyKey = false
                    for k, v in pairs(stats) do
                        anyKey = true
                        print(string.format("    GetItemStats: %s = %s", tostring(k), tostring(v)))
                    end
                    if not anyKey then print("    GetItemStats: <empty table>") end
                else
                    print("    GetItemStats: <nil>")
                end
                -- Tooltip-line scan for comparison. Captures lines that
                -- include a percent or a common stat keyword.
                tip:ClearLines()
                tip:SetHyperlink(link)
                local dumped = 0
                for i = 2, tip:NumLines() do -- skip line 1 (item name, already printed)
                    local fs = _G["EpogArmoryDumpStatsTipTextLeft" .. i]
                    local text = fs and fs:GetText() or ""
                    if text ~= "" and (text:find("%%") or text:lower():find("rating") or text:lower():find("increas") or text:lower():find("reduc") or text:lower():find("improv") or text:find("^%+%d")) then
                        print(string.format("    tip%2d: %s", i, text))
                        dumped = dumped + 1
                    end
                end
                if dumped == 0 then print("    tooltip: <no stat-like lines matched>") end
            end
        end
        tip:Hide()
    else
        ShowHelp()
    end
end
