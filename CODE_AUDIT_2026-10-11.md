# Resource Cost on Icons audit — 2026-10-11

Target: World of Warcraft Forever, game type `forever` (was `camelot`), `## Interface: 16001`, Lua 5.1.
References: the Atraeau Forever API dump (build 70170), Warcraft Wiki (Patch 1.60.1 API changes, Patch 12.0.0 secret values), Ketho's vscode-wow-api annotations, Blizzard's Cooldown Manager source, and the sibling Joipov addons.

Scope: every `.lua`, the `.toc`, `tests/run.lua`, and the docs. `assets/`, `.release/`, and `.annotations/` are not addon code.

## Findings and what was done

### BUG-001 — Item and macro action ids fed to `GetSpellInfo`
`Core.lua`'s spell-like fallback passed the raw action id to `C_Spell.GetSpellInfo` whatever the action type, so an item id or macro index could match an unrelated spell and show a wrong cost. **Fixed** — the fallback is skipped for `item` and `macro` action types.

### BUG-002 — Chat escape codes in the help text
`Options.lua` used `mana|rage|energy|focus`. In chat `|r` is the color-reset code, so the text was eaten. **Fixed** — commas.

### PERF-001 — Immediate refresh on noisy events
Paging, spec, equipment, and `ACTIONBAR_UPDATE_STATE_CHANGED` refreshed immediately. **Fixed** — they coalesce into one delayed refresh through `RequestRefresh`.

### PERF-002 — Aura burst rebuilt a timer each event
`UNIT_AURA` created a closure and a `C_Timer.After` per event. **Fixed** — one shared armed timer.

### PERF-003 — Font resolved and set per label per refresh
`ApplyTextStyle` called `ResolveFont` (and the EllesmereUI font API) per label per refresh, and set the font every time. **Fixed** — the font path is cached, and `SetFont` runs only when the path, size, or flags change.

### ARCH-001 — Dead code
`ns.GetTrackedButtons`, `ns.DB_DEFAULTS`, `ns.ANCHORS`, and the unused `GetTime`/`GetMouseFocus` luacheck reads are unused. **Removed.** `GetMouseFocus` (gone on Forever) is replaced by `GetMouseFoci`.

### CQ-001 — Minimap position in two places
`db.minimapAngle` and `db.minimapIcon.minimapPos` could disagree. **Fixed** — one key, with a migration.

### TOC-001 — Game type
Updated to `forever` plus `## ExcludeLoadGameType: standard, classic`. Revert to `camelot` on a pre-70291 build.

### Left as-is
`GetActionText` and `C_Spell.GetSpellInfo` results are checked with `type()` rather than a secret guard; the values are readable on the current client, and every write goes through read-only `HookScript` or `hooksecurefunc`, so there is no taint. Exact-rank and CDM cost lookups are computed once per icon per refresh; a deeper cache was judged not worth the risk.

## Verification

- `luacheck .` — clean.
- `luajit tests/run.lua` — 6 passed.
- LuaLS with Ketho's annotations — clean.

## In-game checklist

- Costs show on Cooldown Manager spell and buff bars; action bars show them after the setting is on.
- A lower action-bar rank shows that rank's cost.
- An item or macro on an action bar does not show a stray spell cost.
- Mana shows as a percent, rage/energy/focus show the raw number.
- `/rco help` reads correctly in chat (no eaten text).
- The minimap button drags and keeps its place after `/reload`.
- The addon loads (`/dump C_AddOns.IsAddOnLoaded("ResourceCostOverlay")`).
