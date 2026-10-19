#!/usr/bin/env python3
"""Tarave imports RetroPie Setup menu metadata without rewriting any source."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

SCRIPT = (Path(__file__).resolve().parents[1] /
          "scriptmodules/supplementary/batocera-es-test/retropie-gamelist-sync.py")
spec = importlib.util.spec_from_file_location("tarave_gamelist", SCRIPT)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class RetroPieGamelistTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "orangepi"
        self.original = self.home / ".emulationstation/gamelists/retropie/gamelist.xml"
        self.original.parent.mkdir(parents=True)
        self.target = (self.home / ".local/share/batocera-es-test/.emulationstation"
                       "/gamelists/retropie/gamelist.xml")
        self.xml = ('<?xml version="1.0"?><gameList>'
                    '<game><path>./rpsetup.rp</path><name>RetroPie Setup</name>'
                    '<desc>Manage packages</desc>'
                    '<image>/home/orangepi/RetroPie/retropiemenu/icons/rpsetup.png</image>'
                    '</game><game><path>./retroarch.rp</path>'
                    '<name>RetroArch</name></game></gameList>')
        self.original.write_text(self.xml)

    def test_copies_missing_setup_entries_into_private_gamelists_plural(self):
        snapshot = self.original.read_bytes()
        self.assertEqual(app.sync(self.home, self.target, [self.original]), (2, 0))
        self.assertTrue(self.target.is_file())
        root = ET.parse(self.target).getroot()
        setup = next(g for g in root.findall("game")
                     if app.key(g) == "rpsetup.rp")
        self.assertEqual(setup.findtext("name"), "RetroPie Setup")
        self.assertTrue(setup.findtext("image").endswith("/rpsetup.png"))
        self.assertEqual(self.original.read_bytes(), snapshot)

        # Repeated configuration does not duplicate or change user data.
        first = self.target.read_bytes()
        self.assertEqual(app.sync(self.home, self.target, [self.original]), (0, 0))
        self.assertEqual(self.target.read_bytes(), first)

    def test_merges_missing_entry_and_icon_but_preserves_user_edits(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text(
            '<gameList><game><path>rpsetup.rp</path>'
            '<name>Mi menú personalizado</name></game>'
            '<game><path>./mycustom.rp</path><name>Custom</name></game>'
            '</gameList>')
        old = self.original.read_bytes()
        self.assertEqual(app.sync(self.home, self.target, [self.original]), (1, 2))
        games = ET.parse(self.target).getroot().findall("game")
        self.assertEqual(len(games), 3)
        first = games[0]
        self.assertEqual(first.findtext("name"), "Mi menú personalizado")
        self.assertEqual(first.findtext("desc"), "Manage packages")
        self.assertIn("rpsetup.png", first.findtext("image"))
        self.assertEqual(games[1].findtext("name"), "Custom")
        self.assertEqual(self.original.read_bytes(), old)

    def test_no_official_gamelist_no_new_file(self):
        self.original.unlink()
        self.assertEqual(app.sync(self.home, self.target, [self.original]), (0, 0))
        self.assertFalse(self.target.exists())

    def test_invalid_private_file_preserved(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text("bad XML")
        with self.assertRaises(ET.ParseError):
            app.sync(self.home, self.target, [self.original])
        self.assertEqual(self.target.read_text(), "bad XML")

    def test_symlink_is_never_written(self):
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(self.original)
        with self.assertRaises(ValueError):
            app.sync(self.home, self.target, [self.original])
        self.assertEqual(self.original.read_text(), self.xml)

    def test_skip_invalid_source(self):
        broken = Path(self.temp.name) / "broken.xml"
        broken.write_text("<truncated")
        self.assertEqual(app.sync(self.home, self.target, [broken, self.original]), (2, 0))


if __name__ == "__main__":
    unittest.main()
