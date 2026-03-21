local mod	= DBM:NewMod("Onyxia", "DBM-Onyxia")
local L		= mod:GetLocalizedStrings()

local ONYXIA_CID = 45133

local FLAME_BREATH_ID = 18435
local FLAME_BREATH_CD = 13.3

local DEEP_BREATH_ID = 18584
-- local DEEP_BREATH_CD = 33
local DEEP_BREATH_CAST_TIME = 4

local FIREBALL_ID = 18392

mod:SetRevision("20260103175316")
mod:SetCreatureID(45133)
mod:RegisterCombat("combat")
mod:SetUsedIcons(8)

mod:RegisterEventsInCombat(
	"SPELL_CAST_START 18435 18392 18351 17086 18564 18576 18584 18596 18609 18617",
	"CHAT_MSG_MONSTER_YELL",
	"UNIT_HEALTH"
)

local groundPhasePreWarn	= mod:NewPrePhaseAnnounce(1)
local groundPhaseWarn		= mod:NewPhaseAnnounce(1)
local flyPhasePreWarn		= mod:NewPrePhaseAnnounce(2)
local flyPhaseWarn			= mod:NewPhaseAnnounce(2)

local flameBreathCD			= mod:NewCDTimer(FLAME_BREATH_CD, FLAME_BREATH_ID, nil, nil, nil, 5)

-- local deepBreathCD			= mod:NewCDTimer(DEEP_BREATH_CD, DEEP_BREATH_ID, nil, nil, nil, 2)
local deepBreathWarn		= mod:NewSpecialWarningSpell(DEEP_BREATH_ID, nil, nil, nil, 2, 2)
local deepBreathCastTimer	= mod:NewCastTimer(DEEP_BREATH_CAST_TIME, DEEP_BREATH_ID, nil, nil, nil, 2)

local fireballWarn			= mod:NewTargetNoFilterAnnounce(FIREBALL_ID, 2, nil, false)
local fireballYell			= mod:NewYell(FIREBALL_ID)

mod.vb.WarnedFly1 = false
mod.vb.WarnedFly2 = false
mod.vb.WarnedLand1 = false
mod.vb.WarnedLand2 = false

mod:AddSetIconOption("SetIconOnFireball", FIREBALL_ID, true, false, {8})

local function IsPhaseYell(msg, phrase)
	return msg == phrase or msg:find(phrase)
end

function mod:FireballTargetScanner(guid)
	self:BossTargetScanner(guid, "FireballTarget", 0.2, 6)
end

function mod:FireballTarget(targetName)
	if not targetName then return end

	fireballWarn:Show(targetName)

	if self.Options.SetIconOnFireball then
		self:SetIcon(targetName, 8, 3)
	end

	if targetName == UnitName("player") then
		fireballYell:Yell()
	end
end

function mod:OnCombatStart()
	flameBreathCD:Start()
	self:SetStage(1)
	self.vb.WarnedFly1 = false
	self.vb.WarnedFly2 = false
	self.vb.WarnedLand1 = false
	self.vb.WarnedLand2 = false
end

function mod:SPELL_CAST_START(args)
	if args.spellId == FLAME_BREATH_ID then
		flameBreathCD:Start()
	-- One for each direction
	elseif args:IsSpellID(18351, 17086, 18564, 18576, 18584, 18596, 18609, 18617) then
		deepBreathWarn:Show()
		deepBreathWarn:Play("breathsoon")
		deepBreathCastTimer:Start()
		-- deepBreathCD:Start()
	elseif args.spellId == FIREBALL_ID then
		self:SendSync("Fireball", args.sourceGUID)
		if self:AntiSpam(2, 1) then
			self:ScheduleMethod(0.15, "FireballTargetScanner", args.sourceGUID)
		end
	end
end

function mod:CHAT_MSG_MONSTER_YELL(msg)
	if IsPhaseYell(msg, L.YellP2_1) or IsPhaseYell(msg, L.YellP2_2) or IsPhaseYell(msg, L.YellP2_3) then
		self:SendSync("Phase2")
	elseif IsPhaseYell(msg, L.YellP1_1) or IsPhaseYell(msg, L.YellP1_2) or IsPhaseYell(msg, L.YellP1_3) then
		self:SendSync("Phase1")
	end
end

function mod:UNIT_HEALTH(uId)
	local cId = self:GetUnitCreatureId(uId)
	if cId ~= ONYXIA_CID then
		return
	end

	if not self.vb.WarnedFly1 and UnitHealth(uId) / UnitHealthMax(uId) <= 0.86 then
		self:SendSync("PrePhase2")
	end

	if not self.vb.WarnedFly2 and UnitHealth(uId) / UnitHealthMax(uId) <= 0.46 then
		self:SendSync("PrePhase2_2")
	end

	if not self.vb.WarnedLand1 and UnitHealth(uId) / UnitHealthMax(uId) <= 0.65 then
		self:SendSync("PrePhase1")
	end

	if not self.vb.WarnedLand2 and UnitHealth(uId) / UnitHealthMax(uId) <= 0.25 then
		self:SendSync("PrePhase1_2")
	end
end

function mod:OnSync(msg, guid, sender)
	if not self:IsInCombat() then return end

	if msg == "PrePhase2" then
		if not self.vb.WarnedFly1 then
			self.vb.WarnedFly1 = true
			flyPhasePreWarn:Show()
		end
	elseif msg == "PrePhase2_2" then
		if not self.vb.WarnedFly2 then
			self.vb.WarnedFly2 = true
			flyPhasePreWarn:Show()
		end
	elseif msg == "PrePhase1" then
		if not self.vb.WarnedLand1 then
			self.vb.WarnedLand1 = true
			groundPhasePreWarn:Show()
		end
	elseif msg == "PrePhase1_2" then
		if not self.vb.WarnedLand2 then
			self.vb.WarnedLand2 = true
			groundPhasePreWarn:Show()
		end
	elseif msg == "Phase2" then
		self:SetStage(2)
		if not self.vb.WarnedFly1 then
			self.vb.WarnedFly1 = true
		elseif not self.vb.WarnedFly2 then
			self.vb.WarnedFly2 = true
		end
		flyPhaseWarn:Show()
		flameBreathCD:Stop()
		-- deepBreathCD:Start()
	elseif msg == "Phase1" then
		self:SetStage(1)
		if not self.vb.WarnedLand1 then
			self.vb.WarnedLand1 = true
		elseif not self.vb.WarnedLand2 then
			self.vb.WarnedLand2 = true
		end
		groundPhaseWarn:Show()
		-- deepBreathCD:Stop()
	elseif msg == "Fireball" and sender and self:AntiSpam(2, 1) then
		self:ScheduleMethod(0.15, "FireballTargetScanner", guid)
	end
end
