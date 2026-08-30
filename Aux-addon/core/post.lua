module 'aux.core.post'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local stack = require 'aux.core.stack'

local state

local function find_post_slot()
	local best_slot, best_item_info
	for slot in info.inventory do
		local item_info = temp-info.container_item(unpack(slot))
		if item_info
			and item_info.item_key == state.item_key
			and info.auctionable(item_info.tooltip, nil, true)
			and not item_info.lootable
		then
			if not best_item_info or item_info.count > best_item_info.count then
				best_slot, best_item_info = copy(slot), item_info
			end
		end
	end
	return best_slot, best_item_info
end

function process()
	if not state then
		return
	end
	if state.posted < state.count then

		local stacking_complete

		local send_signal, signal_received = signal()
		when(signal_received, function()
			if not state then
				return
			end
			local slot = signal_received()[1]
			if slot then
				return post_auction(slot, process)
			else
				return stop()
			end
		end)

		return stack.start(state.item_key, state.stack_size, send_signal)
	end

	return stop()
end

function M.start_direct(item_key, stack_size, duration, unit_start_price, unit_buyout_price, count, callback)
	stop()
	state = {
		item_key = item_key,
		stack_size = stack_size,
		duration = duration,
		unit_start_price = unit_start_price,
		unit_buyout_price = unit_buyout_price,
		count = count,
		posted = 0,
		callback = callback,
	}

	local slot = find_post_slot()
	if not slot then
		return stop()
	end

	local post_count = count
	if post_count < 1 then
		return stop()
	end

	local start_price = max(1, round(unit_start_price * stack_size))
	local buyout_price = round(unit_buyout_price * stack_size)

	ClearCursor()
	ClickAuctionSellItemButton()
	ClearCursor()
	PickupContainerItem(unpack(slot))
	ClickAuctionSellItemButton()
	ClearCursor()

	local send_signal, signal_received = signal()
	thread(when, signal_received, function()
		if not state then
			return
		end
		local success = signal_received()[1]
		if success then
			state.posted = post_count
		end
		return stop()
	end)

	local system_listener_id
	system_listener_id = event_listener('CHAT_MSG_SYSTEM', function(kill)
		if arg1 == ERR_AUCTION_STARTED then
			send_signal(true)
			kill()
		end
	end)
	thread(when, later(6), function()
		kill_listener(system_listener_id)
		send_signal(false)
	end)

	StartAuction(start_price, buyout_price, duration, stack_size, post_count)
end

function post_auction(slot, k)
	if not state then
		return
	end
	local item_info = info.container_item(unpack(slot))
	if not item_info then
		return stop()
	end
	if item_info.item_key == state.item_key and info.auctionable(item_info.tooltip, nil, true) and item_info.aux_quantity == state.stack_size then
        
		ClearCursor()
		ClickAuctionSellItemButton()
		ClearCursor()
		PickupContainerItem(unpack(slot))
		ClickAuctionSellItemButton()
		ClearCursor()
		local start_price = max(1, round(state.unit_start_price * item_info.aux_quantity))
		local buyout_price = round(state.unit_buyout_price * item_info.aux_quantity)
		StartAuction(start_price, buyout_price, state.duration)

		local send_signal, signal_received = signal()
		when(signal_received, function()
			if not state then
				return
			end
			local success = signal_received()[1]
			if success then
				state.posted = state.posted + 1
				return k()
			else
				return stop()
			end
		end)

		local posted
		local system_listener_id
		system_listener_id = event_listener('CHAT_MSG_SYSTEM', function(kill)
			if arg1 == ERR_AUCTION_STARTED then
				send_signal(true)
				kill()
			end
		end)
		thread(when, later(6), function()
			kill_listener(system_listener_id)
			send_signal(false)
		end)
	else
		return stop()
	end
end

function M.stop()
	if state then
		kill_thread(state.thread_id)

		local callback = state.callback
		local posted = state.posted

		state = nil

		if callback then
			callback(posted)
		end
	end
end

function M.start(item_key, stack_size, duration, unit_start_price, unit_buyout_price, count, callback)
	stop()
	state = {
		thread_id = thread(process),
		item_key = item_key,
		stack_size = stack_size,
		duration = duration,
		unit_start_price = unit_start_price,
		unit_buyout_price = unit_buyout_price,
		count = count,
		posted = 0,
		callback = callback,
	}
end
