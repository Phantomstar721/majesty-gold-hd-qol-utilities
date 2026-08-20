# Majesty Gold HD - Unlock All Quests

A small Windows quality-of-life patch for the Steam version of **Majesty Gold HD**.

It reveals the game's dormant quest-map cheat control, renames it **UNLOCK ALL
QUESTS**, and makes every stock quest available to select and play.

The stock **ERASE VICTORIES** / Reset Quests confirmation and victory reset remain
intact. Confirming that reset also turns off the session unlock and restores the
normal quest locks and purple-cloud overlays immediately.

## Supported game versions

The installer detects and supports both Steam branches:

- **Default Public** (`MajestyHD.exe` 1.5.2.24)
- **beta2 - Steam Multiplayer Support** (`MajestyHD.exe` 1.5.2.28)

## Install

1. Close Majesty Gold HD.
2. Download and unzip the release.
3. Double-click `Install - Unlock All Quests.bat`.
4. Start Majesty and open the quest selection map.
5. Click **UNLOCK ALL QUESTS** in the upper-left corner.

If Windows blocks the patch because the game is under `Program Files`, right-click
the install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Quest Unlocks.bat
```

The uninstaller reverses only this utility's executable edits and its one string
replacement inside each modern `UIData_*.dat` archive. It never restores a whole
file, so other Majesty QoL utilities remain installed.

## Compatibility

This patch deliberately uses the stock, normally hidden cheat menu control. It
does not add, clone, remove, or repurpose any UI record. In particular:

- **Downloadable Quests Shortcut** keeps its compass-icon behavior.
- **Quest Map Drag** keeps its separate code cave and hook.
- **ERASE VICTORIES** keeps its stock callback and confirmation dialog, with a
  post-confirmation continuation that restores the real lock state.
- The UI archives receive only a surgical `Cheat All Quests` to `Unlock All
  Quests` string replacement; entry sizes and offsets are updated in place.

The installer validates every hook and refuses to overwrite unexpected bytes.
It supports an already-patched executable as long as the other patches do not own
the same byte ranges.

The stock 800x600 and 1024x768 UI archives do not contain the dormant control, so
this utility targets the modern 1280-wide-and-larger quest-map layouts.

## Non-default game location

The installer searches Steam libraries automatically. You can also supply a path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-UnlockAllQuests.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Majesty HD"
```

Use `-DryRun` to validate the executable without changing it.

## Technical notes

The modern quest menu still ships with a text control named **Cheat All Quests**
(object `666`), but the executable hides it during menu construction and has no
click dispatch for it. This utility:

1. makes object `666` visible;
2. dispatches its click to a small unused tail of the stock `.text` section;
3. sets a process-local unlock flag and then calls the game's own quest-map
   rebuild routine, which is the same routine the stock Reset Quests path calls;
   and
4. makes the stock quest-eligibility predicate return true while that flag is set.

Because the rebuild is the stock one, the quest tiles and their purple
quest-lock clouds repaint immediately and by exactly the same code path the game
already uses. Nothing about the redraw is reimplemented. After a confirmed Reset
Quests action the patch clears the flag and runs that same rebuild, so the normal
locks come straight back without leaving the map.

The flag lives in an unused byte of the executable's writable, uninitialized data
and therefore exists only in memory. Quest victory data is not fabricated or
rewritten.

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

The verified construction, dispatch, reset, cleanup, refresh, cave, and address
trace for both builds is in [`docs/STOCK-TRACE.md`](docs/STOCK-TRACE.md).
