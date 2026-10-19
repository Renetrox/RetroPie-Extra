#!/usr/bin/env python3
"""Provide a private Tarave RetroPie gamelist using the real RetroPie menu.

EmulationStation classic stores .rp launchers under ~/RetroPie/retropiemenu,
not alongside gamelist.xml. Tarave uses that same installed menu if present.
Only on a truly new setup without a shared RetroPie menu does Tarave create
its own fallback shortcuts under <Tarave home>/.emulationstation/retropiemenu.
In every case, the gamelist and any overlay stay within Tarave's own --home.
Never copy/overwrite or modify the original RetroPie .rp files or icons.
"""
import argparse
import os
from pathlib import Path
import posixpath
import sys
import tempfile
import xml.etree.ElementTree as ET

# Entries and descriptions from RetroPie-Setup retropiemenu.sh.
# The Raspberry-Pi-only options and Raspbian-specific WiFi setting are
# deliberately excluded from the generic Debian/Orange Pi defaults.
MENU = (
    ("rpsetup", "RetroPie Setup",
     "Install, remove and configure RetroPie packages, emulators and drivers."),
    ("retroarch", "RetroArch",
     "Open the RetroArch configuration interface."),
    ("bluetooth", "Bluetooth", "Register and configure Bluetooth devices."),
    ("configedit", "Configuration Editor",
     "Edit RetroPie emulator and frontend configuration files."),
    ("esthemes", "ES Themes", "Install and manage EmulationStation themes."),
    ("filemanager", "File Manager", "Open the Midnight Commander file manager."),
    ("retronetplay", "RetroArch Net Play",
     "Configure RetroArch network play."),
    ("runcommand", "Run Command Configuration",
     "Configure RetroPie runcommand options."),
    ("showip", "Show IP", "Display available network addresses."),
)

def secure_dir(path, anchor):
    """Reject links in private paths; do not traverse arbitrary old symlinks."""
    path, anchor = Path(path), Path(anchor)
    if not path.is_relative_to(anchor):
        raise ValueError(f"Outside the private Tarave home: {path}")
    if anchor.is_symlink():
        raise ValueError(f"Private Tarave home is a symlink: {anchor}")
    anchor.mkdir(parents=True, exist_ok=True)
    parent = anchor
    for segment in path.relative_to(anchor).parts:
        parent = parent / segment
        if parent.is_symlink():
            raise ValueError(f"Private Tarave directory is a symlink: {parent}")
        parent.mkdir(exist_ok=True)
        if not parent.is_dir():
            raise ValueError(f"Not a directory: {parent}")

def unique_file(path, payload):
    """Never overwrite an existing private file or any symbolic link."""
    if path.exists() or path.is_symlink():
        return False
    try:
        with path.open("xb") as handle:
            handle.write(payload)
        return True
    except FileExistsError:
        return False

def save_xml(path, document):
    if path.is_symlink():
        raise ValueError(f"Refusing to replace symlink: {path}")
    contents = ET.tostring(document, encoding="utf-8", xml_declaration=True)
    tempname = None
    try:
        with tempfile.NamedTemporaryFile("wb", dir=str(path.parent),
                                         prefix=".tarave-retropie-", delete=False) as tmp:
            tempname = tmp.name
            tmp.write(contents)
        if path.is_symlink():
            raise ValueError(f"Refusing to replace symlink: {path}")
        os.chmod(tempname, 0o644)
        os.replace(tempname, path)
    finally:
        if tempname and os.path.exists(tempname):
            os.unlink(tempname)

def main(home, target_home, setup):
    home = Path(home)
    target_home = Path(target_home)
    setup = Path(setup)
    package_script = setup / "retropie_packages.sh"
    if not package_script.is_file():
        print("Tarave: RetroPie-Setup is unavailable; menu bootstrap skipped.")
        return (0, 0)

    cfg = target_home / ".emulationstation"
    gamelist = cfg / "gamelists/retropie/gamelist.xml"
    shared_menu = home / "RetroPie/retropiemenu"
    has_shared_menu = (shared_menu / "rpsetup.rp").is_file()
    # Installed RetroPie tools remain shared with ES-X. Only a genuinely new
    # setup needs private .rp placeholders; put those beneath .emulationstation
    # (NOT directly in ~/.local/share/batocera-es-test/).
    menu_dir = shared_menu if has_shared_menu else cfg / "retropiemenu"
    icon_dir = menu_dir / "icons"
    overlay = cfg / "es_systems_legacy_import.cfg"
    for directory in (cfg, gamelist.parent):
        secure_dir(directory, target_home)

    count_shortcuts = 0
    if not has_shared_menu:
        for directory in (menu_dir, icon_dir):
            secure_dir(directory, target_home)
        icon_source = setup / "scriptmodules/supplementary/retropiemenu/icons"
        for identifier, _, _ in MENU:
            if unique_file(menu_dir / (identifier + ".rp"), b""):
                count_shortcuts += 1
            src_icon = icon_source / (identifier + ".png")
            dst_icon = icon_dir / (identifier + ".png")
            if (src_icon.is_file() and not src_icon.is_symlink() and
                    not dst_icon.exists() and not dst_icon.is_symlink()):
                unique_file(dst_icon, src_icon.read_bytes())

    if gamelist.is_symlink():
        raise ValueError(f"Private gamelist is a symlink: {gamelist}")
    root = ET.parse(gamelist).getroot() if gamelist.exists() else ET.Element("gameList")
    if root.tag != "gameList":
        raise ValueError(f"Not a gameList XML file: {gamelist}")
    existing = {posixpath.normpath((item.findtext("path") or "").strip())
                for item in root.findall("game")}
    added = 0
    for identifier, name, description in MENU:
        rom = identifier + ".rp"
        # On existing RetroPie installs only display real, working .rp files.
        if not (menu_dir / rom).is_file():
            continue
        if rom in existing:
            continue
        game = ET.SubElement(root, "game")
        ET.SubElement(game, "path").text = "./" + rom
        ET.SubElement(game, "name").text = name
        ET.SubElement(game, "desc").text = description
        img = icon_dir / (identifier + ".png")
        if img.is_file():
            ET.SubElement(game, "image").text = str(img)
        added += 1
    if added or not gamelist.exists():
        save_xml(gamelist, root)

    # The core RetroPie menu remains at ~/RetroPie/retropiemenu if installed,
    # just as EmulationStation classic expects. Only a clean-install fallback
    # uses Tarave's own .emulationstation/retropiemenu directory.
    # Preserve any pre-existing private 'retropie' definition.
    if overlay.is_symlink():
        raise ValueError(f"Private system overlay is a symlink: {overlay}")
    doc = ET.parse(overlay).getroot() if overlay.exists() else ET.Element("systemList")
    if doc.tag != "systemList":
        raise ValueError(f"Invalid private es_systems overlay: {overlay}")
    existing_system = any((sys.findtext("name") or "").strip().lower() == "retropie"
                          for sys in doc.findall("system"))
    if not existing_system:
        system = ET.SubElement(doc, "system")
        for key, value in (
            ("name", "retropie"),
            ("fullname", "RetroPie"),
            ("path", str(menu_dir)),
            ("extension", ".rp .sh"),
            ("command", f"sudo {package_script} retropiemenu launch %ROM%"),
            ("theme", "retropie"),
        ):
            ET.SubElement(system, key).text = value
        save_xml(overlay, doc)

    print(f"Tarave: private RetroPie menu ready at {menu_dir}; "
          f"{count_shortcuts} new shortcuts, {added} gamelist entries.")
    return count_shortcuts, added

def cli():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", default=str(Path.home()))
    parser.add_argument("--tarave-home", required=True)
    parser.add_argument("--setup-dir", default=None)
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("Run as the login user, not root")
    try:
        main(args.home, args.tarave_home, args.setup_dir or Path(args.home) / "RetroPie-Setup")
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f"Tarave: private RetroPie menu bootstrap failed: {exc}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(cli())
