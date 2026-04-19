NotPlater = LibStub("AceAddon-3.0"):NewAddon("NotPlater", "AceEvent-3.0", "AceHook-3.0")
NotPlater.revision = "v2.0.6"

local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitHealth = UnitHealth
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local frames = {}

-- Claude: CLEU-fed class cache so enemy players show correct class colors
-- without needing target/mouseover/focus/group-target matching. Nameplates
-- don't expose GUIDs natively on 3.3.5, so we build a name→guid→class chain
-- from combat log events. Name collisions disable the name-lookup for that
-- name rather than returning wrong data.
local classByGuid = {}  -- guid → class token ("WARRIOR", "MAGE", ...)
local guidByName  = {}  -- player name → guid; set to false on ambiguity
local bit_band    = bit.band
local PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local GetPlayerInfoByGUID = GetPlayerInfoByGUID

local function RememberPlayer(guid, name, flags)
    if not guid or not name or not flags then return end
    if bit_band(flags, PLAYER_FLAG) == 0 then return end
    if not classByGuid[guid] then
        local _, class = GetPlayerInfoByGUID(guid)
        if class and RAID_CLASS_COLORS[class] then
            classByGuid[guid] = class
        end
    end
    local existing = guidByName[name]
    if existing == nil then
        guidByName[name] = guid
    elseif existing ~= guid and existing ~= false then
        guidByName[name] = false -- two different GUIDs for same name → disable
    end
end

NotPlater.frame = CreateFrame("Frame")
function NotPlater:OnInitialize()
	self:LoadDefaultConfig()

	self.db = LibStub:GetLibrary("AceDB-3.0"):New("NotPlaterDB", self.defaults)

	self:PARTY_MEMBERS_CHANGED()
	self:RAID_ROSTER_UPDATE()
	
	self:RegisterEvent("PARTY_MEMBERS_CHANGED")
	self:RegisterEvent("RAID_ROSTER_UPDATE")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- Claude: feed class-color cache
	self:Reload()

	self.SML = LibStub:GetLibrary("LibSharedMedia-3.0")
end

function NotPlater:IsTarget(frame)
    local targetExists = UnitExists('target')
    if not targetExists then
        return false
    end

	local nameText  = select(7,frame:GetRegions())
    local targetName = UnitName('target')

	return nameText and targetName == nameText:GetText() and frame:GetAlpha() >= 0.99
end

function NotPlater:PrepareFrame(frame)
	local threatGlow, healthBorder, castBorder, castNoStop, spellIcon, highlightTexture, nameText, levelText, dangerSkull, bossIcon, raidIcon = frame:GetRegions()
	local health, cast = frame:GetChildren()

	-- Hooks and creation (only once that way settings can be applied while frame is visible)
	if not frame.npHooked then
		frame.npHooked = true

		frame.nameText, frame.levelText, frame.bossIcon, frame.raidIcon = nameText, levelText, bossIcon, raidIcon
		frame.highlightTexture = frame:CreateTexture(nil, "ARTWORK")

		-- Hide default border
		healthBorder:Hide()
		threatGlow:SetTexCoord(0, 0, 0, 0)
		castNoStop:SetTexCoord(0, 0, 0, 0)
		dangerSkull:SetTexCoord(0, 0, 0, 0)
		highlightTexture:SetTexCoord(0, 0, 0, 0)


		-- Construct everything
		self:ConstructHealthBar(frame, health)
		self:ConstructThreatComponents(frame.healthBar)
		self:ConstructCastBar(frame)
		self:ConstructTarget(frame)

		-- Hide old healthbar
		health:Hide()
    
		self:HookScript(frame, "OnShow", function(self)
			self.unitClass = nil
			NotPlater:CastBarOnShow(self)
			NotPlater:HealthBarOnShow(health)
			NotPlater:StackingCheck(self)
			NotPlater:ThreatComponentsOnShow(self)
			NotPlater:TargetCheck(self)
			self.targetChanged = true
		end)

		self:HookScript(frame, 'OnUpdate', function(self, elapsed)
			if not self.targetCheckElapsed then self.targetCheckElapsed = 0 end
			self.targetCheckElapsed = self.targetCheckElapsed + elapsed
			if self.targetCheckElapsed >= 0.1 then
				if self.targetChanged then
					NotPlater:TargetCheck(self)
					self.targetChanged = nil
				end
				if NotPlater.db.profile.threat.nameplateColors.general.useClassColors then
					if not self.unitClass then
						NotPlater:ClassCheck(self)
					end
					if self.unitClass then
						frame.healthBar:SetStatusBarColor(self.unitClass.r, self.unitClass.g, self.unitClass.b, 1)
					end
				end
				NotPlater:SetTargetTargetText(self)
				self.targetCheckElapsed = 0
			end
			if NotPlater:IsTarget(self) then
				self:SetAlpha(1)
			else
				if NotPlater.db.profile.target.general.nonTargetAlpha.enable then
					self:SetAlpha(NotPlater.db.profile.target.general.nonTargetAlpha.opacity)
				end
			end
			if NotPlater.db.profile.levelText.general.enable then
				levelText:Show()
				levelText:SetAlpha(NotPlater.db.profile.levelText.general.opacity)
			else
				levelText:Hide()
			end
		end)
	end
	
	-- Configure everything
	self:ConfigureThreatComponents(frame)
	self:ConfigureHealthBar(frame, health)
	self:ConfigureCastBar(frame)
	self:ConfigureStacking(frame)
	self:ConfigureGeneralisedIcon(bossIcon, frame.healthBar, self.db.profile.bossIcon)
	self:ConfigureGeneralisedIcon(raidIcon, frame.healthBar, self.db.profile.raidIcon)
	self:ConfigureLevelText(levelText, frame.healthBar)
	self:ConfigureNameText(nameText, frame.healthBar)
	self:ConfigureTarget(frame)
	self:TargetCheck(frame)
end

function NotPlater:HookFrames(...)
	for i=1, select("#", ...) do
		local frame = select(i, ...)
		local region = frame:GetRegions()
		if( not frames[frame] and not frame:GetName() and region and region:GetObjectType() == "Texture" and region:GetTexture() == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash" ) then
			frames[frame] = true
			self:PrepareFrame(frame)
		end
	end
end

function NotPlater:Reload()
	if self.db.profile.castBar.statusBar.general.enable then
		self:RegisterCastBarEvents(NotPlater.frame)
	else
		self:UnregisterCastBarEvents(NotPlater.frame)
	end

	if self.db.profile.threat.general.enableMouseoverUpdate then
		self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	else
		self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	end

	for frame in pairs(frames) do
		self:PrepareFrame(frame)
	end
end

function NotPlater:PLAYER_TARGET_CHANGED()
	for frame in pairs(frames) do
		frame.targetChanged = true
	end
end

-- Claude: feed classByGuid / guidByName on every combat event so enemy
-- players can be class-colored without needing a target/mouseover. Early
-- bail in RememberPlayer keeps the per-event cost to a couple of bit.bands.
function NotPlater:COMBAT_LOG_EVENT_UNFILTERED(event, _, _, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags)
	RememberPlayer(srcGUID, srcName, srcFlags)
	RememberPlayer(dstGUID, dstName, dstFlags)
end

function NotPlater:ClassCheck(frame)
	if frame.unitClass then return end

	if self:IsTarget(frame) then
		frame.unitClass = select(2, UnitClass("target"))
		if frame.unitClass then frame.unitClass = RAID_CLASS_COLORS[frame.unitClass] end
		return
	end

	local nameText, levelText = select(7, frame:GetRegions())
	local name = nameText:GetText()
	local level = levelText:GetText()
	--local _, healthMaxValue = frame.healthBar:GetMinMaxValues()
	local healthValue = frame.healthBar:GetValue()
	local group = self.raid or self.party
	if group then
		for gMember,unitID in pairs(group) do
			local targetString = unitID .. "-target"
			if name == UnitName(targetString) and level == tostring(UnitLevel(targetString)) and healthValue == UnitHealth(targetString) then
				frame.unitClass = select(2, UnitClass(targetString)) -- Claude: was UnitClass("target") — read from matching unit, not player's target
				if frame.unitClass then frame.unitClass = RAID_CLASS_COLORS[frame.unitClass] end
				return
			end
		end
	end
	if name == UnitName("mouseover") and level == tostring(UnitLevel("mouseover")) and healthValue == UnitHealth("mouseover") then
		frame.unitClass = select(2, UnitClass("mouseover"))
		if frame.unitClass then frame.unitClass = RAID_CLASS_COLORS[frame.unitClass] end
		return
	end
	if name == UnitName("focus") and level == tostring(UnitLevel("focus")) and healthValue == UnitHealth("focus") then
		frame.unitClass = select(2, UnitClass("focus"))
		if frame.unitClass then frame.unitClass = RAID_CLASS_COLORS[frame.unitClass] end
		return
	end

	-- Claude: CLEU-based fallback. Resolves class for any enemy player that
	-- has been in our combat log range, even if we've never targeted them.
	local cachedGuid = guidByName[name]
	if cachedGuid and classByGuid[cachedGuid] then
		frame.unitClass = RAID_CLASS_COLORS[classByGuid[cachedGuid]]
	end
end

function NotPlater:UPDATE_MOUSEOVER_UNIT()
	if UnitCanAttack("player", "mouseover") and not UnitIsDeadOrGhost("mouseover") and UnitAffectingCombat("mouseover") then
		local mouseOverGuid = UnitGUID("mouseover")
		local targetGuid = UnitGUID("target")
		for frame in pairs(frames) do
			if frame:IsShown() then
				if mouseOverGuid == targetGuid then
					if self:IsTarget(frame) then
						self:MouseoverThreatCheck(frame.healthBar, targetGuid)
						frame.highlightTexture:Show()
					end
				else
					local nameText, levelText = select(7, frame:GetRegions())
					local name = nameText:GetText()
					local level = levelText:GetText()
					local _, healthMaxValue = frame.healthBar:GetMinMaxValues()
					local healthValue = frame.healthBar:GetValue()
					if name == UnitName("mouseover") and level == tostring(UnitLevel("mouseover")) and healthValue == UnitHealth("mouseover") and healthValue ~= healthMaxValue then
						self:MouseoverThreatCheck(frame.healthBar, mouseOverGuid)
					end
				end
			end
		end
	end
end

local numChildren = -1
NotPlater.frame:SetScript("OnUpdate", function(self, elapsed)
	if(WorldFrame:GetNumChildren() ~= numChildren) then
		numChildren = WorldFrame:GetNumChildren()
		NotPlater:HookFrames(WorldFrame:GetChildren())
	end
end)

NotPlater.frame:SetScript("OnEvent", function(self, event, unit)
	for frame in pairs(frames) do
		if frame:IsShown() then
			if unit == "target" then
				if NotPlater:IsTarget(frame) then
					frame.healthBar.lastUnitMatch = "target"
					NotPlater:CastBarOnCast(frame, event, unit)
				end
			else
				local nameText, levelText = select(7, frame:GetRegions())
				local name = nameText:GetText()
				local level = levelText:GetText()
				local _, healthMaxValue = frame.healthBar:GetMinMaxValues()
				local healthValue = frame.healthBar:GetValue()
				if name == UnitName(unit) and level == tostring(UnitLevel(unit)) and healthValue == UnitHealth(unit) and healthValue ~= healthMaxValue then
					frame.healthBar.lastUnitMatch = unit
					NotPlater:CastBarOnCast(frame, event, unit)
				end
			end
		end
	end
end)