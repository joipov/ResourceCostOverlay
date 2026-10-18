--[[
  Spell tooltip lines: output per resource point on the cost line, and
  healing or damage per second on the cast line.

  The number written on the tooltip is the rank being shown. A percent-of-base
  line falls back to the resolved power cost. English descriptions only.
]]

local _, ns = ...

local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local issecrettable = issecrettable
local canaccesstable = canaccesstable

local PLAYER_TOOLTIPS = {
	GameTooltip = true,
	ItemRefTooltip = true,
}

local POWER = Enum and Enum.PowerType or {}

local RESOURCES = {
	{ key = "mana", power = POWER.Mana or 0, name = "MANA", word = "mana", costGlobal = "MANA_COST" },
	{ key = "rage", power = POWER.Rage or 1, name = "RAGE", word = "rage", costGlobal = "RAGE_COST" },
	{ key = "focus", power = POWER.Focus or 2, name = "FOCUS", word = "focus", costGlobal = "FOCUS_COST" },
	{ key = "energy", power = POWER.Energy or 3, name = "ENERGY", word = "energy", costGlobal = "ENERGY_COST" },
}

local CACHE_SIZE = 200
local cache = {}
local cacheOrder = {}
local busy = false

-- Rage an auto attack generates. Warrior: weapon speed x 3.46/4.50. Bear: flat 11.
local SWING_RAGE_ONE_HAND, SWING_RAGE_TWO_HAND = 3.46, 4.50
local BEAR_SWING_RAGE = 11
local MAIN_HAND_SLOT = 16
local weaponCache = {}
local itemScanner

-- GameTooltip while a Shift-only part is waiting to redraw.
local shiftTooltip

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
	if type(value) ~= "number" or SecretBlocked(value) then
		return nil
	end
	return value
end

local function ReadableString(value)
	if type(value) ~= "string" or SecretBlocked(value) or value == "" then
		return nil
	end
	return value
end

local function EnglishLocale()
	local locale = GetLocale and GetLocale() or "enUS"
	return locale == "enUS" or locale == "enGB"
end

local function EscapePattern(text)
	return (text:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"))
end

local function PatternFromFormat(fmt)
	if type(fmt) ~= "string" then
		return nil
	end
	local lower = fmt:lower()
	local startAt, stopAt = lower:find("%%d")
	if not startAt then
		startAt, stopAt = lower:find("%%%.?%d*[fg]")
	end
	if not startAt then
		return nil
	end
	local prefix = EscapePattern(lower:sub(1, startAt - 1))
	local suffix = EscapePattern(lower:sub(stopAt + 1))
	return "^" .. prefix .. "([%d,%.]+)" .. suffix
end

for i = 1, #RESOURCES do
	local res = RESOURCES[i]
	local word = EscapePattern(res.word)
	res.patterns = {}
	local fromGlobal = PatternFromFormat(_G[res.costGlobal])
	if fromGlobal then
		res.patterns[#res.patterns + 1] = fromGlobal
	end
	res.patterns[#res.patterns + 1] = "^([%d,%.]+)%s*" .. word
	res.percentPattern = "^[%d%.]+%%.-" .. word
end

local function MatchCost(text)
	for i = 1, #RESOURCES do
		local res = RESOURCES[i]
		if text:find(res.percentPattern) then
			return res, nil
		end
	end
	for i = 1, #RESOURCES do
		local res = RESOURCES[i]
		for p = 1, #res.patterns do
			local num = text:match(res.patterns[p])
			if num then
				return res, tonumber((num:gsub(",", "")))
			end
		end
	end
	return nil
end

local function MatchCast(text)
	local seconds = text:match("^(%d+%.?%d*) sec cast%s*$")
	if not seconds then
		local pattern = PatternFromFormat(_G.SPELL_CAST_TIME_SEC)
		seconds = pattern and text:match(pattern)
	end
	if seconds then
		return "cast", tonumber(seconds)
	end
	local instant = _G.SPELL_CAST_TIME_INSTANT
	if text:find("^instant%s*$") or text:find("^instant cast%s*$")
		or (type(instant) == "string" and text == ns.NormalizeSpellText(instant)) then
		return "instant", 0
	end
	local channeled = _G.SPELL_CAST_CHANNELED
	if text:find("^channeled%s*$") or (type(channeled) == "string" and text == ns.NormalizeSpellText(channeled)) then
		return "channeled", nil
	end
	local nextMelee = _G.SPELL_ON_NEXT_SWING
	local nextRanged = _G.SPELL_ON_NEXT_RANGED
	if text:find("^next melee%s*$") or text:find("^next ranged%s*$")
		or (type(nextMelee) == "string" and text == ns.NormalizeSpellText(nextMelee))
		or (type(nextRanged) == "string" and text == ns.NormalizeSpellText(nextRanged)) then
		return "nextswing", nil
	end
	return nil
end

local function MatchCooldown(text)
	local seconds = text:match("^(%d+%.?%d*) sec cooldown")
	if not seconds then
		local pattern = PatternFromFormat(_G.SPELL_RECAST_TIME_SEC)
		seconds = pattern and text:match(pattern)
	end
	if seconds then
		return tonumber(seconds)
	end
	local minutes = text:match("^(%d+%.?%d*) min cooldown")
	if not minutes then
		local pattern = PatternFromFormat(_G.SPELL_RECAST_TIME_MIN)
		minutes = pattern and text:match(pattern)
	end
	if minutes then
		return tonumber(minutes) * 60
	end
	return nil
end

local function FontLine(tooltipName, side, index)
	local fontString = _G[tooltipName .. side .. index]
	if not fontString or not fontString.GetText then
		return nil
	end
	if fontString.IsShown and not fontString:IsShown() then
		return nil
	end
	local text = ReadableString(fontString:GetText())
	if not text then
		return nil
	end
	return text, fontString
end

local function ReadSpellTooltip(tooltip)
	local name = tooltip:GetName()
	local count = tooltip.NumLines and tooltip:NumLines()
	if type(count) ~= "number" or SecretBlocked(count) then
		return nil
	end
	local costLine, resource, cost, costText, cast, cooldown
	local lines = {}
	for i = 2, count do
		local text, fontString = FontLine(name, "TextLeft", i)
		if text then
			local lower = ns.NormalizeSpellText(text)
			if lower:find("^next rank") then
				break
			end
			local lineResource, lineCost, castKind, castSeconds, lineCooldown
			if i <= 8 and not costLine then
				lineResource, lineCost = MatchCost(lower)
			end
			if i <= 8 and not lineResource and not cast then
				castKind, castSeconds = MatchCast(lower)
			end
			if i <= 8 and not (lineResource or castKind) then
				lineCooldown = MatchCooldown(lower)
			end
			if i <= 8 then
				local rightText = FontLine(name, "TextRight", i)
				if rightText then
					cooldown = cooldown or MatchCooldown(ns.NormalizeSpellText(rightText))
				end
			end
			if lineResource then
				costLine, resource, cost, costText = fontString, lineResource, lineCost, text
			elseif castKind then
				cast = { line = fontString, text = text, kind = castKind, seconds = castSeconds }
			elseif lineCooldown then
				cooldown = cooldown or lineCooldown
			else
				lines[#lines + 1] = lower
			end
		end
	end
	if cast then
		cast.cooldown = cooldown
	end
	if not (costLine or cast) then
		return nil
	end
	return costLine, resource, cost, lines, cast, costText
end

local function CooldownSeconds(spellID)
	spellID = ReadableNumber(spellID)
	if not spellID then
		return nil
	end
	local ms
	if C_Spell and C_Spell.GetSpellBaseCooldown then
		local ok, value = pcall(C_Spell.GetSpellBaseCooldown, spellID)
		if ok then
			ms = value
		end
	end
	if ms == nil and GetSpellBaseCooldown then
		local ok, value = pcall(GetSpellBaseCooldown, spellID)
		if ok then
			ms = value
		end
	end
	ms = ReadableNumber(ms)
	if not ms or ms <= 0 then
		return nil
	end
	return ms / 1000
end

-- Main-hand base speed and two-handed flag from the item tooltip (before haste).
-- Returns weapon, or nil and true when the link or tooltip text is a combat secret.
local function ReadMainHand()
	local link = GetInventoryItemLink and GetInventoryItemLink("player", MAIN_HAND_SLOT)
	if SecretBlocked(link) then
		return nil, true
	end
	if not link then
		return nil
	end
	local weapon = weaponCache[link]
	if weapon == nil then
		itemScanner = itemScanner
			or CreateFrame("GameTooltip", "ResourceCostOverlayItemScanner", nil, "GameTooltipTemplate")
		itemScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
		itemScanner:SetInventoryItem("player", MAIN_HAND_SLOT)
		local speed, twoHand, secret = nil, false, false
		local count = itemScanner:NumLines()
		if SecretBlocked(count) then
			secret = true
			count = 0
		end
		for i = 1, count do
			local left = _G["ResourceCostOverlayItemScannerTextLeft" .. i]
			local right = _G["ResourceCostOverlayItemScannerTextRight" .. i]
			local leftText = left and left:GetText()
			local rightText = right and right:IsShown() and right:GetText()
			if SecretBlocked(leftText) or SecretBlocked(rightText) then
				secret = true
			else
				if leftText == "Two-Hand" then
					twoHand = true
				end
				if type(rightText) == "string" then
					speed = speed or tonumber(rightText:match("^Speed (%d+%.?%d*)"))
				end
			end
		end
		itemScanner:Hide()
		if secret then
			return nil, true
		end
		weapon = speed and { speed = speed, twoHand = twoHand } or false
		weaponCache[link] = weapon
	end
	return weapon or nil
end

local function CombatStats()
	local stats = { secret = {} }
	local ok = pcall(function()
		local _, class = UnitClass("player")
		if class == "WARRIOR" then
			local weaponOk, weapon, weaponSecret = pcall(ReadMainHand)
			if weaponOk and weapon then
				stats.swingSpeed = weapon.speed
				stats.twoHand = weapon.twoHand
				stats.swingRage = weapon.speed * (weapon.twoHand and SWING_RAGE_TWO_HAND or SWING_RAGE_ONE_HAND)
			elseif weaponOk and weaponSecret then
				stats.secret.swingRage = true
			end
		elseif class == "DRUID" then
			stats.swingRage = BEAR_SWING_RAGE
			stats.bearForm = true
		end
		if UnitDamage then
			local minDamage, maxDamage = UnitDamage("player")
			if SecretBlocked(minDamage) or SecretBlocked(maxDamage) then
				stats.secret.melee = true
			else
				minDamage = ReadableNumber(minDamage)
				maxDamage = ReadableNumber(maxDamage)
				if minDamage and maxDamage and maxDamage > 0 then
					stats.melee = (minDamage + maxDamage) / 2
				end
			end
		end
		if UnitRangedDamage then
			local _, minDamage, maxDamage = UnitRangedDamage("player")
			if SecretBlocked(minDamage) or SecretBlocked(maxDamage) then
				stats.secret.ranged = true
			else
				minDamage = ReadableNumber(minDamage)
				maxDamage = ReadableNumber(maxDamage)
				if minDamage and maxDamage and maxDamage > 0 then
					stats.ranged = (minDamage + maxDamage) / 2
				end
			end
		end
		if UnitAttackPower then
			local base, positive, negative = UnitAttackPower("player")
			if SecretBlocked(base) or SecretBlocked(positive) or SecretBlocked(negative) then
				stats.secret.ap = true
			else
				base = ReadableNumber(base)
				positive = ReadableNumber(positive) or 0
				negative = ReadableNumber(negative) or 0
				if base then
					stats.ap = base + positive + negative
				end
			end
		end
	end)
	if not ok then
		return { secret = {} }
	end
	return stats
end

local function CurrentComboPoints()
	if not UnitPower then
		return nil
	end
	local power = POWER.ComboPoints or 4
	local points = ReadableNumber(UnitPower("player", power))
	if points and points > 0 then
		return points
	end
	return nil
end

local function StatsKey(stats)
	local secret = stats.secret or {}
	return string.format(
		"%.1f|%.1f|%.1f|%.2f|%s%s%s%s",
		stats.melee or 0,
		stats.ranged or 0,
		stats.ap or 0,
		stats.swingRage or 0,
		secret.melee and "m" or "",
		secret.ranged and "r" or "",
		secret.ap and "a" or "",
		secret.swingRage and "s" or ""
	)
end

local function AppendNotes(notes, more)
	for i = 1, #(more or {}) do
		local note = more[i]
		local seen = false
		for j = 1, #notes do
			if notes[j] == note then
				seen = true
				break
			end
		end
		if not seen then
			notes[#notes + 1] = note
		end
	end
end

-- True if a tooltip part is on, and Shift is held when it is Shift-only.
-- ItemRefTooltip always shows Shift-only parts (Shift-click opens the link).
local function Shown(part, tooltip)
	local db = ns.db
	if not db or not db[part] then
		return false
	end
	local shiftOnly = db[part .. "ShiftOnly"]
	if not shiftOnly then
		return true
	end
	return IsShiftKeyDown() or tooltip ~= GameTooltip
end

local function AnyShiftOnly()
	local db = ns.db
	if not db then
		return false
	end
	return (db.showEfficiency and db.showEfficiencyShiftOnly)
		or (db.showThroughput and db.showThroughputShiftOnly)
		or (db.showNotes and db.showNotesShiftOnly)
end

local function RefreshForShift()
	if not (shiftTooltip and shiftTooltip:IsShown()) then
		return
	end
	local owner = shiftTooltip:GetOwner()
	local refresh = owner and (owner.UpdateTooltip or owner:GetScript("OnEnter"))
	if refresh then
		refresh(owner)
	end
end

local function Cached(key, build)
	local found = cache[key]
	if found ~= nil then
		return found
	end
	local value = build()
	if value == nil then
		value = false
	end
	if #cacheOrder >= CACHE_SIZE then
		cache[table.remove(cacheOrder, 1)] = nil
	end
	cacheOrder[#cacheOrder + 1] = key
	cache[key] = value
	return value
end

local function SuffixOrNil(value)
	if value == false or value == nil then
		return nil
	end
	return value
end

local function SpellIDFromTooltip(tooltip)
	if not tooltip.GetSpell then
		return nil
	end
	local ok, first, _, third = pcall(tooltip.GetSpell, tooltip)
	if not ok then
		return nil
	end
	return ReadableNumber(third) or ReadableNumber(first)
end

local function MacroSpell(slot)
	if not GetActionInfo or not slot then
		return false
	end
	local ok, actionType, id = pcall(GetActionInfo, slot)
	if not ok or actionType ~= "macro" then
		return false
	end
	return true, ns.ResolveMacroSpellID(ReadableNumber(id))
end

local function Process(tooltip, spellID)
	if busy or not tooltip or tooltip.rcoAnnotated then
		return
	end
	if tooltip.IsForbidden and tooltip:IsForbidden() then
		return
	end
	local frameName = tooltip.GetName and tooltip:GetName()
	if not frameName or not PLAYER_TOOLTIPS[frameName] then
		return
	end
	local db = ns.db
	if not db or not db.enabled or (not db.showEfficiency and not db.showThroughput) then
		return
	end

	spellID = ReadableNumber(spellID) or SpellIDFromTooltip(tooltip)
	local costLine, resource, cost, lines, cast, costText = ReadSpellTooltip(tooltip)
	if not lines then
		return
	end

	local title = FontLine(frameName, "TextLeft", 1)
	local titleSecret = false
	if not title then
		local titleLine = _G[frameName .. "TextLeft1"]
		local rawTitle = titleLine and titleLine:GetText()
		if SecretBlocked(rawTitle) then
			titleSecret = true
		end
	end
	ns.lastSpellTooltip = {
		name = title,
		id = spellID,
		lines = lines,
		cast = cast,
		cost = cost,
		resource = resource and resource.key or nil,
	}

	if resource and (not cost or cost <= 0) and ns.ResolvedSpellCost then
		local amount, powerType = ns.ResolvedSpellCost(spellID)
		if amount and amount > 0 and (powerType == nil or powerType == resource.power) then
			cost = amount
			ns.lastSpellTooltip.cost = cost
		end
	end
	if cast and not cast.cooldown then
		local cooldown = CooldownSeconds(spellID)
		if cooldown then
			cast.cooldown = cooldown
		end
	end

	local stats = CombatStats()
	local comboPoints = CurrentComboPoints()
	local showEfficiency = Shown("showEfficiency", tooltip)
	local showThroughput = Shown("showThroughput", tooltip)
	local castKey = ""
	if cast then
		castKey = cast.kind .. ":" .. tostring(cast.seconds) .. ":" .. tostring(cast.cooldown or 0)
	end
	local key = table.concat({
		showEfficiency and "1" or "0",
		showThroughput and "1" or "0",
		tostring(cost or 0),
		resource and resource.key or "",
		title or "",
		StatsKey(stats),
		tostring(comboPoints or 0),
		castKey,
		titleSecret and "s" or "",
		table.concat(lines, "|"),
	}, "\1")

	local suffixes = Cached(key, function()
		local ratio, rate, ratioNotes, rateNotes
		if showEfficiency and costLine and resource then
			if titleSecret then
				ratio, ratioNotes = ns.SECRET_SUFFIX, { ns.SECRET_NOTE }
			elseif cost and cost > 0 then
				ratio, ratioNotes = ns.FormatResourceSuffix(lines, cost, resource.key, title, stats, comboPoints)
			end
		end
		if showThroughput and cast then
			if titleSecret and cast.kind ~= "nextswing" then
				rate, rateNotes = ns.SECRET_SUFFIX, { ns.SECRET_NOTE }
			else
				rate, rateNotes = ns.FormatThroughputSuffix(lines, cast, resource and resource.key, title, stats, comboPoints)
			end
		end
		return {
			ratio = ratio or false,
			rate = rate or false,
			ratioNotes = ratioNotes or false,
			rateNotes = rateNotes or false,
		}
	end)

	local ratio = SuffixOrNil(suffixes.ratio)
	local rate = SuffixOrNil(suffixes.rate)
	local notes = {}
	AppendNotes(notes, SuffixOrNil(suffixes.ratioNotes))
	AppendNotes(notes, SuffixOrNil(suffixes.rateNotes))
	tooltip.rcoAnnotated = true
	local changed = false
	local keyLine
	if ratio and costLine and costText then
		costLine:SetText(costText .. ratio)
		keyLine = costLine
		changed = true
	end
	if rate and cast and cast.line and cast.text then
		cast.line:SetText(cast.text .. rate)
		keyLine = cast.line
		changed = true
	end
	if db.showNotes and #notes > 0 and keyLine then
		if Shown("showNotes", tooltip) then
			for i = 1, #notes do
				tooltip:AddLine(notes[i], 0.8, 0.8, 0.8, true)
			end
		else
			keyLine:SetText(keyLine:GetText() .. " |cff808080(Shift)|r")
		end
		changed = true
	end
	if tooltip == GameTooltip and AnyShiftOnly() then
		shiftTooltip = tooltip
	end
	if changed and tooltip:IsShown() then
		busy = true
		tooltip.rcoResizing = true
		tooltip:Show()
		tooltip.rcoResizing = false
		busy = false
	end
end

local function HookClear(tooltip)
	if not tooltip or tooltip.rcoClearHooked or not tooltip.HookScript then
		return
	end
	tooltip.rcoClearHooked = true
	tooltip:HookScript("OnTooltipCleared", function(self)
		if not self.rcoResizing then
			self.rcoAnnotated = nil
		end
		if self == shiftTooltip then
			shiftTooltip = nil
		end
	end)
end

local function Install()
	if not EnglishLocale() then
		return
	end
	HookClear(GameTooltip)
	HookClear(ItemRefTooltip)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
			local spellID = data and CanIndex(data) and data.id
			Process(tooltip, spellID)
		end)
	elseif GameTooltip and GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipSetSpell", function(self)
			Process(self)
		end)
		if ItemRefTooltip and ItemRefTooltip.HookScript then
			ItemRefTooltip:HookScript("OnTooltipSetSpell", function(self)
				Process(self)
			end)
		end
	end
	if hooksecurefunc and GameTooltip and GameTooltip.SetAction then
		hooksecurefunc(GameTooltip, "SetAction", function(self, slot)
			local isMacro, spellID = MacroSpell(slot)
			if isMacro then
				Process(self, spellID)
			end
		end)
	end
	local shiftFrame = CreateFrame("Frame")
	shiftFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
	shiftFrame:SetScript("OnEvent", function(_, _, key)
		if key == "LSHIFT" or key == "RSHIFT" then
			RefreshForShift()
		end
	end)
end

Install()
