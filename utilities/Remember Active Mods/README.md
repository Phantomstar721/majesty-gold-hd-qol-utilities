# Majesty Gold HD - Remember Active Mods

A small Windows patcher for the Steam version of **Majesty Gold HD**.

Majesty Gold HD normally forgets which mods you activated when you close the
game. This patch remembers the mods in the in-game **Mods > Active** list and
puts them back automatically the next time Majesty starts.

## Install

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Double-click `Install - Remember Active Mods.bat`.
4. Start Majesty Gold HD.
5. Open **Mods**, move the mods you want into **Active**, then press **OK**.

After that, Majesty should restore those active mods on future launches.

If Windows blocks the patch because the game is under `Program Files`, right-click the
install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Mod Selection.bat
```

This restores Majesty's stock mod-selection behavior.

The saved preset file, `%LOCALAPPDATA%\MajestyHD\MajestyModPersistence.txt`, is
left in place. It is
harmless, and keeping it means your choices are still there if you reinstall the patch.

## What It Changes

The installer patches `MajestyHD.exe` so the game can:

- Save the current Active mod list when you press **OK** in the Mods screen.
- Restore that saved list when Majesty starts.
- Commit the restored selection through Majesty's normal active-mod configuration
  routine so custom descriptions and build-menu registrations reload correctly.
- Skip missing or uninstalled mods instead of failing.
- Avoid duplicating the same mod if the Mods screen is opened and saved again.

The installer creates a backup before patching. The uninstall BAT restores the original
behavior.

When combining this with other utilities that append executable sections, the
installer derives its placement from the current executable and relocates its
engine calls accordingly. Re-running it on a compatible multi-patch executable
is safe; it validates its own section without disturbing later sections.

If you used a release from before the active-mod commit fix, run the current
installer again. It updates an existing `.mpst` section in place, including one
left inert by the uninstaller.

## Steam Workshop Note

This is a local EXE patch, not a Steam Workshop mod. Workshop mods are loaded from inside
Majesty after the game is already running, which is too late to change how the game
initializes its active mod list.

## Non-default game location

The installer finds Steam automatically, including libraries on other drives and
an install folder that has been renamed. If it still cannot find the game, run
the script directly with a path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-ModPersistence.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
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
