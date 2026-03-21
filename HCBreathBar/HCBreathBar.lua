-- [[ CONFIGURATION SETTINGS -- START ]]

local PLAY_SOUND_INTERVAL = 0.8      -- seconds between sounds at normal threshold
local SOUND_FILE      = "igQuestComplete"  -- 3.3.5 sound name
local SOUND_THRESHOLD = 20           -- seconds remaining when alerts begin
local BAR_WIDTH       = 420          -- bar width in pixels
local BAR_HEIGHT      = 14           -- bar height in pixels

-- [[ CONFIGURATION SETTINGS -- END ]]

local BAR_R, BAR_G, BAR_B = 0.20, 0.65, 1.0

-- ── Custom breath bar ──────────────────────────────────────────────────────
-- We hide the original MirrorTimer frame and replace it with this one so we
-- have full control over its look without fighting the default backdrop/border.

local customFrame = CreateFrame("Frame", "HCBreathBarCustom", UIParent)
customFrame:SetWidth(BAR_WIDTH)
customFrame:SetHeight(BAR_HEIGHT)
customFrame:Hide()

-- Dark trough (unfilled portion)
local bg = customFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(customFrame)
bg:SetTexture(0.04, 0.04, 0.04)
bg:SetAlpha(0.70)

-- The actual fill bar
local customBar = CreateFrame("StatusBar", nil, customFrame)
customBar:SetAllPoints(customFrame)
customBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
customBar:SetStatusBarColor(BAR_R, BAR_G, BAR_B)
customBar:SetMinMaxValues(0, 1)
customBar:SetValue(1)

-- Countdown label
local customText = customBar:CreateFontString(nil, "OVERLAY")
customText:SetFont("Fonts\\ARIALN.ttf", 11, "OUTLINE")
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
local breathSource = nil  -- whichever MirrorTimer frame is currently BREATH

local function onBreathStop()
    if breathSource then
        breathSource:SetAlpha(1)   -- restore original frame
        breathSource = nil
    end
    customFrame:Hide()
    alert:Hide()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("MIRROR_TIMER_STOP")
eventFrame:SetScript("OnEvent", function() onBreathStop() end)

-- ── Hook each MirrorTimer frame ────────────────────────────────────────────
for index = 1, MIRRORTIMER_NUMTIMERS do
    local frame = _G["MirrorTimer" .. index]
    local lastPlayedSound = 0

    frame:HookScript("OnUpdate", function(self)
        if self.timer ~= "BREATH" then
            if breathSource == self then onBreathStop() end
            return
        end

        -- On first detection: hide original, snap our bar into position
        if breathSource ~= self then
            breathSource = self
            self:SetAlpha(0)
            customFrame:ClearAllPoints()
            customFrame:SetPoint("CENTER", self, "CENTER")
            customBar:SetMinMaxValues(0, self.maxValue or 180)
            customFrame:Show()
        end

        -- Update fill and label
        customBar:SetValue(self.value)
        local Min = math.floor(self.value / 60)
        local Sec = math.floor(self.value - Min * 60)
        customText:SetText(string.format("Breath  %d:%02d", Min, Sec))

        if InCombatLockdown() then alert:Show() end

        -- Sound alerts
        if self.value < SOUND_THRESHOLD / 2 then
            if GetTime() - lastPlayedSound > PLAY_SOUND_INTERVAL / 2 then
                PlaySound(SOUND_FILE)
                lastPlayedSound = GetTime()
            end
        elseif self.value < SOUND_THRESHOLD then
            if GetTime() - lastPlayedSound > PLAY_SOUND_INTERVAL then
                PlaySound(SOUND_FILE)
                lastPlayedSound = GetTime()
            end
        end
    end)
end
