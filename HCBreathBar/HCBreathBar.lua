-- [[ CONFIGURATION SETTINGS -- START ]]

local PLAY_SOUND_INTERVAL = 0.8   -- seconds between beeps at normal threshold
local SOUND_FILE      = "Sound\\Interface\\AlarmClockWarning1.wav"  -- PlaySoundFile path
local SOUND_THRESHOLD = 20        -- seconds remaining when alerts begin
local BAR_WIDTH       = 420       -- bar width in pixels
local BAR_HEIGHT      = 14        -- bar height in pixels

-- [[ CONFIGURATION SETTINGS -- END ]]

local BAR_R, BAR_G, BAR_B = 0.20, 0.65, 1.0

-- ── Custom breath bar ──────────────────────────────────────────────────────
local customFrame = CreateFrame("Frame", "HCBreathBarCustom", UIParent)
customFrame:SetWidth(BAR_WIDTH)
customFrame:SetHeight(BAR_HEIGHT)
customFrame:Hide()

local bg = customFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(customFrame)
bg:SetTexture(0.04, 0.04, 0.04)
bg:SetAlpha(0.70)

local customBar = CreateFrame("StatusBar", nil, customFrame)
customBar:SetAllPoints(customFrame)
customBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
customBar:SetStatusBarColor(BAR_R, BAR_G, BAR_B)
customBar:SetMinMaxValues(0, 180)
customBar:SetValue(180)

local customText = customBar:CreateFontString(nil, "OVERLAY")
customText:SetFont("Fonts\\FRIZQT__.ttf", 13, "THICKOUTLINE")  -- Claude: FRIZQT__ bold + thick outline for contrast against the fill
customText:SetTextColor(1, 1, 1)
customText:SetAllPoints(customFrame)
customText:SetJustifyH("CENTER")
customText:SetJustifyV("MIDDLE")

-- ── Combat spacebar-warning overlay ───────────────────────────────────────
local alert = CreateFrame("Frame", nil, UIParent)
alert:SetWidth(1)
alert:SetHeight(1)
alert:SetPoint("TOP", 0, -50)
alert.text = alert:CreateFontString(nil, "ARTWORK")
alert.text:SetFont("Fonts\\ARIALN.ttf", 18, "OUTLINE")
alert.text:SetText("Do NOT use SPACEBAR to surface.")
alert.text:SetPoint("CENTER", 0, 0)
alert:Hide()

-- ── Shared state ───────────────────────────────────────────────────────────
local breathSource   = nil   -- MirrorTimer frame currently showing BREATH
local breathMaxValue = 180   -- updated from MIRROR_TIMER_START; defaults to 3 min

local function onBreathStop()
    if breathSource then
        breathSource:SetAlpha(1)
        breathSource = nil
    end
    customFrame:Hide()
    alert:Hide()
end

-- ── Capture actual breath max from the start event ────────────────────────
-- MIRROR_TIMER_START args: timerType, value, maxValue, scale, paused, label
-- In 3.3.5 maxValue may be in ms; normalise if it looks like ms (> 600).
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("MIRROR_TIMER_START")
eventFrame:RegisterEvent("MIRROR_TIMER_STOP")
eventFrame:SetScript("OnEvent", function(self, event, timerType, value, maxValue)
    if event == "MIRROR_TIMER_START" and timerType == "BREATH" then
        -- Claude: normalise ms→s if value looks like milliseconds
        local max = (maxValue and maxValue > 600) and (maxValue / 1000) or (maxValue or 180)
        breathMaxValue = max
        customBar:SetMinMaxValues(0, breathMaxValue)
    elseif event == "MIRROR_TIMER_STOP" then
        onBreathStop()
    end
end)

-- ── Hook each MirrorTimer frame ────────────────────────────────────────────
for index = 1, MIRRORTIMER_NUMTIMERS do
    local frame = _G["MirrorTimer" .. index]
    local lastPlayedSound = 0

    frame:HookScript("OnUpdate", function(self)
        if self.timer ~= "BREATH" then
            if breathSource == self then onBreathStop() end
            return
        end

        -- First detection: hide original, position and show our bar
        if breathSource ~= self then
            breathSource = self
            self:SetAlpha(0)
            customFrame:ClearAllPoints()
            customFrame:SetPoint("CENTER", self, "CENTER")
            customBar:SetMinMaxValues(0, breathMaxValue)
            customFrame:Show()
        end

        -- Update fill and countdown label
        customBar:SetValue(self.value)
        local Min = math.floor(self.value / 60)
        local Sec = math.floor(self.value - Min * 60)
        customText:SetText(string.format("Breath  %d:%02d", Min, Sec))

        if InCombatLockdown() then alert:Show() end

        -- Sound alerts — double rate in final half of threshold
        if self.value < SOUND_THRESHOLD / 2 then
            if GetTime() - lastPlayedSound > PLAY_SOUND_INTERVAL / 2 then
                PlaySoundFile(SOUND_FILE)  -- Claude: use PlaySoundFile for 3.3.5 compatibility
                lastPlayedSound = GetTime()
            end
        elseif self.value < SOUND_THRESHOLD then
            if GetTime() - lastPlayedSound > PLAY_SOUND_INTERVAL then
                PlaySoundFile(SOUND_FILE)
                lastPlayedSound = GetTime()
            end
        end
    end)
end
