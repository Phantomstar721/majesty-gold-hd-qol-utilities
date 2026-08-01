# Majesty Gold HD - QoL Utilities

One download that bundles the Majesty Gold HD quality-of-life utilities built for the
Steam version of **Majesty Gold HD**.

## What's Included

- **Skip Intro Videos**: starts Majesty at the main menu instead of playing the intro
  videos.
- **Downloadable Quests Shortcut**: turns the bottom Freestyle quest icon into a
  fixed shortcut for downloadable/custom quests.
- **Quest Map Drag**: adds left-click drag panning while preserving the stock
  quest-map edge-scroll dimensions.
- **Remember Active Mods**: saves the in-game **Mods > Active** list and restores it
  automatically on future launches.
- **Remember Game Speed**: saves the in-quest game-speed slider and restores it for
  saved games, new quests, and future Majesty launches.
- **Remember Camera Zoom**: saves the in-quest camera zoom button setting and
  restores it for new quests and future Majesty launches.

## Install Everything

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Double-click `Install - All Majesty QoL Utilities.bat`.
4. Launch Majesty Gold HD normally from Steam.

If Windows blocks the patch because Majesty is installed under `Program Files`,
right-click the install BAT and choose **Run as administrator**.

### Non-default game location

The BAT files auto-detect Steam. If your game is somewhere the detection misses,
run the installer directly and point it at the folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-All.ps1 -GamePath "D:\Path\To\Majesty HD"
```

Add `-DryRun` to see exactly what would change without touching anything.

## Pick And Choose

Each utility is also included separately under `utilities\`.

Open the folder for the utility you want and run its own install or uninstall BAT.

**Install order does not matter.** Each utility works out where its own patch
goes by reading `MajestyHD.exe`, and the two that share code sites hand off to
each other in either direction.

## Uninstall Everything

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Majesty QoL.bat
```

This restores the stock behavior changed by the bundled utilities. Individual
uninstallers are also available in each utility folder.

**Uninstall order does matter.** Three of these append a section to
`MajestyHD.exe`, and a section can only be removed while it is the last one
added, so the most recently installed must come off first. The bundle
uninstaller already does this for you. If you uninstall utilities individually
and get a message about a section not being last, remove the newer ones first
and try again.

If you also installed the standalone **Speedrun Timer**, uninstall that before
running the bundle uninstaller, since its section sits after everything here.

## Notes

These are local Windows patchers, not Steam Workshop mods. Workshop mods load after
Majesty is already running, so startup behavior, EXE UI hooks, and mod-list restoration
need local setup.

The game-folder patchers try to find the Steam install automatically, including Steam
library folders on other drives.

Remember Game Speed writes `MajestySessionSpeed.bin` under `%LOCALAPPDATA%\MajestyHD`
after you change the in-quest speed with the slider or faster/slower controls.
The file is harmless and is left behind by the uninstallers so reinstalling the
patch keeps your last speed.

Remember Camera Zoom writes `MajestyCameraZoom.bin` under `%LOCALAPPDATA%\MajestyHD`
after you use the in-quest camera zoom button once. The file is harmless and is
left behind by the uninstallers so reinstalling the patch keeps your last zoom.

## Included Repos

- `majesty-gold-hd-skip-intro-videos`
- `majesty-gold-hd-downloadable-quests-shortcut`
- `majesty-gold-hd-quest-map-drag`
- `majesty-gold-hd-remember-active-mods`
- `majesty-gold-hd-remember-game-speed`
- `majesty-gold-hd-remember-camera-zoom`

## If you ever need a clean executable

These utilities uninstall by reversing their own byte changes, so you do not
need a backup copy to remove them. The `_*_originals` folder each installer
creates is only a convenience snapshot of whatever was on disk beforehand, which
may already include other patches. It is not a stock game file.

For a guaranteed unmodified executable, let Steam do it:

1. Right-click **Majesty Gold HD** in your Steam library
2. **Properties** > **Installed Files**
3. **Verify integrity of game files**

Steam will replace `MajestyHD.exe` with the original. You can then reinstall
whichever utilities you want.