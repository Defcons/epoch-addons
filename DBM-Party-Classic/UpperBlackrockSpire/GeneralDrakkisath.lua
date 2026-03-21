local mod	= DBM:NewMod("GeneralDrakkisath", "DBM-Party-Classic", 1)
local L		= mod:GetLocalizedStrings()

local BOSS_CREATURE_ID = 10363
local CONFLAGRATION_ID = 85980
local CONFLAGRATION_DURATION = 5
local CONFLAGRATION_CD = 11
local MOLTEN_ENGULFMENT_ID = 85990
local FLAMESTRIKE_ID = 85978
local CHARRED_GROUND_ID = 85985

mod:SetRevision("20251103141714")
mod:SetCreatureID(BOSS_CREATURE_ID)
mod:SetUsedIcons(1)

mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 85980",
	"SPELL_AURA_REMOVED 85980",
	"SPELL_CAST_START 85990 85978",
	"SPELL_PERIODIC_DAMAGE 85985",
	"SPELL_PERIODIC_MISSED 85985"
)

local conflagrationWarn			= mod:NewTargetNoFilterAnnounce(CONFLAGRATION_ID, 2)
local conflagrationTimer		= mod:NewTargetTimer(CONFLAGRATION_DURATION, CONFLAGRATION_ID, nil, false, nil, 3)
local conflagrationSay			= mod:NewYell(CONFLAGRATION_ID)
local conflagrationCDTimer		= mod:NewCDTimer(CONFLAGRATION_CD, CONFLAGRATION_ID, nil, nil, nil, 3)

local moltenEngulfmentWarn		= mod:NewSpecialWarningSpell(MOLTEN_ENGULFMENT_ID, nil, nil, nil, 2, 2)

local charredGroundWarnGTFO		= mod:NewSpecialWarningMove(CHARRED_GROUND_ID, nil, nil, nil, 1, 8)

local flamestrikeWarn			= mod:NewSpecialWarningInterrupt(FLAMESTRIKE_ID, "HasInterrupt", nil, 2, 1, 2)

mod:AddSetIconOption("SetIconOnConflagration", CONFLAGRATION_ID, true, false, {1})

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == CONFLAGRATION_ID then
		conflagrationWarn:Show(args.destName)
		conflagrationTimer:Start(args.destName)
		conflagrationCDTimer:Start()
		if args:IsPlayer() then
			conflagrationSay:Yell()
		end

		if self.Options.SetIconOnConflagration then
			self:SetIcon(args.destName, 1, CONFLAGRATION_DURATION)
		end
	end
end

function mod:SPELL_AURA_REMOVED(args)
	if args.spellId == CONFLAGRATION_ID then
		conflagrationTimer:Stop(args.destName)
		if self.Options.SetIconOnConflagration then
			self:SetIcon(args.destName, 0)
		end
	end
end

function mod:SPELL_CAST_START(args)
	if args.spellId == MOLTEN_ENGULFMENT_ID then
		moltenEngulfmentWarn:Show()
		moltenEngulfmentWarn:Play("useitem")
	elseif args.spellId == FLAMESTRIKE_ID and self:CheckInterruptFilter(args.sourceGUID) then
		flamestrikeWarn:Show(args.sourceName)
		flamestrikeWarn:Play("kickcast")
	end
end

function mod:SPELL_PERIODIC_DAMAGE(_, _, _, destGUID, _, _, spellId, spellName)
	if spellId == CHARRED_GROUND_ID and destGUID == UnitGUID("player") and self:AntiSpam(2, 1) then
		charredGroundWarnGTFO:Show()
		charredGroundWarnGTFO:Play("watchfeet")
	end
end

mod.SPELL_PERIODIC_MISSED = mod.SPELL_PERIODIC_DAMAGE
