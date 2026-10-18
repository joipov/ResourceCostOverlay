local _, ns = ...

local Settings = Settings
local CreateSettingsListSectionHeaderInitializer = CreateSettingsListSectionHeaderInitializer
local CreateSettingsButtonInitializer = CreateSettingsButtonInitializer

function ns.OpenSettings()
	if not ns.settingsCategory then
		ns.InitOptions()
	end
	if not ns.settingsCategory then
		ns.Print("Couldn't open settings.")
		return
	end
	Settings.OpenToCategory(ns.settingsCategory:GetID())
end

function _G.ResourceCostOverlay_OnAddonCompartmentClick()
	ns.OpenSettings()
end

function _G.ResourceCostOverlay_OnAddonCompartmentEnter(_, owner)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(owner or UIParent, "ANCHOR_LEFT")
	GameTooltip:AddLine("Spell Resources")
	GameTooltip:AddLine("Click for settings.", 1, 1, 1)
	GameTooltip:Show()
end

function _G.ResourceCostOverlay_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

local function OnChanged()
	if ns.ApplySettings then
		ns.ApplySettings()
	end
end

local function AddCheckbox(category, varName, key, label, defaultValue, tooltip, onChanged)
	local setting = Settings.RegisterAddOnSetting(
		category,
		"RCO_" .. varName,
		key,
		ns.db,
		Settings.VarType.Boolean,
		label,
		defaultValue
	)
	setting:SetValueChangedCallback(onChanged or OnChanged)
	local checkbox = Settings.CreateCheckbox(category, setting, tooltip)
	return checkbox, setting
end

local function AddSlider(category, varName, key, label, defaultValue, minV, maxV, step, formatFn, tooltip)
	if not (Settings.CreateSliderOptions and Settings.CreateSlider) then
		return
	end
	local setting = Settings.RegisterAddOnSetting(
		category,
		"RCO_" .. varName,
		key,
		ns.db,
		Settings.VarType.Number,
		label,
		defaultValue
	)
	setting:SetValueChangedCallback(function()
		local v = tonumber(ns.db[key])
		if v then
			if step >= 1 then
				v = math.floor(v + 0.5)
			end
			if v < minV then
				v = minV
			elseif v > maxV then
				v = maxV
			end
			ns.db[key] = v
		end
		OnChanged()
	end)
	local opts = Settings.CreateSliderOptions(minV, maxV, step)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and formatFn then
		opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatFn)
	end
	local slider = Settings.CreateSlider(category, setting, opts, tooltip)
	return slider, setting
end

local function AddDropdown(category, varName, key, label, defaultValue, getOptions, tooltip)
	local createDropdown = Settings.CreateDropdown or Settings.CreateDropDown
	if not createDropdown then
		return
	end
	local varType = (Settings.VarType and Settings.VarType.String) or "string"
	local setting = Settings.RegisterAddOnSetting(
		category,
		"RCO_" .. varName,
		key,
		ns.db,
		varType,
		label,
		defaultValue
	)
	setting:SetValueChangedCallback(OnChanged)
	local dropdown = createDropdown(category, setting, getOptions, tooltip)
	return dropdown, setting
end

local function Clamp01(value, fallback)
	value = tonumber(value)
	if not value then
		return fallback
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function SetTextColor(r, g, b)
	local db = ns.db
	if not db then
		return
	end
	local defaults = ns.defaults or {}
	db.colorR = Clamp01(r, defaults.colorR or 1)
	db.colorG = Clamp01(g, defaults.colorG or 1)
	db.colorB = Clamp01(b, defaults.colorB or 1)
	OnChanged()
end

local function OpenColorPicker()
	local db = ns.db
	if not db or not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
		return
	end
	local prevR, prevG, prevB = db.colorR, db.colorG, db.colorB
	ColorPickerFrame:SetupColorPickerAndShow({
		r = prevR,
		g = prevG,
		b = prevB,
		hasOpacity = false,
		swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			SetTextColor(r, g, b)
		end,
		cancelFunc = function()
			SetTextColor(prevR, prevG, prevB)
		end,
	})
end

local function AddHeader(category, text)
	if not (SettingsPanel and SettingsPanel.GetLayout and CreateSettingsListSectionHeaderInitializer) then
		return
	end
	local layout = SettingsPanel:GetLayout(category)
	if not (layout and layout.AddInitializer) then
		return
	end
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function AddColorButton(category, tooltip)
	if not (SettingsPanel and SettingsPanel.GetLayout and CreateSettingsButtonInitializer) then
		return
	end
	local layout = SettingsPanel:GetLayout(category)
	if not (layout and layout.AddInitializer) then
		return
	end
	local initializer = CreateSettingsButtonInitializer(
		"Text color",
		"Choose color",
		function()
			OpenColorPicker()
		end,
		tooltip,
		true
	)
	layout:AddInitializer(initializer)
	return initializer
end

function ns.InitOptions()
	if ns.settingsCategory or not ns.db or not Settings then
		return
	end

	local ok = pcall(function()
		local category = Settings.RegisterVerticalLayoutCategory("Spell Resources")
		ns.settingsCategory = category
		local defaults = ns.defaults or {}

		local percentTip = "Percent of your maximum. Off shows the cost itself."

		local enableCheckbox, enableSetting = AddCheckbox(
			category,
			"ENABLED",
			"enabled",
			"Enable Spell Resources",
			defaults.enabled ~= false,
			"Shows resource costs on ability icons, and rates on spell tooltips."
		)

		local minimapCheckbox = AddCheckbox(
			category,
			"SHOW_MINIMAP",
			"showMinimapButton",
			"Minimap button",
			defaults.showMinimapButton ~= false,
			"Button on the minimap. Opens settings.",
			function()
				OnChanged()
				if ns.UpdateMinimapButton then
					ns.UpdateMinimapButton()
				end
			end
		)

		AddHeader(category, "Icons")

		local actionBars = AddCheckbox(
			category,
			"SHOW_BARS",
			"showActionBars",
			"Action bars",
			defaults.showActionBars == true,
			"On the default action buttons and custom action buttons."
		)

		local cooldownSpells = AddCheckbox(
			category,
			"SHOW_CDM_SPELLS",
			"showCdmSpellBars",
			"Cooldown spells",
			defaults.showCdmSpellBars ~= false,
			"On Essential and Utility Cooldown Manager icons."
		)

		local cooldownBuffs = AddCheckbox(
			category,
			"SHOW_CDM_BUFFS",
			"showCdmBuffBars",
			"Cooldown buffs",
			defaults.showCdmBuffBars ~= false,
			"On Cooldown Manager buff icons and tracked buff bars."
		)

		AddHeader(category, "Numbers")

		local percentMana = AddCheckbox(
			category,
			"PERCENT_MANA",
			"percentMana",
			"Mana as % of max",
			defaults.percentMana ~= false,
			percentTip
		)

		local percentRage = AddCheckbox(
			category,
			"PERCENT_RAGE",
			"percentRage",
			"Rage as % of max",
			defaults.percentRage == true,
			percentTip
		)

		local percentEnergy = AddCheckbox(
			category,
			"PERCENT_ENERGY",
			"percentEnergy",
			"Energy as % of max",
			defaults.percentEnergy == true,
			percentTip
		)

		local percentFocus = AddCheckbox(
			category,
			"PERCENT_FOCUS",
			"percentFocus",
			"Focus as % of max",
			defaults.percentFocus == true,
			percentTip
		)

		AddHeader(category, "Tooltips")

		local efficiency = AddCheckbox(
			category,
			"SHOW_EFFICIENCY",
			"showEfficiency",
			"Resource efficiency",
			defaults.showEfficiency ~= false,
			"Damage, healing, or absorb per point of mana, rage, energy, or focus, on the cost line. English spell descriptions."
		)

		local efficiencyShift = AddCheckbox(
			category,
			"EFFICIENCY_SHIFT",
			"showEfficiencyShiftOnly",
			"Efficiency only while Shift is held",
			defaults.showEfficiencyShiftOnly == true,
			"Hides the efficiency suffix until Shift is held."
		)

		local throughput = AddCheckbox(
			category,
			"SHOW_THROUGHPUT",
			"showThroughput",
			"Healing and damage per second",
			defaults.showThroughput ~= false,
			"On the cast line, for spells that can be cast again immediately. English spell descriptions."
		)

		local throughputShift = AddCheckbox(
			category,
			"THROUGHPUT_SHIFT",
			"showThroughputShiftOnly",
			"Per-second rates only while Shift is held",
			defaults.showThroughputShiftOnly == true,
			"Hides the dps/hps suffix until Shift is held."
		)

		local notes = AddCheckbox(
			category,
			"SHOW_NOTES",
			"showNotes",
			"Calculation notes",
			defaults.showNotes ~= false,
			"Explains forgone rage, DoT DPS mode, absorb drain, and similar calculations."
		)

		local notesShift = AddCheckbox(
			category,
			"NOTES_SHIFT",
			"showNotesShiftOnly",
			"Notes only while Shift is held",
			defaults.showNotesShiftOnly ~= false,
			"Shows a Shift hint after the suffix until Shift is held."
		)

		AddHeader(category, "Placement")

		local numberPosition = AddDropdown(category, "ANCHOR", "anchor", "Number position", defaults.anchor or "BOTTOMLEFT", function()
			local container = Settings.CreateControlTextContainer()
			container:Add("CENTER", "Center")
			container:Add("TOP", "Top")
			container:Add("BOTTOM", "Bottom")
			container:Add("LEFT", "Left")
			container:Add("RIGHT", "Right")
			container:Add("TOPLEFT", "Top left")
			container:Add("TOPRIGHT", "Top right")
			container:Add("BOTTOMLEFT", "Bottom left")
			container:Add("BOTTOMRIGHT", "Bottom right")
			return container:GetData()
		end, "Where the number sits on the icon.")

		local offsetX = AddSlider(
			category,
			"OFFSET_X",
			"offsetX",
			"Horizontal offset",
			defaults.offsetX or 1,
			-40,
			40,
			1,
			function(value)
				return tostring(math.floor(value + 0.5)) .. " px"
			end,
			"Moves the number left or right."
		)

		local offsetY = AddSlider(
			category,
			"OFFSET_Y",
			"offsetY",
			"Vertical offset",
			defaults.offsetY or 1,
			-40,
			40,
			1,
			function(value)
				return tostring(math.floor(value + 0.5)) .. " px"
			end,
			"Moves the number up or down."
		)

		local textSize = AddSlider(
			category,
			"FONT_SIZE",
			"fontSize",
			"Text size",
			defaults.fontSize or 9,
			6,
			32,
			1,
			function(value)
				return tostring(math.floor(value + 0.5))
			end,
			"Size of the number."
		)

		AddHeader(category, "Color")

		local colorByResource = AddCheckbox(
			category,
			"TINT",
			"tintByResource",
			"Color by resource",
			defaults.tintByResource == true,
			"Mana blue, rage red, focus orange, energy yellow. Off uses Text color."
		)

		local textColor = AddColorButton(category, "Used when Color by resource is off.")

		local function MasterEnabled()
			return enableSetting:GetValue()
		end
		local function Parent(child)
			if child then
				child:SetParentInitializer(enableCheckbox, MasterEnabled)
			end
		end
		Parent(minimapCheckbox)
		Parent(actionBars)
		Parent(cooldownSpells)
		Parent(cooldownBuffs)
		Parent(percentMana)
		Parent(percentRage)
		Parent(percentEnergy)
		Parent(percentFocus)
		Parent(efficiency)
		Parent(efficiencyShift)
		Parent(throughput)
		Parent(throughputShift)
		Parent(notes)
		Parent(notesShift)
		Parent(numberPosition)
		Parent(offsetX)
		Parent(offsetY)
		Parent(textSize)
		Parent(colorByResource)
		Parent(textColor)

		Settings.RegisterAddOnCategory(category)
	end)

	if not ok then
		ns.settingsCategory = nil
		ns.Print("Couldn't open settings.")
	end
end

_G.SLASH_RCO1 = "/rco"
_G.SLASH_RCO2 = "/resourcecost"
_G.SlashCmdList.RCO = function(msg)
	msg = type(msg) == "string" and msg:lower():match("^%s*(.-)%s*$") or ""
	if msg == "bars" then
		if ns.db then
			ns.db.showActionBars = not ns.db.showActionBars
			ns.ApplySettings()
			ns.Print("Action bars: " .. (ns.db.showActionBars and "on" or "off") .. ".")
		end
		return
	end
	if msg == "percent" or msg == "pct" or msg:match("^percent ") or msg:match("^pct ") then
		if not ns.db then
			return
		end
		local which = msg:match("^p%w*%s+(%S+)$")
		local keys = {
			mana = "percentMana",
			rage = "percentRage",
			energy = "percentEnergy",
			focus = "percentFocus",
		}
		local labels = {
			percentMana = "Mana",
			percentRage = "Rage",
			percentEnergy = "Energy",
			percentFocus = "Focus",
		}
		if which then
			local key = keys[which]
			if not key then
				ns.Print("Use mana, rage, energy, or focus.")
				return
			end
			ns.db[key] = not ns.db[key]
			ns.ApplySettings()
			ns.Print(labels[key] .. " as % of max: " .. (ns.db[key] and "on" or "off") .. ".")
			return
		end
		ns.Print(
			"Mana "
				.. (ns.db.percentMana and "on" or "off")
				.. ", rage "
				.. (ns.db.percentRage and "on" or "off")
				.. ", energy "
				.. (ns.db.percentEnergy and "on" or "off")
				.. ", focus "
				.. (ns.db.percentFocus and "on" or "off")
				.. ". /rco percent mana, rage, energy, focus toggles one."
		)
		return
	end
	if msg == "minimap" or msg == "mm" then
		if ns.db then
			ns.db.showMinimapButton = not ns.db.showMinimapButton
			ns.ApplySettings()
			if ns.UpdateMinimapButton then
				ns.UpdateMinimapButton()
			end
			ns.Print("Minimap button: " .. (ns.db.showMinimapButton and "on" or "off") .. ".")
		end
		return
	end
	if msg == "toggle" then
		if ns.db then
			ns.SetEnabled(not ns.db.enabled)
			ns.Print(ns.db.enabled and "Enabled." or "Disabled.")
		end
		return
	end
	if msg == "debug" then
		if ns.DebugTargets then
			ns.DebugTargets()
		end
		return
	end
	if msg == "mouse" or msg == "probe" then
		local starts = {}
		if GetMouseFoci then
			local ok, foci = pcall(GetMouseFoci)
			if ok and type(foci) == "table" then
				for i = 1, #foci do
					starts[#starts + 1] = foci[i]
				end
			end
		end
		if GetMouseFocus then
			local ok, focus = pcall(GetMouseFocus)
			if ok and focus then
				starts[#starts + 1] = focus
			end
		end
		-- Walk up the frame hierarchy. Action buttons and CDM icons have
		-- several child layers, so a few parents are not always enough.
		for s = 1, #starts do
			local node = starts[s]
			for _ = 1, 12 do
				if not node then
					break
				end
				local sid = ns.ButtonSpellID(node) or ns.ResolveCdmSpellID(node) or ns.ResolveActionSpellID(node)
				if sid then
					local rawCost, rawType = ns.RawSpellResourceCost(sid)
					local exactCost, exactType = ns.GetSpellResourceCost(sid, true)
					local trainedCost, trainedType = ns.GetSpellResourceCost(sid)
					local tooltipCost, tooltipType = ns.TooltipSpellResourceCost(sid)
					local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
					local rank = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(sid)
					ns.Print(string.format(
						"mouse: frame=%s sid=%s name=%s rank=%s raw=%s exact=%s trained=%s tooltip=%s powerType=%s",
						tostring(node.GetName and node:GetName() or node),
						tostring(sid),
						tostring(name),
						tostring(rank),
						tostring(rawCost),
						tostring(exactCost),
						tostring(trainedCost),
						tostring(tooltipCost),
						tostring(exactType or rawType or trainedType or tooltipType)
					))
					return
				end
				node = node.GetParent and node:GetParent()
			end
		end
		-- Nothing resolved. If this is a macro, print what the client says it
		-- contains so a failing macro can be diagnosed from chat.
		for s = 1, #starts do
			local node = starts[s]
			for _ = 1, 12 do
				if not node then
					break
				end
				local action = ns.ActionSlot(node)
				if action then
					local ok, actionType, id = pcall(GetActionInfo, action)
					if ok and actionType == "macro" then
						local body, macroSpell, bodySpell
						if GetMacroBody then
							local bodyOk, value = pcall(GetMacroBody, id)
							if bodyOk then
								body = value
							end
						end
						if GetMacroSpell then
							local spellOk, value = pcall(GetMacroSpell, id)
							if spellOk then
								macroSpell = value
							end
						end
						if ns.ResolveMacroBodySpellID then
							local bodyOk, value = pcall(ns.ResolveMacroBodySpellID, id)
							if bodyOk then
								bodySpell = value
							end
						end
						ns.Print(string.format(
							"mouse: action=%s macro=%s body=%s spell=%s bodySpell=%s",
							tostring(action),
							tostring(id),
							tostring(body),
							tostring(macroSpell),
							tostring(bodySpell)
						))
						return
					end
				end
				node = node.GetParent and node:GetParent()
			end
		end
		ns.Print("mouse: no spell found under cursor (hover a CDM icon or action button).")
		return
	end
	if msg == "spell" then
		local last = ns.lastSpellTooltip
		if not last then
			ns.Print("Hover a spell tooltip first.")
			return
		end
		ns.Print(string.format("%s (%s)", tostring(last.name), tostring(last.id)))
		if last.resource then
			ns.Print("cost: " .. tostring(last.cost) .. " " .. tostring(last.resource))
		end
		local cast = last.cast
		if cast then
			ns.Print(string.format(
				"cast: %s, %s sec, cooldown %s",
				tostring(cast.kind),
				tostring(cast.seconds),
				tostring(cast.cooldown)
			))
		end
		local lines = last.lines or {}
		for i = 1, #lines do
			ns.Print(string.format("%d: %s", i, lines[i]))
		end
		return
	end
	if msg == "help" then
		ns.Print("/rco: settings, bars, percent [mana, rage, energy, focus], minimap, toggle, debug, mouse, spell")
		return
	end
	ns.OpenSettings()
end
