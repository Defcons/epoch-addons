module 'aux.core.blizzard_compat'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local search_tab = require 'aux.tabs.search'
local post_tab = require 'aux.tabs.post'

local hooked_buttons = {}
local hooks_active = false
local selected_aux_top_tab = 'Search'

local function use_blizzard_bags()
	return true
end

local function aux_rightclick_enabled()
	local modified = get_modified and get_modified()
	local has_modifier = (modified == 1 or modified == true)
	return use_blizzard_bags()
		and AuxFrame and AuxFrame:IsShown()
		and not has_modifier
end

local function get_selected_aux_top_tab()
	if not AuxFrame or not AuxFrame.GetChildren then return selected_aux_top_tab end

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
	if not AuxFrame or not AuxFrame.GetChildren or AuxFrame.__aux_blizzard_tab_tracking then return end

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

	AuxFrame.__aux_blizzard_tab_tracking = true
end

local function get_search_name(item_info)
	if item_info and item_info.item_id then
		local base_item = info.item(item_info.item_id)
		if base_item and base_item.name and base_item.name ~= '' then
			return base_item.name
		end
	end
	return item_info and item_info.name
end

local function route_to_aux_search(item_info)
	local search_name = get_search_name(item_info)
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
	if type(post_tab.update_inventory_records) == 'function' then
		post_tab.update_inventory_records()
	end
	post_tab.select_item(item_info.item_key)
	return true
end

local function each_container_button(visitor)
	local max_frames = _G.NUM_CONTAINER_FRAMES or 13
	local max_items = _G.MAX_CONTAINER_ITEMS or 36
	for i = 1, max_frames do
		local frame = _G['ContainerFrame' .. i]
		if frame then
			for slot = 1, max_items do
				local button = _G[frame:GetName() .. 'Item' .. slot]
				if button then
					visitor(button, frame, slot)
				end
			end
		end
	end
end

local function route_to_aux_from_button(item_button)
	if not item_button then return end

	local parent = item_button:GetParent()
	local bag = parent and parent:GetID()
	local slot = item_button:GetID()
	if type(bag) ~= 'number' or type(slot) ~= 'number' then return end

	local item_info = info.container_item(bag, slot)
	if not item_info then return end

	local selected_tab = get_selected_aux_top_tab()
	if selected_tab == 'Search' then
		return route_to_aux_search(item_info)
	end
	if selected_tab == 'Post' then
		return route_to_aux_post(item_info)
	end
end

local function button_onmouseup(self, button)
	local click_button = button or _G.arg1
	if click_button == 'RightButton' and aux_rightclick_enabled() then
		route_to_aux_from_button(self or _G.this)
	end
end

local function install_button_hooks()
	if not use_blizzard_bags() then return end

	each_container_button(function(button)
		if not hooked_buttons[button] then
			button:HookScript('OnMouseUp', button_onmouseup)
			hooked_buttons[button] = true
		end
	end)
end

local function set_rightclick_enabled(enabled)
	if not use_blizzard_bags() then return end

	each_container_button(function(button)
		if button.RegisterForClicks then
			if enabled then
				button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
			else
				button:RegisterForClicks('LeftButtonUp')
			end
		end
	end)
end

do
	local f = CreateFrame('Frame')
	f:RegisterEvent('PLAYER_ENTERING_WORLD')
	f:RegisterEvent('BAG_UPDATE')
	f:RegisterEvent('AUCTION_HOUSE_SHOW')
	f:RegisterEvent('AUCTION_HOUSE_CLOSED')
	f:RegisterEvent('PLAYER_LOGOUT')
	f:SetScript('OnUpdate', function()
		if hooks_active and (not AuxFrame or not AuxFrame:IsShown()) then
			hooks_active = false
			set_rightclick_enabled(true)
		end
	end)
	f:SetScript('OnEvent', function()
		if event == 'AUCTION_HOUSE_SHOW' then
			selected_aux_top_tab = 'Search'
			install_aux_tab_tracking()
			hooks_active = true
			install_button_hooks()
			set_rightclick_enabled(false)
		elseif event == 'BAG_UPDATE' or event == 'PLAYER_ENTERING_WORLD' then
			install_button_hooks()
			if hooks_active then
				set_rightclick_enabled(false)
			else
				set_rightclick_enabled(true)
			end
		else
			hooks_active = false
			set_rightclick_enabled(true)
		end
	end)
end
