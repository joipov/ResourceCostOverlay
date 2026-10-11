-- Lua 5.1, explicit WoW globals. Modeled on GatherSkillTooltip / BigWigs.
std = "lua51"
max_line_length = false
self = false

exclude_files = {
	".release/",
	".annotations/",
	"assets/",
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
	"GetMouseFocus",
	"GetMouseFoci",
	"GetSpellPowerCost",
	"GetTime",
	"GameTooltip",
	"hooksecurefunc",
	"IsPlayerSpell",
	"IsSpellKnown",
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
