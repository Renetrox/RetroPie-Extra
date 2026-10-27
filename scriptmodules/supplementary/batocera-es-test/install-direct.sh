#!/usr/bin/env bash
# Direct interactive Tarave installer. Uses the exact RetroPie-Setup _source_
# route verified to work on Orange Pi, bypassing setup.sh's dialog/GUI logging.
# Installs Tarave as RetroPie's only frontend. After a successful source
# build, other registered ES / ES-X packages are removed. User data is kept.
# Requires the module to be registered in RetroPie-Setup.
set -Eeuo pipefail

if (( $# != 0 )); then
    echo "Usage: tarave-install (run as your regular login user)" >&2
    exit 2
fi
if (( EUID == 0 )); then
    echo "Run tarave-install as your regular user, NOT with sudo." >&2
    echo "The script invokes sudo for RetroPie-Setup only." >&2
    exit 2
fi
if [[ ! -t 0 ]]; then
    echo "Tarave installation needs an interactive terminal for sudo." >&2
    echo "Open a real terminal or SSH session and run: tarave-install" >&2
    exit 2
fi

setup="${TARAVE_RETROPIE_SETUP:-$HOME/RetroPie-Setup}"
packages="$setup/retropie_packages.sh"
if [[ ! -f "$packages" ]]; then
    echo "RetroPie-Setup is missing: $packages" >&2
    exit 1
fi
if [[ ! -f "$setup/ext/RetroPie-Extra/scriptmodules/supplementary/batocera-es-test.sh" &&
      ! -f "$setup/scriptmodules/supplementary/batocera-es-test.sh" ]]; then
    echo "Tarave module is not registered in RetroPie-Setup." >&2
    echo "Install the batocera-es-test.sh module first, then rerun this command." >&2
    exit 1
fi

umask 077
log="${TARAVE_INSTALL_LOG:-$HOME/tarave-install.log}"
echo "Tarave: interactive install from RetroPie source (without dialog)"
echo "RetroPie-Setup: $packages"
echo "Complete log: $log"
echo "Tarave becomes the only RetroPie frontend after installation."
echo "Older ES / ES-X program packages are removed; ROMs and configs are preserved."
echo "Boot setup: desktop autostart (LightDM auto-login when installed), or RetroPie tty1 autostart."
echo "Note: GDM/SDDM may still require enabling automatic desktop login."
# Prompt before starting the tee pipeline so sudo's interactive password
# exchange and the subsequent source build both use the original terminal.
sudo -v || exit 1

# Unlike setup.sh's GUI route, stdout/stderr remain visible throughout CMake.
# Do not redirect stdin: apt/sudo and terminal programs may require it.
set +e
sudo env TARAVE_BOOT_AUTOSTART="${TARAVE_BOOT_AUTOSTART:-1}" \
    TARAVE_BOOT_AUTOLOGIN="${TARAVE_BOOT_AUTOLOGIN:-1}" \
    "$packages" batocera-es-test _source_ 2>&1 | tee "$log"
result=${PIPESTATUS[0]}
set -e
if (( result == 0 )); then
    echo "Tarave installation complete. Use sudo reboot to test automatic boot."
    echo "For a manual test without reboot: batocera-es-test"
else
    echo "Tarave installation failed with status $result." >&2
    echo "Read the output above or the log: $log" >&2
fi
exit "$result"
