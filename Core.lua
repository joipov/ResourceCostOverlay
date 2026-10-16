--[[
  Spell Resources — rage, energy, focus, and mana cost numbers on Cooldown
  Manager spell bars, buff bars, and optionally action bars.

  An action button shows the rank placed on it. A Cooldown Manager icon
  shows the rank the player has trained, because those viewers often store
  rank 1.
]]

local ADDON_NAME, ns = ...

local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local issecrettable = issecrettable
local canaccesstable = canaccesstable
local C_Timer = C_Timer

local POWER_MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local POWER_RAGE = Enum and Enum.PowerType and Enum.PowerType.Rage or 1
local POWER_FOCUS = Enum and Enum.PowerType and Enum.PowerType.Focus or 2
local POWER_ENERGY = Enum and Enum.PowerType and Enum.PowerType.Energy or 3

local TRACKED_POWER = {
	[POWER_MANA] = true,
	[POWER_RAGE] = true,
	[POWER_FOCUS] = true,
	[POWER_ENERGY] = true,
}

local POWER_TINT = {
	[POWER_MANA] = { 0.25, 0.50, 1.00 },
	[POWER_RAGE] = { 0.90, 0.20, 0.20 },
	[POWER_FOCUS] = { 1.00, 0.55, 0.20 },
	[POWER_ENERGY] = { 1.00, 0.95, 0.20 },
}

local PERCENT_KEY = {
	[POWER_MANA] = "percentMana",
	[POWER_RAGE] = "percentRage",
	[POWER_FOCUS] = "percentFocus",
	[POWER_ENERGY] = "percentEnergy",
}

local FONT_PATH_FALLBACK = "Fonts\\FRIZQT__.TTF"
local REFRESH_THROTTLE = 0.08

local driver = CreateFrame("Frame")
local overlays = {} -- [button] = FontString
local trackedButtons = {}
local cooldownSpellCache = {} -- [cooldownID] = spellID
local refreshSerial = 0
local refreshQueued = false
local layoutDirty = true

local function Print(msg)
	print("|cff8b5cf6Joipov|r Spell Resources: " .. tostring(msg or ""))
end

ns.Print = Print

function ns.Debug(...)
	if not (ns.db and ns.db.debug) then
		return
	end
	local count = select("#", ...)
	local parts = {}
	for i = 1, count do
		parts[i] = tostring(select(i, ...))
	end
	Print(table.concat(parts, " "))
end

-- Login line. Name and version come from the TOC, so they never drift.
function ns.Welcome()
	local title = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Title") or "Spell Resources"
	local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
	print(string.format("|cff8b5cf6Joipov|r %s (|cff22d3eev%s|r). Type |cffffffff/rco|r to open settings.", title, version))
end

local function DB()
	return ns.db
end

--- Blizzard default font, or the host addon's configured UI font when that addon is loaded.
--- Cached; ApplySettings clears it.
local cachedFontPath, cachedFontFlags

local function ResolveFont()
	if cachedFontPath then
		return cachedFontPath, cachedFontFlags
	end
	if EllesmereUI and EllesmereUI.GetFontPath then
		local path = EllesmereUI.GetFontPath()
		if type(path) == "string" and path ~= "" then
			local flags = ""
			if EllesmereUI.GetFontOutlineFlag then
				flags = EllesmereUI.GetFontOutlineFlag() or ""
			end
			if flags == "" or flags == nil then
				flags = "OUTLINE"
			elseif not tostring(flags):find("OUTLINE", 1, true) then
				flags = tostring(flags) .. ",OUTLINE"
			end
			cachedFontPath, cachedFontFlags = path, flags
			return path, flags
		end
	end
	local path = (STANDARD_TEXT_FONT and STANDARD_TEXT_FONT ~= "" and STANDARD_TEXT_FONT) or FONT_PATH_FALLBACK
	cachedFontPath, cachedFontFlags = path, "OUTLINE"
	return path, "OUTLINE"
end

local function SecretBlocked(value)
	return issecretvalue and issecretvalue(value) and not (canaccessvalue and canaccessvalue(value))
end

local function CanIndex(value)
	if value == nil or SecretBlocked(value) then
		return false
	end
	if issecrettable and issecrettable(value) and not (canaccesstable and canaccesstable(value)) then
		return false
	end
	return true
end

local function ReadableNumber(value)
	if value == nil or SecretBlocked(value) or type(value) ~= "number" then
		return nil
	end
	return value
end

local function ReadableString(value)
	if type(value) ~= "string" or SecretBlocked(value) then
		return nil
	end
	return value
end

--- Spellbook name -> the rank the player has trained. Cooldown Manager icons
--- often store rank 1, and this map upgrades those. An action button keeps
--- the rank placed on it.
local knownByName = {}
local knownRanksReady = false

local function SpellSubtext(spellID)
	if not (C_Spell and C_Spell.GetSpellSubtext) then
		return nil
	end
	local sub = C_Spell.GetSpellSubtext(spellID)
	if type(sub) ~= "string" or sub == "" or SecretBlocked(sub) then
		return nil
	end
	return sub
end

--- "Rank 3" / "Rang 3" style subtext. Other subtext (Solar, Lunar) is identity.
local function RankNumber(spellID)
	local sub = SpellSubtext(spellID)
	if not sub or not sub:match("^%a+%s+%d+$") then
		return nil
	end
	return tonumber(sub:match("(%d+)"))
end

local function NonRankSubtext(spellID)
	local sub = SpellSubtext(spellID)
	if not sub or sub:match("^%a+%s+%d+$") then
		return nil
	end
	return sub
end

local function SameRankFamily(a, b)
	if not (C_Spell and C_Spell.GetSpellName) then
		return false
	end
	local nameA = C_Spell.GetSpellName(a)
	local nameB = C_Spell.GetSpellName(b)
	if type(nameA) ~= "string" or nameA == "" or SecretBlocked(nameA) then
		return false
	end
	if nameA ~= nameB then
		return false
	end
	local subA = NonRankSubtext(a)
	local subB = NonRankSubtext(b)
	if subA and subB and subA ~= subB then
		return false
	end
	return true
end

local function SpellKnown(known)
	return not SecretBlocked(known) and known and true or false
end

local function PlayerKnowsSpell(spellID)
	spellID = ReadableNumber(spellID)
	if not spellID then
		return false
	end
	if SpellKnown(C_SpellBook.IsSpellKnown(spellID)) then
		return true
	end
	return SpellKnown(IsPlayerSpell(spellID))
end

local function RebuildKnownRanks()
	wipe(knownByName)
	knownRanksReady = false
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then
		return
	end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	if not bank or not (C_Spell and C_Spell.GetSpellName) then
		return
	end
	local futureType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
	local lines = C_SpellBook.GetNumSpellBookSkillLines()
	if SecretBlocked(lines) or type(lines) ~= "number" or lines <= 0 then
		return
	end
	for index = 1, lines do
		local line = C_SpellBook.GetSpellBookSkillLineInfo(index)
		local offset = CanIndex(line) and ReadableNumber(line.itemIndexOffset)
		local count = offset and ReadableNumber(line.numSpellBookItems)
		if offset and count then
			local last = offset + count
			for slot = offset + 1, last do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
				local itemType = CanIndex(item) and item.itemType
				local isFuture = false
				if itemType ~= nil and not SecretBlocked(itemType) then
					isFuture = itemType == futureType or itemType == "FUTURESPELL"
				end
				if CanIndex(item) and not isFuture then
					local actionID = ReadableNumber(item.actionID)
					local castID = ReadableNumber(item.spellID)
					if actionID and actionID <= 0 then
						actionID = nil
					end
					if castID and castID <= 0 then
						castID = nil
					end
					local id = actionID or castID
					if actionID and castID and actionID ~= castID then
						local actionRank = RankNumber(actionID)
						local castRank = RankNumber(castID)
						if actionRank and castRank and castRank > actionRank then
							id = castID
						end
					end
					if id then
						local name = C_Spell.GetSpellName(id)
						if type(name) == "string" and name ~= "" and not SecretBlocked(name) then
							knownByName[name] = id
						end
					end
				end
			end
		end
	end
	knownRanksReady = true
end

local function EnsureKnownRanks()
	if not knownRanksReady then
		RebuildKnownRanks()
	end
end

function ns.InvalidateKnownRanks()
	knownRanksReady = false
end

--- Rank the player has trained, when `spellID` is an older rank of that spell.
local function CurrentRankSpellID(spellID)
	EnsureKnownRanks()
	if not (C_Spell and C_Spell.GetSpellName) then
		return nil
	end
	local name = C_Spell.GetSpellName(spellID)
	if type(name) ~= "string" or name == "" or SecretBlocked(name) then
		return nil
	end

	local function accept(id)
		id = ReadableNumber(id)
		if not id or id <= 0 or id == spellID or not SameRankFamily(spellID, id) then
			return nil
		end
		local passedRank = RankNumber(spellID)
		local nextRank = RankNumber(id)
		if passedRank and nextRank and nextRank > passedRank then
			return id
		end
		if not PlayerKnowsSpell(spellID) and PlayerKnowsSpell(id) then
			return id
		end
		return nil
	end

	local fromBook = accept(knownByName[name])
	if fromBook then
		return fromBook
	end
	if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
		local upgraded = accept(C_SpellBook.FindSpellOverrideByID(spellID))
		if upgraded then
			return upgraded
		end
	end
	if C_Spell.GetOverrideSpell then
		local upgraded = accept(C_Spell.GetOverrideSpell(spellID))
		if upgraded then
			return upgraded
		end
	end
	if C_Spell.GetSpellIDForSpellIdentifier then
		local upgraded = accept(C_Spell.GetSpellIDForSpellIdentifier(name))
		if upgraded then
			return upgraded
		end
	end

	-- Talent replacement can change the name. Only use it when the stored id
	-- is not the spell the player currently knows.
	if PlayerKnowsSpell(spellID) then
		return nil
	end
	local function knownUpgrade(id)
		id = ReadableNumber(id)
		if id and id > 0 and id ~= spellID and PlayerKnowsSpell(id) then
			return id
		end
		return nil
	end
	if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
		local upgraded = knownUpgrade(C_SpellBook.FindSpellOverrideByID(spellID))
		if upgraded then
			return upgraded
		end
	end
	if C_Spell.GetOverrideSpell then
		local upgraded = knownUpgrade(C_Spell.GetOverrideSpell(spellID))
		if upgraded then
			return upgraded
		end
	end
	return nil
end

local function ReadCostEntry(entry, allowPercent)
	if not CanIndex(entry) then
		return nil
	end
	local powerType = ReadableNumber(entry.type)
	if not powerType or not TRACKED_POWER[powerType] then
		return nil
	end

	local cost = ReadableNumber(entry.cost)
	local minCost = ReadableNumber(entry.minCost)
	-- Important: cost may be 0 while minCost is the real flat cost (0 is truthy in Lua).
	local amount = nil
	if cost and cost > 0 then
		amount = cost
	elseif minCost and minCost > 0 then
		amount = minCost
	end
	if not amount then
		return nil
	end

	local costPercent = ReadableNumber(entry.costPercent) or 0
	local costPerSec = ReadableNumber(entry.costPerSec) or 0
	-- A per-second cost has no single cast total. Icon text stays hidden for
	-- percent costs; tooltips can use the resolved amount.
	if costPerSec ~= 0 or (costPercent ~= 0 and not allowPercent) then
		return nil
	end

	return amount, powerType, costPercent ~= 0
end

local function DirectSpellCost(spellID, allowPercent)
	local getCosts = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
	if not getCosts then
		return nil
	end
	local costs = getCosts(spellID)
	if not CanIndex(costs) then
		return nil
	end
	-- Prefer an entry whose required aura is currently met; otherwise still
	-- use a flat cost so stance abilities (Shield Block, Disarm) show.
	local fallbackAmount, fallbackType, fallbackPercent
	for i = 1, #costs do
		local amount, powerType, isPercent = ReadCostEntry(costs[i], allowPercent)
		if amount then
			local entry = costs[i]
			local requiredAuraID = ReadableNumber(entry.requiredAuraID)
			if requiredAuraID and requiredAuraID > 0 and entry.hasRequiredAura == false then
				fallbackAmount = fallbackAmount or amount
				fallbackType = fallbackType or powerType
				if fallbackPercent == nil then
					fallbackPercent = isPercent
				end
			else
				return amount, powerType, isPercent
			end
		end
	end
	if fallbackAmount then
		return fallbackAmount, fallbackType, fallbackPercent
	end
	return nil
end

--- Base mana/power on the spell record. Forever puts this on GetSpellInfo.
--- GetSpellPowerCost is the cast cost, including talents. Use the base only
--- when that API hands back the trained rank for a lower rank id.
local function BaseSpellCost(spellID)
	if not (C_Spell and C_Spell.GetSpellInfo) then
		return nil
	end
	local info = C_Spell.GetSpellInfo(spellID)
	if not CanIndex(info) then
		return nil
	end
	local cost = ReadableNumber(info.cost)
	if not cost or cost <= 0 then
		return nil
	end
	local powerType = ReadableNumber(info.powerType)
	if powerType and not TRACKED_POWER[powerType] then
		return nil
	end
	return cost, powerType
end

--- Spellbook cast of the same name, when `spellID` itself has no flat cost
--- (buff-slot aura ids are often "known" and still have no mana cost).
local function SpellbookCastID(spellID)
	EnsureKnownRanks()
	if not (C_Spell and C_Spell.GetSpellName) then
		return nil
	end
	local name = C_Spell.GetSpellName(spellID)
	if type(name) ~= "string" or name == "" or SecretBlocked(name) then
		return nil
	end
	local known = ReadableNumber(knownByName[name])
	if not known or known <= 0 or known == spellID or not SameRankFamily(spellID, known) then
		return nil
	end
	return known
end

--- Cost of this spell id. No rank rewrite.
function ns.RawSpellResourceCost(spellID)
	spellID = ReadableNumber(spellID)
	if not spellID or spellID <= 0 then
		return nil
	end
	return DirectSpellCost(spellID)
end

--- Flat cost. `exact` keeps the spell on an action button, including a lower
--- rank. Cooldown Manager icons omit it: those viewers often store rank 1,
--- and that cheap cost must not replace the rank the player casts.
function ns.GetSpellResourceCost(spellID, exact)
	spellID = ReadableNumber(spellID)
	if not spellID or spellID <= 0 then
		return nil
	end

	if not exact then
		local current = CurrentRankSpellID(spellID)
		if current then
			return DirectSpellCost(current)
		end
	end

	local amount, powerType = DirectSpellCost(spellID)
	if exact then
		local current = CurrentRankSpellID(spellID)
		if current then
			local trainedAmount = DirectSpellCost(current)
			-- The client resolved every rank id to the trained spell.
			if amount and trainedAmount and amount == trainedAmount then
				local baseAmount, baseType = BaseSpellCost(spellID)
				if baseAmount and baseAmount ~= amount then
					return baseAmount, powerType or baseType
				end
			end
		end
	end
	if amount then
		return amount, powerType
	end
	if exact then
		return nil
	end
	local book = SpellbookCastID(spellID)
	if book then
		return DirectSpellCost(book)
	end
	return nil
end

--- Absolute cost of this spell id for a tooltip. Percent-of-base costs are
--- included once the client has resolved them. A flat cost is not upgraded
--- to the trained rank; if the client returns that rank for every id, the
--- spell record's base cost is used instead.
function ns.ResolvedSpellCost(spellID)
	spellID = ReadableNumber(spellID)
	if not spellID or spellID <= 0 then
		return nil
	end
	local amount, powerType, isPercent = DirectSpellCost(spellID, true)
	if not amount then
		return nil
	end
	if isPercent then
		return amount, powerType
	end
	local current = CurrentRankSpellID(spellID)
	if current then
		local trainedAmount = DirectSpellCost(current, true)
		if trainedAmount and amount == trainedAmount then
			local baseAmount, baseType = BaseSpellCost(spellID)
			if baseAmount and baseAmount ~= amount then
				return baseAmount, powerType or baseType
			end
		end
	end
	return amount, powerType
end

--- Full cost display only.
function ns.ComputeDisplay(spellID, exact)
	local db = DB()
	if not db or not db.enabled then
		return nil
	end

	local cost, powerType = ns.GetSpellResourceCost(spellID, exact)
	if not cost or not powerType then
		return nil
	end

	local percentKey = PERCENT_KEY[powerType]
	if percentKey and db[percentKey] then
		local maxPower = ReadableNumber(UnitPowerMax("player", powerType))
		if maxPower and maxPower > 0 then
			local pct = math.floor((cost / maxPower) * 100 + 0.5)
			return tostring(pct) .. "%", powerType
		end
	end

	return tostring(math.floor(cost + 0.5)), powerType
end

local function ApplyTextStyle(fs, powerType)
	local db = DB()
	if not db or not fs then
		return
	end

	local size = db.fontSize or 9
	local path, flags = ResolveFont()
	local fontKey = path .. ":" .. size .. ":" .. flags
	if fs.fontKey ~= fontKey then
		fs:SetFont(path, size, flags)
		fs.fontKey = fontKey
	end

	if db.tintByResource and powerType and POWER_TINT[powerType] then
		local c = POWER_TINT[powerType]
		fs:SetTextColor(c[1], c[2], c[3], 1)
	else
		fs:SetTextColor(db.colorR or 1, db.colorG or 1, db.colorB or 1, 1)
	end
end

local function LayoutOverlay(fs)
	local db = DB()
	if not fs or not db then
		return
	end
	local anchor = db.anchor or "BOTTOMLEFT"
	fs:ClearAllPoints()
	fs:SetPoint(anchor, fs:GetParent(), anchor, db.offsetX or 1, db.offsetY or 1)
end

function ns.EnsureOverlay(button)
	if not button then
		return nil
	end
	local fs = overlays[button]
	if fs then
		local holder = fs:GetParent()
		if holder and holder ~= button and holder.SetFrameLevel and button.GetFrameLevel then
			holder:SetFrameLevel((button:GetFrameLevel() or 0) + 30)
		end
		return fs
	end

	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints(button)
	holder:EnableMouse(false)
	if holder.EnableMouseMotion then
		holder:EnableMouseMotion(false)
	end
	holder:SetFrameLevel((button:GetFrameLevel() or 0) + 30)

	fs = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	fs:SetJustifyH("CENTER")
	fs:SetJustifyV("MIDDLE")
	fs:Hide()
	overlays[button] = fs
	LayoutOverlay(fs)
	ApplyTextStyle(fs, nil)
	return fs
end

function ns.HideOverlay(button)
	local fs = overlays[button]
	if fs then
		fs:SetText("")
		fs:Hide()
	end
end

function ns.ClearAllOverlays()
	for _, fs in pairs(overlays) do
		fs:SetText("")
		fs:Hide()
	end
end

function ns.CacheCooldownSpell(cooldownID, spellID)
	cooldownID = ReadableNumber(cooldownID)
	spellID = ReadableNumber(spellID)
	if cooldownID and spellID and spellID > 0 then
		cooldownSpellCache[cooldownID] = spellID
	end
end

function ns.GetCachedCooldownSpell(cooldownID)
	cooldownID = ReadableNumber(cooldownID)
	if not cooldownID then
		return nil
	end
	return cooldownSpellCache[cooldownID]
end

local function GetEcmeModule()
	if not EllesmereUI or not EllesmereUI._ModuleNS then
		return nil
	end
	return EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
end

local function AddSpellCandidate(list, seen, spellID)
	spellID = ReadableNumber(spellID)
	if spellID and spellID > 0 and not seen[spellID] then
		seen[spellID] = true
		list[#list + 1] = spellID
	end
end

local function AddSpellCandidateList(list, seen, spellIDs)
	if type(spellIDs) ~= "table" or not CanIndex(spellIDs) then
		return
	end
	for i = 1, #spellIDs do
		AddSpellCandidate(list, seen, spellIDs[i])
	end
end

local function AddCooldownInfoCandidates(list, seen, info)
	if not CanIndex(info) then
		return
	end
	AddSpellCandidate(list, seen, info.overrideSpellID)
	AddSpellCandidateList(list, seen, info.linkedSpellIDs)
	AddSpellCandidate(list, seen, info.spellID)
end

--- First id in list that has a flat tracked resource cost.
function ns.PickCostSpellID(spellIDs)
	if type(spellIDs) ~= "table" then
		return nil
	end
	for i = 1, #spellIDs do
		local spellID = ReadableNumber(spellIDs[i])
		if spellID and spellID > 0 and ns.GetSpellResourceCost(spellID) then
			return spellID
		end
	end
	return nil
end

local function ReadCooldownID(child, fc)
	local cdID = ReadableNumber(child.cooldownID)
	if not cdID and CanIndex(child.cooldownInfo) then
		cdID = ReadableNumber(child.cooldownInfo.cooldownID)
	end
	if not cdID and CanIndex(fc) then
		cdID = ReadableNumber(fc.cachedCdID)
	end
	return cdID
end

--- Spell bars already carry a cast id with a cost. Buff viewers often expose a
--- spec aura (no cost) or a secret id while the aura is up, so walk aura,
--- canonical, and linked ids and keep the first one that has a flat cost.
function ns.ResolveCdmSpellID(child)
	if not child then
		return nil
	end

	local list = {}
	local seen = {}
	local eui = GetEcmeModule()
	local fc
	if eui and eui._ecmeFC then
		fc = eui._ecmeFC[child]
	end

	-- Missing-buff placeholders belong to the host addon. Their live spell
	-- getters and cooldown links are secret or shared while any other aura is
	-- up. The icon's spell is the plain id stored on the frame.
	if child._isPlaceholderFrame then
		AddSpellCandidate(list, seen, child._phSpellID)
		if CanIndex(fc) then
			AddSpellCandidate(list, seen, fc.spellID)
		end
		return ns.PickCostSpellID(list)
	end

	if eui and type(eui.GetCanonicalSpellIDForFrame) == "function" then
		local ok, sid = pcall(eui.GetCanonicalSpellIDForFrame, child)
		if ok then
			AddSpellCandidate(list, seen, sid)
		end
	end

	if CanIndex(fc) then
		AddSpellCandidate(list, seen, fc.resolvedSid)
		AddSpellCandidate(list, seen, fc.spellID)
		AddSpellCandidate(list, seen, fc.baseSpellID)
		AddSpellCandidateList(list, seen, fc.linkedSpellIDs)
	end

	local cdID = ReadCooldownID(child, fc)
	if cdID and eui and type(eui._cdmCleanSidByCDID) == "table" then
		AddSpellCandidate(list, seen, eui._cdmCleanSidByCDID[cdID])
	end

	if type(child.GetAuraSpellID) == "function" then
		AddSpellCandidate(list, seen, child:GetAuraSpellID())
	end
	if type(child.GetSpellID) == "function" then
		AddSpellCandidate(list, seen, child:GetSpellID())
	end

	if cdID then
		AddSpellCandidate(list, seen, ns.GetCachedCooldownSpell(cdID))
		if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
			local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
			AddCooldownInfoCandidates(list, seen, info)
		end
	end
	AddCooldownInfoCandidates(list, seen, child.cooldownInfo)

	local picked = ns.PickCostSpellID(list)
	if picked and cdID then
		ns.CacheCooldownSpell(cdID, picked)
	end
	return picked
end

function ns.ResolveActionSpellID(button)
	if not button then
		return nil
	end

	local action
	if button.GetAttribute then
		action = ReadableNumber(button:GetAttribute("action"))
	end
	if not action or action <= 0 then
		action = ReadableNumber(button.action)
	end
	if not action or action <= 0 then
		return nil
	end

	local rawType, rawID = GetActionInfo(action)
	local actionType = ReadableString(rawType)
	local id = ReadableNumber(rawID)
	if not actionType or not id then
		return nil
	end

	if actionType == "spell" then
		return id
	end
	if actionType == "macro" then
		if GetMacroSpell then
			local sid = ReadableNumber(GetMacroSpell(id))
			if sid and sid > 0 then
				return sid
			end
		end
		-- Named macros sometimes only resolve through the action slot helper.
		if GetActionText then
			local name = GetActionText(action)
			if type(name) == "string" and name ~= "" and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
				local sid = ReadableNumber(C_Spell.GetSpellIDForSpellIdentifier(name))
				if sid and sid > 0 then
					return sid
				end
			end
		end
	end
	-- Some Forever slots report an unusual spell-like type. Never feed an item
	-- or macro id to GetSpellInfo: an unrelated spell could own that number.
	if actionType ~= "item" and actionType ~= "macro" and C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if CanIndex(info) then
			local sid = ReadableNumber(info.spellID) or id
			if sid and sid > 0 and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(sid) then
				-- Only accept if it actually has a resource cost candidate.
				if ns.GetSpellResourceCost(sid) then
					return sid
				end
			end
		end
	end
	return nil
end

function ns.UpdateButtonOverlay(button, spellID, exact)
	if not button then
		return
	end

	local db = DB()
	if not db or not db.enabled then
		ns.HideOverlay(button)
		return
	end

	if not spellID then
		ns.HideOverlay(button)
		return
	end

	local text, powerType = ns.ComputeDisplay(spellID, exact)
	if not text then
		ns.HideOverlay(button)
		return
	end

	local fs = ns.EnsureOverlay(button)
	if not fs then
		return
	end
	if layoutDirty then
		LayoutOverlay(fs)
	end
	ApplyTextStyle(fs, powerType)
	fs:SetText(text)
	fs:Show()
end

function ns.MarkLayoutDirty()
	layoutDirty = true
end

function ns.SetTrackedButtons(list)
	trackedButtons = list or {}
end

function ns.RefreshAll()
	local db = DB()
	if not db or not db.enabled then
		ns.ClearAllOverlays()
		return
	end

	if ns.CollectTargets then
		ns.CollectTargets()
	end

	ns.ClearAllOverlays()

	for i = 1, #trackedButtons do
		local entry = trackedButtons[i]
		local button = entry and entry.button
		if button then
			local spellID
			local exact = entry.kind ~= "cdm"
			if entry.kind == "cdm" then
				spellID = entry.spellID or ns.ResolveCdmSpellID(button)
			else
				-- Always re-resolve: page/bonus remaps change action without new collect cache.
				spellID = ns.ResolveActionSpellID(button)
			end
			ns.UpdateButtonOverlay(button, spellID, exact)
		end
	end

	layoutDirty = false
end

-- First delayed request arms one timer. Further requests before it fires do
-- nothing. An immediate refresh runs now and drops a timer that has not fired.
function ns.RequestRefresh(immediate)
	if immediate then
		refreshSerial = refreshSerial + 1
		refreshQueued = false
		ns.RefreshAll()
		return
	end
	if refreshQueued then
		return
	end
	refreshQueued = true
	local serial = refreshSerial
	local function Fire()
		if serial ~= refreshSerial or not refreshQueued then
			return
		end
		refreshQueued = false
		ns.RefreshAll()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(REFRESH_THROTTLE, Fire)
	else
		Fire()
	end
end

-- Delayed refresh for the noisy events (paging, spec, equipment, aura). They
-- coalesce into one refresh through RequestRefresh.
local function RefreshSoon()
	ns.MarkLayoutDirty()
	ns.RequestRefresh(false)
end

local function InvalidateAndRefresh()
	ns.InvalidateKnownRanks()
	RefreshSoon()
end

local function Prepare()
	ns.InvalidateKnownRanks()
	if ns.InitOptions then
		ns.InitOptions()
	end
	if ns.CreateMinimapButton then
		ns.CreateMinimapButton()
	end
	if ns.HookTargets then
		ns.HookTargets()
	end
	ns.RequestRefresh(true)
end

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON_NAME then
		return
	end
	ns.db = ns.LoadDB(_G.ResourceCostOverlayDB)
	_G.ResourceCostOverlayDB = ns.db
	driver:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
	ns.Welcome()
	Prepare()
end

function handlers.PLAYER_ENTERING_WORLD(isLogin)
	if isLogin then
		return
	end
	Prepare()
end

-- The host addon repaints missing-buff placeholders shortly after the aura event.
-- One shared delay, so a burst of auras arms a single refresh.
local auraQueued = false
local function QueueAuraRefresh()
	if auraQueued then
		return
	end
	auraQueued = true
	C_Timer.After(0.3, function()
		auraQueued = false
		ns.RequestRefresh(false)
	end)
end

function handlers.UNIT_AURA(unit)
	if unit and unit ~= "player" then
		return
	end
	QueueAuraRefresh()
end

function handlers.UNIT_MAXPOWER(unit)
	if unit and unit ~= "player" then
		return
	end
	RefreshSoon()
end

handlers.SPELLS_CHANGED = InvalidateAndRefresh
handlers.PLAYER_SPECIALIZATION_CHANGED = InvalidateAndRefresh
handlers.TRAIT_CONFIG_UPDATED = InvalidateAndRefresh
handlers.ACTIONBAR_SLOT_CHANGED = RefreshSoon
handlers.ACTIONBAR_PAGE_CHANGED = RefreshSoon
handlers.UPDATE_BONUS_ACTIONBAR = RefreshSoon
handlers.UPDATE_SHAPESHIFT_FORM = RefreshSoon
handlers.PLAYER_EQUIPMENT_CHANGED = RefreshSoon

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
driver:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
driver:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
if driver.RegisterUnitEvent then
	driver:RegisterUnitEvent("UNIT_AURA", "player")
	driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")
else
	driver:RegisterEvent("UNIT_AURA")
	driver:RegisterEvent("UNIT_MAXPOWER")
end
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("TRAIT_CONFIG_UPDATED")

driver:SetScript("OnEvent", function(_, event, arg1)
	local handler = handlers[event]
	if handler then
		handler(arg1)
	end
end)

function ns.SetEnabled(enabled)
	local db = DB()
	if not db then
		return
	end
	db.enabled = enabled and true or false
	ns.RequestRefresh(true)
end

function ns.ApplySettings()
	cachedFontPath, cachedFontFlags = nil, nil
	ns.MarkLayoutDirty()
	ns.RequestRefresh(true)
end
