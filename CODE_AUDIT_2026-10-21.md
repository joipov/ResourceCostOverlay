# Spell Resources audit

Target: World of Warcraft Forever, `## Interface: 16001` (client 1.60.1.70862), Lua 5.1.
References, in house order: the Forever API for this build, Warcraft Wiki
Patch 1.60.1/API changes and Patch 12.0.0 secret values, Ketho's vscode-wow-api
annotations, BlizzardInterfaceCode. Compared 2026-10-21 against
ResourceEfficiencyTooltips 0.2.1 (2026-10-18), EllesmereUI 9.6.1 (2026-10-19),
and PrettyTooltip 1.3.5 (2026-10-21). That comparison is behaviour only:
ResourceEfficiencyTooltips and ForeverBiS ship no licence, so no code,
strings, or data tables were taken from them. Re-checked against client
1.60.1.70862 and EllesmereUI 9.8.2 on 2026-11-08.

This note is for development. It is not shipped in the addon zip.

## What changed in 1.5.2

- Re-checked every private Ellesmere field this addon reads against 9.8.2:
  `ERB_PrimaryBar`, `_sb`, `RaiseBorderAbove`, `EllesmereUIUnitFrames_Player.Power`,
  `EllesmereUI._ModuleNS`, `CollectAndReanchor`, `cdmBarIcons`, `cdmBarFrames`,
  `IsBarBuffFamily`, `GetTrackedBuffBars`, `GetTBBFrame`, `_isPlaceholderFrame`,
  `useBlizzardBuffBars`, `hideBlizzard`, and `EABButton<slot>` (1–180). All
  keep their shapes. `C_Spell.GetSpellBaseCooldown` and the
  `GetSpellBaseCooldown` global are still absent, and the existing guard
  still covers them. No code change.

## What changed in 1.5.1

- A secret cooldown is "unknown", not "none". `CooldownSeconds` returns a
  secret flag, `ReadSpellTooltip` marks `cast.secret` when the cooldown line
  is secret, and `ThroughputRates` answers the secret mark instead of a
  per-second rate that assumed a recast.
- A secret description or cost line poisons the whole computation. The
  suffixes show the combat-secret mark rather than numbers built from the
  lines that happened to be readable.
- `C_Spell.GetSpellPowerCost` is read as one guarded call. A cost that goes
  secret in combat keeps its last readable text on icons.
- The Ellesmere reanchor hook is retried during target collection, and
  `/rco debug` names missing host fields. Every private Ellesmere field this
  addon reads was checked present in 9.6.1 (2026-10-19); the failure mode if
  one goes away is silent missing text, never an error.
- Settings setup follows house style again: no pcall around `InitOptions`,
  no existence guards for `Settings`, and the mouse probe uses
  `GetMouseFoci` (the old `GetMouseFocus` global does not exist here).
- The Minimap button row stays active while the addon is off.

## Still holds

- Cost resolution (rank fallback through `C_TooltipInfo`, macro ranks,
  override spells) is deeper than the compared addon's and unchanged.
- Secret checks stay `issecretvalue` and not `canaccessvalue`, as Patch
  12.0.0 documents. Cache keys include the secret flags, so a combat read
  cannot reuse an out-of-combat number.
- No `OnUpdate` anywhere; refreshes stay event-driven and coalesced.

## Checked in the client (manual pass, 1.5.1)

- [ ] In combat: hover a spell with a cooldown — the cast line shows the
      secret mark, not a per-second rate; hover a cost-bearing spell — the
      suffix is the secret mark, not a ratio.
- [ ] In combat: icon cost text stays up on cooldown-manager and action-bar
      buttons it was already on.
- [ ] With PrettyTooltip at defaults: coefficients show as an extra row;
      the in-place cost suffix is superseded by its panel, which is its
      design. No duplicated lines.

## Recorded decisions

- Settings rows keep the direct `Settings.CreateCheckbox` form. The
  "secure delegate" claim from TweaksForever was not confirmed; current
  Forever addons (NodeSight, LFG Forever) use the direct form and their
  settings search works. See STYLE.md.
- Coefficients stay text-estimated and marked `~`. The compared addon's
  spell-ID coefficient table was not used and is not Forever-verified.
