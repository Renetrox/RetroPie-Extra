#!/usr/bin/env python3
"""Safely populate Tarave's private RetroPie menu metadata.

RetroPie-Setup creates retropiemenu shortcuts and their names, descriptions and
absolute PNG image paths in an EmulationStation gamelist. Tarave uses a separate
--home; without the metadata file its menu appears unlabelled or incomplete.

Read official RetroPie/EmulationStation data, never modify that source.
Merge by ROM path, preserving all user-maintained fields and other game entries
in Tarave's copy. Run during module configure, or explicitly on request.
"""
import argparse
import copy
import os
from pathlib import Path
import posixpath
import sys
import tempfile
import xml.etree.ElementTree as ET


def source_paths(home):
    home = Path(home)
    return (
        home / ".emulationstation/gamelists/retropie/gamelist.xml",
        Path("/opt/retropie/configs/all/emulationstation/gamelists/retropie/gamelist.xml"),
        home / "RetroPie/retropiemenu/gamelist.xml",
        Path("/etc/emulationstation/gamelists/retropie/gamelist.xml"),
    )


def load(path):
    root = ET.parse(path).getroot()
    if root.tag != "gameList":
        raise ValueError(f"Unexpected XML root in {path}: {root.tag}")
    return root


def find_source(candidates):
    for path in candidates:
        if not path.is_file():
            continue
        try:
            root = load(path)
        except (OSError, ValueError, ET.ParseError) as exc:
            print(f"Tarave: skipping invalid source {path}: {exc}", file=sys.stderr)
            continue
        if any((node.findtext("path") or "").strip() for node in root.findall("game")):
            return path, root
    return None, None


def key(node):
    path = (node.findtext("path") or "").strip()
    # RetroPie uses ./rpsetup.rp while other frontends may save rpsetup.rp.
    # Both refer to the same item within the retropiemenu ROM directory.
    return posixpath.normpath(path) if path else ""


def merge_from_source(source_root, dest_root):
    by_path = {
        key(item): item for item in dest_root
        if item.tag in ("game", "folder") and key(item)
    }
    additions = 0
    enrichments = 0
    for item in source_root:
        if item.tag not in ("game", "folder") or not key(item):
            continue
        k = key(item)
        if k not in by_path:
            child = copy.deepcopy(item)
            dest_root.append(child)
            by_path[k] = child
            additions += 1
            continue
        existing = by_path[k]
        # Do not replace custom titles, artwork, command fields or flags.
        # Fill only missing/empty metadata from RetroPie-Setup.
        for field in item:
            if field.tag == "path":
                continue
            current = existing.find(field.tag)
            if current is None:
                existing.append(copy.deepcopy(field))
                enrichments += 1
            elif not (current.text or "").strip() and (field.text or "").strip():
                current.text = field.text
                enrichments += 1
    return additions, enrichments


def atomic_write(target, contents):
    target.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile("wb", dir=str(target.parent),
                                         prefix=".gamelist-tarave-", delete=False) as temp:
            name = temp.name
            temp.write(contents)
        os.chmod(name, 0o644)
        # Refuse to replace a user symlink, including dangling links.
        if target.is_symlink():
            raise ValueError(f"Refusing to overwrite symlink {target}")
        os.replace(name, target)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


def sync(home, target, candidates=None):
    target = Path(target)
    if target.is_symlink():
        raise ValueError(f"Refusing to change a symlink: {target}")
    source_path, source_root = find_source(candidates or source_paths(home))
    if source_path is None:
        print("Tarave: RetroPie menu gamelist unavailable; leaving private metadata unchanged.")
        return (0, 0)

    if target.exists():
        if not target.is_file():
            raise ValueError(f"Destination is not a file: {target}")
        # Preserve the user's file if it is invalid; never silently erase it.
        dest_root = load(target)
    else:
        dest_root = ET.Element("gameList")

    added, enriched = merge_from_source(source_root, dest_root)
    if not target.exists() or added or enriched:
        data = ET.tostring(dest_root, encoding="utf-8", xml_declaration=True)
        atomic_write(target, data)
    print(f"Tarave: RetroPie menu metadata from {source_path}: "
          f"{added} new entries, {enriched} missing fields restored.")
    return (added, enriched)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", default=str(Path.home()),
                        help="Login user's home, not Tarave's isolated --home")
    parser.add_argument("--target", required=True,
                        help="Tarave's private gamelists/retropie/gamelist.xml")
    args = parser.parse_args()
    try:
        sync(args.home, args.target)
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f"Tarave: could not sync private RetroPie gamelist: {exc}",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
