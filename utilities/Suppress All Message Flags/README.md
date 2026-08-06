# Majesty Gold HD - Suppress All Message Flags

A small local patcher for the Steam version of **Majesty Gold HD**.

It suppresses scripted message flags completely: no banner icon, no message-flag
sound, and no forced mini-camera focus on the flag target. Reward flags, ordinary
selection sounds, and normal camera controls are unchanged.

## Install

1. Close Majesty Gold HD.
2. Download and unzip the latest release.
3. Double-click `Install - Suppress All Message Flags.bat`.
4. Launch Majesty Gold HD normally from Steam.

If Windows blocks the patch because the game is under `Program Files`, right-click
the install BAT and choose **Run as administrator**.

## Uninstall

Close Majesty Gold HD, then double-click:

```text
Uninstall - Restore Message Flags.bat
```

This restores the stock message-flag behavior and leaves other QOL patches intact.

## What It Changes

This is a six-byte, version-guarded edit to `MajestyHD.exe`. The patched routine is
the engine's message-flag constructor. In the stock executable that one routine:

- creates the `MSGF` object and its `ARE1` banner action;
- plays the `ME02` / `EBE0` notification sound; and
- optionally sends the target to the mini-camera when `ZoomMessageFlags` is enabled.

The patch changes the constructor into an immediate return. The script-level
`MessageFlag` command still completes normally, but no message-flag object or any
of those follow-on effects is created. See [docs/research.md](docs/research.md) for
the reverse-engineering evidence and boundaries.

## Compatibility

This is a local executable patch, not a Steam Workshop mod. The patcher recognizes
only the expected Steam Majesty Gold HD 1.5.2.24 bytes and its own patched bytes;
it refuses to guess if another edit owns the same routine.

The patch changes no shared QOL hook or appended executable section, so install
and uninstall order do not matter. The repo contains no Majesty game assets or
game files.

## Non-default game location

The installer finds Steam automatically, including libraries on other drives and
an install folder that has been renamed. If it still cannot find the game, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-SuppressAllMessageFlags.ps1 -GamePath "D:\Path\To\Majesty HD"
```

Add `-DryRun` to inspect the executable without changing it.

## If you ever need a clean executable

The installer creates `_suppress_message_flags_originals` in the game folder as a
convenience snapshot. That file may already contain other patches and is not used
to uninstall. Uninstalling reverses only this utility's six bytes.

For a guaranteed unmodified executable, let Steam do it:

1. Right-click **Majesty Gold HD** in your Steam library
2. **Properties** > **Installed Files**
3. **Verify integrity of game files**

Steam will replace `MajestyHD.exe` with the original. You can then reinstall
whichever utilities you want.
