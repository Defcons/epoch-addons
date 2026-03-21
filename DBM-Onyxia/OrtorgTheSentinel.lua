local mod	= DBM:NewMod("OrtorgTheSentinel", "DBM-Onyxia")
local L		= mod:GetLocalizedStrings()

-- Guttural Shout
local SILENCE_ID = 85598
local SILENCE_CD = 25

local EMBER_BONDS_ID = 85596
local EMBER_BONDS_CD = 30
local CRIPPLING_BONDS_ID = 85595

local CRUMBLING_LAIR_ID = 85592

local LAVA_SLASH_ID = 85600
local LAVA_SLASH_CD = 22
local LAVA_SLASH_PULL_CD = 15
local LAVA_SLASH_P2_CD = 12
local LAVA_SLASH_HIGHSTACK = 2

-- This is set to not log
local OVERWHELMING_UPHEAVAL_ID = 85609
local OVERWHELMING_UPHEAVAL_CD = 90
local OVERWHELMING_UPHEAVAL_CD2 = 100

local P2_MOLTEN_UPHEAVAL_ID = 85603
local P2_MOLTEN_UPHEAVAL_CAST_TIME = 3.5

mod:SetRevision("20260107170028")
mod:SetCreatureID(45136)
mod:SetUsedIcons(1, 2, 3, 4, 5, 6)

mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 85596 85595 85600",
	"SPELL_AURA_APPLIED_DOSE 85600",
	"SPELL_AURA_REMOVED 85596 85595",
	"SPELL_PERIODIC_DAMAGE 85592",
	"SPELL_PERIODIC_MISSED 85592",
	"SPELL_CAST_START 85598 85603 85600",
	"CHAT_MSG_MONSTER_YELL"
)

local silenceCDTimer	= mod:NewCDTimer(SILENCE_CD, SILENCE_ID, nil, nil, nil, 2)
-- local silencePreWarn	= mod:NewPreWarnAnnounce(SILENCE_ID, SILENCE_CD, 2)

local emberBondsWarn			= mod:NewSpecialWarningTarget(EMBER_BONDS_ID, nil, nil, nil, 1, 2)
local emberBondsYell			= mod:NewYell(EMBER_BONDS_ID)
local emberBondsMove			= mod:NewSpecialWarningMoveAway(EMBER_BONDS_ID, nil, nil, nil, 4, 2)
local cripplingBondsFadesYell	= mod:NewShortFadesYell(CRIPPLING_BONDS_ID)
local emberBondsCDTimer			= mod:NewCDTimer(EMBER_BONDS_CD, EMBER_BONDS_ID, nil, nil, nil, 2)

local crumblingLairWarnGTFO = mod:NewSpecialWarningMove(CRUMBLING_LAIR_ID, nil, nil, nil, 1, 8)

local lavaSlashWarnStack		= mod:NewStackAnnounce(LAVA_SLASH_ID, 2, nil, "Tank|Healer")
local lavaSlashWarnHighStack	= mod:NewSpecialWarningStack(LAVA_SLASH_ID, nil, LAVA_SLASH_HIGHSTACK, nil, nil, 1, 6)
local lavaSlashCD				= mod:NewCDTimer(LAVA_SLASH_CD, LAVA_SLASH_ID, nil, nil, nil, 2)

local overwhelmingUpheavalCDTimer	= mod:NewCDTimer(OVERWHELMING_UPHEAVAL_CD, OVERWHELMING_UPHEAVAL_ID, nil, nil, nil, 6)
local phase2Counter					= mod:NewCountAnnounce(P2_MOLTEN_UPHEAVAL_ID, 2)

local phase1Warn = mod:NewPhaseAnnounce(1)
local phase2Warn = mod:NewPhaseAnnounce(2)

mod:AddRangeFrameOption(10, EMBER_BONDS_ID)
mod:AddSetIconOption("SetIconOnEmberBonds", EMBER_BONDS_ID, true, false, {1,2,3,4,5,6})

mod.vb.EmberBondsIcon = 1
mod.vb.P2Counter = 0

function mod:AnnouncePhase1()
	self.vb.P2Counter = 0
	phase1Warn:Show()
	silenceCDTimer:Start()
	emberBondsCDTimer:Start()
	lavaSlashCD:Start(LAVA_SLASH_P2_CD)
	overwhelmingUpheavalCDTimer:Start(OVERWHELMING_UPHEAVAL_CD2)
end

function mod:OnCombatStart()
	self.vb.EmberBondsIcon = 1
	self.vb.P2Counter = 0
	silenceCDTimer:Start()
	emberBondsCDTimer:Start()
	lavaSlashCD:Start(LAVA_SLASH_PULL_CD)
	overwhelmingUpheavalCDTimer:Start()
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == EMBER_BONDS_ID then
		emberBondsCDTimer:Stop()

		if self.Options.SetIconOnEmberBonds then
			self:SetIcon(args.destName, self.vb.EmberBondsIcon)
			self.vb.EmberBondsIcon = self.vb.EmberBondsIcon + 1
		end

		if args:IsPlayer() then
			emberBondsMove:Show()
			emberBondsMove:Play("runout")
			emberBondsYell:Yell()
			if self.Options.RangeFrame then
				DBM.RangeCheck:Show(10, nil, true)
			end
		else
			emberBondsWarn:CombinedShow(0.3, args.destName)
		end
	elseif args.spellId == CRIPPLING_BONDS_ID then
		if args:IsPlayer() then
			cripplingBondsFadesYell:Countdown(args.spellId)
		end
	elseif args.spellId == LAVA_SLASH_ID then
		local amount = args.amount or 1
		if amount >= LAVA_SLASH_HIGHSTACK then
			if args:IsPlayer() then
				lavaSlashWarnHighStack:Show(amount)
				lavaSlashWarnHighStack:Play("stackhigh")
			else
				lavaSlashWarnStack:Show(args.destName, amount)
			end
		else
			lavaSlashWarnStack:Show(args.destName, amount)
		end
	end
end

mod.SPELL_AURA_APPLIED_DOSE = mod.SPELL_AURA_APPLIED

function mod:SPELL_AURA_REMOVED(args)
	if args.spellId == EMBER_BONDS_ID then
		if args:IsPlayer() and self.Options.RangeFrame then
			DBM.RangeCheck:Hide(true)
		end
	elseif args.spellId == CRIPPLING_BONDS_ID then
		if not emberBondsCDTimer:IsStarted() then
			emberBondsCDTimer:Start()
		end

		if not silenceCDTimer:IsStarted() then
			silenceCDTimer:Start()
		end

		if self.Options.SetIconOnEmberBonds then
			self:SetIcon(args.destName, 0)
			self.vb.EmberBondsIcon = 1
		end

		if args:IsPlayer() then
			cripplingBondsFadesYell:Cancel()
		end
	end
end

function mod:SPELL_PERIODIC_DAMAGE(_, _, _, destGUID, _, _, spellId, spellName)
	if spellId == CRUMBLING_LAIR_ID and destGUID == UnitGUID("player") and self:AntiSpam(3, 1) then
		crumblingLairWarnGTFO:Show()
		crumblingLairWarnGTFO:Play("watchfeet")
	end
end

mod.SPELL_PERIODIC_MISSED = mod.SPELL_PERIODIC_DAMAGE

function mod:SPELL_CAST_START(args)
	if args.spellId == SILENCE_ID then
		silenceCDTimer:Stop()
	elseif args.spellId == P2_MOLTEN_UPHEAVAL_ID then
		self.vb.P2Counter = self.vb.P2Counter + 1
		phase2Counter:Show(self.vb.P2Counter)
		if self.vb.P2Counter >= 10 then
			self:ScheduleMethod(P2_MOLTEN_UPHEAVAL_CAST_TIME, "AnnouncePhase1")
		end
	elseif args.spellId == LAVA_SLASH_ID then
		lavaSlashCD:Start()
	end
end

function mod:CHAT_MSG_MONSTER_YELL(msg)
	local isPhase2 = msg == L.YellP2_1 or msg:find(L.YellP2_1) or
		msg == L.YellP2_2 or msg:find(L.YellP2_2) or
		msg == L.YellP2_3 or msg:find(L.YellP2_3) or
		msg == L.YellP2_4 or msg:find(L.YellP2_4)
	if isPhase2 then
		phase2Warn:Show()
		silenceCDTimer:Stop()
		emberBondsCDTimer:Stop()
		overwhelmingUpheavalCDTimer:Stop()
		lavaSlashCD:Stop()
		self.vb.P2Counter = 0
	end
end
