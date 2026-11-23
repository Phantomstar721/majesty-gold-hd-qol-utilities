# Message Flag Controls

Adds two in-quest controls. The first toggles message flags and remembers your
choice between sessions. The second clears existing message flags without
changing that preference. Reward flags keep their normal behavior.

Select this package under **Merge** in a Majesty Mod Manager build that
supports `stock.message-flag-controls.v1`. Choose **Prepare Selected Mods** and
launch Majesty through the Manager.

## Build the source package

From this directory, run the builder with the Python environment used by Mod
Manager.

```powershell
python .\scripts\Build-TestPackage.py
```

Use `--manager` to point to a compatible source checkout in another location.
The builder writes the two-file package and ZIP under `dist/`.
