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

After that, Majesty writes `MajestyCameraZoom.bin` in its install folder and
uses that saved zoom level when quests load.

If Windows blocks the patch because the game is under `Program Files`,
right-click the install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Camera Zoom.bat
```

The saved `MajestyCameraZoom.bin` file is left in the game folder. It is
harmless, and keeping it means your zoom setting is still there if you reinstall.

To reset the remembered zoom, delete `MajestyCameraZoom.bin` from the Majesty
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

The repo does not contain Majesty game assets or game files.
