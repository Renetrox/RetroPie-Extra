#!/usr/bin/env python3
"""Import existing RetroPie gamelists into Tarave's isolated configuration.

A previous RetroPie/EmulationStation install may have Wine, Kodi, Ports,
RetroPie Setup and hundreds of system gamelists. Copy *all* of these on
install/configure, without overwriting Tarave edits. If there are no prior
gamelists, at least seek the stock RetroPie Setup metadata.

No changes to previous frontends, their gamelists, or shared ROM folders.
"""
import argparse
import copy
import os
from pathlib import Path
import posixpath
import shutil
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


def legacy_gamelists_dirs(home):
    """The login home may itself be a symlink to the shared RetroPie config."""
    home = Path(home)
    return (
        home / ".emulationstation/gamelists",
        Path("/opt/retropie/configs/all/emulationstation/gamelists"),
    )


def _safe_folder(root, folder):
    """Never follow links in Tarave's private gamelists tree."""
    if root.is_symlink() or folder.is_symlink():
        raise ValueError(f"Refusing symlink in private gamelists: {folder}")
    if not root.exists():
        root.mkdir(parents=True)
    if not root.is_dir():
        raise ValueError(f"Not a directory: {root}")
    # All subfolders are constructed from real directory entries, not XML paths.
    relative = folder.relative_to(root)
    current = root
    for component in relative.parts:
        current = current / component
        if current.is_symlink():
            raise ValueError(f"Refusing symlink in private gamelists: {current}")
        current.mkdir(exist_ok=True)
        if not current.is_dir():
            raise ValueError(f"Not a directory: {current}")


def _copy_exclusive(source, target):
    """Copy regular files without replacing existing user data, even in a race."""
    if target.is_symlink() or target.exists():
        return False
    # Create a private temporary file in the same destination filesystem.
    with tempfile.NamedTemporaryFile("wb", dir=str(target.parent),
                                     prefix=".tarave-import-", delete=False) as temp:
        tmpname = temp.name
        try:
            with source.open("rb") as old:
                shutil.copyfileobj(old, temp)
        except BaseException:
            os.unlink(tmpname)
            raise
    try:
        # link(2) fails if target exists, unlike rename/replace; no clobber.
        try:
            os.link(tmpname, target)
            return True
        except FileExistsError:
            return False
    finally:
        os.unlink(tmpname)


def sync_all(home, gamelists_dir, legacy_dirs=None, retro_candidates=None):
    """Non-destructive one-time import of the entire prior gamelists tree.

    Source precedence: ~/.emulationstation, then shared RetroPie-Setup config.
    Existing Tarave files always take precedence. The RetroPie menu is merged
    afterward so freshly installed RetroPie-Setup shortcuts receive PNG data.
    """
    gamelists_dir = Path(gamelists_dir)
    _safe_folder(gamelists_dir, gamelists_dir)
    imported = 0
    skipped_links = 0
    found_previous = False

    for source in (legacy_dirs if legacy_dirs is not None
                   else legacy_gamelists_dirs(home)):
        source = Path(source)
        if not source.is_dir() or source.resolve() == gamelists_dir.resolve():
            continue

        for folder, subfolders, files in os.walk(str(source), followlinks=False):
            parent = Path(folder)
            subfolders[:] = [d for d in subfolders
                             if not (parent / d).is_symlink()]
            relative = parent.relative_to(source)
            destination = gamelists_dir / relative
            _safe_folder(gamelists_dir, destination)
            for filename in files:
                original = parent / filename
                if original.is_symlink() or not original.is_file():
                    skipped_links += 1
                    continue
                found_previous = True
                new_file = destination / filename
                if _copy_exclusive(original, new_file):
                    imported += 1

    if found_previous:
        print(f"Tarave: imported {imported} missing files from previous "
              f"gamelists (unchanged files retained).")
    else:
        print("Tarave: no previous gamelists found; checking RetroPie menu.")
    if skipped_links:
        print(f"Tarave: skipped {skipped_links} linked/special files for safety.")

    # Always make sure the official RetroPie Setup shortcut, names and PNG
    # icon paths are available even on clean installations or after updating
    # RetroPie-Setup. Only the private retropie gamelist is edited.
    retro_target = gamelists_dir / "retropie" / "gamelist.xml"
    if retro_target.is_symlink():
        raise ValueError(f"Refusing symlink at {retro_target}")
    return imported, sync(home, retro_target, candidates=retro_candidates)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", default=str(Path.home()),
                        help="Login user's home, not Tarave's isolated --home")
    parser.add_argument("--target", required=True,
                        help="Tarave's private gamelists/retropie/gamelist.xml")
    parser.add_argument("--all", action="store_true",
                        help="Copy all existing system gamelists into Tarave (no overwrite)")
    args = parser.parse_args()
    try:
        if args.all:
            target = Path(args.target)
            if target.name != "gamelist.xml" or target.parent.name != "retropie":
                raise ValueError("--all requires a gamelists/retropie/gamelist.xml target")
            sync_all(args.home, target.parent.parent)
        else:
            sync(args.home, args.target)
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f"Tarave: could not sync private RetroPie gamelist: {exc}",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
