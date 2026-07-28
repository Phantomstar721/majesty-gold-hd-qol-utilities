# Majesty Gold HD - Quest Map Drag

A small Windows patcher for the Steam version of **Majesty Gold HD**.

It lets you hold the left mouse button on the quest selection map and drag to
pan. The game's stock edge-scroll dimensions are left unchanged.

## Install

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Double-click `Install - Quest Map Drag.bat`.
4. Start Majesty Gold HD and open the quest selection screen.

If Windows blocks the patch because the game is under `Program Files`, right-click the
install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Quest Map.bat
```

This removes click-drag panning and leaves the stock quest-map behavior intact.

## Notes

This is a local file patch, not a Steam Workshop mod. Workshop mods load after Majesty
has already started, so this behavior change needs to be applied to the local install.

The patcher tries to find the Steam install automatically, including Steam library
folders on other drives. If it cannot find the game, run the PowerShell script manually
with a path:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Install-QuestMapDragPan.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
```
