local ADDON_NAME, ADDON = ...

local CONTACT_DEFAULT_ICON = "INV_Misc_GroupLooking"
local NUM_ICONS_PER_ROW = 8
local NUM_ICON_ROWS = 8
local NUM_ICONS_SHOWN = NUM_ICONS_PER_ROW * NUM_ICON_ROWS

local iconFiles
local popup

local function UpdateEditContactPopup()
    local numIcons = #iconFiles

    for i = 1, NUM_ICONS_SHOWN do
        local button = popup.BorderBox["Button" .. i]
        -- In 3.3.5 parentkey="Icon" is ignored; use GetNormalTexture() instead
        local buttonIcon = button:GetNormalTexture()
        local texture = iconFiles[i]

        if (i <= numIcons and texture) then
            ADDON:SetTexture(buttonIcon, texture)
            button:Show()
        else
            buttonIcon:SetTexture("")
            button:Hide()
        end
        if (popup.icon == texture) then
            button:SetChecked(true)
        else
            button:SetChecked(false)
        end
    end
end

local function EditContactPopupSelectTexture(iconIndex)
    popup.icon = iconFiles[iconIndex]
    popup.BorderBox.IconName:SetText(popup.icon or "")
    UpdateEditContactPopup()
end

local function CreateIconButtons()
    local previous, firstLastRow

    for i = 1, NUM_ICONS_SHOWN do
        local modulo = math.fmod(i, NUM_ICONS_PER_ROW)

        -- 5th arg to CreateFrame is not supported in 3.3.5; use SetID() instead
        local button = CreateFrame("CheckButton", nil, popup, "FavoriteContactsEditContactButtonTemplate")
        button:SetID(i)
        if i == 1 then
            button:SetPoint("TOPLEFT", popup.BorderBox.IconLabel, "BOTTOMLEFT", 0, -10)
            firstLastRow = button
        elseif modulo == 1 then
            button:SetPoint("TOPLEFT", firstLastRow, "BOTTOMLEFT", 0, -8)
            firstLastRow = button
        else
            button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        end

        popup.BorderBox["Button" .. i] = button
        previous = button
    end
end

local function CreateEditContactPopup()
    local L = ADDON.L

    -- Give popup a global name so $parentXxx children resolve correctly in 3.3.5
    popup = CreateFrame("Frame", "FCEditContactPopup", UIParent, "FavoriteContactsEditContactPopupTemplate")

    -- parentKey is retail-only; in 3.3.5 children are named $parentXxx and accessed via _G
    local bb = _G["FCEditContactPopupBorderBox"]
    popup.BorderBox             = bb
    bb.NameLabel                = _G["FCEditContactPopupBorderBoxNameLabel"]
    bb.NoteLabel                = _G["FCEditContactPopupBorderBoxNoteLabel"]
    bb.IconLabel                = _G["FCEditContactPopupBorderBoxIconLabel"]
    bb.ContactNameEditBox       = _G["FCEditContactPopupBorderBoxContactNameEditBox"]
    bb.NoteEditBox              = _G["FCEditContactPopupBorderBoxNoteEditBox"]
    bb.IconName                 = _G["FCEditContactPopupBorderBoxIconName"]

    -- OkayButton and CancelButton were provided by SelectionFrameTemplate (retail-only);
    -- create them manually here
    local okay = CreateFrame("Button", nil, bb, "UIPanelButtonTemplate")
    okay:SetWidth(80)
    okay:SetHeight(22)
    okay:SetPoint("BOTTOMLEFT", bb, "BOTTOMLEFT", 25, 10)
    okay:SetText(OKAY or "Okay")
    bb.OkayButton = okay

    local cancel = CreateFrame("Button", nil, bb, "UIPanelButtonTemplate")
    cancel:SetWidth(80)
    cancel:SetHeight(22)
    cancel:SetPoint("BOTTOMRIGHT", bb, "BOTTOMRIGHT", -25, 10)
    cancel:SetText(CANCEL or "Cancel")
    bb.CancelButton = cancel

    CreateIconButtons()
    bb.NameLabel:SetText(L["Contact Name:"])
    bb.NoteLabel:SetText(L["Contact Note:"] or "Note:")

    popup:SetScript("OnShow", function(sender)
        iconFiles = {
            -- Classes (vanilla only): using INV_ item icons which are confirmed present in this client
            "inv_sword_04",               -- Warrior
            "inv_hammer_01",              -- Paladin
            "inv_weapon_bow_07",          -- Hunter
            "inv_weapon_shortblade_05",   -- Rogue
            "inv_staff_01",               -- Priest
            "inv_jewelry_talisman_04",    -- Shaman
            "inv_wand_07",                -- Mage
            "inv_staff_09",               -- Warlock
            "inv_misc_monsterclaw_04",    -- Druid

            -- Races: Achievement_Character_* icons were added in WotLK 3.0
            -- Alliance
            "achievement_character_human_male",
            "achievement_character_human_female",
            "achievement_character_dwarf_male",
            "achievement_character_dwarf_female",
            "achievement_character_gnome_male",
            "achievement_character_gnome_female",
            "achievement_character_nightelf_male",
            "achievement_character_nightelf_female",
            "achievement_character_draenei_male",
            "achievement_character_draenei_female",
            -- Horde
            "achievement_character_orc_male",
            "achievement_character_orc_female",
            "achievement_character_undead_male",
            "achievement_character_undead_female",
            "achievement_character_tauren_male",
            "achievement_character_tauren_female",
            "achievement_character_troll_male",
            "achievement_character_troll_female",
            "achievement_character_bloodelf_male",
            "achievement_character_bloodelf_female",

            -- Professions
            "inv_misc_gem_01",            -- Jewelcrafting
            "Trade_Engraving",            -- Enchanting
            "Trade_Engineering",          -- Engineering
            "Trade_Alchemy",              -- Alchemy
            "inv_inscription_tradeskill01", -- Inscription
            "Trade_Tailoring",            -- Tailoring
            "inv_misc_armorkit_17",       -- Leatherworking
            "Trade_BlackSmithing",        -- Blacksmithing
            "Trade_Herbalism",            -- Herbalism
            "inv_misc_pelt_wolf_01",      -- Skinning
            "Trade_Mining",               -- Mining
            "inv_misc_food_15",           -- Cooking
            "Trade_Fishing",              -- Fishing
            "spell_holy_sealofsacrifice", -- First Aid

            -- Bank / Storage (practical for bank alts)
            "inv_misc_bag_07",            -- Bag (blue/purple)
            "inv_misc_bag_10",            -- Bag (white)
            "inv_misc_bag_11",            -- Bag (green)
            "inv_misc_bag_14",            -- Bag (brown)
            "inv_misc_bag_20",            -- Bag (yellow/gold)
            -- "inv_misc_chest_02",          -- (broken in this client)
            -- "inv_misc_chest_04",          -- (broken in this client)
            "inv_chest_chain",            -- Chain chest
            "inv_misc_key_01",            -- Key
            "inv_misc_coin_01",           -- Coin (single)
            "inv_misc_coin_04",           -- Coin pile
            "inv_misc_note_01",           -- Note / ledger

            -- Faction / Misc
            "INV_BannerPVP_01",
            "INV_BannerPVP_02",

            CONTACT_DEFAULT_ICON,
        }
    end)
    popup:SetScript("OnHide", function()
        iconFiles = nil
        collectgarbage()
    end)

    for index = 1, NUM_ICONS_SHOWN do
        local icon = popup.BorderBox["Button" .. index]
        icon:SetScript("OnClick", function(sender)
            EditContactPopupSelectTexture(sender:GetID())
        end)
    end

    bb.OkayButton:SetScript("OnClick", function()
        popup:Hide()

        local index = popup.index
        local recipient = bb.ContactNameEditBox:GetText()
        local note = bb.NoteEditBox:GetText()

        local icon = bb.IconName:GetText()
        if (not icon or string.len(icon) == 0) then
            icon = CONTACT_DEFAULT_ICON
        end

        ADDON:SetContact(index, recipient, icon, note)

        ADDON:SetSelectedContact(-1)
        ADDON:SetEnableContacts(true)
    end)

    bb.CancelButton:SetScript("OnClick", function()
        popup:Hide()

        ADDON:SetSelectedContact(-1)
        ADDON:SetEnableContacts(true)
    end)
end

ADDON:RegisterLoadUICallback(CreateEditContactPopup)

function ADDON:ShowEditContactPopup(index)
    popup.index = index

    local contact = self.settings.contacts[index] or {}
    popup.icon = contact.icon or CONTACT_DEFAULT_ICON

    local bb = popup.BorderBox
    bb.ContactNameEditBox:SetText(contact.recipient or "")
    bb.NoteEditBox:SetText(contact.note or "")
    bb.IconName:SetText(popup.icon or "")

    popup:Show()
    bb.ContactNameEditBox:SetFocus()

    self:SetSelectedContact(popup.index)
    self:SetEnableContacts(false)

    UpdateEditContactPopup()
end
