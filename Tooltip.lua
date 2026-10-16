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

local function CombatStats()
	local stats = {}
	local ok = pcall(function()
		if UnitDamage then
			local minDamage, maxDamage = UnitDamage("player")
			minDamage = ReadableNumber(minDamage)
			maxDamage = ReadableNumber(maxDamage)
			if minDamage and maxDamage and maxDamage > 0 then
				stats.melee = (minDamage + maxDamage) / 2
			end
		end
		if UnitRangedDamage then
			local _, minDamage, maxDamage = UnitRangedDamage("player")
			minDamage = ReadableNumber(minDamage)
			maxDamage = ReadableNumber(maxDamage)
			if minDamage and maxDamage and maxDamage > 0 then
				stats.ranged = (minDamage + maxDamage) / 2
			end
		end
		if UnitAttackPower then
			local base, positive, negative = UnitAttackPower("player")
			base = ReadableNumber(base)
			positive = ReadableNumber(positive) or 0
			negative = ReadableNumber(negative) or 0
			if base then
				stats.ap = base + positive + negative
			end
		end
	end)
	if not ok then
		return {}
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
	return string.format("%.1f|%.1f|%.1f", stats.melee or 0, stats.ranged or 0, stats.ap or 0)
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
	local ok, actionType, id, subType = pcall(GetActionInfo, slot)
	if not ok or actionType ~= "macro" then
		return false
	end
	id = ReadableNumber(id)
	if subType == "spell" and id then
		return true, id
	end
	if GetMacroSpell and id then
		local spellOk, first, _, third = pcall(GetMacroSpell, id)
		if not spellOk then
			return true, nil
		end
		return true, ReadableNumber(first) or ReadableNumber(third)
	end
	return true, nil
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
	local castKey = ""
	if cast then
		castKey = cast.kind .. ":" .. tostring(cast.seconds) .. ":" .. tostring(cast.cooldown or 0)
	end
	local key = table.concat({
		db.showEfficiency and "1" or "0",
		db.showThroughput and "1" or "0",
		tostring(cost or 0),
		resource and resource.key or "",
		title or "",
		StatsKey(stats),
		tostring(comboPoints or 0),
		castKey,
		table.concat(lines, "|"),
	}, "\1")

	local suffixes = Cached(key, function()
		local ratio, rate
		if db.showEfficiency and cost and cost > 0 and resource then
			ratio = ns.FormatResourceSuffix(lines, cost, resource.key, title, stats, comboPoints)
		end
		if db.showThroughput and cast then
			rate = ns.FormatThroughputSuffix(lines, cast, resource and resource.key, title, stats, comboPoints)
		end
		return { ratio = ratio or false, rate = rate or false }
	end)

	local ratio = SuffixOrNil(suffixes.ratio)
	local rate = SuffixOrNil(suffixes.rate)
	tooltip.rcoAnnotated = true
	local changed = false
	if ratio and costLine and costText then
		costLine:SetText(costText .. ratio)
		changed = true
	end
	if rate and cast and cast.line and cast.text then
		cast.line:SetText(cast.text .. rate)
		changed = true
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
end

Install()
