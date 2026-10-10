local _, ns = ...

local DB_VERSION = 7

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

local defaults = {
	enabled = true,
	showActionBars = false,
	showCdmSpellBars = true,
	showCdmBuffBars = true,
	showAsPercent = false,
	showMinimapButton = false,
	minimapAngle = 220,
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
	if type(value) ~= "number" then
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

local function CopyDefaults(db)
	for key, value in pairs(defaults) do
		if type(db[key]) ~= type(value) then
			db[key] = value
		end
	end
	return db
end

local function Validate(db)
	db.enabled = db.enabled ~= false
	db.showActionBars = db.showActionBars == true
	db.showCdmSpellBars = db.showCdmSpellBars ~= false
	db.showCdmBuffBars = db.showCdmBuffBars ~= false
	db.showCooldownManager = nil
	db.showAsPercent = db.showAsPercent == true
	db.showMinimapButton = db.showMinimapButton == true
	db.minimapAngle = ClampNumber(db.minimapAngle, -360, 360, defaults.minimapAngle)
	if type(db.minimapIcon) ~= "table" then
		db.minimapIcon = {}
	end
	if type(db.anchor) ~= "string" or not ANCHORS[db.anchor] then
		db.anchor = defaults.anchor
	end
	db.offsetX = ClampNumber(db.offsetX, -40, 40, defaults.offsetX)
	db.offsetY = ClampNumber(db.offsetY, -40, 40, defaults.offsetY)
	db.offsetX = math.floor(db.offsetX + 0.5)
	db.offsetY = math.floor(db.offsetY + 0.5)
	db.fontSize = ClampNumber(db.fontSize, 6, 32, defaults.fontSize)
	db.fontSize = math.floor(db.fontSize + 0.5)
	db.tintByResource = db.tintByResource == true
	db.colorR = ClampNumber(db.colorR, 0, 1, defaults.colorR)
	db.colorG = ClampNumber(db.colorG, 0, 1, defaults.colorG)
	db.colorB = ClampNumber(db.colorB, 0, 1, defaults.colorB)
	-- Drop removed setting.
	db.displayMode = nil
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
		db.minimapAngle = defaults.minimapAngle
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
	db.version = DB_VERSION
	return version
end

function ns.LoadDB(saved)
	local db = type(saved) == "table" and saved or {}
	MigrateDB(db)
	CopyDefaults(db)
	Validate(db)
	return db
end

ns.DB_DEFAULTS = defaults
ns.DB_VERSION = DB_VERSION
ns.defaults = defaults
ns.ANCHORS = ANCHORS
