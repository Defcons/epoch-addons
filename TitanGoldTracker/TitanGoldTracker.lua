-- **************************************************************************
-- * Titan Gold Tracker.lua - VERSION 2.3.2
-- **************************************************************************
-- * by Poena @ Area 52
-- * This mod will display all the gold held by toons in the same faction on 
-- * on the same server.  I have also incorporated the Titan Money functionality
-- * of displaying money session stats.
-- *
-- * Credits: The inspiration came from  Lozareth's Total Gold
-- *          Many thanks to:
-- *          Cladhaire @ Silent Transcendence who helped
-- *               clarify some muddy .lua programming routines early on.
-- *          Malreth @ Silver Hand and Zanek @ Malfurion who assisted me
-- *               in clarifying the sort routines.
-- * Updates for the new TitanPanel: Titan Development Team        
-- *               (HonorGoG, jaketodd422, joejanko, Lothayer, Tristanian)
-- **************************************************************************

-- ******************************** Versions ********************************
-- v2.3.2 Nov 13, 2007 - Fixed error with versioning text.
-- v2.3.1 Nov 13, 2007 - Updated TOC to 20300. Changed versioning so that the first two digits represent Blizz's current release.
-- v2.3 Sept 25, 2007 - Updated TOC to 20200.
-- v2.2 May 22, 2007 - Updated TOC to 20100.
-- v2.1 Apr 13, 2007 - Fixed bug the occured when the program tried to update values for a toon not yet in the database
-- v2.0 Apr 12, 2007 - Added option to hide a toon from Gold Tracker.  Just log into the toon and choose "hide toon"
-- v1.9 Jan  9, 2007 - Updated TOC to 20003.
-- v1.8 Jan  4, 2007 - Added French localization - thanks Wilf - Les Chevaliers Pourpres - Vol'Jin!
-- v1.7 Dec 20, 2006 - Fixed German Localization & added the ability to hide the gold/hour display.
-- v1.6 Dec 18, 2006 - Added German localization - thanks Omegasnow!
--                   - added functionality where the mod will remember your settings even after clearing the database
-- v1.5 Dec 18, 2006 - Fixed a bug that caused the mod to forget what your sort preference was between sessions
--                   - added functionality where the mod will remember your settings even after clearing the database
-- v1.4 Dec 16, 2006 - Fixed spacing on button between coins - smaller now.
-- v1.3 Dec 13, 2006 - Added the ability to sort the display table by name or by gold amount.
-- v1.2 Dec 11, 2006 - Removed Dependancy on Titan Panel [Money].
-- v1.1 Dec 10, 2006 - Fixed bug that showed "money lost" text even when you earned money.


-- ******************************** Constants *******************************
local TITAN_GOLDTRACKER_ID = "GoldTracker";
local TITAN_GOLDTRACKER_COUNT_FORMAT = "%d";
local TITAN_GOLDTRACKER_VERSION = TITAN_VERSION;
local TITAN_GOLDTRACKER_SPACERBAR = "--------------------";
local TITAN_GOLDTRACKER_BLUE = {r=0.4,b=1,g=0.4};
local TITAN_GOLDTRACKER_RED = {r=1,b=0,g=0};
local TITAN_GOLDTRACKER_GREEN = {r=0,b=0,g=1};
local updateTable = {TITAN_GOLDTRACKER_ID, TITAN_PANEL_UPDATE_TOOLTIP };
-- ******************************** Variables *******************************
local GOLDTRACKER_INITIALIZED = false;
local GOLDTRACKER_VARIABLES_LOADED = false;
local GOLDTRACKER_ENTERINGWORLD = false;
local GOLDTRACKER_INDEX = "";
local GOLDTRACKER_COLOR;
local GOLDTRACKER_STARTINGGOLD;
local GOLDTRACKER_SESSIONSTART;
local REMEMBER_VIEWALL;
local REMEMBER_SORTBYNAME;
local REMEMBER_SHOWGPH;
local L = LibStub("AceLocale-3.0"):GetLocale("Titan", true)
local LB = LibStub("AceLocale-3.0"):GetLocale("Titan_GoldTracker", true)
local TitanGoldTracker = LibStub("AceAddon-3.0"):NewAddon("TitanGoldTracker", "AceHook-3.0", "AceTimer-3.0")
local GoldTrackerTimer = nil;
local _G = getfenv(0);

-- ================================ Item Wealth Tracking ================================
-- Session-only caches (NEVER stored in GoldArray / SavedVariables)
local GT_PriceCache   = {}  -- [item_key]   = copper value (0 = no price found)
local GT_QualCache    = {}  -- [item_link]  = quality integer (0-6)
local GT_ItemValCache = {}  -- [charIndex]  = bags+bank total in copper
local GT_AHValCache   = {}  -- [charIndex]  = AH listings total in copper
local GT_BagScanTimer = nil -- AceTimer handle; debounces BAG_UPDATE floods

-- Session-relative AH wealth tracking
local GT_SessAHBase    = nil  -- (currentBags+currentAH) at session start; nil = lazy init on first tooltip
local GT_SessMailedVal = 0    -- cumulative copper value of items mailed this session
local GT_SessBagAtMail = nil  -- bags value snapshot taken when mailbox opens

-- Forward declarations so event handlers and tooltip defined above can call these.
local GT_ScanBagsNow, GT_ScanBankNow, GT_ScanAHNow
local GT_GetCharItemValue, GT_GetCharAHValue
local GT_GetItemPrice, GT_GetItemQuality, GT_ItemKeyFromLink

-- ******************************** Functions *******************************

-- **************************************************************************
-- NAME : TitanPanelGoldTrackerButton_OnLoad()
-- DESC : Registers the add on upon it loading
-- **************************************************************************
function TitanPanelGoldTrackerButton_OnLoad(self)
     self.registry = { 
          id = TITAN_GOLDTRACKER_ID,
 --         builtIn = 1,
			category = "Built-ins",
          version = TITAN_GOLDTRACKER_VERSION,
          menuText = LB["TITAN_GOLDTRACKER_MENU_TEXT"], 
          tooltipTitle = LB["TITAN_GOLDTRACKER_TOOLTIP"],
          tooltipTextFunction = "TitanPanelGoldTrackerButton_GetTooltipText",
          buttonTextFunction = "TitanPanelGoldTrackerButton_GetButtonText",
     };

     self:RegisterEvent("PLAYER_ENTERING_WORLD");
     self:RegisterEvent("PLAYER_MONEY");
     self:RegisterEvent("VARIABLES_LOADED");
     self:RegisterEvent("UNIT_NAME_UPDATE");
     self:RegisterEvent("BAG_UPDATE");
     self:RegisterEvent("BANKFRAME_OPENED");
     self:RegisterEvent("AUCTION_OWNED_LIST_UPDATE");
     self:RegisterEvent("MAIL_SHOW");
     self:RegisterEvent("MAIL_SEND_SUCCESS");
     
     -- support for picking up money     
     TitanGoldTracker:SecureHook("OpenCoinPickupFrame",TitanGoldTracker_OpenCoinPickupFrame);     
     
     if (not GoldArray) then 
          GoldArray={};
          GoldArray["VIEWALL"] = true
          GoldArray["DISPLAYGPH"] = true
     end
     
end


-- **************************************************************************
-- NAME : TitanPanelGoldTrackerButton_OnShow()
-- DESC : Create repeating timer when plugin is visible
-- **************************************************************************
function TitanPanelGoldTrackerButton_OnShow()
	if not GoldTrackerTimer and GoldArray and GoldArray["DISPLAYGPH"] then		
		GoldTrackerTimer = TitanGoldTracker:ScheduleRepeatingTimer(TitanPanelPluginHandle_OnUpdate, 1, updateTable)
	end
end

-- **************************************************************************
-- NAME : TitanPanelGoldTrackerButton_OnHide()
-- DESC : Destroy repeating timer when plugin is hidden
-- **************************************************************************
function TitanPanelGoldTrackerButton_OnHide()	
	TitanGoldTracker:CancelTimer(GoldTrackerTimer, true)
	GoldTrackerTimer = nil;     
end

-- **************************************************************************
-- NAME : TitanGoldTracker_OnEvent()
-- DESC : This section will grab the events registered to the add on and act on them
-- **************************************************************************
function TitanGoldTracker_OnEvent(self, event, ...)

     if (event == "VARIABLES_LOADED") then
          GOLDTRACKER_VARIABLES_LOADED = true;
          if (GOLDTRACKER_ENTERINGWORLD) then
               TitanPanelGoldTrackerButton_Initialize_Array(self);
          end
          return;
     end

     if ( event == "PLAYER_ENTERING_WORLD" ) then
          GOLDTRACKER_ENTERINGWORLD = true;
          if (GOLDTRACKER_VARIABLES_LOADED) then          		
               TitanPanelGoldTrackerButton_Initialize_Array(self);
          end
          return;
     end

     if (event == "PLAYER_MONEY") then
          if (GOLDTRACKER_INITIALIZED) then
               GoldArray[GOLDTRACKER_INDEX] = TitanPanelGoldTracker_ParseArray(GoldArray[GOLDTRACKER_INDEX]);
               MoneyFrame_Update("TitanPanelGoldTrackerButton", TitanPanelGoldTrackerButton_FindGold());
          end
          return;
     end

     if (event == "BAG_UPDATE") then
          if (GOLDTRACKER_INITIALIZED) then
               -- Debounce: bags fire many updates at once; wait 0.5s before scanning.
               if GT_BagScanTimer then TitanGoldTracker:CancelTimer(GT_BagScanTimer, true) end
               GT_BagScanTimer = TitanGoldTracker:ScheduleTimer(GT_ScanBagsNow, 0.5)
          end
          return;
     end

     if (event == "BANKFRAME_OPENED") then
          if (GOLDTRACKER_INITIALIZED) then
               GT_ScanBagsNow()   -- refresh bags too (catches anything missed)
               GT_ScanBankNow()
          end
          return;
     end

     if (event == "AUCTION_OWNED_LIST_UPDATE") then
          if (GOLDTRACKER_INITIALIZED) then
               GT_ScanAHNow()
          end
          return;
     end

     if (event == "MAIL_SHOW") then
          if (GOLDTRACKER_INITIALIZED) then
               -- Snapshot bag item value before the player sends anything
               GT_SessBagAtMail = GT_GetCharItemValue(GOLDTRACKER_INDEX);
          end
          return;
     end

     if (event == "MAIL_SEND_SUCCESS") then
          if (GOLDTRACKER_INITIALIZED) then
               -- Force an immediate bag rescan (skip the 0.5s debounce)
               if GT_BagScanTimer then TitanGoldTracker:CancelTimer(GT_BagScanTimer, true); end
               GT_ScanBagsNow();
               -- Items that left bags via mail still count toward session AH value
               if GT_SessBagAtMail then
                    local newBagVal = GT_GetCharItemValue(GOLDTRACKER_INDEX);
                    local mailed    = GT_SessBagAtMail - newBagVal;
                    if mailed > 0 then GT_SessMailedVal = GT_SessMailedVal + mailed; end
                    GT_SessBagAtMail = newBagVal;   -- update snapshot for subsequent sends
               end
          end
          return;
     end
end
 
-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerButton_GetTooltipText()
-- DESC: Gets our tool-tip text, what appears when we hover over our item on the Titan bar.
-- *******************************************************************************************
function TitanPanelGoldTrackerButton_GetTooltipText()
     -- the following code will parse the database and then display all members from the same server
     -- to the user (cross-faction)

     local server = GetCVar("realmName");
     GoldArray[GOLDTRACKER_INDEX] = TitanPanelGoldTracker_ParseArray(GoldArray[GOLDTRACKER_INDEX]);
    local currentMoneyRichText = ""; -- initialize the variable to hold the array

     -- This next section will sort the array based on user preference 
     -- either by name, or by gold amount decending.

     local GoldArraySorted = {};
     for index, money in pairs(GoldArray) do
          -- Only include numeric (gold) entries; skip table entries like BAGS_/BANK_/AH_/ITEMVAL_/AHVAL_.
          if type(money) == "number" then
               local character, charserver = string.match(index, '(.*)_(.*)');
               if (character) then
                    if (string.find(charserver, server, 1, true) == 1) then
                         table.insert(GoldArraySorted, index); -- insert all keys from hash into the array
                    end
               end
          end
     end
     
     if (GoldArray["SORTBYNAME"]) then
          table.sort(GoldArraySorted);
     else
          table.sort(GoldArraySorted, function (key1, key2) return GoldArray[key1] > GoldArray[key2] end) 
     end
     
     -- Compute session data up front so totals and session stats can share it.
     local sesstotal = GetMoney("player") - GOLDTRACKER_STARTINGGOLD;
     local sessNeg   = (sesstotal < 0);
     if (sessNeg) then sesstotal = math.abs(sesstotal); end
     local sesslength = math.max(GetTime() - GOLDTRACKER_SESSIONSTART, 1);
     local perhour    = math.floor(sesstotal / sesslength * 3600);
     local sessColor  = sessNeg and TITAN_GOLDTRACKER_RED or TITAN_GOLDTRACKER_GREEN;

     local ttlItemVal = 0;
     local ttlAHVal   = 0;
     for i = 1, getn(GoldArraySorted) do
          local character, charserver = string.match(GoldArraySorted[i], '(.*)_(.*)');
          if (character) then
               if (string.find(charserver, server, 1, true) == 1) then
                    if (mod(GoldArray[GoldArraySorted[i]],10) == 0) then
                         local goldText = TitanUtils_GetHighlightText(floor(GoldArray[GoldArraySorted[i]]/100000).."g");
                         local extraText = "";
                         local refreshFlag = "";
                         if (GoldArray["SHOWITEMWEALTH"]) then
                              local iv = GT_GetCharItemValue(GoldArraySorted[i]);
                              ttlItemVal = ttlItemVal + iv;
                              if (iv > 0) then
                                   extraText = extraText.."  |cffcccc33"..LB["TITAN_GOLDTRACKER_BAGS"]..": "..floor(iv/10000).."g|r";
                              end
                              -- Mark characters whose bag/bank data has never been captured
                              if (GoldArray["BAGS_"..GoldArraySorted[i]] == nil) then
                                   refreshFlag = " |cffff9900[?]|r";
                              end
                         end
                         if (GoldArray["SHOWAHLISTINGS"]) then
                              local av = GT_GetCharAHValue(GoldArraySorted[i]);
                              ttlAHVal = ttlAHVal + av;
                              if (av > 0) then
                                   extraText = extraText.."  |cff33cc66"..LB["TITAN_GOLDTRACKER_AH"]..": "..floor(av/10000).."g|r";
                              end
                         end
                         currentMoneyRichText = currentMoneyRichText.."\n"..character..refreshFlag.."\t"..goldText..extraText;
                    end
               end
          end
     end

     currentMoneyRichText = currentMoneyRichText.."\n"..TITAN_GOLDTRACKER_SPACERBAR.."\n"..LB["TITAN_GOLDTRACKER_TTL_GOLD"].."\t"..TitanUtils_GetHighlightText(floor(TitanPanelGoldTrackerButton_TotalGold()/10000).."g");
     if (GoldArray["SHOWITEMWEALTH"] and ttlItemVal > 0) then
          currentMoneyRichText = currentMoneyRichText.."\n"..LB["TITAN_GOLDTRACKER_TTL_ITEMS"].."\t"..TitanUtils_GetHighlightText(floor(ttlItemVal/10000).."g");
     end
     if (GoldArray["SHOWAHLISTINGS"] and ttlAHVal > 0) then
          currentMoneyRichText = currentMoneyRichText.."\n"..LB["TITAN_GOLDTRACKER_TTL_AH"].."\t"..TitanUtils_GetHighlightText(floor(ttlAHVal/10000).."g");
     end
     if (GoldArray["SHOWITEMWEALTH"] and (ttlItemVal > 0 or ttlAHVal > 0)) then
          local grandTotal = TitanPanelGoldTrackerButton_TotalGold() + ttlItemVal + ttlAHVal;
          currentMoneyRichText = currentMoneyRichText.."\n"..LB["TITAN_GOLDTRACKER_GRANDTOTAL"].."\t"..TitanUtils_GetHighlightText(floor(grandTotal/10000).."g");
     end

     -- Session-relative AH value for the current character only.
     -- Baseline is (bags + AH listings) at session start.  Items that leave bags
     -- via vendor/delete automatically reduce this.  Items mailed to alts are
     -- tracked separately and added back so they still count.
     local curBagVal  = GT_GetCharItemValue(GOLDTRACKER_INDEX);
     local curAHVal   = GT_GetCharAHValue(GOLDTRACKER_INDEX);
     if GT_SessAHBase == nil then GT_SessAHBase = curBagVal + curAHVal; end
     local sessAHVal  = math.max(0, (curBagVal + curAHVal) - GT_SessAHBase + GT_SessMailedVal);

     -- Session Statistics block
     local sessionMoneyRichText = "\n\n"..TitanUtils_GetHighlightText(LB["TITAN_GOLDTRACKER_STATS_TITLE"]).."\n"..LB["TITAN_GOLDTRACKER_START_GOLD"].."\t"..(TitanUtils_GetColoredText(floor(GOLDTRACKER_STARTINGGOLD/10000).."g", TITAN_GOLDTRACKER_BLUE) or "");

     -- Gold earned/lost row
     local goldSessLabel = (sessNeg and LB["TITAN_GOLDTRACKER_SESS_LOST_GOLD"] or LB["TITAN_GOLDTRACKER_SESS_EARNED_GOLD"]) or "";
     sessionMoneyRichText = sessionMoneyRichText.."\n"..goldSessLabel.."\t"..(TitanUtils_GetColoredText(floor(sesstotal/10000).."g", sessColor) or "");
     if (GoldArray["DISPLAYGPH"]) then
          local goldGphLabel = (sessNeg and LB["TITAN_GOLDTRACKER_GPH_LOST_GOLD"] or LB["TITAN_GOLDTRACKER_GPH_EARNED_GOLD"]) or "";
          sessionMoneyRichText = sessionMoneyRichText.."\n"..goldGphLabel.."\t"..(TitanUtils_GetColoredText(floor(perhour/10000).."g", sessColor) or "");
     end

     -- AH Value rows: session-relative, resets with the session button
     if (GoldArray["SHOWAHLISTINGS"] and sessAHVal > 0) then
          local ahperhour = math.floor(sessAHVal / sesslength * 3600);
          sessionMoneyRichText = sessionMoneyRichText.."\n"..LB["TITAN_GOLDTRACKER_SESS_AH_VALUE"].."\t"..TitanUtils_GetHighlightText(floor(sessAHVal/10000).."g");
          if (GoldArray["DISPLAYGPH"]) then
               sessionMoneyRichText = sessionMoneyRichText.."\n"..LB["TITAN_GOLDTRACKER_GPH_AH_VALUE"].."\t"..TitanUtils_GetHighlightText(floor(ahperhour/10000).."g");
          end

          -- Combined (signed gold delta + session AH value)
          local rawCombined   = (sessNeg and -sesstotal or sesstotal) + sessAHVal;
          local combinedNeg   = rawCombined < 0;
          local combinedAbs   = math.abs(rawCombined);
          local combinedColor = combinedNeg and TITAN_GOLDTRACKER_RED or TITAN_GOLDTRACKER_GREEN;
          local combSessLabel = (combinedNeg and LB["TITAN_GOLDTRACKER_SESS_COMBINED_LOSS"] or LB["TITAN_GOLDTRACKER_SESS_COMBINED"]) or "";
          sessionMoneyRichText = sessionMoneyRichText.."\n"..combSessLabel.."\t"..(TitanUtils_GetColoredText(floor(combinedAbs/10000).."g", combinedColor) or "");
          if (GoldArray["DISPLAYGPH"]) then
               local combinedPerhour = math.floor(combinedAbs / sesslength * 3600);
               local combGphLabel = (combinedNeg and LB["TITAN_GOLDTRACKER_GPH_COMBINED_LOSS"] or LB["TITAN_GOLDTRACKER_GPH_COMBINED"]) or "";
               sessionMoneyRichText = sessionMoneyRichText.."\n"..combGphLabel.."\t"..(TitanUtils_GetColoredText(floor(combinedPerhour/10000).."g", combinedColor) or "");
          end
     end
     
     
     local final_tooltip = LB["TITAN_GOLDTRACKER_TOOLTIPTEXT"].." : "..GetCVar("realmName").." : All Factions";
     GOLDTRACKER_COLOR = TITAN_GOLDTRACKER_BLUE;


     return ""..TitanUtils_GetColoredText(final_tooltip,GOLDTRACKER_COLOR)..currentMoneyRichText..sessionMoneyRichText;     
end


-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerButton_FindGold()
-- DESC: This routines determines which gold total the ui wants (server or player) then calls it and returns it
-- *******************************************************************************************
function TitanPanelGoldTrackerButton_FindGold()

     local server = GetCVar("realmName");

     GoldArray[GOLDTRACKER_INDEX] = TitanPanelGoldTracker_ParseArray(GoldArray[GOLDTRACKER_INDEX]);
     
    local ttlgold = 0;
     
     if (GoldArray["VIEWALL"]) then
          for index, money in pairs(GoldArray) do
               if type(money) == "number" then
                    local character, charserver = string.match(index, '(.*)_(.*)');
                    if (character) then
                         if (string.find(charserver, server, 1, true) == 1) then
                              if (mod(money,10)==0) then
                                   ttlgold = ttlgold + floor(money / 10);
                              end
                         end
                    end
               end
          end
     else
          ttlgold = GetMoney("player");
     end     

     return ttlgold;
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerButton_TotalGold()
-- DESC: Calculates total gold for display
-- *******************************************************************************************
function TitanPanelGoldTrackerButton_TotalGold()

     local server = GetCVar("realmName");
     GoldArray[GOLDTRACKER_INDEX] = TitanPanelGoldTracker_ParseArray(GoldArray[GOLDTRACKER_INDEX]);
    local ttlgold = 0;
     
     for index, money in pairs(GoldArray) do
          if type(money) == "number" then
               local character, charserver = string.match(index, '(.*)_(.*)');
               if (character) then
                    if (string.find(charserver, server, 1, true) == 1) then
                         if (mod(money,10)==0) then
                              ttlgold = ttlgold + floor(money / 10);
                         end
                    end
               end
          end
     end

     return ttlgold;
end


-- *******************************************************************************************
-- NAME: TitanPanelRightClickMenu_PrepareGoldTrackerMenu
-- DESC: Builds the right click config menu
-- *******************************************************************************************
function TitanPanelRightClickMenu_PrepareGoldTrackerMenu()
	if UIDROPDOWNMENU_MENU_LEVEL == 1 then
     -- Menu title
     TitanPanelRightClickMenu_AddTitle(LB["TITAN_GOLDTRACKER_ITEMNAME"]);     

     -- Function to toggle button gold view
     if (GoldArray["VIEWALL"]) then
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_PLAYER_TEXT"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerButton_Toggle");
     else
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_ALL_TEXT"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerButton_Toggle");
     end
          
     -- Function to toggle display sort
     if (GoldArray["SORTBYNAME"]) then
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_SORT_GOLD"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerSort_Toggle");
     else
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_SORT_NAME"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerSort_Toggle");
     end

     -- Function to toggle gold per hour sort
     if (GoldArray["DISPLAYGPH"]) then
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_GPH_HIDE"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerGPH_Toggle");
     else
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_GPH_SHOW"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerGPH_Toggle");
     end

     -- Item wealth: toggle visibility
     if (GoldArray["SHOWITEMWEALTH"]) then
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_ITEMWEALTH_HIDE"], TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerItemWealth_Toggle");
     else
          TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_ITEMWEALTH_SHOW"], TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerItemWealth_Toggle");
     end

     -- AH listings and quality threshold (only shown when item wealth is active)
     if (GoldArray["SHOWITEMWEALTH"]) then
          if (GoldArray["SHOWAHLISTINGS"]) then
               TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_AH_HIDE"], TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerAHListings_Toggle");
          else
               TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_AH_SHOW"], TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerAHListings_Toggle");
          end

          -- Quality threshold: three direct-select options; [x] = currently active
          local minQ    = GoldArray["MINQUALITY"] or 1;
          local selGrey  = (minQ <= 0) and "[x] " or "[ ] ";
          local selWhite = (minQ == 1) and "[x] " or "[ ] ";
          local selGreen = (minQ >= 2) and "[x] " or "[ ] ";
          TitanPanelRightClickMenu_AddCommand(selGrey ..LB["TITAN_GOLDTRACKER_MINQUALITY_OPT_GREY"],  TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerMinQualityGrey_Set");
          TitanPanelRightClickMenu_AddCommand(selWhite..LB["TITAN_GOLDTRACKER_MINQUALITY_OPT_WHITE"], TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerMinQualityWhite_Set");
          TitanPanelRightClickMenu_AddCommand(selGreen..LB["TITAN_GOLDTRACKER_MINQUALITY_OPT_GREEN"], TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerMinQualityGreen_Set");
     end

     -- A blank line in the menu
     TitanPanelRightClickMenu_AddSpacer();

     -- Function to toggle whether or not they want this toon visible in GoldTracker
     if (GoldArray[GOLDTRACKER_INDEX] ~= nil) then
          local toontoggle = GoldArray[GOLDTRACKER_INDEX];
          if (mod(toontoggle,10) == 0) then
               TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_PLAYER_HIDE"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerShowToon_Toggle");
          else
               TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_TOGGLE_PLAYER_SHOW"], TITAN_GOLDTRACKER_ID,"TitanPanelGoldTrackerShowToon_Toggle");
          end
     end
		
		-- Delete toon
		local info = {};
		info.text = LB["TITAN_GOLDTRACKER_DELETE_PLAYER"];
		info.value = "ToonDelete";
		info.hasArrow = 1;
		UIDropDownMenu_AddButton(info);		
		
     -- A blank line in the menu
     TitanPanelRightClickMenu_AddSpacer();
     
     -- Function to clear the enter database     
     local info = {};
     info.text = LB["TITAN_GOLDTRACKER_CLEAR_DATA_TEXT"];
     info.func = TitanGoldTracker_ClearDB;
     UIDropDownMenu_AddButton(info);
     
     TitanPanelRightClickMenu_AddCommand(LB["TITAN_GOLDTRACKER_RESET_SESS_TEXT"], TITAN_GOLDTRACKER_ID, "TitanPanelGoldTrackerButton_ResetSession");
     
     -- A blank line in the menu
     TitanPanelRightClickMenu_AddSpacer();
     
     -- Generic function to toggle and hide
     TitanPanelRightClickMenu_AddCommand(L["TITAN_PANEL_MENU_HIDE"], TITAN_GOLDTRACKER_ID, TITAN_PANEL_MENU_FUNC_HIDE);
     
  end
     
     if UIDROPDOWNMENU_MENU_LEVEL == 2 and UIDROPDOWNMENU_MENU_VALUE == "ToonDelete" then
			local info = {};
			info.text = LB["TITAN_GOLDTRACKER_FACTION_PLAYER_ALLY"];
			info.value = "Alliance";
			info.hasArrow = 1;
			UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);
						
			info.text = LB["TITAN_GOLDTRACKER_FACTION_PLAYER_HORDE"];
			info.value = "Horde";
			info.hasArrow = 1;
			UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);
		 end
		
		if UIDROPDOWNMENU_MENU_LEVEL == 3 and UIDROPDOWNMENU_MENU_VALUE == "Alliance" then
			local info = {};
			local name = GetUnitName("player");
			local server = GetRealmName();
				for index, money in pairs(GoldArray) do
				if type(money) == "number" then
      		local character, charserver = string.match(index, "(.*)_(.*)::Alliance");
      			if character then
							info.text = character.." - "..charserver;
							info.value = character;
							info.func = function()
								local rementry = character.."_"..charserver.."::Alliance";
								GoldArray[rementry] = nil;
								MoneyFrame_Update("TitanPanelGoldTrackerButton", TitanPanelGoldTrackerButton_FindGold())								
							end
							-- cannot delete current character							
							if name == character and server == charserver then
								info.disabled = 1;
							else
								info.disabled = nil;
							end
							UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);
						end						
				end												
			end   -- for loop
		elseif UIDROPDOWNMENU_MENU_LEVEL == 3 and UIDROPDOWNMENU_MENU_VALUE == "Horde" then
			local info = {};
			local name = GetUnitName("player");
			local server = GetRealmName();
				for index, money in pairs(GoldArray) do
				if type(money) == "number" then
      		local character, charserver = string.match(index, "(.*)_(.*)::Horde");
      			if character then
							info.text = character.." - "..charserver;
							info.value = character;
							info.func = function()
								local rementry = character.."_"..charserver.."::Horde";
								GoldArray[rementry] = nil;
								MoneyFrame_Update("TitanPanelGoldTrackerButton", TitanPanelGoldTrackerButton_FindGold())								
							end
							if name == character and server == charserver then
								info.disabled = 1;
							else
								info.disabled = nil;
							end
							UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);
						end
				end  -- type check
				end		
		end     
end

-- **************************************************************************
-- NAME : TitanPanelGoldTrackerButton_ClearData()
-- DESC : This will allow the user to clear all the data and rebuild the array
-- **************************************************************************
function TitanPanelGoldTrackerButton_ClearData(self)
     GOLDTRACKER_INITIALIZED = false;
     
     REMEMBER_VIEWALL =      GoldArray["VIEWALL"];
     REMEMBER_SORTBYNAME = GoldArray["SORTBYNAME"];
     REMEMBER_SHOWGPH = GoldArray["DISPLAYGPH"];
     local REMEMBER_SHOWITEMWEALTH = GoldArray["SHOWITEMWEALTH"];
     local REMEMBER_SHOWAHLISTINGS = GoldArray["SHOWAHLISTINGS"];
     local REMEMBER_MINQUALITY     = GoldArray["MINQUALITY"];
     
     GoldArray = {};
     TitanPanelGoldTrackerButton_Initialize_Array(self);

     GoldArray["VIEWALL"] = REMEMBER_VIEWALL;
     GoldArray["SORTBYNAME"] = REMEMBER_SORTBYNAME;
     GoldArray["DISPLAYGPH"] = REMEMBER_SHOWGPH;
     GoldArray["SHOWITEMWEALTH"] = REMEMBER_SHOWITEMWEALTH;
     GoldArray["SHOWAHLISTINGS"] = REMEMBER_SHOWAHLISTINGS;
     GoldArray["MINQUALITY"]     = REMEMBER_MINQUALITY;
          
     DEFAULT_CHAT_FRAME:AddMessage(LB["TITAN_GOLDTRACKER_DB_CLEARED"], 1.0, 0.0, 1.0 );
end

-- **************************************************************************
-- NAME : TitanPanelGoldTrackerButton_Initialize_Array()
-- DESC : Build the gold array for the server/faction
-- **************************************************************************
function TitanPanelGoldTrackerButton_Initialize_Array(self)
     if (GOLDTRACKER_INITIALIZED) then return; end          

     self:UnregisterEvent("VARIABLES_LOADED");
     self:UnregisterEvent("PLAYER_ENTERING_WORLD");
     self:UnregisterEvent("UNIT_NAME_UPDATE");

     if (not GoldArray["INITIALIZED"]) then
          GoldArray = {};
          GoldArray["INITIALIZED"] = true;
          GoldArray["VIEWALL"] = true;
          GoldArray["DISPLAYGPH"] = true;
          GoldArray["SORTBYNAME"] = true;
          GoldArray["VERSION2"] = true;
     end

     if (GoldArray["SORTBYNAME"] == nil) then
          GoldArray["SORTBYNAME"] = true;
     end

     if (GoldArray["DISPLAYGPH"] == nil) then
          GoldArray["DISPLAYGPH"] = true;
     end

     if (GoldArray["VERSION2"] == nil) then
          GoldArray["VERSION2"] = true;
          for index, money in pairs(GoldArray) do
               if type(money) == "number" then
                    local character, charserver = string.match(index, '(.*)_(.*)');
                    if (character) then
                              money = money * 10;
                              GoldArray[index] = money;
                    end
               end
          end
     end
     
     GOLDTRACKER_INDEX = UnitName("player").."_"..GetCVar("realmName").."::"..UnitFactionGroup("Player");
     
     if (GoldArray[GOLDTRACKER_INDEX] == nil) then
          GoldArray[GOLDTRACKER_INDEX] = GetMoney("player")*10;
     end
     
     GoldArray[GOLDTRACKER_INDEX] = TitanPanelGoldTracker_ParseArray(GoldArray[GOLDTRACKER_INDEX]);

     GOLDTRACKER_STARTINGGOLD = GetMoney("player");
     GOLDTRACKER_SESSIONSTART = GetTime();

     MoneyFrame_Update("TitanPanelGoldTrackerButton", TitanPanelGoldTrackerButton_FindGold());

     GOLDTRACKER_INITIALIZED = true;

     -- Purge any numeric ITEMVAL_/AHVAL_ keys written by a previous buggy build.
     -- These were incorrectly stored in GoldArray, causing phantom entries in the
     -- tooltip and inflated totals.  They are now kept as session-local variables.
     for key in pairs(GoldArray) do
          local p = string.sub(key, 1, 8);
          if p == "ITEMVAL_" or string.sub(key, 1, 6) == "AHVAL_" then
               GoldArray[key] = nil;
          end
     end

     -- Item-wealth config defaults (only on first ever load)
     if (GoldArray["SHOWITEMWEALTH"] == nil) then
          GoldArray["SHOWITEMWEALTH"] = true;
     end
     if (GoldArray["SHOWAHLISTINGS"] == nil) then
          GoldArray["SHOWAHLISTINGS"] = true;
     end
     if (GoldArray["MINQUALITY"] == nil) then
          GoldArray["MINQUALITY"] = 1;   -- 0=grey+, 1=white+, 2=green+
     end

     -- Trigger an initial bag scan now that the index is known.
     GT_ScanBagsNow();

     -- Reset session AH baseline so it's recomputed on first tooltip access.
     GT_SessAHBase    = nil;
     GT_SessMailedVal = 0;
     GT_SessBagAtMail = nil;
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerButton_Toggle()
-- DESC: This toggles whether or not the player wants to view total gold on the button, or player gold.
-- *******************************************************************************************
function TitanPanelGoldTrackerButton_Toggle()
     GoldArray["VIEWALL"] = not GoldArray["VIEWALL"];

     MoneyFrame_Update("TitanPanelGoldTrackerButton", TitanPanelGoldTrackerButton_FindGold());
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerSort_Toggle()
-- DESC: This toggles how the player wants the display to be sorted - by name or gold amount
-- *******************************************************************************************
function TitanPanelGoldTrackerSort_Toggle()
     GoldArray["SORTBYNAME"] = not GoldArray["SORTBYNAME"];
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerGPH_Toggle()
-- DESC: This toggles if the player wants to see the gold/hour stats
-- *******************************************************************************************
function TitanPanelGoldTrackerGPH_Toggle()
     GoldArray["DISPLAYGPH"] = not GoldArray["DISPLAYGPH"];
     if not GoldTrackerTimer and GoldArray["DISPLAYGPH"] then
			GoldTrackerTimer = TitanGoldTracker:ScheduleRepeatingTimer(TitanPanelPluginHandle_OnUpdate, 1, updateTable)
		 elseif GoldTrackerTimer and not GoldArray["DISPLAYGPH"] then
		 	TitanGoldTracker:CancelTimer(GoldTrackerTimer, true)
			GoldTrackerTimer = nil;     
		end
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerButton_ResetSession()
-- DESC: Resets the current session
-- *******************************************************************************************
function TitanPanelGoldTrackerButton_ResetSession()
     GOLDTRACKER_STARTINGGOLD = GetMoney("player");
     GOLDTRACKER_SESSIONSTART = GetTime();
     GT_SessAHBase    = nil;   -- recomputed on next tooltip access
     GT_SessMailedVal = 0;
     GT_SessBagAtMail = nil;
     DEFAULT_CHAT_FRAME:AddMessage(LB["TITAN_GOLDTRACKER_SESSION_RESET"], 1.0, 0.0, 1.0 );
end
     
-- *******************************************************************************************
-- NAME: TitanPanelGoldTracker_BreakMoney(money)
-- DESC: This routine was borrowed from TitanPanel [Money] - breaks down gold into denominations
-- *******************************************************************************************
function TitanPanelGoldTracker_BreakMoney(money)
     -- Non-negative money only
     if (money >= 0) then
          local gold = floor(money / (COPPER_PER_SILVER * SILVER_PER_GOLD));
          local silver = floor((money - (gold * COPPER_PER_SILVER * SILVER_PER_GOLD)) / COPPER_PER_SILVER);
          local copper = mod(money, COPPER_PER_SILVER);
          return gold, silver, copper;
     end
end     

-- *******************************************************************************************
-- NAME: TitanPanelGoldTracker_ParseArray(tooninfo)
-- DESC: This routine will parse the value of the array in order to remember if the toon should
--       be shown/included or not, while also updating the toon's gold information
-- *******************************************************************************************
function TitanPanelGoldTracker_ParseArray(tooninfo)
     TitanGoldTracker_ShowToon = mod(tooninfo,10);
     local finalvalue = (GetMoney("player") * 10) + TitanGoldTracker_ShowToon;
     return finalvalue;
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerShowToon_Toggle()
-- DESC: This routine will toggle a toon's status from visible to hidden
-- *******************************************************************************************
function TitanPanelGoldTrackerShowToon_Toggle()
     if (mod(GoldArray[GOLDTRACKER_INDEX],10)==0) then
          local newvalue = (floor(GoldArray[GOLDTRACKER_INDEX],10)*10)+1;
          GoldArray[GOLDTRACKER_INDEX] = newvalue;
          local character, charserver = string.match(GOLDTRACKER_INDEX, '(.*)_(.*)');
          DEFAULT_CHAT_FRAME:AddMessage("Titan Gold Tracker: "..character.." "..LB["TITAN_GOLDTRACKER_STATUS_PLAYER_HIDE"], 1.0, 0.0, 1.0 );
     else
          local newvalue = floor(GoldArray[GOLDTRACKER_INDEX],10)*10;
          GoldArray[GOLDTRACKER_INDEX] = newvalue;
          local character, charserver = string.match(GOLDTRACKER_INDEX, '(.*)_(.*)');
          DEFAULT_CHAT_FRAME:AddMessage("Titan Gold Tracker: "..character.." "..LB["TITAN_GOLDTRACKER_STATUS_PLAYER_SHOW"], 1.0, 0.0, 1.0 );
     end

     MoneyFrame_Update("TitanPanelGoldTrackerButton", TitanPanelGoldTrackerButton_FindGold());
end     

-- support for picking up money
-- extra functions

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerCopperButton_OnClick(button)
-- DESC: Create pickup frame for copper
-- VARS: button = value of action
-- *******************************************************************************************
function TitanPanelGoldTrackerCopperButton_OnClick(self, button)
     if (button == "LeftButton") then
          local parent = self:GetParent();
          OpenCoinPickupFrame(1, MoneyTypeInfo[parent.moneyType].UpdateFunc(), parent);
          parent.hasPickup = 1;
     end
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerSilverButton_OnClick(button)
-- DESC: Create pickup frame for silver
-- VARS: button = value of action
-- *******************************************************************************************
function TitanPanelGoldTrackerSilverButton_OnClick(self, button)
     if (button == "LeftButton") then
          local parent = self:GetParent();
          OpenCoinPickupFrame(COPPER_PER_SILVER, MoneyTypeInfo[parent.moneyType].UpdateFunc(), parent);
          parent.hasPickup = 1;
     end
end

-- *******************************************************************************************
-- NAME: TitanPanelGoldTrackerGoldButton_OnClick(button)
-- DESC: Create pickup frame for gold
-- VARS: button = value of action
-- *******************************************************************************************
function TitanPanelGoldTrackerGoldButton_OnClick(self, button)
     if (button == "LeftButton") then
          local parent = self:GetParent();
          OpenCoinPickupFrame(COPPER_PER_GOLD, MoneyTypeInfo[parent.moneyType].UpdateFunc(), parent);
          parent.hasPickup = 1;
     end
end

-- *******************************************************************************************
-- NAME: TitanGoldTracker_OpenCoinPickupFrame(multiplier, maxMoney, parent)
-- DESC: Create pickup frame and deliver money
-- VARS: multiplier = money type, maxMoney = amount available, parent = parent function
-- *******************************************************************************************
function TitanGoldTracker_OpenCoinPickupFrame(multiplier, maxMoney, parent)    
     CoinPickupFrame:Hide();
     
     position = TitanUtils_GetRealPosition(TITAN_GOLDTRACKER_ID);


     local scale = TitanPanelGetVar("Scale");
     if scale == nil then scale = 1; end

     if (parent:GetName() == "TitanPanelGoldTrackerButton") then
          if (position == TITAN_PANEL_PLACE_TOP) then 
			--local panelYOffset = TitanMovable_GetPanelYOffset(TITAN_PANEL_PLACE_TOP, TitanPanelGetVar("BothBars"));
               CoinPickupFrame:ClearAllPoints();
               CoinPickupFrame:SetPoint("TOPLEFT", parent:GetName(), "BOTTOMLEFT", -10, -4 * scale);
               CoinPickupFrame:SetFrameStrata("FULLSCREEN");               
          else
               CoinPickupFrame:ClearAllPoints();
               CoinPickupFrame:SetPoint("BOTTOMLEFT", parent:GetName(), "TOPLEFT", -10, 0);
               CoinPickupFrame:SetFrameStrata("FULLSCREEN");
          end          
     else
          CoinPickupFrame:ClearAllPoints();
          CoinPickupFrame:SetPoint("BOTTOMRIGHT", parent:GetName(), "TOPRIGHT", 0, 0);
     end
     CoinPickupFrame:Show();
     --PlaySound("igBackPackCoinSelect");
end

-- ===========================================================================
-- ITEM WEALTH TRACKING
-- ===========================================================================
-- Prices come from Aux (direct raw-string parse, same technique as AuxTSMBridge)
-- with a fallback to TSM AuctionDB.  Grey items (quality 0) are filtered by
-- the MINQUALITY threshold (default 1 = white+) to avoid polluting totals with
-- near-zero vendor prices.
--
-- Per-character inventory is stored in GoldArray under:
--   BAGS_<charIndex>  – bag slots (updated on BAG_UPDATE)
--   BANK_<charIndex>  – bank slots (updated on BANKFRAME_OPENED)
--   AH_<charIndex>    – owned AH auctions (updated on AUCTION_OWNED_LIST_UPDATE)
--
-- Pre-computed copper totals are cached in:
--   ITEMVAL_<charIndex>  – bags + bank value
--   AHVAL_<charIndex>    – AH listing value
-- These are set to nil whenever the underlying store changes, forcing a lazy
-- recalculate on the next tooltip hover.
-- ===========================================================================

-- ---- Aux raw-history price lookup ----------------------------------------
-- Mirrors AuxTSMBridge's GetAuxPricesDirect to avoid calling into aux's
-- internal temp-table allocator (which crashes when iterated externally).

local function GT_GetAuxFactionKey()
     local realm   = GetCVar("realmName")       or "";
     local faction = UnitFactionGroup("player") or "";
     return realm .. "|" .. faction;
end

GT_ItemKeyFromLink = function(link)
     if not link then return nil; end
     local itemID, suffixID = link:match("item:(%d+):%d+:%d+:%d+:%d+:%d+:(%-?%d+):?");
     if not itemID then return nil; end
     return itemID .. ":" .. (suffixID or "0");
end

local function GT_ParseAuxRecord(str)
     if not str or str == "" then return nil, {}; end
     local _, s2, s3 = str:match("^([^#]*)#([^#]*)#?(.*)");
     local daily_min = tonumber(s2);
     local pts = {};
     if s3 and s3 ~= "" then
          for entry in (s3 .. ";"):gmatch("([^;]+);") do
               local vs, ts = entry:match("^([^@]+)@(.+)$");
               local v, t = tonumber(vs), tonumber(ts);
               if v and t then tinsert(pts, {value=v, time=t}); end
          end
     end
     return daily_min, pts;
end

local function GT_WeightedMedian(pts)
     if not pts or #pts == 0 then return nil; end
     local ref   = pts[1].time;
     -- Honour the same configurable decay as Aux itself.
     local decay = (aux and aux.account and type(aux.account.history_decay)=="number"
                    and aux.account.history_decay) or 0.75;
     local W, wtbl = 0, {};
     for _, dp in ipairs(pts) do
          local days = floor((ref - dp.time) / 86400 + 0.5);
          local w    = decay ^ days;
          W = W + w;
          tinsert(wtbl, {value=dp.value, weight=w});
     end
     if W == 0 then return nil; end
     table.sort(wtbl, function(a, b) return a.value < b.value; end);
     local cum = 0;
     for _, w in ipairs(wtbl) do
          cum = cum + w.weight / W;
          if cum >= 0.5 then return w.value; end
     end
     return wtbl[#wtbl] and wtbl[#wtbl].value;
end

local function GT_LookupAuxPrice(itemKey)
     local fKey  = GT_GetAuxFactionKey();
     local hdata = aux and aux.faction and aux.faction[fKey] and aux.faction[fKey]["history"];
     if not hdata then return nil; end
     local str = hdata[itemKey];
     if not str then return nil; end
     local daily_min, pts = GT_ParseAuxRecord(str);
     if pts and #pts > 0 then return GT_WeightedMedian(pts); end
     return daily_min;
end

local function GT_LookupTSMPrice(itemKey)
     if not TSMAPI then return nil; end
     local itemID = tonumber(itemKey:match("^(%d+):"));
     if not itemID then return nil; end
     local ok, price = pcall(function()
          local AceAddon = LibStub and LibStub("AceAddon-3.0", true);
          local adb = AceAddon and AceAddon:GetAddon("TSM_AuctionDB", true);
          if adb then return adb:GetMarketValue(itemID); end
     end);
     return ok and type(price)=="number" and price > 0 and price or nil;
end

-- Returns unit AH price in copper, nil when unknown.  Cached per session.
GT_GetItemPrice = function(itemKey)
     if GT_PriceCache[itemKey] ~= nil then
          return GT_PriceCache[itemKey] ~= 0 and GT_PriceCache[itemKey] or nil;
     end
     local price = GT_LookupAuxPrice(itemKey) or GT_LookupTSMPrice(itemKey);
     GT_PriceCache[itemKey] = price or 0;
     return price;
end

-- Returns item quality (0-6), nil when WoW client hasn't cached it yet.
GT_GetItemQuality = function(link)
     if not link then return nil; end
     if GT_QualCache[link] ~= nil then return GT_QualCache[link]; end
     local _, _, q = GetItemInfo(link);
     if q ~= nil then GT_QualCache[link] = q; end
     return q;
end

-- ---- Generic value calculator for a stored item table --------------------

local function GT_CalcStoreValue(store)
     if not store then return 0; end
     local minQ  = GoldArray and (GoldArray["MINQUALITY"] or 1) or 1;
     local total = 0;
     for ik, info in pairs(store) do
          -- Lazy quality fetch: we may not have had it at scan time.
          local q = info.quality;
          if q == nil and info.link then
               q = GT_GetItemQuality(info.link);
               if q ~= nil then info.quality = q; end
          end
          -- nil quality = unknown → include it so nothing is accidentally hidden.
          if q == nil or q >= minQ then
               local price = GT_GetItemPrice(ik);
               if price then total = total + price * info.count; end
          end
     end
     return total;
end

-- ---- Scanning functions --------------------------------------------------

GT_ScanBagsNow = function()
     if not GOLDTRACKER_INITIALIZED then return; end
     GT_BagScanTimer = nil;
     local items = {};
     for bag = 0, NUM_BAG_SLOTS do
          for slot = 1, GetContainerNumSlots(bag) do
               local link = GetContainerItemLink(bag, slot);
               if link then
                    local _, count = GetContainerItemInfo(bag, slot);
                    count = count or 1;
                    local ik = GT_ItemKeyFromLink(link);
                    if ik then
                         if not items[ik] then
                              items[ik] = {link=link, count=0, quality=GT_GetItemQuality(link)};
                         end
                         items[ik].count = items[ik].count + count;
                    end
               end
          end
     end
     GoldArray["BAGS_"..GOLDTRACKER_INDEX] = items;
     GT_ItemValCache[GOLDTRACKER_INDEX] = nil;   -- invalidate session cache
end

GT_ScanBankNow = function()
     if not GOLDTRACKER_INITIALIZED then return; end
     local items = {};
     -- Main bank frame: BANK_CONTAINER (-1), NUM_BANKGENERIC_SLOTS slots.
     for slot = 1, NUM_BANKGENERIC_SLOTS do
          local link = GetContainerItemLink(BANK_CONTAINER, slot);
          if link then
               local _, count = GetContainerItemInfo(BANK_CONTAINER, slot);
               count = count or 1;
               local ik = GT_ItemKeyFromLink(link);
               if ik then
                    if not items[ik] then
                         items[ik] = {link=link, count=0, quality=GT_GetItemQuality(link)};
                    end
                    items[ik].count = items[ik].count + count;
               end
          end
     end
     -- Bank bag slots (NUM_BAG_SLOTS+1 … NUM_BAG_SLOTS+NUM_BANKBAGSLOTS).
     for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
          for slot = 1, GetContainerNumSlots(bag) do
               local link = GetContainerItemLink(bag, slot);
               if link then
                    local _, count = GetContainerItemInfo(bag, slot);
                    count = count or 1;
                    local ik = GT_ItemKeyFromLink(link);
                    if ik then
                         if not items[ik] then
                              items[ik] = {link=link, count=0, quality=GT_GetItemQuality(link)};
                         end
                         items[ik].count = items[ik].count + count;
                    end
               end
          end
     end
     GoldArray["BANK_"..GOLDTRACKER_INDEX] = items;
     GT_ItemValCache[GOLDTRACKER_INDEX] = nil;   -- invalidate session cache
end

GT_ScanAHNow = function()
     if not GOLDTRACKER_INITIALIZED then return; end
     local numOwned = GetNumAuctionItems("owner") or 0;
     local ahItems = {};
     for i = 1, numOwned do
          local link = GetAuctionItemLink("owner", i);
          if link then
               local _, _, count = GetAuctionItemInfo("owner", i);
               count = count or 1;
               local ik = GT_ItemKeyFromLink(link);
               if ik then
                    if not ahItems[ik] then
                         ahItems[ik] = {link=link, count=0, quality=GT_GetItemQuality(link)};
                    end
                    ahItems[ik].count = ahItems[ik].count + count;
               end
          end
     end
     GoldArray["AH_"..GOLDTRACKER_INDEX] = ahItems;
     GT_AHValCache[GOLDTRACKER_INDEX] = nil;   -- invalidate session cache
end

-- ---- Per-character value accessors (lazy-cached) -------------------------

GT_GetCharItemValue = function(charIndex)
     if GT_ItemValCache[charIndex] then
          return GT_ItemValCache[charIndex];
     end
     local val = GT_CalcStoreValue(GoldArray["BAGS_"..charIndex])
               + GT_CalcStoreValue(GoldArray["BANK_"..charIndex]);
     GT_ItemValCache[charIndex] = val;   -- session-local only, never in GoldArray
     return val;
end

GT_GetCharAHValue = function(charIndex)
     if GT_AHValCache[charIndex] then
          return GT_AHValCache[charIndex];
     end
     local val = GT_CalcStoreValue(GoldArray["AH_"..charIndex]);
     GT_AHValCache[charIndex] = val;   -- session-local only, never in GoldArray
     return val;
end

-- ---- Toggle / config functions (global so Titan's menu dispatcher finds them) ---

function TitanPanelGoldTrackerItemWealth_Toggle()
     GoldArray["SHOWITEMWEALTH"] = not GoldArray["SHOWITEMWEALTH"];
end

function TitanPanelGoldTrackerAHListings_Toggle()
     GoldArray["SHOWAHLISTINGS"] = not GoldArray["SHOWAHLISTINGS"];
end

-- Cycles quality threshold: grey+(0) → white+(1) → green+(2) → grey+(0) …
-- Invalidates all cached item-value totals so they recalculate with the new filter.
function TitanPanelGoldTrackerMinQuality_Cycle()
     local q = GoldArray["MINQUALITY"] or 1;
     if     q <= 0 then GoldArray["MINQUALITY"] = 1;
     elseif q == 1 then GoldArray["MINQUALITY"] = 2;
     else               GoldArray["MINQUALITY"] = 0;
     end
     -- Wipe session-local caches so values recalculate with the new threshold.
     GT_ItemValCache = {};
     GT_AHValCache   = {};
end

-- Direct-set quality functions used by the radio-style right-click menu.
function TitanPanelGoldTrackerMinQualityGrey_Set()
     GoldArray["MINQUALITY"] = 0;
     GT_ItemValCache = {};
     GT_AHValCache   = {};
end

function TitanPanelGoldTrackerMinQualityWhite_Set()
     GoldArray["MINQUALITY"] = 1;
     GT_ItemValCache = {};
     GT_AHValCache   = {};
end

function TitanPanelGoldTrackerMinQualityGreen_Set()
     GoldArray["MINQUALITY"] = 2;
     GT_ItemValCache = {};
     GT_AHValCache   = {};
end

-- ===========================================================================

function TitanGoldTracker_ClearDB()
	StaticPopupDialogs["TITANGOLDTRACKER_CLEAR_DATABASE"] = {
	text = TitanUtils_GetNormalText(L["TITAN_PANEL_MENU_TITLE"].." "..LB["TITAN_GOLDTRACKER_MENU_TEXT"]).."\n\n"..LB["TITAN_GOLDTRACKER_CLEAR_DATA_WARNING"],
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self)
	local frame = _G["TitanPanelGoldTrackerButton"]
  TitanPanelGoldTrackerButton_ClearData(frame)
	end,	
	showAlert = 1,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1
	};
	StaticPopup_Show("TITANGOLDTRACKER_CLEAR_DATABASE");
end
