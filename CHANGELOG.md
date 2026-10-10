# Changelog

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
