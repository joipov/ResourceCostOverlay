-- Unit tests for the pure parts of Spell Resources.
--   luajit tests/run.lua
--   lua5.1 tests/run.lua
-- Files that create frames (Core.lua, Targets.lua, Options.lua,
-- MinimapButton.lua, Tooltip.lua) are not loaded. Database.lua and
-- Efficiency.lua are plain Lua.

local root = (arg and arg[0] or "tests/run.lua"):match("^(.*)[/\\]tests[/\\]") or "."

local ns = {}
local function load(file)
	local chunk, err = loadfile(root .. "/" .. file)
	assert(chunk, err)
	chunk("ResourceCostOverlay", ns)
end

load("Database.lua")
load("Efficiency.lua")

local passed, failed = 0, 0

local function eq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

test("LoadDB fills defaults", function()
	local db = ns.LoadDB(nil)
	eq(db.enabled, true, "enabled")
	eq(db.showActionBars, false, "showActionBars")
	eq(db.showCdmSpellBars, true, "showCdmSpellBars")
	eq(db.showCdmBuffBars, true, "showCdmBuffBars")
	eq(db.percentMana, true, "percentMana")
	eq(db.percentRage, false, "percentRage")
	eq(db.showMinimapButton, true, "showMinimapButton")
	eq(db.anchor, "BOTTOMLEFT", "anchor")
	eq(db.fontSize, 9, "fontSize")
	eq(db.showEfficiency, true, "showEfficiency")
	eq(db.showThroughput, true, "showThroughput")
	eq(db.version, ns.DB_VERSION, "version")
end)

test("LoadDB rejects an unknown anchor", function()
	eq(ns.LoadDB({ version = ns.DB_VERSION, anchor = "MIDDLE" }).anchor, "BOTTOMLEFT")
	eq(ns.LoadDB({ version = ns.DB_VERSION, anchor = "TOP" }).anchor, "TOP")
end)

test("LoadDB clamps offsets and font size", function()
	local db = ns.LoadDB({ version = ns.DB_VERSION, offsetX = 100, offsetY = -100, fontSize = 100 })
	eq(db.offsetX, 40, "offsetX")
	eq(db.offsetY, -40, "offsetY")
	eq(db.fontSize, 32, "fontSize")
end)

test("LoadDB migrates the old single percent toggle", function()
	local db = ns.LoadDB({ version = 7, showAsPercent = true })
	eq(db.percentMana, true, "percentMana")
	eq(db.percentRage, false, "percentRage")
	eq(db.showAsPercent, nil, "showAsPercent")
end)

test("LoadDB splits the old Cooldown Manager toggle", function()
	local db = ns.LoadDB({ version = 6, showCooldownManager = false })
	eq(db.showCdmSpellBars, false, "spell bars")
	eq(db.showCdmBuffBars, false, "buff bars")
	eq(db.showCooldownManager, nil, "old key")
end)

local function near(actual, expected, label)
	if type(actual) ~= "number" or math.abs(actual - expected) > 0.02 then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function ratioKind(ratios, kind)
	for i = 1, #ratios do
		if ratios[i].kind == kind then
			return ratios[i]
		end
	end
	return nil
end

test("a direct heal reports heal per mana and healing per second", function()
	local lines = { "Heals a friendly target for 2000 to 2200." }
	local cast = { kind = "cast", seconds = 2.5 }
	local ratios = ns.ResourceRatios(lines, 700, "Greater Heal", nil, nil)
	local heal = ratioKind(ratios, "heal")
	near(heal.ratio, 3, "heal/mana")
	local rates = ns.ThroughputRates(lines, cast, "Greater Heal", nil, "mana", nil)
	near(rates.hps, 840, "hps")
	eq(rates.dps, nil, "no dps")
	local suffix = ns.FormatResourceSuffix(lines, 700, "mana", "Greater Heal", nil, nil)
	eq(type(suffix) == "string" and suffix:find("3.00 heal/mana", 1, true) ~= nil, true, "suffix")
	local rate = ns.FormatThroughputSuffix(lines, cast, "mana", "Greater Heal", nil, nil)
	eq(type(rate) == "string" and rate:find("840 hps", 1, true) ~= nil, true, "hps suffix")
end)

test("a direct damage cast reports damage per mana and damage per second", function()
	local lines = { "Causes 100 to 120 Frost damage to the target." }
	local cast = { kind = "cast", seconds = 2 }
	local ratios = ns.ResourceRatios(lines, 50, "Frostbolt", nil, nil)
	near(ratioKind(ratios, "damage").ratio, 2.2, "dmg/mana")
	local rates = ns.ThroughputRates(lines, cast, "Frostbolt", nil, "mana", nil)
	near(rates.dps, 55, "dps")
end)

test("a heal over time is the full heal, paced by its duration", function()
	local lines = { "Heals the target for 45 every 3 sec for 15 sec." }
	local cast = { kind = "instant", seconds = 0 }
	local ratios = ns.ResourceRatios(lines, 100, "Renew", nil, nil)
	near(ratioKind(ratios, "heal").ratio, 2.25, "heal/mana")
	local rates = ns.ThroughputRates(lines, cast, "Renew", nil, "mana", nil)
	near(rates.hps, 15, "hps")
end)

test("impact damage plus damage over time refreshes instead of stacking", function()
	local lines = { "Burns all enemies in the area for 120 damage and an additional 80 damage over 8 sec." }
	local cast = { kind = "cast", seconds = 3 }
	local ratios = ns.ResourceRatios(lines, 300, "Flamestrike", nil, nil)
	local damage = ratioKind(ratios, "damage")
	near(damage.ratio, 200 / 300, "dmg/mana")
	eq(damage.aoe, true, "per target")
	local rates = ns.ThroughputRates(lines, cast, "Flamestrike", nil, "mana", nil)
	near(rates.dps, 50, "dps")
	eq(rates.dpsAoe, true, "dps per target")
	local suffix = ns.FormatResourceSuffix(lines, 300, "mana", "Flamestrike", nil, nil)
	eq(type(suffix) == "string" and suffix:find("per target", 1, true) ~= nil, true, "label")
end)

test("a next swing counts only its bonus", function()
	local lines = { "A strong attack that increases melee damage by 157." }
	local stats = { melee = 500 }
	local ratios = ns.ResourceRatios(lines, 15, "Heroic Strike", stats, nil)
	near(ratioKind(ratios, "damage").ratio, 157 / 15, "bonus")
	local rates = ns.ThroughputRates(lines, { kind = "nextswing" }, "Heroic Strike", stats, "rage", nil)
	eq(rates, nil, "no rate")
end)

test("cleave's next swing does not add the whole weapon hit", function()
	local lines = { "Inflicts 100% weapon damage plus 5 to an enemy and its nearest ally." }
	local stats = { melee = 100 }
	local ratios = ns.ResourceRatios(lines, 20, "Cleave", stats, nil)
	local damage = ratioKind(ratios, "damage")
	near(damage.ratio, 5 / 20, "bonus only")
	eq(damage.aoe, true, "per target")
end)

test("an absorb shield includes mana spent while it holds", function()
	local lines = { "Absorbs 200 damage, draining 2 mana per damage absorbed." }
	local ratios = ns.ResourceRatios(lines, 100, "Mana Shield", nil, nil)
	near(ratioKind(ratios, "absorb").ratio, 200 / 500, "absorb/mana")
end)

test("a finisher uses current combo points, or the highest line", function()
	local lines = { "1 point: 10 damage", "5 points: 50 damage" }
	local atMax = ns.ResourceRatios(lines, 35, "Eviscerate", nil, nil)
	local maxRatio = ratioKind(atMax, "damage")
	near(maxRatio.ratio, 50 / 35, "max")
	eq(maxRatio.comboPoints, 5, "5 CP")
	local atOne = ns.ResourceRatios(lines, 35, "Eviscerate", nil, 1)
	near(ratioKind(atOne, "damage").ratio, 10 / 35, "1 CP")
	eq(ns.ThroughputRates(lines, { kind = "instant", seconds = 0 }, "Eviscerate", nil, "energy", nil), nil, "no rate")
end)

test("an area spell is labeled per target", function()
	local lines = { "Causes 100 Fire damage to all enemies in the area." }
	local ratios = ns.ResourceRatios(lines, 25, "Arcane Explosion", nil, nil)
	eq(ratioKind(ratios, "damage").aoe, true, "aoe")
end)

test("yards and other units are not throughput", function()
	local onlyYards = ns.ResourceRatios({ "The spell reaches 30 yards." }, 10, "Far Sight", nil, nil)
	eq(#onlyYards, 0, "no ratio")
	local lines = { "Heals a friendly target within 40 yards for 500." }
	local ratios = ns.ResourceRatios(lines, 100, "Flash Heal", nil, nil)
	near(ratioKind(ratios, "heal").ratio, 5, "heal")
end)

test("a channel uses its length", function()
	local lines = { "Heals the target for 900 over 3 sec." }
	local rates = ns.ThroughputRates(lines, { kind = "channeled" }, "Penance", nil, "mana", nil)
	near(rates.hps, 300, "hps")
end)

test("an instant uses the global cooldown, and energy is faster", function()
	local lines = { "Deals 300 damage." }
	local cast = { kind = "instant", seconds = 0 }
	near(ns.ThroughputRates(lines, cast, "Strike", nil, "mana", nil).dps, 200, "mana gcd")
	near(ns.ThroughputRates(lines, cast, "Strike", nil, "energy", nil).dps, 300, "energy gcd")
end)

test("a cooldown suppresses the per second rate", function()
	local lines = { "Deals 300 damage." }
	local cast = { kind = "instant", seconds = 0, cooldown = 8 }
	eq(ns.ThroughputRates(lines, cast, "Strike", nil, "focus", nil), nil, "no rate")
	near(ratioKind(ns.ResourceRatios(lines, 40, "Strike", nil, nil), "damage").ratio, 7.5, "still a ratio")
end)

test("LoadDB turns the minimap button on and moves it off the 220 angle", function()
	local db = ns.LoadDB({ version = 8, showMinimapButton = false, minimapAngle = 220 })
	eq(db.showMinimapButton, true, "showMinimapButton")
	eq(db.minimapIcon.minimapPos, 245, "minimapPos")
	eq(db.minimapAngle, nil, "old key")
end)

if failed > 0 then
	print(string.format("%d passed, %d failed", passed, failed))
	os.exit(1)
end
print(string.format("%d passed", passed))
