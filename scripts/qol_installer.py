"""Core services for the Majesty Gold HD QoL Utilities window."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Callable
import xml.etree.ElementTree as ET


DEFAULT_GAME = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Majesty HD")
STEAM_APP_ID = "73230"


@dataclass(frozen=True)
class Utility:
    key: str
    name: str
    description: str
    install_script: str
    uninstall_script: str
    installed_phrase: str = ""
    preference_only: bool = False


UTILITIES = (
    Utility("skip-intro", "Skip Intro Videos", "Starts Majesty at the main menu instead of playing the opening movies.",
            r"Skip Intro Videos\scripts\Install-NoIntro.ps1", r"Skip Intro Videos\scripts\Uninstall-NoIntro.ps1", preference_only=True),
    Utility("quests-shortcut", "Downloadable Quests Shortcut", "Makes the compass icon a fixed shortcut to downloadable and custom quests.",
            r"Downloadable Quests Shortcut\scripts\Install-DownloadableQuestShortcut.ps1", r"Downloadable Quests Shortcut\scripts\Restore-CustomQuestButton.ps1", "AlreadyPatched"),
    Utility("map-drag", "Quest Map Drag", "Adds left-click drag panning to the quest map.",
            r"Quest Map Drag\scripts\Install-QuestMapDragPan.ps1", r"Quest Map Drag\scripts\Restore-QuestMapDragPan.ps1", "already installed"),
    Utility("unlock-quests", "Unlock All Quests", "Adds an UNLOCK ALL QUESTS control so every stock quest can be selected for the session.",
            r"Unlock All Quests\scripts\Install-UnlockAllQuests.ps1", r"Unlock All Quests\scripts\Restore-UnlockAllQuests.ps1", "would leave installed"),
    Utility("suppress-flags", "Suppress All Message Flags", "Hides scripted message banners, their sound, and forced mini-camera focus.",
            r"Suppress All Message Flags\scripts\Install-SuppressAllMessageFlags.ps1", r"Suppress All Message Flags\scripts\Restore-SuppressAllMessageFlags.ps1", "already suppressed"),
    Utility("remember-mods", "Remember Active Mods", "Restores the Mods > Active list automatically on future launches.",
            r"Remember Active Mods\scripts\Install-ModPersistence.ps1", r"Remember Active Mods\scripts\Restore-ModPersistence.ps1", "already installed"),
    Utility("remember-speed", "Remember Game Speed", "Saves and restores the in-quest game-speed setting.",
            r"Remember Game Speed\scripts\Install-RememberGameSpeed.ps1", r"Remember Game Speed\scripts\Restore-RememberGameSpeed.ps1", "already installed"),
    Utility("remember-zoom", "Remember Camera Zoom", "Saves and restores the in-quest camera zoom setting.",
            r"Remember Camera Zoom\scripts\Install-RememberCameraZoom.ps1", r"Remember Camera Zoom\scripts\Restore-RememberCameraZoom.ps1", "already installed"),
    Utility("generic-visitors", "Generic Visitor Lists", "Displays nonhero visitors with stock monster icons and XP-derived Threat Ranks.",
            r"Generic Visitor Lists\scripts\Install-GenericVisitorLists.ps1", r"Generic Visitor Lists\scripts\Restore-GenericVisitorLists.ps1", "Threat Ranks are already installed"),
)


def resource_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS"))
    return Path(__file__).resolve().parents[1]


def utility_script(relative: str) -> Path:
    return resource_root() / "utilities" / Path(relative)


def is_game_exe(path: Path) -> bool:
    return path.is_file() and path.name.lower() == "majestyhd.exe"


def discover_game_exes() -> list[Path]:
    candidates: list[Path] = []
    env_game = os.environ.get("MAJESTY_HD_DIR")
    if env_game:
        supplied = Path(env_game)
        candidates.append(supplied if supplied.suffix.lower() == ".exe" else supplied / "MajestyHD.exe")
    candidates.append(DEFAULT_GAME / "MajestyHD.exe")
    for steam_root in steam_roots():
        libraries = [steam_root, *steam_libraries_from_vdf(steam_root / "steamapps" / "libraryfolders.vdf")]
        for library in libraries:
            steamapps = library / "steamapps"
            candidates.append(steamapps / "common" / "Majesty HD" / "MajestyHD.exe")
            installdir = steam_installdir(steamapps / f"appmanifest_{STEAM_APP_ID}.acf")
            if installdir:
                candidates.append(steamapps / "common" / installdir / "MajestyHD.exe")
    unique: list[Path] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = os.path.normcase(str(candidate))
        if key not in seen:
            unique.append(candidate)
            seen.add(key)
    return unique


def resolve_game_exe() -> Path | None:
    return next((path for path in discover_game_exes() if is_game_exe(path)), None)


def steam_roots() -> list[Path]:
    roots: list[Path] = []
    for hive, subkey, value in (
        ("HKCU", r"Software\Valve\Steam", "SteamPath"),
        ("HKLM", r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
        ("HKLM", r"SOFTWARE\Valve\Steam", "InstallPath"),
    ):
        found = read_registry_path(hive, subkey, value)
        if found:
            roots.append(found)
    for env_name in ("ProgramFiles(x86)", "ProgramFiles"):
        if os.environ.get(env_name):
            roots.append(Path(os.environ[env_name]) / "Steam")
    roots.extend((Path(r"C:\Program Files (x86)\Steam"), Path(r"C:\Program Files\Steam")))
    return roots


def read_registry_path(hive: str, subkey: str, value_name: str) -> Path | None:
    try:
        import winreg
        root = winreg.HKEY_CURRENT_USER if hive == "HKCU" else winreg.HKEY_LOCAL_MACHINE
        with winreg.OpenKey(root, subkey) as key:
            value, _kind = winreg.QueryValueEx(key, value_name)
        return Path(value) if value else None
    except (ImportError, OSError):
        return None


def default_prefs_path() -> Path:
    """Match PowerShell's MyDocuments lookup, including redirected folders."""
    documents = read_registry_path(
        "HKCU", r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders", "Personal"
    )
    if documents:
        documents = Path(os.path.expandvars(str(documents)))
    else:
        documents = Path.home() / "Documents"
    return documents / "My Games" / "MajestyHD" / "MajXPrefs"


def steam_installdir(manifest: Path) -> str | None:
    try:
        text = manifest.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    match = re.search(r'"installdir"\s+"([^"]+)"', text, re.IGNORECASE)
    return match.group(1) if match else None


def steam_libraries_from_vdf(path: Path) -> list[Path]:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return []
    return [Path(value.replace("\\\\", "\\")) for value in re.findall(r'"path"\s+"([^"]+)"', text, re.IGNORECASE)]


def intro_is_disabled(prefs: Path | None = None) -> bool:
    prefs = prefs or default_prefs_path()
    try:
        root = ET.parse(prefs).getroot()
        node = root.find("IntroVideo")
        return node is not None and (node.text or "").strip() == "0"
    except (OSError, ET.ParseError):
        return False


def powershell_command(script: Path, game_exe: Path, dry_run: bool = False) -> list[str]:
    args = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    if "Skip Intro Videos" in str(script):
        args.extend(("-PrefsPath", str(default_prefs_path())))
    else:
        args.extend(("-GamePath", str(game_exe.parent)))
    if dry_run:
        args.append("-DryRun")
    return args


def subprocess_window_options() -> dict[str, object]:
    if os.name != "nt":
        return {}
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    return {"startupinfo": startupinfo, "creationflags": subprocess.CREATE_NO_WINDOW}


def run_utility(utility: Utility, action: str, game_exe: Path) -> subprocess.CompletedProcess[str]:
    relative = utility.install_script if action == "install" else utility.uninstall_script
    script = utility_script(relative)
    if not script.is_file():
        raise FileNotFoundError(f"Bundled patch script is missing: {script}")
    return subprocess.run(
        powershell_command(script, game_exe), capture_output=True, text=True,
        encoding="utf-8", errors="replace", check=False, **subprocess_window_options(),
    )


def detect_utility(utility: Utility, game_exe: Path) -> tuple[str, str]:
    if utility.preference_only:
        return ("installed", "Installed") if intro_is_disabled() else ("available", "Available")
    script = utility_script(utility.install_script)
    try:
        completed = subprocess.run(
            powershell_command(script, game_exe, dry_run=True), capture_output=True,
            text=True, encoding="utf-8", errors="replace", check=False,
            **subprocess_window_options(),
        )
    except OSError as exc:
        return "error", str(exc)
    output = "\n".join((completed.stdout, completed.stderr)).strip()
    if completed.returncode != 0:
        return "error", output or f"Inspection exited with code {completed.returncode}."
    lowered = output.lower()
    # Multi-file utilities can report some pieces as AlreadyPatched and others
    # as WouldPatch. Only call the complete utility installed when no piece is
    # still waiting to be applied.
    installed = utility.installed_phrase.lower() in lowered and "wouldpatch" not in lowered
    return ("installed", "Installed") if installed else ("available", "Available")


def utility_by_key(key: str) -> Utility:
    return next(utility for utility in UTILITIES if utility.key == key)
