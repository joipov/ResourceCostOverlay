--[[
  Spell power and attack power coefficients from English tooltip text.

  No spell-ID table: Forever does not expose coefficients to addons. Shares
  follow Classic cast/DoT rules as Forever uses them (no sub-20 penalty, no
  DoT cap). Formula estimates are marked ~. Attack power shares written in
  the description ("X% of your attack power") are exact.
]]

local _, ns = ...

local SCHOOLS = {
	holy = 2,
	fire = 3,
	nature = 4,
	frost = 5,
	shadow = 6,
	arcane = 7,
}

local SCHOOL_NAMES = {
	[2] = "holy",
	[3] = "fire",
	[4] = "nature",
	[5] = "frost",
	[6] = "shadow",
	[7] = "arcane",
}

local UNIT_AFTER = {
	"^%%",
	"^%.%d",
	"^%s*sec",
	"^%s*min",
	"^%s*hour",
	"^%s*yd",
	"^%s*yards?",
	"^%s*ft",
	"^%s*times?",
	"^%s*targets?",
	"^%s*charges?",
	"^%s*stacks?",
}

local ACCENT = "ff6fc3ff"
local SEPARATOR = " \194\183 "

local function ToNum(text)
	return tonumber((text:gsub("[,%.]$", "")))
end

local function IsAmount(text, start, stop)
	local before = text:sub(start - 1, start - 1)
	if before:match("[%a%.]") then
		return false
	end
	local after = text:sub(stop + 1)
	for i = 1, #UNIT_AFTER do
		if after:match(UNIT_AFTER[i]) then
			return false
		end
	end
	return true
end

-- Duration after an amount, and tick count when the amount is per tick.
local function OverTime(after)
	local seconds = after:match("^[^%d%.]-over (%d+%.?%d*) sec")
	if seconds then
		return ToNum(seconds)
	end
	seconds = after:match("^[^%d%.]-each second for (%d+%.?%d*) sec")
	if seconds then
		local duration = ToNum(seconds)
		return duration, duration
	end
	local every, rest = after:match("^[^%d%.]-every (%d+%.?%d*) sec%a*(.*)$")
	if every then
		seconds = rest:match("^ for (%d+%.?%d*) sec") or rest:match("lasts (%d+%.?%d*) sec")
		if seconds then
			local duration = ToNum(seconds)
			local interval = ToNum(every)
			if interval and interval > 0 then
				return duration, duration / interval
			end
			return duration
		end
	end
end

-- First direct amount and first over-time amount from description lines.
function ns.ReadCoefficientAmounts(lines)
	local text = ns.NormalizeSpellText(table.concat(lines or {}, " "))
	local direct, periodic
	local pos = 1
	while not (direct and periodic) do
		local startAt, stopAt = text:find("%d+", pos)
		if not startAt then
			break
		end
		local low = tonumber(text:sub(startAt, stopAt))
		local high = low
		local _, rangeStop, highText = text:find("^ to (%d+)", stopAt + 1)
		if rangeStop then
			high = tonumber(highText)
			stopAt = rangeStop
		end
		pos = stopAt + 1
		if low and IsAmount(text, startAt, stopAt) then
			local amount = { low = low, high = high or low }
			local seconds, ticks = OverTime(text:sub(stopAt + 1))
			if seconds then
				if not periodic then
					amount.duration = seconds
					amount.ticks = ticks
					periodic = amount
				end
			elseif not direct then
				direct = amount
			end
		end
	end
	return direct, periodic
end

-- Cast seconds used by the coefficient rules (Instant = 1.5, capped at 3.5).
-- Channeled spells use the DoT/channel duration as the cast time for the rules.
function ns.CoefficientCastSeconds(cast, periodic)
	if not cast then
		return nil
	end
	if cast.kind == "instant" then
		return 1.5
	end
	if cast.kind == "channeled" then
		local duration = periodic and periodic.duration
		if not duration then
			return nil
		end
		return math.min(3.5, math.max(1.5, duration))
	end
	if cast.kind == "cast" and type(cast.seconds) == "number" then
		return math.min(3.5, math.max(1.5, cast.seconds))
	end
	return nil
end

-- Direct and periodic shares (0–1+). Forever: no sub-20 penalty, no DoT cap.
function ns.EstimateCoefficientShares(cast, direct, periodic)
	local castSeconds = ns.CoefficientCastSeconds(cast, periodic)
	local directShare, periodicShare
	if direct and periodic then
		if castSeconds and periodic.duration and periodic.duration > 0 then
			local castPart = castSeconds / 3.5
			local timePart = periodic.duration / 15
			local total = castPart + timePart
			if total > 0 then
				directShare = castPart * castPart / total
				periodicShare = timePart * timePart / total
			end
		end
	else
		if direct and castSeconds then
			directShare = castSeconds / 3.5
		end
		if periodic and periodic.duration and periodic.duration > 0 then
			periodicShare = periodic.duration / 15
		end
	end
	return directShare, periodicShare
end

local function DetectSchoolAndHealing(text)
	for word in text:gmatch("(%a+) damage") do
		local school = SCHOOLS[word]
		if school then
			return school, false
		end
	end
	-- Heals / healed / healing; not health. Absorbs use healing power.
	local healing = text:find("heal[^t]") ~= nil or text:find("absorb", 1, true) ~= nil
	return nil, healing
end

local function FormatRange(low, high)
	if low == high then
		return tostring(low)
	end
	return low .. " to " .. high
end

local function FormatShare(share, estimate)
	local prefix = estimate and "~" or ""
	return string.format("|c%s%s%.1f%%|r", ACCENT, prefix, share * 100)
end

local function PlayerSpellPower(stats, school, healing)
	stats = stats or {}
	local secret = stats.secret or {}
	if healing then
		if secret.spellHealing then
			return nil, true
		end
		return stats.spellHealing, false
	end
	if secret.spellDamage then
		return nil, true
	end
	local bySchool = stats.spellDamage
	if type(bySchool) == "table" and school then
		return bySchool[school], false
	end
	return nil, false
end

local function AddPowerRow(rows, label, amount, share, power, estimate)
	if not (amount and share) then
		return
	end
	local ticks = amount.ticks or 1
	local right = FormatShare(share, estimate)
	if power then
		local bonus = math.floor(power * share / ticks + 1e-6)
		local baseLow = math.max(0, amount.low - bonus)
		local baseHigh = math.max(0, amount.high - bonus)
		right = right
			.. SEPARATOR
			.. FormatRange(baseLow, baseHigh)
			.. " + |c"
			.. ACCENT
			.. bonus
			.. "|r"
			.. (amount.ticks and " each" or "")
	end
	rows[#rows + 1] = {
		text = label .. " " .. right,
		share = share,
		estimate = estimate and true or false,
		kind = "spell",
	}
end

local function AttackPowerRows(text, stats, rows, notes)
	local percent = text:match("(%d+%.?%d*)%% of your attack power")
	if not percent then
		return
	end
	local share = ToNum(percent) / 100
	if not share or share <= 0 then
		return
	end
	local secret = stats and stats.secret and stats.secret.ap
	local right = FormatShare(share, false)
	if secret then
		rows[#rows + 1] = {
			text = "Attack Power " .. right .. ns.SECRET_SUFFIX,
			share = share,
			estimate = false,
			kind = "attack",
		}
		notes[#notes + 1] = ns.SECRET_NOTE
		return
	end
	local ap = stats and stats.ap
	if ap then
		local bonus = math.floor(ap * share + 1e-6)
		right = right .. SEPARATOR .. "+" .. bonus
	end
	rows[#rows + 1] = {
		text = "Attack Power " .. right,
		share = share,
		estimate = false,
		kind = "attack",
	}
end

--- lines: normalized description lines. cast: { kind, seconds }. stats: spell
--- damage by school, spellHealing, ap, secret flags.
--- Returns { rows, notes, secret } or nil when nothing applies.
function ns.SpellCoefficients(lines, cast, _spellName, stats)
	if type(lines) ~= "table" or #lines == 0 then
		return nil
	end
	local text = ns.NormalizeSpellText(table.concat(lines, " "))
	local rows = {}
	local notes = {}

	AttackPowerRows(text, stats, rows, notes)

	local school, healing = DetectSchoolAndHealing(text)
	if school or healing then
		local direct, periodic = ns.ReadCoefficientAmounts(lines)
		if direct or periodic then
			local directShare, periodicShare = ns.EstimateCoefficientShares(cast, direct, periodic)
			local power, powerSecret = PlayerSpellPower(stats, school, healing)
			if powerSecret then
				notes[#notes + 1] = ns.SECRET_NOTE
			end
			local label = healing and "Healing Power" or "Spell Power"
			AddPowerRow(rows, label, direct, directShare, power, true)
			AddPowerRow(rows, label .. " over time", periodic, periodicShare, power, true)
			if powerSecret then
				for i = 1, #rows do
					if rows[i].kind == "spell" and not rows[i].text:find(ns.SECRET_ICON, 1, true) then
						rows[i].text = rows[i].text .. ns.SECRET_SUFFIX
					end
				end
			end
		end
	end

	if #rows == 0 then
		return nil
	end
	return {
		rows = rows,
		notes = notes,
		secret = #notes > 0,
	}
end

ns.COEFFICIENT_SCHOOLS = SCHOOL_NAMES
