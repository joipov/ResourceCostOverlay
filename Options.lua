local _, ns = ...

local Settings = Settings

function ns.OpenSettings()
	if not ns.settingsCategory then
		ns.InitOptions()
	end
	if not ns.settingsCategory then
		ns.Print("Settings UI unavailable.")
		return
	end
	Settings.OpenToCategory(ns.settingsCategory:GetID())
end

function _G.ResourceCostOverlay_OnAddonCompartmentClick()
	ns.OpenSettings()
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
	Settings.CreateCheckbox(category, setting, tooltip)
	return setting
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
	Settings.CreateSlider(category, setting, opts, tooltip)
	return setting
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
	createDropdown(category, setting, getOptions, tooltip)
	return setting
end

function ns.InitOptions()
	if ns.settingsCategory or not ns.db or not Settings then
		return
	end

	local ok, err = pcall(function()
		local category = Settings.RegisterVerticalLayoutCategory("Resource Cost on Icons")
		ns.settingsCategory = category
		local defaults = ns.defaults or {}

		AddCheckbox(
			category,
			"ENABLED",
			"enabled",
			"Enable overlay",
			defaults.enabled ~= false,
			"Show resource cost numbers on tracked buttons."
		)

		AddCheckbox(
			category,
			"SHOW_BARS",
			"showActionBars",
			"Show on action bars",
			defaults.showActionBars == true,
			"Overlay costs on Blizzard / Ellesmere action-bar buttons."
		)

		AddCheckbox(
			category,
			"SHOW_CDM_SPELLS",
			"showCdmSpellBars",
			"Show on CDM spell bars",
			defaults.showCdmSpellBars ~= false,
			"Overlay costs on Essential and Utility Cooldown Manager icons."
		)

		AddCheckbox(
			category,
			"SHOW_CDM_BUFFS",
			"showCdmBuffBars",
			"Show on CDM buff bars",
			defaults.showCdmBuffBars ~= false,
			"Overlay costs on Cooldown Manager buff icons and tracked buff bars."
		)

		AddCheckbox(
			category,
			"PERCENT_MANA",
			"percentMana",
			"Mana as % of max",
			defaults.percentMana ~= false,
			"Show mana costs as a percent of your maximum mana. Off shows the raw cost. Falls back to the raw cost if max mana cannot be read."
		)

		AddCheckbox(
			category,
			"PERCENT_RAGE",
			"percentRage",
			"Rage as % of max",
			defaults.percentRage == true,
			"Show rage costs as a percent of your maximum rage. Off shows the raw cost. Falls back to the raw cost if max rage cannot be read."
		)

		AddCheckbox(
			category,
			"PERCENT_ENERGY",
			"percentEnergy",
			"Energy as % of max",
			defaults.percentEnergy == true,
			"Show energy costs as a percent of your maximum energy. Off shows the raw cost. Falls back to the raw cost if max energy cannot be read."
		)

		AddCheckbox(
			category,
			"PERCENT_FOCUS",
			"percentFocus",
			"Focus as % of max",
			defaults.percentFocus == true,
			"Show focus costs as a percent of your maximum focus. Off shows the raw cost. Falls back to the raw cost if max focus cannot be read."
		)

		AddCheckbox(
			category,
			"SHOW_MINIMAP",
			"showMinimapButton",
			"Show minimap button",
			defaults.showMinimapButton == true,
			"Show a minimap button that opens these settings. Off by default. The addon compartment entry always works.",
			function()
				OnChanged()
				if ns.UpdateMinimapButton then
					ns.UpdateMinimapButton()
				end
			end
		)

		AddDropdown(category, "ANCHOR", "anchor", "Number position", defaults.anchor or "BOTTOMLEFT", function()
			local container = Settings.CreateControlTextContainer()
			container:Add("CENTER", "Center")
			container:Add("TOP", "Top")
			container:Add("BOTTOM", "Bottom")
			container:Add("LEFT", "Left")
			container:Add("RIGHT", "Right")
			container:Add("TOPLEFT", "Top Left")
			container:Add("TOPRIGHT", "Top Right")
			container:Add("BOTTOMLEFT", "Bottom Left")
			container:Add("BOTTOMRIGHT", "Bottom Right")
			return container:GetData()
		end, "Where on the button the number is anchored.")

		AddSlider(
			category,
			"OFFSET_X",
			"offsetX",
			"Offset X",
			defaults.offsetX or 1,
			-40,
			40,
			1,
			function(value)
				return tostring(math.floor(value + 0.5)) .. " px"
			end,
			"Horizontal shift of the number from the anchor."
		)

		AddSlider(
			category,
			"OFFSET_Y",
			"offsetY",
			"Offset Y",
			defaults.offsetY or 1,
			-40,
			40,
			1,
			function(value)
				return tostring(math.floor(value + 0.5)) .. " px"
			end,
			"Vertical shift of the number from the anchor."
		)

		AddSlider(
			category,
			"FONT_SIZE",
			"fontSize",
			"Font size",
			defaults.fontSize or 9,
			6,
			32,
			1,
			function(value)
				return tostring(math.floor(value + 0.5))
			end,
			"Size of the cost number."
		)

		AddCheckbox(
			category,
			"TINT",
			"tintByResource",
			"Tint by resource type",
			defaults.tintByResource == true,
			"Color the number by power type (mana blue, rage red, energy yellow). When off, uses the color below."
		)

		AddSlider(
			category,
			"COLOR_R",
			"colorR",
			"Text color red",
			defaults.colorR or 1,
			0,
			1,
			0.05,
			function(value)
				return string.format("%.0f%%", value * 100)
			end,
			"Red channel when not tinting by resource."
		)

		AddSlider(
			category,
			"COLOR_G",
			"colorG",
			"Text color green",
			defaults.colorG or 1,
			0,
			1,
			0.05,
			function(value)
				return string.format("%.0f%%", value * 100)
			end,
			"Green channel when not tinting by resource."
		)

		AddSlider(
			category,
			"COLOR_B",
			"colorB",
			"Text color blue",
			defaults.colorB or 1,
			0,
			1,
			0.05,
			function(value)
				return string.format("%.0f%%", value * 100)
			end,
			"Blue channel when not tinting by resource."
		)

		Settings.RegisterAddOnCategory(category)
	end)

	if not ok then
		ns.settingsCategory = nil
		ns.Print("options panel failed: " .. tostring(err))
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
				.. ". /rco percent mana|rage|energy|focus toggles one."
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
		local focus = GetMouseFoci and GetMouseFoci() or nil
		local frame = focus and focus[1] or (GetMouseFocus and GetMouseFocus())
		-- Walk up a few parents to find a button-like frame.
		local node = frame
		for _ = 1, 6 do
			if not node then
				break
			end
			local sid = ns.ResolveCdmSpellID(node) or ns.ResolveActionSpellID(node)
			if sid then
				local cost, powerType = ns.GetSpellResourceCost(sid)
				local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
				ns.Print(string.format(
					"mouse: frame=%s sid=%s name=%s cost=%s powerType=%s",
					tostring(node.GetName and node:GetName() or node),
					tostring(sid),
					tostring(name),
					tostring(cost),
					tostring(powerType)
				))
				return
			end
			node = node.GetParent and node:GetParent()
		end
		ns.Print("mouse: no spell found under cursor (hover a CDM or action button).")
		return
	end
	if msg == "help" then
		ns.Print("/rco — settings | bars | percent [mana|rage|energy|focus] | minimap | toggle | debug | mouse")
		return
	end
	ns.OpenSettings()
end
