"""Validate and stage this mod's source package; never compose a Manager profile.

Run with the Manager's Python environment. No game launch, install, registry
generation, or native patch is performed. Source must use the admitted Manager
contract before this tool can produce a package.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_NAME = "MessageFlagControls"
FILES = ("MessageFlagControls.mmxml", "mod-definition.json")


def find_manager():
    for parent in ROOT.parents:
        for directory in (parent, parent / "tools"):
            candidate = directory / "majesty-gold-hd-mod-manager"
            if (candidate / "src" / "majesty_cam" / "package.py").is_file():
                return candidate
    return None


def build(manager):
    source = ROOT / "src" / PACKAGE_NAME
    if not source.is_dir():
        raise ValueError("Package source is not authored yet: waiting for the admitted Manager contract.")
    if source.resolve() != source:
        raise ValueError("Source directory must not redirect outside its canonical path.")
    actual = {p.relative_to(source).as_posix() for p in source.rglob("*") if p.is_file()}
    if actual != set(FILES) or any(p.is_symlink() for p in source.rglob("*")):
        raise ValueError("Unexpected source inventory; review the runtime contract before changing the whitelist.")
    sys.path.insert(0, str(manager.resolve() / "src"))
    from majesty_cam.package import load_package
    package = load_package(source)
    if package.definition is None:
        raise ValueError("The native-controls package requires a validated definition.")
    declaration = json.loads((source / "mod-definition.json").read_text(encoding="utf-8"))
    if (declaration.get("custom_buildings") != [] or
            declaration.get("runtime_features") != [{"type": "stock.message-flag-controls.v1"}]):
        raise ValueError("This package must declare only the admitted message-controls feature.")
    destination = ROOT / "dist" / PACKAGE_NAME
    if destination.resolve() != ROOT / "dist" / PACKAGE_NAME:
        raise ValueError("Staging destination redirects outside its canonical path.")
    if destination.exists():
        old = {p.relative_to(destination).as_posix() for p in destination.rglob("*") if p.is_file()}
        if old - set(FILES) or any(p.is_symlink() for p in destination.rglob("*")):
            raise ValueError("Staging contains unexpected files; refusing to erase or carry them forward.")
    destination.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        shutil.copyfile(source / name, destination / name)
    load_package(destination)
    archive = ROOT / "dist" / (PACKAGE_NAME + ".zip")
    if archive.is_symlink():
        raise ValueError("Archive destination must not be a symlink.")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for name in FILES:
            output.write(destination / name, PACKAGE_NAME + "/" + name)
    report = {
        "package": str(destination), "archive": str(archive),
        "validation": "Manager package parser only; runtime readiness/live acceptance are separate gates",
        "files": {name: hashlib.sha256((destination / name).read_bytes()).hexdigest() for name in FILES},
    }
    report_path = ROOT / "dist" / "test-package-report.json"
    if report_path.is_symlink():
        raise ValueError("Report destination must not be a symlink.")
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manager", type=Path, help="Path to a compatible Mod Manager source checkout")
    args = parser.parse_args()
    manager = args.manager or find_manager()
    if manager is None:
        parser.error("Majesty Mod Manager checkout not found. Pass --manager with its path.")
    try:
        print(json.dumps(build(manager), indent=2))
    except (ValueError, OSError, ImportError) as error:
        parser.exit(1, str(error) + "\n")
