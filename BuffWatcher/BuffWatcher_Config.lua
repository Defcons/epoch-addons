-- BuffWatcher_Config.lua
-- Edit this file to change which buffs/consumes are required per class.
--
-- Format for each entry:  { "Label", "Buff Name 1"[, "Buff Name 2", ...] }
--   • The label is shown in the missing-buffs report.
--   • Any one of the listed buff names counts as "present".
--   • Add  zandalar = true  to entries that should be skipped when
--     Zandalar is toggled off (via /bw zan or the in-frame button).
--
-- worldbuffs  = world buffs (Onyxia, Songflower, DMT, etc.)
-- consumes    = consumables (elixirs, Juju, food, Zanza pots, etc.)
-- Both lists are checked; flask is tracked separately and always required.

BW_Config = {

    -- Any one of these flasks counts as "has flask"
    flasks = {
        "Flask of the Titans",
        "Distilled Wisdom",
        "Supreme Power",
    },

    -- ── Warrior ──────────────────────────────────────────────────
    WARRIOR = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "Warchief",    "Warchief's Blessing" },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT AP",      "Fengus' Ferocity" },
        },
        consumes = {
            { "Mongoose",    "Elixir of the Mongoose" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Rage of Ages",
                "Strike of the Scorpok",
                "Darnassus Gift Collection", "Orgrimmar Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "AP",          "Juju Might", "Winterfall Firewater" },
            { "Strength",    "Juju Power", "Elixir of the Giants" },
            { "Food",        "Well Fed", "Increased Stamina", "Blessed Sunfruit", "Increased Agility" },
        },
    },

    -- ── Rogue ─────────────────────────────────────────────────────
    ROGUE = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "Warchief",    "Warchief's Blessing" },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT AP",      "Fengus' Ferocity" },
        },
        consumes = {
            { "Mongoose",    "Elixir of the Mongoose" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Rage of Ages",
                "Strike of the Scorpok",
                "Darnassus Gift Collection", "Orgrimmar Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "AP",          "Juju Might", "Winterfall Firewater" },
            { "Strength",    "Juju Power", "Elixir of the Giants" },
            { "Food",        "Well Fed", "Increased Stamina", "Blessed Sunfruit", "Increased Agility" },
        },
    },

    -- ── Hunter ────────────────────────────────────────────────────
    HUNTER = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT AP",      "Fengus' Ferocity" },
            { "DMT Crit",    "Slip'kik's Savvy" },
        },
        consumes = {
            { "Mongoose",    "Elixir of the Mongoose" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Rage of Ages",
                "Strike of the Scorpok",
                "Darnassus Gift Collection", "Orgrimmar Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "Food",        "Well Fed", "Increased Stamina", "Increased Agility", "Mana Regeneration" },
        },
    },

    -- ── Mage ──────────────────────────────────────────────────────
    MAGE = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT Crit",    "Slip'kik's Savvy" },
        },
        consumes = {
            { "GAP",         "Greater Arcane Elixir" },
            { "Mageblood",   "Mana Regeneration" },
            { "Power",       "Greater Firepower", "Frost Power" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "Food",        "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" },
        },
    },

    -- ── Warlock ───────────────────────────────────────────────────
    WARLOCK = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT Crit",    "Slip'kik's Savvy" },
        },
        consumes = {
            { "GAP",         "Greater Arcane Elixir" },
            { "Shadow",      "Shadow Power" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "Food",        "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" },
        },
    },

    -- ── Priest ────────────────────────────────────────────────────
    PRIEST = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT Crit",    "Slip'kik's Savvy" },
        },
        consumes = {
            { "Mageblood",   "Mana Regeneration" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "Food",        "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" },
        },
    },

    -- ── Paladin ───────────────────────────────────────────────────
    PALADIN = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT Crit",    "Slip'kik's Savvy" },
        },
        consumes = {
            { "Mageblood",   "Mana Regeneration" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "Food",        "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" },
        },
    },

    -- ── Druid ─────────────────────────────────────────────────────
    DRUID = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "DMT Stam",    "Mol'dar's Moxie" },
            { "DMT Crit",    "Slip'kik's Savvy" },
        },
        consumes = {
            { "Mageblood",   "Mana Regeneration" },
            { "Zanza/Blasted",
                "Spirit of Zanza", "Swiftness of Zanza", "Infallible Mind",
                "Stormwind Gift Collection", "Undercity Gift Collection",
                "Ironforge Gift Collection", "Thunder Bluff Gift Collection" },
            { "Food",        "Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration" },
        },
    },

    -- ── Shaman ────────────────────────────────────────────────────
    SHAMAN = {
        worldbuffs = {
            { "Songflower",  "Songflower Serenade" },
            { "Ony",         "Rallying Cry of the Dragonslayer" },
            { "Zandalar",    "Spirit of Zandalar",   zandalar = true },
            { "DMT Stam",    "Mol'dar's Moxie" },
        },
        consumes = {
            { "Mageblood",   "Mana Regeneration" },
            { "Food",        "Well Fed", "Increased Stamina" },
        },
    },
}
