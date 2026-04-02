module 'aux.tabs.search'

include 'T'
include 'aux'

local info = require 'aux.util.info'

TAB 'Search'

StaticPopupDialogs.AUX_SEARCH_TABLE_FULL = {
    text = 'Table full!\nFurther results from this search will still be processed but no longer displayed in the table.',
    button1 = 'Ok',
    showAlert = 1,
    timeout = 0,
    hideOnEscape = 1,
}

RESULTS = 1
SAVED = 2
FILTER = 3

function LOAD()
	subtab = SAVED
end

function OPEN()
    frame:Show()
    update_search_listings()
    update_filter_display()
end

function CLOSE()
    current_search.table:SetSelectedRecord()
    frame:Hide()
end

function CLICK_LINK(item_info)
	filter = strlower(item_info.name) .. '/exact'
	execute(nil, false)
end

function USE_ITEM(_, _, _, _, name)
	filter = strlower(name) .. '/exact'
	execute(nil, false)
end

function set_subtab(tab)
	CloseDropDownMenus()
    search_results_button:UnlockHighlight()
    saved_searches_button:UnlockHighlight()
    new_filter_button:UnlockHighlight()
    frame.results:Hide()
    frame.saved:Hide()
    frame.filter:Hide()

    if tab == RESULTS then
        frame.results:Show()
        search_results_button:LockHighlight()
    elseif tab == SAVED then
        frame.saved:Show()
        saved_searches_button:LockHighlight()
    elseif tab == FILTER then
        frame.filter:Show()
        new_filter_button:LockHighlight()
    end
end

function M.set_filter(filter_string)
	search_box:SetFocus()
    search_box:SetText(filter_string)
end

function add_filter(filter_string)
    local old_filter_string = search_box:GetText()
    old_filter_string = trim(old_filter_string)

    if old_filter_string ~= '' then
        old_filter_string = old_filter_string .. ';'
    end

    filter = old_filter_string .. filter_string
end

function blizzard_page_index(str)
    if tonumber(str) then
        return max(0, tonumber(str) - 1)
    end
end

-- Claude: Full AH scan — iterates all pages to populate price history DB
function M.scan_all()
    if not AuxFrame:IsShown() then
        print('aux: Open the Auction House first.')
        return
    end

    local scan = require 'aux.core.scan'

    discard_continuation()
    new_search('', nil, nil, false)

    local search = current_search
    search.active = true
    update_start_stop()
    clear_control_focus()
    subtab = RESULTS

    local current_page = 0
    local total_count = 0

    search_scan_id = scan.start{
        type = 'list',
        queries = A(O('blizzard_query', O())), -- Claude: empty query = all items
        ignore_owner = true,
        on_scan_start = function()
            search.status_bar:update_status(0, 0)
            search.status_bar:set_text('Full AH scan starting...')
        end,
        on_start_query = function()
        end,
        on_page_loaded = function(_, total_scan_pages) -- Claude: track page progress
            current_page = current_page + 1
            total_scan_pages = max(total_scan_pages, 1)
            current_page = min(current_page, total_scan_pages)
            search.status_bar:update_status(0, current_page / total_scan_pages)
            search.status_bar:set_text(format('Scanning page %d / %d', current_page, total_scan_pages))
        end,
        on_page_scanned = function()
        end,
        on_auction = function() -- Claude: just count, history updated by scan engine
            total_count = total_count + 1
        end,
        on_complete = function()
            search.status_bar:update_status(1, 1)
            search.status_bar:set_text(format('Scan complete - %d auctions', total_count))
            print(format('aux: Full AH scan complete - %d auctions processed.', total_count))
            search.active = false
            update_start_stop()
        end,
        on_abort = function()
            search.status_bar:update_status(1, 1)
            search.status_bar:set_text('Full scan paused')
            search.active = false
            update_start_stop()
        end,
    }
end

