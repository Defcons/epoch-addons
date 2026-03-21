if( not NotPlater ) then return end

local tgetn = table.getn
local tostring = tostring
local UnitGUID = UnitGUID
local UnitAffectingCombat = UnitAffectingCombat
local UnitInRaid = UnitInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitInParty = UnitInParty
local GetPartyMember = GetPartyMember
local UnitCanAttack = UnitCanAttack
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local MAX_PARTY_MEMBERS = MAX_PARTY_MEMBERS
local MAX_RAID_MEMBERS = MAX_RAID_MEMBERS
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local Threat = {}

function Threat:GetThreat(unit, mobUnit)
	if not unit or not mobUnit or not UnitExists(unit) or not UnitExists(mobUnit) then return nil end
	local isTanking, status, scaledPercent, rawPercent, threatValue = UnitDetailedThreatSituation(unit, mobUnit)
	return threatValue
end

function Threat:GetMaxThreatOnTarget(unit, group)
	local maxThreat = 0
	for gMember,unitId in pairs(group) do
		if unitId and unit and UnitExists(unitId) and UnitExists(unit) then
			local isTanking, status, scaledPercent, rawPercent, threatValue = UnitDetailedThreatSituation(unitId, unit)
			if threatValue and threatValue > maxThreat then
				maxThreat = threatValue
			end
		end
	end
	return maxThreat
end

local lastThreat = {}

function NotPlater:RAID_ROSTER_UPDATE()
	self.raid = nil
	if UnitInRaid("player") then
		self.raid = {}
		local raidNum = GetNumRaidMembers()
		local i = 1
		while raidNum > 0 and i <= MAX_RAID_MEMBERS do
			if GetRaidRosterInfo(i) then
				local guid = UnitGUID("raid" .. i)
				if guid then
					self.raid[guid] = "raid" .. i
				end
				local pet = UnitGUID("raidpet" .. i)
				if pet then
					self.raid[pet] = "raidpet" .. i
				end
				raidNum = raidNum - 1
			end
			i = i + 1
		end
	end
end

function NotPlater:PARTY_MEMBERS_CHANGED()
	self.party = {}
	if UnitInParty("party1") then
		local partyNum = GetNumPartyMembers()
		local i = 1
		while partyNum > 0 and i < MAX_PARTY_MEMBERS do
			if GetPartyMember(i) then
				local guid = UnitGUID("party" .. i)
				if guid then
					self.party[guid] = "party" .. i
				end
				local pet = UnitGUID("partypet" .. i)
				if pet then
					self.party[pet] = "partypet" .. i
				end
				partyNum = partyNum - 1
			end
			i = i + 1
		end
	end
	local playerGuid = UnitGUID("player")
	if playerGuid then
		self.party[playerGuid] = "player"
	end
	local pet = UnitGUID("pet")
	if pet then
		self.party[pet] = "pet"
	end
end

function NotPlater:OnNameplateMatch(healthFrame, group, ThreatLib)
	if not ThreatLib then ThreatLib = Threat end
	local threatConfig = self.db.profile.threat
	local unit = healthFrame.lastUnitMatch
	-- Use a stable GUID as the key for lastThreat so the High Threat trajectory
	-- condition can compare across successive calls to the same mob.
	local unitGuid = healthFrame.lastUnitGuid
	local playerThreat = ThreatLib:GetThreat("player", unit) or 0
	local playerThreatNumber = 1
	local highestThreat, highestThreatMember = ThreatLib:GetMaxThreatOnTarget(unit, group)
	local secondHighestThreat = 0
	-- Count group members properly (group is a hash table keyed by GUID)
	local groupSize = 0
	-- Solo correction: UnitDetailedThreatSituation for the pet may not return
	-- threat values when not in a party/raid, making highestThreat == playerThreat
	-- even when the pet actually holds aggro. Use the player's own status (0/1 =
	-- not tanking, 2/3 = tanking) to detect this and correct highestThreat.
	if not UnitInParty("party1") and not UnitInRaid("player") then
		local _, status = UnitDetailedThreatSituation("player", unit)
		if status ~= nil and status < 2 and playerThreat and playerThreat > 0 then
			highestThreat = playerThreat + 1
		end
	end
	if highestThreat and highestThreat > 0 then
		for gMember, gMemberUnitId in pairs(group) do
			groupSize = groupSize + 1
			local gMemberThreat = ThreatLib:GetThreat(gMemberUnitId, unit)
			if gMemberThreat then
				if gMemberThreat ~= highestThreat and gMemberThreat > secondHighestThreat then
					secondHighestThreat = gMemberThreat
				end

				if gMemberThreat > playerThreat then
					playerThreatNumber = playerThreatNumber + 1
				end
			end
		end

		local mode = threatConfig.general.mode
		if threatConfig.nameplateColors.general.enable or threatConfig.differentialText.general.enable then
			local barColorConfig, textColorConfig = threatConfig.nameplateColors.colors, threatConfig.differentialText.colors
			local barColor, textColor
			if mode == "hdps" then
				if highestThreat == playerThreat then
					barColor = barColorConfig[mode].c1
					textColor = textColorConfig[mode].c1
				elseif unitGuid and lastThreat[unitGuid] and highestThreat - (playerThreat + 3*(playerThreat - lastThreat[unitGuid])) < 0 then
					barColor = barColorConfig[mode].c2
					textColor = textColorConfig[mode].c2
				else
					barColor = barColorConfig[mode].c3
					textColor = textColorConfig[mode].c3
				end
			else -- "tank"
				if highestThreat == playerThreat then
					if unitGuid and lastThreat[unitGuid] and (playerThreat - 3*(playerThreat - lastThreat[unitGuid]) - secondHighestThreat) < 0 then
						barColor = barColorConfig[mode].c2
						textColor = textColorConfig[mode].c2
					else
						barColor = barColorConfig[mode].c1
						textColor = textColorConfig[mode].c1
					end
				else
					barColor = barColorConfig[mode].c3
					textColor = textColorConfig[mode].c3
				end
			end

			local frame = healthFrame:GetParent()
			if self.db.profile.threat.nameplateColors.general.useClassColors and frame.unitClass then
				healthFrame:SetStatusBarColor(frame.unitClass.r, frame.unitClass.g, frame.unitClass.b, 1)
			elseif threatConfig.nameplateColors.general.enable then
				healthFrame:SetStatusBarColor(self:GetColor(barColor))
			end

			if threatConfig.differentialText.general.enable then
				local threatDiff = 0
				if highestThreat == playerThreat then
					threatDiff = playerThreat - secondHighestThreat
				else
					threatDiff = highestThreat - playerThreat
				end

				healthFrame.threatDifferentialText:SetTextColor(self:GetColor(textColor))
				if threatDiff < 1000 then
					healthFrame.threatDifferentialText:SetFormattedText("%.0f", threatDiff)
				else
					threatDiff = threatDiff / 1000
					healthFrame.threatDifferentialText:SetFormattedText("%.1fk", threatDiff)
				end
				healthFrame.threatDifferentialText:Show()
			else
				healthFrame.threatDifferentialText:Hide()
			end
		end

		-- Number text
		local numberTextConfig = threatConfig.numberText
		if numberTextConfig.general.enable then
			local numberColor = nil
			if playerThreatNumber == 1 then
				numberColor = numberTextConfig.colors[mode].c1
			elseif groupSize > 1 and playerThreatNumber / (groupSize - 1) < 0.2 then
				numberColor = numberTextConfig.colors[mode].c2
			else
				numberColor = numberTextConfig.colors[mode].c3
			end
			healthFrame.threatNumberText:SetTextColor(self:GetColor(numberColor))
			healthFrame.threatNumberText:SetText(tostring(playerThreatNumber))
			healthFrame.threatNumberText:Show()
		else
			healthFrame.threatNumberText:Hide()
		end

		-- Percent bar
		local percentConfig = threatConfig.percent
		if percentConfig.statusBar.general.enable then
			local threatPercent, barColor = playerThreat/highestThreat * 100, nil
			if threatPercent >= 100 then
				barColor = percentConfig.statusBar.colors[mode].c1
			elseif threatPercent >= 90 then
				barColor = percentConfig.statusBar.colors[mode].c2
			else
				barColor = percentConfig.statusBar.colors[mode].c3
			end
			healthFrame.threatPercentBar:SetValue(threatPercent)
			barColor = percentConfig.statusBar.general.useThreatColors and barColor or percentConfig.statusBar.general.color
			healthFrame.threatPercentBar:SetStatusBarColor(self:GetColor(barColor))
			healthFrame.threatPercentBar:Show()
		else
			healthFrame.threatPercentBar:Hide()
		end

		-- Percent text
		if percentConfig.text.general.enable then
			local threatPercent, textColor = playerThreat/highestThreat * 100, nil
			if threatPercent >= 100 then
				textColor = percentConfig.text.colors[mode].c1
			elseif threatPercent >= 90 then
				textColor = percentConfig.text.colors[mode].c2
			else
				textColor = percentConfig.text.colors[mode].c3
			end
			healthFrame.threatPercentText:SetFormattedText("%d%%", threatPercent)
			textColor = percentConfig.text.general.useThreatColors and textColor or percentConfig.text.general.color
			healthFrame.threatPercentText:SetTextColor(self:GetColor(textColor))
			healthFrame.threatPercentText:Show()
		else
			healthFrame.threatPercentText:Hide()
		end

		if unitGuid then
			lastThreat[unitGuid] = playerThreat
		end
	end
end

function NotPlater:MouseoverThreatCheck(healthFrame, guid)
	local group = self.raid or self.party
	if group then
		healthFrame.lastUnitMatch = "mouseover"
		healthFrame.lastUnitGuid = guid
		self:OnNameplateMatch(healthFrame, group)
	else
		local frame = healthFrame:GetParent().unitClass
		if self.db.profile.threat.nameplateColors.general.useClassColors and frame.unitClass then
			healthFrame:SetStatusBarColor(frame.unitClass.r, frame.unitClass.g, frame.unitClass.b, 1)
		else
			if self.db.profile.healthBar.statusBar.general.enable then
				healthFrame:SetStatusBarColor(self:GetColor(self.db.profile.healthBar.statusBar.general.color))
			end
		end
	end
end

function NotPlater:ThreatCheck(frame)
	local nameText, levelText = select(7, frame:GetRegions())
	if not nameText or not levelText then return end
	local healthFrame = frame.healthBar
	local name = nameText:GetText()
	local level = levelText:GetText()
	local _, healthMaxValue = healthFrame:GetMinMaxValues()
    local healthValue = healthFrame:GetValue()
	local group = self.raid or self.party
	if group then
		if healthValue ~= healthMaxValue then
			for gMember,unitID in pairs(group) do
				local targetString = unitID .. "-target"
				if UnitCanAttack("player", targetString) and not UnitIsDeadOrGhost(targetString) and UnitAffectingCombat(targetString) then
					if name == UnitName(targetString) and level == tostring(UnitLevel(targetString)) and healthValue == UnitHealth(targetString) then
						healthFrame.lastUnitMatch = targetString
						healthFrame.lastUnitGuid = UnitGUID(targetString)
						break
					end
				end
			end
			if UnitCanAttack("player", "mouseover") and not UnitIsDeadOrGhost("mouseover") and UnitAffectingCombat("mouseover") then
				if name == UnitName("mouseover") and level == tostring(UnitLevel("mouseover")) and healthValue == UnitHealth("mouseover") then
					healthFrame.lastUnitMatch = "mouseover"
					healthFrame.lastUnitGuid = UnitGUID("mouseover")
				end
			end
			if UnitCanAttack("player", "focus") and not UnitIsDeadOrGhost("focus") and UnitAffectingCombat("focus") then
				if name == UnitName("focus") and level == tostring(UnitLevel("focus")) and healthValue == UnitHealth("focus") then
					healthFrame.lastUnitMatch = "focus"
					healthFrame.lastUnitGuid = UnitGUID("focus")
				end
			end
		end
		if healthFrame.lastUnitMatch then
			self:OnNameplateMatch(healthFrame, group)
		end
	else -- Not in party
		if UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target") and UnitAffectingCombat("target") then
			if name == UnitName("target") and level == tostring(UnitLevel("target")) and healthValue == UnitHealth("target") and healthValue ~= healthMaxValue then
				if self.db.profile.threat.nameplateColors.general.useClassColors and frame.unitClass then
					healthFrame:SetStatusBarColor(frame.unitClass.r, frame.unitClass.g, frame.unitClass.b, 1)
				else
					if self.db.profile.healthBar.statusBar.general.enable then
						healthFrame:SetStatusBarColor(self:GetColor(self.db.profile.healthBar.statusBar.general.color))
					end
				end
			end
		end
	end
end

function NotPlater:ScaleThreatComponents(healthFrame, isTarget)
	local scaleConfig = self.db.profile.target.general.scale
	if scaleConfig.threat then
		local threatConfig = self.db.profile.threat
		local scalingFactor = isTarget and scaleConfig.scalingFactor or 1
		self:ScaleGeneralisedStatusBar(healthFrame.threatPercentBar, scalingFactor, threatConfig.percent.statusBar)
		self:ScaleGeneralisedText(healthFrame.threatPercentText, scalingFactor, threatConfig.percent.text)
		self:ScaleGeneralisedText(healthFrame.threatDifferentialText, scalingFactor, threatConfig.differentialText)
		self:ScaleGeneralisedText(healthFrame.threatNumberText, scalingFactor, threatConfig.numberText)
	end
end

function NotPlater:ThreatComponentsOnShow(frame)
	local healthFrame = frame.healthBar
	-- Font strings crash on SetText if no font has been set yet (before
	-- ConfigureThreatComponents runs for the first time). Guard with GetFont().
	if healthFrame.threatDifferentialText:GetFont() then
		healthFrame.threatDifferentialText:SetText("")
		healthFrame.threatNumberText:SetText("")
		healthFrame.threatPercentText:SetText("")
	end
	healthFrame.threatPercentBar:Hide()
	healthFrame.lastUnitMatch = nil
	healthFrame.lastUnitGuid = nil
	self:ThreatCheck(frame)
end

function NotPlater:ConfigureThreatComponents(frame)
	local healthFrame = frame.healthBar
	local threatConfig = self.db.profile.threat
	-- Set differential text
	self:ConfigureGeneralisedText(healthFrame.threatDifferentialText, healthFrame, threatConfig.differentialText)

	-- Set number text
	self:ConfigureGeneralisedText(healthFrame.threatNumberText, healthFrame, threatConfig.numberText)

	-- Set percent text
	self:ConfigureGeneralisedText(healthFrame.threatPercentText, healthFrame.threatPercentBar, threatConfig.percent.text)

	-- Set percent bar
	self:ConfigureGeneralisedPositionedStatusBar(healthFrame.threatPercentBar, healthFrame, threatConfig.percent.statusBar)

	self:ThreatCheck(frame)
end

function NotPlater:ConstructThreatComponents(healthFrame)
	healthFrame:SetFrameLevel(healthFrame:GetParent():GetFrameLevel() + 1)

    -- Create threat text
    healthFrame.threatDifferentialText = healthFrame:CreateFontString(nil, "ARTWORK")
    healthFrame.threatNumberText = healthFrame:CreateFontString(nil, "ARTWORK")

	-- Percent text
    healthFrame.threatPercentText = healthFrame:CreateFontString(nil, "OVERLAY")

	-- Percent bar
    healthFrame.threatPercentBar = CreateFrame("StatusBar", nil, healthFrame)
	self:ConstructGeneralisedStatusBar(healthFrame.threatPercentBar)
    healthFrame.threatPercentBar:SetMinMaxValues(0, 100)
    healthFrame.threatPercentBar:SetFrameLevel(healthFrame:GetFrameLevel() - 1)
    healthFrame.threatPercentBar:Hide()
end