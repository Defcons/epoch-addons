-- EpochFixes.lua

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

local savedAbandonIndex = nil

local fixFrame = CreateFrame("Frame")
fixFrame:RegisterEvent("PLAYER_LOGIN")
fixFrame:SetScript("OnEvent", function()

    -- Step 1: Record the selection index at the moment the player clicks Abandon.
    -- HookScript fires after the original OnClick (which shows the popup), so the
    -- quest log selection is still guaranteed to be the player's intended quest.
    if QuestLogAbandonButton then
        QuestLogAbandonButton:HookScript("OnClick", function()
            savedAbandonIndex = GetQuestLogSelection()
        end)
    end

    -- Step 2: Wrap the popup's OnAccept to restore the correct quest selection
    -- just before AbandonQuest() is called. This is the authoritative fix point:
    -- by the time OnAccept fires, any other addon's QUEST_LOG_UPDATE handling
    -- has already run and may have shifted the selection away from the intended
    -- quest. We force it back here, guaranteeing the right quest is abandoned.
    local popup = StaticPopupDialogs and StaticPopupDialogs["ABANDON_QUEST"]
    if popup and popup.OnAccept then
        local originalAccept = popup.OnAccept
        popup.OnAccept = function(self, ...)
            if savedAbandonIndex then
                -- Re-select the quest the player originally clicked Abandon on.
                -- This corrects any selection drift that happened while the popup
                -- was open (e.g. Leatrix's SelectQuestLogEntry loop).
                SelectQuestLogEntry(savedAbandonIndex)
            end
            savedAbandonIndex = nil
            originalAccept(self, ...)
        end
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
