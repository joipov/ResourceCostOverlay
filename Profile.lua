local ADDON_NAME, ns = ...

-- Copy-paste profile strings. Encode and decode are plain Lua so tests/run.lua
-- can load this file without a client. The dialog is built on first use.

local PREFIX = "!JPV:" .. ADDON_NAME .. "!"

local function Exclude()
	return ns.profileShareExclude
end

local function Encode(value, seen, exclude)
	local kind = type(value)
	if kind == "boolean" then
		if value then
			return "true"
		end
		return "false"
	end
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		return tostring(value)
	end
	if kind == "string" then
		return string.format("%q", value)
	end
	if kind ~= "table" then
		return nil
	end
	if seen[value] then
		return nil
	end
	seen[value] = true
	local parts = {}
	for key, child in pairs(value) do
		if not (exclude and exclude[key]) then
			local encodedKey = Encode(key, seen)
			local encodedChild = Encode(child, seen)
			if encodedKey and encodedChild then
				parts[#parts + 1] = "[" .. encodedKey .. "]=" .. encodedChild
			end
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function Trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function DecodeTable(payload)
	payload = Trim(payload)
	if payload:sub(1, 1) ~= "{" then
		return nil
	end
	local chunk, err
	if setfenv then
		chunk, err = (loadstring or load)("return " .. payload)
		if chunk then
			setfenv(chunk, {})
		end
	else
		chunk, err = load("return " .. payload, "profile", "t", {})
	end
	if not chunk then
		return nil, err
	end
	local ok, result = pcall(chunk)
	if not ok or type(result) ~= "table" then
		return nil
	end
	return result
end

local function ParseProfile(text)
	if type(text) ~= "string" then
		return nil, "Could not import this profile."
	end
	local id, payload = Trim(text):match("^!JPV:([^!]+)!(.*)$")
	if not id then
		return nil, "Not a Joipov profile string."
	end
	if id ~= ADDON_NAME then
		return nil, "That profile is for " .. id .. "."
	end
	local data = DecodeTable(payload)
	if not data then
		return nil, "Could not read that profile."
	end
	return data
end

function ns.ExportProfile()
	if type(ns.db) ~= "table" then
		return nil
	end
	local payload = Encode(ns.db, {}, Exclude())
	if not payload then
		return nil
	end
	return PREFIX .. payload
end

function ns.ImportProfile(text)
	local data, err = ParseProfile(text)
	if not data then
		return nil, err
	end
	if type(ns.LoadDB) ~= "function" or type(ns.db) ~= "table" then
		return nil, "Could not import this profile."
	end
	local imported = ns.LoadDB(data)
	local skip = Exclude()
	for key in pairs(ns.db) do
		if not (skip and skip[key]) then
			ns.db[key] = nil
		end
	end
	for key, value in pairs(imported) do
		if not (skip and skip[key]) then
			ns.db[key] = value
		end
	end
	return true
end

local function Tell(message)
	if ns.Print then
		ns.Print(message)
	else
		print(message)
	end
end

local function EnsurePopup()
	if not StaticPopupDialogs or StaticPopupDialogs.JOIPOV_PROFILE_IMPORT then
		return
	end
	StaticPopupDialogs.JOIPOV_PROFILE_IMPORT = {
		text = "Import this profile? The UI will reload.",
		button1 = OKAY or "OK",
		button2 = CANCEL or "Cancel",
		OnAccept = function()
			local apply = _G.JoipovProfileSharePending
			_G.JoipovProfileSharePending = nil
			if apply then
				apply()
			end
		end,
		OnCancel = function()
			_G.JoipovProfileSharePending = nil
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
		preferredIndex = 3,
	}
end

local function Solid(parent, r, g, b, a)
	local texture = parent:CreateTexture(nil, "BACKGROUND")
	texture:SetAllPoints()
	texture:SetColorTexture(r, g, b, a)
	return texture
end

local function EnsureDialog()
	local frame = _G.JoipovProfileShareDialog
	if frame then
		return frame
	end
	if not CreateFrame then
		return nil
	end

	frame = CreateFrame("Frame", "JoipovProfileShareDialog", UIParent)
	frame:SetSize(520, 280)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	Solid(frame, 0.08, 0.08, 0.09, 0.96)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	frame.title = title

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
	hint:SetWidth(480)
	hint:SetWordWrap(true)
	frame.hint = hint

	local box = CreateFrame("Frame", nil, frame)
	box:SetPoint("TOPLEFT", 20, -72)
	box:SetPoint("BOTTOMRIGHT", -20, 56)
	Solid(box, 0.12, 0.12, 0.14, 1)

	local scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -6, 6)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(468)
	edit:SetHeight(400)
	edit:SetTextInsets(4, 4, 4, 4)
	edit:SetMaxLetters(20000)
	edit:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)
	scroll:SetScrollChild(edit)
	frame.edit = edit

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(96, 22)
	close:SetPoint("BOTTOMRIGHT", -20, 18)
	close:SetText("Close")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	frame.close = close

	local apply = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	apply:SetSize(96, 22)
	apply:SetPoint("RIGHT", close, "LEFT", -8, 0)
	apply:SetText("Import")
	apply:SetScript("OnClick", function()
		if frame.importFn then
			frame.importFn(edit:GetText())
		end
	end)
	frame.apply = apply

	_G.JoipovProfileShareDialog = frame
	return frame
end

local function ShowDialog(mode, text)
	local frame = EnsureDialog()
	if not frame then
		return
	end
	if mode == "export" then
		frame.title:SetText("Export profile")
		frame.hint:SetText("Copy this string. Paste it into Import on another character or computer.")
		frame.apply:Hide()
		frame.close:SetText("Close")
		frame.edit:SetText(text or "")
		frame.edit:SetFocus()
		frame.edit:HighlightText()
		frame.importFn = nil
	else
		frame.title:SetText("Import profile")
		frame.hint:SetText("Paste a profile string for this addon.")
		frame.apply:Show()
		frame.close:SetText("Cancel")
		frame.edit:SetText("")
		frame.edit:SetFocus()
	end
	frame:Show()
end

function ns.ShowProfileExport()
	local text = ns.ExportProfile()
	if not text then
		Tell("Nothing to export.")
		return
	end
	ShowDialog("export", text)
end

function ns.ShowProfileImport()
	local frame = EnsureDialog()
	if not frame then
		return
	end
	frame.importFn = function(text)
		local data, err = ParseProfile(text)
		if not data then
			Tell(err)
			return
		end
		frame:Hide()
		local function Apply()
			local ok, applyErr = ns.ImportProfile(text)
			if not ok then
				Tell(applyErr)
				return
			end
			if ReloadUI then
				ReloadUI()
			end
		end
		EnsurePopup()
		if StaticPopup_Show then
			_G.JoipovProfileSharePending = Apply
			StaticPopup_Show("JOIPOV_PROFILE_IMPORT")
			return
		end
		Apply()
	end
	ShowDialog("import")
end

function ns.AddProfileShareButtons(category)
	if not category or not CreateSettingsButtonInitializer then
		return
	end
	local exportInit = CreateSettingsButtonInitializer(
		"Export profile",
		"Export",
		function()
			ns.ShowProfileExport()
		end,
		"Copy a string with this addon's settings and positions. Paste it in the same addon on another character or computer.",
		true
	)
	local importInit = CreateSettingsButtonInitializer(
		"Import profile",
		"Import",
		function()
			ns.ShowProfileImport()
		end,
		"Paste a profile string from this addon. The UI reloads after import.",
		true
	)
	if Settings and Settings.RegisterInitializer then
		Settings.RegisterInitializer(category, exportInit)
		Settings.RegisterInitializer(category, importInit)
		return
	end
	local layout = SettingsPanel and SettingsPanel:GetLayout(category)
	if layout then
		layout:AddInitializer(exportInit)
		layout:AddInitializer(importInit)
	end
end
