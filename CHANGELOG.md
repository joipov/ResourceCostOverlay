# Changelog

## 1.2.0

Fewer needless refreshes, and two small fixes.

### Fixed

- An action button that holds an item or a macro is no longer mistaken for the spell with the same number, which could show a wrong cost.
- Slash-command help uses commas, so chat no longer eats the text after `|`.

### Changed

- Paging, spec, equipment, and similar events now coalesce into one delayed refresh instead of refreshing immediately per event.
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
- The button uses LibDBIcon when that library is loaded, and the same frame name when it is not, so the default minimap, the addon compartment, Ellesmere, and ElvUI can all show it.
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
