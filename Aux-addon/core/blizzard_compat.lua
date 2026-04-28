module 'aux.core.blizzard_compat'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local search_tab = require 'aux.tabs.search'
local post_tab = require 'aux.tabs.post'

local hooked_buttons = {}
local hooks_active = false

local function use_blizzard_bags()
	return not IsAddOnLoaded('pfUI')
end

local function aux_rightclick_enabled()
	local modified = get_modified and get_modified()
	local has_modifier = (modified == 1 or modified == true)
	return use_blizzard_bags()
		and AuxFrame and AuxFrame:IsShown()
		and not has_modifier
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

	local routed = nil
	if search_tab and type(search_tab.set_filter) == 'function' and item_info.name then
		search_tab.set_filter(strlower(item_info.name) .. '/exact')
		routed = true
	end
	if post_tab and type(post_tab.select_item) == 'function' and item_info.item_key then
		post_tab.select_item(item_info.item_key)
		routed = true
	end
	return routed
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
