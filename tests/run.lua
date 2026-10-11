-- Unit tests for the pure parts of Resource Cost on Icons.
--   luajit tests/run.lua
--   lua5.1 tests/run.lua
-- Files that create frames (Core.lua, Targets.lua, Options.lua,
-- MinimapButton.lua) are not loaded. Database.lua is plain Lua.

local root = (arg and arg[0] or "tests/run.lua"):match("^(.*)[/\\]tests[/\\]") or "."

local ns = {}
local function load(file)
	local chunk, err = loadfile(root .. "/" .. file)
	assert(chunk, err)
	chunk("ResourceCostOverlay", ns)
end

load("Database.lua")

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
