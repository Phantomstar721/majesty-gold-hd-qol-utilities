# Majesty Gold HD — Lower Tracking Window

Changes the lower-left mini-camera's existing **Autoscan** control into a
stock-style **Track Selected** button. Select a hero, building, monster, flag,
or other normal dialog target and click that button to assign the target to
Majesty's second tracking slot. The original dialog Track buttons continue to
control the upper window exactly as before.

The installer detects and supports both Steam branches:

- **Default Public Version** (`1.5.2.24`)
- **beta2 / Steam Multiplayer Support** (`1.5.2.28`)

## Install

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Run `Install - Lower Tracking Window.bat`.
4. Start a quest, select a target, and click the former Autoscan button in the
   lower tracking window's controller row.

If Windows blocks the patch because Majesty is under `Program Files`,
right-click the install BAT and choose **Run as administrator**.

Run `Uninstall - Restore Tracking Windows.bat` to remove only this patch and
restore the stock executable and interface records it owns.

## What it changes

The patch uses Majesty's stock tracking implementation rather than adding a
second camera controller:

- changes only the existing lower Autoscan control's `INTG` artwork from its
  stock Autoscan frame to the stock Track frame in each applicable
  `UIData_*.dat` APMK layout;
- changes that record's stock ID `0x239E` to the private ID `0x7F01`, bypassing
  the stock Autoscan dispatcher while retaining its native visible layer;
- routes the private lower-window control ID through the stock MainFrame
  controller;
- displays `Track selected target in the lower Tracking Window.` through the
  tracking controller's stock tooltip string-copy path;
- clones the existing dialog Track action, changing only the stock tracking
  slot argument from `1` (upper) to `2` (lower);
- retains the stock target registration, following, label refresh, target-loss
  cleanup, redraw, and manager destruction lifecycle.

The UI edit consists of two same-size four-byte replacements and is reversible.
The executable hooks are guarded by the detected build, exact stock instruction
bytes, and the first four stock PE section layouts. The patch can coexist with
the other Majesty QoL utilities and leaves an inert reusable section if a later
patch section prevents safe physical truncation during uninstall.

## Compatibility and safety

This is a local executable and UIData patch, not a Workshop data mod. It refuses
unknown game builds, unexpected hook bytes, duplicate/private control records,
and corrupt private payloads before changing any file. Install and uninstall
touch only the two APMK values, two executable hooks, and private `.mltw` section
owned by this utility.

The installer finds Steam libraries automatically. For a nonstandard or copied
game folder, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-LowerTrackingWindow.ps1 -GamePath "D:\Path\To\Majesty HD"
```

Add `-DryRun` to inspect the detected build and planned changes without writing.

See [docs/stock-trace.md](docs/stock-trace.md) for the recovered stock identity
table, dispatch path, ownership lifecycle, and Default/beta2 address profiles.
