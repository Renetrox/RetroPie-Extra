#!/usr/bin/env python3
"""Regression tests for clean-install Tarave RetroPie menu bootstrap."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

SOURCE = (Path(__file__).resolve().parents[1] /
          "scriptmodules/supplementary/batocera-es-test/bootstrap-retropiemenu.py")
spec = importlib.util.spec_from_file_location("tarave_rpbootstrap", SOURCE)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class FreshRetroPieMenuTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.home = Path(scratch.name) / "orangepi"
        self.home.mkdir()
        self.private = self.home / ".local/share/batocera-es-test"
        self.setup = self.home / "RetroPie-Setup"
        self.setup.mkdir()
        (self.setup / "retropie_packages.sh").write_text("#!/bin/bash\n")
        self.icons = self.setup / "scriptmodules/supplementary/retropiemenu/icons"
        self.icons.mkdir(parents=True)
        (self.icons / "rpsetup.png").write_bytes(b"PNG fixture")
        self.gamelist = self.private / ".emulationstation/gamelists/retropie/gamelist.xml"
        self.overlay = self.private / ".emulationstation/es_systems_legacy_import.cfg"
        self.menu = self.private / "retropiemenu"

    def test_fresh_install_creates_independent_menu_xml_icons_and_system(self):
        setup_bytes = (self.setup / "retropie_packages.sh").read_bytes()
        shortcuts, games = app.main(self.home, self.private, self.setup)
        self.assertEqual(shortcuts, len(app.MENU))
        self.assertEqual(games, len(app.MENU))
        self.assertTrue((self.menu / "rpsetup.rp").is_file())
        self.assertEqual((self.menu / "icons/rpsetup.png").read_bytes(),
                         b"PNG fixture")
        root = ET.parse(self.gamelist).getroot()
        game = next(x for x in root.findall("game")
                    if x.findtext("path") == "./rpsetup.rp")
        self.assertEqual(game.findtext("name"), "RetroPie Setup")
        self.assertEqual(game.findtext("image"),
                         str(self.menu / "icons/rpsetup.png"))
        systems = ET.parse(self.overlay).getroot()
        system = systems.find("./system")
        self.assertEqual(system.findtext("name"), "retropie")
        self.assertEqual(system.findtext("path"), str(self.menu))
        self.assertIn("retropiemenu launch %ROM%", system.findtext("command"))
        self.assertEqual((self.setup / "retropie_packages.sh").read_bytes(),
                         setup_bytes)
        self.assertFalse((self.home / ".emulationstation").exists())
        self.assertFalse((self.home / "RetroPie/retropiemenu").exists())

        # Idempotent: no duplicated game entries or overwritten user assets.
        prev = self.gamelist.read_bytes()
        self.assertEqual(app.main(self.home, self.private, self.setup), (0, 0))
        self.assertEqual(self.gamelist.read_bytes(), prev)

    def test_existing_retropie_menu_copies_old_assets_and_keeps_private_edits(self):
        old_menu = self.home / "RetroPie/retropiemenu"
        old_menu.mkdir(parents=True)
        (old_menu / "rpsetup.rp").touch()
        (old_menu / "custom.sh").write_text("#!/bin/bash\\necho custom\\n")
        (old_menu / "custom.sh").chmod(0o755)
        (old_menu / "icons").mkdir()
        (old_menu / "icons/custom.png").write_bytes(b"custom icon")
        self.gamelist.parent.mkdir(parents=True)
        self.gamelist.write_text(
            '<gameList><game><path>./rpsetup.rp</path>'
            '<name>Mi RetroPie personalizado</name></game></gameList>')
        self.overlay.write_text(
            '<systemList><system><name>wine</name><path>/wine</path>'
            '</system></systemList>')
        snap = (old_menu / "rpsetup.rp").read_bytes()
        app.main(self.home, self.private, self.setup)
        root = ET.parse(self.gamelist).getroot()
        self.assertEqual(root.findall("game")[0].findtext("name"),
                         "Mi RetroPie personalizado")
        self.assertEqual(len([x for x in root.findall("game")
                              if x.findtext("path") == "./rpsetup.rp"]), 1)
        self.assertEqual([x.findtext("name") for x in
                          ET.parse(self.overlay).getroot().findall("system")],
                         ["wine", "retropie"])
        self.assertEqual((old_menu / "rpsetup.rp").read_bytes(), snap)
        self.assertEqual((self.menu / "custom.sh").read_bytes(),
                         (old_menu / "custom.sh").read_bytes())
        self.assertTrue((self.menu / "custom.sh").stat().st_mode & 0o111)
        self.assertEqual((self.menu / "icons/custom.png").read_bytes(),
                         b"custom icon")
        retro = next(x for x in ET.parse(self.overlay).getroot().findall("system")
                     if x.findtext("name") == "retropie")
        self.assertEqual(retro.findtext("path"), str(self.menu))

    def test_incomplete_prior_private_retropie_is_safely_completed(self):
        self.overlay.parent.mkdir(parents=True)
        self.overlay.write_text(
            '<systemList><system><name>j2me</name><path>/j2me</path>'
            '<extension>.jar</extension><command>java %ROM%</command>'
            '</system></systemList>')
        self.gamelist.parent.mkdir(parents=True, exist_ok=True)
        self.gamelist.write_text(
            '<gameList><game><path>./mycustom.rp</path>'
            '<name>My custom item</name></game></gameList>')
        app.main(self.home, self.private, self.setup)
        systems = ET.parse(self.overlay).getroot().findall("system")
        self.assertEqual([s.findtext("name") for s in systems], ["j2me", "retropie"])
        games = ET.parse(self.gamelist).getroot().findall("game")
        self.assertEqual(games[0].findtext("name"), "My custom item")

    def test_bad_xml_cannot_be_overwritten(self):
        self.gamelist.parent.mkdir(parents=True, exist_ok=True)
        self.gamelist.write_text("invalid")
        with self.assertRaises(ET.ParseError):
            app.main(self.home, self.private, self.setup)
        self.assertEqual(self.gamelist.read_text(), "invalid")

    def test_private_symlink_not_followed(self):
        external = self.home / "outside"
        external.mkdir()
        self.private.mkdir(parents=True)
        (self.private / "retropiemenu").symlink_to(external)
        with self.assertRaises(ValueError):
            app.main(self.home, self.private, self.setup)
        self.assertEqual(list(external.iterdir()), [])

    def test_missing_setup_skips_bootstrap_safely(self):
        (self.setup / "retropie_packages.sh").unlink()
        self.assertEqual(app.main(self.home, self.private, self.setup), (0, 0))
        self.assertFalse(self.gamelist.exists())


if __name__ == "__main__":
    unittest.main()
