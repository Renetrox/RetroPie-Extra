#!/usr/bin/env bash
# Verify desktop/tty boot integration without modifying the runner's system.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox"' EXIT
source "$root/scriptmodules/supplementary/batocera-es-test.sh"
__user="$(id -un)"
__group="$(id -gn)"
home="$sandbox/user"
mkdir -p "$home/.config/autostart" "$sandbox/bin" "$sandbox/lightdm"
launcher="$sandbox/bin/tarave"
printf '#!/usr/bin/env bash\nexit 0\n' > "$launcher"
chmod 755 "$launcher"

# Simulate the old RetroPie auto-launch shortcut, which becomes stale when
# the classic EmulationStation program package has been uninstalled.
ln -s /usr/local/share/applications/retropie.desktop \
    "$home/.config/autostart/retropie.desktop"
_tarave_enable_desktop_autostart "$home" "$__user" "$__group" "$launcher"
target="$home/.config/autostart/tarave.desktop"
[[ -f "$target" ]]
grep -Fqx '# TARAVE_BOOT_AUTOSTART_MANAGED=1' "$target"
grep -Fqx "Exec=$launcher" "$target"
[[ ! -e "$home/.config/autostart/retropie.desktop" ]]
# Reinstall is idempotent.
_tarave_enable_desktop_autostart "$home" "$__user" "$__group" "$launcher"

# Never overwrite an unrelated user autostart entry.
printf '[Desktop Entry]\nName=User Owns This\n' > "$target"
if _tarave_enable_desktop_autostart "$home" "$__user" "$__group" "$launcher"; then
    echo 'ERROR: overwrote unrelated user desktop file' >&2
    exit 1
fi
grep -Fqx 'Name=User Owns This' "$target"

# LightDM alone gets a managed auto-login drop-in. Do not rewrite settings
# belonging to GDM/SDDM or other LightDM configurations.
hint="$sandbox/default-display-manager"
echo '/usr/sbin/gdm3' > "$hint"
_tarave_enable_lightdm_autologin "$__user" "$hint" "$sandbox/lightdm"
[[ ! -e "$sandbox/lightdm/90-tarave-autologin.conf" ]]
echo '/usr/sbin/lightdm' > "$hint"
_tarave_enable_lightdm_autologin "$__user" "$hint" "$sandbox/lightdm"
conf="$sandbox/lightdm/90-tarave-autologin.conf"
grep -Fqx '# TARAVE_LIGHTDM_AUTOLOGIN_MANAGED=1' "$conf"
grep -Fqx "autologin-user=$__user" "$conf"
_tarave_enable_lightdm_autologin "$__user" "$hint" "$sandbox/lightdm"
echo '# user managed, do not touch' > "$conf"
if _tarave_enable_lightdm_autologin "$__user" "$hint" "$sandbox/lightdm"; then
    echo 'ERROR: overwrote unrelated LightDM config' >&2
    exit 1
fi
grep -Fqx '# user managed, do not touch' "$conf"

# Simulate TTY-only RetroPie: invoke its existing enable_autostart function,
# rather than building a competing systemd service.
isPlatform() { [[ "$1" == "$platform" ]]; }
platform="tty"
enable_autostart() { printf '%s\n' "$1" > "$sandbox/tty-enabled"; }
_tarave_configure_boot "$launcher"
grep -Fqx 'es' "$sandbox/tty-enabled"
platform="x11"
# Override on-disk LightDM paths in tests by mocking the integration function.
_tarave_enable_lightdm_autologin() {
    printf '%s\n' "$1" > "$sandbox/lightdm-enabled"
}
# Restore owned desktop file before checking the high-level invocation.
rm -f "$target"
_tarave_configure_boot "$launcher"
[[ -f "$target" ]]
grep -Fqx "$__user" "$sandbox/lightdm-enabled"

# Remove only our managed autostart entry, leaving unrelated login configs.
printf '# TARAVE_LIGHTDM_AUTOLOGIN_MANAGED=1\n' > "$conf"
_tarave_remove_managed_desktop_boot "$home" "$conf"
[[ ! -e "$target" && ! -e "$conf" ]]
printf '[Desktop Entry]\nName=Someone Else\n' > "$target"
printf '# unrelated config\n' > "$conf"
_tarave_remove_managed_desktop_boot "$home" "$conf"
[[ -f "$target" && -f "$conf" ]]

echo 'PASS: XDG autostart, LightDM auto-login, RetroPie TTY boot and safe cleanup'
