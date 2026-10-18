# Spell Resources

Small numbers for mana, rage, energy, and focus on spell buttons, and healing or damage rates on spell tooltips. Cooldown Manager bars are on by default. Action bars are off until you turn them on.

Target client: World of Warcraft **Forever** (`## Interface: 16001`).

## Features

- Cost text on Cooldown Manager spell bars and buff bars. Action bars are optional.
- A lower rank on an action bar — including a rank written in a macro — shows that rank's cost. A Cooldown Manager icon shows the rank you have trained.
- Mana, rage, energy, and focus. Other power types are ignored.
- Mana costs show as a percent of maximum. Rage, energy, and focus show the raw cost. Each resource has its own setting.
- Optional tint by resource (blue mana, red rage, orange focus, yellow energy).
- Spell tooltips show damage, healing, or absorb per point of resource, and healing or damage per second for spells that can be cast again immediately. English descriptions. Both lines are on by default.
- Minimap launcher via LibDBIcon when present, otherwise a built-in button. On by default. Addon compartment and `/rco` open settings.

## Commands

| Command | Effect |
| --- | --- |
| `/rco`, `/resourcecost` | Open the settings panel |
| `/rco bars` | Toggle action-bar costs |
| `/rco percent` | Show which resources use a percent |
| `/rco percent mana` | Toggle mana as a percent (`rage`, `energy`, `focus` too) |
| `/rco minimap` | Toggle the minimap button |
| `/rco toggle` | Enable or disable the overlay |
| `/rco debug` | Print target discovery |
| `/rco mouse` | Print the spell under the cursor, with its rank, costs, and macro details when it cannot resolve |
| `/rco spell` | Print the last spell tooltip that was read |
| `/rco help` | List commands |

## Files

Loaded in TOC order; modules communicate only through the shared `ns` table.

| File | Concern |
| --- | --- |
| `Database.lua` | SavedVariables defaults, migrations, validation |
| `SpellText.lua` | Rank suffix and first `/cast` token from macro text |
| `Core.lua` | Spell cost, macro and action-bar rank, trained rank for Cooldown Manager, overlay text |
| `Efficiency.lua` | Damage, healing, and absorb parsed from an English spell description |
| `Tooltip.lua` | Cost and cast lines on spell tooltips |
| `Targets.lua` | Cooldown Manager and action buttons to label |
| `MinimapButton.lua` | LibDBIcon launcher or built-in button, addon compartment |
| `Options.lua` | Settings panel, slash commands |

## Development

The repository lives outside the game folder; the AddOns entry is a
directory junction to it:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\ResourceCostOverlay" "D:\Repos\Joipov\ResourceCostOverlay"
```

Static checks (no game client needed):

```
luacheck .            # .luacheckrc: Lua 5.1, explicit WoW globals
luajit tests/run.lua  # or: lua5.1 tests/run.lua
```

LuaLS uses `.luarc.json` and Ketho's WoW API annotations. The repo-local
`.annotations/` folder declares the Forever secret-value helpers those
annotations lack.

`assets/` is release media for CurseForge and Wago (screenshots, and a logo
when one exists). The game does not load it, and it is not part of the addon
zip. Do not delete it during cleanup.

Local zip, with the addon folder at the root, written to `.release/`:

```
powershell -File package.ps1
```

Releases: push an annotated tag (`git tag -a 1.0.0 -m "1.0.0"`). The
`Package and release` workflow runs BigWigsMods/packager, which reads the game
version from the TOC and the manual changelog from `CHANGELOG.md`.
`CODE_AUDIT_*.md` is the audit note and is not shipped.
