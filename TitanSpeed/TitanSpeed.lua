-- **************************************************************************
-- * TitanSpeed.lua
-- * Displays player movement speed as a percentage on the Titan Panel bar.
-- * Base run speed is 7 yards/sec (100%).
-- **************************************************************************

local TITAN_SPEED_ID    = "Speed";
local BASE_RUN_SPEED    = 7.0;  -- yards/sec at 100%
local UPDATE_INTERVAL   = 0.2;  -- seconds between bar refreshes
local updateTable       = {TITAN_SPEED_ID, TITAN_PANEL_UPDATE_ALL};
local _G                = getfenv(0);
local L                 = LibStub("AceLocale-3.0"):GetLocale("Titan", true);

-- Known movement-speed buff names (English client).
-- Shapeshifts appear in UnitBuff just like regular buffs.
-- bonus     = flat speed bonus % (same at all ranks)
-- byRank    = per-rank bonus % table, keyed by the rank string UnitBuff returns
local SPEED_BUFF_INFO = {
    -- Druid
    ["Cat Form"]                = { bonus = 30 },
    ["Travel Form"]             = { bonus = 40 },
    ["Dash"]                    = { byRank = { ["Rank 1"] = 50, ["Rank 2"] = 65, ["Rank 3"] = 80 } },
    -- Shaman
    ["Ghost Wolf"]              = { bonus = 30 },
    -- Hunter
    ["Aspect of the Cheetah"]   = { bonus = 30 },
    ["Aspect of the Pack"]      = { bonus = 30 },
    -- Rogue
    ["Sprint"]                  = { byRank = { ["Rank 1"] = 50, ["Rank 2"] = 60, ["Rank 3"] = 70 } },
    -- Potions
    ["Swiftness Potion"]        = { bonus = 50 },
    ["Major Swiftness Potion"]  = { bonus = 50 },
};

-- **************************************************************************
-- NAME : TitanPanelSpeedButton_OnLoad()
-- DESC : Register the plugin with Titan Panel
-- **************************************************************************
function TitanPanelSpeedButton_OnLoad(self)
	self.registry = {
		id               = TITAN_SPEED_ID,
		category         = "Built-ins",
		version          = TITAN_VERSION,
		menuText         = "Move Speed",
		buttonTextFunction = "TitanPanelSpeedButton_GetButtonText",
		tooltipTitle     = "Movement Speed",
		tooltipTextFunction = "TitanPanelSpeedButton_GetTooltipText",
		controlVariables = {
			ShowIcon         = false,
			ShowLabelText    = true,
			ShowRegularText  = false,
			ShowColoredText  = false,
			DisplayOnRightSide = false,
		},
		savedVariables = {
			ShowLabelText = 1,
		},
	};
end

-- **************************************************************************
-- NAME : TitanPanelSpeedButton_OnUpdate()
-- DESC : Poll speed at UPDATE_INTERVAL and refresh the bar text
-- **************************************************************************
function TitanPanelSpeedButton_OnUpdate(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed;
	if self.elapsed >= UPDATE_INTERVAL then
		self.elapsed = 0;
		TitanPanelPluginHandle_OnUpdate(updateTable);
	end
end

-- **************************************************************************
-- NAME : TitanPanelSpeedButton_GetButtonText()
-- DESC : Return the label and value shown on the Titan bar
-- **************************************************************************
function TitanPanelSpeedButton_GetButtonText(id)
	local speed = GetUnitSpeed("player");
	local pct   = math.floor(speed / BASE_RUN_SPEED * 100 + 0.5);
	return "Speed:", TitanUtils_GetHighlightText(pct .. "%");
end

-- **************************************************************************
-- NAME : TitanPanelSpeedButton_GetTooltipText()
-- DESC : Return the tooltip body shown on hover
-- **************************************************************************
function TitanPanelSpeedButton_GetTooltipText()
	local speed = GetUnitSpeed("player");
	local pct   = math.floor(speed / BASE_RUN_SPEED * 100 + 0.5);

	local lines =
		"Current speed:\t" .. TitanUtils_GetHighlightText(pct .. "%") .. "\n" ..
		"Yards / sec:\t"   .. TitanUtils_GetHighlightText(string.format("%.2f", speed));

	-- Collect active speed sources
	local sources = {};

	if IsMounted() then
		table.insert(sources, TitanUtils_GetHighlightText("Mounted"));
	end

	local i = 1;
	while true do
		local name, rank, icon, count, debuffType, duration, expirationTime = UnitBuff("player", i);
		if not name then break; end
		local info = SPEED_BUFF_INFO[name];
		if info then
			local bonus;
			if info.byRank then
				bonus = info.byRank[rank];
			else
				bonus = info.bonus;
			end
			local bonusStr = bonus and (" (+" .. bonus .. "%)") or "";
			local entry;
			if duration and duration > 0 then
				local remaining = math.max(0, math.floor(expirationTime - GetTime()));
				entry = TitanUtils_GetHighlightText(name .. bonusStr) .. " - " .. remaining .. "s";
			else
				entry = TitanUtils_GetHighlightText(name .. bonusStr);
			end
			table.insert(sources, entry);
		end
		i = i + 1;
	end

	if #sources > 0 then
		lines = lines .. "\n\n" .. TitanUtils_GetNormalText("Active speed sources:") .. "\n  " ..
		        table.concat(sources, "\n  ");
	end

	return lines;
end

-- **************************************************************************
-- NAME : TitanPanelRightClickMenu_PrepareSpeedMenu()
-- DESC : Build the right-click context menu
-- **************************************************************************
function TitanPanelRightClickMenu_PrepareSpeedMenu()
	if UIDROPDOWNMENU_MENU_LEVEL == 1 then
		TitanPanelRightClickMenu_AddTitle("Move Speed");
		TitanPanelRightClickMenu_AddSpacer();
		TitanPanelRightClickMenu_AddToggleLabelText(TITAN_SPEED_ID);
		TitanPanelRightClickMenu_AddSpacer();
		TitanPanelRightClickMenu_AddCommand(L["TITAN_PANEL_MENU_HIDE"], TITAN_SPEED_ID, TITAN_PANEL_MENU_FUNC_HIDE);
	end
end
