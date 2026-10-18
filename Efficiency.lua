--[[
  Spell throughput from an English tooltip description.

  The cost line and the cast line are read by Tooltip.lua. This file turns
  the description into damage, healing, and absorb, then into output per
  resource point and into healing or damage per second.
]]

local _, ns = ...

local ORDER = { "damage", "heal", "absorb" }
local LABELS = { damage = "dmg", heal = "heal", absorb = "absorb" }
local COLORS = { damage = "ffff9040", heal = "ff40c86a", absorb = "ff80c8ff" }

-- A number followed by one of these is a distance, a time, or a count.
local UNIT_WORDS = {
	"yd", "yard", "sec", "second", "min", "hour", "ms", "target", "enem", "member",
	"time", "charge", "stack", "combo", "point", "level", "health", "mana", "rage",
	"energy", "focus", "feet", "foot", "party", "raid", "group", "ally", "allies",
}

local AOE_PHRASES = {
	"enemies", "targets", "party members", "group members", "raid members", "allies",
	"target area", "area of effect", "in an area", "in the area", "in a cone",
	"nearby", "nearest ally",
}

-- Spare resource turned into damage is not the cast's own output.
local CONVERSION_PHRASES = {
	"each mana", "per mana", "each extra point", "extra rage", "extra energy",
	"extra focus", "additional rage", "additional energy", "additional focus",
}

-- Summons that say "repeatedly attacks" without a swing speed.
local SHOT_INTERVALS = {
	["searing totem"] = 2.4,
}

-- Reads like a full weapon strike, but only the next melee swing is empowered.
local NEXT_SWING_NAMES = {
	["cleave"] = true,
}

local WORD_NUMBERS = {
	two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
}

local function ToNum(text)
	return tonumber((text:gsub("[,%.]$", "")))
end

function ns.NormalizeSpellText(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("(%d),(%d%d%d)", "%1%2"):gsub("(%d),(%d%d%d)", "%1%2")
	return text:lower()
end

-- Name-keyed tables (SHOT_INTERVALS, NEXT_SWING_NAMES) share one entry per spell
-- across ranks, so "Cleave (Rank 3)" looks up "cleave".
function ns.SpellKey(name)
	if type(name) ~= "string" then
		return nil
	end
	local key = ns.NormalizeSpellText(name)
	key = key:gsub("%s*%(rank %d+%)%s*$", ""):gsub("%s+rank %d+%s*$", "")
	return key
end

-- Shown when a number cannot be calculated because a combat secret blocked it.
ns.SECRET_ICON = "|TInterface\\CharacterFrame\\UI-StateIcon:18:18:0:0:64:64:32:64:0:31|t"
ns.SECRET_SUFFIX = "  (" .. ns.SECRET_ICON .. ")"
ns.SECRET_NOTE = "Something this needs is hidden during combat, so it shows again after combat."

local function IsUnitWord(word)
	if word:sub(1, 1) == "%" then
		return true
	end
	for i = 1, #UNIT_WORDS do
		local unit = UNIT_WORDS[i]
		if word:sub(1, #unit) == unit then
			return true
		end
	end
	return false
end

local function HasPhrase(text, phrases)
	for i = 1, #phrases do
		if text:find(phrases[i], 1, true) then
			return true
		end
	end
	return false
end

-- First amount in a clause. "31 to 45" and "31-45" average. Returns the
-- amount and the text after it.
local function FindAmount(clause)
	local pos = 1
	while true do
		local startAt, stopAt, num = clause:find("(%d+%.?%d*)", pos)
		if not startAt then
			return nil
		end
		local value = ToNum(num)
		local rest = clause:sub(stopAt + 1)
		local rangeEnd, rangeNum = rest:match("^%s+to%s+(%d+%.?%d*)()")
		if not rangeEnd then
			rangeEnd, rangeNum = rest:match("^%s*%-%s*(%d+%.?%d*)()")
		end
		if rangeNum then
			value = (value + ToNum(rangeEnd)) / 2
			rest = rest:sub(rangeNum)
		end
		local word = rest:match("^%s*(%S*)") or ""
		local before = clause:sub(1, startAt - 1)
		local modifies = before:find("%f[%a]by%s*$") or before:find("%f[%a]by%s+up%s+to%s*$")
		if value and not modifies and not IsUnitWord(word) and not before:find("level%s*$") and not before:find("rank%s*$") then
			return value, rest
		end
		-- Skip the whole range ("31 to 45"), not only the first number.
		if rangeNum then
			pos = stopAt + rangeNum
		else
			pos = stopAt + 1
		end
	end
end

local function ParseDuration(text, prefix)
	local seconds = text:match(prefix .. "%s+(%d+%.?%d*)%s*sec")
	if seconds then
		return ToNum(seconds)
	end
	local minutes = text:match(prefix .. "%s+(%d+%.?%d*)%s*min")
	if minutes then
		return ToNum(minutes) * 60
	end
	return nil
end

-- Per-tick text becomes a total. "26 every 1 sec for 3 sec" is three ticks.
-- Returns multiplier, unknownTick, duration.
local function TickMultiplier(clause, rest, lasts, shotInterval)
	if rest:find("over%s+%d") then
		return 1, false, ParseDuration(rest, "over")
	end
	local interval = rest:match("every%s+(%d+%.?%d*)%s*sec")
	interval = interval and ToNum(interval)
	if not interval and (rest:find("every%s+sec") or rest:find("each%s+sec") or rest:find("per%s+sec")) then
		interval = 1
	end
	if not interval and clause:find("repeatedly", 1, true) then
		if not shotInterval then
			return 1, true
		end
		interval = shotInterval
	end
	if not interval or interval <= 0 then
		return 1, false
	end
	local duration = ParseDuration(rest, "for") or ParseDuration(clause, "for") or lasts
	if not duration then
		return 1, true
	end
	return math.max(1, math.floor(duration / interval + 0.5)), false, duration
end

local function IsConversion(clause)
	return HasPhrase(clause, CONVERSION_PHRASES)
end

-- false stops the clause from inheriting a previous kind. nil inherits.
local function ClauseKind(clause)
	if clause:find("yourself", 1, true) or clause:find("himself", 1, true) or clause:find("herself", 1, true) or clause:find("itself", 1, true) then
		return false
	end
	if clause:find("increas") or clause:find("reduc") or clause:find("decreas") then
		return false
	end
	if IsConversion(clause) then
		return false
	end
	if clause:find("absorb", 1, true) then
		return "absorb"
	end
	if clause:gsub("health", ""):find("heal", 1, true) then
		return "heal"
	end
	if clause:find("damage", 1, true) then
		return "damage"
	end
	return nil
end

local function ParseCharges(text)
	local suffixes = { "charges?", "times" }
	local expended = text:match("expends one ([%a%s]-)[%.,;]") or text:match("consumes one ([%a%s]-)[%.,;]")
	local noun = expended and expended:match("(%a+)%s*$")
	if noun then
		table.insert(suffixes, 1, noun:gsub("s$", "") .. "s?")
	end
	for s = 1, #suffixes do
		local pos = 1
		while true do
			local startAt, stopAt, count = text:find("(%w+)%s+" .. suffixes[s], pos)
			if not startAt then
				break
			end
			local stackLimit = text:sub(1, startAt - 1):find("stacks?%s+up%s+to%s*$")
			local charges = tonumber(count) or WORD_NUMBERS[count]
			if charges and charges > 1 and not stackLimit then
				return charges
			end
			pos = stopAt + 1
		end
	end
	return 1
end

local function IsAoE(sentence)
	return HasPhrase(sentence, AOE_PHRASES)
end

-- Mana spent per point absorbed, such as "draining 2 mana per damage absorbed".
local function ParseAbsorbDrain(text)
	if not text:find("absorb", 1, true) then
		return nil
	end
	local mana, damage = text:match("(%d+%.?%d*) mana per (%d+%.?%d*) [%a%s]-damage")
	if mana and damage then
		local damageNum = ToNum(damage)
		if damageNum and damageNum > 0 then
			return ToNum(mana) / damageNum
		end
	end
	mana = text:match("(%d+%.?%d*) mana per") or text:match("(%d+%.?%d*) mana for each")
		or text:match("drain%a* (%d+%.?%d*) mana") or text:match("cost%a* (%d+%.?%d*) mana")
	return mana and ToNum(mana) or nil
end

-- Weapon strikes use the player's current weapon damage. A next-swing
-- ability only adds its bonus, because the swing would land anyway.
-- Returns isWeapon, amount (nil when the needed stat cannot be read),
-- isNextSwing, and the stat an instant strike used ("melee", "ranged", "ap").
local function WeaponAmount(clause, stats, nextSwing)
	local apPercent = clause:match("(%d+%.?%d*)%% of your attack power")
	if apPercent then
		if not stats.ap then
			return true, nil, false, "ap"
		end
		return true, stats.ap * ToNum(apPercent) / 100, false, "ap"
	end
	local percent = clause:match("(%d+%.?%d*)%% weapon damage")
		or clause:match("(%d+%.?%d*)%% normal damage")
		or clause:match("(%d+%.?%d*)%% damage plus")
	local bonus = clause:match("weapon damage plus (%d+%.?%d*)")
		or clause:match("normal damage plus (%d+%.?%d*)")
		or clause:match("%% damage plus (%d+%.?%d*)")
		or clause:match("(%d+%.?%d*) damage in addition to")
		or clause:match("(%d+%.?%d*) additional damage")
		or clause:match("ranged damage by (%d+%.?%d*)")
	local swingBonus = clause:match("melee damage by (%d+%.?%d*)") or clause:match("next attack by (%d+%.?%d*)")
	if swingBonus then
		return true, ToNum(swingBonus), true
	end
	if not (percent or bonus or clause:find("weapon damage", 1, true) or clause:find("normal damage", 1, true)) then
		return false
	end
	if nextSwing then
		return true, bonus and ToNum(bonus) or nil, true
	end
	local source = clause:find("ranged", 1, true) and "ranged" or "melee"
	local weapon = stats[source]
	local bonusNum = bonus and ToNum(bonus) or 0
	if not weapon then
		return true, bonus and bonusNum or nil, false, source
	end
	local scale = percent and ToNum(percent) / 100 or 1
	return true, weapon * scale + bonusNum, false, source
end

local function SelectComboLines(lines, comboPoints)
	local listed = {}
	local maxPoints = 0
	for i = 1, #lines do
		local points = tonumber(lines[i]:match("^%s*(%d+)%s+points?%s*:") or "")
		if points and points > 0 then
			listed[points] = true
			if points > maxPoints then
				maxPoints = points
			end
		end
	end
	if maxPoints == 0 then
		return lines, nil
	end
	local chosen = maxPoints
	if comboPoints and comboPoints > 0 then
		if listed[comboPoints] then
			chosen = comboPoints
		else
			local best = nil
			for points in pairs(listed) do
				if points <= comboPoints and (not best or points > best) then
					best = points
				end
			end
			chosen = best or maxPoints
		end
	end
	local kept = {}
	for i = 1, #lines do
		local points, rest = lines[i]:match("^%s*(%d+)%s+points?%s*:%s*(.*)")
		if not points then
			kept[#kept + 1] = lines[i]
		elseif tonumber(points) == chosen then
			kept[#kept + 1] = rest
		end
	end
	return kept, chosen
end

local function IsOverTime(clause)
	return clause:find("over%s+%d") or clause:find("every") or clause:find("each%s+sec")
		or clause:find("per%s+sec") or clause:find("repeatedly", 1, true)
end

--- lines: description text. spellName: tooltip title. stats: melee, ranged, ap,
--- swingRage, secret. comboPoints: current combo points, or nil for highest line.
function ns.AnalyzeSpellLines(lines, spellName, stats, comboPoints)
	local totals, perTick, aoe, direct, directAoe, dots, dotUnknown = {}, {}, {}, {}, {}, {}, {}
	local result = {
		totals = totals,
		perTick = perTick,
		aoe = aoe,
		direct = direct,
		directAoe = directAoe,
		dots = dots,
		dotUnknown = dotUnknown,
	}
	stats = stats or {}
	spellName = ns.SpellKey(spellName)
	local split = {}
	for i = 1, #lines do
		local line = ns.NormalizeSpellText(lines[i])
		for part in line:gmatch("[^\n]+") do
			split[#split + 1] = part
		end
	end
	local chosenPoints
	split, chosenPoints = SelectComboLines(split, comboPoints)
	local fullText = table.concat(split, " ")
	result.comboPoints = chosenPoints
	if fullText:find("imbue", 1, true) or fullText:find("only one seal", 1, true) or fullText:find("each melee attack", 1, true) then
		return result
	end
	local lasts = ParseDuration(fullText, "lasts")
	result.absorbDrain = ParseAbsorbDrain(fullText)
	result.duration = ParseDuration(fullText, "over") or ParseDuration(fullText, "for") or lasts
	local charges = ParseCharges(fullText)
	local shotInterval = spellName and SHOT_INTERVALS[spellName]
	local nextSwingSpell = spellName and NEXT_SWING_NAMES[spellName]
	for i = 1, #split do
		local sentences = split[i]:gsub("%.%s+", "\1")
		for sentence in sentences:gmatch("[^\1]+") do
			local kind
			local sentenceIsAoE = IsAoE(sentence)
			local clauses = sentence:gsub("%s+and%s+", "\2"):gsub(";", "\2")
			local function add(value, mult, tick, overTime, duration)
				totals[kind] = (totals[kind] or 0) + value * mult * charges
				perTick[kind] = perTick[kind] or tick
				aoe[kind] = aoe[kind] or sentenceIsAoE
				if charges > 1 then
					return
				end
				if overTime or tick or mult > 1 then
					if duration and duration > 0 and not tick then
						dots[kind] = dots[kind] or {}
						dots[kind][#dots[kind] + 1] = {
							total = value * mult,
							duration = duration,
							aoe = sentenceIsAoE,
						}
					else
						dotUnknown[kind] = true
					end
				else
					direct[kind] = (direct[kind] or 0) + value
					directAoe[kind] = directAoe[kind] or sentenceIsAoE
				end
			end
			for clause in clauses:gmatch("[^\2]+") do
				if IsConversion(clause) then
					result.conversion = true
				end
				local isWeapon, weaponDamage, isNextSwing, source = WeaponAmount(clause, stats, nextSwingSpell)
				local clauseKind = ClauseKind(clause)
				if isWeapon and not IsConversion(clause) then
					kind = "damage"
					result.nextSwing = result.nextSwing or isNextSwing
					result.weaponSource = result.weaponSource or source
					if not weaponDamage and source and stats.secret and stats.secret[source] then
						result.secret = true
					end
					if weaponDamage and weaponDamage > 0 then
						add(weaponDamage, 1, false, false)
					end
				elseif clauseKind == false then
					kind = nil
				else
					kind = clauseKind or kind
					if kind then
						local value, rest = FindAmount(clause)
						if value and value > 0 then
							local mult, tick, duration = TickMultiplier(clause, rest, lasts, shotInterval)
							add(value, mult, tick, IsOverTime(clause), duration)
						end
					end
				end
			end
		end
	end
	return result
end

local function FormatRate(value)
	if value >= 10 then
		local text = string.format("%.1f", value)
		return (text:gsub("%.0$", ""))
	end
	return string.format("%.2f", value)
end

local function AppendNote(notes, note)
	for i = 1, #notes do
		if notes[i] == note then
			return
		end
	end
	notes[#notes + 1] = note
end

-- resourceKey: "mana", "rage", "energy", or "focus". Used for forgone rage on
-- next-swing abilities. Returns a list of ratios with .notes and optional .secret.
function ns.ResourceRatios(lines, cost, spellName, stats, comboPoints, resourceKey)
	local ratios = {}
	local notes = {}
	ratios.notes = notes
	if not cost or cost <= 0 then
		return ratios
	end
	stats = stats or {}
	local analysis = ns.AnalyzeSpellLines(lines, spellName, stats, comboPoints)
	local secret = stats.secret or {}
	if analysis.secret or (analysis.nextSwing and resourceKey == "rage" and secret.swingRage) then
		ratios.secret = true
		notes[1] = ns.SECRET_NOTE
		return ratios
	end
	-- An empowered swing generates no rage, so the rage it would have given counts as cost too.
	local forgoneRage = analysis.nextSwing and resourceKey == "rage" and stats.swingRage
	for i = 1, #ORDER do
		local kind = ORDER[i]
		local total = analysis.totals[kind]
		if total and total > 0 then
			local totalCost = cost
			if kind == "absorb" and analysis.absorbDrain then
				totalCost = cost + total * analysis.absorbDrain
			elseif kind == "damage" and forgoneRage then
				totalCost = cost + forgoneRage
			end
			if totalCost > 0 then
				ratios[#ratios + 1] = {
					kind = kind,
					ratio = total / totalCost,
					perTick = analysis.perTick[kind],
					aoe = analysis.aoe[kind],
					comboPoints = analysis.comboPoints,
				}
			end
		end
	end
	if #ratios == 0 then
		return ratios
	end
	if analysis.nextSwing then
		AppendNote(notes, "Only the bonus damage counts, because the swing would have hit anyway.")
	end
	if forgoneRage and stats.bearForm then
		AppendNote(notes, string.format(
			"The empowered swing generates no rage, so the %g rage a Bear Form swing gives counts as cost too: %d + %g rage.",
			forgoneRage,
			cost,
			forgoneRage
		))
	elseif forgoneRage then
		AppendNote(notes, string.format(
			"The empowered swing generates no rage, so the %.1f rage it would have given (%.2f speed, %s) counts as cost too: %d + %.1f rage.",
			forgoneRage,
			stats.swingSpeed,
			stats.twoHand and "two-handed" or "one-handed",
			cost,
			forgoneRage
		))
	end
	if analysis.weaponSource == "ap" and stats.ap then
		AppendNote(notes, string.format("Uses your current attack power (%d).", stats.ap))
	elseif analysis.weaponSource and stats[analysis.weaponSource] then
		AppendNote(notes, string.format(
			"Uses your current %s weapon damage (%d average).",
			analysis.weaponSource == "ranged" and "ranged" or "main-hand",
			stats[analysis.weaponSource]
		))
	end
	if analysis.absorbDrain and analysis.totals.absorb then
		AppendNote(notes, string.format("Counts the %g mana drained per point absorbed as cost too.", analysis.absorbDrain))
	end
	if analysis.conversion then
		AppendNote(notes, "Extra damage from spending more than the cost isn't counted.")
	end
	return ratios
end

local function GlobalCooldown(resourceKey)
	if resourceKey == "energy" then
		return 1
	end
	return 1.5
end

-- Refresh-rate model: impact / cast time, plus each DoT at total / max(duration, cast).
local function RateFor(analysis, kind, seconds)
	if analysis.dotUnknown[kind] then
		return nil
	end
	local perSecond = (analysis.direct[kind] or 0) / seconds
	local isAoE = analysis.directAoe[kind]
	local list = analysis.dots[kind]
	if list then
		for i = 1, #list do
			local dot = list[i]
			perSecond = perSecond + dot.total / math.max(dot.duration, seconds)
			isAoE = isAoE or dot.aoe
		end
	end
	if perSecond <= 0 then
		return nil
	end
	return perSecond, isAoE
end

-- When most of the damage is over time, DPS is the DoT alone over cast + duration
-- (Immolate-style). Otherwise the refresh-rate model above is used.
local DOT_DPS_SHARE = 0.45

local function DamagePerSecond(analysis, castTime, gcd, notes)
	if analysis.dotUnknown.damage then
		return nil
	end
	local direct = analysis.direct.damage or 0
	local dots = analysis.dots.damage or {}
	local dotTotal = 0
	for i = 1, #dots do
		dotTotal = dotTotal + dots[i].total
	end
	if dotTotal + direct <= 0 then
		return nil
	end
	local dps, isAoE = 0, false
	if dotTotal / (dotTotal + direct) > DOT_DPS_SHARE then
		for i = 1, #dots do
			local dot = dots[i]
			dps = dps + dot.total / (castTime + dot.duration)
			isAoE = isAoE or dot.aoe
		end
		if direct > 0 then
			AppendNote(notes, "Most of the damage is over time, so DPS is that effect alone: its total over the cast "
				.. "time plus its duration. The initial damage isn't counted.")
		elseif castTime > 0 then
			AppendNote(notes, "DPS is the damage over time effect's total over the cast time plus its duration.")
		end
		return dps, isAoE
	end
	local seconds = math.max(castTime, gcd)
	dps, isAoE = RateFor(analysis, "damage", seconds)
	if #dots > 0 then
		AppendNote(notes, "DPS counts damage over time at the rate it ticks while you keep recasting, because "
			.. "recasting refreshes it rather than stacking it.")
	end
	return dps, isAoE
end

--- cast: kind ("cast", "instant", "channeled", "nextswing"), seconds, cooldown.
--- A per-second rate assumes the spell is cast again as soon as it can be.
function ns.ThroughputRates(lines, cast, spellName, stats, resourceKey, comboPoints)
	if not cast or cast.kind == "nextswing" or (cast.cooldown and cast.cooldown > 0) then
		return nil
	end
	local analysis = ns.AnalyzeSpellLines(lines, spellName, stats, comboPoints)
	if analysis.comboPoints then
		return nil
	end
	local notes = {}
	if analysis.secret then
		return { secret = true, notes = { ns.SECRET_NOTE } }
	end
	local gcd = GlobalCooldown(resourceKey)
	local rates = { notes = notes }
	if cast.kind == "channeled" then
		local seconds = analysis.duration
		if not seconds or seconds <= 0 then
			return nil
		end
		local time = math.max(seconds, gcd)
		if not analysis.perTick.damage and analysis.totals.damage and analysis.totals.damage > 0 then
			rates.dps = analysis.totals.damage / time
			rates.dpsAoe = analysis.aoe.damage
		end
		if not analysis.perTick.heal and analysis.totals.heal and analysis.totals.heal > 0 then
			rates.hps = analysis.totals.heal / time
			rates.hpsAoe = analysis.aoe.heal
		end
	else
		local castTime = cast.seconds or 0
		rates.dps, rates.dpsAoe = DamagePerSecond(analysis, castTime, gcd, notes)
		local healSeconds = math.max(castTime, gcd)
		rates.hps, rates.hpsAoe = RateFor(analysis, "heal", healSeconds)
	end
	if not rates.dps and not rates.hps then
		return nil
	end
	return rates
end

local function RatioSuffix(ratios, resourceKey)
	local parts = {}
	for i = 1, #ratios do
		local ratio = ratios[i]
		local extra = ""
		if ratio.comboPoints then
			extra = extra .. string.format(" at %d CP", ratio.comboPoints)
		end
		if ratio.perTick then
			extra = extra .. " per tick"
		end
		if ratio.aoe then
			extra = extra .. " per target"
		end
		parts[#parts + 1] = string.format(
			"|c%s%s %s/%s%s|r",
			COLORS[ratio.kind],
			FormatRate(ratio.ratio),
			LABELS[ratio.kind],
			resourceKey,
			extra
		)
	end
	if #parts == 0 then
		return nil
	end
	return "  (" .. table.concat(parts, ", ") .. ")"
end

local function RateSuffix(rates)
	if not rates then
		return nil
	end
	local parts = {}
	if rates.dps then
		parts[#parts + 1] = string.format(
			"|c%s%s dps%s|r",
			COLORS.damage,
			FormatRate(rates.dps),
			rates.dpsAoe and " per target" or ""
		)
	end
	if rates.hps then
		parts[#parts + 1] = string.format(
			"|c%s%s hps%s|r",
			COLORS.heal,
			FormatRate(rates.hps),
			rates.hpsAoe and " per target" or ""
		)
	end
	if #parts == 0 then
		return nil
	end
	return "  (" .. table.concat(parts, ", ") .. ")"
end

-- Returns suffix, notes. suffix is SECRET_SUFFIX when combat secrets block the math.
function ns.FormatResourceSuffix(lines, cost, resourceKey, spellName, stats, comboPoints)
	local ratios = ns.ResourceRatios(lines, cost, spellName, stats, comboPoints, resourceKey)
	if ratios.secret then
		return ns.SECRET_SUFFIX, ratios.notes
	end
	return RatioSuffix(ratios, resourceKey), ratios.notes
end

-- Returns suffix, notes. suffix is SECRET_SUFFIX when combat secrets block the math.
function ns.FormatThroughputSuffix(lines, cast, resourceKey, spellName, stats, comboPoints)
	local rates = ns.ThroughputRates(lines, cast, spellName, stats, resourceKey, comboPoints)
	if not rates then
		return nil, nil
	end
	if rates.secret then
		return ns.SECRET_SUFFIX, rates.notes
	end
	return RateSuffix(rates), rates.notes
end
