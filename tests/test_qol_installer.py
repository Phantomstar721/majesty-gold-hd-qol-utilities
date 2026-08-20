from pathlib import Path
import struct
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
import qol_installer as installer


def write_build_fixture(path: Path, build: installer.GameBuild, *, section_count: int = 4) -> None:
    pe_offset = 0x100
    optional_size = 0xE0
    optional_offset = pe_offset + 24
    section_table = optional_offset + optional_size
    stock_length = max(section.raw_offset + section.raw_size for section in build.sections)
    data = bytearray(max(stock_length, section_table + (section_count * 40)))
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, pe_offset)
    data[pe_offset:pe_offset + 4] = b"PE\0\0"
    struct.pack_into("<HH", data, pe_offset + 4, 0x014C, section_count)
    struct.pack_into("<I", data, pe_offset + 8, build.coff_timestamp)
    struct.pack_into("<H", data, pe_offset + 20, optional_size)
    struct.pack_into("<H", data, optional_offset, 0x010B)
    struct.pack_into("<I", data, optional_offset + 28, 0x00400000)
    struct.pack_into("<II", data, optional_offset + 32, 0x1000, 0x0200)
    struct.pack_into("<I", data, optional_offset + 60, 0x0400)
    for index, section in enumerate(build.sections):
        offset = section_table + (index * 40)
        data[offset:offset + 8] = section.name.encode("ascii").ljust(8, b"\0")
        struct.pack_into(
            "<IIII", data, offset + 8,
            section.virtual_size, section.rva, section.raw_size, section.raw_offset,
        )
        struct.pack_into("<I", data, offset + 36, section.characteristics)
    if section_count > 4:
        data[section_table + 160:section_table + 168] = b".test\0\0\0"
    path.write_bytes(data)


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

    def test_detects_both_supported_game_builds(self):
        for expected in installer.SUPPORTED_GAME_BUILDS:
            with self.subTest(build=expected.key):
                path = self.root / f"{expected.key}.exe"
                write_build_fixture(path, expected)
                actual = installer.detect_game_build(path)
                self.assertIsNotNone(actual)
                self.assertEqual(actual.key, expected.key)

    def test_build_detection_allows_appended_qol_sections(self):
        expected = installer.SUPPORTED_GAME_BUILDS[1]
        path = self.root / "patched-beta2.exe"
        write_build_fixture(path, expected, section_count=5)
        self.assertEqual(installer.detect_game_build(path).key, "beta2")

    def test_build_detection_rejects_unknown_timestamp_or_stock_layout(self):
        expected = installer.SUPPORTED_GAME_BUILDS[0]
        path = self.root / "unknown.exe"
        write_build_fixture(path, expected)
        data = bytearray(path.read_bytes())
        struct.pack_into("<I", data, 0x108, 0x12345678)
        path.write_bytes(data)
        self.assertIsNone(installer.detect_game_build(path))

        write_build_fixture(path, expected)
        data = bytearray(path.read_bytes())
        data[0x1F8:0x200] = b".wrong\0\0"
        path.write_bytes(data)
        self.assertIsNone(installer.detect_game_build(path))

    def test_build_detection_rejects_malformed_files(self):
        path = self.root / "not-a-pe.exe"
        path.write_bytes(b"MZ")
        self.assertIsNone(installer.detect_game_build(path))

        expected = installer.SUPPORTED_GAME_BUILDS[0]
        write_build_fixture(path, expected)
        path.write_bytes(path.read_bytes()[:0x400])
        self.assertIsNone(installer.detect_game_build(path))

    def test_command_passes_selected_exe_parent(self):
        command = installer.powershell_command(Path("patch.ps1"), Path(r"D:\Games\Majesty HD\MajestyHD.exe"), True)
        self.assertEqual(command[-3:], ["-GamePath", r"D:\Games\Majesty HD", "-DryRun"])

    def test_every_utility_has_bundled_scripts(self):
        for utility in installer.UTILITIES:
            self.assertTrue(installer.utility_script(utility.install_script).is_file(), utility.name)
            self.assertTrue(installer.utility_script(utility.uninstall_script).is_file(), utility.name)

    def test_generic_visitor_lists_is_available(self):
        self.assertEqual(installer.utility_by_key("generic-visitors").name, "Generic Visitor Lists")

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
