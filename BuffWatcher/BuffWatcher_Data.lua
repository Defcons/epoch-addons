-- BuffWatcher_Data.lua
-- Defines every possible buff/consume check per class.
-- Claude: BW must exist before BuffWatcher_Config.lua loads (it runs next in the TOC)
BW = BW or {}

--
-- Format per entry:
--   { id = "unique_key", label = "Short Name", buffs = { "Buff Name 1", ... } }
--   Any one of the listed buff names counts as "present".
--   'id' is the SavedVariables key — keep it stable across versions.
--
-- To add a new check: add an entry to worldbuffs or consumes.
-- To rename a display label: change 'label' only, never 'id'.
-- flask: any one of these counts as "has flask" (global, shown as a separate column).

BW_Data = {

    flasks = {
        "Flask of the Titans",
        "Distilled Wisdom",
        "Supreme Power",
    },

    -- ── Warrior ──────────────────────────────────────────────────────────
    WARRIOR = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "warchief",   label = "Warchief",    buffs = { "Warchief's Blessing" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_ap",     label = "DMT AP",      buffs = { "Fengus' Ferocity" } },
        },
        consumes = {
            { id = "mongoose",  label = "Mongoose",     buffs = { "Elixir of the Mongoose" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Rage of Ages", "Strike of the Scorpok",
                "Darnassus Gift Collection", "Orgrimmar Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "ap",        label = "AP",           buffs = { "Juju Might", "Winterfall Firewater" } },
            { id = "strength",  label = "Strength",     buffs = { "Juju Power", "Elixir of the Giants" } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Blessed Sunfruit", "Increased Agility" } },
        },
    },

    -- ── Rogue ────────────────────────────────────────────────────────────
    ROGUE = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "warchief",   label = "Warchief",    buffs = { "Warchief's Blessing" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_ap",     label = "DMT AP",      buffs = { "Fengus' Ferocity" } },
        },
        consumes = {
            { id = "mongoose",  label = "Mongoose",     buffs = { "Elixir of the Mongoose" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Rage of Ages", "Strike of the Scorpok",
                "Darnassus Gift Collection", "Orgrimmar Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "ap",        label = "AP",           buffs = { "Juju Might", "Winterfall Firewater" } },
            { id = "strength",  label = "Strength",     buffs = { "Juju Power", "Elixir of the Giants" } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Blessed Sunfruit", "Increased Agility" } },
        },
    },

    -- ── Hunter ───────────────────────────────────────────────────────────
    HUNTER = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_ap",     label = "DMT AP",      buffs = { "Fengus' Ferocity" } },
            { id = "dmt_crit",   label = "DMT Crit",    buffs = { "Slip'kik's Savvy" } },
        },
        consumes = {
            { id = "mongoose",  label = "Mongoose",     buffs = { "Elixir of the Mongoose" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Rage of Ages", "Strike of the Scorpok",
                "Darnassus Gift Collection", "Orgrimmar Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Increased Agility", "Mana Regeneration" } },
        },
    },

    -- ── Paladin ──────────────────────────────────────────────────────────
    PALADIN = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_crit",   label = "DMT Crit",    buffs = { "Slip'kik's Savvy" } },
        },
        consumes = {
            { id = "mageblood", label = "Mageblood",   buffs = { "Mana Regeneration" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" } },
        },
    },

    -- ── Priest ───────────────────────────────────────────────────────────
    PRIEST = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_crit",   label = "DMT Crit",    buffs = { "Slip'kik's Savvy" } },
        },
        consumes = {
            { id = "mageblood", label = "Mageblood",   buffs = { "Mana Regeneration" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" } },
        },
    },

    -- ── Mage ─────────────────────────────────────────────────────────────
    MAGE = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_crit",   label = "DMT Crit",    buffs = { "Slip'kik's Savvy" } },
        },
        consumes = {
            { id = "gap",       label = "GAP",          buffs = { "Greater Arcane Elixir" } },
            { id = "mageblood", label = "Mageblood",   buffs = { "Mana Regeneration" } },
            { id = "power",     label = "Power",        buffs = { "Greater Firepower", "Frost Power" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" } },
        },
    },

    -- ── Warlock ──────────────────────────────────────────────────────────
    WARLOCK = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_crit",   label = "DMT Crit",    buffs = { "Slip'kik's Savvy" } },
        },
        consumes = {
            { id = "gap",       label = "GAP",          buffs = { "Greater Arcane Elixir" } },
            { id = "shadow",    label = "Shadow",       buffs = { "Shadow Power" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" } },
        },
    },

    -- ── Druid ────────────────────────────────────────────────────────────
    DRUID = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
            { id = "dmt_crit",   label = "DMT Crit",    buffs = { "Slip'kik's Savvy" } },
        },
        consumes = {
            { id = "mageblood", label = "Mageblood",   buffs = { "Mana Regeneration" } },
            { id = "zanza",     label = "Zanza/Blasted",buffs = {
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection",
            } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" } },
        },
    },

    -- ── Shaman ───────────────────────────────────────────────────────────
    SHAMAN = {
        worldbuffs = {
            { id = "songflower", label = "Songflower",  buffs = { "Songflower Serenade" } },
            { id = "ony",        label = "Ony",         buffs = { "Rallying Cry of the Dragonslayer" } },
            { id = "zandalar",   label = "Zandalar",    buffs = { "Spirit of Zandalar" } },
            { id = "dmt_stam",   label = "DMT Stam",    buffs = { "Mol'dar's Moxie" } },
        },
        consumes = {
            { id = "mageblood", label = "Mageblood",   buffs = { "Mana Regeneration" } },
            { id = "food",      label = "Food",         buffs = { "Well Fed", "Increased Stamina" } },
        },
    },
}

-- Class display order for the Config tab row
BW_ClassOrder = {
    "WARRIOR", "ROGUE", "HUNTER", "PALADIN", "PRIEST",
    "MAGE",    "WARLOCK", "DRUID", "SHAMAN",
}

BW_ClassLabel = {
    WARRIOR = "Warrior", ROGUE    = "Rogue",   HUNTER  = "Hunter",
    PALADIN = "Paladin", PRIEST   = "Priest",  MAGE    = "Mage",
    WARLOCK = "Warlock", DRUID    = "Druid",   SHAMAN  = "Shaman",
}

BW_ClassColors = {
    WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372",
    ROGUE   = "FFF468", PRIEST  = "FFFFFF", MAGE   = "3FC7EB",
    WARLOCK = "8788EE", DRUID   = "FF7C0A", SHAMAN = "0070DE",
    DEATHKNIGHT = "C41E3A",
}
