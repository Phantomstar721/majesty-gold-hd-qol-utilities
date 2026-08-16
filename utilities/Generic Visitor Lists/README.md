# Majesty Gold HD - Generic Visitor Lists

A small local patcher for the Steam version of **Majesty Gold HD**.

It lets a building's stock Visitors panel display any valid unit stored in its
occupant list. Stock hero rows remain unchanged. Other unit types use the
existing hero-row presentation: level, name, current action, and hit points.
Monster rows use Majesty's stock `IX92` / `IX94` monster-icon resolver.
For nonhero units with a positive stock XP bounty, the level column displays
an eight-step **Threat Rank** derived from that bounty instead of the unit's
normally empty hero-level attribute.

This was developed for Restore Abandoned Zoo, whose captured monsters were
correctly stored and selectable but whose visitor rows were blank.

## Install

1. Download and unzip the latest release.
2. Close Majesty Gold HD.
3. Double-click `Install - Generic Visitor Lists.bat`.
4. Start Majesty normally.

If Windows blocks the patch because the game is under `Program Files`,
right-click the BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Visitor Lists.bat
```

## What It Changes

This changes three guarded dispatch/call sites in `MajestyHD.exe`. Both the icon
dispatcher and Threat Rank converter live in a dedicated `.mgvl` PE section
whose location is calculated when installed, so the utility does not claim
padding or storage owned by another patch.

The stock visitor controller already creates rows for every occupant and
stores their valid unit IDs. It also already contains a complete
level/name/action/HP renderer, but stock sends non-hero/non-alternate unit
categories directly to cleanup without drawing. This patch redirects only
that discarded category into the existing stock renderer.

There are no Zoo IDs, replacement UI controls, or gameplay changes in this
utility. Icon selection remains owned by Majesty's existing monster resolver.
Threat Rank is calculated only while painting a row; it does not write a level
or any other attribute back to the unit.

## Monster Threat Rank

Majesty stores each monster's designer-authored kill reward in
`ATTRIB_LevelXP`, sourced from the character XML's `<Experience value="..."/>`.
The stock attack lifecycle awards that exact value to the victorious hero.
This patch groups the 48 stock monsters with positive XP into eight approximate
quantiles:

| Threat Rank | Monster XP |
| --- | ---: |
| 1 | 1-230 |
| 2 | 231-400 |
| 3 | 401-500 |
| 4 | 501-900 |
| 5 | 901-1500 |
| 6 | 1501-2000 |
| 7 | 2001-3500 |
| 8 | 3501+ |

The rank bands are mod-authored UI semantics, not a surviving stock monster
level system. Tied XP values remain together, so the middle bands are only
roughly equal in population. A nonhero unit without positive `LevelXP` data
keeps the stock level-column value instead.

## Compatibility

The installer guards every changed byte for the Steam 1.5.2.24 executable and
refuses unknown data instead of overwriting it. Its static ranges do not
overlap the other Majesty Gold HD QoL Utilities patches. Its relocatable
`.mgvl` section is appended after any existing patch sections.

Generic Visitor Lists can be installed or uninstalled independently in any
order. If another patch section follows `.mgvl`, uninstall restores every hook
immediately and leaves only inert reserved storage that a later reinstall can
reuse safely.

## Required monster-icon resources

Any mod that places monsters in a visitor list must also make `IX92` and `IX94`
available in that dataset. Base quests do not ordinarily load those expansion
interface resources. See [Custom monster icon contract](docs/custom-monster-icons.md)
for the exact requirements and CAM compatibility warning.

## Non-default game location

The installer finds Steam automatically, including libraries on other drives.
If needed, run the script directly with a path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-GenericVisitorLists.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
```

Add `-DryRun` to validate the executable and report the intended changes
without writing anything.

## If you ever need a clean executable

The uninstaller reverses only this utility's own guarded changes. The backup
folder is a convenience snapshot and may contain other patches that were
already installed. For a guaranteed stock executable, use Steam's **Verify
integrity of game files** command.
