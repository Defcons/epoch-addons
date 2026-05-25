-- ============================================================================
-- EpogArmoryDungeon.lua — Dungeon speedrun tracker frame
-- ============================================================================
-- Detects when the player enters a tracked dungeon (per the epoglogs.com
-- leaderboard's supported set), opens a small status frame showing the
-- boss roster + kill progress + run timer + /combatlog status. Prompts
-- the user once on entry to start logging.
--
-- Passive validation: boss UNIT_DIED events in the log ARE the proof
-- the run is real — no Validate button, no marker. The site parses the
-- log for the expected boss kill sequence and accepts based on that.
-- (Matches how Warcraftlogs treats raid logs.)
--
-- Stratholme side detection: GetInstanceInfo returns "Stratholme" for
-- both Live and Undead sides. We pick the side on first-boss-kill and
-- lock it in for the rest of the run.
-- ============================================================================
-- Claude (v1.7.3 internal): new module — dungeon speedrun status frame
-- ============================================================================

local floor = math.floor
local time, GetTime = time, GetTime

-- ============================================================================
-- Dungeon roster — keyed by GetInstanceInfo() name
-- ============================================================================

-- Roster source: epoglogs.com leaderboard rules (pasted 2026-05-20).
-- Boss names are exact, case-sensitive — they must match UNIT_DIED's
-- destName from CLEU. If the server has localized boss names different
-- from these, the kill won't register. (No locale issues expected on
-- Project Epoch since the server uses English globally.)
--
-- NOT included in this first cut: trash bucket requirements from the
-- epoglogs rules. Those need OR-group tracking which adds ~200 lines
-- of UI/state. Boss tracking covers the primary user need ("which
-- bosses did I kill, which am I missing"). Add trash in v1.7.4 if
-- the user asks.
-- Multi-variant pattern: some instances share one GetInstanceInfo() name
-- but map to multiple leaderboard dungeons. The "variants" field signals
-- DetectDungeon that a side/variant choice is needed:
--   "Blackrock Spire" → variants { lbrs, ubrs }
--   "Stratholme"      → variants { live, undead }
-- For these, the user picks a variant via buttons in the frame (or it
-- auto-resolves on the first boss kill that uniquely belongs to one side).
-- Single-variant dungeons just have a top-level `bosses` array.
local DUNGEONS = {
    ["Blackrock Depths"] = {
        displayName = "Blackrock Depths",
        bosses = {
            "Lord Incendius",
            "Magmus",
            "Emperor Dagran Thaurissan",
            "Princess Moira Bronzebeard",
        },
        -- v1.7.6: most buckets get their display name auto-derived from
        -- the common word-prefix of their mobs. Manual `name` only set
        -- where the auto wouldn't disambiguate (e.g. two buckets in the
        -- same trash list with the same first word).
        trash = {
            { mobs = {"Fireguard"},                                            required = 1 },
            { mobs = {"Anvilrage Footman", "Anvilrage Guardsman"},             required = 6 },
            { mobs = {"Blazing Fireguard"},                                    required = 2 },
            { mobs = {"Fireguard Destroyer"},                                  required = 3 },
        },
    },
    ["Blackrock Spire"] = {
        displayName = "Blackrock Spire (variant: select below)",
        variants = {
            lbrs = {
                displayName = "Lower Blackrock Spire",
                shortName   = "LBRS",
                bosses = {
                    "Highlord Omokk",
                    "Shadow Hunter Vosh'gajin",
                    "War Master Voone",
                    "Mother Smolderweb",
                    "Halycon",
                    "Overlord Wyrmthalak",
                },
                trash = {
                    { mobs = {"Scarshield Legionnaire","Scarshield Acolyte","Scarshield Spellbinder","Scarshield Raider","Scarshield Warlock"}, required = 16 },
                    { mobs = {"Spirestone Enforcer","Spirestone Ogre Magus","Spirestone Battle Mage","Spirestone Warlord"},                     required = 6 },
                    -- Smolderthorn A/B both auto-compute to "Smolderthorn"; load-time
                    -- collision suffix turns them into "Smolderthorn (1)" / "(2)".
                    { mobs = {"Smolderthorn Shadow Priest","Smolderthorn Mystic","Smolderthorn Axe Thrower","Smolderthorn Shadow Hunter"},      required = 10 },
                    { mobs = {"Smolderthorn Berserker","Smolderthorn Seer","Smolderthorn Witch Doctor","Smolderthorn Headhunter"},              required = 9 },
                    { mobs = {"Firebrand Legionnaire","Firebrand Grunt","Firebrand Invoker","Firebrand Darkweaver","Firebrand Pyromancer","Firebrand Dreadweaver"}, required = 22 },
                    { mobs = {"Spire Spider"},                                                                                                  required = 5 },
                    { mobs = {"Bloodaxe Veteran","Bloodaxe Warmonger","Bloodaxe Evoker","Bloodaxe Raider","Bloodaxe Summoner"},                 required = 14 },
                },
            },
            ubrs = {
                displayName = "Upper Blackrock Spire",
                shortName   = "UBRS",
                bosses = {
                    "Warchief Rend Blackhand",
                    "Gyth",
                    "The Beast",
                    "General Drakkisath",
                },
                trash = {
                    { mobs = {"Ragetalon Dragonspawn","Ragetalon Flamescale"},                       required = 10 },
                    -- Blackhand (1) and (2) collide on auto; load-time suffix handles it.
                    { mobs = {"Blackhand Dreadweaver","Blackhand Elite","Blackhand Veteran"},        required = 14 },
                    { mobs = {"Rage Talon Dragon Guard","Rage Talon Fire Tongue","Rage Talon Captain"}, required = 6 },
                    { mobs = {"Blackhand Thug","Blackhand Iron Guard","Blackhand Assassin"},         required = 6 },
                },
            },
        },
    },
    ["Scholomance"] = {
        displayName = "Scholomance",
        bosses = {
            "Rattlegore",
            "Instructor Malicia",
            "Doctor Theolen Krastinov",
            "Lorekeeper Polkelt",
            "The Ravenian",
            "Lord Alexei Barov",
            "Lady Illucia Barov",
            "Darkmaster Gandling",
        },
        trash = {
            { mobs = {"Risen Guard"},                                                          required = 5 },
            -- Scholo lower-case "Researcher/Acolyte/Neophyte" share no first word
            -- ("Spectral" vs "Scholomance"); manual name retained for clarity.
            { name = "Spectral / Acolyte",    mobs = {"Spectral Researcher","Scholomance Acolyte","Scholomance Neophyte"},     required = 4 },
            { name = "Dark Summoner / Necro", mobs = {"Scholomance Dark Summoner","Scholomance Necrolyte"},                    required = 6 },
            -- Note: keeping the typo "Scolomance Adept" verbatim from the
            -- epoglogs rules — Blizzard's mob name is misspelled in-game.
            { name = "Necromancer / Adept",   mobs = {"Scholomance Necromancer","Spectral Tutor","Scolomance Adept"},          required = 9 },
        },
    },
    ["Stratholme"] = {
        displayName = "Stratholme (variant: select below)",
        variants = {
            live = {
                displayName = "Stratholme — Live",
                shortName   = "Live",
                bosses = {
                    "Archivist Galford",
                    "Balnazzar",
                    "Timmy the Cruel",
                    "The Unforgiven",
                },
                trash = {
                    -- No common first word — manual name retained.
                    { name = "Skeletons/Cadavers", mobs = {"Skeletal Berserker","Mangled Cadaver","Skeletal Guardian","Ravaged Cadaver"}, required = 25 },
                    { mobs = {"Plague Ghoul"},                                                                required = 6 },
                    { mobs = {"Patchwerk Horror"},                                                            required = 1 },
                    -- Crimson melee/caster collide on auto; manual disambiguation kept
                    -- (semantic split is more useful than a "(1)/(2)" numeric suffix).
                    { name = "Crimson melee",      mobs = {"Crimson Gallant","Crimson Guardsman","Crimson Initiate","Crimson Conjurer"},  required = 14 },
                    { name = "Crimson caster",     mobs = {"Crimson Sorcerer","Crimson Battle Mage","Crimson Monk"},                      required = 6 },
                },
            },
            undead = {
                displayName = "Stratholme — Undead",
                shortName   = "Undead",
                bosses = {
                    "Magistrate Barthilas",
                    "Nerub'enkan",
                    "Maleki the Pallid",
                    "Baroness Anastari",
                    "Ramstein the Gorger",
                    "Lord Aurius Rivendare",
                },
                trash = {
                    { name = "Skeletons/Cadavers", mobs = {"Skeletal Berserker","Mangled Cadaver","Skeletal Guardian","Ravaged Cadaver"}, required = 8 },
                    { name = "Banshees",           mobs = {"Wailing Banshee","Shrieking Banshee"},                                         required = 6 },
                    -- Typo "Ghould Ravener" kept verbatim from epoglogs rules (Blizzard mob name).
                    -- No common first word -> manual "Ghouls" retained.
                    { name = "Ghouls",             mobs = {"Plague Ghoul","Ghould Ravener","Fleshflayer Ghoul"},                          required = 10 },
                    { mobs = {"Crypt Beast","Crypt Crawler"},                                                 required = 6 },
                    { mobs = {"Rockwing Screecher","Rockwing Gargoyle"},                                      required = 6 },
                    { mobs = {"Thuzadin Necromancer","Thuzadin Shadowcaster"},                                required = 6 },
                },
            },
        },
    },
    ["Onyxia's Lair"] = {
        -- v1.7.7: first raid in the supported set. Single boss, no trash
        -- buckets (Onyxia's whelps come in scripted waves rather than as
        -- countable adds). Auto-logs on entry via the raid-auto-log
        -- behavior wired in OnEnterDungeon.
        displayName = "Onyxia's Lair",
        bosses = {
            "Onyxia",
        },
    },
    ["Baradin Hold"] = {
        displayName = "Baradin Hold",
        bosses = {
            "Glagut",
            "Nazrasash",
            "Calypso",
            "Pirate Lord Blackstone",
        },
        trash = {
            { mobs = {"Baradin Sentry","Baradin Guard","Baradin Warden"},                  required = 8 },
            { mobs = {"Manifested Imp","Manifested Felhound","Manifested Infernal"},       required = 10 },
            { mobs = {"Improvised Cannon"},                                                 required = 2 },
            -- Three Blackstone buckets collide on auto; semantic disambiguation kept
            -- (more useful than numeric "(1)/(2)/(3)").
            { name = "Blackstone melee", mobs = {"Blackstone Pirate","Blackstone Gunner","Blackstone Reaver"},        required = 12 },
            { name = "Blackstone crew",  mobs = {"Blackstone Cook","Blackstone Cabin Boy"},                            required = 8 },
            { name = "Blackstone elite", mobs = {"Blackstone Sea Dog","Blackstone Bosun","Blackstone Surgeon"},        required = 14 },
        },
    },
}

-- Per-dungeon reverse lookup: boss name → variant key. Built once at
-- file load so OnBossKilled can O(1) auto-resolve the variant for
-- multi-variant dungeons. Single-variant dungeons get no entry here.
-- Example: BOSS_TO_VARIANT["Blackrock Spire"]["Highlord Omokk"] = "lbrs"
local BOSS_TO_VARIANT = {}
for dungeonKey, def in pairs(DUNGEONS) do
    if def.variants then
        BOSS_TO_VARIANT[dungeonKey] = {}
        for variantKey, variantDef in pairs(def.variants) do
            for _, bossName in ipairs(variantDef.bosses) do
                BOSS_TO_VARIANT[dungeonKey][bossName] = variantKey
            end
        end
    end
end

-- v1.7.6: auto-truncated bucket display name. For a bucket like
-- {mobs = {"Scarshield Legionnaire","Scarshield Acolyte",...}} the
-- common word-prefix across all mob names is "Scarshield" — that's
-- what we show in the UI. Single-mob buckets get the full name.
-- The bucket's optional manual `name` field still wins as an explicit
-- override (used for disambiguation when two buckets in the same
-- dungeon would auto-compute to the same prefix, e.g. Smolderthorn A
-- vs B in LBRS).
local function ComputeBucketName(bucket)
    if bucket.name then return bucket.name end
    local mobs = bucket.mobs
    if not mobs or #mobs == 0 then return "(unknown)" end
    if #mobs == 1 then return mobs[1] end

    -- Word-by-word longest common prefix across all mob names.
    -- Reset to first mob's words, then trim against each subsequent mob.
    local prefixWords = {}
    for w in mobs[1]:gmatch("%S+") do prefixWords[#prefixWords+1] = w end
    for i = 2, #mobs do
        local mobWords = {}
        for w in mobs[i]:gmatch("%S+") do mobWords[#mobWords+1] = w end
        local keep = 0
        for j = 1, math.min(#prefixWords, #mobWords) do
            if prefixWords[j] == mobWords[j] then keep = j else break end
        end
        -- Truncate prefixWords to `keep` entries
        for j = #prefixWords, keep + 1, -1 do prefixWords[j] = nil end
        if #prefixWords == 0 then break end
    end
    if #prefixWords == 0 then
        -- No common prefix at all (rare on these rosters) — fall back
        -- to first mob's name + "..." so the user has something to
        -- match against.
        return mobs[1] .. " ..."
    end
    return table.concat(prefixWords, " ")
end

-- Trash lookup: mob name → bucket index, per dungeon (and per variant
-- for multi-variant dungeons). Built once at load. Layout:
--   TRASH_LOOKUP[dungeonKey][variantKey or "_"][mobName] = bucketIndex
-- Where bucketIndex is the position in the trash array. The CLEU
-- handler uses this to O(1) classify each UNIT_DIED.
local TRASH_LOOKUP = {}
for dKey, dDef in pairs(DUNGEONS) do
    TRASH_LOOKUP[dKey] = {}
    if dDef.variants then
        for vKey, vDef in pairs(dDef.variants) do
            TRASH_LOOKUP[dKey][vKey] = {}
            if vDef.trash then
                for bIdx, bucket in ipairs(vDef.trash) do
                    for _, mob in ipairs(bucket.mobs) do
                        TRASH_LOOKUP[dKey][vKey][mob] = bIdx
                    end
                end
            end
        end
    elseif dDef.trash then
        TRASH_LOOKUP[dKey]["_"] = {}
        for bIdx, bucket in ipairs(dDef.trash) do
            for _, mob in ipairs(bucket.mobs) do
                TRASH_LOOKUP[dKey]["_"][mob] = bIdx
            end
        end
    end
end

-- v1.7.6: compute bucket.displayName for every trash bucket. Auto-derived
-- from the common word-prefix unless a manual bucket.name is set. After
-- the first pass, if two buckets in the same trash list ended up with
-- the same name (e.g. LBRS Smolderthorn A/B both auto-compute to
-- "Smolderthorn"), suffix them with " (1)" / " (2)" for disambiguation.
local function processTrashList(trashList)
    for _, bucket in ipairs(trashList) do
        bucket.displayName = ComputeBucketName(bucket)
    end
    -- Collision detection within this trash list
    local counts = {}
    for _, bucket in ipairs(trashList) do
        counts[bucket.displayName] = (counts[bucket.displayName] or 0) + 1
    end
    local seen = {}
    for _, bucket in ipairs(trashList) do
        if counts[bucket.displayName] > 1 then
            seen[bucket.displayName] = (seen[bucket.displayName] or 0) + 1
            bucket.displayName = bucket.displayName .. " (" .. seen[bucket.displayName] .. ")"
        end
    end
end
for _, dDef in pairs(DUNGEONS) do
    if dDef.variants then
        for _, vDef in pairs(dDef.variants) do
            if vDef.trash then processTrashList(vDef.trash) end
        end
    elseif dDef.trash then
        processTrashList(dDef.trash)
    end
end

-- ============================================================================
-- Module state
-- ============================================================================

local frame              = nil          -- the UI frame, lazily built
local currentDungeon     = nil          -- key into DUNGEONS, or nil if not in a tracked dungeon
local currentVariant     = nil          -- variant key (e.g. "lbrs", "ubrs", "live", "undead") for multi-variant dungeons; nil when not yet resolved
local dungeonStartTime   = nil          -- GetTime() when entered (used for boss kill timestamps)
local bossKillTimes      = {}           -- v1.7.5: bossName → elapsed seconds (from dungeon entry) when killed; nil = not killed
local trashKills         = {}           -- v1.7.5: bucketIdx → count of mobs from that bucket killed
local loggingActive      = false        -- mirror of LoggingCombat() state (set by us; the API getter exists but is checked at decision points only)
-- v1.7.11: track WHO owns the current /combatlog session. true if we
-- (raid auto-log) started it, false if user/another addon started it
-- or if nothing's logging. Used to decide whether to stop on raid exit.
-- Persisted to SavedVariables so /reload doesn't lose ownership.
local addonStartedLog    = false
-- v1.7.11: tracks the instance-type from the previous zone change so we
-- can detect "left a raid instance" transitions. Set by the event handler.
local wasInRaid          = false
local logStartTime       = nil          -- v1.7.5: GetTime() when StartLogging was called; nil = never started this run
local logEndTime         = nil          -- v1.7.5: GetTime() when StopLogging was called; used to freeze the timer at the stopped value
local promptShown        = false        -- per-run flag: have we already shown the Yes/No prompt?
local userDeclinedLog    = false        -- per-run: user clicked "No" on the prompt — don't re-ask this run

-- ============================================================================
-- Helpers
-- ============================================================================

-- Returns the dungeon key (matching DUNGEONS) for the current instance,
-- or nil if the player is not in a tracked dungeon. Multi-variant
-- dungeons (Blackrock Spire, Stratholme) return their shared name
-- even though we don't yet know the variant; that gets resolved
-- either by user button click or by first boss kill.
local function DetectDungeon()
    if not IsInInstance or not GetInstanceInfo then return nil end
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return nil end
    -- Both 5-mans (party) and raid (Baradin Hold) are accepted.
    if instanceType ~= "party" and instanceType ~= "raid" then return nil end
    local name = GetInstanceInfo()
    if name and DUNGEONS[name] then return name end
    return nil
end

-- Returns the list of bosses for the current dungeon. For multi-variant
-- dungeons, returns the resolved variant's roster, or a synthetic
-- combined "all variants" preview before resolution.
local function GetCurrentBosses()
    if not currentDungeon then return {} end
    local def = DUNGEONS[currentDungeon]
    if def.variants then
        if currentVariant then
            return def.variants[currentVariant].bosses
        else
            -- Variant undetected: return ALL variants' bosses concatenated
            -- so the UI can show them tagged + greyed until the user picks.
            local combined = {}
            for _, variantDef in pairs(def.variants) do
                for _, b in ipairs(variantDef.bosses) do combined[#combined+1] = b end
            end
            return combined
        end
    end
    return def.bosses
end

-- Returns the trash bucket list for the current dungeon (resolved
-- variant if multi-variant). Returns empty list if unresolved or no
-- trash defined.
local function GetCurrentTrash()
    if not currentDungeon then return {} end
    local def = DUNGEONS[currentDungeon]
    if def.variants then
        if not currentVariant then return {} end -- need variant resolved first
        return def.variants[currentVariant].trash or {}
    end
    return def.trash or {}
end

-- Returns the human-friendly name for the current dungeon, including
-- the resolved variant if known.
local function GetCurrentDisplayName()
    if not currentDungeon then return "(not in a dungeon)" end
    local def = DUNGEONS[currentDungeon]
    if def.variants then
        if currentVariant then return def.variants[currentVariant].displayName end
        return def.displayName -- "<Name> (variant: select below)"
    end
    return def.displayName
end

-- v1.7.11: query the actual /combatlog state via LoggingCombat() with
-- no args (returns boolean on WoW 3.3.5 and later). Wrapped in pcall
-- because in case some private-server fork changes the API to be
-- write-only, we don't want to crash — we just fall back to assuming
-- "off" (the conservative answer, makes us NOT claim ownership in
-- ambiguous cases).
local function IsLoggingActive()
    if not LoggingCombat then return false end
    local ok, isOn = pcall(LoggingCombat)
    if ok and type(isOn) == "boolean" then return isOn end
    return false
end

-- Format elapsed seconds as "M:SS" or "H:MM:SS" for longer runs.
local function FormatElapsed(seconds)
    seconds = floor(seconds)
    local h = floor(seconds / 3600)
    local m = floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

local function IsBossOfCurrent(destName)
    if not currentDungeon or not destName then return false end
    local def = DUNGEONS[currentDungeon]
    if def.variants then
        -- For multi-variant dungeons, ANY variant's boss counts as
        -- "boss of current" — we use the kill to auto-resolve the
        -- variant if it wasn't manually selected.
        local map = BOSS_TO_VARIANT[currentDungeon]
        return map and map[destName] ~= nil
    end
    for _, b in ipairs(def.bosses) do
        if b == destName then return true end
    end
    return false
end

-- ============================================================================
-- State transitions
-- ============================================================================

-- Forward declarations so functions defined earlier can call functions
-- defined further down. Without these, the names are looked up as
-- globals at call time and resolve to nil. Common Lua scoping gotcha.
--
-- Required for:
--   BuildFrame  -- called from OnEnterDungeon (lazy build on entry)
--                  and from _G.EpogArmoryDungeon_Toggle.
--   AnchorTopLeft -- called from OnEnterDungeon (re-anchor on entry).
--                    Bug fix v1.7.4: crashed PLAYER_ENTERING_WORLD
--                    with "attempt to call global 'AnchorTopLeft'".
local BuildFrame
local AnchorTopLeft

local function ResetRun()
    currentDungeon    = nil
    currentVariant         = nil
    dungeonStartTime  = nil
    bossKillTimes     = {}
    trashKills        = {}
    logStartTime      = nil
    logEndTime        = nil
    promptShown       = false
    userDeclinedLog   = false
    -- Don't touch loggingActive — that mirrors a global setting the
    -- user may have started themselves. Only StopLogging/StartLogging
    -- below modify it.
end

local function StartLogging()
    if LoggingCombat then LoggingCombat(true) end
    loggingActive = true
    -- v1.7.5: timer is tied to the log session, not dungeon entry.
    -- Reset the log start/end timestamps so the visible timer counts
    -- only logged seconds.
    logStartTime = GetTime()
    logEndTime   = nil
    print("|cffffaa44EpogArmory|r: |cff66ff66/combatlog started|r for this dungeon run.")
end

local function StopLogging()
    if LoggingCombat then LoggingCombat(false) end
    loggingActive = false
    -- v1.7.5: freeze the timer at the stopped value by capturing the
    -- end timestamp. UpdateUI shows (logEndTime - logStartTime) while
    -- not logging, so the timer doesn't keep counting after stop.
    logEndTime = GetTime()
    print("|cffffaa44EpogArmory|r: /combatlog stopped.")
end

local function OnEnterDungeon(dungeonKey)
    if currentDungeon == dungeonKey then return end -- already in this one

    local instanceType
    if IsInInstance then
        local _, t = IsInInstance()
        instanceType = t
    end

    -- v1.7.8: raid silent mode. Per user request: auto-start /combatlog
    -- in the background but DO NOT auto-open the frame and DO NOT start
    -- the visible timer. Rationale: raids are long, the frame doesn't
    -- need to be in the way for normal play. /combatlog runs invisibly;
    -- user can /epogarmory dungeon manually to see boss/logging status.
    --
    -- We DO still set currentDungeon + dungeonStartTime so:
    --   - boss kill CLEU tracking still works (Onyxia's death timestamp)
    --   - manual frame open shows useful info
    --   - re-entry guard (currentDungeon == dungeonKey) suppresses
    --     duplicate chat messages on /reload or run-back wipes
    -- We DON'T set logStartTime — that's the variable the frame timer
    -- watches, so the timer stays "--:--" in the raid case.
    if instanceType == "raid"
       and EpogArmoryDB and EpogArmoryDB.config
       and EpogArmoryDB.config.raidAutoLog
    then
        ResetRun()
        currentDungeon   = dungeonKey
        dungeonStartTime = GetTime() -- for boss kill timestamps only, not the visible timer
        promptShown      = true      -- suppress the Yes/No prompt if frame is opened manually
        if frame and frame:IsShown() then frame:Hide() end -- hide leftover 5-man frame

        -- v1.7.11: don't blindly call LoggingCombat(true) — check whether
        -- the log is already running (started by another addon, the user
        -- manually, OR by us in a previous session that /reload survived).
        -- The addonStartedLog flag is restored from SavedVariables at
        -- PLAYER_LOGIN, so on a /reload-into-raid it's still set if we
        -- owned the log before the reload.
        EpogArmoryDB.session = EpogArmoryDB.session or {}
        local alreadyOn = IsLoggingActive()
        if alreadyOn then
            loggingActive = true
            -- DON'T overwrite addonStartedLog here — it was restored from
            -- SV. true = our log from before /reload, false = someone
            -- else's. We just print the appropriate message.
            print("|cffffaa44=======================================|r")
            if addonStartedLog then
                print(string.format("|cffffd200EpogArmory|r |cff66ff66RAID AUTO-LOG RESUMED|r |cff888888(%s)|r", dungeonKey))
                print("  |cff888888/combatlog was already running from a previous session|r")
                print("  |cff888888(survived /reload). Will auto-stop on raid exit.|r")
            else
                print(string.format("|cffffd200EpogArmory|r |cffffd200raid detected|r |cff888888(%s)|r", dungeonKey))
                print("  |cff888888/combatlog was already active|r - leaving it as-is.")
                print("  |cff888888We won't stop it on raid exit (we didn't start it).|r")
            end
            print("|cffffaa44=======================================|r")
        else
            if LoggingCombat then LoggingCombat(true) end
            loggingActive = true
            addonStartedLog = true
            EpogArmoryDB.session.addonStartedLog = true
            local expectedFile = date("Logs/%Y-%m-%d-%H.%M.%S WoWCombatLog.txt")
            print("|cffffaa44=======================================|r")
            print(string.format("|cffffd200EpogArmory|r |cff66ff66RAID AUTO-LOG STARTED|r"))
            print(string.format("  Instance: |cffffd200%s|r", dungeonKey))
            print(string.format("  Log file: |cffaaaaaa%s|r", expectedFile))
            print("  |cff888888Will auto-stop when you leave the raid.|r")
            print("  |cff888888/epogarmory raidlog off  to disable for future raids|r")
            print("|cffffaa44=======================================|r")
        end
        return
    end

    -- 5-man / party instance path: original behavior. Frame opens
    -- automatically, Yes/No prompt asks about logging.
    ResetRun()
    currentDungeon   = dungeonKey
    dungeonStartTime = GetTime()
    -- Auto-open the frame so the user sees the prompt + roster. Build
    -- it lazily on first entry — BuildFrame defined further down so we
    -- assume it's available by the time OnEnterDungeon ever fires
    -- (PLAYER_ENTERING_WORLD comes well after file load).
    if not frame then frame = BuildFrame() end
    AnchorTopLeft(frame)
    if not frame:IsShown() then frame:Show() end
    frame.UpdateUI()
end

local function OnLeaveDungeon()
    -- Don't auto-stop logging on zone change — the user may have
    -- intentionally started /combatlog for cross-instance reasons.
    -- We only stop logging that WE started, and only via the Stop
    -- button in the frame.
    --
    -- Keep the frame visible briefly so the user can see the final
    -- state before resetting. (Actual reset happens on next dungeon
    -- entry, or on /epogarmory dungeon toggle.)
    if frame and frame.UpdateUI then frame.UpdateUI() end
end

local function OnBossKilled(bossName)
    if not currentDungeon then return end
    if bossKillTimes[bossName] then return end -- already recorded
    -- v1.7.5: record kill time as elapsed seconds since dungeon entry.
    -- Timestamps show next to boss names in the UI (e.g. "+ Lord Incendius (3:42)").
    bossKillTimes[bossName] = dungeonStartTime and (GetTime() - dungeonStartTime) or 0

    -- Multi-variant auto-resolution: if the user hasn't picked a variant
    -- yet, lock it in based on which variant this boss belongs to.
    local def = DUNGEONS[currentDungeon]
    if def.variants and not currentVariant then
        local map = BOSS_TO_VARIANT[currentDungeon]
        currentVariant = map and map[bossName]
        if currentVariant then
            -- v1.7.5: trash buckets are per-variant; reset on auto-resolve
            -- since any pre-resolution kills were counted against the wrong
            -- variant's bucket indices anyway.
            trashKills = {}
            print(string.format("|cffffaa44EpogArmory|r: variant auto-detected from boss kill: |cffffd200%s|r",
                def.variants[currentVariant].displayName))
        end
    end

    print(string.format("|cffffaa44EpogArmory|r: |cff66ff66boss down|r - %s", bossName))

    if frame and frame.UpdateUI then frame.UpdateUI() end
end

-- ============================================================================
-- UI frame
-- ============================================================================

-- Anchor helper mirrors the dummy frame's approach: pin to top-left
-- of UIParent on every Show so a panel rearrange doesn't lose the
-- frame off-screen. Assigned to the forward-declared local (see top
-- of state-transitions section).
AnchorTopLeft = function(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
end

-- Assign via expression rather than `function BuildFrame()` so the
-- forward-declared local is unambiguously the assignment target. The
-- bare-function-syntax should work in Lua 5.1 but has bit users on
-- WoW 3.3.5 before; explicit assignment removes the doubt.
BuildFrame = function()
    local f = CreateFrame("Frame", "EpogArmoryDungeonFrame", UIParent)
    -- v1.7.5: compact layout, smaller timer, trash bucket section.
    -- Total height tuned to fit 10 boss rows + 7 trash rows + headers
    -- + bottom button without scrolling.
    f:SetWidth(280); f:SetHeight(430)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText("EpogLogs - Dungeon Run")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Dungeon name (resolved + variant)
    f.dungeonLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.dungeonLabel:SetPoint("TOP", 0, -30)
    f.dungeonLabel:SetWidth(252)
    f.dungeonLabel:SetJustifyH("CENTER")

    -- Variant selection container — shown only when the current
    -- dungeon has variants AND no variant is yet resolved. Holds
    -- up to 2 buttons side-by-side (LBRS/UBRS or Live/Undead).
    f.variantContainer = CreateFrame("Frame", nil, f)
    f.variantContainer:SetPoint("TOP", 0, -52)
    f.variantContainer:SetWidth(252)
    f.variantContainer:SetHeight(24)
    f.variantContainer:Hide()
    f.variantBtns = {} -- variantKey -> button, populated lazily

    -- v1.7.5: Timer downsized from Huge (~32pt) to NormalLarge (~16pt)
    -- per user feedback. Still the visual focal point but doesn't
    -- dominate the frame any more.
    f.timerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.timerLabel:SetPoint("TOP", 0, -82)

    -- Run status (IN PROGRESS / COMPLETE / IDLE)
    f.statusBadge = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.statusBadge:SetPoint("TOP", f.timerLabel, "BOTTOM", 0, -2)

    -- Logging status row
    f.logStatusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.logStatusLabel:SetPoint("TOP", f.statusBadge, "BOTTOM", 0, -4)

    -- Prompt: compact version (height 38, was 54). Two buttons (Yes/No),
    -- a short prompt text. Non-secure — LoggingCombat is unprotected.
    f.prompt = CreateFrame("Frame", nil, f)
    f.prompt:SetPoint("TOPLEFT", 16, -148)
    f.prompt:SetPoint("TOPRIGHT", -16, -148)
    f.prompt:SetHeight(38)
    f.prompt:Hide()
    f.prompt.bg = f.prompt:CreateTexture(nil, "BACKGROUND")
    f.prompt.bg:SetAllPoints()
    f.prompt.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.prompt.bg:SetVertexColor(0.15, 0.15, 0.18, 0.7)
    f.prompt.text = f.prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.prompt.text:SetPoint("TOP", 0, -3)
    f.prompt.text:SetText("Start /combatlog for this run?")
    f.prompt.yes = CreateFrame("Button", nil, f.prompt, "UIPanelButtonTemplate")
    f.prompt.yes:SetSize(70, 18); f.prompt.yes:SetText("Yes")
    f.prompt.yes:SetPoint("BOTTOMLEFT", 24, 3)
    f.prompt.yes:SetScript("OnClick", function()
        StartLogging()
        f.prompt:Hide()
        if frame and frame.UpdateUI then frame.UpdateUI() end
    end)
    f.prompt.no = CreateFrame("Button", nil, f.prompt, "UIPanelButtonTemplate")
    f.prompt.no:SetSize(70, 18); f.prompt.no:SetText("No")
    f.prompt.no:SetPoint("BOTTOMRIGHT", -24, 3)
    f.prompt.no:SetScript("OnClick", function()
        userDeclinedLog = true
        f.prompt:Hide()
        if frame and frame.UpdateUI then frame.UpdateUI() end
    end)

    -- v1.9.2 fix: row pitch reduced 11 -> 10, plus the trash section
    -- now positions dynamically below the actual visible boss rows
    -- (instead of a static y reserved for the worst-case 10-boss
    -- preview). Frame height is also recomputed each tick to fit
    -- the visible content. Net effect: LBRS (6 bosses + 7 trash)
    -- now fits without the "Stop logging" button clipping the last
    -- trash row.
    f.BOSS_LABEL_Y   = -192
    f.BOSS_TOP       = -204
    f.BOSS_PITCH     = 10
    f.TRASH_PITCH    = 10
    f.SECTION_GAP    = 8   -- gap between last boss row and trash label
    f.LABEL_TO_ROW   = 12  -- gap from a section label to its first row
    f.FRAME_FOOTER   = 50  -- space reserved at bottom for the log toggle button

    f.bossesLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.bossesLabel:SetPoint("TOPLEFT", 14, f.BOSS_LABEL_Y)
    f.bossesLabel:SetText("|cffffd200Bosses|r")

    f.bossTexts = {}
    for i = 1, 10 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 18, f.BOSS_TOP - (i - 1) * f.BOSS_PITCH)
        fs:SetWidth(244)
        fs:SetJustifyH("LEFT")
        fs:Hide()
        f.bossTexts[i] = fs
    end

    -- Trash section. Labels + row positions get re-anchored every
    -- UpdateUI tick to sit right below the last visible boss row.
    -- Initial positions are placeholders; UpdateUI overwrites them.
    f.trashLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.trashLabel:SetPoint("TOPLEFT", 14, -310)
    f.trashLabel:SetText("|cffffd200Trash|r")

    f.trashTexts = {}
    for i = 1, 7 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 18, -322 - (i - 1) * f.TRASH_PITCH)
        fs:SetWidth(244)
        fs:SetJustifyH("LEFT")
        fs:Hide()
        f.trashTexts[i] = fs
    end

    -- Bottom action button: toggle log start/stop manually if the
    -- user wants to control it after dismissing the prompt.
    f.logToggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.logToggleBtn:SetSize(140, 22)
    f.logToggleBtn:SetPoint("BOTTOM", 0, 14)
    f.logToggleBtn:SetScript("OnClick", function()
        if loggingActive then
            StopLogging()
        else
            StartLogging()
        end
        if frame and frame.UpdateUI then frame.UpdateUI() end
    end)

    -- ----------------------------------------------------------------
    -- UpdateUI — full redraw, called from event handlers + tick.
    -- ----------------------------------------------------------------
    function f.UpdateUI()
        f.dungeonLabel:SetText(GetCurrentDisplayName())

        -- v1.7.5: timer is now driven by log start/end, not dungeon entry.
        --   logStartTime set + loggingActive: live count from start
        --   logStartTime set + !loggingActive: frozen at (logEndTime - logStartTime)
        --   logStartTime nil: show "--:--" (no log session this run)
        local timerText
        if logStartTime and loggingActive then
            timerText = FormatElapsed(GetTime() - logStartTime)
            f.timerLabel:SetTextColor(1, 1, 1)
        elseif logStartTime and logEndTime then
            timerText = FormatElapsed(logEndTime - logStartTime)
            f.timerLabel:SetTextColor(0.8, 0.8, 0.4) -- yellowish: frozen
        else
            timerText = "--:--"
            f.timerLabel:SetTextColor(0.5, 0.5, 0.5)
        end
        f.timerLabel:SetText(timerText)

        -- Status badge
        if currentDungeon then
            local bosses = GetCurrentBosses()
            local killed = 0
            for _, b in ipairs(bosses) do
                if bossKillTimes[b] then killed = killed + 1 end
            end
            local total = #bosses
            if total > 0 and killed == total then
                f.statusBadge:SetText("|cff66ff66COMPLETE|r")
            else
                f.statusBadge:SetText(string.format("|cffffd200IN PROGRESS|r |cff888888(%d / %d bosses)|r",
                    killed, total))
            end
        else
            f.statusBadge:SetText("|cff888888IDLE|r")
        end

        -- Logging status
        if loggingActive then
            f.logStatusLabel:SetText("Logging: |cff66ff66ACTIVE|r")
        else
            f.logStatusLabel:SetText("Logging: |cffff6666OFF|r")
        end

        -- Prompt visibility. v1.9.2 fix: previously the gate only
        -- evaluated `not loggingActive` AT FIRST DISPLAY. Once
        -- promptShown flipped to true, the prompt stayed visible
        -- even if logging later became active (e.g. user clicked
        -- the bottom Start-logging button, or another addon
        -- turned /combatlog on). Now: hide unconditionally when
        -- logging is active or user declined; only show on the
        -- first eligible tick.
        if not currentDungeon then
            f.prompt:Hide()
        elseif loggingActive or userDeclinedLog then
            f.prompt:Hide()
        elseif not promptShown then
            f.prompt:Show()
            promptShown = true
        end

        -- Variant selection buttons (v1.7.4). Shown only when the
        -- current dungeon has variants AND the variant isn't yet
        -- resolved. Lazily creates one button per variant the first
        -- time we see this dungeon. Buttons are positioned within
        -- variantContainer (252px wide, 24px tall) — for 2 variants,
        -- each gets ~120px wide centered side-by-side.
        do
            local def = currentDungeon and DUNGEONS[currentDungeon] or nil
            if def and def.variants and not currentVariant then
                -- Build button per variant if not yet created. We'd build
                -- once per dungeon, so we check by key. This is robust
                -- against the user re-entering a different multi-variant
                -- dungeon (Strat -> BRS) — different keys, fresh buttons.
                local variantKeys = {}
                for vk in pairs(def.variants) do variantKeys[#variantKeys+1] = vk end
                table.sort(variantKeys) -- deterministic order
                local n = #variantKeys
                local btnWidth = math.floor((252 - 8 * (n - 1)) / n) -- 8px gap between buttons
                for i, vk in ipairs(variantKeys) do
                    local btn = f.variantBtns[vk]
                    if not btn then
                        btn = CreateFrame("Button", nil, f.variantContainer, "UIPanelButtonTemplate")
                        btn:SetHeight(22)
                        btn:SetScript("OnClick", function(self)
                            currentVariant = self._variantKey
                            -- v1.7.5: trash buckets are per-variant; reset counters
                            -- on variant pick so leftover counts from one side don't
                            -- pollute the other.
                            trashKills = {}
                            -- Look up def fresh at click time rather than from the
                            -- captured closure, since the user might re-enter a
                            -- different multi-variant dungeon between button creation
                            -- and click.
                            local dDef = currentDungeon and DUNGEONS[currentDungeon]
                            local vDef = dDef and dDef.variants and dDef.variants[currentVariant]
                            print(string.format("|cffffaa44EpogArmory|r: variant selected: |cffffd200%s|r",
                                vDef and vDef.displayName or currentVariant))
                            if frame and frame.UpdateUI then frame.UpdateUI() end
                        end)
                        f.variantBtns[vk] = btn
                    end
                    btn._variantKey = vk
                    btn:SetWidth(btnWidth)
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", f.variantContainer, "LEFT",
                        (i - 1) * (btnWidth + 8), 0)
                    btn:SetText(def.variants[vk].shortName or vk)
                    btn:Show()
                end
                -- Hide any leftover buttons from a previous dungeon's
                -- variants that aren't in the current set.
                for vk, btn in pairs(f.variantBtns) do
                    if not def.variants[vk] then btn:Hide() end
                end
                f.variantContainer:Show()
            else
                f.variantContainer:Hide()
            end
        end

        -- Boss list. Build the text per-row with +/- markers.
        local bosses = GetCurrentBosses()
        local def = DUNGEONS[currentDungeon] -- may be nil if no dungeon
        local variantMap = currentDungeon and BOSS_TO_VARIANT[currentDungeon] or nil
        for i = 1, #f.bossTexts do
            local row = f.bossTexts[i]
            local bossName = bosses[i]
            if bossName then
                local variantTag = ""
                if def and def.variants and not currentVariant and variantMap then
                    -- Annotate which variant each boss belongs to since
                    -- both lists are mixed in pre-resolution.
                    local v = variantMap[bossName]
                    if v then
                        local short = def.variants[v].shortName or v
                        variantTag = string.format(" |cff888888(%s)|r", short)
                    end
                end
                local killT = bossKillTimes[bossName]
                if killT then
                    -- v1.7.5: append kill timestamp "(M:SS)" relative to dungeon entry
                    local m = floor(killT / 60)
                    local s = floor(killT % 60)
                    row:SetText(string.format("|cff66ff66+|r %s%s |cff888888(%d:%02d)|r",
                        bossName, variantTag, m, s))
                else
                    row:SetText(string.format("|cffaaaaaa-|r |cff888888%s%s|r", bossName, variantTag))
                end
                row:Show()
            else
                row:Hide()
            end
        end

        -- v1.7.5: trash bucket rendering. Each row shows
        -- "<bucket name> X/Y" where X=kills, Y=required. Color cues:
        --   red    X==0
        --   yellow 0<X<Y
        --   green  X>=Y
        -- Trash header shows aggregate "(N/M)" count of buckets met.
        do
            local trash = GetCurrentTrash()
            local buckets, complete = #trash, 0
            for i, bucket in ipairs(trash) do
                if (trashKills[i] or 0) >= bucket.required then
                    complete = complete + 1
                end
            end
            local pickVariantFirst = currentDungeon
                and DUNGEONS[currentDungeon].variants
                and not currentVariant
            if pickVariantFirst then
                f.trashLabel:SetText("|cffffd200Trash|r |cff888888(pick variant first)|r")
            elseif buckets == 0 then
                f.trashLabel:SetText("|cffffd200Trash|r |cff888888(none)|r")
            else
                f.trashLabel:SetText(string.format("|cffffd200Trash|r |cff888888(%d / %d buckets)|r",
                    complete, buckets))
            end
            for i = 1, #f.trashTexts do
                local row = f.trashTexts[i]
                local bucket = trash[i]
                if bucket and not pickVariantFirst then
                    local count = trashKills[i] or 0
                    local color
                    if count >= bucket.required then
                        color = "|cff66ff66" -- green
                    elseif count > 0 then
                        color = "|cffffd200" -- yellow
                    else
                        color = "|cffff6666" -- red
                    end
                    row:SetText(string.format("%s%d/%d|r |cffcccccc%s|r",
                        color, count, bucket.required, bucket.displayName))
                    row:Show()
                else
                    row:Hide()
                end
            end

            -- v1.9.2: dynamic repositioning. Sit the trash label + rows
            -- right below the actual visible boss list (instead of at a
            -- fixed y reserved for the worst-case 10-boss preview), and
            -- resize the frame so the bottom button doesn't overlap the
            -- last trash row. Without this, LBRS (6 bosses + 7 trash)
            -- had ~40px of empty space between bosses and trash, AND
            -- the "Stop logging" button clipped the last trash row.
            local visibleBosses = math.min(#bosses, #f.bossTexts)
            local visibleTrash = pickVariantFirst and 0 or math.min(buckets, #f.trashTexts)

            local trashLabelY = f.BOSS_TOP - visibleBosses * f.BOSS_PITCH - f.SECTION_GAP
            f.trashLabel:ClearAllPoints()
            f.trashLabel:SetPoint("TOPLEFT", 14, trashLabelY)

            local trashRowsTopY = trashLabelY - f.LABEL_TO_ROW
            for i = 1, #f.trashTexts do
                local row = f.trashTexts[i]
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 18, trashRowsTopY - (i - 1) * f.TRASH_PITCH)
            end

            -- Compute desired frame height. Bottom of trash section
            -- (label+rows or just label if no trash) plus footer space
            -- for the log toggle button. SetHeight only if changed by
            -- more than 1px to avoid flicker.
            local trashBottomY
            if visibleTrash > 0 then
                trashBottomY = trashRowsTopY - visibleTrash * f.TRASH_PITCH
            else
                trashBottomY = trashLabelY - f.LABEL_TO_ROW
            end
            local desiredHeight = -trashBottomY + f.FRAME_FOOTER
            -- Clamp to a sensible minimum so the header section always fits
            if desiredHeight < 270 then desiredHeight = 270 end
            if math.abs(desiredHeight - f:GetHeight()) > 1 then
                f:SetHeight(desiredHeight)
            end
        end

        -- Action button label reflects current logging state
        if loggingActive then
            f.logToggleBtn:SetText("Stop logging")
        else
            f.logToggleBtn:SetText("Start logging")
        end
    end

    -- Tick for the live timer. 0.5s is enough granularity for a
    -- minute-scale timer and is light on CPU.
    local lastTick = 0
    f:SetScript("OnUpdate", function(self, e)
        lastTick = lastTick + (e or 0)
        if lastTick < 0.5 then return end
        lastTick = 0
        if currentDungeon then f.UpdateUI() end
    end)

    return f
end

-- ============================================================================
-- Public functions
-- ============================================================================

_G.EpogArmoryDungeon_Toggle = function()
    if not frame then frame = BuildFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        AnchorTopLeft(frame)
        frame:Show()
        frame.UpdateUI()
    end
end

-- Claude v1.7.3: diagnostic dump for when the auto-open isn't firing.
-- Tells us exactly what GetInstanceInfo returns, whether the name is
-- in the DUNGEONS table, and current module state. Wired to
-- /epogarmory dungeondebug.
_G.EpogArmoryDungeon_Debug = function()
    print("|cffffaa44EpogArmory|r [dungeon-debug] dumping detection state:")
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        print(string.format("  IsInInstance: %s, type: %s",
            tostring(inInstance), tostring(instanceType)))
    else
        print("  IsInInstance: API not available")
    end
    if GetInstanceInfo then
        local name, instanceType, difficulty, difficultyName, maxPlayers = GetInstanceInfo()
        print(string.format("  GetInstanceInfo: name='%s' type='%s' difficulty=%s difficultyName='%s' maxPlayers=%s",
            tostring(name), tostring(instanceType), tostring(difficulty),
            tostring(difficultyName), tostring(maxPlayers)))
        if name and DUNGEONS[name] then
            print(string.format("  |cff66ff66MATCH|r DUNGEONS['%s'] found", name))
        elseif name then
            print(string.format("  |cffff6666NO MATCH|r in DUNGEONS table for name='%s'", name))
            print("  known keys: Blackrock Depths, Lower Blackrock Spire, Upper Blackrock Spire, Scholomance, Stratholme, Baradin Hold")
        end
    else
        print("  GetInstanceInfo: API not available")
    end
    print(string.format("  module state: currentDungeon=%s, currentVariant=%s, dungeonStartTime=%s",
        tostring(currentDungeon), tostring(currentVariant), tostring(dungeonStartTime)))
    print(string.format("  frame: built=%s, shown=%s",
        tostring(frame ~= nil), tostring(frame and frame:IsShown())))
    print(string.format("  logging: active=%s, logStartTime=%s, logEndTime=%s, promptShown=%s, userDeclined=%s",
        tostring(loggingActive), tostring(logStartTime), tostring(logEndTime),
        tostring(promptShown), tostring(userDeclinedLog)))
    do
        local nBosses, nTrash = 0, 0
        for _ in pairs(bossKillTimes) do nBosses = nBosses + 1 end
        for _ in pairs(trashKills) do nTrash = nTrash + 1 end
        print(string.format("  kills: %d bosses recorded, %d trash buckets touched",
            nBosses, nTrash))
    end
    print(string.format("  GetRealZoneText='%s', GetSubZoneText='%s'",
        tostring(GetRealZoneText and GetRealZoneText() or "?"),
        tostring(GetSubZoneText and GetSubZoneText() or "?")))
end

-- ============================================================================
-- Event wiring
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- v1.7.7: default raid auto-log to ON for new users. Existing
        -- users who explicitly disabled it (set to false) keep their
        -- preference. Only inits when the key is nil.
        EpogArmoryDB = EpogArmoryDB or {}
        EpogArmoryDB.config = EpogArmoryDB.config or {}
        if EpogArmoryDB.config.raidAutoLog == nil then
            EpogArmoryDB.config.raidAutoLog = true
        end
        -- v1.7.11: restore the addonStartedLog claim across /reload via
        -- SavedVariables. Sanity-check against the actual API state:
        -- if /combatlog is off, our flag is irrelevant (clear it).
        EpogArmoryDB.session = EpogArmoryDB.session or {}
        addonStartedLog = EpogArmoryDB.session.addonStartedLog and true or false
        if addonStartedLog and not IsLoggingActive() then
            addonStartedLog = false
            EpogArmoryDB.session.addonStartedLog = false
        end
        loggingActive = IsLoggingActive() -- best-effort sync
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
       or event == "ZONE_CHANGED_NEW_AREA"
    then
        -- v1.7.11: detect "left a raid instance" transitions. Compare
        -- previous wasInRaid flag to the current instance type. If we
        -- were in a raid and now aren't, stop the log if WE started it
        -- (addonStartedLog). Done BEFORE the dungeon-detect branch so
        -- the order is: detect-leave-raid first, then maybe enter-new.
        local _, currentInstanceType = nil, nil
        if IsInInstance then
            _, currentInstanceType = IsInInstance()
        end
        local nowInRaid = (currentInstanceType == "raid")
        if wasInRaid and not nowInRaid and addonStartedLog then
            -- We own the running /combatlog and have just exited the
            -- raid. Stop it.
            if LoggingCombat then LoggingCombat(false) end
            loggingActive = false
            addonStartedLog = false
            EpogArmoryDB = EpogArmoryDB or {}
            EpogArmoryDB.session = EpogArmoryDB.session or {}
            EpogArmoryDB.session.addonStartedLog = false
            print("|cffffaa44=======================================|r")
            print("|cffffd200EpogArmory|r |cffff9966RAID AUTO-LOG STOPPED|r")
            print("  |cff888888Left raid instance - /combatlog closed.|r")
            print("|cffffaa44=======================================|r")
        end
        wasInRaid = nowInRaid

        local detected = DetectDungeon()
        if detected then
            if currentDungeon ~= detected then
                OnEnterDungeon(detected)
            end
        else
            -- Left the tracked dungeon; clear state lazily so the
            -- frame retains the last view until user dismisses or
            -- enters a new dungeon.
            if currentDungeon then OnLeaveDungeon() end
        end
        if frame and frame:IsShown() then frame.UpdateUI() end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not currentDungeon then return end
        local _, subevent, _, _, _, _, destName = ...
        if subevent ~= "UNIT_DIED" or not destName then return end
        if IsBossOfCurrent(destName) then
            OnBossKilled(destName)
            return
        end
        -- v1.7.5: trash bucket tracking. Lookup whether this mob name
        -- belongs to a trash bucket for the current dungeon (and
        -- variant, if applicable). If so, increment its counter.
        local dungeonLookup = TRASH_LOOKUP[currentDungeon]
        if dungeonLookup then
            local variantMap = dungeonLookup[currentVariant or "_"]
            if variantMap then
                local bucketIdx = variantMap[destName]
                if bucketIdx then
                    trashKills[bucketIdx] = (trashKills[bucketIdx] or 0) + 1
                    if frame and frame.UpdateUI then frame.UpdateUI() end
                end
            end
        end
        return
    end
end)
