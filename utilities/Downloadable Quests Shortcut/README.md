# Majesty Gold HD - Downloadable Quests Shortcut

A small Windows patcher for the Steam version of **Majesty Gold HD**.

It makes the Downloadable Quests menu easier to reach from the quest selection map.
In the unpatched game, that button sits on the panning map and can be annoying to find.
After installing this patch:

- The circular compass icon opens **Downloadable Quests**.
- The `FREESTYLE QUESTS` text label still opens Freestyle.
- The old panning-map Downloadable Quests button is removed.

## Install

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Double-click `Install - Downloadable Quests Shortcut.bat`.
4. Start Majesty Gold HD and open the quest selection screen.

If Windows blocks the patch because the game is under `Program Files`, right-click the
install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Original Quest Buttons.bat
```

The installer creates backups the first time it runs and the uninstaller restores those
files.

## Notes

This is a local file patch, not a Steam Workshop mod. Workshop mods load after Majesty
has already started, so this menu change needs to be applied to the local install.

The patcher tries to find the Steam install automatically, including Steam library
folders on other drives. If it cannot find the game, run the PowerShell script manually
with a path:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Install-DownloadableQuestShortcut.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
```

Tested with the Steam release of Majesty Gold HD at `1680x1050`. The installer also
patches the other modern UI layouts that contain the same quest selection menu.

## Non-default game location

The installer finds Steam automatically, including libraries on other drives and
an install folder that has been renamed. If it still cannot find the game, run
the script directly with a path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-DownloadableQuestShortcut.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
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