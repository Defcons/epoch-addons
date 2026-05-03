module 'aux.core.bagshui_compat'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local search_tab = require 'aux.tabs.search'
local post_tab = require 'aux.tabs.post'
local selected_aux_top_tab = 'Search'

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
				selected_aux_top_tab = text
				return text
			end
		end
	end

	return selected_aux_top_tab
end

local function install_aux_tab_tracking()
	if not AuxFrame or not AuxFrame.GetChildren or AuxFrame.__aux_bagshui_tab_tracking then return end

	for _, child in ipairs({ AuxFrame:GetChildren() }) do
		if child and child.GetObjectType and child:GetObjectType() == 'Button' then
			local font_string = child.GetFontString and child:GetFontString()
			local text = font_string and font_string.GetText and font_string:GetText()
			if text == 'Search' or text == 'Post' or text == 'Auctions' or text == 'Bids' then
				child:HookScript('OnClick', function()
					selected_aux_top_tab = text
				end)
			end
		end
	end

	AuxFrame.__aux_bagshui_tab_tracking = true
end

local function get_search_name(item_info, bagshui_item)
	if bagshui_item and bagshui_item.baseName and bagshui_item.baseName ~= '' then
		return bagshui_item.baseName
	end
	if item_info and item_info.item_id then
		local base_item = info.item(item_info.item_id)
		if base_item and base_item.name and base_item.name ~= '' then
			return base_item.name
		end
	end
	return item_info and item_info.name
end

local function route_to_aux_search(item_info, bagshui_item)
	local search_name = get_search_name(item_info, bagshui_item)
	if not (search_tab and type(search_tab.set_filter) == 'function' and search_name and search_name ~= '') then
		return
	end
	if type(set_tab) == 'function' then
		set_tab(1)
	end
	search_tab.set_filter(strlower(search_name) .. '/exact')
	if type(search_tab.execute) == 'function' then
		search_tab.execute(nil, false)
	end
	return true
end

local function route_to_aux_post(item_info)
	if not (post_tab and type(post_tab.select_item) == 'function') then
		return
	end
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
	return true
end

local function route_to_aux_from_bagshui_slot(itemButton)
	if not itemButton or not itemButton.bagshuiData then
		return
	end

	local bag = itemButton.bagshuiData.bagNum
	local slot = itemButton.bagshuiData.slotNum
	if type(bag) ~= 'number' or type(slot) ~= 'number' then
		return
	end

	local item_info = info.container_item(bag, slot)
	if not item_info then
		return
	end

	local selected_tab = get_selected_aux_top_tab()
	local bagshui_item = itemButton.bagshuiData.item

	if selected_tab == 'Post' then
		return route_to_aux_post(item_info)
	end
	if selected_tab == 'Search' then
		return route_to_aux_search(item_info, bagshui_item)
	end
end

local function install_bagshui_click_hook()
	if not bagshui_loaded() then return end

	local Inventory = _G.Bagshui.prototypes.Inventory
	if not Inventory or Inventory.__aux_bagshui_compat_hooked then return end

	local orig_is_secure_rightclick_use_allowed = Inventory.IsSecureRightClickUseAllowed
	if type(orig_is_secure_rightclick_use_allowed) == 'function' then
		Inventory.IsSecureRightClickUseAllowed = function(self)
			if AuxFrame and AuxFrame:IsShown() then
				return false
			end
			return orig_is_secure_rightclick_use_allowed(self)
		end
	end

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
	f:RegisterEvent('AUCTION_HOUSE_SHOW')
	f:SetScript('OnEvent', function()
		if event == 'AUCTION_HOUSE_SHOW' then
			selected_aux_top_tab = 'Search'
			install_aux_tab_tracking()
			install_bagshui_click_hook()
		elseif event == 'PLAYER_LOGIN' or (event == 'ADDON_LOADED' and arg1 == 'Bagshui') then
			install_aux_tab_tracking()
			install_bagshui_click_hook()
		end
	end)
end
