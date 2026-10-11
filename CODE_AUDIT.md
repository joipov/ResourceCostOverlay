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

## Practices (2026-10-10)

Checked against the Joipov house style and against Warcraft Wiki secret values plus the Ketho WoW API library in `.luarc.json`.

- The always-on `OnUpdate` is gone. A delayed refresh arms one `C_Timer.After` (`REFRESH_THROTTLE`). Another delayed request before that timer fires does nothing. An immediate refresh still runs `RefreshAll` now and drops a timer that has not fired.
- `UNIT_MAXPOWER` is `RegisterUnitEvent(..., "player")`, same as `UNIT_AURA`. If the client has no `RegisterUnitEvent`, both events fall back to `RegisterEvent` and the handler ignores a non-player unit.
- `ADDON_LOADED` is unregistered after this addon loads.
- The event `if` ladder is a handler table. Spec and trait events still invalidate ranks and then refresh. Other bar events still refresh immediately. The aura handler still waits 0.3s, then requests a delayed refresh.

Left alone: cost lookup, button discovery, the Ellesmere `hooksecurefunc`, and the SavedVariables schema.

## 1.1.3

Action-bar costs use the rank on the button. Cooldown Manager icons still use the trained rank. If `GetSpellPowerCost` returns that trained cost for a lower rank id, the button uses `GetSpellInfo.cost` when the base cost is a different positive number.
