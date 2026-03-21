module 'aux.tabs.auctions'

include 'T'
include 'aux'

local scan_util = require 'aux.util.scan'
local scan = require 'aux.core.scan'

TAB 'Auctions'

auction_records = T

function LOAD()
	event_listener('AUCTION_OWNED_LIST_UPDATE', scan_auctions)
end

function OPEN()
    frame:Show()
    GetOwnerAuctionItems()
end

function CLOSE()
    frame:Hide()
end

function update_listing()
    listing:SetDatabase(auction_records)
end

function M.scan_auctions()

    -- Remember what was selected before the wipe so we can restore it after rescanning.
    -- AUCTION_OWNED_LIST_UPDATE fires on every cancel, so scan_auctions runs automatically
    -- and destroys the selection through wipe(). We recover it here.
    local prev_item_key = listing.selected and listing.selected.item_key
    local prev_name    = listing.selected and listing.selected.name

    status_bar:update_status(0, 0)
    status_bar:set_text('Scanning auctions...')

    wipe(auction_records)
    update_listing()
    scan.start{
        type = 'owner',
        on_auction = function(auction_record)
            tinsert(auction_records, auction_record)
        end,
        on_complete = function()
            status_bar:update_status(1, 1)
            status_bar:set_text('Scan complete')
            update_listing()

            if prev_item_key then
                local restore = nil
                -- 1. Same item still has auctions → stay on it
                for _, r in pairs(auction_records) do
                    if r.item_key == prev_item_key then
                        restore = r
                        break
                    end
                end
                -- 2. Item is gone (last auction cancelled) → pick next alphabetically
                if not restore and prev_name then
                    for _, r in pairs(auction_records) do
                        if r.name >= prev_name then
                            if not restore or r.name < restore.name then
                                restore = r
                            end
                        end
                    end
                end
                -- 3. Nothing after it → fall back to first remaining auction
                if not restore then
                    restore = auction_records[1]
                end
                if restore then
                    listing:SetSelectedRecord(restore)
                end
            end
        end,
        on_abort = function()
            status_bar:update_status(1, 1)
            status_bar:set_text('Scan aborted')
        end,
    }
end

do
    local scan_id = 0
    local IDLE, SEARCHING, FOUND = T, T, T
    local state = IDLE
    local found_index

    function find_auction(record)
        if not listing:ContainsRecord(record) then return end

        scan.abort(scan_id)
        state = SEARCHING
        scan_id = scan_util.find(
            record,
            status_bar,
            function() state = IDLE end,
            function() state = IDLE; listing:RemoveAuctionRecord(record) end,
            function(index)
                state = FOUND
                found_index = index

                cancel_button:SetScript('OnClick', function()
                    if scan_util.test(record, index) and listing:ContainsRecord(record) then
                        cancel_auction(index, function() listing:RemoveAuctionRecord(record) end)
                    end
                end)
                cancel_button:Enable()
            end
        )
    end

    function on_update()
        if state == IDLE or state == SEARCHING then
            cancel_button:Disable()
        end

        if state == SEARCHING then return end

        local selection = listing:GetSelection()
        if not selection then
            state = IDLE
        elseif selection and state == IDLE then
            find_auction(selection.record)
        elseif state == FOUND and not scan_util.test(selection.record, found_index) then
            cancel_button:Disable()
            if not cancel_in_progress then state = IDLE end
        end
    end
end