# Majesty Gold HD - Speedrun Timer

Adds a speed-adjusted speedrun timer to the Steam version of **Majesty Gold HD**.

The timer appears in the Majesty window title bar while a quest is running:

```text
Majesty - Speedrun Time: 00:00.000
```

## What It Does

- Starts automatically when a quest loads.
- Resets to `00:00.000` on each new quest start.
- Stops and freezes when the quest ends through victory or loss.
- Uses `QueryPerformanceCounter` real-time measurement rather than Majesty's internal simulation tick.
- Scales elapsed time by the current game-speed slider value so runs at different game speeds can be compared.
- Updates correctly if the game-speed slider changes mid-quest.

## Install

Close Majesty Gold HD, then run:

```text
Install - Speedrun Timer.bat
```

The installer looks for Majesty at the default Steam path:

```text
C:\Program Files (x86)\Steam\steamapps\common\Majesty HD
```

If your game is installed somewhere else, run the installer script manually:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-SpeedrunTimer.ps1 -GamePath "D:\Path\To\Majesty HD"
```

## Uninstall

Close Majesty Gold HD, then run:

```text
Uninstall - Restore Stock Timer.bat
```

For a custom game path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Restore-SpeedrunTimer.ps1 -GamePath "D:\Path\To\Majesty HD"
```

## Notes

- Uses Windows PowerShell. No Python install is required.
- The patch modifies `MajestyHD.exe` by adding a reversible `.msrt` section.
- **Uninstall order matters.** A section can only be removed while it is the
  last one added. If you also installed the **Freestyle Custom CAM Fix**
  (`.mfsp`), remove that before this one. The uninstaller says so if you get it
  the wrong way round.
- The installer creates a backup in `_speedrun_timer_originals` the first time it runs.
- Installs on a clean executable, and alongside the Majesty QoL Utilities. The
  installer prints which quest-start trigger it chose:
  - `hooked directly` on a game without Remember Game Speed.
  - `bridged through Remember Game Speed (.mskp)` when that utility is present,
    since it already owns the same two code sites.

  Either way the timer behaves identically. Install order does not matter.
- Manual return to the main menu before victory/loss does not currently stop the timer, but the next quest starts from zero.
- This repo does not include Majesty game files or assets.

## Non-default game location

The installer finds Steam automatically, including libraries on other drives and
an install folder that has been renamed. If it still cannot find the game, run
the script directly with a path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-SpeedrunTimer.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
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
