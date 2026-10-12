local ADDON_NAME, ns = ...

-- Minimap button and addon compartment. Uses LibDBIcon when another addon has
-- loaded it. Otherwise builds a button named LibDBIcon10_<addon>, the frame
-- button collectors look for. Both read and write
-- db.minimapIcon.

local TITLE = "Resource Cost on Icons"
local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local CLICK_TEXT = "Click for settings."
local DRAG_TEXT = "Drag to move."

local FRAME_NAME = "LibDBIcon10_" .. ADDON_NAME

local GameTooltip = GameTooltip
local Minimap = Minimap
local GetCursorPosition = GetCursorPosition

local button
local ldbIcon
local dragging

local function OnLauncherClick()
	ns.OpenSettings()
end

local function IconDB()
	local icon = ns.db.minimapIcon
	icon.hide = not ns.db.showMinimapButton
	return icon
end

local function AddTooltipLines(tooltip)
	tooltip:AddLine(TITLE)
	tooltip:AddLine(CLICK_TEXT, 1, 1, 1)
end

local function PlaceButton()
	local angle = math.rad(ns.db.minimapIcon.minimapPos)
	local radius = Minimap:GetWidth() / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
	if not ns.db then
		return
	end
	local icon = IconDB()
	if ldbIcon then
		if icon.hide then
			ldbIcon:Hide(ADDON_NAME)
		else
			ldbIcon:Show(ADDON_NAME)
		end
	elseif button then
		button:SetShown(not icon.hide)
		PlaceButton()
	end
end

local function TryLibDBIcon()
	local LibStub = _G.LibStub
	local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
	if not (ldb and icon) then
		return false
	end
	local object = ldb:GetDataObjectByName(ADDON_NAME) or ldb:NewDataObject(ADDON_NAME, {
		type = "launcher",
		text = TITLE,
		icon = ICON,
		OnClick = OnLauncherClick,
		OnTooltipShow = AddTooltipLines,
	})
	if not icon:IsRegistered(ADDON_NAME) then
		icon:Register(ADDON_NAME, object, IconDB())
	end
	ldbIcon = icon
	return true
end

local function OnButtonClick()
	if not dragging then
		OnLauncherClick()
	end
end

local function OnButtonEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	AddTooltipLines(GameTooltip)
	GameTooltip:AddLine(DRAG_TEXT, 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function OnButtonLeave()
	GameTooltip:Hide()
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.minimapIcon.minimapPos = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
	PlaceButton()
end

local function OnDragStart(self)
	dragging = true
	GameTooltip:Hide()
	self:SetScript("OnUpdate", OnDragUpdate)
end

local function EndDrag()
	dragging = false
end

local function OnDragStop(self)
	self:SetScript("OnUpdate", nil)
	-- The click that ends a drag arrives after OnDragStop.
	C_Timer.After(0, EndDrag)
end

local function CreateButton()
	button = CreateFrame("Button", FRAME_NAME, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	-- Button collectors read these LibDBIcon fields.
	button.dataObject = { type = "launcher", text = TITLE, icon = ICON }
	button.db = ns.db.minimapIcon

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("CENTER")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT", -1, 1)
	button.border = border

	button:SetScript("OnClick", OnButtonClick)
	button:SetScript("OnEnter", OnButtonEnter)
	button:SetScript("OnLeave", OnButtonLeave)
	button:SetScript("OnDragStart", OnDragStart)
	button:SetScript("OnDragStop", OnDragStop)
end

-- Called once at PLAYER_LOGIN, after other addons have loaded LibDBIcon.
function ns.CreateMinimapButton()
	if ldbIcon or button then
		return
	end
	if not TryLibDBIcon() then
		CreateButton()
	end
	ns.UpdateMinimapButton()
end
