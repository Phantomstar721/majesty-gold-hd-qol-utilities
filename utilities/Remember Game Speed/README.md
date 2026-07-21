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

After that, Majesty writes `MajestySessionSpeed.bin` in its install folder and
uses that saved speed when new quests start, saved games load, and the game is
relaunched.

If Windows blocks the patch because the game is under `Program Files`,
right-click the install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Stock Game Speed.bat
```

The saved `MajestySessionSpeed.bin` file is left in the game folder. It is
harmless, and keeping it means your speed setting is still there if you
reinstall.

To reset the remembered speed, delete `MajestySessionSpeed.bin` from the Majesty
install folder or change the slider again after reinstalling the patch.

## What It Changes

The installer patches `MajestyHD.exe` so the game can:

- Save the selected speed when the in-quest settings slider changes.
- Apply the saved speed to the live game object when saved games load.
- Apply the saved speed during new-quest setup before the game falls back to its
  default speed.
- Load the saved speed from disk on a fresh Majesty launch.
- Coexist with the earlier Remember Active Mods patch by adding a separate
  `.mskp` section after any existing `.mpst` section.

This is an EXE patch, not a Steam Workshop mod.

## Compatibility

This patch targets the Steam release of Majesty Gold HD tested during this
project. If Steam updates `MajestyHD.exe`, run the installer again. The installer
checks the bytes it plans to patch and stops if the executable is not in a known
stock or already-patched state.
