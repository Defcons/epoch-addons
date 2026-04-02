module 'aux.tabs.auctions'

local gui = require 'aux.gui'
local auction_listing = require 'aux.gui.auction_listing'

frame = CreateFrame('Frame', nil, AuxFrame)
frame:SetAllPoints()
frame:SetScript('OnUpdate', on_update)
frame:EnableKeyboard(true) -- Claude: letter-key navigation
frame:Hide()

do -- Claude: type a letter to jump to matching item; repeat to cycle
    local search_text = ''
    local last_key_time = 0
    local RESET_DELAY = 1

    frame:SetScript('OnKeyDown', function()
        if GetCurrentKeyBoardFocus() then return end
        local key = arg1
        if not key or strlen(key) ~= 1 then return end
        local letter = strlower(key)
        if letter < 'a' or letter > 'z' then return end

        local now = GetTime()
        if now - last_key_time > RESET_DELAY then
            search_text = ''
        end
        last_key_time = now

        local cycleNext = false
        if search_text == letter then
            cycleNext = true -- Claude: same letter again, advance to next match
        else
            search_text = search_text .. letter
        end

        listing:JumpToLetter(search_text, cycleNext)
    end)
end

frame.listing = gui.panel(frame)
frame.listing:SetPoint('TOP', frame, 'TOP', 0, -8)
frame.listing:SetPoint('BOTTOMLEFT', AuxFrame.content, 'BOTTOMLEFT', 0, 0)
frame.listing:SetPoint('BOTTOMRIGHT', AuxFrame.content, 'BOTTOMRIGHT', 0, 0)

listing = auction_listing.new(frame.listing, 20, auction_listing.auctions_columns)
listing:SetSort(1, 2, 3, 4, 5, 6, 7, 8)
listing:Reset()
listing:SetHandler('OnClick', function(row, button)
    if IsAltKeyDown() and listing:GetSelection().record == row.record then
        cancel_button:Click()
    end
end)
listing:SetHandler('OnSelectionChanged', function(rt, datum)
    if not datum then return end
    find_auction(datum.record)
end)

do
	status_bar = gui.status_bar(frame)
    status_bar:SetWidth(265)
    status_bar:SetHeight(25)
    status_bar:SetPoint('TOPLEFT', AuxFrame.content, 'BOTTOMLEFT', 0, -6)
    status_bar:update_status(1, 1)
    status_bar:set_text('')
end
do
    local btn = gui.button(frame)
    btn:SetPoint('TOPLEFT', status_bar, 'TOPRIGHT', 5, 0)
    btn:SetText('Cancel')
    btn:Disable()
    cancel_button = btn
end
do
    local btn = gui.button(frame)
    btn:SetPoint('TOPLEFT', cancel_button, 'TOPRIGHT', 5, 0)
    btn:SetText('Refresh')
    btn:SetScript('OnClick', GetOwnerAuctionItems)
end