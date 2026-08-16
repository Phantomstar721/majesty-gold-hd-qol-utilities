# Majesty Gold HD - Remember Camera Zoom

A small local patcher for the Steam version of **Majesty Gold HD**.

Majesty resets the in-quest camera zoom whenever a new quest starts. This patch
remembers the last zoom level used by the zoom button near the minimap and
restores it for new quests, saved games, and future Majesty launches.

## Install

1. Close Majesty Gold HD.
2. Double-click `Install - Remember Camera Zoom.bat`.
3. Start Majesty Gold HD.
4. Start a quest and use the camera zoom button once.

After that, Majesty writes `MajestyCameraZoom.bin` under
`%LOCALAPPDATA%\MajestyHD` and
uses that saved zoom level when quests load.

The installer encodes this path using Windows' active ANSI code page, matching
Majesty's narrow file API. If the path cannot be represented exactly,
installation stops before changing `MajestyHD.exe` instead of installing a
patch that cannot save.

If Windows blocks the patch because the game is under `Program Files`,
right-click the install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Camera Zoom.bat
```

The saved `%LOCALAPPDATA%\MajestyHD\MajestyCameraZoom.bin` file is left in
place. It is
harmless, and keeping it means your zoom setting is still there if you reinstall.

To reset the remembered zoom, delete `%LOCALAPPDATA%\MajestyHD\MajestyCameraZoom.bin` from the Majesty
install folder or use the zoom button again after reinstalling the patch.

## What It Changes

The installer patches `MajestyHD.exe` so the game can:

- Save the selected camera zoom when you use the in-quest zoom button.
- Load the saved zoom from disk when a quest starts.
- Coexist with the other Majesty Gold HD QoL utilities.

This is an EXE patch, not a Steam Workshop mod.

## Compatibility

This patch targets the Steam release of Majesty Gold HD tested during this
project. If Steam updates `MajestyHD.exe`, run the installer again. The installer
checks the bytes it plans to patch and stops if the executable is not in a known
stock or already-patched state.

It can be installed or uninstalled independently of the other QoL patches in
any order. When a later executable section must retain its address, uninstall
restores every game hook immediately and leaves only inert `.mczp` storage for
a future reinstall to reuse.

The repo does not contain Majesty game assets or game files.

## Non-default game location

The installer finds Steam automatically, including libraries on other drives and
an install folder that has been renamed. If it still cannot find the game, run
the script directly with a path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-RememberCameraZoom.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
```

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
