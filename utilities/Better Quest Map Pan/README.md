# Majesty Gold HD - Better Quest Map Pan

A small Windows patcher for the Steam version of **Majesty Gold HD**.

This improves the quest selection map in two ways:

- You can hold the left mouse button on the map and drag to pan.
- The edge-scroll zone is wider, so panning at the edge of the screen is much easier.

## Install

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Double-click `Install - Better Quest Map Pan.bat`.
4. Start Majesty Gold HD and open the quest selection screen.

If Windows blocks the patch because the game is under `Program Files`, right-click the
install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Quest Map Pan.bat
```

This restores the quest map panning behavior changed by this patch.

## Optional Files

The main install BAT is the one most players want.

The ZIP also includes click-drag-only BATs for troubleshooting:

- `Install - Click-Drag Quest Map Pan Only.bat`
- `Uninstall - Restore Click-Drag Quest Map Pan Only.bat`

The edge-pan-only version is still available as the older `v1.0.0` release.

## Notes

This is a local file patch, not a Steam Workshop mod. Workshop mods load after Majesty
has already started, so this behavior change needs to be applied to the local install.

The patcher tries to find the Steam install automatically, including Steam library
folders on other drives. If it cannot find the game, run the PowerShell script manually
with a path:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Install-QuestMapPan.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
```

## Tuning Edge Pan

The default edge zone is `64` pixels. To try a different size, run the PowerShell script
directly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Install-QuestMapPan.ps1 -EdgePixels 48
```

