-- BuffWatcher_Data.lua
-- Default check entries and class colour table.
-- Claude: everything stored in the BW table to avoid global namespace clobbering.

BW = BW or {}

-- ── Default entries ───────────────────────────────────────────────────────────
-- Seeded into BuffWatcherDB.entries on first login (or when Reset is clicked).
--
-- Format: { buff = "WoW buff name", label = "output label", enabled = true/false }
--
-- Entries that share the same label are grouped:
--   if ANY matching buff is found on the unit, the whole label is satisfied.
--
-- Example: three "Battle Elixir" rows — having any one is enough.

BW.DefaultEntries = {
    -- ── World buffs ───────────────────────────────────────────────────────────
    { buff = "Songflower Serenade",                  label = "Songflower",      enabled = true  },
    { buff = "Rallying Cry of the Dragonslayer",      label = "Onyxia",          enabled = true  },
    { buff = "Spirit of Zandalar",                   label = "Zandalar",        enabled = true  },
    { buff = "Warchief's Blessing",                  label = "Warchief",        enabled = false },
    { buff = "Mol'dar's Moxie",                      label = "DMT Stam",        enabled = true  },
    { buff = "Fengus' Ferocity",                     label = "DMT AP",          enabled = true  },
    { buff = "Slip'kik's Savvy",                     label = "DMT Crit",        enabled = true  },
    -- ── TBC Flasks ────────────────────────────────────────────────────────────
    { buff = "Flask of Chromatic Wonder",            label = "Flask",           enabled = true  },
    { buff = "Flask of Fortification",               label = "Flask",           enabled = true  },
    { buff = "Flask of Relentless Assault",          label = "Flask",           enabled = true  },
    { buff = "Flask of Mighty Restoration",          label = "Flask",           enabled = true  },
    -- ── TBC Battle Elixirs ────────────────────────────────────────────────────
    { buff = "Elixir of Major Agility",              label = "Battle Elixir",   enabled = true  },
    { buff = "Onslaught Elixir",                     label = "Battle Elixir",   enabled = true  },
    { buff = "Elixir of Major Strength",             label = "Battle Elixir",   enabled = true  },
    { buff = "Elixir of Mastery",                    label = "Battle Elixir",   enabled = true  },
    { buff = "Elixir of Major Shadow Power",         label = "Battle Elixir",   enabled = true  },
    { buff = "Elixir of Major Firepower",            label = "Battle Elixir",   enabled = true  },
    { buff = "Elixir of Major Frost Power",          label = "Battle Elixir",   enabled = true  },
    -- ── TBC Guardian Elixirs ──────────────────────────────────────────────────
    { buff = "Elixir of Major Fortitude",            label = "Guardian Elixir", enabled = true  },
    { buff = "Elixir of Draenic Wisdom",             label = "Guardian Elixir", enabled = true  },
    { buff = "Elixir of Major Mageblood",            label = "Guardian Elixir", enabled = true  },
    { buff = "Elixir of Ironskin",                   label = "Guardian Elixir", enabled = true  },
    -- ── Well Fed ──────────────────────────────────────────────────────────────
    { buff = "Well Fed",                             label = "Well Fed",        enabled = true  },
}

-- Claude: class colours referenced at runtime in RebuildTable
BW.ClassColors = {
    WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372",
    ROGUE   = "FFF468", PRIEST  = "FFFFFF", MAGE   = "3FC7EB",
    WARLOCK = "8788EE", DRUID   = "FF7C0A", SHAMAN = "0070DE",
    DEATHKNIGHT = "C41E3A",
}
