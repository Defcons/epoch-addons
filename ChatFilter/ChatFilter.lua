-- List of words to filter (add new if needed)
local blockedWords = {
    "appearance",
}

-- Filtering Function
local function ChatFilter(self, event, message, author, ...)
    local lowerMessage = string.lower(message)
    for _, word in ipairs(blockedWords) do
        -- "%f[%a]" = frontier before a letter, "%f[%A]" = frontier after a letter
        local pattern = "%f[%a]" .. string.lower(word) .. "%f[%A]"
        if string.find(lowerMessage, pattern) then
            return true -- Block the message
        end
    end
    return false, message, author, ...
end

-- Apply the filters to different channels
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)
