local mod	= DBM:NewMod("Volchan", "DBM-Azeroth")
local L		= mod:GetLocalizedStrings()

local ANCIENT_FLAME_ID = 87656
local ANCIENT_FLAME_CD = 30
local ANCIENT_FLAME_CD_PULL = 10
local BURNING_SOUL_ID = 87658
local BURNING_SOUL_DURATION = 10
local CALL_OF_EMBERS_ID = 87659
local MOLTEN_AGONY_ID = 87653
local MOLTEN_AGONY_CD = 300 -- 5 minutes

mod:SetRevision("20251228142020")
mod:SetCreatureID(46602)
mod:SetUsedIcons(8)

mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 87658",
	"SPELL_AURA_REMOVED 87658",
	"SPELL_CAST_SUCCESS 87656",
	"SPELL_PERIODIC_DAMAGE 87659",
	"SPELL_PERIODIC_MISSED 87659"
)

local ancientFlameWarn			= mod:NewSpecialWarningSpell(ANCIENT_FLAME_ID, nil, nil, nil, 1, 2)
local ancientFlameCDTimer		= mod:NewCDTimer(ANCIENT_FLAME_CD, ANCIENT_FLAME_ID, nil, false, nil, 1)

local burningSoulWarn			= mod:NewSpecialWarningTarget(BURNING_SOUL_ID, nil, nil, nil, 1, 2)
local burningSoulYell			= mod:NewYell(BURNING_SOUL_ID)
local burningSoulMove			= mod:NewSpecialWarningMoveAway(BURNING_SOUL_ID, nil, nil, nil, 4, 2)
local burningSoulFadesYell		= mod:NewShortFadesYell(BURNING_SOUL_ID)

local callOfEmbersWarnGTFO		= mod:NewSpecialWarningMove(CALL_OF_EMBERS_ID, nil, nil, nil, 1, 8)

local moltenAgonyCDTimer		= mod:NewBerserkTimer(MOLTEN_AGONY_CD)

mod:AddRangeFrameOption(10, BURNING_SOUL_ID)
mod:AddSetIconOption("SetIconOnBurningSoul", BURNING_SOUL_ID, true, false, {8})

function mod:OnCombatStart()
	moltenAgonyCDTimer:Start()
	ancientFlameCDTimer:Start(ANCIENT_FLAME_CD_PULL)
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == BURNING_SOUL_ID then
		if self.Options.SetIconOnBurningSoul then
			self:SetIcon(args.destName, 8, BURNING_SOUL_DURATION)
		end

		if args:IsPlayer() then
			burningSoulMove:Show()
			burningSoulMove:Play("runout")
			burningSoulYell:Yell()
			burningSoulFadesYell:Countdown(args.spellId)
			if self.Options.RangeFrame then
				DBM.RangeCheck:Show(10, nil, true)
			end
		else
			burningSoulWarn:Show(args.destName)
		end
	end
end

function mod:SPELL_AURA_REMOVED(args)
	if args.spellId == BURNING_SOUL_ID then
		if self.Options.SetIconOnBurningSoul then
			self:SetIcon(args.destName, 0)
		end

		if args:IsPlayer() then
			burningSoulFadesYell:Cancel()
			if self.Options.RangeFrame then
				DBM.RangeCheck:Hide(true)
			end
		end
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args.spellId == ANCIENT_FLAME_ID then
		ancientFlameWarn:Show()
		ancientFlameCDTimer:Start()
	end
end

function mod:SPELL_PERIODIC_DAMAGE(_, _, _, destGUID, _, _, spellId, spellName)
	if spellId == CALL_OF_EMBERS_ID and destGUID == UnitGUID("player") and self:AntiSpam(2, 1) then
		callOfEmbersWarnGTFO:Show()
		callOfEmbersWarnGTFO:Play("watchfeet")
	end
end

mod.SPELL_PERIODIC_MISSED = mod.SPELL_PERIODIC_DAMAGE
