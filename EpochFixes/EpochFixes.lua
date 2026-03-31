-- EpochFixes.lua

-- ============================================================
-- Claude: Quest debug system (/epochdebug on|off|status)
-- Tracks quest log selection changes, SelectQuestLogEntry calls,
-- QUEST_LOG_UPDATE firings, and the full abandon flow to diagnose
-- wrong-quest-abandoned and related quest log bugs.
-- ============================================================

local EFDebug = {
    enabled = false,
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

-- Watch QUEST_LOG_UPDATE events for debug logging.
-- The SelectQuestLogEntry guard is now installed at file scope (Solution A+C above).
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

-- Fix 2: Quest log selection drift and wrong-quest-abandoned bugs.
--
-- ROOT CAUSE:
--   Leatrix Plus's QUEST_LOG_UPDATE handler iterates every quest log entry
--   calling SelectQuestLogEntry(i) to check completion status. This fires on
--   every QUEST_LOG_UPDATE event — including while the quest log is open and
--   while the "Abandon Quest" confirmation popup is visible. This causes:
--
--   a) "Wrong quest opened": selection shifts mid-frame while browsing
--   b) "Wrong quest abandoned": SetAbandonQuest() captures the correct quest
--      at button-click time, but if a QUEST_LOG_UPDATE fires between click
--      and confirm AND something re-calls SetAbandonQuest(), the internal
--      state drifts. More commonly, the visual selection drifts so the user
--      thinks they're abandoning quest A but the UI shows quest B.
--
-- THREE-LAYER FIX:
--   A) Guard SelectQuestLogEntry: block addon-driven calls (from Leatrix's
--      QUEST_LOG_UPDATE scan) when QuestLogFrame is visible. This prevents
--      "opening wrong quest" entirely.
--   B) On abandon confirm: re-select the correct quest by title, then re-call
--      SetAbandonQuest() so the internal C++ state matches before AbandonQuest().
--   C) While ABANDON_QUEST popup is open, block ALL SelectQuestLogEntry calls
--      from other addons to prevent any drift during confirmation.

-- Claude: save both title and index for robust abandon targeting
local savedAbandonTitle = nil
local savedAbandonIndex = nil
local abandonPopupOpen = false -- Claude: Solution C flag

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
    abandonPopupOpen = false -- Claude: clear popup flag
end

-- Claude: Solution A + C — Guard SelectQuestLogEntry against addon-driven calls
-- This replaces the debug-only hook above with a functional guard.
-- We must install this early (PLAYER_LOGIN) so it wraps before other addons hook.
local _real_SelectQuestLogEntry = SelectQuestLogEntry -- Claude: save the real function
local efBypassGuard = false -- Claude: internal flag to let our own calls through

SelectQuestLogEntry = function(index, ...) -- Claude: Solution A+C wrapper
    -- Always allow our own calls (when we set efBypassGuard = true)
    if efBypassGuard then
        return _real_SelectQuestLogEntry(index, ...)
    end

    -- Solution C: Block ALL external SelectQuestLogEntry calls while abandon popup is open
    if abandonPopupOpen then
        DBG("BLOCKED SelectQuestLogEntry(" .. tostring(index) .. ") — abandon popup open")
        return
    end

    -- Solution A: Block addon-driven calls when QuestLogFrame is visible.
    -- Known offenders that iterate SelectQuestLogEntry in a loop:
    --   - Leatrix_Plus: QUEST_LOG_UPDATE handler scans all entries for completion
    --   - pfQuest-epoch/pfQuest-nameplates.lua: ScanQuestObjectives() on multiple events
    -- We block calls originating from addon event handlers while the quest log is open.
    -- Blizzard's own QuestLog_SetSelection (from user clicks) is allowed through.
    if QuestLogFrame and QuestLogFrame:IsVisible() then
        if debugstack then
            local stack = debugstack(2, 8, 0) or ""
            -- Claude: Block if call comes from known addon scan patterns:
            -- 1. Any QUEST_LOG_UPDATE event handler (Leatrix, pfQuest, etc.)
            -- 2. pfQuest-nameplates ScanQuestObjectives (fires on ZONE_CHANGED too)
            -- 3. Any Leatrix_Plus event handler
            if stack:find("QUEST_LOG_UPDATE")
                or stack:find("pfQuest%-nameplates")
                or stack:find("pfQuest%-epoch")
                or stack:find("Leatrix_Plus") then
                DBG("BLOCKED SelectQuestLogEntry(" .. tostring(index) .. ") — addon scan while quest log open")
                return
            end
        end
    end

    -- Debug logging (replaces the old debug-only hook)
    if EFDebug.enabled then
        local before = GetQuestLogSelection()
        local tb = ""
        if debugstack then
            local raw = debugstack(2, 4, 0) or ""
            raw = raw:gsub("\n", " | "):gsub("%s+", " ")
            tb = raw
        end
        DBG(string.format(
            "SelectQuestLogEntry(%s)  before=%s  caller=%s",
            tostring(index), QuestDesc(before), tb
        ))
    end

    return _real_SelectQuestLogEntry(index, ...)
end

local fixFrame = CreateFrame("Frame")
fixFrame:RegisterEvent("PLAYER_LOGIN")
fixFrame:SetScript("OnEvent", function()

    -- Step 1: Capture quest title + index when the player clicks Abandon.
    -- Also set abandonPopupOpen flag (Solution C) to block external selection changes.
    if QuestLogAbandonButton then
        QuestLogAbandonButton:HookScript("OnClick", function()
            savedAbandonIndex = GetQuestLogSelection()
            savedAbandonTitle = savedAbandonIndex and GetQuestLogTitle(savedAbandonIndex) or nil
            abandonPopupOpen = true -- Claude: Solution C — block external calls
            DBG("AbandonButton clicked  idx=" .. tostring(savedAbandonIndex)
                .. "  title=" .. tostring(savedAbandonTitle))
        end)
    end

    local popup = StaticPopupDialogs and StaticPopupDialogs["ABANDON_QUEST"]
    if not popup then return end

    -- Step 2 (Solution B): On confirm — find the quest by title, force-select it,
    -- then re-call SetAbandonQuest() so the C++ internal state matches.
    -- AbandonQuest() reads from SetAbandonQuest()'s internal state, NOT from
    -- GetQuestLogSelection(), so we MUST call SetAbandonQuest() again.
    if popup.OnAccept then
        local originalAccept = popup.OnAccept
        popup.OnAccept = function(self, ...)
            local currentSel = GetQuestLogSelection()
            local targetIndex = nil

            if savedAbandonTitle then
                targetIndex = FindQuestIndexByTitle(savedAbandonTitle)
            end
            if not targetIndex then
                targetIndex = savedAbandonIndex
            end

            DBG("ABANDON_QUEST OnAccept  title=" .. tostring(savedAbandonTitle)
                .. "  savedIdx=" .. tostring(savedAbandonIndex)
                .. "  resolvedIdx=" .. tostring(targetIndex)
                .. "  currentSel=" .. tostring(currentSel)
                .. "  drift=" .. tostring(targetIndex ~= currentSel))

            if targetIndex then
                -- Claude: Use bypass flag so our call goes through the guard
                efBypassGuard = true
                _real_SelectQuestLogEntry(targetIndex) -- Claude: select the correct quest
                efBypassGuard = false
                -- Claude: Solution B — re-call SetAbandonQuest() to update C++ internal state
                -- This is the critical fix: AbandonQuest() uses SetAbandonQuest()'s state,
                -- not GetQuestLogSelection(). Without this, the wrong quest gets abandoned.
                SetAbandonQuest()
                DBG("Re-called SetAbandonQuest() after selecting index " .. tostring(targetIndex)
                    .. "  confirmTitle=" .. tostring(GetAbandonQuestName()))
            end

            ClearAbandonState()
            originalAccept(self, ...)
        end
    end

    -- Step 3: Clean up saved state if the player cancels or closes the popup.
    local originalCancel = popup.OnCancel
    popup.OnCancel = function(self, ...)
        DBG("ABANDON_QUEST OnCancel — clearing saved state")
        ClearAbandonState()
        if originalCancel then originalCancel(self, ...) end
    end

    -- Claude: Also handle popup hiding without explicit cancel (e.g. escape key, timeout)
    local originalHide = popup.OnHide
    popup.OnHide = function(self, ...)
        DBG("ABANDON_QUEST OnHide — clearing saved state")
        ClearAbandonState()
        if originalHide then originalHide(self, ...) end
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
