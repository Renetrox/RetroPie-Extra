#!/usr/bin/env python3
"""Import previously configured RetroPie systems missing from Tarave.

Only complete <system> definitions absent from the shared RetroPie catalog
are imported. Wine/Kodi, custom systems and optional ports are treated equally.
Never modify ES-X, RetroPie-Setup, or the shared es_systems.cfg. Pre-existing
Tarave definitions take precedence and are never replaced.
"""
import argparse
import os
from pathlib import Path
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

SOURCE_NAMES = ("es_systems_custom.cfg", "es_systems.cfg")


def parse_systems(path):
    if not path.is_file():
        return []
    document = ET.parse(path)
    if document.getroot().tag != "systemList":
        raise ValueError(f"Expected <systemList> in {path}")
    return [node for node in document.getroot().findall("system")]


def system_id(node):
    return (node.findtext("name") or "").strip().lower()


def import_systems(source_home, target_cfg, shared_catalog, names=None):
    """Merge *missing* definitions into Tarave-private XML, preserving edits.

    `names` can restrict the migration, but by default any safe, complete
    definition absent from the shared RetroPie catalog qualifies.
    """
    source_home = Path(source_home)
    target_cfg = Path(target_cfg)
    wanted = None if names is None else set(names)
    if wanted is not None and (not wanted or
                               any(not re.fullmatch(r"[a-z0-9_-]+", n) for n in wanted)):
        raise ValueError("Invalid system selection")
    if target_cfg.is_symlink():
        raise ValueError(f"Refusing symlink destination: {target_cfg}")

    base_ids = set()
    if shared_catalog and Path(shared_catalog).is_file():
        base_ids = {system_id(node) for node in parse_systems(Path(shared_catalog))}

    # Validate the prior user file before touching it. Preserve all its nodes.
    if target_cfg.exists():
        root = ET.parse(target_cfg).getroot()
        if root.tag != "systemList":
            raise ValueError(f"Unexpected XML root in {target_cfg}")
    else:
        root = ET.Element("systemList")

    existing = {system_id(node) for node in root.findall("system")}
    definitions = {}
    for filename in SOURCE_NAMES:
        path = source_home / ".emulationstation" / filename
        for node in parse_systems(path):
            name = system_id(node)
            if (not re.fullmatch(r"[a-z0-9_-]+", name) or
                    (wanted is not None and name not in wanted) or
                    name in base_ids or name in existing or name in definitions):
                continue
            if not all((node.findtext(x) or "").strip()
                       for x in ("path", "extension", "command")):
                continue
            definitions[name] = node

    if not definitions:
        return []

    for node in definitions.values():
        root.append(node)
    data = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    target_cfg.parent.mkdir(parents=True, exist_ok=True)

    if target_cfg.exists():
        # An existing private imported file may contain user's manual edits.
        # Atomic replacement updates ONLY this private Tarave file.
        tmpname = None
        try:
            with tempfile.NamedTemporaryFile("wb", dir=str(target_cfg.parent),
                                             prefix=".tarave-systems-", delete=False) as tmp:
                tmpname = tmp.name
                tmp.write(data)
            if target_cfg.is_symlink():
                raise ValueError(f"Refusing symlink destination: {target_cfg}")
            os.replace(tmpname, target_cfg)
        finally:
            if tmpname and os.path.exists(tmpname):
                os.unlink(tmpname)
    else:
        # Exclusive creation: installation may never overwrite user data.
        fd = os.open(str(target_cfg), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        try:
            with os.fdopen(fd, "wb") as out:
                out.write(data)
        except BaseException:
            target_cfg.unlink(missing_ok=True)
            raise
    return sorted(definitions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-home", default=str(Path.home()))
    parser.add_argument("--destination", required=True)
    parser.add_argument("--catalog", default="/etc/emulationstation/es_systems.cfg")
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("Run as your regular user, not root")
    try:
        imported = import_systems(args.source_home, args.destination, args.catalog)
    except (OSError, ValueError, ET.ParseError) as exc:
        parser.error(str(exc))
    if imported:
        print("Tarave: imported missing system definitions: " + ", ".join(imported))
        print("Restart Tarave to load these systems. ES-X files were not modified.")
    else:
        print("Tarave: no new user-defined systems to import.")


if __name__ == "__main__":
    main()
