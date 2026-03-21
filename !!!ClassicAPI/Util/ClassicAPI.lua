local _, Private = ...

--[[ INTERNAL ]]

-- Texture Path
Private.TEXTURE_PATH = "Interface\\AddOns\\!!!ClassicAPI\\Texture\\"

-- Scan Tooltip
local Tooltip = CreateFrame("GameTooltip", "__CAPIScanTooltip")
Tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
Tooltip:AddFontStrings(Tooltip:CreateFontString("$parentTextLeft1", nil, "GameTooltipText"), Tooltip:CreateFontString("$parentTextRight1", nil, "GameTooltipText"))
Private.Tooltip = Tooltip

-- General Event
Tooltip:SetScript("OnEvent", function(Self, Event)
	-- [Unit.lua:C_UnitInRange] Force client to cache Vial of the Sunwell
	if ( WOW_PROJECT_ID_RCE ~= WOW_PROJECT_CLASSIC ) then
		local _, RangeItemCached = GetItemInfo(34471)
		if ( not RangeItemCached ) then
			ItemEventListener:AddCallback(34471, Private.Void)
		end
	end

	ItemEventListener:Init()
	Self:UnregisterEvent(Event)
	Self:SetScript("OnEvent", nil)
end)
Tooltip:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Common Functions
function Private.Void()
	-- Send it to the nether.
end

function Private.True()
	return true
end

function Private.False()
	return false
end

function Private.Zero()
	return 0
end

--[[function Private.Globalize(Namespace, Data)
	_G[Namespace] = Data
	for Name,Func in pairs(Data) do
		local Exist = _G[Name]
		if ( Exist ) then
			if ( Func ~= Exist ) then
				Name = "C_"..Name
			end
		else
			_G[Name] = Func
		end
	end
end]]

--[[ MISCELLANEOUS ]]

-- [LFD_ERROR_FIX] Workaround long-standing client/server error.
local LFDCooldown = LFDQueueFrameCooldownFrame
if ( LFDCooldown ) then
	LFDCooldown:UnregisterEvent("UNIT_AURA")
	LFDCooldown:UnregisterEvent("PARTY_MEMBERS_CHANGED")
	LFDQueueFrame:HookScript("OnShow", LFDQueueFrameRandomCooldownFrame_Update)
end