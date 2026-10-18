#!/usr/bin/env bash
# Apply the RetroPie Mupen64Plus input profile name-match fix.
# Usage: bash tools/fix-mupen64plus-profile-match.sh [path/to/configscripts/mupen64plus.sh]
set -euo pipefail
script="${1:-${HOME}/RetroPie-Setup/scriptmodules/supplementary/emulationstation/configscripts/mupen64plus.sh}"
if [[ ! -f "$script" ]]; then
    printf 'Missing RetroPie input configuration script: %s\n' "$script" >&2
    exit 1
fi
python3 - "$script" <<'PY'
import datetime
import pathlib
import shutil
import sys

path = pathlib.Path(sys.argv[1])
old = 'if grep -Fq "$DEVICE_NAME" "$file" ; then'
new = 'if grep -Fxq "[$DEVICE_NAME]" "$file" ; then'
original = path.read_bytes()
old_bytes, new_bytes = old.encode(), new.encode()

if new_bytes in original and old_bytes not in original:
    print(f'Already patched: {path}')
    sys.exit(0)
if original.count(old_bytes) != 1:
    sys.exit('Expected original statement not found exactly once; no changes made.')

stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = path.with_name(f'{path.name}.bak-profile-match-{stamp}')
if backup.exists():
    sys.exit(f'Backup already exists: {backup}; no changes made.')
shutil.copy2(path, backup)
path.write_bytes(original.replace(old_bytes, new_bytes, 1))
print(f'Patched: {path}')
print(f'Backup:  {backup}')
PY
