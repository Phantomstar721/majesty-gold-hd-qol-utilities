# Majesty QoL Utilities

One download that bundles the Majesty Gold HD quality-of-life utilities built for the
Steam version of **Majesty Gold HD**.

## What's Included

- **Skip Intro Videos**: starts Majesty at the main menu instead of playing the intro
  videos.
- **Downloadable Quests Shortcut**: turns the bottom Freestyle quest icon into a
  fixed shortcut for downloadable/custom quests.
- **Better Quest Map Pan**: widens the quest-map edge-scroll zone and adds
  left-click drag panning.
- **Remember Active Mods**: saves the in-game **Mods > Active** list and restores it
  automatically on future launches.

## Install Everything

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Double-click `Install - All Majesty QoL Utilities.bat`.
4. Launch Majesty Gold HD normally from Steam.

If Windows blocks the patch because Majesty is installed under `Program Files`,
right-click the install BAT and choose **Run as administrator**.

## Pick And Choose

Each utility is also included separately under `utilities\`.

Open the folder for the utility you want and run its own install or uninstall BAT.

## Uninstall Everything

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Majesty QoL.bat
```

This restores the stock behavior changed by the bundled utilities. Individual
uninstallers are also available in each utility folder.

## Notes

These are local Windows patchers, not Steam Workshop mods. Workshop mods load after
Majesty is already running, so startup behavior, EXE UI hooks, and mod-list restoration
need local setup.

The game-folder patchers try to find the Steam install automatically, including Steam
library folders on other drives.

## Included Repos

- `majesty-gold-hd-skip-intro-videos`
- `majesty-gold-hd-downloadable-quests-shortcut`
- `majesty-gold-hd-better-quest-map-pan`
- `majesty-gold-hd-remember-active-mods`

## Build A Release Zip

Run:

```text
Create Release Zip.bat
```

The ZIP is written to `dist\`.

