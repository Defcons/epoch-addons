-- EpochFixes.lua

-- ============================================================
-- Claude: Quest debug system (/epochdebug on|off|status)
-- Tracks quest log selection changes, SelectQuestLogEntry calls,
-- QUEST_LOG_UPDATE firings, and the full abandon flow to diagnose
-- wrong-quest-abandoned and related quest log bugs.
-- ============================================================

local EFDebug = {
    enabled = false,
    selectionHooked = false,
}

-- Print a timestamped debug line to the chat frame.
local function DBG(msg)
    if not EFDebug.enabled then return end
    local t = GetTime()
    DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cffff9900[EFDebug %.3f]|r %s", t, tostring(msg)),
        1, 0.6, 0
    )
end

-- Return a short description of the currently selected quest log entry.
local function QuestDesc(index)
    index = index or GetQuestLogSelection()
    if not index or index == 0 then return "none(0)" end
    local title, _, _, _, isHeader = GetQuestLogTitle(index)
    if not title then return "nil@" .. index end
    if isHeader then return "[HDR:" .. title .. "]@" .. index end
    return '"' .. title .. '"@' .. index
end

-- Hook SelectQuestLogEntry so we can see every caller that shifts the
-- quest selection. Works by replacing the global with a wrapper that
-- logs caller info (via debug.traceback when available) then calls through.
local function InstallSelectionHook()
    if EFDebug.selectionHooked then return end
    EFDebug.selectionHooked = true

    local _orig_SelectQuestLogEntry = SelectQuestLogEntry
    SelectQuestLogEntry = function(index, ...)
        if EFDebug.enabled then
            local before = GetQuestLogSelection()
            -- Grab 2-level traceback: skip this wrapper (level 1), show the caller (level 2+)
            -- Claude: use WoW's debugstack() instead of debug.traceback (unavailable in 3.3.5 sandbox)
            local tb = ""
            if debugstack then
                -- debugstack(level, topCount, tailCount): skip 1 = this wrapper, show 4 frames
                local raw = debugstack(2, 4, 0) or ""
                -- Collapse to one line for readability
                raw = raw:gsub("\n", " | "):gsub("%s+", " ")
                tb = raw
            end
            DBG(string.format(
                "SelectQuestLogEntry(%s)  before=%s  caller=%s",
                tostring(index), QuestDesc(before), tb
            ))
        end
        return _orig_SelectQuestLogEntry(index, ...)
    end
end

-- Watch QUEST_LOG_UPDATE events so we know when and how often the log
-- refreshes (each refresh can trigger addons to call SelectQuestLogEntry).
-- Claude: separate frames so PLAYER_LOGIN and QUEST_LOG_UPDATE don't clobber each other
local debugLoginFrame = CreateFrame("Frame")
debugLoginFrame:RegisterEvent("PLAYER_LOGIN")
debugLoginFrame:SetScript("OnEvent", function()
    InstallSelectionHook()
end)

local debugQuestFrame = CreateFrame("Frame")
debugQuestFrame:RegisterEvent("QUEST_LOG_UPDATE")
debugQuestFrame:SetScript("OnEvent", function(self, event)
    DBG("QUEST_LOG_UPDATE  selection=" .. QuestDesc())
end)

-- Slash command: /epochdebug [on|off|status]
SLASH_EPOCHDEBUG1 = "/epochdebug"
SlashCmdList["EPOCHDEBUG"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "on" then
        EFDebug.enabled = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EpochFixes]|r Quest debug ON. Use /epochdebug off to stop.", 0, 1, 0)
    elseif msg == "off" then
        EFDebug.enabled = false
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EpochFixes]|r Quest debug OFF.", 0, 1, 0)
    else
        local state = EFDebug.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EpochFixes]|r Quest debug is " .. state .. ".  Usage: /epochdebug on|off", 0, 1, 0)
    end
end

-- ============================================================

-- Fix 1: nil concatenation error on SpellBookFrameTabButton2 OnEnter
-- when TOGGLEPETBOOK has no keybind assigned.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if SpellBookFrameTabButton2 then
        local original = SpellBookFrameTabButton2:GetScript("OnEnter")
        SpellBookFrameTabButton2:SetScript("OnEnter", function()
            local ok, err = pcall(original)
        end)
    end
end)

-- Fix 2: Quest log abandon bugs.
--
-- "Wrong quest abandoned":
--   Blizzard's AbandonQuest() uses the currently-selected quest log entry
--   (GetQuestLogSelection()) to determine which quest to abandon. The
--   confirmation popup (StaticPopupDialogs["ABANDON_QUEST"]) is shown when
--   the player clicks the Abandon button, but AbandonQuest() is only called
--   later when the player clicks OK. If another addon fires QUEST_LOG_UPDATE
--   between those two moments and calls SelectQuestLogEntry() (e.g. Leatrix
--   Plus's auto-quest scan), the selection can shift to a different quest.
--   The result: the wrong quest gets abandoned.
--
-- "Abandon button unclickable":
--   pfQuest-wotlk raw-replaced QuestLog_Update() (the function that shows/
--   hides QuestLogAbandonButton) with a non-secure wrapper. On 3.3.5, this
--   can cause subtle taint propagation that prevents the abandon button from
--   responding. Fixed in pfQuest-wotlk/quest.lua (changed to hooksecurefunc).
--
-- Fix: Capture the quest log index when the player first clicks the Abandon
-- button (before the popup appears). Then wrap the popup's OnAccept so it
-- re-selects that exact index before AbandonQuest() is called, regardless of
-- what other addons did to the selection while the popup was open.

-- Claude: save both title and index for robust abandon targeting
local savedAbandonTitle = nil
local savedAbandonIndex = nil

-- Claude: find a quest in the log by title; returns its index or nil
local function FindQuestIndexByTitle(title)
    for i = 1, GetNumQuestLogEntries() do
        local t, _, _, _, isHeader = GetQuestLogTitle(i)
        if not isHeader and t == title then
            return i
        end
    end
    return nil
end

local function ClearAbandonState()
    savedAbandonTitle = nil
    savedAbandonIndex = nil
end

local fixFrame = CreateFrame("Frame")
fixFrame:RegisterEvent("PLAYER_LOGIN")
fixFrame:SetScript("OnEvent", function()

    -- Step 1: Capture quest title + index when the player clicks Abandon.
    -- Title is the robust identifier: immune to index drift if quests are
    -- added/removed while the confirmation popup is open.
    -- Index is kept as a fallback only.
    if QuestLogAbandonButton then
        QuestLogAbandonButton:HookScript("OnClick", function()
            savedAbandonIndex = GetQuestLogSelection()
            savedAbandonTitle = savedAbandonIndex and GetQuestLogTitle(savedAbandonIndex) or nil
            -- Claude: debug
            DBG("AbandonButton clicked  idx=" .. tostring(savedAbandonIndex)
                .. "  title=" .. tostring(savedAbandonTitle))
        end)
    end

    local popup = StaticPopupDialogs and StaticPopupDialogs["ABANDON_QUEST"]
    if not popup then return end

    -- Step 2: On confirm — find the quest by title (robust) or fall back to
    -- saved index, then force-select it immediately before AbandonQuest() runs.
    -- This corrects any selection drift from addons (e.g. Leatrix's
    -- QUEST_LOG_UPDATE scanner) that ran while the popup was open.
    if popup.OnAccept then
        local originalAccept = popup.OnAccept
        popup.OnAccept = function(self, ...)
            local currentSel = GetQuestLogSelection()
            local targetIndex = nil

            if savedAbandonTitle then
                -- Primary: find by title — works even if indices shifted
                targetIndex = FindQuestIndexByTitle(savedAbandonTitle)
            end
            if not targetIndex then
                -- Fallback: use the saved numeric index
                targetIndex = savedAbandonIndex
            end

            -- Claude: debug
            DBG("ABANDON_QUEST OnAccept  title=" .. tostring(savedAbandonTitle)
                .. "  savedIdx=" .. tostring(savedAbandonIndex)
                .. "  resolvedIdx=" .. tostring(targetIndex)
                .. "  currentSel=" .. tostring(currentSel)
                .. "  drift=" .. tostring(targetIndex ~= currentSel))

            if targetIndex then
                SelectQuestLogEntry(targetIndex)
            end
            ClearAbandonState()
            originalAccept(self, ...)
        end
    end

    -- Step 3: Clean up saved state if the player cancels or closes the popup.
    -- Without this, a stale savedAbandonTitle from a cancelled attempt could
    -- interfere with the next abandon.
    local originalCancel = popup.OnCancel
    popup.OnCancel = function(self, ...)
        -- Claude: debug
        DBG("ABANDON_QUEST OnCancel — clearing saved state")
        ClearAbandonState()
        if originalCancel then originalCancel(self, ...) end
    end

end)

-- Fix 3: Quest reward item tooltips broken (hovering shows nothing).
--
-- In QuestInfoFrame, each reward item button's OnEnter calls:
--   GameTooltip:SetQuestItem(type, index)
-- This fails silently if GameTooltip's owner has been stolen by another addon.
-- Two known causes on this setup:
--   a) pfQuest-wotlk's database scanner calls ItemRefTooltip:SetHyperlink() on
--      every OnUpdate tick to probe item data. This can corrupt GameTooltip's
--      internal owner/anchor state on 3.3.5.
--   b) Leatrix's TipModEnable feature globally re-anchors GameTooltip, leaving
--      it pointing at a different owner than the reward button.
--
-- Fix: Hook each QuestInfoItem button's OnEnter to explicitly re-claim
-- GameTooltip ownership before SetQuestItem is called.
-- Note: self.type and self.index are set by Blizzard's QuestInfo_ShowRewards
-- each time the quest frame populates, so they are always current at call-time.

local rewardFrame = CreateFrame("Frame")
rewardFrame:RegisterEvent("PLAYER_LOGIN")
rewardFrame:SetScript("OnEvent", function()

    local function FixRewardButton(button)
        if not button then return end

        button:HookScript("OnEnter", function(self)
            local itemType  = self.type
            local itemIndex = self.index
            if not itemType or not itemIndex then return end

            -- Force GameTooltip ownership to this button unconditionally,
            -- undoing any anchor theft by pfQuest or Leatrix.
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetQuestItem(itemType, itemIndex)
            GameTooltip:Show()
        end)

        button:HookScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end

    -- WotLK 3.3.5 uses QuestInfoItem1..6 for both choice and reward buttons.
    -- The game reuses these buttons per quest and sets .type/.index on each.
    for i = 1, 6 do
        FixRewardButton(_G["QuestInfoItem" .. i])
    end

end)

-- Fix 4: Inspect frame item tooltips break after ~10–15 seconds.
--
-- When you inspect another player, NotifyInspect() fetches their gear from
-- the server. INSPECT_READY fires and GetInventoryItemLink("target", slot)
-- returns valid links. After ~10–15 seconds the client-side inspect cache
-- expires, and all subsequent GameTooltip:SetInventoryItem("target", slot)
-- calls on the inspect frame buttons silently return nothing — no tooltip.
--
-- Fix: On INSPECT_READY, snapshot all item links for the inspected unit.
-- Hook each inspect frame slot button's OnEnter to fall back to
-- GameTooltip:SetHyperlink(cachedLink) when the normal SetInventoryItem
-- would fail (detectable because GetInventoryItemLink returns nil post-expiry).

local INSPECT_SLOTS = {
    [1]  = "InspectHeadSlot",
    [2]  = "InspectNeckSlot",
    [3]  = "InspectShoulderSlot",
    [4]  = "InspectBackSlot",
    [5]  = "InspectChestSlot",
    [6]  = "InspectShirtSlot",
    [7]  = "InspectTabardSlot",
    [8]  = "InspectWristSlot",
    [9]  = "InspectHandsSlot",
    [10] = "InspectWaistSlot",
    [11] = "InspectLegsSlot",
    [12] = "InspectFeetSlot",
    [13] = "InspectFinger0Slot",
    [14] = "InspectFinger1Slot",
    [15] = "InspectTrinket0Slot",
    [16] = "InspectTrinket1Slot",
    [17] = "InspectMainHandSlot",
    [18] = "InspectSecondaryHandSlot",
    [19] = "InspectRangedSlot",
}

local inspectLinkCache = {}  -- slotID → item link string

local inspectCacheFrame = CreateFrame("Frame")
inspectCacheFrame:RegisterEvent("INSPECT_READY")
inspectCacheFrame:SetScript("OnEvent", function()
    -- Cache all equipped item links for the inspected unit right now,
    -- while the server data is still hot.
    wipe(inspectLinkCache)
    for slotID = 1, 19 do
        local link = GetInventoryItemLink("target", slotID)
        if link then
            inspectLinkCache[slotID] = link
        end
    end
end)

local inspectHookFrame = CreateFrame("Frame")
inspectHookFrame:RegisterEvent("PLAYER_LOGIN")
inspectHookFrame:SetScript("OnEvent", function()
    for slotID, btnName in pairs(INSPECT_SLOTS) do
        local btn = _G[btnName]
        if btn then
            btn:HookScript("OnEnter", function(self)
                -- If GetInventoryItemLink still works (cache is live), do nothing —
                -- the original OnEnter already ran SetInventoryItem successfully.
                if GetInventoryItemLink("target", slotID) then return end

                -- Cache has expired. Fall back to the link we snapshotted at
                -- INSPECT_READY time, if we have one.
                local link = inspectLinkCache[slotID]
                if link then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(link)
                    GameTooltip:Show()
                end
            end)

            btn:HookScript("OnLeave", function(self)
                -- Only hide if we were the ones who showed a fallback tooltip.
                -- Check: if live data is gone and we have a cached link,
                -- we must have taken ownership.
                if not GetInventoryItemLink("target", slotID) and inspectLinkCache[slotID] then
                    GameTooltip:Hide()
                end
            end)
        end
    end
end)
