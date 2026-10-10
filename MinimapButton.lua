--[[
  Minimap launcher: LibDBIcon when present (Ellesmere / broker), else a built-in
  button. Hidden by default; enable via settings (showMinimapButton).
  Addon compartment uses ResourceCostOverlay_OnAddonCompartmentClick in Options.
]]

local _, ns = ...

local C_Timer = C_Timer
local GetCursorPosition = GetCursorPosition

local ICON_TEXTURE = "Interface\\Icons\\Ability_Warrior_Disarm"
local TITLE = "ResourceCostOverlay"
local DISPLAY = "Resource Cost on Icons"

local minimapBtn
local ldbIcon
local minimapDragging

local function UpdateMinimapButtonPosition()
	if not minimapBtn or ldbIcon then
		return
	end
	if minimapBtn:GetParent() ~= Minimap then
		return
	end
	local angle = math.rad(ns.db.minimapAngle or 220)
	local radius = (Minimap:GetWidth() / 2) + 10
	minimapBtn:ClearAllPoints()
	minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function MinimapIconDB()
	local icon = ns.db.minimapIcon
	if type(icon) ~= "table" then
		icon = {}
		ns.db.minimapIcon = icon
	end
	icon.hide = not ns.db.showMinimapButton
	return icon
end

function ns.UpdateMinimapButton()
	if not ns.db then
		return
	end
	if ldbIcon then
		if MinimapIconDB().hide then
			ldbIcon:Hide(TITLE)
		else
			ldbIcon:Show(TITLE)
		end
		return
	end
	if not minimapBtn then
		return
	end
	if ns.db.showMinimapButton then
		minimapBtn:Show()
		UpdateMinimapButtonPosition()
	else
		minimapBtn:Hide()
	end
end

local function OnLauncherClick()
	ns.OpenSettings()
end

local function OnLauncherTooltip(tt)
	tt:AddLine(DISPLAY)
	tt:AddLine("Click to open settings", 1, 1, 1)
end

local function TryLibDBIcon()
	local LibStub = _G.LibStub
	if not LibStub then
		return false
	end
	local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
	local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
	if not ldb or not icon then
		return false
	end

	local obj = ldb:GetDataObjectByName(TITLE)
	if not obj then
		obj = ldb:NewDataObject(TITLE, {
			type = "launcher",
			text = DISPLAY,
			icon = ICON_TEXTURE,
			OnClick = OnLauncherClick,
			OnTooltipShow = OnLauncherTooltip,
		})
	end
	if not obj then
		return false
	end

	local iconDB = MinimapIconDB()
	if not iconDB.minimapPos then
		iconDB.minimapPos = ns.db.minimapAngle or 220
	end
	if not icon:IsRegistered(TITLE) then
		icon:Register(TITLE, obj, iconDB)
	end
	ldbIcon = icon
	minimapBtn = icon.GetMinimapButton and icon:GetMinimapButton(TITLE)
	ns.UpdateMinimapButton()
	return true
end

local function OnButtonClick()
	if not minimapDragging then
		ns.OpenSettings()
	end
end

local function OnButtonEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(DISPLAY)
	GameTooltip:AddLine("Click to open settings", 1, 1, 1)
	GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function OnButtonLeave()
	GameTooltip:Hide()
end

local function OnButtonDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
	UpdateMinimapButtonPosition()
end

local function OnButtonDragStart(self)
	if self:GetParent() ~= Minimap then
		return
	end
	minimapDragging = true
	GameTooltip:Hide()
	self:SetScript("OnUpdate", OnButtonDragUpdate)
end

local function EndDrag()
	minimapDragging = false
end

local function OnButtonDragStop(self)
	self:SetScript("OnUpdate", nil)
	C_Timer.After(0, EndDrag)
end

function ns.CreateMinimapButton()
	if minimapBtn then
		ns.UpdateMinimapButton()
		return
	end
	if TryLibDBIcon() then
		return
	end

	minimapBtn = CreateFrame("Button", "ResourceCostOverlayMinimapButton", Minimap)
	minimapBtn:SetSize(31, 31)
	minimapBtn:SetFrameStrata("MEDIUM")
	minimapBtn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapBtn:RegisterForDrag("LeftButton")
	minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture(ICON_TEXTURE)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = minimapBtn:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetPoint("CENTER")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	minimapBtn:SetScript("OnClick", OnButtonClick)
	minimapBtn:SetScript("OnEnter", OnButtonEnter)
	minimapBtn:SetScript("OnLeave", OnButtonLeave)
	minimapBtn:SetScript("OnDragStart", OnButtonDragStart)
	minimapBtn:SetScript("OnDragStop", OnButtonDragStop)

	ns.UpdateMinimapButton()
end
