module 'aux.tabs.post'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local sort_util = require 'aux.util.sort'
local persistence = require 'aux.util.persistence'
local money = require 'aux.util.money'
local scan_util = require 'aux.util.scan'
local post = require 'aux.core.post'
local scan = require 'aux.core.scan'
local history = require 'aux.core.history'
local cache = require 'aux.core.cache'
local item_listing = require 'aux.gui.item_listing'
local al = require 'aux.gui.auction_listing'

TAB 'Post'

local DURATION_12, DURATION_24, DURATION_48 = 1, 2, 3

local settings_schema = {'tuple', '#', {duration='number'}, {start_price='number'}, {buyout_price='number'}, {hidden='boolean'}}

local scan_id, inventory_records, bid_records, buyout_records = 0, {}, {}, {}

function get_default_settings()
	return O('duration', DURATION_12, 'start_price', 0, 'buyout_price', 0, 'hidden', false)
end

function LOAD2()
	data = faction_data'post'
end

function read_settings(item_key)
	item_key = item_key or selected_item.key
	return data[item_key] and persistence.read(settings_schema, data[item_key]) or get_default_settings() -- Claude: was 'default_settings' (nil); call the function
end
function write_settings(settings, item_key)
	item_key = item_key or selected_item.key
	data[item_key] = persistence.write(settings_schema, settings)
end

do
	local bid_selections, buyout_selections = {}, {}
	function get_bid_selection()
		return bid_selections[selected_item.key]
	end
	function set_bid_selection(record)
		bid_selections[selected_item.key] = record
	end
	function get_buyout_selection()
		return buyout_selections[selected_item.key]
	end
	function set_buyout_selection(record)
		buyout_selections[selected_item.key] = record
	end
end

function refresh_button_click()
	scan.abort(scan_id)
	refresh_entries()
	refresh = true
end

do
	local item
	function get_selected_item() return item end
	function set_selected_item(v) item = v end
end

do
	local c = 0
	function get_refresh() return c end
	function set_refresh(v) c = v end
end

do
	local override = false
	function get_user_price_override() return override end
	function set_user_price_override(v) override = v end
end

function OPEN()
    frame:Show()
    update_inventory_records()
    refresh = true
end

function CLOSE()
    selected_item = nil
    frame:Hide()
end

function USE_ITEM(item_id, suffix_id)
	select_item(item_id .. ':' .. suffix_id)
end

function get_unit_start_price()
	return selected_item and (read_settings().start_price or 0) or 0 -- Claude: guard nil field
end

function set_unit_start_price(amount)
	local settings = read_settings()
	settings.start_price = amount
	write_settings(settings)
end

function get_unit_buyout_price()
	return selected_item and (read_settings().buyout_price or 0) or 0 -- Claude: guard nil field
end

function set_unit_buyout_price(amount)
	local settings = read_settings()
	settings.buyout_price = amount
	write_settings(settings)
end

do
	local last_scroll_target = nil
	function update_inventory_listing()
		local records = values(filter(copy(inventory_records), function(record)
			local settings = read_settings(record.key)
			return record.aux_quantity > 0 and (not settings.hidden or show_hidden_checkbox:GetChecked())
		end))
		sort(records, function(a, b) return a.name < b.name end)
		item_listing.populate(inventory_listing, records)
		-- Scroll the list to keep the selected item visible when it changes
		if selected_item and selected_item ~= last_scroll_target then
			item_listing.scroll_to(inventory_listing, selected_item)
			last_scroll_target = selected_item
		end
		-- Auto-select first item when nothing is currently selected
		if not selected_item and getn(records) > 0 then
			update_item(records[1])
		end
	end
end

function update_auction_listing(listing, records, reference)
	local rows = T
	if selected_item then
		local historical_value = history.value(selected_item.key)
		local stack_size = stack_size_slider:GetValue()
		for _, record in pairs(records[selected_item.key] or empty) do
			local price_color = undercut(record, stack_size_slider:GetValue(), listing == 'bid') < reference and color.red
			local price = record.unit_price * (listing == 'bid' and record.stack_size / stack_size_slider:GetValue() or 1)
			tinsert(rows, O(
				'cols', A(
				O('value', record.own and color.green(record.count) or record.count),
				O('value', al.time_left(record.duration)),
				O('value', record.stack_size == stack_size and color.green(record.stack_size) or record.stack_size),
				O('value', money.to_string(price, true, nil, price_color)),
				O('value', historical_value and al.percentage_historical(round(price / historical_value * 100)) or '---')
			),
				'record', record
			))
		end
		if historical_value then
			tinsert(rows, O(
				'cols', A(
				O('value', '---'),
				O('value', '---'),
				O('value', '---'),
				O('value', money.to_string(historical_value, true, nil, color.green)),
				O('value', historical_value and al.percentage_historical(100) or '---')
			),
				'record', O('historical_value', true, 'stack_size', stack_size, 'unit_price', historical_value, 'own', true)
			))
		end
		sort(rows, function(a, b)
			return sort_util.multi_lt(
				a.record.unit_price * (listing == 'bid' and a.record.stack_size or 1),
				b.record.unit_price * (listing == 'bid' and b.record.stack_size or 1),

				a.record.historical_value and 1 or 0,
				b.record.historical_value and 1 or 0,

				b.record.own and 0 or 1,
				a.record.own and 0 or 1,

				a.record.stack_size,
				b.record.stack_size,

				a.record.duration,
				b.record.duration
			)
		end)
	end
	if listing == 'bid' then
		bid_listing:SetData(rows)
		-- No auto-select for bid_selection: its stack-based unit_price can produce
		-- a start price far above the buyout price, disabling the Post button.
		-- bid_selection is set only when the user manually clicks a bid row.
	elseif listing == 'buyout' then
		buyout_listing:SetData(rows)
		-- Auto-select first real auction row unless the user has manually typed a price
		if not buyout_selection and not user_price_override then
			for i = 1, getn(rows) do
				if not rows[i].record.historical_value then
					buyout_selection = rows[i].record
					refresh = true
					break
				end
			end
		end
	end
end

function update_auction_listings()
	update_auction_listing('bid', bid_records, unit_start_price)
	update_auction_listing('buyout', buyout_records, unit_buyout_price)
end

function M.select_item(item_key)
    for _, inventory_record in pairs(filter(copy(inventory_records), function(record) return record.aux_quantity > 0 end)) do
        if inventory_record.key == item_key then
            update_item(inventory_record)
            return
        end
    end
end

function price_update()
    if selected_item then
        local historical_value = history.value(selected_item.key)
        if bid_selection or buyout_selection then
	        unit_start_price = undercut(bid_selection or buyout_selection, stack_size_slider:GetValue(), bid_selection)
	        unit_start_price_input:SetText(money.to_string(unit_start_price, true, nil, nil, true))
        end
        if buyout_selection then
	        unit_buyout_price = undercut(buyout_selection, stack_size_slider:GetValue())
	        unit_buyout_price_input:SetText(money.to_string(unit_buyout_price, true, nil, nil, true))
        end
        start_price_percentage:SetText(historical_value and al.percentage_historical(round(unit_start_price / historical_value * 100)) or '---')
        buyout_price_percentage:SetText(historical_value and al.percentage_historical(round(unit_buyout_price / historical_value * 100)) or '---')
    end
end

function post_auctions()
	if selected_item then
        local unit_start_price = unit_start_price
        local unit_buyout_price = unit_buyout_price
        local stack_size = stack_size_slider:GetValue()
        local stack_count
        stack_count = stack_count_slider:GetValue()
        local duration = UIDropDownMenu_GetSelectedValue(duration_dropdown)
		local key = selected_item.key

        -- local duration_code
		-- if duration == DURATION_2 then
            -- duration_code = 2
		-- elseif duration == DURATION_8 or duration == DURATION_12 then
            -- duration_code = 3
		-- elseif duration == DURATION_24 or duration == DURATION_48 then
            -- duration_code = 4
		-- end

		post.start(
			key,
			stack_size,
			duration,
            unit_start_price,
            unit_buyout_price,
			stack_count,
			function(posted)
				for i = 1, posted do
                    record_auction(key, stack_size, unit_start_price * stack_size, unit_buyout_price, duration + 1, UnitName'player')
                end
                update_inventory_records()
                -- Build sorted, filtered inventory list to find the next item
                local old_name = selected_item and selected_item.name or ''
                local filtered = values(filter(copy(inventory_records), function(record)
                    local settings = read_settings(record.key)
                    return record.aux_quantity > 0 and (not settings.hidden or show_hidden_checkbox:GetChecked())
                end))
                sort(filtered, function(a, b) return a.name < b.name end)
                if getn(filtered) > 0 then
                    local next_item = nil
                    -- Find first item strictly after the old item alphabetically (advance forward)
                    for i = 1, getn(filtered) do
                        if filtered[i].name > old_name then
                            next_item = filtered[i]
                            break
                        end
                    end
                    -- Fallback: stay on same item if it still has quantity
                    if not next_item then
                        for _, record in pairs(filtered) do
                            if record.key == key then
                                next_item = record
                                break
                            end
                        end
                    end
                    -- Last resort: take the last item in the list
                    if not next_item then
                        next_item = filtered[getn(filtered)]
                    end
                    selected_item = nil
                    update_item(next_item)
                else
                    selected_item = nil
                end
                refresh = true
			end
		)
	end
end

function select_next_item()
    local filtered = values(filter(copy(inventory_records), function(record)
        local settings = read_settings(record.key)
        return record.aux_quantity > 0 and (not settings.hidden or show_hidden_checkbox:GetChecked())
    end))
    sort(filtered, function(a, b) return a.name < b.name end)
    if getn(filtered) == 0 then return end
    if not selected_item then
        selected_item = nil
        update_item(filtered[1])
        return
    end
    local old_name = selected_item.name
    local next_item = nil
    for i = 1, getn(filtered) do
        if filtered[i].name > old_name then
            next_item = filtered[i]
            break
        end
    end
    -- Wrap around to first item if we were on the last one
    if not next_item then
        next_item = filtered[1]
    end
    selected_item = nil
    update_item(next_item)
end

do
    local buyout_state = 'idle'  -- 'idle', 'searching', 'found'
    local buyout_index = nil
    local buyout_price_total = nil

    function reset_buyout_state()
        buyout_state = 'idle'
        buyout_index = nil
        buyout_price_total = nil
    end

    function get_buyout_state_value()
        return buyout_state
    end

    function buyout_selected_auction()
        if buyout_state == 'found' then
            -- This click IS a hardware event — safe to call place_bid here
            local index = buyout_index
            local price = buyout_price_total
            reset_buyout_state()
            place_bid('list', index, price, function()
                status_bar:update_status(1, 1)
                status_bar:set_text('Buyout complete')
                refresh_button_click()
            end)
            return
        end

        if buyout_state == 'searching' then return end

        -- idle: validate then begin scan
        if not selected_item or not buyout_selection or buyout_selection.own then return end
        if bid_in_progress then return end

        local target_unit_price = buyout_selection.unit_price
        local target_stack_size = buyout_selection.stack_size
        local item_key = selected_item.key
        local query = scan_util.item_query(selected_item.item_id)
        if not query then return end

        buyout_state = 'searching'
        status_bar:update_status(0, 0)
        status_bar:set_text('Searching auction to buyout...')

        local found = false
        scan.start{
            type = 'list',
            ignore_owner = true,
            queries = A(query),
            on_page_loaded = function(page, total_pages)
                status_bar:update_status(page / total_pages, 0)
                status_bar:set_text(format('Searching auction... Page %d / %d', page, total_pages))
            end,
            on_auction = function(auction_record)
                if not found
                    and auction_record.item_key == item_key
                    and auction_record.unit_buyout_price == target_unit_price
                    and auction_record.aux_quantity == target_stack_size
                    and not cache.is_player(auction_record.owner) then
                    found = true
                    scan.stop()
                    buyout_index = auction_record.index
                    buyout_price_total = auction_record.buyout_price
                    buyout_state = 'found'
                    status_bar:update_status(1, 1)
                    status_bar:set_text('Auction found - click Buyout again to confirm')
                end
            end,
            on_complete = function()
                if not found then
                    reset_buyout_state()
                    status_bar:update_status(1, 1)
                    status_bar:set_text('Auction not found for buyout')
                end
            end,
            on_abort = function()
                if not found then
                    reset_buyout_state()
                    status_bar:update_status(1, 1)
                    status_bar:set_text('Buyout scan aborted')
                end
            end,
        }
    end
end

function validate_parameters()
    -- Next button: enabled whenever there are items in the inventory
    if getn(inventory_records) > 0 then
        next_item_button:Enable()
    else
        next_item_button:Disable()
    end
    -- Buyout button: state-machine driven
    local bstate = get_buyout_state_value()
    if bstate == 'found' then
        -- Auction located — enable so user can confirm with a second click
        buyout_auction_button:Enable()
    elseif bstate == 'searching' then
        buyout_auction_button:Disable()
    elseif buyout_selection and not buyout_selection.own and not bid_in_progress then
        buyout_auction_button:Enable()
    else
        buyout_auction_button:Disable()
    end
    -- Post button
    if not selected_item then
        post_button:Disable()
        return
    end
    if unit_buyout_price > 0 and unit_start_price > unit_buyout_price then
        post_button:Disable()
        return
    end
    if unit_start_price == 0 then
        post_button:Disable()
        return
    end
    if stack_count_slider:GetValue() == 0 then
        post_button:Disable()
        return
    end
    post_button:Enable()
end

function update_item_configuration()
    if not selected_item then
        refresh_button:Disable()

        item.texture:SetTexture(nil)
        item.count:SetText()
        item.name:SetTextColor(color.label.enabled())
        item.name:SetText('No item selected')

        unit_start_price_input:Hide()
        unit_buyout_price_input:Hide()
        stack_size_slider:Hide()
        stack_count_slider:Hide()
        deposit:Hide()
        duration_dropdown:Hide()
        hide_checkbox:Hide()
    else
        unit_start_price_input:Show()
        unit_buyout_price_input:Show()
        stack_size_slider:Show()
        stack_count_slider:Show()
        deposit:Show()
        duration_dropdown:Show()
        hide_checkbox:Show()

        item.texture:SetTexture(selected_item.texture)
        item.name:SetText('[' .. selected_item.name .. ']')
        do
            local color = ITEM_QUALITY_COLORS[selected_item.quality]
            item.name:SetTextColor(color.r, color.g, color.b)
        end
        if selected_item.aux_quantity > 1 then
            item.count:SetText(selected_item.aux_quantity)
        else
            item.count:SetText()
        end

        stack_size_slider.editbox:SetNumber(stack_size_slider:GetValue())
        stack_count_slider.editbox:SetNumber(stack_count_slider:GetValue())

        local deposit_factor = UnitFactionGroup'npc' and 0.15 or 0.75
        local duration_value = UIDropDownMenu_GetSelectedValue(duration_dropdown)
        local duration_hours = duration_value == DURATION_12 and 12 or duration_value == DURATION_24 and 24 or duration_value == DURATION_48 and 48 or nil
        local duration_factor = duration_hours and (duration_hours / 12) or nil
        local stack_size = selected_item.max_charges and 1 or stack_size_slider:GetValue()
        local stack_count = stack_count_slider:GetValue()

            -- Always prefer GetItemInfo vendor sell price (return #11) as it is reliable
        -- in 3.3.5. Only fall back to the scanned unit_vendor_price when GetItemInfo
        -- returns nothing (e.g. item not yet cached by the client).
        local vendor_price = nil
        if selected_item.item_id then
            local gi_price = select(11, GetItemInfo(selected_item.item_id))
            if gi_price and gi_price > 0 then
                vendor_price = gi_price
            end
        end
        if (not vendor_price or vendor_price == 0) then
            vendor_price = selected_item.unit_vendor_price
        end

        local amount = 0
        if vendor_price and vendor_price > 0 and duration_factor then
            amount = floor(vendor_price * deposit_factor * stack_size) * stack_count * duration_factor
            local min_deposit = 100 * stack_count
            if amount < min_deposit then
                amount = min_deposit
            end
        else
            amount = 100 * stack_count
        end

        deposit:SetText('Deposit: ' .. money.to_string(amount, nil, nil, color.text.enabled))

        refresh_button:Enable()
    end
end


function undercut(record, stack_size, stack)
    local price = ceil(record.unit_price * (stack and record.stack_size or stack_size))
    if not record.own then
	    price = price - 1
    end
    return price / stack_size
end

function quantity_update(maximize_count)
    if selected_item then
        local max_stack_count = selected_item.max_charges and selected_item.availability[stack_size_slider:GetValue()] or floor(selected_item.availability[0] / stack_size_slider:GetValue())
        stack_count_slider:SetMinMaxValues(1, max_stack_count)
        if maximize_count then
            stack_count_slider:SetValue(max_stack_count)
        end
    end
    refresh = true
end

function unit_vendor_price(item_key)
    for slot in info.inventory do
	    temp(slot)
        local item_info = temp-info.container_item(unpack(slot))
        if item_info and item_info.item_key == item_key then
            if info.auctionable(item_info.tooltip, nil, true) and not item_info.lootable then
                ClearCursor()
                PickupContainerItem(unpack(slot))
                ClickAuctionSellItemButton()
                local auction_sell_item = temp-info.auction_sell_item()
                ClearCursor()
                ClickAuctionSellItemButton()
                ClearCursor()
                if auction_sell_item then
                    return auction_sell_item.vendor_price / auction_sell_item.count
                end
            end
        end
    end
end

function update_item(item)
	CloseDropDownMenus()
    reset_buyout_state()
    user_price_override = false

    local settings = read_settings(item.key)

    item.unit_vendor_price = unit_vendor_price(item.key)

    -- CHANGE: Fallback for Project Epoch (3.3.5) if the scan returns 0 or fails
    if (not item.unit_vendor_price or item.unit_vendor_price == 0) and item.item_id then
        local vendorPrice = select(11, GetItemInfo(item.item_id))
        if vendorPrice and vendorPrice > 0 then
            item.unit_vendor_price = vendorPrice
        end
    end

    if not item.unit_vendor_price then
        settings.hidden = true
        write_settings(settings, item.key)
        refresh = true
        return
    end

    scan.abort(scan_id)

    selected_item = item

    UIDropDownMenu_Initialize(duration_dropdown, initialize_duration_dropdown)
    UIDropDownMenu_SetSelectedValue(duration_dropdown, settings.duration)

    hide_checkbox:SetChecked(settings.hidden)

    if selected_item.max_charges then
	    for i = selected_item.max_charges, 1, -1 do
			if selected_item.availability[i] > 0 then
				stack_size_slider:SetMinMaxValues(1, i)
				break
			end
	    end
    else
	    stack_size_slider:SetMinMaxValues(1, min(selected_item.max_stack, selected_item.aux_quantity))
    end
    -- Default to 1 item per stack, half of total quantity as stack count
    stack_size_slider:SetValue(1)
    quantity_update(false)
    local total = selected_item.max_charges and selected_item.availability[stack_size_slider:GetValue()] or selected_item.availability[0]
    stack_count_slider:SetValue(max(1, floor(total / 2)))

    unit_start_price_input:SetText(money.to_string(settings.start_price or 0, true, nil, nil, true)) -- Claude: guard nil from corrupt saved data
    unit_buyout_price_input:SetText(money.to_string(settings.buyout_price or 0, true, nil, nil, true)) -- Claude: guard nil from corrupt saved data

    if not bid_records[selected_item.key] then
        refresh_entries()
    end

    write_settings(settings, item.key)

    refresh = true
end

function update_inventory_records()
    local auctionable_map = temp-T
    for slot in info.inventory do
	    temp(slot)
	    local item_info = temp-info.container_item(unpack(slot))
        if item_info then
            local charge_class = item_info.charges or 0
            if info.auctionable(item_info.tooltip, nil, true) and not item_info.lootable then
                if not auctionable_map[item_info.item_key] then
                    local availability = T
                    for i = 0, 10 do
                        availability[i] = 0
                    end
                    availability[charge_class] = item_info.count
                    auctionable_map[item_info.item_key] = O(
	                    'item_id', item_info.item_id,
	                    'suffix_id', item_info.suffix_id,
	                    'key', item_info.item_key,
	                    'itemstring', item_info.itemstring,
	                    'name', item_info.name,
	                    'texture', item_info.texture,
	                    'quality', item_info.quality,
	                    'aux_quantity', item_info.charges or item_info.count,
	                    'max_stack', item_info.max_stack,
	                    'max_charges', item_info.max_charges,
	                    'availability', availability
                    )
                else
                    local auctionable = auctionable_map[item_info.item_key]
                    auctionable.availability[charge_class] = (auctionable.availability[charge_class] or 0) + item_info.count
                    auctionable.aux_quantity = auctionable.aux_quantity + (item_info.charges or item_info.count)
                end
            end
        end
    end
    release(inventory_records)
    inventory_records = values(auctionable_map)
    refresh = true
end

function refresh_entries()
	if selected_item then
        local item_key = selected_item.key
		bid_selection, buyout_selection = nil, nil
		user_price_override = false
        bid_records[item_key], buyout_records[item_key] = nil, nil
        local query = scan_util.item_query(selected_item.item_id)
        status_bar:update_status(0, 0)
        status_bar:set_text('Scanning auctions...')

		scan_id = scan.start{
            type = 'list',
            ignore_owner = true,
			queries = A(query),
			on_page_loaded = function(page, total_pages)
                status_bar:update_status(page / total_pages, 0) -- TODO
                status_bar:set_text(format('Scanning Page %d / %d', page, total_pages))
			end,
			on_auction = function(auction_record)
				if auction_record.item_key == item_key then
                    record_auction(
                        auction_record.item_key,
                        auction_record.aux_quantity,
                        auction_record.unit_blizzard_bid,
                        auction_record.unit_buyout_price,
                        auction_record.duration,
                        auction_record.owner
                    )
				end
			end,
			on_abort = function()
				bid_records[item_key], buyout_records[item_key] = nil, nil
                status_bar:update_status(1, 1)
                status_bar:set_text('Scan aborted')
			end,
			on_complete = function()
				bid_records[item_key] = bid_records[item_key] or T
				buyout_records[item_key] = buyout_records[item_key] or T
                refresh = true
                status_bar:update_status(1, 1)
                status_bar:set_text('Scan complete')
            end,
		}
	end
end

function record_auction(key, aux_quantity, unit_blizzard_bid, unit_buyout_price, duration, owner)
    bid_records[key] = bid_records[key] or T
    do
	    local entry
	    for _, record in pairs(bid_records[key]) do
	        if unit_blizzard_bid == record.unit_price and aux_quantity == record.stack_size and duration == record.duration and cache.is_player(owner) == record.own then
	            entry = record
	        end
	    end
	    if not entry then
	        entry = O('stack_size', aux_quantity, 'unit_price', unit_blizzard_bid, 'duration', duration, 'own', cache.is_player(owner), 'count', 0)
	        tinsert(bid_records[key], entry)
	    end
	    entry.count = entry.count + 1
    end
    buyout_records[key] = buyout_records[key] or T
    if unit_buyout_price == 0 then return end
    do
	    local entry
	    for _, record in pairs(buyout_records[key]) do
		    if unit_buyout_price == record.unit_price and aux_quantity == record.stack_size and duration == record.duration and cache.is_player(owner) == record.own then
			    entry = record
		    end
	    end
	    if not entry then
		    entry = O('stack_size', aux_quantity, 'unit_price', unit_buyout_price, 'duration', duration, 'own', cache.is_player(owner), 'count', 0)
		    tinsert(buyout_records[key], entry)
	    end
	    entry.count = entry.count + 1
    end
end

function on_update()
    if refresh then
        refresh = false
        update_item_configuration()
        update_inventory_listing()
        update_auction_listings()
        price_update()  -- after listings so auto-selections are visible immediately
    end
    validate_parameters()
end

function initialize_duration_dropdown()
    local function on_click()
        UIDropDownMenu_SetSelectedValue(duration_dropdown, this.value)
        local settings = read_settings()
        settings.duration = this.value
        write_settings(settings)
        refresh = true
    end
    UIDropDownMenu_AddButton{
	    text = '12 Hours',
	    value = DURATION_12,
	    func = on_click,
    }
    UIDropDownMenu_AddButton{
	    text = '24 Hours',
	    value = DURATION_24,
	    func = on_click,
    }
    UIDropDownMenu_AddButton{
	    text = '48 Hours',
	    value = DURATION_48,
	    func = on_click,
    }
end
