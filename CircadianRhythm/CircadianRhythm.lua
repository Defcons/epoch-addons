local addonName = "CircadianRhythm"
local settings = {}

if CircadianRhythmSettings then
    settings = CircadianRhythmSettings
else
    settings = {
        showGameTimeOnHover = true,
        use12HourFormat = true,
        showButton = true,
        buttonLocked = false,
        buttonPosition = { point = "CENTER", x = 0, y = 0 },
        showLockIcon = true,
    }
end

local function SaveSettings()
    CircadianRhythmSettings = settings
end

local button = CreateFrame("Button", "MyGameTimeButton", UIParent)
button:SetSize(40, 40)
button:SetPoint("CENTER", 0, 0)
button:SetMovable(true)
button:EnableMouse(true)
button:RegisterForClicks("AnyUp")

local texture = button:CreateTexture(nil, "BACKGROUND")
texture:SetAllPoints(button)

local lockTexture = button:CreateTexture(nil, "OVERLAY")
lockTexture:SetSize(12, 12)
lockTexture:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
lockTexture:SetTexture("Interface\\Icons\\inv_misc_key_03")
lockTexture:SetAlpha(0.7)
lockTexture:Hide()

local function SavePosition()
    local point, _, _, x, y = button:GetPoint()
    if point then
        settings.buttonPosition = { point = point, x = x or 0, y = y or 0 }
        SaveSettings()
    end
end

local function RestorePosition()
    if settings.buttonPosition and settings.buttonPosition.point then
        button:ClearAllPoints()
        button:SetPoint(settings.buttonPosition.point, UIParent, settings.buttonPosition.point,
                       settings.buttonPosition.x or 0, settings.buttonPosition.y or 0)
    else
        button:ClearAllPoints()
        button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function UpdateLockVisual()
    if settings.buttonLocked then
        button:SetMovable(false)
        button:EnableMouse(true)
        if settings.showLockIcon then
            lockTexture:Show()
        else
            lockTexture:Hide()
        end
    else
        button:SetMovable(true)
        button:EnableMouse(true)
        lockTexture:Hide()
    end
end

local function ConvertTo12HourFormat(hour)
    local ampm = "AM"
    if hour >= 12 and hour < 24 then
        ampm = "PM"
    end
    if hour == 0 or hour == 24 then
        hour = 12
    else
        hour = hour % 12
        if hour == 0 then
            hour = 12
        end
    end
    return hour, ampm
end

local function UpdateGameTimeTexture()
    local fake_hour = _G['EPOCH_GAME_TIME_HUMAN']
    if fake_hour then
        local texturePath
        if fake_hour == "Morning" or fake_hour == "Noon" or fake_hour == "Afternoon" or fake_hour == "Evening" then
            texturePath = "Interface\\AddOns\\" .. addonName .. "\\images\\day"
        elseif fake_hour == "Night" or fake_hour == "Midnight" or fake_hour == "Late Night" then
            texturePath = "Interface\\AddOns\\" .. addonName .. "\\images\\night"
        else
            texturePath = "Interface\\Icons\\inv_misc_gem_amethyst_02"
        end

        texture:SetTexture(texturePath)
    end
end

local function OnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed >= 1 then
        UpdateGameTimeTexture()
        self.elapsed = 0
    end
end

local function OnEnter()
    if not settings.showGameTimeOnHover then return end

    local tooltipTitle = _G['EPOCH_GAME_TIME_HUMAN'] or "Game Time"
    local hour = _G['EPOCH_GAME_TIME'] or 0
    local displayTime

    if settings.use12HourFormat then
        local hour12, ampm = ConvertTo12HourFormat(hour)
        displayTime = hour12 .. " " .. ampm
    else
        displayTime = hour .. " hours"
    end

    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:AddLine("|TInterface\\Icons\\inv_misc_pocketwatch_01:16|t |cffFFD700" .. tooltipTitle .. "|r", 1, 1, 1)
    GameTooltip:AddLine("|cFF87CEFACurrent Time: |r" .. displayTime, 0.7, 0.7, 0.9)

    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

local isDragging = false
local mouseDownTime = 0

local function OnMouseDown(self, buttonClick)
    if buttonClick == "LeftButton" and not settings.buttonLocked then
        isDragging = false
        mouseDownTime = GetTime()
        self:StartMoving()
    end
end

local function OnMouseUp(self, buttonClick)
    if buttonClick == "LeftButton" and not settings.buttonLocked then
        self:StopMovingOrSizing()

        local holdTime = GetTime() - mouseDownTime
        if holdTime > 0.15 then
            isDragging = true
        else
            isDragging = false
        end

        SavePosition()
    end
end

local function OnClick(self, clickButton)
    if clickButton == "LeftButton" and isDragging then
        isDragging = false
        return
    end

    if clickButton == "LeftButton" then
        ToggleCalendar()
    elseif clickButton == "RightButton" then
        SavePosition()
        settings.buttonLocked = not settings.buttonLocked
        SaveSettings()
        UpdateLockVisual()
    end
end

function GameTime_UpdateTooltip()
    GameTooltip:AddLine(TIMEMANAGER_TOOLTIP_TITLE, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)

    GameTooltip:AddDoubleLine(
        "Game Time:",
        _G['EPOCH_GAME_TIME_HUMAN'],
        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
    )

    local hour = _G['EPOCH_GAME_TIME'] or 0
    local displayTime

    if settings.use12HourFormat then
        local hour12, ampm = ConvertTo12HourFormat(hour)
        displayTime = hour12 .. " " .. ampm
    else
        displayTime = hour .. ":00"
    end

    GameTooltip:AddDoubleLine(
        "Epoch Time:",
        displayTime,
        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
    )

    GameTooltip:AddDoubleLine(
        TIMEMANAGER_TOOLTIP_REALMTIME,
        GameTime_GetGameTime(true),
        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
    )

    GameTooltip:AddDoubleLine(
        TIMEMANAGER_TOOLTIP_LOCALTIME,
        GameTime_GetLocalTime(true),
        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b
    )
end

local optionsPanel = CreateFrame("Frame", addonName .. "OptionsPanel", UIParent)
optionsPanel.name = addonName
InterfaceOptions_AddCategory(optionsPanel)

local hoverCheckbox = CreateFrame("CheckButton", addonName .. "ShowHoverCheckbox", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
hoverCheckbox:SetPoint("TOPLEFT", 16, -16)

local hoverLabel = hoverCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
hoverLabel:SetPoint("LEFT", hoverCheckbox, "RIGHT", 4, 0)
hoverLabel:SetText("Show Game Time on Hover")

hoverCheckbox:SetChecked(settings.showGameTimeOnHover)
hoverCheckbox:SetScript("OnClick", function(self)
    settings.showGameTimeOnHover = self:GetChecked()
    SaveSettings()
end)

local formatCheckbox = CreateFrame("CheckButton", addonName .. "Use12HourFormatCheckbox", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
formatCheckbox:SetPoint("TOPLEFT", hoverCheckbox, "BOTTOMLEFT", 0, -8)

local formatLabel = formatCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
formatLabel:SetPoint("LEFT", formatCheckbox, "RIGHT", 4, 0)
formatLabel:SetText("Use AM/PM Format")

formatCheckbox:SetChecked(settings.use12HourFormat)
formatCheckbox:SetScript("OnClick", function(self)
    settings.use12HourFormat = self:GetChecked()
    SaveSettings()
end)

local buttonCheckbox = CreateFrame("CheckButton", addonName .. "ShowButtonCheckbox", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
buttonCheckbox:SetPoint("TOPLEFT", formatCheckbox, "BOTTOMLEFT", 0, -8)

local buttonLabel = buttonCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
buttonLabel:SetPoint("LEFT", buttonCheckbox, "RIGHT", 4, 0)
buttonLabel:SetText("Show Game Time Graphic")

buttonCheckbox:SetChecked(settings.showButton)
buttonCheckbox:SetScript("OnClick", function(self)
    settings.showButton = self:GetChecked()
    SaveSettings()
    if settings.showButton then
        button:Show()
    else
        button:Hide()
    end
end)

local lockCheckbox = CreateFrame("CheckButton", addonName .. "ButtonLockedCheckbox", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
lockCheckbox:SetPoint("TOPLEFT", buttonCheckbox, "BOTTOMLEFT", 0, -8)

local lockLabel = lockCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lockLabel:SetPoint("LEFT", lockCheckbox, "RIGHT", 4, 0)
lockLabel:SetText("Lock Button Position")

lockCheckbox:SetChecked(settings.buttonLocked)
lockCheckbox:SetScript("OnClick", function(self)
    settings.buttonLocked = self:GetChecked()
    SaveSettings()
    UpdateLockVisual()
end)

local lockIconCheckbox = CreateFrame("CheckButton", addonName .. "ShowLockIconCheckbox", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
lockIconCheckbox:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -8)

local lockIconLabel = lockIconCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lockIconLabel:SetPoint("LEFT", lockIconCheckbox, "RIGHT", 4, 0)
lockIconLabel:SetText("Show Lock Icon")

lockIconCheckbox:SetChecked(settings.showLockIcon)
lockIconCheckbox:SetScript("OnClick", function(self)
    settings.showLockIcon = self:GetChecked()
    SaveSettings()
    UpdateLockVisual()
end)

local instructionsText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
instructionsText:SetPoint("TOPLEFT", lockIconCheckbox, "BOTTOMLEFT", 0, -20)
instructionsText:SetText("Instructions:\n• Left-click the button to open Calendar\n• Right-click the button to toggle lock/unlock\n• Drag the button to move it (when unlocked)")
instructionsText:SetTextColor(0.8, 0.8, 0.8)

button:RegisterEvent("ADDON_LOADED")

button:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == addonName then
        if CircadianRhythmSettings then
            settings = CircadianRhythmSettings
        else
            settings = {
                showGameTimeOnHover = true,
                use12HourFormat = true,
                showButton = true,
                buttonLocked = false,
                buttonPosition = { point = "CENTER", x = 0, y = 0 },
                showLockIcon = true,
            }
        end

        if not settings.buttonPosition then
            settings.buttonPosition = { point = "CENTER", x = 0, y = 0 }
        end

        if settings.showLockIcon == nil then
            settings.showLockIcon = true
        end

        hoverCheckbox:SetChecked(settings.showGameTimeOnHover)
        formatCheckbox:SetChecked(settings.use12HourFormat)
        buttonCheckbox:SetChecked(settings.showButton)
        lockCheckbox:SetChecked(settings.buttonLocked)
        lockIconCheckbox:SetChecked(settings.showLockIcon)

        self:SetScript("OnUpdate", OnUpdate)
        self:SetScript("OnEnter", OnEnter)
        self:SetScript("OnLeave", OnLeave)
        self:SetScript("OnMouseDown", OnMouseDown)
        self:SetScript("OnMouseUp", OnMouseUp)
        self:SetScript("OnClick", OnClick)

        if settings.showButton then
            button:Show()
            RestorePosition()
        else
            button:Hide()
        end

        UpdateLockVisual()

        UpdateGameTimeTexture()
    end
end)

local function HookElvUITimeTooltip()
    if ElvUI and ElvUI:GetModule("DataTexts") then
        local dataText = ElvUI:GetModule("DataTexts"):GetDataText("Time")

        if dataText and dataText.OnEnter then
            local originalOnEnter = dataText.OnEnter
            dataText.OnEnter = function(self)
                originalOnEnter(self)
                GameTime_UpdateTooltip()
                GameTooltip:Show()
            end
        end
    end
end

HookElvUITimeTooltip()