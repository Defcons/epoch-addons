local _, Private = ...

local PCall = pcall
local Max = math.max
local Assert = assert
local GetTime = GetTime
local CreateFrame = CreateFrame
local GetMetaTable = getmetatable

local FrameRef = CreateFrame("Frame")
local ButtonRef = CreateFrame("Button")
local SliderRef = CreateFrame("Slider")
local CooldownRef = CreateFrame("Cooldown")
local StatusBarRef = CreateFrame("StatusBar")
local ScrollFrameRef = CreateFrame("ScrollFrame")
local CheckButtonRef = CreateFrame("CheckButton")
local PlayerModelRef = CreateFrame("PlayerModel")
local AnimationGroupRef = FrameRef:CreateAnimationGroup()

local Frame = GetMetaTable(FrameRef).__index
local Button = GetMetaTable(ButtonRef).__index
local Slider = GetMetaTable(SliderRef).__index
local Cooldown = GetMetaTable(CooldownRef).__index
local StatusBar = GetMetaTable(StatusBarRef).__index
local ScrollFrame = GetMetaTable(ScrollFrameRef).__index
local CheckButton = GetMetaTable(CheckButtonRef).__index
local PlayerModel = GetMetaTable(PlayerModelRef).__index
local FrameTexture = GetMetaTable(FrameRef:CreateTexture()).__index
local FrameFontString = GetMetaTable(FrameRef:CreateFontString()).__index
local AnimationAlpha = GetMetaTable(AnimationGroupRef:CreateAnimation("Alpha")).__index

local CONST_ATLAS_WIDTH			= 1
local CONST_ATLAS_HEIGHT		= 2
local CONST_ATLAS_LEFT			= 3
local CONST_ATLAS_RIGHT			= 4
local CONST_ATLAS_TOP			= 5
local CONST_ATLAS_BOTTOM		= 6
local CONST_ATLAS_TILESHORIZ	= 7
local CONST_ATLAS_TILESVERT		= 8
local CONST_ATLAS_TEXTUREPATH	= 9

-- [Preceding Compat] (Patches, Servers ...)
local Preceding_SetAtlas = FrameTexture.SetAtlas
local Preceding_GetAtlas = FrameTexture.GetAtlas

local function Hook_SetCooldown(Self, Start, Duration, Modrate)
	Self.___Start = Start > 0 and Start or nil
	Self.___Duration = Duration > 0 and Duration or nil
end

local function Method_GetCooldownTimes(Self)
	local Start = Self.___Start
	local Duration = Self.___Duration

	if ( Start and Duration and (GetTime() - (Start + Duration)) >= 0 ) then
		Start = nil
		Duration = nil
		Self.___Start = nil
		Self.___Duration = nil
	end

	return Start or 0, Duration or 0
end

local function Method_GetCooldownDuration(Self)
	local Duration = Self.___Duration

	if ( Duration ) then
		Duration = Duration - (GetTime() - Self.___Start)

		if ( Duration <= 0 ) then
			Duration = 0
			Self.___Start = nil
			Self.___Duration = nil
		end
	end

	return Duration or 0
end

local function Method_SetCooldownDuration(Self, Duration, Modrate)
	Self:SetCooldown(GetTime(), Duration, Modrate)
end

local function Method_SetSwipeColor(Self, R, G, B, A)
	if ( A ) then
		Self:SetAlpha(A)
	end
end

local function Method_SetDrawSwipe(Self, drawSwipe)
	Self:SetAlpha(drawSwipe and 1 or 0)
end

local function Method_GetDrawSwipe(Self)
	return Self:GetAlpha() > 0
end

local function Method_SetShown(Self, Show)
	if ( Show ) then
		Self:Show()
	else
		Self:Hide()
	end
end

local function Method_SetEnabled(Self, Enabled)
	if ( Enabled ) then
		Self:Enable()
	else
		Self:Disable()
	end
end

local function Method_SetSubTexCoord(Self, Left, Right, Top, Bottom)
	local UL_X, UL_Y, LL_X, LL_Y, UR_X, UR_Y, LR_X, LR_Y = Self:GetTexCoord()

	local LeftEdge = UL_X
	local RightEdge = UR_X
	local TopEdge = UL_Y
	local BottomEdge = LL_Y

	local Width  = RightEdge - LeftEdge
	local Height = BottomEdge - TopEdge

	LeftEdge = UL_X + Width * Left
	TopEdge  = UL_Y  + Height * Top
	RightEdge = Max(RightEdge * Right, UL_X)
	BottomEdge = Max(BottomEdge * Bottom, UL_Y)

	UL_X = LeftEdge
	UL_Y = TopEdge
	LL_X = LeftEdge
	LL_Y = BottomEdge
	UR_X = RightEdge
	UR_Y = TopEdge
	LR_X = RightEdge
	LR_Y = BottomEdge

	Self:SetTexCoord(UL_X, UL_Y, LL_X, LL_Y, UR_X, UR_Y, LR_X, LR_Y)
end

local function Method_SetAtlas(...)
	if ( Preceding_SetAtlas ) then
		local Success = PCall(Preceding_SetAtlas, ...)
		if ( Success and Preceding_GetAtlas and Preceding_GetAtlas(...) ) then
			return
		end
	end

	local Self, AtlasName, UseAtlasSize, FilterMode = ...
	local Atlas = ATLAS_INFO_STORAGE[AtlasName]

	Assert(Self, "SetAtlas: Not a valid object")
	Assert(AtlasName, "SetAtlas: Atlas must be specified")
	if not Atlas then return end

	Self:SetTexture(Atlas[CONST_ATLAS_TEXTUREPATH] or "", Atlas[CONST_ATLAS_TILESHORIZ], Atlas[CONST_ATLAS_TILESVERT])

	if ( UseAtlasSize ) then
		Self:SetSize(Atlas[CONST_ATLAS_WIDTH], Atlas[CONST_ATLAS_HEIGHT])
	end

	Self:SetTexCoord(Atlas[CONST_ATLAS_LEFT], Atlas[CONST_ATLAS_RIGHT], Atlas[CONST_ATLAS_TOP], Atlas[CONST_ATLAS_BOTTOM])

	Self:SetHorizTile(Atlas[CONST_ATLAS_TILESHORIZ])
	Self:SetVertTile(Atlas[CONST_ATLAS_TILESVERT])

	Self.___AtlasName = AtlasName
end

local function Method_GetAtlas(Self)
	if ( Preceding_GetAtlas ) then
		local AtlasName = Preceding_GetAtlas(Self)
		if ( AtlasName ) then
			return AtlasName
		end
	end

	return Self.___AtlasName
end

local function Method_SetNormalAtlas(Self, AtlasName)
	local Texture = Self:GetNormalTexture()

	if ( not Texture ) then
		Self:SetNormalTexture("")
		Texture = Self:GetNormalTexture()
	end

	Method_SetAtlas(Texture, AtlasName)
end

local function Method_SetPushedAtlas(Self, AtlasName)
	local Texture = Self:GetPushedTexture()

	if ( not Texture ) then
		Self:SetPushedTexture("")
		Texture = Self:GetPushedTexture()
	end

	Method_SetAtlas(Texture, AtlasName)
end

local function Method_SetDisabledAtlas(Self, AtlasName)
	local Texture = Self:GetDisabledTexture()

	if ( not Texture ) then
		Self:SetDisabledTexture("")
		Texture = Self:GetDisabledTexture()
	end

	Method_SetAtlas(Texture, AtlasName)
end

local function Method_SetHighlightAtlas(Self, AtlasName)
	local Texture = Self:GetHighlightTexture()

	if ( not Texture ) then
		Self:SetHighlightTexture("")
		Texture = Self:GetHighlightTexture()
	end

	Method_SetAtlas(Texture, AtlasName)
end

local function Method_ClearAndSetPoint(Self, ...)
	Self:ClearAllPoints()
	Self:SetPoint(...)
end

local function Method_CreateLine(Self, ...)
	local Line = Self:CreateTexture(...) -- Self is NineSlice
	Line.IsLine = true
	return Line
end

local function Method_IsForbidden(Self)
	return Self.___Forbidden
end

local function Method_SetForbidden(Self)
	Self.___Forbidden = true
end

local function Method_SetHideCountdownNumbers(Self, Hide)
	Self.noCooldownCount = (Hide) and true or nil -- OmniCC
end

local function Method_SetToAlpha(Self, normalizedAlpha)
	if ( Self.___FromAlpha ) then
		Self:SetChange(normalizedAlpha - Self.___FromAlpha)
		Self.___FromAlpha = nil
	else
		Self.___ToAlpha = normalizedAlpha
	end
end

local function Method_SetFromAlpha(Self, normalizedAlpha)
	if ( Self.___ToAlpha ) then
		self:SetChange(Self.___ToAlpha - normalizedAlpha)
		Self.___ToAlpha = nil
	else
		Self.___FromAlpha = normalizedAlpha
	end
end

local function Method_GetEffectiveScale(Self)
	return Self:GetParent():GetEffectiveScale()
end

-- FRAME
Frame.SetShown = Method_SetShown
Frame.ClearAndSetPoint = Method_ClearAndSetPoint
Frame.IsRectValid = Private.True
Frame.SetIgnoreParentScale = Private.Void
Frame.CreateMaskTexture = Private.Void
Frame.SetClipsChildren = Private.Void
Frame.SetPortraitZoom = Private.Void
Frame.SetForbidden = Method_SetForbidden
Frame.IsForbidden = Method_IsForbidden
	-- Line
		Frame.CreateLine = Method_CreateLine

	-- TEXTURE (FRAME)
		FrameTexture.SetShown = Method_SetShown
		FrameTexture.SetSubTexCoord = Method_SetSubTexCoord
		FrameTexture.SetAtlas = Method_SetAtlas
		FrameTexture.GetAtlas = Method_GetAtlas
		FrameTexture.ClearAndSetPoint = Method_ClearAndSetPoint
		FrameTexture.SetMask = Private.Void
		FrameTexture.GetNumMaskTextures = Private.Zero
		FrameTexture.SetSnapToPixelGrid = Private.Void
		FrameTexture.SetTexelSnappingBias = Private.Void
		FrameTexture.SetColorTexture = FrameTexture.SetTexture
		FrameTexture.GetEffectiveScale = Method_GetEffectiveScale
			-- Line
				FrameTexture.SetThickness = Private.Void
				FrameTexture.SetStartPoint = Private.Void
				FrameTexture.SetEndPoint = Private.Void
				FrameTexture.SetIgnoreParentAlpha = Private.Void

	-- FONTSTRING (FRAME)
		FrameFontString.SetShown = Method_SetShown
		FrameFontString.ClearAndSetPoint = Method_ClearAndSetPoint
		FrameFontString.GetEffectiveScale = Method_GetEffectiveScale

-- BUTTON
Button.SetShown = Method_SetShown
Button.SetEnabled = Method_SetEnabled
Button.ClearAndSetPoint = Method_ClearAndSetPoint
Button.SetNormalAtlas = Method_SetNormalAtlas
Button.SetPushedAtlas = Method_SetPushedAtlas
Button.SetDisabledAtlas = Method_SetDisabledAtlas
Button.SetHighlightAtlas = Method_SetHighlightAtlas
Button.SetForbidden = Method_SetForbidden
Button.IsForbidden = Method_IsForbidden

-- SLIDER
Slider.SetShown = Method_SetShown
Slider.ClearAndSetPoint = Method_ClearAndSetPoint

-- STATUSBAR
StatusBar.SetShown = Method_SetShown
StatusBar.ClearAndSetPoint = Method_ClearAndSetPoint

-- SCROLLFRAME
ScrollFrame.SetShown = Method_SetShown
ScrollFrame.ClearAndSetPoint = Method_ClearAndSetPoint

-- CHECKBUTTON
CheckButton.SetShown = Method_SetShown
CheckButton.SetEnabled = Method_SetEnabled
CheckButton.ClearAndSetPoint = Method_ClearAndSetPoint

-- COOLDOWN
hooksecurefunc(Cooldown, "SetCooldown", Hook_SetCooldown)
Cooldown.Clear = Cooldown.Hide
Cooldown.SetHideCountdownNumbers = Method_SetHideCountdownNumbers
Cooldown.SetDrawBling = Private.Void
Cooldown.SetDrawSwipe = Method_SetDrawSwipe
Cooldown.GetDrawSwipe = Method_GetDrawSwipe
Cooldown.IsPaused = Private.Void
Cooldown.Pause = Private.Void
Cooldown.Resume = Private.Void
Cooldown.SetSwipeTexture = Private.Void
Cooldown.SetSwipeColor = Method_SetSwipeColor
Cooldown.GetCooldownTimes = Method_GetCooldownTimes
Cooldown.GetCooldownDuration = Method_GetCooldownDuration
Cooldown.SetCooldownDuration = Method_SetCooldownDuration

-- PLAYERMODEL
PlayerModel.ClearTransform = Private.Void
PlayerModel.SetPortraitZoom = Private.Void -- TODO: Ref: zoom into parent (code: WA => calc)

-- ANIMATION
	-- ALPHA
	AnimationAlpha.SetFromAlpha = Method_SetFromAlpha
	AnimationAlpha.SetToAlpha = Method_SetToAlpha