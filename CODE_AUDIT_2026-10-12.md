# Spell Resources audit

Target: World of Warcraft Forever, `## Interface: 16001`, Lua 5.1.
References: Ketho's vscode-wow-api annotations, the Forever API, and the other Joipov addons.

This note is for development. It is not shipped in the addon zip.

## Current shape (through 1.4.3)

- Folder and SavedVariables stay `ResourceCostOverlay` / `ResourceCostOverlayDB`. The player-facing title is Spell Resources. Slash is `/rco`.
- Cost text on Cooldown Manager spell bars and buff bars by default. Action bars are optional.
- An action button keeps the rank on the button, including a macro's first `/cast` with `(Rank N)`. Cooldown Manager icons use the trained rank.
- Macro resolution: Classic `GetMacroSpell` (numeric first or third return), then body/`#showtooltip`/`/cast` via `SpellText.lua`, then the macro name on the button, then the action tooltip as a last resort. Custom bars that store a spell id in `.action` still use the slot from the button name so `GetActionInfo` sees the macro.
- Lower ranks that return nothing from `GetSpellPowerCost` fall back to that rank's tooltip cost. Costs that report both a percent and a resolved amount are kept.
- Spell tooltips: damage/healing/absorb per resource point, HPS/DPS for re-castable spells, next-swing forgone rage, DoT-heavy DPS share, and Shift-gated calculation notes.
- Mana defaults to a percent of maximum. Rage, energy, and focus default to the raw cost. Optional tint by resource.
- Minimap launcher via LibDBIcon when present, otherwise a built-in button. On by default. Addon compartment opens settings.
- Login prepares overlays once. Known spells use the spellbook and `IsPlayerSpell`. Secret values are rejected before they are treated as true.
- Paging, spec, equipment, and aura bursts coalesce into one delayed refresh.
- TOC loads only on `forever`. Event registration skips APIs this client does not have.
- Modules talk only through `ns`. Pure parsers (`Database.lua`, `SpellText.lua`, `Efficiency.lua`) are covered by `tests/run.lua`.

## Housekeeping that still holds

- `ns.Debug` stays silent unless `db.debug` is on.
- TOC fields follow the house order. README and DESCRIPTION match the player-facing name.
- Ketho's annotation path stays in `.luarc.json`. Repo-local `.annotations/` covers Forever secret-value helpers those annotations lack.
- `assets/` is release media and must not be deleted during cleanup.
