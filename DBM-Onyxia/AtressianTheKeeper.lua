local mod	= DBM:NewMod("Atressian", "DBM-Onyxia")
local L		= mod:GetLocalizedStrings()

-- local PYROBLAST_ID = 150038
-- local PYROBLAST_CAST_TIME = 6

local SUMMON_DRAGONFIRE_ID = 150041

local DRAGONKIN_SORCERY_ID = 150053
local DRAGONKIN_SORCERY_WITH_DESC_ID = 150054
local DRAGONKIN_SORCERY_CD = 90
local DRAGONKIN_SORCERY_CD2 = 100

local SUMMON_DRAGONKIN_ID = 150121
local SUMMON_DRAGONKIN_TRIGGER_ID = 150126
local SUMMON_DRAGONKIN_CD = 50

local ARCANE_DECIMATE_ID = 150040
local ARCANE_DECIMATE_CAST_TIME = 2

local COLLAPSE_LAIR_ID = 150123
local COLLAPSE_LAIR_CAST_TIME = 30
local DRAGONKIN_CID = 300065 -- Onyxian Magmaweaver

local DRAGONKINS_RIGHT_ID = 150063
local DRAGONKINS_RIGHT_ID2 = 150049
local DRAGONKINS_RIGHT_WITH_DESC_ID = 150050
local DRAGONKINS_RIGHT_CD = 47
local DRAGONKINS_RIGHT_CAST_TIME = 5

local RITUAL_FLAMES_ID = 150051
local RITUAL_FLAMES_TIMER = 8

local IMPLODE_OR_EXPLODE_ID = 150127

local EXPLODE_ID = 150118
-- local EXPLODE_DEBUFF_ID = 150144
local EXPLODE_CAST_TIME = 6
local EXPLODE_RANGE = 6

local IMPLODE_ID = 150120
local IMPLODE_CAST_TIME = 6

local IMPLODE_EXPLODE_CD = 25
local IMPLODE_EXPLODE_CD2 = 60

mod:SetRevision("20260107170028")
mod:SetCreatureID(45125)
mod:SetUsedIcons(6, 8)

mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_CAST_START 150053 150121 150040 150123 150063 150049 150118 150120",
	"SPELL_CAST_SUCCESS 150126 150127",
	"SPELL_SUMMON 150041",
	-- "SPELL_AURA_REMOVED 150144",
	"UNIT_HEALTH",
	"UNIT_DIED"
)

local summonDragonfireWarn		= mod:NewSpecialWarningSwitch(SUMMON_DRAGONFIRE_ID, nil, nil, nil, 1, 2)

local manaGemsWarn				= mod:NewSpecialWarningSwitch(DRAGONKIN_SORCERY_WITH_DESC_ID, nil, nil, nil, 1, 2)
local manaGemsTimer				= mod:NewCDTimer(DRAGONKIN_SORCERY_CD, DRAGONKIN_SORCERY_WITH_DESC_ID, nil, nil, nil, 1)

local summonDragonkinWarn		= mod:NewSpecialWarningSwitch(SUMMON_DRAGONKIN_ID, nil, nil, nil, 1, 2)
local summonDragonkinTimer		= mod:NewCDTimer(SUMMON_DRAGONKIN_CD, SUMMON_DRAGONKIN_ID, nil, nil, nil, 1)

local arcaneDecimateWarn		= mod:NewTargetNoFilterAnnounce(ARCANE_DECIMATE_ID, 2)
local arcaneDecimateSay			= mod:NewYell(ARCANE_DECIMATE_ID)

local collpaseLairCastTimer		= mod:NewCastTimer(COLLAPSE_LAIR_CAST_TIME, COLLAPSE_LAIR_ID, nil, nil, nil, 2)
local collpaseLairWarn			= mod:NewSpecialWarningSpell(COLLAPSE_LAIR_ID, nil, nil, nil, 2, 2)

local dragonkinsRightWarn		= mod:NewPhaseAnnounce(3, 2, nil, nil, nil, nil, nil, 2)
local dragonkinsRightTimer		= mod:NewCDTimer(DRAGONKINS_RIGHT_CD, DRAGONKINS_RIGHT_WITH_DESC_ID, nil, nil, nil, 2)
local dragonkinsRightCastTimer	= mod:NewCastTimer(DRAGONKINS_RIGHT_CAST_TIME, DRAGONKINS_RIGHT_WITH_DESC_ID, nil, nil, nil, 2)

-- local ritualFlamesTimer			= mod:NewCastTimer(RITUAL_FLAMES_TIMER, RITUAL_FLAMES_ID, nil, nil, nil, 2)

local implodeSay				= mod:NewYell(IMPLODE_ID)
local implodeWarn				= mod:NewTargetNoFilterAnnounce(IMPLODE_ID, 2)
local implodeCastTimer			= mod:NewCastTimer(IMPLODE_CAST_TIME, IMPLODE_ID, nil, nil, nil, 2)

local explodeWarn				= mod:NewSpecialWarningSpell(EXPLODE_ID, nil, nil, nil, 2, 2)
local explodeCastTimer			= mod:NewCastTimer(EXPLODE_CAST_TIME, EXPLODE_ID, nil, nil, nil, 2)
local implodeExplodeTimer		= mod:NewCDTimer(IMPLODE_EXPLODE_CD, EXPLODE_ID, L.ImplodeExplodeTimer, nil, nil, 2)

local magmaweaverHealth = 0

mod:AddSetIconOption("SetIconOnArcaneDecimate", ARCANE_DECIMATE_ID, true, false, {6})
mod:AddSetIconOption("SetIconOnImplode", IMPLODE_ID, true, false, {8})
mod:AddRangeFrameOption(EXPLODE_RANGE, EXPLODE_ID)
mod:AddInfoFrameOption(COLLAPSE_LAIR_ID, true)

function mod:ArcaneDecimateTarget(targetName)
	if not targetName then return end

	if self.Options.SetIconOnArcaneDecimate then
		self:SetIcon(targetName, 6, ARCANE_DECIMATE_CAST_TIME)
	end

	arcaneDecimateWarn:Show(targetName)

	if targetName == UnitName("player") then
		arcaneDecimateSay:Yell()
	end
end

function mod:ImplodeTarget(targetName)
	if not targetName then return end

	if self.Options.SetIconOnImplode then
		self:SetIcon(targetName, 8, IMPLODE_CAST_TIME)
	end

	implodeWarn:Show(targetName)
	implodeCastTimer:Start()

	if targetName == UnitName("player") then
		implodeSay:Yell()
	end
end

local function UpdateMagmaweaverHealth()
	local str = string.format("Health: %.2f%%", magmaweaverHealth)
	return {str}, {str}
end

function mod:OnCombatStart()
	manaGemsTimer:Start()
end

function mod:OnCombatEnd()
	if self.Options.RangeFrame then
		DBM.RangeCheck:Hide(true)
	end

	if self.Options.InfoFrame then
		DBM.InfoFrame:Hide()
	end
end

function mod:SPELL_CAST_START(args)
	if args.spellId == DRAGONKIN_SORCERY_ID then
		manaGemsWarn:Show()
		manaGemsWarn:Play("mobsoon")
		summonDragonkinTimer:Start()
		manaGemsTimer:Stop()
		implodeExplodeTimer:Stop()
	elseif args.spellId == SUMMON_DRAGONKIN_ID then
		summonDragonkinTimer:Stop()
		dragonkinsRightTimer:Start()
		magmaweaverHealth = 100.0
		if self.Options.InfoFrame then
			DBM.InfoFrame:SetHeader("Onyxian Magmaweaver")
			DBM.InfoFrame:Show(1, "function", UpdateMagmaweaverHealth, false, false)
		end
	elseif args.spellId == ARCANE_DECIMATE_ID then
		self:BossTargetScanner(args.sourceGUID, "ArcaneDecimateTarget", 0.25, 8)
	elseif args.spellId == COLLAPSE_LAIR_ID then
		collpaseLairCastTimer:Start()
		collpaseLairWarn:Show()
	elseif args.spellId == DRAGONKINS_RIGHT_ID or args.spellId == DRAGONKINS_RIGHT_ID2 then
		dragonkinsRightTimer:Stop()
		dragonkinsRightWarn:Show()
		dragonkinsRightCastTimer:Start()
		manaGemsTimer:Start(DRAGONKIN_SORCERY_CD2)
		implodeExplodeTimer:Start()
		-- TODO Schedule this with the cast time but for now this mechanic is disabled anyway
		-- dragonkinsRightWarn:Play("runintofire")
		-- ritualFlamesTimer:Start()
	elseif args.spellId == IMPLODE_ID then
		self:BossTargetScanner(args.sourceGUID, "ImplodeTarget", 0.25, 8)
	elseif args.spellId == EXPLODE_ID then
		if self.Options.RangeFrame then
			DBM.RangeCheck:Show(EXPLODE_RANGE, nil, true)
		end

		explodeWarn:Show()
		explodeWarn:Play("aesoon")
		explodeCastTimer:Start()
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args.spellId == SUMMON_DRAGONKIN_TRIGGER_ID then
		summonDragonkinWarn:Show()
		summonDragonkinWarn:Play("bigmob")
	elseif args.spellId == IMPLODE_OR_EXPLODE_ID then
		implodeExplodeTimer:Start(IMPLODE_EXPLODE_CD2)
	end
end

function mod:SPELL_SUMMON(args)
	if args.spellId == SUMMON_DRAGONFIRE_ID then
		summonDragonfireWarn:Show()
	end
end

function mod:UNIT_HEALTH(uId)
	local cid = self:GetUnitCreatureId(uId)
	if cid ~= DRAGONKIN_CID then
		return
	end

	magmaweaverHealth = UnitHealth(uId) / UnitHealthMax(uId) * 100.0
	-- I'm not exactly sure how often this happens so just in case limiting it to 2 seconds
	-- to prevent potential fps issues
	if self:AntiSpam(2, 1) then
		self:SendSync("MagmaweaverHealth", magmaweaverHealth)
	end
end

function mod:UNIT_DIED(args)
	local cid = self:GetCIDFromGUID(args.destGUID)
	if cid == DRAGONKIN_CID then
		collpaseLairCastTimer:Stop()
		if self.Options.InfoFrame then
			DBM.InfoFrame:Hide()
		end
	end
end

function mod:OnSync(msg, health, sender)
	if not self:IsInCombat() then return end

	if msg == "MagmaweaverHealth" and sender then
		magmaweaverHealth = health
	end
end
