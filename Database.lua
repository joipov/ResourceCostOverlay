local _, ns = ...

-- Saved variables: defaults, migrations, validation. Plain Lua, so the tests
-- can load it without a client.

local DB_VERSION = 10
local MINIMAP_POS = 245

local ANCHORS = {
	CENTER = true,
	TOP = true,
	BOTTOM = true,
	LEFT = true,
	RIGHT = true,
	TOPLEFT = true,
	TOPRIGHT = true,
	BOTTOMLEFT = true,
	BOTTOMRIGHT = true,
}

-- Scalars only. Tables are built fresh in EnsureTables.
local defaults = {
	enabled = true,
	showActionBars = false,
	showCdmSpellBars = true,
	showCdmBuffBars = true,
	percentMana = true,
	percentRage = false,
	percentEnergy = false,
	percentFocus = false,
	showMinimapButton = true,
	anchor = "BOTTOMLEFT",
	offsetX = 1,
	offsetY = 1,
	fontSize = 9,
	tintByResource = false,
	colorR = 1,
	colorG = 1,
	colorB = 1,
}

local function ClampNumber(value, lo, hi, fallback)
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	if value < lo then
		return lo
	end
	if value > hi then
		return hi
	end
	return value
end

local function EnsureTables(db)
	if type(db.minimapIcon) ~= "table" then
		db.minimapIcon = {}
	end
	db.minimapIcon.minimapPos = ClampNumber(db.minimapIcon.minimapPos, 0, 360, MINIMAP_POS)
end

local function CopyDefaults(db)
	for key, value in pairs(defaults) do
		if type(db[key]) ~= type(value) then
			db[key] = value
		end
	end
	EnsureTables(db)
end

local function Validate(db)
	if type(db.anchor) ~= "string" or not ANCHORS[db.anchor] then
		db.anchor = defaults.anchor
	end
	db.offsetX = math.floor(ClampNumber(db.offsetX, -40, 40, defaults.offsetX) + 0.5)
	db.offsetY = math.floor(ClampNumber(db.offsetY, -40, 40, defaults.offsetY) + 0.5)
	db.fontSize = math.floor(ClampNumber(db.fontSize, 6, 32, defaults.fontSize) + 0.5)
	db.colorR = ClampNumber(db.colorR, 0, 1, defaults.colorR)
	db.colorG = ClampNumber(db.colorG, 0, 1, defaults.colorG)
	db.colorB = ClampNumber(db.colorB, 0, 1, defaults.colorB)
end

local function MigrateDB(db)
	local version = type(db.version) == "number" and db.version or 0
	if version < 2 then
		db.fontSize = defaults.fontSize
	end
	if version < 3 then
		db.anchor = defaults.anchor
		db.offsetX = defaults.offsetX
		db.offsetY = defaults.offsetY
		if type(db.fontSize) ~= "number" then
			db.fontSize = defaults.fontSize
		end
	end
	if version < 4 then
		-- Deficit mode removed (Forever secrets block rage UnitPower math).
		db.displayMode = nil
	end
	if version < 5 then
		db.showAsPercent = false
	end
	if version < 6 then
		db.showMinimapButton = false
		db.minimapAngle = MINIMAP_POS
		if type(db.minimapIcon) ~= "table" then
			db.minimapIcon = {}
		end
	end
	if version < 7 then
		-- One CDM toggle used to cover spell bars only. Keep that choice, and
		-- turn buff bars on for anyone who had Cooldown Manager enabled.
		local cdmOn = db.showCooldownManager ~= false
		db.showCdmSpellBars = cdmOn
		db.showCdmBuffBars = cdmOn
		db.showCooldownManager = nil
	end
	if version < 8 then
		-- One percent toggle covered every resource. Mana stays a percent.
		-- Rage, energy, and focus show the raw cost.
		db.percentMana = true
		db.percentRage = false
		db.percentEnergy = false
		db.percentFocus = false
		db.showAsPercent = nil
	end
	if version < 9 then
		-- The button used to default off, and that false was saved. Turn it on
		-- once. 220 was the old shared default angle.
		db.showMinimapButton = true
		if db.minimapAngle == 220 then
			db.minimapAngle = MINIMAP_POS
		end
		if type(db.minimapIcon) == "table" and db.minimapIcon.minimapPos == 220 then
			db.minimapIcon.minimapPos = MINIMAP_POS
		end
	end
	if version < 10 then
		-- The built-in button kept its own angle. LibDBIcon's table holds it now.
		if type(db.minimapIcon) ~= "table" then
			db.minimapIcon = {}
		end
		if type(db.minimapIcon.minimapPos) ~= "number" and type(db.minimapAngle) == "number" then
			db.minimapIcon.minimapPos = db.minimapAngle % 360
		end
		db.minimapAngle = nil
	end
	db.version = DB_VERSION
end

function ns.LoadDB(saved)
	ns.firstRun = type(saved) ~= "table"
	local db = ns.firstRun and {} or saved
	MigrateDB(db)
	CopyDefaults(db)
	Validate(db)
	return db
end

ns.defaults = defaults
ns.DB_VERSION = DB_VERSION
