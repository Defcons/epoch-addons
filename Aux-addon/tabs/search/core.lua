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

do
    -- Claude: closure-local previous-subtab tracking (cannot use module globals — those route through mutators)
    local prev_sub
    local cur_sub
    function set_subtab(tab)
        CloseDropDownMenus()
        search_results_button:UnlockHighlight()
        saved_searches_button:UnlockHighlight()
        new_filter_button:UnlockHighlight()
        frame.results:Hide()
        frame.saved:Hide()
        frame.filter:Hide()

        if tab ~= cur_sub then prev_sub = cur_sub end -- Claude: remember previous for Back
        cur_sub = tab

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
    -- Claude: Back button support -- returns to previous search subtab if there is one
    function M.go_back_subtab()
        if prev_sub and prev_sub ~= cur_sub then
            set_subtab(prev_sub)
            return true
        end
        return false
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

