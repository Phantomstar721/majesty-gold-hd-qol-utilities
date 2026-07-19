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

The saved preset file, `MajestyModPersistence.txt`, is left in the game folder. It is
harmless, and keeping it means your choices are still there if you reinstall the patch.

## What It Changes

The installer patches `MajestyHD.exe` so the game can:

- Save the current Active mod list when you press **OK** in the Mods screen.
- Restore that saved list when Majesty starts.
- Skip missing or uninstalled mods instead of failing.
- Avoid duplicating the same mod if the Mods screen is opened and saved again.

The installer creates a backup before patching. The uninstall BAT restores the original
behavior.

## Steam Workshop Note

This is a local EXE patch, not a Steam Workshop mod. Workshop mods are loaded from inside
Majesty after the game is already running, which is too late to change how the game
initializes its active mod list.

## Custom Steam Library Folders

The patcher tries to find the Steam install automatically, including Steam library folders
on other drives. If it cannot find the game, run the PowerShell script manually with a
path:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Install-ModPersistence.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
```

