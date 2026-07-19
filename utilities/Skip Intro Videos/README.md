# Majesty Gold HD - Skip Intro Videos

One-click helper for Majesty Gold HD on Steam that skips the intro videos and goes
straight to the main menu.

## Quick Start

1. Download this project as a ZIP from GitHub.
2. Extract the ZIP anywhere, such as your Desktop.
3. Double-click `Enable Skip Intro Videos.bat`.
4. Launch Majesty Gold HD normally from Steam.

That is it. The change is saved in your Majesty preferences and should keep working
across future launches.

## Undo The Change

Double-click:

```text
Restore Intro Videos.bat
```

## What It Changes

Majesty Gold HD already supports skipping intro videos, but the setting is not exposed
clearly in the game options. This helper edits your per-user preferences file:

```text
Documents\My Games\MajestyHD\MajXPrefs
```

It sets:

```xml
<IntroVideo>0</IntroVideo>
```

Before changing the file, it creates a timestamped backup next to it.

## Manual Steam Launch Option

You can also skip the intro videos by adding this Steam launch option:

```text
-nointro
```

This helper exists for players who would rather double-click one file than dig through
Steam settings.

## Steam Workshop Feasibility

A Workshop-only version is probably not practical. Majesty loads Workshop mods from the
in-game Mods menu, after the executable has already started and after the intro-video
decision has been made. Workshop packages are good for quest/data changes, but they do
not appear to be able to run pre-launch setup or change startup arguments.

## Safety

This utility does not modify the Steam install folder and does not include game assets.
It only edits the per-user preferences file under `Documents\My Games\MajestyHD`.
