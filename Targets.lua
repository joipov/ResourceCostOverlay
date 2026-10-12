--[[
  Discover Cooldown Manager icons and action-bar buttons.

  Supports Blizzard CDM viewers and a host addon (ECME_CDMBar_* / EABButton* /
  ECME_TBB*), which reparents or replaces the stock frames.

  Spell bars: Essential + Utility, and host bars that are not buff-family.
  Buff bars: BuffIcon + BuffBar viewers, host buff-family icons, and
  host tracking bars when those replace Blizzard's buff bars.
]]

local _, ns = ...

local C_Timer = C_Timer

local CDM_SPELL_VIEWERS = {
	"EssentialCooldownViewer",
	"UtilityCooldownViewer",
}

local CDM_BUFF_ICON_VIEWER = "BuffIconCooldownViewer"
local CDM_BUFF_BAR_VIEWER = "BuffBarCooldownViewer"

local ACTION_BAR_PREFIXES = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarRightButton",
	"MultiBarLeftButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
	"MultiBar8Button",
	"EABButton", -- host action bars (EABButton<slot>, through Bar 8)
}

local BUTTONS_PER_BAR = 12
-- Host Bar 6 is slots 145-156, Bar 7 is 157-168, Bar 8 is 169-180.
-- Slots 121-144 are unused. Bars 9 and 10 sit inside 1-120.
local EAB_MAX_SLOT = 180
local hookedViewers = {}
local hookedButtons = {}
local rescanTicker

local function IsFrame(frame)
	return frame and type(frame) == "table" and frame.GetObjectType
end

--- Parentable widget (not a texture or fontstring).
local function IsWidgetFrame(frame)
	return IsFrame(frame) and frame.CreateFontString and frame.SetFrameLevel
end

local function GetEcmeModule()
	if not EllesmereUI or not EllesmereUI._ModuleNS then
		return nil
	end
	return EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
end

local reanchorHooked = false

--- The host addon shows a missing-buff placeholder on a bar that is already visible,
--- so the bar's OnShow never fires. Refresh after the reanchor paint, and the
--- next time that same placeholder is shown.
local function HookEllesmereReanchor()
	if reanchorHooked then
		return
	end
	local mod = GetEcmeModule()
	if not mod or type(mod.CollectAndReanchor) ~= "function" then
		return
	end
	reanchorHooked = true
	hooksecurefunc(mod, "CollectAndReanchor", function()
		ns.RequestRefresh(false)
	end)
end

local function HookPlaceholderShow(icon)
	if not icon._isPlaceholderFrame or hookedViewers[icon] then
		return
	end
	hookedViewers[icon] = true
	if icon.HookScript then
		icon:HookScript("OnShow", function()
			ns.RequestRefresh(false)
		end)
	end
end

local function HookViewerOnShow(viewer)
	if not IsFrame(viewer) or hookedViewers[viewer] then
		return
	end
	hookedViewers[viewer] = true
	if viewer.HookScript then
		viewer:HookScript("OnShow", function()
			ns.RequestRefresh(true)
		end)
		viewer:HookScript("OnHide", function()
			ns.RequestRefresh(true)
		end)
	end
end

local function AddTarget(out, seen, button, kind, spellID)
	if not IsFrame(button) or seen[button] then
		return
	end
	seen[button] = true
	out[#out + 1] = {
		button = button,
		kind = kind,
		spellID = spellID,
	}
	ns.EnsureOverlay(button)
end

local function CdmProfile(mod)
	local ecme = mod and mod.ECME
	local profile = ecme and ecme.db and ecme.db.profile
	return profile and profile.cdmBars or nil
end

local function IsBuffFamilyKey(mod, key)
	if mod and type(mod.IsBarBuffFamily) == "function" then
		return mod.IsBarBuffFamily(key) and true or false
	end
	return key == "buffs"
end

--- Blizzard tracked bars stay on screen when the host addon is absent, when the
--- user opted into Blizzard buff bars, or when the host addon is not hiding them.
local function BlizzardBuffBarsVisible(mod)
	if not mod then
		return true
	end
	local cdm = CdmProfile(mod)
	if not cdm then
		return true
	end
	if cdm.useBlizzardBuffBars then
		return true
	end
	if cdm.hideBlizzard then
		return false
	end
	return true
end

local function EllesmereTbbVisible(mod)
	if not mod or type(mod.GetTBBFrame) ~= "function" then
		return false
	end
	local cdm = CdmProfile(mod)
	if cdm and cdm.useBlizzardBuffBars then
		return false
	end
	return true
end

--- Long buff bars keep the number on the square icon, not the status bar.
local function CostAnchor(frame, anchorToIcon)
	if anchorToIcon and IsWidgetFrame(frame) and IsWidgetFrame(frame.Icon) then
		return frame.Icon
	end
	return frame
end

local function FrameHasSpellIdentity(frame)
	return frame.GetSpellID or frame.GetAuraSpellID or frame.cooldownID or frame.cooldownInfo
end

local function AddCdmItem(out, seen, item, anchorToIcon)
	if not IsWidgetFrame(item) or not FrameHasSpellIdentity(item) then
		return
	end
	local host = CostAnchor(item, anchorToIcon)
	AddTarget(out, seen, host, "cdm", ns.ResolveCdmSpellID(item))
end

local function CollectCdmViewer(viewerName, out, seen, anchorToIcon)
	local viewer = _G[viewerName]
	if not IsWidgetFrame(viewer) then
		return
	end
	HookViewerOnShow(viewer)

	local pool = viewer.itemFramePool
	if pool and pool.EnumerateActive then
		for frame in pool:EnumerateActive() do
			AddCdmItem(out, seen, frame, anchorToIcon)
		end
	end

	local children = { viewer:GetChildren() }
	for i = 1, #children do
		AddCdmItem(out, seen, children[i], anchorToIcon)
	end
end

local function CollectEllesmereIcons(out, seen, wantBuff)
	local mod = GetEcmeModule()
	if not mod then
		return
	end

	local countBefore = #out
	local iconsByKey = mod.cdmBarIcons
	local framesByKey = mod.cdmBarFrames

	if type(framesByKey) == "table" then
		for _, frame in pairs(framesByKey) do
			HookViewerOnShow(frame)
		end
	end

	if type(iconsByKey) == "table" then
		for key, icons in pairs(iconsByKey) do
			if IsBuffFamilyKey(mod, key) == wantBuff and type(icons) == "table" then
				for i = 1, #icons do
					local icon = icons[i]
					if IsWidgetFrame(icon) then
						HookPlaceholderShow(icon)
						AddTarget(out, seen, icon, "cdm", ns.ResolveCdmSpellID(icon))
					end
				end
			end
		end
	end

	-- Fallback: walk named bar containers if that family had no icon table.
	if #out == countBefore and type(framesByKey) == "table" then
		for key, frame in pairs(framesByKey) do
			if IsBuffFamilyKey(mod, key) == wantBuff and IsWidgetFrame(frame) then
				local children = { frame:GetChildren() }
				for i = 1, #children do
					local child = children[i]
					if IsWidgetFrame(child) then
						local sid = ns.ResolveCdmSpellID(child)
						if sid or child.GetSpellID or child.GetAuraSpellID or child.cooldownID or child.Icon then
							AddTarget(out, seen, child, "cdm", sid)
						end
					end
				end
			end
		end
	end
end

local function TbbSpellCandidates(cfg)
	local list = {}
	if type(cfg.spellID) == "number" and cfg.spellID > 0 then
		list[#list + 1] = cfg.spellID
	end
	if type(cfg.baseSpellID) == "number" and cfg.baseSpellID > 0 then
		list[#list + 1] = cfg.baseSpellID
	end
	if type(cfg.spellIDs) == "table" then
		for i = 1, #cfg.spellIDs do
			local sid = cfg.spellIDs[i]
			if type(sid) == "number" and sid > 0 then
				list[#list + 1] = sid
			end
		end
	end
	return list
end

local function CollectEllesmereTbb(out, seen)
	local mod = GetEcmeModule()
	if not mod or not EllesmereTbbVisible(mod) or type(mod.GetTrackedBuffBars) ~= "function" then
		return
	end

	local tbb = mod.GetTrackedBuffBars()
	local bars = tbb and tbb.bars
	if type(bars) ~= "table" then
		return
	end

	for i = 1, #bars do
		local cfg = bars[i]
		local wrap = mod.GetTBBFrame(i)
		if type(cfg) == "table" and cfg.enabled ~= false and IsWidgetFrame(wrap) then
			local icon = wrap._icon
			-- Parent to the icon even while the bar is hidden. The number shows
			-- with the icon; a hidden icon (icons turned off) stays blank.
			if IsWidgetFrame(icon) then
				HookViewerOnShow(wrap)
				HookViewerOnShow(icon)
				local sid = ns.PickCostSpellID(TbbSpellCandidates(cfg))
				AddTarget(out, seen, icon, "cdm", sid)
			end
		end
	end
end

local function HookActionButton(button)
	if not IsFrame(button) or hookedButtons[button] then
		return
	end
	hookedButtons[button] = true
	if button.HookScript then
		button:HookScript("OnShow", function()
			ns.RequestRefresh(false)
		end)
		button:HookScript("OnAttributeChanged", function(_, name)
			if name == "action" then
				ns.RequestRefresh(false)
			end
		end)
	end
end

local function CollectActionButtons(out, seen)
	-- Host action buttons (absolute slots).
	for slot = 1, EAB_MAX_SLOT do
		local button = _G["EABButton" .. slot]
		if IsFrame(button) then
			HookActionButton(button)
			AddTarget(out, seen, button, "action", ns.ResolveActionSpellID(button))
		end
	end

	-- Stock Blizzard prefixes (also used if the host addon is off).
	for p = 1, #ACTION_BAR_PREFIXES do
		local prefix = ACTION_BAR_PREFIXES[p]
		if prefix ~= "EABButton" then
			for i = 1, BUTTONS_PER_BAR do
				local button = _G[prefix .. i]
				if IsFrame(button) then
					HookActionButton(button)
					AddTarget(out, seen, button, "action", ns.ResolveActionSpellID(button))
				end
			end
		end
	end
end

function ns.CollectTargets()
	local db = ns.db
	local list = {}
	local seen = {}

	if db and db.enabled then
		if db.showCdmSpellBars ~= false then
			CollectEllesmereIcons(list, seen, false)
			for i = 1, #CDM_SPELL_VIEWERS do
				CollectCdmViewer(CDM_SPELL_VIEWERS[i], list, seen, false)
			end
		end
		if db.showCdmBuffBars ~= false then
			CollectEllesmereIcons(list, seen, true)
			CollectCdmViewer(CDM_BUFF_ICON_VIEWER, list, seen, false)
			if BlizzardBuffBarsVisible(GetEcmeModule()) then
				CollectCdmViewer(CDM_BUFF_BAR_VIEWER, list, seen, true)
			end
			CollectEllesmereTbb(list, seen)
		end
		if db.showActionBars then
			CollectActionButtons(list, seen)
		end
	end

	ns.SetTrackedButtons(list)
	return list
end

local function TryHookAllViewers()
	local viewers = {
		CDM_SPELL_VIEWERS[1],
		CDM_SPELL_VIEWERS[2],
		CDM_BUFF_ICON_VIEWER,
		CDM_BUFF_BAR_VIEWER,
	}
	for i = 1, #viewers do
		local viewer = _G[viewers[i]]
		if IsWidgetFrame(viewer) then
			HookViewerOnShow(viewer)
		end
	end
	HookEllesmereReanchor()
	local mod = GetEcmeModule()
	if mod and type(mod.cdmBarFrames) == "table" then
		for _, frame in pairs(mod.cdmBarFrames) do
			HookViewerOnShow(frame)
		end
	end
end

function ns.HookTargets()
	TryHookAllViewers()

	if rescanTicker then
		rescanTicker:Cancel()
		rescanTicker = nil
	end

	local attempts = 0
	rescanTicker = C_Timer.NewTicker(1, function(ticker)
		attempts = attempts + 1
		TryHookAllViewers()
		ns.RequestRefresh(true)
		local mod = GetEcmeModule()
		local ready = _G.EssentialCooldownViewer
			or _G.UtilityCooldownViewer
			or _G.BuffIconCooldownViewer
			or _G.BuffBarCooldownViewer
			or (mod and mod.cdmBarIcons)
		if ready or attempts >= 20 then
			ticker:Cancel()
			rescanTicker = nil
		end
	end)
end

function ns.DebugTargets()
	local list = ns.CollectTargets() or {}
	local withSpell, withCost, shown = 0, 0, 0
	local samples = {}
	local mod = GetEcmeModule()

	for i = 1, #list do
		local entry = list[i]
		local sid = entry.spellID
		if not sid then
			if entry.kind == "cdm" then
				sid = ns.ResolveCdmSpellID(entry.button)
			else
				sid = ns.ResolveActionSpellID(entry.button)
			end
		end
		if sid then
			withSpell = withSpell + 1
			local exact = entry.kind ~= "cdm"
			local cost, powerType = ns.GetSpellResourceCost(sid, exact)
			if cost then
				withCost = withCost + 1
				local text = ns.ComputeDisplay(sid, exact)
				if text then
					shown = shown + 1
				end
				if #samples < 8 then
					samples[#samples + 1] = string.format(
						"%s sid=%d cost=%s powerType=%s display=%s",
						entry.kind,
						sid,
						tostring(cost),
						tostring(powerType),
						tostring(text or "hidden")
					)
				end
			end
		end
	end

	ns.Print(string.format(
		"targets=%d spells=%d withCost=%d visible=%d ellesmereCDM=%s eab1=%s",
		#list,
		withSpell,
		withCost,
		shown,
		mod and "yes" or "no",
		_G.EABButton1 and "yes" or "no"
	))
	for i = 1, #samples do
		ns.Print("  " .. samples[i])
	end
	if #list == 0 then
		ns.Print("No buttons found. Enable spell bars, buff bars, and/or action bars in /rco settings.")
	elseif withCost == 0 then
		ns.Print("Buttons found but no resource costs resolved.")
	end
end
