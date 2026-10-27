#!/usr/bin/env bash
# Does not write any system launcher; tests the module's isolated functions.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
home="$HOME"
source "$root/scriptmodules/supplementary/batocera-es-test.sh"
original="$temp/emulationstation"
next="$temp/next"
cat > "$original" <<'ORIGINAL'
#!/usr/bin/env bash
printf 'original:%s\n' "$*"
ORIGINAL
cat > "$next" <<'NEXT'
#!/usr/bin/env bash
if [[ "${MOCK_KMS_FAIL:-0}" == "1" ]]; then exit 42; fi
printf 'next:%s\n' "$*"
NEXT
chmod 755 "$next" "$original"
_batocera_es_test_activate "$original" "$next"
[[ "$("$original" 'hello world' '--angle=x y')" == 'next:hello world --angle=x y' ]]
[[ -x "$original.batocera-es-test.previous" ]]
# A second install/configure must be idempotent and preserve the prior binary.
_batocera_es_test_activate "$original" "$next"
[[ "$("$original.batocera-es-test.previous" 'old')" == 'original:old' ]]
# Simulate a physical TTY and failed KMS/DRM EGL context. Exclusive
# mode must report the Tarave failure, not run an uninstalled ES executable.
cat > "$temp/tty" <<'FAKETTY'
#!/usr/bin/env bash
echo /dev/tty3
FAKETTY
chmod 755 "$temp/tty"
tty_status=0
env -u DISPLAY -u WAYLAND_DISPLAY MOCK_KMS_FAIL=1 PATH="$temp:$PATH" \
    "$original" 'back up' >/dev/null 2>&1 || tty_status=$?
[[ "$tty_status" -eq 42 ]]
_batocera_es_test_restore "$original"
[[ "$("$original" 'hello world')" == 'original:hello world' ]]
[[ ! -e "$original.batocera-es-test.previous" ]]
# ES-X may be reinstalled while Tarave's former backup still exists.
# Reinstalling Tarave must pick the CURRENT active frontend for rollback and
# archive the even older backup, never overwrite/delete unrelated binaries.
_batocera_es_test_activate "$original" "$next"
cat > "$original" <<'FOREIGN'
#!/usr/bin/env bash
echo es-x
FOREIGN
chmod 755 "$original"
_batocera_es_test_activate "$original" "$next"
[[ "$("$original")" == 'next:' ]]
[[ "$("$original.batocera-es-test.previous")" == 'es-x' ]]
archived=( "$original".batocera-es-test.previous.archived.* )
[[ "${#archived[@]}" -eq 1 && -f "${archived[0]}" ]]
[[ "$("${archived[0]}")" == 'original:' ]]
_batocera_es_test_restore "$original"
[[ "$("$original")" == 'es-x' ]]
[[ ! -e "$original.batocera-es-test.previous" ]]
[[ "$("${archived[0]}")" == 'original:' ]]

# A symlink to either ES or ES-X is a valid existing RetroPie entrypoint.
# Restore the *same* symlink after removing Tarave.
other="$temp/esx"
printf '#!/usr/bin/env bash\necho symlink-esx\n' > "$other"
chmod +x "$other"
ln -s "$other" "$temp/symlink-emulationstation"
link="$temp/symlink-emulationstation"
_batocera_es_test_activate "$link" "$next"
[[ "$("$link")" == 'next:' ]]
[[ -L "$link.batocera-es-test.previous" ]]
_batocera_es_test_restore "$link"
[[ -L "$link" && "$(readlink "$link")" == "$other" ]]
[[ "$("$link")" == 'symlink-esx' ]]
# The normal source install must retire ALL registered ES/ES-X packages,
# then re-create the Tarave default launcher. Simulate RetroPie-Setup package
# removal under a scratch directory: never write to the runner's actual /opt.
rootdir="$temp/opt/retropie"
mkdir -p "$rootdir/supplementary"
fresh="$temp/main-emulationstation"
marker="$temp/.tarave-activate-after-install"
config="$temp/user/gamelist.xml"
mkdir -p "$(dirname "$config")"
printf '<gameList />\n' > "$config"

rp_hasModule() {
    case "$1" in
        emulationstation|emulationstation-es-x|emulationstation-dev) return 0 ;;
        *) return 1 ;;
    esac
}
rp_isInstalled() { [[ -d "$rootdir/supplementary/$1" ]]; }
rp_callModule() {
    [[ "$2" == "remove" ]] || return 1
    printf '%s\n' "$1" >> "$temp/removed"
    rmdir -- "$rootdir/supplementary/$1" || return 1
    # RetroPie's EmulationStation remove hook unlinks its shared entrypoint.
    rm -f -- "$fresh"
}
# No real boot settings may be modified in the isolated launcher test.
_tarave_configure_boot() { printf '%s\n' "$1" >> "$temp/boot-configure"; }
make_legacy_packages() {
    mkdir -p "$rootdir/supplementary/emulationstation" \
             "$rootdir/supplementary/emulationstation-es-x" \
             "$rootdir/supplementary/emulationstation-dev"
}
cat > "$fresh" <<'CLASSIC'
#!/usr/bin/env bash
printf 'classic:%s\n' "$*"
CLASSIC
chmod +x "$fresh"
make_legacy_packages
# Configure-only must NOT remove or replace the existing frontend.
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh" old)" == 'classic:old' ]]
[[ -d "$rootdir/supplementary/emulationstation" ]]

touch "$marker"
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh" new)" == 'next:new' ]]
[[ ! -f "$marker" ]]
[[ ! -e "$fresh.batocera-es-test.previous" ]]
[[ "$(wc -l < "$temp/removed")" -eq 3 ]]
for id in emulationstation emulationstation-es-x emulationstation-dev; do
    [[ ! -d "$rootdir/supplementary/$id" ]]
    grep -Fqx "$id" "$temp/removed"
done
[[ -f "$config" ]] && grep -q '<gameList />' "$config"

# Reinstalling Tarave remains idempotent and never removes user data.
touch "$marker"
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh" old)" == 'next:old' ]]
[[ ! -f "$marker" ]]
[[ "$(wc -l < "$temp/removed")" -eq 3 ]]
[[ -f "$config" ]]
[[ "$(wc -l < "$temp/boot-configure")" -eq 2 ]]

# If ES-X gets installed again, the next Tarave source install takes over.
make_legacy_packages
cat > "$fresh" <<'FOREIGN'
#!/usr/bin/env bash
echo es-x
FOREIGN
chmod +x "$fresh"
touch "$marker"
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh")" == 'next:' ]]
[[ ! -e "$fresh.batocera-es-test.previous" ]]
[[ "$(wc -l < "$temp/removed")" -eq 6 ]]
[[ -f "$config" ]]

echo 'PASS: Tarave is the only frontend after install; private settings and ROM data preserved'
