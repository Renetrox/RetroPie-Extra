#!/usr/bin/env bash
# Package/resource regression tests without altering the runner's system.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
home="$scratch/user"
mkdir -p "$home"
__user="$(id -un)"
__group="$(id -gn)"
md_inst="$scratch/package"
mkdir -p "$md_inst/themes/tarave-minimal"
cat > "$md_inst/themes/tarave-minimal/theme.xml" <<'XML'
<theme><formatVersion>7</formatVersion></theme>
XML
source "$root/scriptmodules/supplementary/batocera-es-test.sh"

# The complete frontend resource bundle is retained; none of these resources
# may be omitted when the package is staged by RetroPie-Setup.
install_batocera-es-test
for file in emulationstation resources locale themes scripts LICENSE.md opensans_license.txt ubuntu_licence.txt README.md THEMES.md GAMELISTS.md SYSTEMS.md CREDITS.md; do
    found=0
    for item in "${md_ret_files[@]}"; do
        if [[ "$item" == "$file" ]]; then
            found=1
            break
        fi
    done
    (( found )) || { echo "Missing packaged artifact: $file" >&2; exit 1; }
done

private_cfg="$home/.local/share/batocera-es-test/.emulationstation"
_tarave_seed_default_theme "$private_cfg"
[[ -f "$private_cfg/themes/tarave-minimal/theme.xml" ]]

# Idempotence: subsequent configure operations must never overwrite a user
# edit or a selected/downloaded theme.
echo '<theme>USER CUSTOM</theme>' > "$private_cfg/themes/tarave-minimal/theme.xml"
_tarave_seed_default_theme "$private_cfg"
grep -q 'USER CUSTOM' "$private_cfg/themes/tarave-minimal/theme.xml"
rm -rf "$private_cfg/themes/tarave-minimal"
mkdir -p "$private_cfg/themes/my-downloaded"
echo '<theme>EXTERNAL</theme>' > "$private_cfg/themes/my-downloaded/theme.xml"
_tarave_seed_default_theme "$private_cfg"
[[ ! -e "$private_cfg/themes/tarave-minimal" ]]

# No ES-X configuration directory is created as a side effect.
[[ ! -e "$home/.emulationstation" ]]
echo 'PASS: resources staged, offline theme only as needed, private data intact'
