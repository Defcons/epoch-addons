local ADDON_NAME, ADDON = ...

-- couldn't use SetCursor() because of missing Atlas features => therefore usage of own cursor frame.
-- couldn't use dragIcon:StartMoving() properly => therefore usage of own update Ticker.

local dragIcon

local function SetDragIconWithCursor()
    dragIcon:ClearAllPoints()
    dragIcon:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", GetCursorPosition())
end


local function CreateDragIcon()
    dragIcon = CreateFrame("Frame")
    dragIcon:SetWidth(20)
    dragIcon:SetHeight(20)
    dragIcon:SetMovable(false)
    dragIcon:EnableMouse(false)
    dragIcon:SetFrameStrata("TOOLTIP")
    dragIcon.background = dragIcon:CreateTexture(nil, "BACKGROUND")
    dragIcon.background:SetAllPoints()

    dragIcon:Hide()

    dragIcon:SetScript('OnShow', function(self)
        SetDragIconWithCursor()
        self:SetScript('OnUpdate', SetDragIconWithCursor) --~every frame
    end)

    dragIcon:SetScript('OnHide', function(self)
        self:SetScript('OnUpdate', nil)
    end)
end
ADDON:RegisterLoadUICallback(CreateDragIcon)

function ADDON:StartDrag(index)
    local contact = self.settings.contacts[index]
    if (not contact) then
        return
    end

    dragIcon.background:SetTexture('')
    self:SetTexture(dragIcon.background, contact.icon)
    dragIcon:Show()
end

function ADDON:StopDrag()
    dragIcon:Hide()
    ADDON:SetSelectedContact(0)
end
