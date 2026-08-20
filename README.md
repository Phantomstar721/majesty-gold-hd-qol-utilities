# Majesty Gold HD QoL Utilities

A single Windows app for installing the Majesty Gold HD quality-of-life utilities.
Each improvement can be installed or removed on its own, or you can use **Install
All** and **Uninstall All**.

The app supports both Steam game builds:

- **Default Public Version** (`1.5.2.24`)
- **beta2 / Steam Multiplayer Support** (`1.5.2.28`)

## Use it

1. Close Majesty Gold HD.
2. Download `Majesty QoL Utilities.exe` from this Workshop item/release.
3. Double-click the EXE and approve the Windows administrator prompt.
4. Check the detected `MajestyHD.exe`, then choose the utilities you want.
5. Launch Majesty normally through Steam.

The app finds the game in your Steam libraries, including libraries on other
drives. Use **Choose EXE** if you want to patch a different Majesty installation.
It identifies which supported game build is selected, displays that version,
and marks utilities it recognizes as **Installed**. Build detection continues
to work after QoL patch sections have been added; an unknown executable is
reported before any executable-patching utility can run.
Use the **Full Patch Details** link in the app footer to open this GitHub page
for implementation notes, source code, and individual utility documentation.

Every bundled utility can be installed or removed independently in any order.
When a later patch section prevents safe physical truncation, uninstalling
still restores all behavior immediately and leaves only inert private storage
that the same utility can reuse on a later install.

If you switch between Steam's public and beta2 branches, reopen this app after
Steam finishes updating and install the utilities for the newly selected build.
The executable patches use separate guarded address profiles, and UIData
originals are kept build-specific so one branch is never restored over the
other.

The download contains no game files. It applies small, version-checked changes
to the copy of Majesty Gold HD you already own. Windows may show a SmartScreen
warning because this community-built EXE is not code-signed; use **More info >
Run anyway** only if you downloaded it from the official Workshop item/release.

## Included utilities

- **Skip Intro Videos** — starts at the main menu instead of playing the intro.
- **Downloadable Quests Shortcut** — makes the compass icon a fixed shortcut to
  downloadable and custom quests.
- **Quest Map Drag** — adds left-click drag panning to the quest map.
- **Unlock All Quests** — makes every stock quest selectable for the session.
- **Suppress All Message Flags** — hides scripted message banners, their sound,
  and forced mini-camera focus.
- **Remember Active Mods** — restores your active-mod list on later launches.
- **Remember Game Speed** — saves and restores the in-quest speed setting.
- **Remember Camera Zoom** — saves and restores the camera zoom setting.
- **Generic Visitor Lists** — lets building visitor lists render nonhero units
  with stock monster icons, live name/action/HP data, and a Threat Rank.

### Monster Threat Rank

Generic Visitor Lists uses each monster's stock `ATTRIB_LevelXP` kill reward,
sourced from its character XML `<Experience value="..."/>`, as a generic
strength reference. It divides the 48 stock positive-XP monsters into eight
roughly even groups while keeping equal XP values together:

| Threat Rank | Monster XP |
| --- | ---: |
| 1 | 1-230 |
| 2 | 231-400 |
| 3 | 401-500 |
| 4 | 501-900 |
| 5 | 901-1500 |
| 6 | 1501-2000 |
| 7 | 2001-3500 |
| 8 | 3501+ |

Threat Rank is a mod-authored display convention, not a recovered stock
monster-level system. It changes only the number painted in a nonhero visitor
row and does not alter the unit, its XP reward, or gameplay. Custom monsters
participate automatically when they define a positive stock-style
`<Experience>` value.

## If the app reports an unsupported build or unexpected EXE data

Confirm Steam is set to either **Default Public Version** or **beta2**, then
remove any unrelated Majesty EXE patches you installed separately. If you need
a guaranteed stock executable for the selected branch, let Steam refresh it:

1. Open your Steam Library and right-click **Majesty Gold HD**.
2. Choose **Properties > Installed Files**.
3. Select **Verify integrity of game files**.
4. When Steam finishes, reopen this app and install the utilities you want.

Steam verification replaces `MajestyHD.exe` with the stock version, so all local
EXE patches need to be reinstalled afterward. It does not remove Workshop
subscriptions or normal save files.

## Run or build from source

Python 3.9 or newer is required only for source development:

```powershell
.\run_installer.cmd
py -3 -m unittest discover -s tests
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Exe.ps1
```

The build produces the standalone `Majesty QoL Utilities.exe`; players do not
need Python or PowerShell modules. The app embeds and runs each utility's
existing version-checked PowerShell patcher.
