from pathlib import Path
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
import qol_installer as installer


class InstallerTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_reads_renamed_install_from_manifest(self):
        manifest = self.root / "appmanifest_73230.acf"
        manifest.write_text('"AppState" { "installdir" "My Majesty" }', encoding="utf-8")
        self.assertEqual(installer.steam_installdir(manifest), "My Majesty")

    def test_reads_modern_library_vdf_paths(self):
        vdf = self.root / "libraryfolders.vdf"
        vdf.write_text('"path" "D:\\\\SteamLibrary"\n"path" "E:\\\\Games"', encoding="utf-8")
        self.assertEqual(installer.steam_libraries_from_vdf(vdf), [Path(r"D:\SteamLibrary"), Path(r"E:\Games")])

    def test_intro_detection(self):
        prefs = self.root / "MajXPrefs"
        prefs.write_text("<DataGroups><IntroVideo>0</IntroVideo></DataGroups>", encoding="ascii")
        self.assertTrue(installer.intro_is_disabled(prefs))
        prefs.write_text("<DataGroups><IntroVideo>1</IntroVideo></DataGroups>", encoding="ascii")
        self.assertFalse(installer.intro_is_disabled(prefs))

    def test_command_passes_selected_exe_parent(self):
        command = installer.powershell_command(Path("patch.ps1"), Path(r"D:\Games\Majesty HD\MajestyHD.exe"), True)
        self.assertEqual(command[-3:], ["-GamePath", r"D:\Games\Majesty HD", "-DryRun"])

    def test_every_utility_has_bundled_scripts(self):
        for utility in installer.UTILITIES:
            self.assertTrue(installer.utility_script(utility.install_script).is_file(), utility.name)
            self.assertTrue(installer.utility_script(utility.uninstall_script).is_file(), utility.name)

    def test_generic_visitor_lists_is_last_for_safe_section_order(self):
        self.assertEqual(installer.UTILITIES[-1].key, "generic-visitors")

    @mock.patch("qol_installer.subprocess.run")
    def test_detection_recognizes_installed_phrase(self, run):
        run.return_value = mock.Mock(returncode=0, stdout="MajestyHD.exe: click-drag panning is already installed.", stderr="")
        utility = installer.utility_by_key("map-drag")
        self.assertEqual(installer.detect_utility(utility, Path(r"C:\Games\MajestyHD.exe")), ("installed", "Installed"))

    @mock.patch("qol_installer.subprocess.run")
    def test_detection_does_not_call_partial_multi_file_patch_installed(self, run):
        run.return_value = mock.Mock(returncode=0, stdout="AlreadyPatched executable\nWouldPatch UIData_English.dat", stderr="")
        utility = installer.utility_by_key("quests-shortcut")
        self.assertEqual(installer.detect_utility(utility, Path(r"C:\Games\MajestyHD.exe")), ("available", "Available"))

    @mock.patch("qol_installer.subprocess.run")
    def test_detection_surfaces_incompatible_executable(self, run):
        run.return_value = mock.Mock(returncode=1, stdout="", stderr="Unexpected bytes in MajestyHD.exe")
        utility = installer.utility_by_key("suppress-flags")
        status, detail = installer.detect_utility(utility, Path(r"C:\Games\MajestyHD.exe"))
        self.assertEqual(status, "error")
        self.assertIn("Unexpected bytes", detail)


if __name__ == "__main__":
    unittest.main()
