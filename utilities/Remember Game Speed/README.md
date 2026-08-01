# Majesty Gold HD - Remember Game Speed

A small local patcher for the Steam version of **Majesty Gold HD**.

Majesty remembers volume settings between sessions, but it resets the in-quest
game-speed slider whenever you launch the game again or start a new quest. This
patch makes the speed slider behave like a saved preference.

## Install

1. Close Majesty Gold HD.
2. Double-click `Install - Remember Game Speed.bat`.
3. Start Majesty Gold HD.
4. Start a quest and change the game-speed slider once.

After that, Majesty writes `MajestySessionSpeed.bin` under
`%LOCALAPPDATA%\MajestyHD`, where the normal non-administrator game process has
write access. It uses that saved speed when new quests start, saved games load,
and the game is relaunched.

If Windows blocks the patch because the game is under `Program Files`,
right-click the install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Game Speed.bat
```

The saved `%LOCALAPPDATA%\MajestyHD\MajestySessionSpeed.bin` file is left in
place. It is harmless, and keeping it means your speed setting is still there
if you reinstall.

To reset the remembered speed, delete
`%LOCALAPPDATA%\MajestyHD\MajestySessionSpeed.bin` or change the slider again
after reinstalling the patch.

## What It Changes

The installer patches `MajestyHD.exe` so the game can:

- Save the selected speed when the in-quest slider or faster/slower controls
  change it.
- Apply the saved speed to the live game object when saved games load.
- Apply the saved speed during new-quest setup before the game falls back to its
  default speed.
- Load the saved speed from disk on a fresh Majesty launch.
- Coexist with the earlier Remember Active Mods patch by adding a separate
  `.mskp` section after any existing `.mpst` section.
- Recognize and preserve the optional Speedrun Timer bridges when both patches
  are installed.

This is an EXE patch, not a Steam Workshop mod.

## Compatibility

This patch targets the Steam release of Majesty Gold HD tested during this
project. If Steam updates `MajestyHD.exe`, run the installer again. The installer
checks the bytes it plans to patch and stops if the executable is not in a known
stock or already-patched state.

## Non-default game location

The installer finds Steam automatically, including libraries on other drives and
an install folder that has been renamed. If it still cannot find the game, run
the script directly with a path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-RememberGameSpeed.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
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