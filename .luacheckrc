-- Lua 5.1, explicit WoW globals. Same layout in every Joipov addon.
std = "lua51"
max_line_length = false
self = false

exclude_files = {
	".release/",
	".annotations/",
	"assets/",
}

files["tests/"] = {
	std = "lua51",
}

globals = {
	"ResourceCostOverlayDB",
	"ResourceCostOverlay_OnAddonCompartmentClick",
	"ResourceCostOverlay_OnAddonCompartmentEnter",
	"ResourceCostOverlay_OnAddonCompartmentLeave",
	"SLASH_RCO1",
	"SLASH_RCO2",
	SlashCmdList = { fields = { "RCO" } },
}

read_globals = {
	"issecretvalue",
	"canaccessvalue",
	"issecrettable",
	"canaccesstable",

	"C_AddOns",
	"C_Spell",
	"C_SpellBook",
	"C_Timer",
	"Enum",

	"CreateFrame",
	"C_CooldownViewer",
	"EllesmereUI",
	"GetActionInfo",
	"GetActionText",
	"GetCursorPosition",
	"GetMacroSpell",
	"GetMouseFoci",
	"GetSpellPowerCost",
	"GameTooltip",
	"hooksecurefunc",
	"IsPlayerSpell",
	"Minimap",
	"MinimalSliderWithSteppersMixin",
	"Settings",
	"SettingsPanel",
	"CreateSettingsListSectionHeaderInitializer",
	"CreateSettingsButtonInitializer",
	"ColorPickerFrame",
	"STANDARD_TEXT_FONT",
	"UIParent",
	"UnitPowerMax",
	"wipe",
}
