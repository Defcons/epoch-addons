module 'aux.core.bagshui_compat'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local search_tab = require 'aux.tabs.search'
local post_tab = require 'aux.tabs.post'

local function bagshui_loaded()
	return IsAddOnLoaded('Bagshui')
		and _G.Bagshui
		and _G.Bagshui.prototypes
		and _G.Bagshui.prototypes.Inventory
end

local function aux_rightclick_enabled()
	local modified = get_modified and get_modified()
	local has_modifier = (modified == 1 or modified == true)
	return bagshui_loaded()
		and AuxFrame and AuxFrame:IsShown()
		and not has_modifier
end

local function get_selected_aux_top_tab()
	if not AuxFrame or not AuxFrame.GetChildren then return end

	for _, child in ipairs({ AuxFrame:GetChildren() }) do
		if child and child.GetObjectType and child:GetObjectType() == 'Button' then
			local font_string = child.GetFontString and child:GetFontString()
			local text = font_string and font_string.GetText and font_string:GetText()
			if (text == 'Search' or text == 'Post' or text == 'Auctions' or text == 'Bids')
				and child.IsEnabled and child:IsEnabled() == 0
			then
				return text
			end
		end
	end
end

local function route_to_aux_from_bagshui_slot(itemButton)
	if not itemButton or not itemButton.bagshuiData then return end

	local bag = itemButton.bagshuiData.bagNum
	local slot = itemButton.bagshuiData.slotNum
	if type(bag) ~= 'number' or type(slot) ~= 'number' then return end

	local item_info = info.container_item(bag, slot)
	if not item_info then return end

	local selected_tab = get_selected_aux_top_tab()

	local routed = nil
	if selected_tab == 'Post' and post_tab and type(post_tab.select_item) == 'function' then
		local is_auctionable = info.auctionable and info.auctionable(item_info.tooltip, nil, false)
		if not is_auctionable or item_info.lootable then
			return true
		end
		if type(set_tab) == 'function' then
			set_tab(2)
		end
		local key_a = item_info.item_key
		local key_b = nil
		if item_info.item_id then
			key_b = tostring(item_info.item_id) .. ':' .. tostring(item_info.suffix_id or 0)
		end
		if type(post_tab.update_inventory_records) == 'function' then
			post_tab.update_inventory_records()
		end
		if key_a then
			post_tab.select_item(key_a)
		end
		if key_b and key_b ~= key_a then
			post_tab.select_item(key_b)
		end
		routed = true
	end
	if selected_tab == 'Search'
		and search_tab
		and type(search_tab.set_filter) == 'function'
		and item_info.name
		and item_info.name ~= ''
	then
		if type(set_tab) == 'function' then
			set_tab(1)
		end
		search_tab.set_filter(strlower(item_info.name) .. '/exact')
		routed = true
	end
	return routed
end

local function install_bagshui_click_hook()
	if not bagshui_loaded() then return end

	local Inventory = _G.Bagshui.prototypes.Inventory
	if not Inventory or Inventory.__aux_bagshui_compat_hooked then return end

	local orig = Inventory.ItemButton_OnClick
	if type(orig) ~= 'function' then return end

	Inventory.ItemButton_OnClick = function(self, mouseButton, isDrag)
		if mouseButton == 'RightButton' and not isDrag and aux_rightclick_enabled() then
			local itemButton = _G.this
			if route_to_aux_from_bagshui_slot(itemButton) then
				return
			end
		end
		return orig(self, mouseButton, isDrag)
	end

	Inventory.__aux_bagshui_compat_hooked = true
end

do
	local f = CreateFrame('Frame')
	f:RegisterEvent('PLAYER_LOGIN')
	f:RegisterEvent('ADDON_LOADED')
	f:SetScript('OnEvent', function()
		if event == 'PLAYER_LOGIN' or (event == 'ADDON_LOADED' and arg1 == 'Bagshui') then
			install_bagshui_click_hook()
		end
	end)
end
