local ADDON_NAME, ADDON = ...

local CONTACT_BUTTON_SIZE = 36
local CONTACT_BUTTON_MARGIN = 12
local CONTAINER_PADDING = 4  -- padding around button grid so backdrop border is visible

local function UpdateBackdropColor()
    if not ADDON.contactContainer or not ADDON.settings then return end
    if ADDON.settings.locked then
        -- Locked: subtle grey border
        ADDON.contactContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    else
        -- Unlocked: gold border so it's obvious the frame can be moved
        ADDON.contactContainer:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
    end
end

local function CreateContainer()
    local contactContainer = CreateFrame("Frame", "FavoriteContactsContainer", UIParent)
    contactContainer:SetToplevel(true)
    contactContainer:SetFrameStrata("HIGH")
    contactContainer:Hide()
    contactContainer:SetMovable(true)
    contactContainer:EnableMouse(true)
    contactContainer:RegisterForDrag("LeftButton")

    -- Dark background using tooltip texture (available in all 3.3.5 clients)
    contactContainer:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    contactContainer:SetBackdropColor(0, 0, 0, 0.85)
    -- Border colour set in UpdateBackdropColor() once settings are available

    -- Left-drag moves the frame when unlocked
    contactContainer:SetScript("OnDragStart", function(self)
        if ADDON.settings and not ADDON.settings.locked then
            self:StartMoving()
        end
    end)
    contactContainer:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ADDON.settings and not ADDON.settings.locked then
            -- Save absolute position so it persists across sessions
            ADDON.settings.posX = self:GetLeft()
            ADDON.settings.posY = self:GetTop()
        end
    end)

    -- Right-click on background (gaps between buttons) to toggle lock
    contactContainer:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and ADDON.settings then
            ADDON.settings.locked = not ADDON.settings.locked
            ADDON:UpdateContactContainer()
        end
    end)

    ADDON.contactContainer = contactContainer
end

function ADDON:UpdateContactContainer()
    local scale    = self.settings.scale
    local position = self.settings.position
    local locked   = self.settings.locked

    local width  = ((CONTACT_BUTTON_SIZE + CONTACT_BUTTON_MARGIN) * self.settings.columnCount) - CONTACT_BUTTON_MARGIN
    local height = ((CONTACT_BUTTON_SIZE + CONTACT_BUTTON_MARGIN) * self.settings.rowCount)    - CONTACT_BUTTON_MARGIN

    -- Container is padded so the backdrop border shows around the button grid
    self.contactContainer:SetWidth(width   + CONTAINER_PADDING * 2)
    self.contactContainer:SetHeight(height + CONTAINER_PADDING * 2)

    if scale == "AUTO" then
        if position == "TOP" or position == "BOTTOM" then
            scale = MailFrame:GetScale() * MailFrame:GetWidth() / width
        else
            scale = MailFrame:GetScale() * (MailFrame:GetHeight() - 4) / height
        end
    end
    self.contactContainer:SetScale(scale)

    UpdateBackdropColor()

    if not locked then
        -- Free-floating: clear panel layout attrs so MailFrame positions normally
        MailFrame:SetAttribute("UIPanelLayout-xoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-yoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraWidth", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraHeight", 0)

        self.contactContainer:ClearAllPoints()
        if type(self.settings.posX) == "number" and type(self.settings.posY) == "number" then
            -- Restore saved absolute position (GetLeft/GetTop coordinates)
            self.contactContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                self.settings.posX, self.settings.posY)
        else
            -- No saved position yet: default to right of MailFrame
            self.contactContainer:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", CONTACT_BUTTON_MARGIN, 0)
        end

        UpdateUIPanelPositions(MailFrame)
        UpdateUIPanelPositions(OpenMailFrame)
        return
    end

    -- Locked: anchor to MailFrame using chosen position setting
    local scaledW = (width  + CONTAINER_PADDING * 2) * scale
    local scaledH = (height + CONTAINER_PADDING * 2) * scale

    if (position == "LEFT") then
        MailFrame:SetAttribute("UIPanelLayout-xoffset", scaledW + CONTACT_BUTTON_MARGIN)
        MailFrame:SetAttribute("UIPanelLayout-yoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraWidth", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraHeight", 0)

        self.contactContainer:ClearAllPoints()
        self.contactContainer:SetPoint("TOPRIGHT", MailFrame, "TOPLEFT", -CONTACT_BUTTON_MARGIN, 0)

    elseif (position == "TOP") then
        MailFrame:SetAttribute("UIPanelLayout-xoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-yoffset", -(scaledH + CONTACT_BUTTON_MARGIN))
        MailFrame:SetAttribute("UIPanelLayout-extraWidth", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraHeight", 0)

        self.contactContainer:ClearAllPoints()
        self.contactContainer:SetPoint("BOTTOMLEFT", MailFrame, "TOPLEFT", 0, CONTACT_BUTTON_MARGIN)

    elseif (position == "BOTTOM") then
        MailFrame:SetAttribute("UIPanelLayout-xoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-yoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraWidth", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraHeight", scaledH)

        self.contactContainer:ClearAllPoints()
        self.contactContainer:SetPoint("TOPLEFT", MailFrameTab1, "BOTTOMLEFT", 0, -CONTACT_BUTTON_MARGIN)

    else -- RIGHT (default)
        MailFrame:SetAttribute("UIPanelLayout-xoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-yoffset", 0)
        MailFrame:SetAttribute("UIPanelLayout-extraWidth", scaledW + CONTACT_BUTTON_MARGIN)
        MailFrame:SetAttribute("UIPanelLayout-extraHeight", 0)

        self.contactContainer:ClearAllPoints()
        self.contactContainer:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", CONTACT_BUTTON_MARGIN, 0)
    end

    UpdateUIPanelPositions(MailFrame)
    UpdateUIPanelPositions(OpenMailFrame)
end

ADDON:RegisterLoadUICallback(function()
    CreateContainer()
    ADDON:UpdateContactContainer()
end)
