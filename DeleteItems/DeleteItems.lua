local ADDON_NAME = "DeleteItems"
local P = "|cff33ff99DeleteItems:|r "

-- Module-level UI references
local mainFrame, junkFrame
local scrollContent, junkScrollContent
local dragZoneText, dragResetTimer
local noteBox
local junkIgnoreLabel   -- updated whenever ignore list changes
local listTabBtns = {}
local rowPool     = {}
local junkRowPool = {}
local activeRows     = {}
local activeJunkRows = {}

-- Forward declarations
local RefreshUI, UpdateTabs, OpenJunkScanner

-------------------------------------------------
-- Data helpers
-- DIData uses SavedVariables (not PerCharacter),
-- so all lists are shared across every character on the account.
-------------------------------------------------
local currentList = "list1"

local function GetList(name)
    return DIData.lists[name or currentList]
end

local function CountList(name)
    local n = 0
    for _ in pairs(DIData.lists[name or currentList]) do n = n + 1 end
    return n
end

local function GetListName(name)
    return DIData.listNames[name or currentList] or (name or currentList)
end

local function SetActiveList(name)
    currentList = name
    DIData.activeList = name
    if noteBox then
        noteBox:SetText(DIData.listNotes[name] or "")
    end
end

local function AddItem(itemID)
    local k = tostring(itemID)
    if GetList()[k] then return false end
    GetList()[k] = true
    return true
end

local function RemoveItem(itemID)
    GetList()[tostring(itemID)] = nil
end

-- Scan bags without deleting. Returns: slotCount, totalCopperValue
local function CountDeletableItems()
    local count      = 0
    local totalValue = 0
    local list = GetList()
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = link:match("|Hitem:(%d+):")
                if id and list[id] then
                    local _, stackCount = GetContainerItemInfo(bag, slot)
                    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
                    count = count + 1
                    if sellPrice and sellPrice > 0 then
                        totalValue = totalValue + sellPrice * (stackCount or 1)
                    end
                end
            end
        end
    end
    return count, totalValue
end

local function DeleteBagItems()
    local n = 0
    local list = GetList()
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = link:match("|Hitem:(%d+):")
                if id and list[id] then
                    PickupContainerItem(bag, slot)
                    DeleteCursorItem()
                    n = n + 1
                end
            end
        end
    end
    print(P .. "Deleted " .. n .. " item(s) from bags.")
end

-------------------------------------------------
-- SavedVariables init + migration
-------------------------------------------------
local function EnsureDefaults()
    -- Migrate from old DITotalSavedItems / DICurrentList format
    if type(DITotalSavedItems) == "table" then
        if type(DIData) ~= "table" then DIData = {} end
        if type(DIData.lists) ~= "table" then DIData.lists = {} end
        for _, k in ipairs({"list1", "list2", "list3"}) do
            DIData.lists[k] = DIData.lists[k] or {}
            if type(DITotalSavedItems[k]) == "table" then
                for id in pairs(DITotalSavedItems[k]) do
                    DIData.lists[k][tostring(id)] = true
                end
            end
        end
        if type(DICurrentList) == "string" then
            DIData.activeList = DICurrentList
        end
        DITotalSavedItems = nil
        DICurrentList = nil
        print(P .. "Migrated data from old save format.")
    end

    if type(DIData) ~= "table" then DIData = {} end
    if type(DIData.lists) ~= "table" then DIData.lists = {} end
    for _, k in ipairs({"list1", "list2", "list3"}) do
        if type(DIData.lists[k]) ~= "table" then DIData.lists[k] = {} end
    end

    if type(DIData.listNames) ~= "table" then
        DIData.listNames = { list1 = "List 1", list2 = "List 2", list3 = "List 3" }
    end
    if type(DIData.listNotes) ~= "table" then
        DIData.listNotes = { list1 = "", list2 = "", list3 = "" }
    end
    for _, k in ipairs({"list1", "list2", "list3"}) do
        if DIData.listNames[k] == nil then DIData.listNames[k] = "List " .. k:sub(-1) end
        if DIData.listNotes[k] == nil then DIData.listNotes[k] = "" end
    end

    if type(DIData.junkThreshold) ~= "number" then
        DIData.junkThreshold = 1000  -- 10 silver in copper (default)
    end
    -- Ignore list: items that should never be suggested as junk
    if type(DIData.junkIgnore) ~= "table" then
        DIData.junkIgnore = {}
    end
    if type(DIData.activeList) ~= "string" or not DIData.lists[DIData.activeList] then
        DIData.activeList = "list1"
    end
    currentList = DIData.activeList
end

-------------------------------------------------
-- Utility: format copper as coloured g/s/c string
-------------------------------------------------
local function FormatMoney(copper)
    if not copper or copper <= 0 then return "|cff888888No vendor value|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, "|cffd4a72a" .. g .. "g|r") end
    if s > 0 then table.insert(parts, "|cffb0b0b0" .. s .. "s|r") end
    if c > 0 or #parts == 0 then table.insert(parts, "|cffb87333" .. c .. "c|r") end
    return table.concat(parts, " ")
end

-------------------------------------------------
-- Static popups
-------------------------------------------------
StaticPopupDialogs["DELETEITEMS_CLEAR_CONFIRMATION"] = {
    text = "Clear all items from the active list?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        wipe(DIData.lists[currentList])
        print(P .. "Cleared " .. GetListName() .. ".")
        RefreshUI()
    end,
    OnCancel = function() end,
    timeout = 0, exclusive = 1, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["DELETEITEMS_RENAME_LIST"] = {
    text = "Enter a new name for this list:",
    button1 = "OK",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnShow = function(self)
        self.editBox:SetText(GetListName())
        self.editBox:HighlightText()
    end,
    OnAccept = function(self)
        local text = strtrim(self.editBox:GetText())
        if text ~= "" then
            DIData.listNames[currentList] = text
            UpdateTabs()
        end
    end,
    OnCancel = function() end,
    timeout = 0, exclusive = 1, whileDead = 1, hideOnEscape = 1,
}

-------------------------------------------------
-- UpdateTabs
-------------------------------------------------
UpdateTabs = function()
    for i = 1, 3 do
        local btn = listTabBtns[i]
        if btn then
            local key   = "list" .. i
            local label = DIData.listNames[key] or ("List " .. i)
            btn:SetText(label .. " (" .. CountList(key) .. ")")
            if key == currentList then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
    end
end

-------------------------------------------------
-- RefreshUI  (main item list)
-------------------------------------------------
RefreshUI = function()
    UpdateTabs()
    if not mainFrame or not mainFrame:IsShown() then return end

    for _, row in ipairs(activeRows) do row:Hide() end
    activeRows = {}

    local list = GetList()
    local keys = {}
    for k in pairs(list) do table.insert(keys, k) end

    table.sort(keys, function(a, b)
        local na = GetItemInfo(tonumber(a))
        local nb = GetItemInfo(tonumber(b))
        if na and nb then return na < nb end
        if na then return true end
        if nb then return false end
        return tonumber(a) < tonumber(b)
    end)

    local ROW_H  = 22
    local PAD    = 2
    local CONT_W = 260

    scrollContent:SetHeight(math.max(#keys * (ROW_H + PAD), 30))
    scrollContent:SetWidth(CONT_W)

    if #keys == 0 then
        scrollContent.emptyText:Show()
        return
    end
    scrollContent.emptyText:Hide()

    for i, key in ipairs(keys) do
        local itemID = tonumber(key)
        local name, _, rarity, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)

        local row = rowPool[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollContent)
            row:SetHeight(ROW_H)
            row:SetWidth(CONT_W)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            row.bg:SetAllPoints()

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("LEFT", 5, 0)
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -54, 0)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)

            row.removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.removeBtn:SetSize(48, 18)
            row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.removeBtn:SetText("Remove")

            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if self.itemID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. self.itemID)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            rowPool[i] = row
        end

        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -(i - 1) * (ROW_H + PAD))
        row:SetWidth(CONT_W)

        if i % 2 == 0 then
            row.bg:SetVertexColor(0.18, 0.18, 0.18, 0.5)
        else
            row.bg:SetVertexColor(0.08, 0.08, 0.08, 0.3)
        end

        local r, g, b = 1, 1, 1
        if rarity and rarity >= 2 then r, g, b = GetItemQualityColor(rarity) end

        -- Show sell price per item instead of raw item ID
        local priceTag
        if sellPrice and sellPrice > 0 then
            priceTag = "  " .. FormatMoney(sellPrice)
        else
            priceTag = "  |cff888888(no value)|r"
        end
        row.nameText:SetText((name or "Unknown Item") .. priceTag)
        row.nameText:SetTextColor(r, g, b)
        row.itemID = itemID

        local capturedKey = key
        row.removeBtn:SetScript("OnClick", function()
            RemoveItem(tonumber(capturedKey))
            RefreshUI()
        end)

        row:Show()
        table.insert(activeRows, row)
    end
end

-------------------------------------------------
-- Junk scanner: helpers
-------------------------------------------------
local junkItems = {}

-- Returns true if itemID string is in ANY deletion list
local function IsInAnyList(id)
    for _, k in ipairs({"list1", "list2", "list3"}) do
        if DIData.lists[k][id] then return true end
    end
    return false
end

local function CountIgnored()
    local n = 0
    for _ in pairs(DIData.junkIgnore) do n = n + 1 end
    return n
end

local function UpdateIgnoreLabel()
    if junkIgnoreLabel then
        local n = CountIgnored()
        if n == 0 then
            junkIgnoreLabel:SetText("|cff888888No items ignored|r")
        else
            junkIgnoreLabel:SetText("|cffff9900Ignored: " .. n .. " item(s)|r")
        end
    end
end

-------------------------------------------------
-- Junk scanner: scan logic
-- threshold = 0  → show ALL gray items (any sell price), no whites.
-- threshold > 0  → show gray AND white items whose sell price <= threshold (copper).
-- Skips items already in any deletion list OR in the ignore list.
-- Also counts how many of each item are currently in bags and gets max stack size.
-- Sorts purely by sell price ascending (cheapest / no-value first).
-------------------------------------------------
local function ScanBagsForJunk(threshold)
    -- First pass: tally bag counts for every item slot
    local bagCounts = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = link:match("|Hitem:(%d+):")
                if id then
                    local _, slotCount = GetContainerItemInfo(bag, slot)
                    bagCounts[id] = (bagCounts[id] or 0) + (slotCount or 1)
                end
            end
        end
    end

    -- Second pass: decide what to suggest
    local seen    = {}
    local results = {}

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = link:match("|Hitem:(%d+):")
                if id and not seen[id]
                   and not IsInAnyList(id)
                   and not DIData.junkIgnore[id]
                then
                    local name, _, quality, _, _, _, _, maxStack, _, texture, sellPrice
                        = GetItemInfo(link)
                    if name then
                        local sp = sellPrice or 0
                        local isJunkQuality = (quality == 0 or quality == 1)
                        -- threshold = 0  →  grays only (any sell price)
                        -- threshold > 0  →  any gray/white whose sell price <= threshold
                        local meetsThreshold = (threshold == 0 and quality == 0)
                                            or (threshold > 0 and sp <= threshold)
                        if isJunkQuality and meetsThreshold then
                            seen[id] = true
                            table.insert(results, {
                                id        = id,
                                name      = name,
                                quality   = quality,
                                sellPrice = sp,
                                texture   = texture,
                                bagCount  = bagCounts[id] or 1,
                                maxStack  = maxStack or 1,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Sort cheapest first (no-value = 0 copper at the very top)
    table.sort(results, function(a, b)
        return a.sellPrice < b.sellPrice
    end)
    return results
end

-------------------------------------------------
-- Junk scanner: refresh row list
-- Two-line rows:
--   Line 1: item name (quality colour)
--   Line 2: sell price per item  +  bag count  +  max stack
-- Buttons stacked vertically on far right: [Add] top, [Ignore] bottom.
-------------------------------------------------
local function RefreshJunkList(items)
    for _, row in ipairs(activeJunkRows) do row:Hide() end
    activeJunkRows = {}

    UpdateIgnoreLabel()

    if not items or #items == 0 then
        junkScrollContent.emptyText:Show()
        return
    end
    junkScrollContent.emptyText:Hide()

    local ROW_H  = 38   -- tall enough for two comfortable text lines
    local PAD    = 2
    local CONT_W = 368  -- matches junk frame scroll area

    junkScrollContent:SetHeight(math.max(#items * (ROW_H + PAD), 30))
    junkScrollContent:SetWidth(CONT_W)

    -- Buttons are 90px wide, stacked; icon is 32px; text fills the middle.
    local ICON_W   = 32
    local BTN_W    = 90
    local BTN_GAP  = 2   -- gap from right edge
    local TEXT_L   = ICON_W + 6          -- text left offset from row left
    local TEXT_R   = -(BTN_W + BTN_GAP + 4)  -- text right offset from row right

    for i, item in ipairs(items) do
        local row = junkRowPool[i]
        if not row then
            row = CreateFrame("Frame", nil, junkScrollContent)
            row:SetHeight(ROW_H)
            row:SetWidth(CONT_W)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            row.bg:SetAllPoints()

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ICON_W - 2, ICON_W - 2)
            row.icon:SetPoint("LEFT", 3, 0)

            -- Line 1: item name
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_L, -3)
            row.nameText:SetPoint("RIGHT",   row, "RIGHT",   TEXT_R, 0)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)

            -- Line 2: price + count — using the larger Normal font so price stands out
            row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.priceText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", TEXT_L, 4)
            row.priceText:SetPoint("RIGHT",      row, "RIGHT",      TEXT_R, 0)
            row.priceText:SetJustifyH("LEFT")
            row.priceText:SetWordWrap(false)

            -- [Add to List] — upper right button
            row.addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.addBtn:SetSize(BTN_W, 17)
            row.addBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -BTN_GAP, -2)
            row.addBtn:SetText("Add to List")

            -- [Ignore] — lower right button
            row.ignBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.ignBtn:SetSize(BTN_W, 17)
            row.ignBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -BTN_GAP, 2)
            row.ignBtn:SetText("Ignore")

            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if self.itemID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. self.itemID)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            junkRowPool[i] = row
        end

        row:SetPoint("TOPLEFT", junkScrollContent, "TOPLEFT", 0, -(i - 1) * (ROW_H + PAD))
        row:SetWidth(CONT_W)
        row.itemID = item.id

        if i % 2 == 0 then
            row.bg:SetVertexColor(0.18, 0.18, 0.18, 0.5)
        else
            row.bg:SetVertexColor(0.08, 0.08, 0.08, 0.3)
        end

        row.icon:SetTexture(item.texture)

        -- Line 1: name in quality colour
        local r, g, b = GetItemQualityColor(item.quality)
        row.nameText:SetText(item.name)
        row.nameText:SetTextColor(r, g, b)

        -- Line 2: sell price/ea · bag count · stack size
        -- Price in copper colour codes makes it visually prominent.
        local stackNote = ""
        if item.maxStack and item.maxStack > 1 then
            stackNote = "  |cff888888(max stack: " .. item.maxStack .. ")|r"
        end
        local countStr = "|cffbbbbbbx" .. (item.bagCount or 1) .. " in bags|r"
        row.priceText:SetText(
            FormatMoney(item.sellPrice) .. "/ea   " .. countStr .. stackNote
        )
        row.priceText:SetTextColor(1, 1, 1)

        local capturedItem = item

        row.addBtn:SetScript("OnClick", function()
            AddItem(tonumber(capturedItem.id))
            for j, v in ipairs(junkItems) do
                if v == capturedItem then table.remove(junkItems, j); break end
            end
            RefreshJunkList(junkItems)
            RefreshUI()
            print(P .. "Added " .. capturedItem.name .. " to " .. GetListName() .. ".")
        end)

        row.ignBtn:SetScript("OnClick", function()
            DIData.junkIgnore[capturedItem.id] = true
            for j, v in ipairs(junkItems) do
                if v == capturedItem then table.remove(junkItems, j); break end
            end
            RefreshJunkList(junkItems)
            print(P .. capturedItem.name .. " ignored — won't be suggested again.")
        end)

        row:Show()
        table.insert(activeJunkRows, row)
    end
end

-------------------------------------------------
-- Build junk scanner frame
-- Layout (W=335):
--   Title + close                           (y=-16)
--   Row A: "White item limit:" [edit] "silver"  (y=-38)
--   Row B: [Scan Bags Now — full width]     (y=-66)
--   Row C: ignore status label              (y=-96)
--   Sep                                     (y=-114)
--   Scroll from y=-118 to bottom+80
--   Sep                                     (y=76)
--   [Add All]                               (y=50)
--   [Clear Ignored]                         (y=22)
--
-- Keeping Row A and Row B completely separate prevents any label/button overlap.
-------------------------------------------------
local junkClearIgnoredBtn  -- forward ref so UpdateIgnoreLabel can enable/disable it

local function BuildJunkFrame()
    if junkFrame then return end

    local W, H = 430, 450

    junkFrame = CreateFrame("Frame", ADDON_NAME .. "JunkFrame", UIParent)
    junkFrame:SetSize(W, H)
    junkFrame:SetPoint("LEFT", mainFrame, "RIGHT", 10, 0)
    junkFrame:SetFrameStrata("MEDIUM")
    junkFrame:SetMovable(true)
    junkFrame:EnableMouse(true)
    junkFrame:RegisterForDrag("LeftButton")
    junkFrame:SetScript("OnDragStart", junkFrame.StartMoving)
    junkFrame:SetScript("OnDragStop",  junkFrame.StopMovingOrSizing)
    junkFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    junkFrame:SetBackdropColor(0, 0, 0, 0.92)
    junkFrame:Hide()
    tinsert(UISpecialFrames, ADDON_NAME .. "JunkFrame") -- Claude: Escape closes junk scanner window

    ---- Title ----
    local title = junkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cffff9900Junk Scanner|r")

    local closeBtn = CreateFrame("Button", nil, junkFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() junkFrame:Hide() end)

    ---- Row A: threshold controls (label + editbox + unit — NO button on this row) ----
    local threshLabel = junkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    threshLabel:SetPoint("TOPLEFT", junkFrame, "TOPLEFT", 14, -40)
    threshLabel:SetText("Max sell price (gray/white):")

    local threshBox = CreateFrame("EditBox", ADDON_NAME .. "ThreshBox", junkFrame)
    threshBox:SetSize(44, 20)
    threshBox:SetPoint("LEFT", threshLabel, "RIGHT", 6, 0)
    threshBox:SetFontObject(ChatFontNormal)
    threshBox:SetMaxLetters(6)
    -- No SetNumeric — parse manually to avoid 3.3.5 quirks
    threshBox:SetAutoFocus(false)
    threshBox:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
    })
    threshBox:SetBackdropColor(0, 0, 0, 0.6)
    threshBox:SetText(tostring(math.floor(DIData.junkThreshold / 100)))
    threshBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    threshBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    threshBox:SetScript("OnEditFocusLost", function(self)
        local v = math.max(0, math.floor(tonumber(self:GetText()) or 0))
        self:SetText(tostring(v))
        DIData.junkThreshold = v * 100
    end)

    local silverLabel = junkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    silverLabel:SetPoint("LEFT", threshBox, "RIGHT", 5, 0)
    silverLabel:SetText("silver   |cff888888(0 = all grays regardless of price)|r")

    ---- Row B: scan button — full width, own row, guaranteed no overlap ----
    local scanBtn = CreateFrame("Button", nil, junkFrame, "UIPanelButtonTemplate")
    scanBtn:SetSize(W - 28, 24)
    scanBtn:SetPoint("TOPLEFT", junkFrame, "TOPLEFT", 14, -66)
    scanBtn:SetText("Scan Bags Now")
    scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Scan bags for junk items.", 1, 1, 1)
        GameTooltip:AddLine("Threshold 0: all grays shown, no whites.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Threshold > 0: any gray or white item whose sell", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("price per item is at or under the limit.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Items already in any list or ignored are skipped.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Results sorted cheapest first.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ---- Row C: ignore status ----
    junkIgnoreLabel = junkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    junkIgnoreLabel:SetPoint("TOPLEFT", junkFrame, "TOPLEFT", 14, -98)
    junkIgnoreLabel:SetText("|cff888888No items ignored|r")

    ---- Separator below controls ----
    local sep = junkFrame:CreateTexture(nil, "ARTWORK")
    sep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    sep:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    sep:SetPoint("TOPLEFT",  junkFrame, "TOPLEFT",  14, -114)
    sep:SetPoint("TOPRIGHT", junkFrame, "TOPRIGHT", -14, -114)
    sep:SetHeight(1)

    ---- Scroll frame ----
    local sf = CreateFrame("ScrollFrame", ADDON_NAME .. "JunkScroll", junkFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     junkFrame, "TOPLEFT",  14, -118)
    sf:SetPoint("BOTTOMRIGHT", junkFrame, "BOTTOMRIGHT", -28, 80)

    junkScrollContent = CreateFrame("Frame", ADDON_NAME .. "JunkScrollContent", sf)
    junkScrollContent:SetWidth(368)
    junkScrollContent:SetHeight(10)
    sf:SetScrollChild(junkScrollContent)

    junkScrollContent.emptyText = junkScrollContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    junkScrollContent.emptyText:SetPoint("TOP", 0, -40)
    junkScrollContent.emptyText:SetText(
        "Click 'Scan Bags Now' to find junk.\n\n" ..
        "Threshold = 0: shows all gray items.\n" ..
        "Threshold > 0: shows gray and white items\n" ..
        "whose sell price is at or under the limit.\n\n" ..
        "Items already in any deletion list\n" ..
        "or the ignore list are never shown."
    )
    junkScrollContent.emptyText:Show()

    ---- Separator above bottom buttons ----
    local sep2 = junkFrame:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    sep2:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    sep2:SetPoint("BOTTOMLEFT",  junkFrame, "BOTTOMLEFT",  14, 76)
    sep2:SetPoint("BOTTOMRIGHT", junkFrame, "BOTTOMRIGHT", -14, 76)
    sep2:SetHeight(1)

    ---- Bottom buttons ----
    local addAllBtn = CreateFrame("Button", nil, junkFrame, "UIPanelButtonTemplate")
    addAllBtn:SetSize(W - 28, 22)
    addAllBtn:SetPoint("BOTTOM", junkFrame, "BOTTOM", 0, 48)
    addAllBtn:SetText("Add All Suggestions to Active List")

    junkClearIgnoredBtn = CreateFrame("Button", nil, junkFrame, "UIPanelButtonTemplate")
    junkClearIgnoredBtn:SetSize(W - 28, 22)
    junkClearIgnoredBtn:SetPoint("BOTTOM", junkFrame, "BOTTOM", 0, 22)
    junkClearIgnoredBtn:SetText("Clear Ignored Items (0)")
    junkClearIgnoredBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clears the ignore list.", 1, 1, 1)
        GameTooltip:AddLine("Ignored items may appear in future scans again.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    junkClearIgnoredBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Re-define UpdateIgnoreLabel now that both label and button exist
    UpdateIgnoreLabel = function()
        local n = CountIgnored()
        if junkIgnoreLabel then
            if n == 0 then
                junkIgnoreLabel:SetText("|cff888888No items ignored|r")
            else
                junkIgnoreLabel:SetText("|cffff9900Ignored: " .. n .. " item(s)|r")
            end
        end
        if junkClearIgnoredBtn then
            junkClearIgnoredBtn:SetText("Clear Ignored Items (" .. n .. ")")
            if n > 0 then junkClearIgnoredBtn:Enable()
            else          junkClearIgnoredBtn:Disable() end
        end
    end
    UpdateIgnoreLabel()

    ---- Wire scan button ----
    scanBtn:SetScript("OnClick", function()
        -- Commit editbox value before reading it
        threshBox:ClearFocus()
        local silver = math.max(0, math.floor(tonumber(threshBox:GetText()) or 0))
        DIData.junkThreshold = silver * 100
        junkItems = ScanBagsForJunk(DIData.junkThreshold)
        RefreshJunkList(junkItems)
        if #junkItems == 0 then
            print(P .. "No junk found (everything is already listed or ignored).")
        else
            print(P .. "Found " .. #junkItems .. " junk item(s).")
        end
    end)

    ---- Wire Add All button ----
    addAllBtn:SetScript("OnClick", function()
        local added = 0
        for _, item in ipairs(junkItems) do
            AddItem(tonumber(item.id))
            added = added + 1
        end
        junkItems = {}
        if added > 0 then
            print(P .. "Added " .. added .. " item(s) to " .. GetListName() .. ".")
            RefreshJunkList(junkItems)
            RefreshUI()
        else
            print(P .. "No suggestions to add.")
        end
    end)

    ---- Wire Clear Ignored button ----
    junkClearIgnoredBtn:SetScript("OnClick", function()
        local n = CountIgnored()
        wipe(DIData.junkIgnore)
        print(P .. "Cleared " .. n .. " ignored item(s).")
        UpdateIgnoreLabel()
    end)
end

OpenJunkScanner = function()
    BuildJunkFrame()
    if junkFrame:IsShown() then
        junkFrame:Hide()
    else
        junkFrame:Show()
        UpdateIgnoreLabel()
    end
end

-------------------------------------------------
-- Build main window
-------------------------------------------------
local function BuildUI()
    if mainFrame then return end

    local W, H = 320, 475

    mainFrame = CreateFrame("Frame", ADDON_NAME .. "MainFrame", UIParent)
    mainFrame:SetSize(W, H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
    mainFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    mainFrame:SetBackdropColor(0, 0, 0, 0.92)
    mainFrame:Hide()
    tinsert(UISpecialFrames, ADDON_NAME .. "MainFrame") -- Claude: Escape closes main window (StaticPopups close first if open)

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cff33ff99Delete Items|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- List tabs (left-click = switch, right-click = rename)
    local TAB_Y = -40
    local TAB_W = math.floor((W - 30) / 3)
    for i = 1, 3 do
        local tab = CreateFrame("Button", ADDON_NAME .. "Tab" .. i, mainFrame, "UIPanelButtonTemplate")
        tab:SetSize(TAB_W, 24)
        tab:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12 + (i - 1) * (TAB_W + 3), TAB_Y)
        tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local idx = i
        tab:SetScript("OnClick", function(_, btn)
            SetActiveList("list" .. idx)
            if btn == "RightButton" then
                StaticPopup_Show("DELETEITEMS_RENAME_LIST")
            else
                RefreshUI()
            end
        end)
        tab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Left-click: Switch to this list", 1, 1, 1)
            GameTooltip:AddLine("Right-click: Rename this list", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        listTabBtns[i] = tab
    end

    -- Note editbox (1 line, auto-saves on focus lost)
    local NOTE_Y = TAB_Y - 30
    local noteBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    noteBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    noteBg:SetVertexColor(0, 0, 0, 0.4)
    noteBg:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  12, NOTE_Y)
    noteBg:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -12, NOTE_Y)
    noteBg:SetHeight(20)

    noteBox = CreateFrame("EditBox", ADDON_NAME .. "NoteBox", mainFrame)
    noteBox:SetSize(W - 30, 18)
    noteBox:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, NOTE_Y - 1)
    noteBox:SetFontObject(ChatFontNormal)
    noteBox:SetMaxLetters(200)
    noteBox:SetMultiLine(false)
    noteBox:SetAutoFocus(false)
    noteBox:SetText(DIData.listNotes[currentList] or "")
    noteBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    noteBox:SetScript("OnEscapePressed", function(self)
        noteBox:SetText(DIData.listNotes[currentList] or "")
        self:ClearFocus()
    end)
    noteBox:SetScript("OnEditFocusLost", function(self)
        DIData.listNotes[currentList] = self:GetText()
    end)

    local notePlaceholder = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    notePlaceholder:SetPoint("LEFT", noteBox, "LEFT", 2, 0)
    notePlaceholder:SetText("Add a note for this list...")
    noteBox:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= "" then notePlaceholder:Hide() else notePlaceholder:Show() end
    end)

    -- Separator under note
    local SEP1_Y = NOTE_Y - 24
    local sep1 = mainFrame:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    sep1:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    sep1:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  12, SEP1_Y)
    sep1:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -12, SEP1_Y)
    sep1:SetHeight(1)

    -- Scroll frame for item list
    local sf = CreateFrame("ScrollFrame", ADDON_NAME .. "Scroll", mainFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",  12, SEP1_Y - 4)
    sf:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -28, 120)

    scrollContent = CreateFrame("Frame", ADDON_NAME .. "ScrollContent", sf)
    scrollContent:SetWidth(260)
    scrollContent:SetHeight(10)
    sf:SetScrollChild(scrollContent)

    scrollContent.emptyText = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    scrollContent.emptyText:SetPoint("TOP", 0, -30)
    scrollContent.emptyText:SetText("This list is empty.\nDrag items to the zone below to add them.")
    scrollContent.emptyText:Hide()

    -- Separator above bottom controls
    local sep2 = mainFrame:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    sep2:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    sep2:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  12, 115)
    sep2:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 115)
    sep2:SetHeight(1)

    -- Drag-to-add zone
    local dz = CreateFrame("Frame", ADDON_NAME .. "DragZone", mainFrame)
    dz:SetSize(W - 24, 36)
    dz:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 73)
    dz:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
    })
    dz:SetBackdropColor(0.05, 0.22, 0.05, 0.7)
    dz:SetBackdropBorderColor(0.25, 0.75, 0.25, 0.9)
    dz:EnableMouse(true)

    dragZoneText = dz:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dragZoneText:SetPoint("CENTER")
    dragZoneText:SetText("|cff55ff55[ Drag an Item Here to Add It ]|r")

    dragResetTimer = CreateFrame("Frame")
    dragResetTimer:Hide()
    dragResetTimer:SetScript("OnUpdate", function(self, dt)
        self.elapsed = (self.elapsed or 0) + dt
        if self.elapsed >= 2 then
            dragZoneText:SetText("|cff55ff55[ Drag an Item Here to Add It ]|r")
            self:Hide()
        end
    end)

    dz:SetScript("OnReceiveDrag", function()
        local t, id = GetCursorInfo()
        if t == "item" and id then
            ClearCursor()
            local itemID = tonumber(id)
            if itemID then
                if AddItem(itemID) then
                    local name = GetItemInfo(itemID)
                    dragZoneText:SetText("|cff33ff99Added:|r " .. (name or "Item " .. itemID))
                    print(P .. "Added " .. (name or "item " .. itemID) .. " to " .. GetListName() .. ".")
                else
                    local name = GetItemInfo(itemID)
                    dragZoneText:SetText("|cffffff00Already in list:|r " .. (name or itemID))
                end
                dragResetTimer.elapsed = 0
                dragResetTimer:Show()
                RefreshUI()
            end
        end
    end)

    -- Bottom row 1: Delete + Clear
    local deleteBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    deleteBtn:SetSize(155, 22)
    deleteBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 12, 48)
    deleteBtn:SetText("Delete Items From Bags")
    deleteBtn:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            DeleteBagItems()
        else
            print(P .. "|cffffff00Hold |cffff4444Shift|cffffff00 and click to confirm deletion.|r")
        end
    end)
    deleteBtn:SetScript("OnEnter", function(self)
        local count, totalValue = CountDeletableItems()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if count == 0 then
            GameTooltip:SetText("Delete Items From Bags", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("No matching items in bags right now.", 0.5, 0.5, 0.5)
        else
            GameTooltip:SetText("Delete Items From Bags", 1, 0.3, 0.3)
            GameTooltip:AddLine("Bag slots freed: |cffffffff" .. count .. "|r", 0.9, 0.9, 0.9)
            if totalValue > 0 then
                GameTooltip:AddLine("Value destroyed: " .. FormatMoney(totalValue), 0.9, 0.9, 0.9)
            else
                GameTooltip:AddLine("Value destroyed: |cff888888none|r", 0.9, 0.9, 0.9)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffff4444Shift-click|r to confirm deletion.", 1, 1, 0)
        GameTooltip:Show()
    end)
    deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clearBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    clearBtn:SetSize(100, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 48)
    clearBtn:SetText("Clear List")
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("DELETEITEMS_CLEAR_CONFIRMATION")
    end)

    -- Bottom row 2: Open junk scanner
    local junkBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    junkBtn:SetSize(W - 24, 22)
    junkBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 12, 20)
    junkBtn:SetText("|cffff9900Scan Bags for Junk Suggestions|r")
    junkBtn:SetScript("OnClick", OpenJunkScanner)
    junkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Opens the Junk Scanner.", 1, 1, 1)
        GameTooltip:AddLine("Finds gray/cheap white items and lets you", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("add or permanently ignore them.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    junkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-------------------------------------------------
-- Launcher button (small draggable on-screen frame)
-------------------------------------------------
local function BuildLauncherButton()
    local btn = CreateFrame("Button", ADDON_NAME .. "LauncherBtn", UIParent)
    btn:SetSize(90, 22)
    btn:SetFrameStrata("MEDIUM")
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", btn.StartMoving)
    btn:SetScript("OnDragStop",  btn.StopMovingOrSizing)
    btn:SetPoint("CENTER", UIParent, "CENTER", 0, -300)

    btn:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
    btn:SetBackdropBorderColor(0.25, 0.75, 0.25, 0.9)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("|cff33ff99Delete Items|r")

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 1, 0.5, 1)
        local count, totalValue = CountDeletableItems()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Delete Items  —  " .. GetListName(), 1, 1, 1)
        GameTooltip:AddLine(" ")
        if count == 0 then
            GameTooltip:AddLine("No matching items in bags.", 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine("Bag slots freed:   |cffffffff" .. count .. "|r", 0.9, 0.9, 0.9)
            if totalValue > 0 then
                GameTooltip:AddLine("Value destroyed:  " .. FormatMoney(totalValue), 0.9, 0.9, 0.9)
            else
                GameTooltip:AddLine("Value destroyed:  |cff888888none|r", 0.9, 0.9, 0.9)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click:              Open / close window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cffff4444Shift-click:|r       Delete now", 1, 1, 0)
        GameTooltip:AddLine("Drag:               Move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.75, 0.25, 0.9)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            DeleteBagItems()
        else
            if mainFrame:IsShown() then
                mainFrame:Hide()
            else
                mainFrame:Show()
                RefreshUI()
            end
        end
    end)
end

-------------------------------------------------
-- Slash commands
-------------------------------------------------
SLASH_DELETEITEMS1 = "/deleteitem"
SLASH_DELETEITEMS2 = "/di"
function SlashCmdList.DELETEITEMS(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")

    if not cmd then
        if mainFrame:IsShown() then mainFrame:Hide()
        else mainFrame:Show(); RefreshUI() end
        return
    end

    cmd = cmd:lower()

    if cmd == "add" then
        if rest:find("|cff") then
            for link in rest:gmatch("(|cff%x%x%x%x%x%x.-|r)") do
                local id = link:match("|Hitem:(%d+):")
                if id and AddItem(tonumber(id)) then
                    print(P .. "Added " .. (GetItemInfo(tonumber(id)) or id) .. " to " .. GetListName() .. ".")
                end
            end
        else
            for id in rest:gmatch("(%d+)") do
                if AddItem(tonumber(id)) then
                    print(P .. "Added " .. (GetItemInfo(tonumber(id)) or id) .. " to " .. GetListName() .. ".")
                end
            end
        end
        RefreshUI()

    elseif cmd == "rem" or cmd == "remove" then
        local id = tonumber(rest)
        if id then
            RemoveItem(id)
            print(P .. "Removed " .. (GetItemInfo(id) or "item " .. id) .. " from " .. GetListName() .. ".")
            RefreshUI()
        else
            print(P .. "Usage: /di rem <itemID>")
        end

    elseif cmd == "del" or cmd == "delete" then
        DeleteBagItems()

    elseif cmd == "list" then
        local keys = {}
        for k in pairs(GetList()) do table.insert(keys, k) end
        if #keys == 0 then print(P .. GetListName() .. " is empty."); return end
        table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
        print(P .. GetListName() .. " (" .. #keys .. " items):")
        for _, k in ipairs(keys) do
            print(string.format("  |cffffd200%s|r  [%s]", GetItemInfo(tonumber(k)) or "Unknown", k))
        end

    elseif cmd == "clear" then
        StaticPopup_Show("DELETEITEMS_CLEAR_CONFIRMATION")

    elseif cmd == "set" then
        if rest == "list1" or rest == "list2" or rest == "list3" then
            SetActiveList(rest)
            RefreshUI()
            print(P .. "Active list: " .. GetListName() .. " (" .. CountList() .. " items).")
        else
            print(P .. "Usage: /di set list1|list2|list3")
        end

    elseif cmd == "junk" or cmd == "scan" then
        OpenJunkScanner()

    else
        print(P .. "Commands:  add  rem  del  list  clear  set  junk")
        print(P .. "Or just |cff33ff99/di|r to open the window.")
    end
end

-------------------------------------------------
-- Init
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDefaults()
        BuildUI()
        BuildLauncherButton()
        UpdateTabs()
        if noteBox then noteBox:SetText(DIData.listNotes[currentList] or "") end
        print(P .. "Loaded. Active: " .. GetListName() .. " (" .. CountList() .. " items). /di to open.")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
