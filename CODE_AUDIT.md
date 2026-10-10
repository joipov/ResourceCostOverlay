# ResourceCostOverlay audit

Target: World of Warcraft Forever, game type `camelot`, `## Interface: 16001`. Lua 5.1. Ketho WoW API annotations via `.luarc.json`.

Checked while aligning the Joipov addons (1.0.0).

## Result

- SavedVariables were already assigned on `_G.ResourceCostOverlayDB`. No gameplay change.
- An unused `GetActionInfo` subtype was dropped, and three empty `if pcall` branches are plain `pcall` calls. The same optional events are still registered.
- Globals this addon writes: SavedVariables, slash commands, and the compartment callback.
- luacheck is Lua 5.1 with an explicit WoW global list. `.annotations/Wow.lua` stubs the Forever secret-value helpers Ketho may omit.

## Left alone

- Cost lookup, button discovery, and the SavedVariables schema.

`assets/` is release media for CurseForge and Wago. It is not loaded by the TOC, not shipped in the zip, and not part of this audit.
