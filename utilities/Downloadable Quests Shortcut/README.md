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

## Build A Release Zip

Run:

```text
Create Release Zip.bat
```

The ZIP is written to `dist\`.
