-- BuffWatcher_Config.lua
-- Claude: configuration frame — role selector dropdown + per-role buff entry editor + spec override panel.
-- Loaded after BuffWatcher.lua (see TOC). Attaches BW:CreateConfigFrame / BW:OpenConfig.

-- ── Layout constants ─────────────────────────────────────────────────────────

local CFG_W      = 520
local CFG_H      = 540
local CONTENT_X  = 10

-- Claude: entry row column widths
local CB_SIZE    = 18
local BUFF_W     = 220
local LABEL_W    = 130
local DEL_W      = 20
local COL_GAP    = 5
local ROW_H      = 24

-- ── State ────────────────────────────────────────────────────────────────────

local selectedRole = "Tank" -- Claude: currently selected role in config UI
local scrollChild  = nil    -- Claude: set inside CreateConfigFrame

-- ── Styled EditBox helper ────────────────────────────────────────────────────
-- Claude: plain EditBox + backdrop wrapper avoids InputBoxTemplate auto-focus issues

local function MakeEB(parent, w, maxChars)
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:SetSize(w, ROW_H - 2)
    wrap:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 4, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    wrap:SetBackdropColor(0.06, 0.07, 0.14, 0.92)
    wrap:SetBackdropBorderColor(0.28, 0.42, 0.65, 0.80)

    local eb = CreateFrame("EditBox", nil, wrap)
    eb:SetPoint("TOPLEFT",     wrap, "TOPLEFT",      4, -2)
    eb:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -4,  2)
    eb:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    eb:SetTextColor(0.90, 0.90, 0.90)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxChars or 128)

    return wrap, eb
end

-- ── Row pool ─────────────────────────────────────────────────────────────────

local rowPool = {}

local function GetPoolRow(idx)
    if not rowPool[idx] then
        if not scrollChild then return nil end

        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(ROW_H)
        row:SetWidth(CB_SIZE + COL_GAP * 3 + BUFF_W + LABEL_W + DEL_W)

        -- Claude: alternating row tint
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if idx % 2 == 0 then
            bg:SetTexture(0.10, 0.12, 0.20, 0.40)
        else
            bg:SetTexture(0.05, 0.06, 0.10, 0.20)
        end

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(CB_SIZE, CB_SIZE)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)

        local buffWrap, buffEB = MakeEB(row, BUFF_W, 128)
        buffWrap:SetPoint("LEFT", cb, "RIGHT", COL_GAP, 0)

        local labelWrap, labelEB = MakeEB(row, LABEL_W, 64)
        labelWrap:SetPoint("LEFT", buffWrap, "RIGHT", COL_GAP, 0)

        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetSize(DEL_W, DEL_W)
        delBtn:SetPoint("LEFT", labelWrap, "RIGHT", COL_GAP, 0)
        delBtn:SetText("X")

        row.cb      = cb
        row.buffEB  = buffEB
        row.labelEB = labelEB
        row.delBtn  = delBtn

        rowPool[idx] = row
    end
    return rowPool[idx]
end

-- ── Get current role's entries ───────────────────────────────────────────────

local function GetCurrentEntries()
    local db = BuffWatcherDB
    if not db or not db.roles or not db.roles[selectedRole] then return {} end
    return db.roles[selectedRole].entries or {}
end

-- ── Config rebuild ───────────────────────────────────────────────────────────

local function RebuildConfig()
    if not scrollChild then return end

    -- Claude: hide all rows and clear old scripts
    for _, row in ipairs(rowPool) do
        row:Hide()
        row.cb:SetScript("OnClick", nil)
        row.buffEB:SetScript("OnEditFocusLost",  nil)
        row.buffEB:SetScript("OnEnterPressed",   nil)
        row.buffEB:SetScript("OnEscapePressed",  nil)
        row.labelEB:SetScript("OnEditFocusLost", nil)
        row.labelEB:SetScript("OnEnterPressed",  nil)
        row.labelEB:SetScript("OnEscapePressed", nil)
        row.delBtn:SetScript("OnClick", nil)
    end

    local entries = GetCurrentEntries()

    for i, entry in ipairs(entries) do
        local row = GetPoolRow(i)
        if not row then break end

        row.entryIndex = i
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_X, -(i - 1) * ROW_H)

        row.cb:SetChecked(entry.enabled ~= false and 1 or nil)
        row.buffEB:SetText(entry.buff   or "")
        row.labelEB:SetText(entry.label or "")

        local capturedRow = row

        row.cb:SetScript("OnClick", function(self)
            local ent = GetCurrentEntries()[capturedRow.entryIndex]
            if ent then ent.enabled = (self:GetChecked() and true or false) end
            if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
        end)

        row.buffEB:SetScript("OnEditFocusLost", function(self)
            local ent = GetCurrentEntries()[capturedRow.entryIndex]
            if ent then ent.buff = self:GetText() end
        end)
        row.buffEB:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        row.buffEB:SetScript("OnEscapePressed", function(self)
            local ent = GetCurrentEntries()[capturedRow.entryIndex]
            if ent then self:SetText(ent.buff or "") end
            self:ClearFocus()
        end)

        row.labelEB:SetScript("OnEditFocusLost", function(self)
            local ent = GetCurrentEntries()[capturedRow.entryIndex]
            if ent then ent.label = self:GetText() end
            if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
        end)
        row.labelEB:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        row.labelEB:SetScript("OnEscapePressed", function(self)
            local ent = GetCurrentEntries()[capturedRow.entryIndex]
            if ent then self:SetText(ent.label or "") end
            self:ClearFocus()
        end)

        row.delBtn:SetScript("OnClick", function()
            local ents = GetCurrentEntries()
            table.remove(ents, capturedRow.entryIndex)
            RebuildConfig()
            if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
        end)

        row:Show()
    end

    -- Claude: clear focus from all EditBoxes
    for _, row in ipairs(rowPool) do
        row.buffEB:ClearFocus()
        row.labelEB:ClearFocus()
    end

    scrollChild:SetHeight(math.max(#entries * ROW_H + 4, ROW_H))
end

-- ── StaticPopup for reset confirmation ───────────────────────────────────────

StaticPopupDialogs["BUFFWATCHER_RESET_CONFIRM"] = {
    text = "Reset %s entries to defaults?\nThis cannot be undone.", -- Claude: %s = role name
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        -- Claude: deep-copy defaults for the selected role
        local defaults = BW.DefaultRoleEntries[selectedRole]
        if defaults and BuffWatcherDB and BuffWatcherDB.roles and BuffWatcherDB.roles[selectedRole] then
            BuffWatcherDB.roles[selectedRole].entries = {}
            for _, e in ipairs(defaults) do
                tinsert(BuffWatcherDB.roles[selectedRole].entries, { buff = e.buff, label = e.label, enabled = e.enabled })
            end
        end
        RebuildConfig()
        if BW.statusFrame and BW.statusFrame:IsShown() then BW:Refresh() end
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

-- ── Role selector dropdown ───────────────────────────────────────────────────

local roleDropdown = nil -- Claude: set in CreateConfigFrame

local function RoleDropdown_OnClick(self)
    selectedRole = self.value -- Claude: UIDropDownMenu passes .value from info table
    UIDropDownMenu_SetSelectedValue(roleDropdown, selectedRole)
    RebuildConfig()
end

local function RoleDropdown_Initialize(self)
    local roleColors = BW.RoleColors or {}
    for _, role in ipairs(BW.ROLES) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cff" .. (roleColors[role] or "FFFFFF") .. role .. "|r"
        info.value = role
        info.func = RoleDropdown_OnClick
        info.checked = (role == selectedRole) -- Claude: 3.3.5 needs explicit checked
        UIDropDownMenu_AddButton(info)
    end
end

-- ── Spec → Role override panel ───────────────────────────────────────────────
-- Claude: small expandable section at the bottom of config where user can override
-- which role a spec maps to (e.g. change Feral Druid from Melee to Tank)

local specOverrideFrame = nil -- Claude: created lazily

local function CreateSpecOverrideFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(CFG_W - CONTENT_X * 2)
    f:SetHeight(200)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 4, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.05, 0.06, 0.10, 0.95)
    f:SetBackdropBorderColor(0.25, 0.40, 0.60, 0.7)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    title:SetText("|cff8899BBSpec → Role Overrides|r")

    local helpText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    helpText:SetWidth(CFG_W - CONTENT_X * 2 - 16)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("|cff667788Change which role a spec maps to (e.g. Feral → Tank)|r")

    -- Claude: build one dropdown per class that has multiple possible roles
    local yOff = -34
    local classOrder = { "WARRIOR", "PALADIN", "DRUID", "SHAMAN", "PRIEST" } -- Claude: only hybrid classes need overrides

    local tabNames = { -- Claude: talent tab names per class
        WARRIOR = { "Arms", "Fury", "Prot" },
        PALADIN = { "Holy", "Prot", "Ret" },
        DRUID   = { "Balance", "Feral", "Resto" },
        SHAMAN  = { "Ele", "Enh", "Resto" },
        PRIEST  = { "Disc", "Holy", "Shadow" },
    }

    for _, classFile in ipairs(classOrder) do
        local specMap = BW.SPEC_ROLE_MAP[classFile]
        if not specMap then break end -- Claude: safety
        local tabs = tabNames[classFile] or { "Tab1", "Tab2", "Tab3" }

        local classColors = BW.ClassColors or {}
        local classHex = classColors[classFile] or "FFFFFF"

        for tab = 1, 3 do
            local defaultRole = specMap[tab]
            local specName = tabs[tab]

            -- Claude: label
            local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 8, yOff)
            lbl:SetWidth(120)
            lbl:SetJustifyH("LEFT")
            lbl:SetText("|cff" .. classHex .. classFile:sub(1,1) .. classFile:sub(2):lower() .. "|r " .. specName)

            -- Claude: current role display + click to cycle
            local roleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            roleBtn:SetSize(70, 18)
            roleBtn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)

            local function UpdateRoleBtnText()
                local overrides = BuffWatcherDB and BuffWatcherDB.specRoles and BuffWatcherDB.specRoles[classFile]
                local currentRole = (overrides and overrides[tab]) or defaultRole
                local roleColors = BW.RoleColors or {}
                local hex = roleColors[currentRole] or "AAAAAA"
                roleBtn:SetText("|cff" .. hex .. currentRole .. "|r")
            end
            UpdateRoleBtnText()

            -- Claude: cycle through roles on click
            local capturedClass = classFile
            local capturedTab = tab
            roleBtn:SetScript("OnClick", function()
                if not BuffWatcherDB then return end
                if not BuffWatcherDB.specRoles then BuffWatcherDB.specRoles = {} end
                if not BuffWatcherDB.specRoles[capturedClass] then BuffWatcherDB.specRoles[capturedClass] = {} end

                local overrides = BuffWatcherDB.specRoles[capturedClass]
                local current = overrides[capturedTab] or defaultRole
                -- Claude: find next role in cycle
                local roles = BW.ROLES
                local nextIdx = 1
                for ri, r in ipairs(roles) do
                    if r == current then nextIdx = ri + 1; break end
                end
                if nextIdx > #roles then nextIdx = 1 end
                local newRole = roles[nextIdx]

                if newRole == defaultRole then
                    overrides[capturedTab] = nil -- Claude: remove override if back to default
                else
                    overrides[capturedTab] = newRole
                end

                -- Claude: clean up empty override tables
                local hasAny = false
                for _ in pairs(overrides) do hasAny = true; break end
                if not hasAny then BuffWatcherDB.specRoles[capturedClass] = nil end

                UpdateRoleBtnText()

                -- Claude: clear inspect cache so roles get re-evaluated
                BW.inspectResults = {}
            end)

            yOff = yOff - 20
        end
        yOff = yOff - 4 -- Claude: gap between classes
    end

    f:SetHeight(math.abs(yOff) + 8)
    return f
end

-- ── Config frame creation ────────────────────────────────────────────────────

function BW:CreateConfigFrame()
    local cf = CreateFrame("Frame", "BWConfigFrame", UIParent)
    cf:SetWidth(CFG_W)
    cf:SetHeight(CFG_H)
    cf:SetFrameStrata("DIALOG")
    cf:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 14,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    cf:SetBackdropColor(0.04, 0.05, 0.09, 0.97)
    cf:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.9)
    cf:SetPoint("CENTER", UIParent, "CENTER", 200, 40)
    cf:SetMovable(true)
    cf:EnableMouse(true)
    cf:RegisterForDrag("LeftButton")
    cf:SetScript("OnDragStart", function(self) self:StartMoving() end)
    cf:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    cf:Hide()
    self.configFrame = cf

    local title = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", cf, "TOP", 0, -9)
    title:SetText("|cff88CCFFBuffWatcher|r |cffAAAAAA- Config|r")

    local closeBtn = CreateFrame("Button", nil, cf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() cf:Hide() end)

    local divTop = cf:CreateTexture(nil, "ARTWORK")
    divTop:SetHeight(1)
    divTop:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -26)
    divTop:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -26)
    divTop:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: role selector dropdown
    local roleLabel = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleLabel:SetPoint("TOPLEFT", cf, "TOPLEFT", CONTENT_X + 4, -32)
    roleLabel:SetText("|cff8899BBRole:|r")

    roleDropdown = CreateFrame("Frame", "BWConfigRoleDropdown", cf, "UIDropDownMenuTemplate")
    roleDropdown:SetPoint("LEFT", roleLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(roleDropdown, 100)
    UIDropDownMenu_Initialize(roleDropdown, RoleDropdown_Initialize)
    UIDropDownMenu_SetSelectedValue(roleDropdown, selectedRole)

    -- Claude: spec overrides toggle button
    local specBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    specBtn:SetSize(110, 18)
    specBtn:SetPoint("LEFT", roleDropdown, "RIGHT", 0, 2)
    specBtn:SetText("Spec Overrides")

    local divRole = cf:CreateTexture(nil, "ARTWORK")
    divRole:SetHeight(1)
    divRole:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -58)
    divRole:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -58)
    divRole:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Claude: column headers
    local HDR_Y = -62
    local function MakeHdr(label, xOff, w, align)
        local fs = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", cf, "TOPLEFT", CONTENT_X + xOff, HDR_Y)
        fs:SetWidth(w)
        fs:SetJustifyH(align or "LEFT")
        fs:SetText("|cff8899BB" .. label .. "|r")
    end
    local hx = 0
    MakeHdr("|TInterface\\Buttons\\UI-CheckBox-Check:13:13|t", hx, CB_SIZE, "CENTER")
    hx = hx + CB_SIZE + COL_GAP
    MakeHdr("Buff Name",    hx, BUFF_W,  "LEFT")
    hx = hx + BUFF_W + COL_GAP
    MakeHdr("Output Label", hx, LABEL_W, "LEFT")

    local divHdr = cf:CreateTexture(nil, "ARTWORK")
    divHdr:SetHeight(1)
    divHdr:SetPoint("TOPLEFT",  cf, "TOPLEFT",  CONTENT_X, -76)
    divHdr:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -CONTENT_X, -76)
    divHdr:SetTexture(0.25, 0.45, 0.75, 0.25)

    -- Claude: bottom buttons
    local addBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 20)
    addBtn:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", CONTENT_X, 8)
    addBtn:SetText("Add Row")
    addBtn:SetScript("OnClick", function()
        local entries = GetCurrentEntries()
        tinsert(entries, { buff = "", label = "", enabled = true })
        RebuildConfig()
        if BW._cfgScroll then
            BW._cfgScroll:SetVerticalScroll(BW._cfgScroll:GetVerticalScrollRange())
        end
    end)

    local resetBtn = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 20)
    resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        -- Claude: inject role name into the confirmation dialog text
        StaticPopupDialogs["BUFFWATCHER_RESET_CONFIRM"].text =
            "Reset " .. selectedRole .. " entries to defaults?\nThis cannot be undone."
        StaticPopup_Show("BUFFWATCHER_RESET_CONFIRM")
    end)

    local divBot = cf:CreateTexture(nil, "ARTWORK")
    divBot:SetHeight(1)
    divBot:SetPoint("BOTTOMLEFT",  cf, "BOTTOMLEFT",  CONTENT_X,  32)
    divBot:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 32)
    divBot:SetTexture(0.25, 0.45, 0.75, 0.35)

    -- Claude: scroll frame for entry rows
    local sfm = CreateFrame("ScrollFrame", nil, cf)
    sfm:SetPoint("TOPLEFT",     cf, "TOPLEFT",     CONTENT_X, -78)
    sfm:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -CONTENT_X, 36)
    sfm:EnableMouseWheel(true)
    sfm:SetScript("OnMouseWheel", function(self, delta)
        local v   = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, v - delta * ROW_H * 3)))
    end)
    BW._cfgScroll = sfm

    local sc = CreateFrame("Frame", nil, sfm)
    sc:SetWidth(CFG_W - CONTENT_X * 2 - 14)
    sc:SetHeight(ROW_H)
    sfm:SetScrollChild(sc)
    scrollChild = sc

    -- Claude: spec overrides panel — shown/hidden by toggle button
    specBtn:SetScript("OnClick", function()
        if not specOverrideFrame then
            specOverrideFrame = CreateSpecOverrideFrame(cf)
            specOverrideFrame:SetPoint("TOPLEFT", cf, "TOPRIGHT", 4, 0)
        end
        if specOverrideFrame:IsShown() then
            specOverrideFrame:Hide()
        else
            specOverrideFrame:Show()
        end
    end)

    cf:SetScript("OnShow", function()
        RebuildConfig()
    end)
    cf:SetScript("OnHide", function()
        if specOverrideFrame then specOverrideFrame:Hide() end
    end)
end

-- ── Public entry point ───────────────────────────────────────────────────────

function BW:OpenConfig()
    if not self.configFrame then return end
    if self.configFrame:IsShown() then
        self.configFrame:Hide()
    else
        self.configFrame:Show()
    end
end
