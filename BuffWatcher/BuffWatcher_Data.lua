-- BuffWatcher_Data.lua
-- Claude: role definitions, spec-to-role mapping, default per-role buff entries, class colours.
-- Everything stored in the BW table to avoid global namespace clobbering.

BW = BW or {}

-- ── Roles ────────────────────────────────────────────────────────────────────

BW.ROLES = { "Tank", "Healer", "Melee", "Ranged" } -- Claude: ordered for UI display

-- ── Spec → Role mapping ──────────────────────────────────────────────────────
-- Claude: each class has 3 talent tabs; the tab with the most points = the spec.
-- Index 1/2/3 = talent tab 1/2/3 → role name.
-- Project Epoch: vanilla classes with TBC talents on 3.3.5 client.

BW.SPEC_ROLE_MAP = {
    WARRIOR = { "Melee",   "Melee",   "Tank"   }, -- Arms, Fury, Prot
    PALADIN = { "Healer",  "Tank",    "Melee"  }, -- Holy, Prot, Ret
    HUNTER  = { "Ranged",  "Ranged",  "Ranged" }, -- BM, MM, Survival
    ROGUE   = { "Melee",   "Melee",   "Melee"  }, -- Assassination, Combat, Subtlety
    PRIEST  = { "Healer",  "Healer",  "Ranged" }, -- Disc, Holy, Shadow
    SHAMAN  = { "Ranged",  "Melee",   "Healer" }, -- Ele, Enh, Resto
    MAGE    = { "Ranged",  "Ranged",  "Ranged" }, -- Arcane, Fire, Frost
    WARLOCK = { "Ranged",  "Ranged",  "Ranged" }, -- Affliction, Demo, Destruction
    DRUID   = { "Ranged",  "Melee",   "Healer" }, -- Balance, Feral, Resto
}

-- Claude: fallback when inspect fails or times out — best-guess role from class alone
BW.CLASS_DEFAULT_ROLE = {
    WARRIOR = "Melee",  PALADIN = "Melee",  HUNTER  = "Ranged",
    ROGUE   = "Melee",  PRIEST  = "Healer", SHAMAN  = "Melee",
    MAGE    = "Ranged", WARLOCK = "Ranged", DRUID   = "Melee",
}

-- ── Default buff entries per role ────────────────────────────────────────────
-- Claude: format: { buff = "WoW buff name", label = "output label", enabled = true/false }
-- Entries sharing the same label are OR-grouped: any one match satisfies the requirement.

local SHARED_ENTRIES = { -- Claude: common to all roles
    { buff = "Songflower Serenade",              label = "Songflower",  enabled = true  },
    { buff = "Rallying Cry of the Dragonslayer", label = "Onyxia",      enabled = true  },
    { buff = "Spirit of Zandalar",               label = "Zandalar",    enabled = true  },
    { buff = "Warchief's Blessing",              label = "Warchief",    enabled = false },
    { buff = "Mol'dar's Moxie",                  label = "DMT Stam",    enabled = true  },
    { buff = "Fengus' Ferocity",                 label = "DMT AP",      enabled = true  },
    { buff = "Slip'kik's Savvy",                 label = "DMT Crit",    enabled = true  },
    { buff = "Well Fed",                         label = "Well Fed",    enabled = true  },
}

-- Claude: helper to merge shared + role-specific entries into one list
local function MergeEntries(roleSpecific)
    local out = {}
    for _, e in ipairs(SHARED_ENTRIES) do
        tinsert(out, { buff = e.buff, label = e.label, enabled = e.enabled })
    end
    for _, e in ipairs(roleSpecific) do
        tinsert(out, { buff = e.buff, label = e.label, enabled = e.enabled })
    end
    return out
end

BW.DefaultRoleEntries = {
    Tank = MergeEntries({
        -- Claude: tank flasks
        { buff = "Flask of Fortification",           label = "Flask",           enabled = true },
        { buff = "Flask of the Titans",              label = "Flask",           enabled = true },
        { buff = "Flask of Chromatic Resistance",    label = "Flask",           enabled = true },
        { buff = "Flask of Chromatic Wonder",        label = "Flask",           enabled = true },
        -- Claude: tank battle elixirs
        { buff = "Elixir of Major Agility",          label = "Battle Elixir",   enabled = true },
        { buff = "Elixir of Mastery",                label = "Battle Elixir",   enabled = true },
        -- Claude: tank guardian elixirs
        { buff = "Elixir of Major Fortitude",        label = "Guardian Elixir", enabled = true },
        { buff = "Elixir of Superior Defense",       label = "Guardian Elixir", enabled = true },
        { buff = "Elixir of Ironskin",               label = "Guardian Elixir", enabled = true },
    }),

    Healer = MergeEntries({
        -- Claude: healer flasks
        { buff = "Flask of Mighty Restoration",      label = "Flask",           enabled = true },
        { buff = "Flask of Distilled Wisdom",        label = "Flask",           enabled = true },
        { buff = "Flask of Chromatic Wonder",        label = "Flask",           enabled = true },
        -- Claude: healer battle elixirs
        { buff = "Elixir of Healing Power",          label = "Battle Elixir",   enabled = true },
        { buff = "Elixir of Mastery",                label = "Battle Elixir",   enabled = true },
        -- Claude: healer guardian elixirs
        { buff = "Elixir of Draenic Wisdom",         label = "Guardian Elixir", enabled = true },
        { buff = "Elixir of Major Mageblood",        label = "Guardian Elixir", enabled = true },
        { buff = "Elixir of Major Fortitude",        label = "Guardian Elixir", enabled = true },
    }),

    Melee = MergeEntries({
        -- Claude: melee flasks
        { buff = "Flask of Relentless Assault",      label = "Flask",           enabled = true },
        { buff = "Flask of the Titans",              label = "Flask",           enabled = true },
        { buff = "Flask of Chromatic Wonder",        label = "Flask",           enabled = true },
        -- Claude: melee battle elixirs
        { buff = "Elixir of Major Agility",          label = "Battle Elixir",   enabled = true },
        { buff = "Elixir of Major Strength",         label = "Battle Elixir",   enabled = true },
        { buff = "Onslaught Elixir",                 label = "Battle Elixir",   enabled = true },
        { buff = "Elixir of Demonslaying",           label = "Battle Elixir",   enabled = true },
        -- Claude: melee guardian elixirs
        { buff = "Elixir of Major Fortitude",        label = "Guardian Elixir", enabled = true },
        { buff = "Elixir of Draenic Wisdom",         label = "Guardian Elixir", enabled = true },
    }),

    Ranged = MergeEntries({
        -- Claude: ranged/caster flasks
        { buff = "Flask of Pure Death",              label = "Flask",           enabled = true },
        { buff = "Flask of Supreme Power",           label = "Flask",           enabled = true },
        { buff = "Flask of Blinding Light",          label = "Flask",           enabled = true },
        { buff = "Flask of Chromatic Wonder",        label = "Flask",           enabled = true },
        -- Claude: ranged battle elixirs
        { buff = "Elixir of Major Firepower",        label = "Battle Elixir",   enabled = true },
        { buff = "Elixir of Major Shadow Power",     label = "Battle Elixir",   enabled = true },
        { buff = "Elixir of Major Frost Power",      label = "Battle Elixir",   enabled = true },
        { buff = "Elixir of Mastery",                label = "Battle Elixir",   enabled = true },
        -- Claude: ranged guardian elixirs
        { buff = "Elixir of Draenic Wisdom",         label = "Guardian Elixir", enabled = true },
        { buff = "Elixir of Major Mageblood",        label = "Guardian Elixir", enabled = true },
        { buff = "Elixir of Major Fortitude",        label = "Guardian Elixir", enabled = true },
    }),
}

-- Claude: class colours referenced at runtime in RebuildTable and Export
BW.ClassColors = {
    WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372",
    ROGUE   = "FFF468", PRIEST  = "FFFFFF", MAGE   = "3FC7EB",
    WARLOCK = "8788EE", DRUID   = "FF7C0A", SHAMAN = "0070DE",
}

-- Claude: role colours for status display
BW.RoleColors = {
    Tank   = "5599FF",
    Healer = "44DD44",
    Melee  = "FF6644",
    Ranged = "FFAA44",
}
