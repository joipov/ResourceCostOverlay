# Resource Cost on Icons audit — 2026-10-12

Target: World of Warcraft Forever, `## Interface: 16001`, Lua 5.1.
References: Ketho's vscode-wow-api annotations, the Forever API, and the other Joipov addons.

## Already in good shape

Action-id checks, coalesced refresh, and the cached font from the 2026-10-11 pass still hold. `pcall` remains around the optional host frame lookup.

## This pass

- Login no longer runs `Prepare` twice. Later zone changes still do.
- Known spells use `C_SpellBook.IsSpellKnown` and `IsPlayerSpell`. Secret results are rejected before they are treated as true. The old `IsSpellKnown` global is gone.
- Spellbook reads and the built-in cooldown-viewer getters are called directly. A secret table is not indexed.
- `ns.Debug` matches the other addons and stays silent unless `db.debug` is on.
- The minimap button is the shared launcher.
- TOC fields follow the house order. The README target line says `forever`.
- Ketho's annotation path stays in `.luarc.json`. That file is the library list LuaLS uses for this addon.
