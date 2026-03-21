-- Broker_ItemRack : Minimalistic LDB plugin for Gello's ItemRack by Tristanian.
local _G = getfenv(0)
local L = LibStub("AceLocale-3.0"):GetLocale("Broker_ItemRack", true)
-- Check if ItemRack is loaded
-- in case some malicious user eliminated the ReqDep :p
if not IsAddOnLoaded("ItemRack") then
 DisableAddOn("Broker_ItemRack")
	DEFAULT_CHAT_FRAME:AddMessage(_G["GREEN_FONT_COLOR_CODE"].."Broker ItemRack: ".._G["FONT_COLOR_CODE_CLOSE"]..L["ItemRack addon not loaded."])
	return
end

local dataobj = LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject("Broker_ItemRack", {type = "data source", label = "Broker ItemRack", icon = "Interface\\Addons\\Broker_ItemRack\\Broker_ItemRack", text = L["<no outfit>"]})
local BRItemRack = CreateFrame("Frame", "Broker_ItemRack")

BRItemRack:RegisterEvent("PLAYER_ENTERING_WORLD");
BRItemRack:RegisterEvent("UNIT_INVENTORY_CHANGED");
BRItemRack:RegisterEvent("ADDON_LOADED")

BRItemRack:SetScript("OnEvent", function(self, event, arg1, ...)

	if event == "ADDON_LOADED" and arg1 == "ItemRackOptions" then			
			hooksecurefunc(ItemRackOpt, "SaveSet", BRItemRack_Update)
			if IsAddOnLoaded("Broker_ItemRack") then BRItemRack:UnregisterEvent("ADDON_LOADED") end
	end
	
  if event == "ADDON_LOADED" and arg1 == "Broker_ItemRack" then	
		if not Broker_ItemRackConfig then 
  -- initialize default configuration
    Broker_ItemRackConfig = {    
		MenuOrientation = "VERTICAL"
        	}
  	end  	
  	-- set enable events to whatever value ItemRack assigns
  		Broker_ItemRackConfig.EnableEvents = ItemRackUser.EnableEvents or "ON"  	
	end

	if ((event == "UNIT_INVENTORY_CHANGED") and (arg1 == "player")) or event == "PLAYER_ENTERING_WORLD" then
   	BRItemRack_Update();
 	end
end);


function BRItemRack_Update()

	local i =1;
	local outfit = nil;
  local usersets = ItemRackUser.Sets;
    
    
	 for i in next,usersets do
		if not string.find(i, "~") then 
			if ItemRack.IsSetEquipped(i) then
			   outfit = i;
			end
		end
	 end
	 
	 -- Set text
	 if outfit then
	  dataobj.text = outfit;
	 else
	  dataobj.text = L["Custom Outfit"];
	 end
	 
	 -- Set icon if found and the display supports it
	 if ItemRackUser.Sets[ItemRackUser.CurrentSet] and ItemRackUser.Sets[ItemRackUser.CurrentSet].icon and ItemRack.IsSetEquipped(dataobj.text) then
	 	if outfit then
	 		dataobj.icon = ItemRackUser.Sets[outfit].icon;
	 	else
	 		dataobj.icon = ItemRackUser.Sets[ItemRackUser.CurrentSet].icon;
	 	end
	 else
	 	dataobj.icon = "Interface\\Addons\\Broker_ItemRack\\Broker_ItemRack";
	 end
	 	 
end

local function GetTipAnchor(frame)
	local x,y = frame:GetCenter()
	if not x or not y then return "TOPLEFT", "BOTTOMLEFT" end
	local hhalf = (x > UIParent:GetWidth()*2/3) and "RIGHT" or (x < UIParent:GetWidth()/3) and "LEFT" or ""
	local vhalf = (y > UIParent:GetHeight()/2) and "TOP" or "BOTTOM"
	return vhalf..hhalf, frame, (vhalf == "TOP" and "BOTTOM" or "TOP")..hhalf
end


function dataobj.OnLeave() GameTooltip:Hide() end

function dataobj.OnEnter(self)
  -- ensure that our savedvar will always have the correct value
	if ItemRackUser and ItemRackUser.EnableEvents then
 		Broker_ItemRackConfig.EnableEvents = ItemRackUser.EnableEvents
 	end 	

	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:SetPoint(GetTipAnchor(self))
	GameTooltip:ClearLines()

	GameTooltip:AddLine(_G["HIGHLIGHT_FONT_COLOR_CODE"].."Broker ItemRack".._G["FONT_COLOR_CODE_CLOSE"])
	GameTooltip:AddLine(L["Left-Click to change outfit."])
	GameTooltip:AddLine(L["Right-Click to open configuration."])
	GameTooltip:AddLine(L["Alt-Right Click to enable/disable ItemRack events."])
	GameTooltip:AddLine(L["Shift-Left Click to toggle ItemRack menu orientation."])
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(_G["GREEN_FONT_COLOR_CODE"]..L["ItemRack events:"].._G["FONT_COLOR_CODE_CLOSE"].." ".._G["NORMAL_FONT_COLOR_CODE"]..L[Broker_ItemRackConfig.EnableEvents].._G["FONT_COLOR_CODE_CLOSE"])
	GameTooltip:AddLine(_G["GREEN_FONT_COLOR_CODE"]..L["Current menu orientation:"].._G["FONT_COLOR_CODE_CLOSE"].." ".._G["NORMAL_FONT_COLOR_CODE"]..L[Broker_ItemRackConfig.MenuOrientation].._G["FONT_COLOR_CODE_CLOSE"])
	
GameTooltip:Show()
end


function dataobj.OnClick(self, button)

if (button == "LeftButton") and IsShiftKeyDown() then
 	if Broker_ItemRackConfig.MenuOrientation == "VERTICAL" then
 		Broker_ItemRackConfig.MenuOrientation = "HORIZONTAL"
 	else
 		Broker_ItemRackConfig.MenuOrientation = "VERTICAL"
 	end
 	dataobj.OnEnter(self)
 	return
 end
 
 if (button == "RightButton") and IsAltKeyDown() then
 -- ensure that our savedvar will always have the correct value
 	ItemRack.ToggleEvents()
 	if ItemRackUser and ItemRackUser.EnableEvents then
 		Broker_ItemRackConfig.EnableEvents = ItemRackUser.EnableEvents
 	end 	
 	return
 end

GameTooltip:Hide()

 if (button == "LeftButton") then
 
 -- Workaround for displays using generic frame references (thanks Adirelle)
 -- We basically create a custom frame (if it doesn't exist) to hold our menu and anchor it to the DO 
 local anchorFrame = _G["Broker_ItemRack_MenuFrame"]
  if not anchorFrame then
    anchorFrame = CreateFrame("Frame", "Broker_ItemRack_MenuFrame")
  end
	
  anchorFrame:ClearAllPoints()
  anchorFrame:SetAllPoints(self)

 	
 	  local tip1, frame, tip2
 	  tip1, frame, tip2 = GetTipAnchor(anchorFrame)
 	   		
 	-- correct itemrack menu frame position
 	if tip1 == "TOP" and tip2 == "BOTTOM" then
 		tip1 = "TOPLEFT"
 		tip2 = "BOTTOMLEFT"
 	elseif tip1 == "BOTTOM" and tip2 == "TOP" then
 	  tip1 = "BOTTOMRIGHT"
 	  tip2 = "TOPRIGHT"
 	end
 	 	
 	ItemRack.DockWindows(tip1, anchorFrame, tip2, Broker_ItemRackConfig.MenuOrientation);
	ItemRack.BuildMenu(20)
	-- scaling and strata settings so our menu is always visible
	ItemRackMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG");
	local BRItemRackMenuScale = ItemRackUser.MenuScale or 1
	anchorFrame:SetScale(BRItemRackMenuScale)
	anchorFrame:SetFrameStrata("FULLSCREEN_DIALOG");	
	
 end
 
 if (button == "RightButton") then
 	if ItemRackMenuFrame:IsVisible() then
		ItemRackMenuFrame:Hide()
	end
	ItemRack.ToggleOptions(1);
	end
end