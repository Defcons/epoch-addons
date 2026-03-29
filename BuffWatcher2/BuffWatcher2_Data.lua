-- BuffWatcher2_Data.lua
-- Claude: default check entries and class colour table.
-- Everything stored in the BW2 table to avoid global namespace clobbering.

BW2 = BW2 or {}

-- ── Default entries ───────────────────────────────────────────────────────────
-- Claude: seeded into BuffWatcher2DB.entries on first login or Reset.
--
-- Format: { buff = "WoW buff name", label = "output label", enabled = true/false }
--
-- Entries that share the same label are grouped:
--   if ANY matching buff is found on the unit, the whole label is satisfied.

BW2.DefaultEntries = {
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

-- Claude: class colours referenced at runtime in RebuildTable and Export
BW2.ClassColors = {
    WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372",
    ROGUE   = "FFF468", PRIEST  = "FFFFFF", MAGE   = "3FC7EB",
    WARLOCK = "8788EE", DRUID   = "FF7C0A", SHAMAN = "0070DE",
    DEATHKNIGHT = "C41E3A",
}
