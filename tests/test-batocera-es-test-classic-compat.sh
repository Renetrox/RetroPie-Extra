#!/usr/bin/env bash
# Compatibility regression: Tarave coexists with classic EmulationStation.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home="$HOME"
source "$root/scriptmodules/supplementary/batocera-es-test.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
__user="$(id -un)"
mkdir -p "$scratch/classic" "$scratch/private" "$scratch/retropie"
# Test the helper without depending on actual root/sudo in CI.
sudo() {
    if [[ "${1:-}" == "-H" && "${2:-}" == "-u" ]]; then
        shift 3
        "$@"
    else
        echo 'Unexpected sudo arguments in test' >&2
        return 1
    fi
}
shared="$scratch/retropie/es_systems.cfg"
prior="$scratch/classic/es_systems.cfg"
dest="$scratch/private/es_systems.cfg"
echo '<systemList><system><name>nes</name></system></systemList>' > "$shared"
ln -s "$shared" "$prior"
_tarave_import_previous_system_catalog "$prior" "$dest" "$shared"
[[ ! -e "$dest" && ! -L "$dest" ]] || { echo 'Shared catalog incorrectly snapshotted' >&2; exit 1; }
# A future RetroPie update to the shared catalog remains live.
echo '<systemList><system><name>j2me</name></system></systemList>' > "$shared"
[[ "$(grep -o 'j2me' "$prior")" == 'j2me' ]]
rm "$prior"
echo '<systemList><system><name>custom</name></system></systemList>' > "$prior"
_tarave_import_previous_system_catalog "$prior" "$dest" "$shared"
grep -q '<name>custom</name>' "$dest"
# A re-install must not overwrite user-customized Tarave configuration.
echo '<systemList><system><name>tarave</name></system></systemList>' > "$dest"
_tarave_import_previous_system_catalog "$prior" "$dest" "$shared"
grep -q '<name>tarave</name>' "$dest"
# Reject invalid source XML without losing an existing frontend.
rm "$dest"
echo 'invalid' > "$prior"
_tarave_import_previous_system_catalog "$prior" "$dest" "$shared" 
[[ ! -e "$dest" ]]
echo 'PASS: classic RetroPie shared catalog stays live, independent custom catalogs copied once'
