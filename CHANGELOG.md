# Changelog

## 1.5.0

Spell tooltips show estimated spell power coefficients (and explicit attack power shares) from cast time, DoT duration, and live player stats—no spell-ID database.

### Added

- Coefficient lines under the spell description: share of spell power or healing power, and a base + bonus split using your current bonuses. Formula estimates are marked `~`.
- Attack power coefficient when the description names a percent of your attack power.
- Settings toggles for coefficients and Shift-only display.
- `/rco spell` prints the coefficient rows for the last tooltip.

## 1.4.3

Action-bar macros on custom bars now show the cost of the rank written in the macro, even when the client does not expose the macro body or spell by its macro id.

### Fixed

- A macro's first `/cast` name, including `(Rank N)`, is passed straight to `GetSpellPowerCost`. This is the rank the player actually casts.
- Host action bars that put a spell id in `.action` or the `action` attribute now use the slot in the button name (`EABButton4` is slot 4), so `GetActionInfo` returns the real macro.
- If the macro body is not available by id, the macro name on the action button is used to read the body.
- If neither works, the action's own tooltip is read as a last resort.
- `/rco mouse` now prints the action slot, macro id, body, `GetMacroSpell` result, and body-resolved spell.

## 1.4.2

Restores the action-bar values that 1.4.1 could hide.

### Fixed

- A macro without a rank uses the spell the client already resolved again. The macro body is only a last-resort fallback, so a button that worked before keeps working.
- The macro-name fallback is back, restricted to a spell the player knows.
- Tooltip cost reads are protected, so a failed tooltip call cannot stop the whole overlay refresh.
- `/rco mouse` reads the spell already shown on a tracked button, and prints the macro body and `GetMacroSpell` result when nothing resolves.

## 1.4.1

Action-bar macros keep the cost of the rank they cast, including rank 1 and multi-word spell names.

### Fixed

- Costs the client reports with both a percent and a resolved amount are no longer discarded. This was why some spells, such as Lesser Heal, showed no number while others did.
- A lower-rank spell on an action bar now reads that rank's cost from the spell tooltip when the client returns nothing from `GetSpellPowerCost`. This covers macros such as `/cast Renew(Rank 1)`.
- An explicit-rank macro resolves from its first `/cast` line, so `(Rank 1)` macros no longer depend on the client's macro spell cache.
- A macro without a rank keeps the spell the client already resolved. The macro body and then the macro name are only fallbacks, so a button that worked before keeps working.
- The macro-name fallback only accepts a spell the player knows.

## 1.4.0

Spell tooltip efficiency: ranked next-swing names, forgone rage, DoT-heavy DPS, and Shift-gated calculation notes.

### Added

- Next-swing abilities (Heroic Strike, Cleave, Maul) count the rage the empowered swing would have generated as cost too.
- DoT-heavy spells (Immolate-style) rate DPS as the DoT over cast time plus duration.
- Calculation notes on tooltips (forgone rage, DoT mode, absorb drain, weapon source). Notes are Shift-only by default.
- Optional Shift-only toggles for efficiency and per-second suffixes.
- A combat-secret marker when weapon damage or swing rage cannot be read in combat.

### Fixed

- Ranked titles such as `Cleave (Rank 3)` now match next-swing and shot-interval name tables.
- Skipped amount ranges no longer re-match the second bound of `31 to 45`.

## 1.3.0

Spell tooltips show what a spell returns for its cost, and the healing or damage per second of casting it again immediately. The player-facing name is Spell Resources.

### Added

- The cost line shows damage, healing, or absorb per point of mana, rage, energy, or focus.
- The cast line shows healing per second and damage per second for spells without a cooldown.
- Settings turn each of those lines on or off.
- `/rco spell` prints the last spell tooltip that was read.

### Changed

- The addon title is Spell Resources. The folder, saved settings, and `/rco` are unchanged.

## 1.2.5

The addon loads without registering an event the client does not have.

### Fixed

- The unknown action-bar state event is no longer registered on load.

## 1.2.4

Settings text describes the buttons without naming another addon.

### Changed

- The minimap button tooltip says the button opens settings.
- Action-button coverage is the default buttons and custom action buttons.

## 1.2.3

Costs are prepared once at login, and known spells are read straight from the spellbook.

### Changed

- Entering the world at login no longer builds the labels a second time.
- A spell you know is checked with the spellbook and `IsPlayerSpell`.

## 1.2.2

The login line shows the addon name and version. The Joipov name color is a brighter violet.

### Changed

- The login line reads Joipov <name> (v<version>). The name and version come from the TOC, so they never drift. The version is a different color.
- Joipov is now a saturated violet.

## 1.2.1

Fewer needless refreshes, and two small fixes.

### Fixed

- An action button that holds an item or a macro is no longer mistaken for the spell with the same number, which could show a wrong cost.
- Slash-command help uses commas, so chat no longer eats the text after `|`.

### Changed

- Paging, spec, equipment, and similar events now coalesce into one delayed refresh instead of refreshing immediately per event.
- A burst of aura events arms a single delayed refresh.
- The font is resolved once and set on a label only when it changes.
- The minimap position is stored in LibDBIcon's own table, so dragging the button with LibDBIcon keeps its place.
- The addon loads only on the `forever` game type.

### Removed

- The unused `ns.GetTrackedButtons`, `ns.DB_DEFAULTS`, and `ns.ANCHORS`.

## 1.1.3

A lower rank on the action bar shows that rank's cost.

### Fixed

- Action buttons keep the mana, rage, energy, or focus of the rank on the button. Cooldown Manager icons still show the rank you have trained.
- If the client returns the trained rank's cost for every rank of a spell, the button uses that rank's base cost instead.

## 1.1.2

Settings are grouped and use the same wording as the other Joipov addons.

### Changed

- Sections are Icons, Numbers, Placement, and Color.
- **Cooldown spells** and **Cooldown buffs** replace the CDM labels.
- **Horizontal offset**, **Vertical offset**, and **Text size** replace Offset X, Offset Y, and Font size.
- **Text color** is a color button. The red, green, and blue sliders are gone. Saved colors stay.
- The other rows grey out while the addon is off.

## 1.1.1

The minimap button is on by default, including saves that still had it off.

### Changed

- **Minimap Button** sits under Enable and starts on. Click opens settings.
- The button uses LibDBIcon when that library is loaded, and the same frame name when it is not, so the default minimap and the addon compartment can show it.
- The button icon is a note, matching the addon list icon.

## 1.1.0

Mana costs show as a percent of maximum. Rage, energy, and focus show the raw number. Each resource has its own setting.

### Changed

- The addon list groups this under Joipov Tools. The list name has no Joipov prefix.
- The single "percent of max" toggle is now one checkbox per resource: mana, rage, energy, and focus.
- Mana defaults to a percent. Rage, energy, and focus default to the raw cost.
- `/rco percent` prints those four states. `/rco percent mana` (or rage, energy, focus) toggles one.

## 1.0.1

Resource Cost on Icons loads on its own. Chat lines no longer go through another addon. The numbers are unchanged.

### Changed

- Chat lines are printed by this addon. One login line tells you `/rco`.

## 1.0.0

Resource costs on Cooldown Manager buttons, with action bars optional.

### Added

- Mana, rage, energy, and focus costs on Cooldown Manager spell bars and buff bars.
- Optional action-bar costs, percent of maximum, and a tint per resource.
- Minimap button (off by default), addon compartment, and `/rco`.
