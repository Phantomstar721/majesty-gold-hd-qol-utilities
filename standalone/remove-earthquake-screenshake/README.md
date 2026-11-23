# Majesty Gold HD — Remove Earthquake Screenshake

Removes the camera shake from the Northern Expansion Earthquake spell and
prevents Earthquake from clearing the game's Tracking Window targets.
Damage, particles, sound, duration, and targeting remain stock.

## What changes

The package replaces the stock `Earthquake_Unit_Created` GPL function with an
exact copy that omits only this native call:

```gpl
$StartEarthquakeSpell ( ThisAgent, 5, 30, 6000 );
```

That native routine is responsible for both effects: it clears tracking slots
1–4 to `none`, shakes all four mini-cameras and the main camera, and does not
restore the previous tracking targets afterward.

## Build

```powershell
.\scripts\Build-RemoveEarthquakeScreenshake.ps1
```

The ready-to-test package is written to:

```text
dist\RemoveEarthquakeScreenshake
```

The package contains the `.mmxml` manifest, compiled
`Data\RemoveEarthquakeScreenshake.bcd`, and matching
`RemoveEarthquakeScreenshake.gpl` source. The manifest registers the source using
Majesty's normal `Source` entry so script-merging tools can preserve this change
when combining it with other mods. Majesty still runs the compiled script;
this remains an independently loadable Standard mod.

## Test locally

Copy the `dist\RemoveEarthquakeScreenshake` folder into:

```text
Documents\My Games\MajestyHD\Mods
```

No custom installer or launcher is required. Start Majesty normally, enable
**Remove Earthquake Screenshake** in the Mods menu, set one or more Tracking
Window targets, and cast or trigger Earthquake. The spell should still damage
buildings and display its normal effects, but the main map and Tracking Windows
should not shake and their targets should remain intact.

## Compatibility

This is a GPL replacement mod. Another active mod that also replaces
`Earthquake_Unit_Created` creates a GPL merge conflict; combine the two source
edits with Majesty Gold HD CAM Merger rather than relying on load order.
