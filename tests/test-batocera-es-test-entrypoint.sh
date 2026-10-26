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
# Simulate a physical TTY and a failed KMS/DRM EGL context. The previous
# frontend must be launched rather than leaving the RetroPie boot blank.
cat > "$temp/tty" <<'FAKETTY'
#!/usr/bin/env bash
echo /dev/tty3
FAKETTY
chmod 755 "$temp/tty"
tty_fallback="$(env -u DISPLAY -u WAYLAND_DISPLAY MOCK_KMS_FAIL=1 PATH="$temp:$PATH" "$original" 'back up')"
[[ "$tty_fallback" == 'original:back up' ]]
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
# A source install (marker created by install()) makes Tarave the main
# frontend by default. Running Configure after the user restores ES does not.
fresh="$temp/main-emulationstation"
marker="$temp/.tarave-activate-after-install"
cat > "$fresh" <<'CLASSIC'
#!/usr/bin/env bash
printf 'classic:%s\n' "$*"
CLASSIC
chmod +x "$fresh"
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh" old)" == 'classic:old' ]]
touch "$marker"
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh" new)" == 'next:new' ]]
[[ "$("$fresh.batocera-es-test.previous" old)" == 'classic:old' ]]
[[ ! -e "$marker" ]]
# Reinstallation of an already managed entrypoint is idempotent.
touch "$marker"
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh.batocera-es-test.previous" old)" == 'classic:old' ]]
_batocera_es_test_restore "$fresh"
[[ "$("$fresh" restored)" == 'classic:restored' ]]
_tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh" unchanged)" == 'classic:unchanged' ]]
# Explicit side-by-side source installation does not take over ES.
touch "$marker"
TARAVE_INSTALL_SIDE_BY_SIDE=1 _tarave_activate_after_install "$fresh" "$next" "$marker"
[[ "$("$fresh" optout)" == 'classic:optout' ]]
[[ ! -e "$marker" && ! -e "$fresh.batocera-es-test.previous" ]]

echo 'PASS: RetroPie entrypoint backup, quoted arguments and rollback'
