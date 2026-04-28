module 'aux.core.pfui_compat'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local search_tab = require 'aux.tabs.search'
local post_tab = require 'aux.tabs.post'

local hooked_slots = {}
local hooks_active = false
local tooltip_guard_installed = false

local function pfui_loaded()
	return IsAddOnLoaded('pfUI')
		and _G.pfUI
		and _G.pfUI.bags
end

local function aux_rightclick_enabled()
	local modified = get_modified and get_modified()
	local has_modifier = (modified == 1 or modified == true)
	return pfui_loaded()
		and AuxFrame and AuxFrame:IsShown()
		and not has_modifier
end

local function route_to_aux_from_slot(slot_frame)
	if not slot_frame then return end

	local bag = slot_frame.__aux_bag_id or slot_frame.bag
	local slot = slot_frame.__aux_slot_id or slot_frame.slot

	if type(bag) ~= 'number' then
		local parent = slot_frame:GetParent()
		bag = parent and parent:GetID()
	end
	if type(slot) ~= 'number' then
		slot = slot_frame:GetID()
	end
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

local function slot_onclick_wrapper(self, button)
	local frame = self or _G.this
	local click_button = button or _G.arg1
	if click_button == 'RightButton' and aux_rightclick_enabled() then
		route_to_aux_from_slot(frame)
	end
end

local function set_slot_rightclick_enabled(enabled)
	if not pfui_loaded() then return end

	for _, bag_data in pairs(_G.pfUI.bags or empty) do
		if bag_data and bag_data.slots then
			for _, slot_data in pairs(bag_data.slots) do
				local frame = slot_data and slot_data.frame
				if frame then
					if enabled then
						frame:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
					else
						frame:RegisterForClicks('LeftButtonUp')
					end
				end
			end
		end
	end
end

local function install_slot_hooks()
	if not pfui_loaded() then return end

	for bag_id, bag_data in pairs(_G.pfUI.bags or empty) do
		if bag_data and bag_data.slots then
			for slot_id, slot_data in pairs(bag_data.slots) do
				local frame = slot_data and slot_data.frame
				if frame then
					frame.__aux_bag_id = bag_id
					frame.__aux_slot_id = slot_id
				end
				if frame and not hooked_slots[frame] then
					frame:HookScript('OnMouseUp', slot_onclick_wrapper)
					hooked_slots[frame] = true
				end
			end
		end
	end
end

local function is_pfui_bag_tooltip()
	local owner = GameTooltip and GameTooltip:GetOwner()
	local owner_name = owner and owner.GetName and owner:GetName()
	return owner_name and strfind(owner_name, '^pfBag')
end

local function install_tooltip_guard()
	if tooltip_guard_installed or not pfui_loaded() or not GameTooltip or not GameTooltip.SetBagItem then return end

	local set_bag_item = GameTooltip.SetBagItem
	GameTooltip.SetBagItem = function(self, bag, slot)
		if is_pfui_bag_tooltip() then
			return
		end
		return set_bag_item(self, bag, slot)
	end
	tooltip_guard_installed = true
end

set_LOAD(function()
	install_tooltip_guard()
end)

set_LOAD2(function()
	if _G.aux and _G.aux.account then
		_G.aux.account.pfui_compat_loaded = 1
	end
	install_tooltip_guard()
end)

do
	local f = CreateFrame('Frame')
	f:RegisterEvent('AUCTION_HOUSE_SHOW')
	f:RegisterEvent('AUCTION_HOUSE_CLOSED')
	f:RegisterEvent('BAG_UPDATE')
	f:RegisterEvent('PLAYER_LOGOUT')
	f:SetScript('OnUpdate', function()
		if hooks_active and (not AuxFrame or not AuxFrame:IsShown()) then
			hooks_active = false
			set_slot_rightclick_enabled(true)
		end
	end)
	f:SetScript('OnEvent', function()
		install_tooltip_guard()
		if event == 'AUCTION_HOUSE_SHOW' then
			hooks_active = true
			install_slot_hooks()
			set_slot_rightclick_enabled(false)
		elseif event == 'BAG_UPDATE' then
			if hooks_active then
				install_slot_hooks()
				set_slot_rightclick_enabled(false)
			end
		else
			hooks_active = false
			set_slot_rightclick_enabled(true)
		end
	end)
end
