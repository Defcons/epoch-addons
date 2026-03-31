-- **************************************************************************
-- * TitanPerformance.lua
-- *
-- * By: TitanMod, Dark Imakuni, Adsertor and the Titan Development Team
-- *     (HonorGoG, jaketodd422, joejanko, Lothayer, Tristanian)
-- **************************************************************************

-- ******************************** Constants *******************************
local TITAN_PERFORMANCE_ID = "Performance";
local TITAN_PERF_FRAME_SHOW_TIME = 0.5;
local updateTable = {TITAN_PERFORMANCE_ID, TITAN_PANEL_UPDATE_ALL};

local TITAN_FPS_THRESHOLD_TABLE = {
     Values = { 20, 30 },
     Colors = { RED_FONT_COLOR, NORMAL_FONT_COLOR, GREEN_FONT_COLOR },
}
local TITAN_LATENCY_THRESHOLD_TABLE = {
     Values = { PERFORMANCEBAR_LOW_LATENCY, PERFORMANCEBAR_MEDIUM_LATENCY },
     Colors = { GREEN_FONT_COLOR, NORMAL_FONT_COLOR, RED_FONT_COLOR },
}
local TITAN_MEMORY_RATE_THRESHOLD_TABLE = {
     Values = { 1, 2 },
     Colors = { GREEN_FONT_COLOR, NORMAL_FONT_COLOR, RED_FONT_COLOR },
}

-- ******************************** Variables *******************************
local _G = getfenv(0);
local topAddOns;
local memUsageSinceGC = {};
local counter = 1; --counter for active addons
local L = LibStub("AceLocale-3.0"):GetLocale("Titan", true)
local AceTimer = LibStub("AceTimer-3.0")
local PerfTimer = nil;

-- ******************************** Memory Monitor ************************* -- Claude: entire memory monitor section added
local MM_UPDATE_INTERVAL = 5
local MM_NUM_ROWS = 20
local mmAddonMemory = {}
local mmAddonBaseline = {}
local mmTotalMemory = 0
local mmTotalBaseline = 0
local mmSortedAddons = {}
local mmSortBy = "memory"
local mmSortAsc = false
local mmLastUpdate = 0
local mmSessionStart = 0

local function MM_FormatMemory(kb)
    if kb >= 1024 then
        return format("%.1f MB", kb / 1024)
    elseif kb >= 1 then
        return format("%.0f KB", kb)
    else
        return format("%.1f KB", kb)
    end
end

local function MM_FormatGrowth(kb)
    if kb > 0 then
        return "|cffff4444+" .. MM_FormatMemory(kb) .. "|r"
    elseif kb < 0 then
        return "|cff44ff44" .. MM_FormatMemory(kb) .. "|r"
    else
        return "|cff888888-|r"
    end
end

local function MM_GetMemoryColor(kb)
    if kb > 10240 then return 1, 0.2, 0.2
    elseif kb > 5120 then return 1, 0.6, 0.2
    elseif kb > 2048 then return 1, 1, 0.3
    else return 0.4, 1, 0.4 end
end

local function MM_ScanMemory()
    UpdateAddOnMemoryUsage()
    local numAddons = GetNumAddOns()
    local total = 0
    wipe(mmAddonMemory)
    for i = 1, numAddons do
        local name, _, _, enabled = GetAddOnInfo(i)
        if enabled then
            local mem = GetAddOnMemoryUsage(i)
            mmAddonMemory[name] = mem
            total = total + mem
            if not mmAddonBaseline[name] then
                mmAddonBaseline[name] = mem
            end
        end
    end
    mmTotalMemory = total
    if mmTotalBaseline == 0 then mmTotalBaseline = total end

    wipe(mmSortedAddons)
    for name, mem in pairs(mmAddonMemory) do
        local baseline = mmAddonBaseline[name] or mem
        tinsert(mmSortedAddons, { name = name, memory = mem, growth = mem - baseline })
    end
    if mmSortBy == "memory" then
        sort(mmSortedAddons, function(a, b)
            if mmSortAsc then return a.memory < b.memory end
            return a.memory > b.memory
        end)
    elseif mmSortBy == "growth" then
        sort(mmSortedAddons, function(a, b)
            if mmSortAsc then return a.growth < b.growth end
            return a.growth > b.growth
        end)
    elseif mmSortBy == "name" then
        sort(mmSortedAddons, function(a, b)
            if mmSortAsc then return a.name < b.name end
            return a.name > b.name
        end)
    end
end

-- Memory Monitor Main Frame
local mmFrame = CreateFrame("Frame", "TitanPerfMemMonFrame", UIParent)
mmFrame:SetWidth(520)
mmFrame:SetHeight(500)
mmFrame:SetPoint("CENTER")
mmFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
mmFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
mmFrame:EnableMouse(true)
mmFrame:SetMovable(true)
mmFrame:RegisterForDrag("LeftButton")
mmFrame:SetScript("OnDragStart", mmFrame.StartMoving)
mmFrame:SetScript("OnDragStop", mmFrame.StopMovingOrSizing)
mmFrame:SetClampedToScreen(true)
mmFrame:SetFrameStrata("HIGH")
mmFrame:Hide()

local mmTitle = mmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mmTitle:SetPoint("TOPLEFT", 12, -10)
mmTitle:SetText("|cff00ccffMemory Monitor|r")

local mmCloseBtn = CreateFrame("Button", nil, mmFrame, "UIPanelCloseButton")
mmCloseBtn:SetPoint("TOPRIGHT", -2, -2)
mmCloseBtn:SetScript("OnClick", function() mmFrame:Hide() end)

-- Summary
local mmSummary = CreateFrame("Frame", nil, mmFrame)
mmSummary:SetPoint("TOPLEFT", 12, -35)
mmSummary:SetPoint("TOPRIGHT", -12, -35)
mmSummary:SetHeight(55)

local mmTotalLabel = mmSummary:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mmTotalLabel:SetPoint("TOPLEFT", 0, 0)
mmTotalLabel:SetText("Total Addon Memory:")
local mmTotalValue = mmSummary:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
mmTotalValue:SetPoint("LEFT", mmTotalLabel, "RIGHT", 8, 0)

local mmGrowthLabel = mmSummary:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mmGrowthLabel:SetPoint("TOPLEFT", 0, -18)
mmGrowthLabel:SetText("Session Growth:")
local mmGrowthValue = mmSummary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mmGrowthValue:SetPoint("LEFT", mmGrowthLabel, "RIGHT", 8, 0)

local mmCountLabel = mmSummary:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mmCountLabel:SetPoint("TOPLEFT", 0, -36)
mmCountLabel:SetText("Loaded Addons:")
local mmCountValue = mmSummary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mmCountValue:SetPoint("LEFT", mmCountLabel, "RIGHT", 8, 0)

-- GC Button
local mmGCBtn = CreateFrame("Button", nil, mmFrame, "UIPanelButtonTemplate")
mmGCBtn:SetWidth(100)
mmGCBtn:SetHeight(22)
mmGCBtn:SetPoint("TOPRIGHT", -35, -35)
mmGCBtn:SetText("Force GC")
mmGCBtn:SetScript("OnClick", function()
    collectgarbage("collect")
    MM_ScanMemory()
end)

-- Reset Baseline Button
local mmResetBtn = CreateFrame("Button", nil, mmFrame, "UIPanelButtonTemplate")
mmResetBtn:SetWidth(120)
mmResetBtn:SetHeight(22)
mmResetBtn:SetPoint("RIGHT", mmGCBtn, "LEFT", -5, 0)
mmResetBtn:SetText("Reset Baseline")
mmResetBtn:SetScript("OnClick", function()
    wipe(mmAddonBaseline)
    mmTotalBaseline = 0
    MM_ScanMemory()
    mmTotalBaseline = mmTotalMemory
    for name, mem in pairs(mmAddonMemory) do
        mmAddonBaseline[name] = mem
    end
end)

-- Column Headers
local mmHeaderFrame = CreateFrame("Frame", nil, mmFrame)
mmHeaderFrame:SetPoint("TOPLEFT", 12, -95)
mmHeaderFrame:SetPoint("TOPRIGHT", -30, -95)
mmHeaderFrame:SetHeight(20)

local function MM_CreateHeaderButton(parent, text, width, xOffset, sortKey)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(width)
    btn:SetHeight(20)
    btn:SetPoint("TOPLEFT", xOffset, 0)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetText(text)
    btn.text = fs
    btn:SetScript("OnClick", function()
        if mmSortBy == sortKey then mmSortAsc = not mmSortAsc
        else mmSortBy = sortKey; mmSortAsc = false end
        MM_ScanMemory()
    end)
    btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
    return btn
end

MM_CreateHeaderButton(mmHeaderFrame, "Addon Name", 220, 0, "name")
MM_CreateHeaderButton(mmHeaderFrame, "Memory", 100, 220, "memory")
MM_CreateHeaderButton(mmHeaderFrame, "Growth", 100, 320, "growth")

local mmHeaderLine = mmHeaderFrame:CreateTexture(nil, "OVERLAY")
mmHeaderLine:SetHeight(1)
mmHeaderLine:SetPoint("BOTTOMLEFT", 0, 0)
mmHeaderLine:SetPoint("BOTTOMRIGHT", 0, 0)
mmHeaderLine:SetTexture(1, 1, 1, 0.3)

-- Scroll Frame
local mmScrollFrame = CreateFrame("ScrollFrame", "TitanPerfMemMonScrollFrame", mmFrame, "FauxScrollFrameTemplate")
mmScrollFrame:SetPoint("TOPLEFT", 12, -118)
mmScrollFrame:SetPoint("BOTTOMRIGHT", -30, 45)

local mmRows = {}
for i = 1, MM_NUM_ROWS do
    local row = CreateFrame("Button", nil, mmFrame)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", mmScrollFrame, "TOPLEFT", 0, -((i - 1) * 18))
    row:SetPoint("RIGHT", mmScrollFrame, "RIGHT", 0, 0)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(1, 1, 1, 0.05)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    if i % 2 == 0 then row.bg:SetTexture(1, 1, 1, 0.03) else row.bg:SetTexture(0, 0, 0, 0) end

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 4, 0)
    row.nameText:SetWidth(216)
    row.nameText:SetJustifyH("LEFT")

    row.memText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.memText:SetPoint("LEFT", 224, 0)
    row.memText:SetWidth(96)
    row.memText:SetJustifyH("RIGHT")

    row.growthText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.growthText:SetPoint("LEFT", 324, 0)
    row.growthText:SetWidth(96)
    row.growthText:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        if not self.data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.data.name, 0, 0.8, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Current:", MM_FormatMemory(self.data.memory), 1,1,1, 1,1,0.6)
        local base = mmAddonBaseline[self.data.name] or self.data.memory
        GameTooltip:AddDoubleLine("Baseline:", MM_FormatMemory(base), 1,1,1, 0.7,0.7,0.7)
        GameTooltip:AddDoubleLine("Growth:", MM_FormatGrowth(self.data.growth), 1,1,1, 1,1,1)
        if base > 0 then
            local pct = (self.data.growth / base) * 100
            local pctColor = pct > 50 and "|cffff4444" or pct > 10 and "|cffffaa44" or "|cff44ff44"
            GameTooltip:AddDoubleLine("Growth %:", pctColor .. format("%.1f%%", pct) .. "|r", 1,1,1, 1,1,1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mmRows[i] = row
end

local function MM_UpdateScrollFrame()
    local numEntries = #mmSortedAddons
    FauxScrollFrame_Update(mmScrollFrame, numEntries, MM_NUM_ROWS, 18)
    local offset = FauxScrollFrame_GetOffset(mmScrollFrame)
    for i = 1, MM_NUM_ROWS do
        local idx = offset + i
        local row = mmRows[i]
        if idx <= numEntries then
            local data = mmSortedAddons[idx]
            row.data = data
            row.nameText:SetText(data.name)
            local r, g, b = MM_GetMemoryColor(data.memory)
            row.memText:SetText(MM_FormatMemory(data.memory))
            row.memText:SetTextColor(r, g, b)
            row.growthText:SetText(MM_FormatGrowth(data.growth))
            row:Show()
        else
            row:Hide()
        end
    end
end

mmScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, 18, MM_UpdateScrollFrame)
end)

-- Status bar
local mmStatusBar = mmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
mmStatusBar:SetPoint("BOTTOMLEFT", 12, 12)
mmStatusBar:SetTextColor(0.5, 0.5, 0.5)

-- OnUpdate for the monitor frame (only ticks while visible)
mmFrame:SetScript("OnUpdate", function(self, elapsed)
    mmLastUpdate = mmLastUpdate + elapsed
    if mmLastUpdate >= MM_UPDATE_INTERVAL then
        mmLastUpdate = 0
        MM_ScanMemory()

        mmTotalValue:SetText(MM_FormatMemory(mmTotalMemory))
        local r, g, b = MM_GetMemoryColor(mmTotalMemory)
        mmTotalValue:SetTextColor(r, g, b)

        local growth = mmTotalMemory - mmTotalBaseline
        mmGrowthValue:SetText(MM_FormatGrowth(growth))
        mmCountValue:SetText(tostring(#mmSortedAddons))

        MM_UpdateScrollFrame()

        local elapsed_session = time() - mmSessionStart
        local mins = floor(elapsed_session / 60)
        local secs = elapsed_session % 60
        mmStatusBar:SetText(format("Session: %dm %ds | Sort: %s %s | Left-click Titan button to toggle",
            mins, secs, mmSortBy, mmSortAsc and "asc" or "desc"))
    end
end)

local function MM_ToggleFrame()
    if mmFrame:IsShown() then
        mmFrame:Hide()
    else
        MM_ScanMemory()
        MM_UpdateScrollFrame()

        mmTotalValue:SetText(MM_FormatMemory(mmTotalMemory))
        local r, g, b = MM_GetMemoryColor(mmTotalMemory)
        mmTotalValue:SetTextColor(r, g, b)
        mmGrowthValue:SetText(MM_FormatGrowth(mmTotalMemory - mmTotalBaseline))
        mmCountValue:SetText(tostring(#mmSortedAddons))

        mmFrame:Show()
    end
end

-- Initialize baselines on login
local mmInitFrame = CreateFrame("Frame")
mmInitFrame:RegisterEvent("PLAYER_LOGIN")
mmInitFrame:SetScript("OnEvent", function()
    mmSessionStart = time()
    MM_ScanMemory()
    mmTotalBaseline = mmTotalMemory
    for name, mem in pairs(mmAddonMemory) do
        mmAddonBaseline[name] = mem
    end
end)

-- ******************************** Functions *******************************

-- **************************************************************************
-- NAME : TitanPanelPerformanceButton_OnLoad()
-- DESC : Registers the plugin upon it loading
-- **************************************************************************
function TitanPanelPerformanceButton_OnLoad(self)
     self.registry = {
          id = TITAN_PERFORMANCE_ID,
--         builtIn = 1,
			category = "Built-ins",
          version = TITAN_VERSION,
          menuText = L["TITAN_PERFORMANCE_MENU_TEXT"],
          buttonTextFunction = "TitanPanelPerformanceButton_GetButtonText";
          tooltipCustomFunction = TitanPanelPerformanceButton_SetTooltip;
          icon = "Interface\\AddOns\\TitanPerformance\\TitanPerformance",
          iconWidth = 16,
		controlVariables = {
			ShowIcon = true,
			ShowLabelText = true,
			ShowRegularText = false,
			ShowColoredText = true,
			DisplayOnRightSide = false
		},
          savedVariables = {
               ShowFPS = 1,
               ShowLatency = 1,
               ShowMemory = 1,
               ShowAddonMemory = false,
               ShowAddonIncRate = false,
               NumOfAddons = 5,
               AddonMemoryType = 1,
               ShowIcon = 1,
               ShowLabelText = false,
               ShowColoredText = 1,
          }
     };

     self.fpsSampleCount = 0;
     self:RegisterEvent("PLAYER_ENTERING_WORLD");
end


function TitanPanelPerformanceButton_OnShow()
	if not PerfTimer then
		PerfTimer = AceTimer.ScheduleRepeatingTimer("TitanPanelPerformance", TitanPanelPerformanceButtonHandle_OnUpdate, 1.5 )
	end
end


function TitanPanelPerformanceButton_OnHide()
	AceTimer.CancelTimer("TitanPanelPerformance", PerfTimer, true)
	PerfTimer = nil;
end

-- **************************************************************************
-- NAME : TitanPanelPerformanceButton_OnUpdate(elapsed)
-- DESC : Update button data
-- VARS : elapsed = <research>
-- **************************************************************************
function TitanPanelPerformanceButtonHandle_OnUpdate()	
		TitanPanelPluginHandle_OnUpdate(updateTable);
		if not (TitanPanelRightClickMenu_IsVisible()) and _G["TitanPanelPerfControlFrame"]:IsVisible() and not (MouseIsOver(_G["TitanPanelPerfControlFrame"])) then
		   _G["TitanPanelPerfControlFrame"]:Hide();
		end
end

function TitanPanelPerformanceButton_OnEvent(self, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then	
		  local i;	     
			topAddOns = {}
			-- scan how many addons are active
			local count = GetNumAddOns();
			local ActiveAddons = 0;
			for i=1, count do
				if IsAddOnLoaded(i) then
					ActiveAddons = ActiveAddons + 1;
				end
			end

			if ActiveAddons < TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons") then
				counter = ActiveAddons;
			else
				counter = TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons");
			end
			--set the counter to the proper number of active addons that are being monitored
			for i=1, counter do
				topAddOns[i] = {name = '', value = 0}
			end			
	end
end

-- **************************************************************************
-- NAME : TitanPanelPerformanceButton_GetButtonText(id) 
-- DESC : Calculate performance based logic for button text
-- VARS : id = button ID
-- **************************************************************************
function TitanPanelPerformanceButton_GetButtonText(id)     
     local button = _G["TitanPanelPerformanceButton"];
     local color, fpsRichText, latencyRichText, memoryRichText;
     local showFPS = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowFPS");
     local showLatency = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowLatency");
     local showMemory = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowMemory");

     -- Update real time data
     TitanPanelPerformanceButton_UpdateData()
     
     -- FPS text
     if ( showFPS ) then
          local fpsText = format(L["TITAN_FPS_FORMAT"], button.fps);
          if ( TitanGetVar(TITAN_PERFORMANCE_ID, "ShowColoredText") ) then     
               color = TitanUtils_GetThresholdColor(TITAN_FPS_THRESHOLD_TABLE, button.fps);
               fpsRichText = TitanUtils_GetColoredText(fpsText, color);
          else
               fpsRichText = TitanUtils_GetHighlightText(fpsText);
          end
     end

     -- Latency text
     if ( showLatency ) then
          local latencyText = format(L["TITAN_LATENCY_FORMAT"], button.latency);     
          if ( TitanGetVar(TITAN_PERFORMANCE_ID, "ShowColoredText") ) then     
               color = TitanUtils_GetThresholdColor(TITAN_LATENCY_THRESHOLD_TABLE, button.latency);
               latencyRichText = TitanUtils_GetColoredText(latencyText, color);
          else
               latencyRichText = TitanUtils_GetHighlightText(latencyText);
          end
     end

     -- Memory text
     if ( showMemory ) then
          local memoryText = format(L["TITAN_MEMORY_FORMAT"], button.memory/1024);
          memoryRichText = TitanUtils_GetHighlightText(memoryText);
     end
     
     if ( showFPS ) then
          if ( showLatency ) then
               if ( showMemory ) then
                    return L["TITAN_FPS_BUTTON_LABEL"], fpsRichText, L["TITAN_LATENCY_BUTTON_LABEL"], latencyRichText, L["TITAN_MEMORY_BUTTON_LABEL"], memoryRichText;
               else
                    return L["TITAN_FPS_BUTTON_LABEL"], fpsRichText, L["TITAN_LATENCY_BUTTON_LABEL"], latencyRichText;
               end
          else
               if ( showMemory ) then
                    return L["TITAN_FPS_BUTTON_LABEL"], fpsRichText, L["TITAN_MEMORY_BUTTON_LABEL"], memoryRichText;
               else
                    return L["TITAN_FPS_BUTTON_LABEL"], fpsRichText;
               end
          end
     else
          if ( showLatency ) then
               if ( showMemory ) then
                    return L["TITAN_LATENCY_BUTTON_LABEL"], latencyRichText, L["TITAN_MEMORY_BUTTON_LABEL"], memoryRichText;
               else
                    return L["TITAN_LATENCY_BUTTON_LABEL"], latencyRichText;
               end
          else
               if ( showMemory ) then
                    return L["TITAN_MEMORY_BUTTON_LABEL"], memoryRichText;
               else
                    return;
               end
          end
     end
end

-- **************************************************************************
-- NAME : TitanPanelPerformanceButton_SetTooltip()
-- DESC : Display tooltip text
-- **************************************************************************
function TitanPanelPerformanceButton_SetTooltip()
		 local button = _G["TitanPanelPerformanceButton"];
     local showFPS = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowFPS");
     local showLatency = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowLatency");
     local showMemory = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowMemory");
     local showAddonMemory = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowAddonMemory");

     -- Tooltip title
     GameTooltip:SetText(L["TITAN_PERFORMANCE_TOOLTIP"], HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);

     -- FPS tooltip
     if ( showFPS ) then
          local fpsText = format(L["TITAN_FPS_FORMAT"], button.fps);
          local avgFPSText = format(L["TITAN_FPS_FORMAT"], button.avgFPS);
          local minFPSText = format(L["TITAN_FPS_FORMAT"], button.minFPS);
          local maxFPSText = format(L["TITAN_FPS_FORMAT"], button.maxFPS);     
          
          GameTooltip:AddLine("\n");
          GameTooltip:AddLine(TitanUtils_GetHighlightText(L["TITAN_FPS_TOOLTIP"]));
          GameTooltip:AddDoubleLine(L["TITAN_FPS_TOOLTIP_CURRENT_FPS"], TitanUtils_GetHighlightText(fpsText));
          GameTooltip:AddDoubleLine(L["TITAN_FPS_TOOLTIP_AVG_FPS"], TitanUtils_GetHighlightText(avgFPSText));
          GameTooltip:AddDoubleLine(L["TITAN_FPS_TOOLTIP_MIN_FPS"], TitanUtils_GetHighlightText(minFPSText));
          GameTooltip:AddDoubleLine(L["TITAN_FPS_TOOLTIP_MAX_FPS"], TitanUtils_GetHighlightText(maxFPSText));
     end

     -- Latency tooltip
     if ( showLatency ) then
          local latencyText = format(L["TITAN_LATENCY_FORMAT"], button.latency);
          local bandwidthInText = format(L["TITAN_LATENCY_BANDWIDTH_FORMAT"], button.bandwidthIn);
          local bandwidthOutText = format(L["TITAN_LATENCY_BANDWIDTH_FORMAT"], button.bandwidthOut);
          
          GameTooltip:AddLine("\n");
          GameTooltip:AddLine(TitanUtils_GetHighlightText(L["TITAN_LATENCY_TOOLTIP"]));
          GameTooltip:AddDoubleLine(L["TITAN_LATENCY_TOOLTIP_LATENCY"], TitanUtils_GetHighlightText(latencyText));
          GameTooltip:AddDoubleLine(L["TITAN_LATENCY_TOOLTIP_BANDWIDTH_IN"], TitanUtils_GetHighlightText(bandwidthInText));
          GameTooltip:AddDoubleLine(L["TITAN_LATENCY_TOOLTIP_BANDWIDTH_OUT"], TitanUtils_GetHighlightText(bandwidthOutText));
     end

     -- Memory tooltip
     if ( showMemory ) then
          local memoryText = format(L["TITAN_MEMORY_FORMAT"], button.memory/1024);
          local initialMemoryText = format(L["TITAN_MEMORY_FORMAT"], button.initialMemory/1024);          
          local sessionTime = time() - button.startSessionTime;          
          local rateRichText, timeToGCRichText, rate, timeToGC, color;     
          if ( sessionTime == 0 ) then
               rateRichText = TitanUtils_GetHighlightText("N/A");
          else
               rate = (button.memory - button.initialMemory) / sessionTime;
               color = TitanUtils_GetThresholdColor(TITAN_MEMORY_RATE_THRESHOLD_TABLE, rate);
               rateRichText = TitanUtils_GetColoredText(format(L["TITAN_MEMORY_RATE_FORMAT"], rate), color);
          end     
          if ( button.memory == button.initialMemory ) then
               timeToGCRichText = TitanUtils_GetHighlightText("N/A");          
          end     
     
          GameTooltip:AddLine("\n");
          GameTooltip:AddLine(TitanUtils_GetHighlightText(L["TITAN_MEMORY_TOOLTIP"]));
          GameTooltip:AddDoubleLine(L["TITAN_MEMORY_TOOLTIP_CURRENT_MEMORY"], TitanUtils_GetHighlightText(memoryText));
          GameTooltip:AddDoubleLine(L["TITAN_MEMORY_TOOLTIP_INITIAL_MEMORY"], TitanUtils_GetHighlightText(initialMemoryText));
          GameTooltip:AddDoubleLine(L["TITAN_MEMORY_TOOLTIP_INCREASING_RATE"], rateRichText);          
     end
     
	if ( showAddonMemory == 1 ) then
				for _,i in pairs(topAddOns) do
			  	i.name = '';
			  	i.value = 0;	
			end

		Stats_UpdateAddonsList(self, GetCVar('scriptProfile') == '1' and not IsModifierKeyDown())
	end     

	GameTooltip:AddLine(TitanUtils_GetGreenText(L["TITAN_PERFORMANCE_TOOLTIP_HINT"]));
end

-- **************************************************************************
-- NAME : TitanPanelRightClickMenu_PreparePerformanceMenu()
-- DESC : Display rightclick menu options
-- **************************************************************************
function TitanPanelRightClickMenu_PreparePerformanceMenu()
	local info
	
	-- level 3
	if _G["UIDROPDOWNMENU_MENU_LEVEL"] == 3 and _G["UIDROPDOWNMENU_MENU_VALUE"]== "AddonControlFrame" then
		TitanPanelPerfControlFrame:Show()
		return
	end
	
	-- level 2
	if _G["UIDROPDOWNMENU_MENU_LEVEL"] == 2 then
			if _G["UIDROPDOWNMENU_MENU_VALUE"] == "Options" then
				TitanPanelRightClickMenu_AddTitle(L["TITAN_PANEL_MENU_OPTIONS"], _G["UIDROPDOWNMENU_MENU_LEVEL"]);
				
				local temptable = {TITAN_PERFORMANCE_ID, "ShowFPS"};
				info = {};
				info.text = L["TITAN_PERFORMANCE_MENU_SHOW_FPS"];
				info.value = temptable;
				info.func = function()
					TitanPanelRightClickMenu_ToggleVar(temptable)
				end
				info.checked = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowFPS");
				info.keepShownOnClick = 1;
				UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
				
				local temptable = {TITAN_PERFORMANCE_ID, "ShowLatency"};
				info = {};
				info.text = L["TITAN_PERFORMANCE_MENU_SHOW_LATENCY"];
				info.value = temptable;
				info.func = function()
					TitanPanelRightClickMenu_ToggleVar(temptable)
				end
				info.checked = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowLatency");
				info.keepShownOnClick = 1;
				UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
				
				local temptable = {TITAN_PERFORMANCE_ID, "ShowMemory"};
				info = {};
				info.text = L["TITAN_PERFORMANCE_MENU_SHOW_MEMORY"];
				info.value = temptable;
				info.func = function()
					TitanPanelRightClickMenu_ToggleVar(temptable)
				end
				info.checked = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowMemory");
				info.keepShownOnClick = 1;
				UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
			end
			
			if _G["UIDROPDOWNMENU_MENU_VALUE"] == "AddonUsage" then
				TitanPanelRightClickMenu_AddTitle(L["TITAN_PERFORMANCE_ADDONS"], _G["UIDROPDOWNMENU_MENU_LEVEL"]);
    		
    		local temptable = {TITAN_PERFORMANCE_ID, "ShowAddonMemory"};
				info = {};
				info.text = L["TITAN_PERFORMANCE_MENU_SHOW_ADDONS"];
				info.value = temptable;
				info.func = function()
					TitanPanelRightClickMenu_ToggleVar(temptable)
				end
				info.checked = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowAddonMemory");
				info.keepShownOnClick = 1;
				UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
				
				local temptable = {TITAN_PERFORMANCE_ID, "ShowAddonIncRate"};
				info = {};
				info.text = L["TITAN_PERFORMANCE_MENU_SHOW_ADDON_RATE"];
				info.value = temptable;
				info.func = function()
					TitanPanelRightClickMenu_ToggleVar(temptable)
				end
				info.checked = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowAddonIncRate");
				info.keepShownOnClick = 1;
				UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
    		
				info = {};
				info.text = L["TITAN_PERFORMANCE_CONTROL_TOOLTIP"]..LIGHTYELLOW_FONT_COLOR_CODE..tostring(TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons"));
				info.value = "AddonControlFrame"
				info.hasArrow = 1;
    		UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
			end
			
			if _G["UIDROPDOWNMENU_MENU_VALUE"] == "AddonMemoryFormat" then
				TitanPanelRightClickMenu_AddTitle(L["TITAN_PERFORMANCE_ADDON_MEM_FORMAT_LABEL"], _G["UIDROPDOWNMENU_MENU_LEVEL"]);
				info = {};
				info.text = L["TITAN_MEGABYTE"];
				info.checked = function() if TitanGetVar(TITAN_PERFORMANCE_ID, "AddonMemoryType") == 1 then return true else return nil end
				end
				info.func = function() TitanSetVar(TITAN_PERFORMANCE_ID, "AddonMemoryType", 1) end
     		UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
     		info = {};
				info.text = L["TITAN_MEMORY_KBMB_LABEL"];
				info.checked = function() if TitanGetVar(TITAN_PERFORMANCE_ID, "AddonMemoryType") == 2 then return true else return nil end
				end
				info.func = function() TitanSetVar(TITAN_PERFORMANCE_ID, "AddonMemoryType", 2) end
     		UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
			end
			
			if _G["UIDROPDOWNMENU_MENU_VALUE"] == "CPUProfiling" then
				if ( GetCVar("scriptProfile") == "1" ) then
					TitanPanelRightClickMenu_AddTitle(L["TITAN_PERFORMANCE_MENU_CPUPROF_LABEL"]..": "..GREEN_FONT_COLOR_CODE..L["TITAN_PANEL_MENU_ENABLED"], _G["UIDROPDOWNMENU_MENU_LEVEL"]);
					info = {};
					info.text = L["TITAN_PERFORMANCE_MENU_CPUPROF_LABEL_OFF"]..GREEN_FONT_COLOR_CODE..L["TITAN_PANEL_MENU_RELOADUI"];
					info.func = function() SetCVar("scriptProfile", "0", 1) ReloadUI() end
					UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
				else
					TitanPanelRightClickMenu_AddTitle(L["TITAN_PERFORMANCE_MENU_CPUPROF_LABEL"]..": "..RED_FONT_COLOR_CODE..L["TITAN_PANEL_MENU_DISABLED"], _G["UIDROPDOWNMENU_MENU_LEVEL"]);
					info = {};
					info.text = L["TITAN_PERFORMANCE_MENU_CPUPROF_LABEL_ON"]..GREEN_FONT_COLOR_CODE..L["TITAN_PANEL_MENU_RELOADUI"];
					info.func = function() SetCVar("scriptProfile", "1", 1) ReloadUI() end
					UIDropDownMenu_AddButton(info, _G["UIDROPDOWNMENU_MENU_LEVEL"]);
				end
			end
		return
	end
	
	-- level 1
		TitanPanelRightClickMenu_AddTitle(TitanPlugins[TITAN_PERFORMANCE_ID].menuText);    
     
			info = {};
	 		info.text = L["TITAN_PANEL_MENU_OPTIONS"];
	 		info.value = "Options"
	 		info.hasArrow = 1;	 
   		UIDropDownMenu_AddButton(info);
   		
   		info = {};
	 		info.text = L["TITAN_PERFORMANCE_ADDONS"];
	 		info.value = "AddonUsage"
	 		info.hasArrow = 1;	 
   		UIDropDownMenu_AddButton(info);
   		
   		info = {};
	 		info.text = L["TITAN_PERFORMANCE_ADDON_MEM_FORMAT_LABEL"];
	 		info.value = "AddonMemoryFormat"
	 		info.hasArrow = 1;	 
   		UIDropDownMenu_AddButton(info);
   		
   		info = {};
	 		info.text = L["TITAN_PERFORMANCE_MENU_CPUPROF_LABEL"];
	 		info.value = "CPUProfiling"
	 		info.hasArrow = 1;	 
   		UIDropDownMenu_AddButton(info);
		
     	TitanPanelRightClickMenu_AddSpacer();
     	TitanPanelRightClickMenu_AddToggleIcon(TITAN_PERFORMANCE_ID);
     	TitanPanelRightClickMenu_AddToggleLabelText(TITAN_PERFORMANCE_ID);
     	TitanPanelRightClickMenu_AddToggleColoredText(TITAN_PERFORMANCE_ID);
     	TitanPanelRightClickMenu_AddSpacer();
     	TitanPanelRightClickMenu_AddCommand(L["TITAN_PANEL_MENU_HIDE"], TITAN_PERFORMANCE_ID, TITAN_PANEL_MENU_FUNC_HIDE);
end

-- **************************************************************************
-- NAME : TitanPanelPerformanceButton_UpdateData()
-- DESC : Update button data
-- **************************************************************************
function TitanPanelPerformanceButton_UpdateData()
     local button = _G["TitanPanelPerformanceButton"];
     local showFPS = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowFPS");
     local showLatency = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowLatency");
     local showMemory = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowMemory");
     local showAddonMemory = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowAddonMemory");
     
     -- FPS Data
     if ( showFPS ) then
          button.fps = GetFramerate();     
          button.fpsSampleCount = button.fpsSampleCount + 1;
          if (button.fpsSampleCount == 1) then
               button.minFPS = button.fps;
               button.maxFPS = button.fps;
               button.avgFPS = button.fps;
          else
               if (button.fps < button.minFPS) then
                    button.minFPS = button.fps;
               elseif (button.fps > button.maxFPS) then
                    button.maxFPS = button.fps;
               end
               button.avgFPS = (button.avgFPS * (button.fpsSampleCount - 1) + button.fps) / button.fpsSampleCount;
          end
     end

     -- Latency Data
     if ( showLatency ) then
          button.bandwidthIn, button.bandwidthOut, button.latency = GetNetStats();
     end

     -- Memory data
     if ( showMemory ) or (showAddonMemory == 1) then
          local previousMemory = button.memory;     
          button.memory, button.gcThreshold = gcinfo();          
          if ( not button.startSessionTime ) then
               -- Initial data
               local i;
               button.startSessionTime = time();     
               button.initialMemory = button.memory;
                              
               	for i = 1, GetNumAddOns() do               
									memUsageSinceGC[GetAddOnInfo(i)] = GetAddOnMemoryUsage(i)
               	end
               
          elseif (previousMemory and button.memory and previousMemory > button.memory) then
               -- Reset data after garbage collection
               local k,i;
               button.startSessionTime = time();
               button.initialMemory = button.memory;
                              
               	for k in pairs(memUsageSinceGC) do
									memUsageSinceGC[k] = nil
               	end
               
               	for i = 1, GetNumAddOns() do
									memUsageSinceGC[GetAddOnInfo(i)] = GetAddOnMemoryUsage(i)
               	end                    
          end
     end     
end

-- **************************************************************************
-- NAME : TitanPanelPerformanceButton_ResetMemory()
-- DESC : Reset the memory monitoring values
-- **************************************************************************
--function TitanPanelPerformanceButton_ResetMemory()
    -- local button = _G["TitanPanelPerformanceButton"];
     --button.memory, button.gcThreshold = gcinfo();     
     --button.initialMemory = button.memory;
     --button.startSessionTime = time();
--end

-- **************************************************************************
-- NAME : Stats_UpdateAddonsList(self, watchingCPU)
-- DESC : Execute garbage collection for Leftclick on button
-- **************************************************************************
function Stats_UpdateAddonsList(self, watchingCPU)
	if(watchingCPU) then
		UpdateAddOnCPUUsage()
	else
		UpdateAddOnMemoryUsage()
	end

	local total = 0
	local i,j,k;
	local showAddonRate = TitanGetVar(TITAN_PERFORMANCE_ID, "ShowAddonIncRate");
	for i=1, GetNumAddOns() do
		local value = (watchingCPU and GetAddOnCPUUsage(i)) or GetAddOnMemoryUsage(i)
		local name = GetAddOnInfo(i)
		total = total + value

		for j,addon in ipairs(topAddOns) do
			if(value > addon.value) then                                                                                                                                                                                                                                         
				for k = counter, 1, -1 do
					if(k == j) then
						topAddOns[k].value = value
						topAddOns[k].name = GetAddOnInfo(i)
						break
					elseif(k ~= 1) then
						topAddOns[k].value = topAddOns[k-1].value
						topAddOns[k].name = topAddOns[k-1].name
					end
				end
				break
			end
		end
	end
	
	GameTooltip:AddLine(' ')

	if (total > 0) then
		if(watchingCPU) then
			GameTooltip:AddLine('|cffffffff'..L["TITAN_PERFORMANCE_ADDON_CPU_USAGE_LABEL"])
		else
			GameTooltip:AddLine('|cffffffff'..L["TITAN_PERFORMANCE_ADDON_MEM_USAGE_LABEL"])
		end
                
		if not watchingCPU then
			if (showAddonRate == 1) then
				GameTooltip:AddDoubleLine(LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_NAME_LABEL"],LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_USAGE_LABEL"].."/"..L["TITAN_PERFORMANCE_ADDON_RATE_LABEL"]..":")
			else
				GameTooltip:AddDoubleLine(LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_NAME_LABEL"],LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_USAGE_LABEL"]..":")
			end
		end
		
		if watchingCPU then
		   GameTooltip:AddDoubleLine(LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_NAME_LABEL"],LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_USAGE_LABEL"]..":")
		end
                                   
		for _,addon in ipairs(topAddOns) do
			if(watchingCPU) then
			  local diff = addon.value/total * 100;
			  local incrate = "";
			    incrate = format("(%.2f%%)", diff);
			    if (showAddonRate == 1) then 
			    GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format("%.3f",addon.value)..L["TITAN_MILLISECOND"].." "..GREEN_FONT_COLOR_CODE..incrate);
			    else
				  GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format("%.3f",addon.value)..L["TITAN_MILLISECOND"]);
				  end
			else
				local diff = addon.value - (memUsageSinceGC[addon.name])
				if diff < 0 or memUsageSinceGC[addon.name]== 0 then
					memUsageSinceGC[addon.name] = addon.value;
				end
				local incrate = "";
				if diff > 0 then
					incrate = format("(+%.2f) "..L["TITAN_KILOBYTES_PER_SECOND"], diff);
				end 
				if (showAddonRate == 1) then                    
					if TitanGetVar(TITAN_PERFORMANCE_ID, "AddonMemoryType") == 1 then                       
					GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format(L["TITAN_MEMORY_FORMAT"], addon.value/1000).." "..GREEN_FONT_COLOR_CODE..incrate)
					else
						if addon.value > 1000 then
							GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format(L["TITAN_MEMORY_FORMAT"], addon.value/1000).." "..GREEN_FONT_COLOR_CODE..incrate)
						else
							GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format(L["TITAN_MEMORY_FORMAT_KB"], addon.value).." "..GREEN_FONT_COLOR_CODE..incrate)
						end
					end
				else
					if TitanGetVar(TITAN_PERFORMANCE_ID, "AddonMemoryType") == 1 then
					GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format(L["TITAN_MEMORY_FORMAT"], addon.value/1000))
					else
						if addon.value > 1000 then
							GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format(L["TITAN_MEMORY_FORMAT"], addon.value/1000))
						else
							GameTooltip:AddDoubleLine(NORMAL_FONT_COLOR_CODE..addon.name," |cffffffff"..format(L["TITAN_MEMORY_FORMAT_KB"], addon.value))
						end
					end
				end
			end
		end
		
		GameTooltip:AddLine(' ')
		
		if(watchingCPU) then
			GameTooltip:AddDoubleLine(LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_TOTAL_CPU_USAGE_LABEL"], format("%.3f",total)..L["TITAN_MILLISECOND"])
		else
			if TitanGetVar(TITAN_PERFORMANCE_ID, "AddonMemoryType") == 1 then
			GameTooltip:AddDoubleLine(LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_TOTAL_MEM_USAGE_LABEL"],format(L["TITAN_MEMORY_FORMAT"], total/1000))
			else
				if total > 1000 then
					GameTooltip:AddDoubleLine(LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_TOTAL_MEM_USAGE_LABEL"], format(L["TITAN_MEMORY_FORMAT"], total/1000))
				else
					GameTooltip:AddDoubleLine(LIGHTYELLOW_FONT_COLOR_CODE..L["TITAN_PERFORMANCE_ADDON_TOTAL_MEM_USAGE_LABEL"], format(L["TITAN_MEMORY_FORMAT_KB"], total))
				end
			end
		end
	end
	
end


-- **************************************************************************
-- NAME : TitanPanelPerformanceButton_OnClick()
-- DESC : Execute garbage collection for Leftclick on button
-- **************************************************************************
function TitanPanelPerformanceButton_OnClick(self, button)
	if button == "LeftButton" then -- Claude: changed from collectgarbage() to toggle memory monitor
		MM_ToggleFrame()
	end
end

-- **************************************************************************
-- NAME : TitanPanelPerfControlSlider_OnEnter()
-- DESC : Display tooltip on entering slider
-- **************************************************************************
function TitanPanelPerfControlSlider_OnEnter(self)
     self.tooltipText = TitanOptionSlider_TooltipText(L["TITAN_PERFORMANCE_CONTROL_TOOLTIP"], TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons"));
     GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT");
     GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, 1);
end

-- **************************************************************************
-- NAME : TitanPanelPerfControlSlider_OnLeave()
-- DESC : Hide tooltip after leaving slider
-- **************************************************************************
function TitanPanelPerfControlSlider_OnLeave(self)
     self.tooltipText = nil;
     GameTooltip:Hide();
end

-- **************************************************************************
-- NAME : TitanPanelPerfControlSlider_OnShow()
-- DESC : Display slider tooltip
-- **************************************************************************
function TitanPanelPerfControlSlider_OnShow(self)     
     _G[self:GetName().."Text"]:SetText(TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons"));
     _G[self:GetName().."High"]:SetText(L["TITAN_PERFORMANCE_CONTROL_LOW"]);
     _G[self:GetName().."Low"]:SetText(L["TITAN_PERFORMANCE_CONTROL_HIGH"]);
     self:SetMinMaxValues(1, 40);
     self:SetValueStep(1);
     self:SetValue(41 - TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons"));
     TitanPanelPerfControlFrame:SetBackdropColor(0, 0, 0, 1)
     	
		TitanPanelPerfControlFrame:ClearAllPoints();
		TitanPanelPerfControlFrame:SetPoint("LEFT", "DropDownList2Button4ExpandArrow","RIGHT", 9/DropDownList2Button4ExpandArrow:GetScale(),0);
		local offscreenX, offscreenY = TitanUtils_GetOffscreen(TitanPanelPerfControlFrame);
		if offscreenX == -1 or offscreenX == 0 then
		  TitanPanelPerfControlFrame:ClearAllPoints();
			TitanPanelPerfControlFrame:SetPoint("LEFT", "DropDownList2Button4ExpandArrow","RIGHT", 9/DropDownList2Button4ExpandArrow:GetScale(),0);
		else
		  TitanPanelPerfControlFrame:ClearAllPoints();
			TitanPanelPerfControlFrame:SetPoint("RIGHT", "DropDownList2","LEFT", 3/DropDownList2Button4ExpandArrow:GetScale(),0);
		end		
end

-- **************************************************************************
-- NAME : TitanPanelPerfControlSlider_OnValueChanged(arg1)
-- DESC : Display slider tooltip text
-- VARS : arg1 = positive or negative change to apply
-- **************************************************************************
function TitanPanelPerfControlSlider_OnValueChanged(self, a1)
     _G[self:GetName().."Text"]:SetText(41 - self:GetValue());
     
     if a1 == -1 then
		self:SetValue(self:GetValue() + 1);
     end
     
     if a1 == 1 then
		self:SetValue(self:GetValue() - 1);
     end
     
     TitanSetVar(TITAN_PERFORMANCE_ID, "NumOfAddons", 41 - self:GetValue());
     
     local i;
     topAddOns = {};
     -- scan how many addons are active
		 local count = GetNumAddOns();
		 local ActiveAddons = 0;
		 for i=1, count do
			if IsAddOnLoaded(i) then
				ActiveAddons = ActiveAddons + 1;
			end
		 end
               
		 if ActiveAddons < TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons") then
			counter = ActiveAddons;
		 else
			counter = TitanGetVar(TITAN_PERFORMANCE_ID, "NumOfAddons");
		 end
		 
		 --set the counter to the proper number of active addons that are being monitored                
     for i=1, counter do
			topAddOns[i] = {name = '', value = 0}
     end
     
     -- Update GameTooltip
     if (self.tooltipText) then
          self.tooltipText = TitanOptionSlider_TooltipText(L["TITAN_PERFORMANCE_CONTROL_TOOLTIP"], 41 - self:GetValue());
          GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, 1);
     end
end

-- **************************************************************************
-- NAME : TitanPanelPerfControlFrame_OnLoad()
-- DESC : Create performance option frame
-- **************************************************************************
function TitanPanelPerfControlFrame_OnLoad(self)
     _G[self:GetName().."Title"]:SetText(L["TITAN_PERFORMANCE_CONTROL_TITLE"]);
     self:SetBackdropBorderColor(1, 1, 1);
     self:SetBackdropColor(0, 0, 0, 1);
end

-- **************************************************************************
-- NAME : TitanPanelPerfControlFrame_OnUpdate(elapsed)
-- DESC : If dropdown is visible, see if its timer has expired.  If so, hide frame
-- VARS : elapsed = <research>
-- **************************************************************************
function TitanPanelPerfControlFrame_OnUpdate(self, elapsed)
	if not MouseIsOver(_G["TitanPanelPerfControlFrame"]) and not MouseIsOver (_G["DropDownList2Button4"]) and not MouseIsOver (_G["DropDownList2Button4ExpandArrow"]) then
     TitanUtils_CheckFrameCounting(self, elapsed);
  end
end