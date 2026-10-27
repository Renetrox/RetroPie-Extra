#!/usr/bin/env bash
#
# Tarave standalone frontend module for RetroPie
#
# Installs Tarave as RetroPie's sole frontend after a successful source build.
# Obsolete classic EmulationStation / ES-X executable packages are removed
# through RetroPie-Setup only after the replacement has been prepared.
# ROMs, emulator settings, game metadata and user theme folders are preserved.
#
# This installs the non-BATOCERA build of the experimental fork.
# Batocera-specific services, launch hooks, and emulator hotkeys are
# NOT provided by this package.

rp_module_id="batocera-es-test"
rp_module_desc="Tarave - sole RetroPie frontend; removes older ES / ES-X binaries"
rp_module_help="Tarave for RetroPie.\n\nSource installation activates Tarave and uninstalls the original EmulationStation and ES-X program packages. ROMs, emulator configs, input mapping files, themes, gamelists and RetroPie Setup remain intact. If you uninstall Tarave later, reinstall an alternative frontend manually.\n\nLaunch: batocera-es-test\nDirect installer: tarave-install\nPrivate settings: $home/.local/share/batocera-es-test/.emulationstation\nSystems: /opt/retropie/configs/all/emulationstation/es_systems.cfg (if present), otherwise /etc/emulationstation/es_systems.cfg."
rp_module_licence="MIT https://github.com/Renetrox/batocera-emulationstation/blob/master/LICENSE.md"
rp_module_repo="git https://github.com/Renetrox/batocera-emulationstation.git experiment/retropie-standalone-20261013"
rp_module_section="exp"
rp_module_flags="frontend"

function depends_batocera-es-test() {
    getDepends \
        git build-essential cmake pkg-config python3 \
        libsdl2-dev libsdl2-mixer-dev \
        libfreeimage-dev libfreetype6-dev libcurl4-openssl-dev \
        rapidjson-dev libasound2-dev \
        libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
        libvlc-dev libvlccore-dev vlc-bin \
        libudev-dev gettext xmlstarlet
}

function sources_batocera-es-test() {
    gitPullOrClone || return 1

    # external/pugixml is a git submodule, not a distro-generated source.
    git -C "$md_build" submodule update --init --recursive || return 1
}

function build_batocera-es-test() {
    local -a cmake_opts=(
        -DCMAKE_BUILD_TYPE=Release
        -DBATOCERA=OFF
        -DRETROBAT=OFF
        -DDISABLE_KODI=ON
        -DENABLE_FILEMANAGER=OFF
        -DENABLE_TTS=OFF
        -DCEC=OFF
    )

    # Desktop/Panfrost X11 -> GL 2.1 renderer. Non-X11 GLES platform -> GLES2.
    if isPlatform "gles" && ! isPlatform "x11"; then
        cmake_opts+=(-DGL=OFF -DGLES=OFF -DGLES2=ON)
    else
        cmake_opts+=(-DGL=ON -DGLES=OFF -DGLES2=OFF)
    fi

    local jobs
    jobs="$(nproc)"
    if [[ "$(uname -m)" == arm* || "$(uname -m)" == aarch64 ]]; then
        # Avoid exhausting RAM on SBCs during this particularly large build.
        (( jobs > 2 )) && jobs=2
    else
        (( jobs > 4 )) && jobs=4
    fi
    (( jobs < 1 )) && jobs=1

    cmake -S "$md_build" -B "$md_build/build" "${cmake_opts[@]}" || return 1
    cmake --build "$md_build/build" --target emulationstation --parallel "$jobs" || return 1

    # This fork forces EXECUTABLE_OUTPUT_PATH to its source root.
    md_ret_require="$md_build/emulationstation"
    [[ -x "$md_ret_require" ]] || return 1
}

function install_batocera-es-test() {
    md_ret_files=(
        "emulationstation"
        "resources"
        "locale"
        "themes"
        "scripts"
        "LICENSE.md"
        "opensans_license.txt"
        "ubuntu_licence.txt"
        "README.md"
        "GAMELISTS.md"
        "THEMES.md"
        "SYSTEMS.md"
        "CREDITS.md"
    )

    # A source install is a deliberate install/upgrade operation. Mark this
    # installation for activation once configure has successfully prepared
    # the private frontend. A later "Configure / Options" call must NOT
    # silently re-activate Tarave after the user restored another frontend.
    touch "$md_inst/.tarave-activate-after-install" || return 1
}

# Take over only the standard RetroPie entrypoint. Do not replace the
# installed EmulationStation package/binary itself or its data directories.
# Backup lives next to the original, outside md_inst, so package removal can
# restore it even after the Next installation directory has been deleted.
function _batocera_es_test_owns_entry() {
    local entry="$1"
    [[ -f "$entry" && ! -L "$entry" ]] || return 1
    head -n 3 "$entry" | grep -Fqx '# BATOCERA_ES_TEST_MANAGED_ENTRYPOINT=1'
}

function _batocera_es_test_activate() {
    local entry="$1"
    local command="$2"
    local backup="${entry}.batocera-es-test.previous"

    if [[ ! -x "$command" ]]; then
        echo "Tarave entrypoint unavailable: $command" >&2
        return 1
    fi

    # A newer ES or ES-X install may have replaced Tarave's managed launcher
    # while the previous-backup still exists. On an explicit Tarave reinstall,
    # the frontend that is active NOW must become the rollback target. Preserve
    # the older backup separately instead of clobbering it or refusing install.
    local tmp moved_original=0 archived_previous=""
    tmp="$(mktemp "${entry}.batocera-es-test.XXXXXX")" || return 1
    {
        printf '#!/usr/bin/env bash\n'
        printf '# BATOCERA_ES_TEST_MANAGED_ENTRYPOINT=1\n'
        printf '# RetroPie frontend selector, managed by batocera-es-test.\n'
        printf 'front=%q\n' "$command"
        cat <<'WRAPPER'
# Physical Linux TTY: select native SDL KMS/DRM. Exclusive installations
# have no ES or ES-X binary to fall back to after an SDL/EGL failure.
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "$(tty 2>/dev/null)" =~ ^/dev/tty[0-9]+$ ]]; then
    export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-kmsdrm}"
    export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
fi
exec "$front" "$@"
WRAPPER
    } > "$tmp"
    if ! chmod 755 "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    if ! _batocera_es_test_owns_entry "$entry"; then
        if [[ -e "$entry" || -L "$entry" ]]; then
            if [[ -e "$backup" || -L "$backup" ]]; then
                # mktemp reserves a collision-free archival name. Retain it on
                # success for manual rollback of an even earlier frontend.
                archived_previous="$(mktemp "${backup}.archived.XXXXXXXX")" || {
                    rm -f -- "$tmp"
                    return 1
                }
                if ! mv -fT -- "$backup" "$archived_previous"; then
                    rm -f -- "$tmp" "$archived_previous"
                    echo "Could not archive an earlier frontend backup." >&2
                    return 1
                fi
            fi
            if ! mv -T -- "$entry" "$backup"; then
                rm -f -- "$tmp"
                if [[ -n "$archived_previous" ]]; then
                    mv -fT -- "$archived_previous" "$backup" ||
                        echo "Restore previous backup manually: $archived_previous" >&2
                fi
                echo "Could not preserve existing EmulationStation launcher." >&2
                return 1
            fi
            moved_original=1
        fi
    fi

    if ! mv -fT -- "$tmp" "$entry"; then
        rm -f -- "$tmp"
        if (( moved_original )); then
            mv -T -- "$backup" "$entry" ||
                echo "Restore active frontend manually: $backup" >&2
        fi
        if [[ -n "$archived_previous" ]]; then
            mv -fT -- "$archived_previous" "$backup" ||
                echo "Restore older backup manually: $archived_previous" >&2
        fi
        echo "Could not enable Tarave launcher." >&2
        return 1
    fi

    echo "Tarave is now the active EmulationStation frontend: $entry"
    if [[ -e "$backup" || -L "$backup" ]]; then
        echo "Previously active frontend saved at: $backup"
    fi
    if [[ -n "$archived_previous" ]]; then
        echo "An older frontend backup was preserved at: $archived_previous"
    fi
}

function _batocera_es_test_restore() {
    local entry="$1"
    local backup="${entry}.batocera-es-test.previous"

    if _batocera_es_test_owns_entry "$entry"; then
        if [[ -e "$backup" || -L "$backup" ]]; then
            if mv -fT -- "$backup" "$entry"; then
                echo "Previous EmulationStation launcher restored: $entry"
            else
                echo "Failed to restore $backup to $entry" >&2
                return 1
            fi
        else
            rm -f -- "$entry" || return 1
            echo "Removed ES-X Next entrypoint (no previous frontend existed)."
        fi
    elif [[ -e "$backup" || -L "$backup" ]]; then
        echo "$entry was changed by another installer; not overwriting it." >&2
        echo "The saved previous launcher remains at $backup" >&2
    fi
}

# Use RetroPie-Setup's own package-removal workflow. This removes only
# superseded frontend *program packages*, never ROMs, user themes, gamelists,
# emulator configurations or shared RetroPie system definitions. Call after
# Tarave has been successfully built and configured, never before.
function _tarave_remove_competing_frontends() {
    local id
    for id in emulationstation-es-x emulationstation-dev emulationstation; do
        if rp_hasModule "$id" && rp_isInstalled "$id"; then
            echo "Removing superseded frontend package: $id"
            rp_callModule "$id" remove || return 1
        fi
    done
}

# RetroPie normally installs a default theme in /etc/emulationstation/themes.
# That location is shared with ES-X. Instead seed Tarave's private folder only
# when no theme (downloaded or user-created) is already installed.
function _tarave_seed_default_theme() {
    local cfg="$1"
    local source="$md_inst/themes/tarave-minimal"
    local dest="$cfg/themes/tarave-minimal"
    local themes="$cfg/themes"
    [[ -d "$source" && -r "$source/theme.xml" ]] || return 1
    mkdir -p "$themes" || return 1
    if [[ -d "$dest" ]]; then
        return 0
    fi
    if [[ -n "$(find "$themes" -maxdepth 4 -name theme.xml -type f -print -quit 2>/dev/null)" ]]; then
        echo "Tarave user theme already exists; leaving theme selection unchanged."
        return 0
    fi
    # Existing RetroPie systems already have a usable global Carbon theme.
    # Avoid unexpectedly replacing its look with the emergency fallback.
    if [[ -d /etc/emulationstation/themes ]] &&
       [[ -n "$(find /etc/emulationstation/themes -maxdepth 4 -name theme.xml -type f -print -quit 2>/dev/null)" ]]; then
        echo "RetroPie system theme available; no Tarave fallback needed."
        return 0
    fi
    cp -a -- "$source" "$dest" || return 1
    chown -R "$__user:$__group" "$dest" || return 1
    echo "Installed small offline fallback theme in Tarave private data."
}

# Expose the known-working RetroPie-Setup source installer as its own
# interactive terminal command and desktop launcher. Do not route this through
# setup.sh's dialog/gzip log pipeline, which may stall when launched from an ES.
function _tarave_direct_installer() {
    local source="$md_data/install-direct.sh"
    local installed="$md_inst/install-direct.sh"
    local launcher="/usr/local/bin/tarave-install"
    local desktop="/usr/local/share/applications/tarave-install.desktop"

    [[ -f "$source" ]] || { echo "Missing Tarave direct installer: $source" >&2; return 1; }
    install -m 755 -- "$source" "$installed" || return 1
    mkdir -p "$(dirname "$launcher")" || return 1
    if [[ -e "$launcher" || -L "$launcher" ]]; then
        if [[ ! -L "$launcher" || "$(readlink "$launcher")" != "$installed" ]]; then
            echo "Refusing to replace unrelated $launcher" >&2
            return 1
        fi
    fi
    ln -sfn -- "$installed" "$launcher" || return 1

    if isPlatform "x11"; then
        if [[ -e "$desktop" ]] &&
           ! grep -Fqx '# TARAVE_DIRECT_INSTALL_MANAGED=1' "$desktop"; then
            echo "Refusing to replace unrelated desktop entry: $desktop" >&2
            return 1
        fi
        cat > "$desktop" <<EOF
[Desktop Entry]
# TARAVE_DIRECT_INSTALL_MANAGED=1
Type=Application
Name=Install or update Tarave
Comment=Install from source in a real terminal and show progress
Exec=$launcher
TryExec=$launcher
Icon=$md_inst/resources/window_icon_256.png
Terminal=true
Categories=Game;System;
EOF
        chmod 644 "$desktop" || return 1
    fi
}

# Keep the graphical shortcut distinct from RetroPie's existing desktop file.
function _tarave_desktop_entry() {
    local desktop="/usr/local/share/applications/tarave-es-next.desktop"
    if [[ -e "$desktop" ]] && ! grep -Fqx '# TARAVE_ES_NEXT_MANAGED=1' "$desktop"; then
        echo "Refusing to replace an unrelated desktop entry at $desktop" >&2
        return 0
    fi
    mkdir -p "$(dirname "$desktop")" || return 1
    cat > "$desktop" <<EOF
[Desktop Entry]
# TARAVE_ES_NEXT_MANAGED=1
Type=Application
Name=ES-X Next (Tarave)
Comment=Independent EmulationStation frontend for RetroPie
Exec=/usr/local/bin/batocera-es-test
TryExec=/usr/local/bin/batocera-es-test
Icon=$md_inst/resources/window_icon_256.png
Terminal=false
Categories=Game;Emulator;
EOF
    chmod 644 "$desktop"
}

# Autostart is part of a finished frontend installation. On desktop systems
# use the user's native XDG autostart (not classic ES's now-removed retropie
# desktop entry). On console-only RetroPie reuse its supported tty1 boot hook.
# Never switch an X11 machine to DRM/TTY, which is not guaranteed on ARM SBCs.
function _tarave_enable_desktop_autostart() {
    local userhome="$1"
    local owner="$2"
    local group="$3"
    local launcher="$4"
    local dest="$userhome/.config/autostart/tarave.desktop"
    local former="$userhome/.config/autostart/retropie.desktop"
    local old_target="/usr/local/share/applications/retropie.desktop"

    [[ -x "$launcher" ]] || {
        echo "Tarave launcher not installed: $launcher" >&2
        return 1
    }
    # Never overwrite a user-customized desktop autostart.
    if [[ ( -e "$dest" || -L "$dest" ) ]] &&
       { [[ -L "$dest" ]] ||
         ! grep -Fqx '# TARAVE_BOOT_AUTOSTART_MANAGED=1' "$dest"; }; then
        echo "Existing non-Tarave autostart file at $dest; leaving it unchanged." >&2
        return 1
    fi

    mkdir -p "$userhome/.config/autostart" || return 1
    chown "$owner:$group" "$userhome/.config" "$userhome/.config/autostart" || return 1
    # The old official shortcut points at a desktop file uninstalled with
    # classic ES. Remove ONLY that exact symlink so Tarave starts once.
    if [[ -L "$former" && "$(readlink "$former")" == "$old_target" ]]; then
        rm -f -- "$former" || return 1
    fi
    cat > "$dest" <<EOF
[Desktop Entry]
# TARAVE_BOOT_AUTOSTART_MANAGED=1
Type=Application
Name=Tarave
Comment=Start the RetroPie Tarave frontend after graphical login
Exec=$launcher
TryExec=$launcher
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    chown "$owner:$group" "$dest" || return 1
    chmod 644 "$dest" || return 1
    echo "Tarave will launch automatically when the desktop session starts."
}

function _tarave_enable_lightdm_autologin() {
    local owner="$1"
    local hint="${2:-/etc/X11/default-display-manager}"
    local confdir="${3:-/etc/lightdm/lightdm.conf.d}"
    local file="$confdir/90-tarave-autologin.conf"

    # Do not change a different display manager or an unrelated file.
    if [[ ! -r "$hint" ]] || ! grep -Eq '(^|/)lightdm([[:space:]]|$)' "$hint"; then
        echo "Desktop auto-login not configured: this display manager is not LightDM."
        return 0
    fi
    if [[ -e "$file" ]] &&
       ! grep -Fqx '# TARAVE_LIGHTDM_AUTOLOGIN_MANAGED=1' "$file"; then
        echo "Existing LightDM configuration at $file; leaving it unchanged." >&2
        return 1
    fi
    mkdir -p "$confdir" || return 1
    cat > "$file" <<EOF
# TARAVE_LIGHTDM_AUTOLOGIN_MANAGED=1
[Seat:*]
autologin-user=$owner
autologin-user-timeout=0
EOF
    chmod 644 "$file" || return 1
    echo "LightDM will auto-login $owner and start Tarave after boot."
}

function _tarave_configure_boot() {
    local launcher="$1"
    if [[ "${TARAVE_BOOT_AUTOSTART:-1}" == "0" ]]; then
        echo "Tarave automatic start disabled explicitly (TARAVE_BOOT_AUTOSTART=0)."
        return 0
    fi

    if isPlatform "x11"; then
        _tarave_enable_desktop_autostart "$home" "$__user" "$__group" "$launcher" ||
            return 1
        # LightDM is common on Debian XFCE. For GDM/SDDM, preserve the
        # existing login policy and explain the limitation to the installer.
        if [[ "${TARAVE_BOOT_AUTOLOGIN:-1}" != "0" ]]; then
            _tarave_enable_lightdm_autologin "$__user" || return 1
        fi
    elif declare -F enable_autostart >/dev/null 2>&1; then
        # RetroPie-Setup's own autostart module configures tty1 auto-login
        # and /etc/profile.d/10-retropie.sh to launch 'emulationstation'.
        # /usr/bin/emulationstation is already Tarave's managed launcher.
        enable_autostart es || return 1
        echo "RetroPie tty1 autostart enabled for Tarave."
    else
        echo "WARNING: no RetroPie tty autostart helper; configure boot in RetroPie-Setup." >&2
        return 1
    fi
}

function _tarave_remove_managed_desktop_boot() {
    local userhome="${1:-$home}"
    local dest="$userhome/.config/autostart/tarave.desktop"
    local lightdm="${2:-/etc/lightdm/lightdm.conf.d/90-tarave-autologin.conf}"
    if [[ -f "$dest" ]] &&
       grep -Fqx '# TARAVE_BOOT_AUTOSTART_MANAGED=1' "$dest"; then
        rm -f -- "$dest" || return 1
    fi
    if [[ -f "$lightdm" ]] &&
       grep -Fqx '# TARAVE_LIGHTDM_AUTOLOGIN_MANAGED=1' "$lightdm"; then
        rm -f -- "$lightdm" || return 1
    fi
}

# Import the old full gamelists folder (including Wine, Kodi and Ports), then
# refresh official RetroPie Setup menu entries. All destination files are in
# Tarave's private --home; other frontend configurations stay untouched.
# Always run as the login user, since RetroPie-Setup runs as root.
function _tarave_sync_retropie_menu() {
    local user_home="$1"
    local target="$user_home/.local/share/batocera-es-test/.emulationstation/gamelists/retropie/gamelist.xml"
    local helper="$md_inst/retropie-gamelist-sync.py"
    [[ -f "$helper" ]] || { echo "Missing RetroPie gamelist sync helper: $helper" >&2; return 1; }
    sudo -H -u "$__user" python3 "$helper" --home "$user_home" --target "$target"
}

function _tarave_sync_all_gamelists() {
    local user_home="$1"
    local target="$user_home/.local/share/batocera-es-test/.emulationstation/gamelists/retropie/gamelist.xml"
    local helper="$md_inst/retropie-gamelist-sync.py"
    [[ -f "$helper" ]] || { echo "Missing gamelist import helper: $helper" >&2; return 1; }
    sudo -H -u "$__user" python3 "$helper" --home "$user_home" --target "$target" --all
}

function _tarave_bootstrap_retropie_menu() {
    local user_home="$1"
    local script="$md_inst/bootstrap-retropiemenu.py"
    [[ -f "$script" ]] || {
        echo "Missing Tarave RetroPie menu bootstrap: $script" >&2
        return 1
    }
    sudo -H -u "$__user" python3 "$script" \
        --home "$user_home" \
        --tarave-home "$user_home/.local/share/batocera-es-test" \
        --setup-dir "$user_home/RetroPie-Setup"
}

function _tarave_import_missing_systems() {
    local user_home="$1"
    local catalog="/opt/retropie/configs/all/emulationstation/es_systems.cfg"
    if [[ ! -r "$catalog" ]]; then
        catalog="/etc/emulationstation/es_systems.cfg"
    fi
    local importer="$md_inst/resources/tarave-import-legacy-systems.py"
    local dst="$user_home/.local/share/batocera-es-test/.emulationstation/es_systems_legacy_import.cfg"
    [[ -f "$importer" ]] || { echo "Missing systems import helper: $importer" >&2; return 1; }
    sudo -H -u "$__user" python3 "$importer" --source-home "$user_home" \
        --destination "$dst" --catalog "$catalog"
}

# Preserve the update behavior of classic RetroPie. For a shared catalog,
# the normal Tarave launcher will install a link to the canonical shared path.
# For a separate manually maintained user catalog, make a one-time private
# snapshot without touching the prior EmulationStation installation.
function _tarave_import_previous_system_catalog() {
    local prior="$1"
    local private="$2"
    shift 2
    if [[ ! -f "$prior" || -e "$private" || -L "$private" ]]; then
        return 0
    fi

    local canonical_prior
    canonical_prior="$(readlink -f -- "$prior")" || return 0
    local shared
    for shared in "$@"; do
        if [[ -f "$shared" && "$canonical_prior" == "$(readlink -f -- "$shared")" ]]; then
            echo "Tarave: prior system catalog is RetroPie's shared catalog; keeping it live."
            return 0
        fi
    done

    # Another independent ES instance can have fully custom definitions.
    # Validate first; never replace an existing Tarave system file.
    if sudo -H -u "$__user" python3 -c \
        'import sys,xml.etree.ElementTree as ET;sys.exit(0 if ET.parse(sys.argv[1]).getroot().tag=="systemList" else 1)' \
        "$prior"; then
        sudo -H -u "$__user" cp -n -- "$prior" "$private" || {
            echo "Warning: previous custom es_systems.cfg could not be copied." >&2
            return 1
        }
        echo "Tarave: imported independently customized es_systems.cfg, original preserved."
    else
        echo "Warning: previous es_systems.cfg is invalid XML; skipping private copy." >&2
    fi
}

function configure_batocera-es-test() {
    [[ "$md_mode" == "remove" ]] && return 0

    local launcher="/usr/local/bin/batocera-es-test"
    local target="$md_inst/batocera-es-test.sh"
    local user_root="$home/.local/share/batocera-es-test"
    local user_cfg="$user_root/.emulationstation"

    # Unlike RetroPie's regular EmulationStation package, this must NEVER
    # moveConfigDir ~/.emulationstation, install global themes, or reconfigure
    # the controller mapping of the other frontend.
    # Explicitly create the XDG parents as the login user as well. On a
    # fresh Debian home ~/.local/share may not exist yet; leaving those
    # ancestors root-owned would break normal non-root applications.
    for directory in "$home/.local" "$home/.local/share" \
                     "$user_root" "$user_cfg" "$user_cfg/themes" \
                     "$user_cfg/gamelists" "$user_cfg/music" \
                     "$user_cfg/themesettings" "$user_cfg/padtokey"; do
        mkdir -p "$directory" || return 1
        chown "$__user:$__group" "$directory" || return 1
    done
    _tarave_seed_default_theme "$user_cfg" || return 1

    # Previous RetroPie config may have Wine/Kodi/Ports and any custom
    # systems. Copy the entire gamelists tree non-destructively; on a clean
    # installation, at least recover RetroPie Setup's gamelist metadata.
    local sync_helper="$md_data/retropie-gamelist-sync.py"
    if [[ ! -f "$sync_helper" ]]; then
        echo "Missing Tarave module resource: $sync_helper" >&2
        return 1
    fi
    install -m 755 -- "$sync_helper" "$md_inst/retropie-gamelist-sync.py" || return 1
    # Also refresh the Python-only system importer without requiring another
    # 30-minute ARM build. Only application resource code is replaced, never
    # the user's saved Tarave/RetroPie/ES-X configurations or games.
    local system_helper="$md_data/tarave-import-legacy-systems.py"
    [[ -f "$system_helper" ]] || {
        echo "Missing Tarave system importer: $system_helper" >&2
        return 1
    }
    mkdir -p "$md_inst/resources" || return 1
    install -m 644 -- "$system_helper" "$md_inst/resources/tarave-import-legacy-systems.py" || return 1
    local menu_helper="$md_data/bootstrap-retropiemenu.py"
    [[ -f "$menu_helper" ]] || {
        echo "Missing Tarave private RetroPie bootstrap resource: $menu_helper" >&2
        return 1
    }
    install -m 755 -- "$menu_helper" "$md_inst/bootstrap-retropiemenu.py" || return 1

    # Classic RetroPie often points ~/.emulationstation/es_systems.cfg at
    # /opt/retropie/configs/all/emulationstation/es_systems.cfg (or /etc).
    # Keep tracking that authoritative catalog, so future emulators/systems
    # continue to appear in Tarave. Copy only a truly independent user file.
    _tarave_import_previous_system_catalog \
        "$home/.emulationstation/es_systems.cfg" \
        "$user_cfg/es_systems.cfg" \
        "/opt/retropie/configs/all/emulationstation/es_systems.cfg" \
        "/etc/emulationstation/es_systems.cfg" || return 1

    _tarave_sync_all_gamelists "$home" ||
        echo "Warning: previous gamelists sync failed; frontend files remain installed." >&2
    # A gamelist only provides artwork/metadata; the corresponding system
    # (Wine and other custom ones) must also exist in es_systems.cfg. Import
    # only definitions absent from the shared RetroPie catalog, without
    # overwriting user customizations. No dependency on the old frontend.
    _tarave_import_missing_systems "$home" ||
        echo "Warning: missing-system import failed; leaving other configurations untouched." >&2

    # On fresh installs, no previous EmulationStation metadata may exist.
    # Generate independent .rp shortcuts, menu icons and gamelist entries,
    # registering a private RetroPie system if the shared menu is absent.
    # Never invoke 'retropiemenu configure': it would alter ES-X/RetroPie.
    _tarave_bootstrap_retropie_menu "$home" ||
        echo "Warning: Tarave private RetroPie menu bootstrap failed." >&2

    # Keep per-user data separate from ES-X and normal RetroPie configs.
    # Only /usr/bin/emulationstation is switched, with reversible backup.
    cat > "$target" <<'LAUNCHER'
#!/usr/bin/env bash
# Managed by the batocera-es-test RetroPie-Extra module.
set -e

if [[ "$(id -u)" -eq 0 ]]; then
    echo "Do not launch Batocera-ES as root." >&2
    exit 1
fi

inst_dir="$(dirname "$(readlink -f "$0")")"
user_home="${BATOCERA_ES_TEST_HOME:-$HOME/.local/share/batocera-es-test}"
user_cfg="$user_home/.emulationstation"

# The upstream Batocera "Minimal" theme is ~6-7 MiB, formatVersion 7.
# Installing it is explicitly opt-in: do not download during the lengthy
# source build, do not modify the selected ThemeSet, and never overwrite
# existing theme folders. The original upstream attribution stays intact.
if [[ "${1:-}" == "--install-minimal-theme" ]]; then
    shift
    if (( $# != 0 )); then
        echo "Usage: batocera-es-test --install-minimal-theme" >&2
        exit 2
    fi
    themes="$user_cfg/themes"
    target="$themes/minimal"
    mkdir -p "$themes"
    if [[ -e "$target" || -L "$target" ]]; then
        echo "Minimal theme is already present at $target; leaving it unchanged."
        exit 0
    fi
    temp="$(mktemp -d "$themes/.minimal-install.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    if ! git clone --depth 1 --single-branch --quiet \
        https://github.com/crcerror/es-theme-minimal.git "$temp/source"; then
        echo "Could not download Minimal theme; existing Tarave data was not changed." >&2
        exit 1
    fi
    if [[ ! -r "$temp/source/theme.xml" ]] || \
       ! grep -Eq '<formatVersion>7</formatVersion>' "$temp/source/theme.xml"; then
        echo "Unexpected upstream Minimal theme format; not installing." >&2
        exit 1
    fi
    # A theme is a collection of XML and assets. Strip Git history from
    # the staged copy to keep the actual installed footprint small.
    rm -rf -- "$temp/source/.git"
    if [[ -e "$target" || -L "$target" ]]; then
        echo "Minimal theme appeared meanwhile; preserving it."
        exit 0
    fi
    mv -- "$temp/source" "$target"
    echo "Installed upstream Minimal theme: $target"
    echo "Select 'minimal' in Tarave's UI Settings > Theme Set."
    echo "Credits: lilbud / fabricecaruso / crcerror. License CC-BY-NC-SA."
    exit 0
fi

# Refresh metadata without recompiling; --sync-gamelists includes all older
# systems and still refreshes RetroPie Setup. No changes to legacy XML files.
if [[ "${1:-}" == "--sync-gamelists" ]]; then
    shift
    if (( $# != 0 )); then
        echo "Usage: batocera-es-test --sync-gamelists" >&2
        exit 2
    fi
    exec python3 "$inst_dir/retropie-gamelist-sync.py" \
        --home "$HOME" \
        --target "$user_cfg/gamelists/retropie/gamelist.xml" --all
fi

# An explicit standalone bootstrap of fresh-install RetroPie Setup shortcuts,
# even when no original gamelist/retropiemenu directory exists.
if [[ "${1:-}" == "--initialize-retropie-menu" ]]; then
    shift
    if (( $# != 0 )); then
        echo "Usage: batocera-es-test --initialize-retropie-menu" >&2
        exit 2
    fi
    exec python3 "$inst_dir/bootstrap-retropiemenu.py" \
        --home "$HOME" --tarave-home "$user_home" \
        --setup-dir "$HOME/RetroPie-Setup"
fi

# Keep a lighter RetroPie-menu-only refresh operation, too.
if [[ "${1:-}" == "--sync-retropie-menu" ]]; then
    shift
    if (( $# != 0 )); then
        echo "Usage: batocera-es-test --sync-retropie-menu" >&2
        exit 2
    fi
    exec python3 "$inst_dir/retropie-gamelist-sync.py" \
        --home "$HOME" \
        --target "$user_cfg/gamelists/retropie/gamelist.xml"
fi

# Explicit manual re-import of missing legacy system definitions, in addition
# to the automatic installation-time migration. Original systems stay intact.
if [[ "${1:-}" == "--retropie-menu-check" ]]; then
    shift
    if (( $# != 0 )); then
        echo "Usage: batocera-es-test --retropie-menu-check" >&2
        exit 2
    fi
    exec bash "$inst_dir/scripts/tarave-retropie-menu.sh" --check
fi

if [[ "${1:-}" == "--import-legacy-systems" ]]; then
    shift
    if (( $# != 0 )); then
        echo "Usage: batocera-es-test --import-legacy-systems" >&2
        exit 2
    fi
    import_catalog="/etc/emulationstation/es_systems.cfg"
    if [[ -r /opt/retropie/configs/all/emulationstation/es_systems.cfg ]]; then
        import_catalog="/opt/retropie/configs/all/emulationstation/es_systems.cfg"
    fi
    exec python3 "$inst_dir/resources/tarave-import-legacy-systems.py" \
        --destination "$user_cfg/es_systems_legacy_import.cfg" \
        --catalog "$import_catalog"
fi

# Opt-in console/DRM test. Never changes the graphical default, RetroPie
# autostart, display manager, or the globally installed frontend.
tty_test=0
if [[ "${1:-}" == "--tty-test" ]]; then
    tty_test=1
    shift
    local_tty="$(tty 2>/dev/null || true)"
    if [[ ! "$local_tty" =~ ^/dev/tty[0-9]+$ ]]; then
        echo "TTY test requires a physical Linux console (Ctrl+Alt+F3), not SSH or a terminal emulator." >&2
        exit 2
    fi
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        echo "Graphical session detected. Log in to a fresh text TTY before --tty-test." >&2
        exit 2
    fi
    if ! compgen -G '/dev/dri/card[0-9]*' >/dev/null; then
        echo "No /dev/dri/card* found; kernel DRM/KMS is required for SDL kmsdrm." >&2
        exit 2
    fi
    export SDL_VIDEODRIVER=kmsdrm
    export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
    echo "Trying native DRM/KMS on $local_tty with SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
    echo "If X11/Wayland still owns the GPU, quit the desktop before retrying."
fi

mkdir -p "$user_cfg"

# RetroPie allows a user's system catalog at
# /opt/retropie/configs/all/emulationstation/es_systems.cfg, which may list
# Kodi, Wine or other extras missing in the global /etc definition. Prefer it,
# but never import/share the old frontend's settings or input mappings.
user_catalog="/opt/retropie/configs/all/emulationstation/es_systems.cfg"
default_catalog="/etc/emulationstation/es_systems.cfg"
if [[ ! -r "$user_catalog" ]]; then
    user_catalog="$default_catalog"
fi
if [[ ! -e "$user_cfg/es_systems.cfg" && ! -L "$user_cfg/es_systems.cfg" ]]; then
    if [[ -r "$user_catalog" ]]; then
        ln -s -- "$user_catalog" "$user_cfg/es_systems.cfg"
    else
        echo "Warning: no RetroPie es_systems.cfg found (Tarave needs a configured system catalog)." >&2
    fi
elif [[ -L "$user_cfg/es_systems.cfg" &&
        "$(readlink "$user_cfg/es_systems.cfg")" == "$default_catalog" &&
        "$user_catalog" != "$default_catalog" ]]; then
    # Refresh only the previous symlink created by this module. Never rewrite
    # regular/private configuration files or foreign symlinks.
    ln -sfn -- "$user_catalog" "$user_cfg/es_systems.cfg"
fi

cd "$inst_dir"
if (( tty_test )); then
    # Tee is used only for this interactive test so that the prompt returns
    # and SDL failures remain visible for diagnosis.
    log_dir="$user_home/tty-test"
    mkdir -p "$log_dir"
    log_file="$log_dir/last-run.log"
    set -o pipefail
    "$inst_dir/emulationstation" --home "$user_home" "$@" 2>&1 | tee "$log_file"
    result="${PIPESTATUS[0]}"
    echo "ES-X Next console test exit status: $result"
    echo "TTY test log: $log_file"
    exit "$result"
fi
exec "$inst_dir/emulationstation" --home "$user_home" "$@"
LAUNCHER

    chmod 755 "$target"
    mkdir -p "$(dirname "$launcher")"

    # Do not overwrite an unrelated command owned by the user/system.
    if [[ -e "$launcher" || -L "$launcher" ]]; then
        if [[ ! -L "$launcher" || "$(readlink "$launcher")" != "$target" ]]; then
            echo "Refusing to replace an existing $launcher" >&2
            return 1
        fi
    fi
    ln -sfn "$target" "$launcher"

    if isPlatform "x11"; then
        _tarave_desktop_entry || return 1
    fi
    _tarave_direct_installer || return 1

    # Source installs exclusively select Tarave, removing registered old
    # frontend packages after building and configuring Tarave successfully.
    _tarave_activate_after_install /usr/bin/emulationstation "$launcher" \
        "$md_inst/.tarave-activate-after-install" || return 1
}

# Activation and package cleanup occur only when a successful source
# installation left a marker. Configure-only calls remain non-destructive.
function _tarave_activate_after_install() {
    local entry="$1"
    local launcher="$2"
    local marker="$3"

    if [[ ! -e "$marker" ]]; then
        if _batocera_es_test_owns_entry "$entry"; then
            echo "Tarave is already the active EmulationStation frontend."
        else
            echo "Tarave is installed; leaving the user's existing frontend selection unchanged."
        fi
        return 0
    fi

    # The new Tarave executable is already built and installed at this point.
    # Remove old frontend packages through the registered RetroPie-Setup
    # module hooks, without deleting shared RetroPie or per-user data.
    # Some removal hooks clear /usr/bin/emulationstation; re-create Tarave's
    # launcher immediately afterwards, even when an old package fails removal.
    local cleanup_ok=1
    if ! _tarave_remove_competing_frontends; then
        cleanup_ok=0
        echo "Warning: an older frontend could not be fully uninstalled." >&2
    fi
    if ! _batocera_es_test_activate "$entry" "$launcher"; then
        echo "Tarave installation completed but activation failed." >&2
        return 1
    fi
    (( cleanup_ok )) || return 1

    # Previous launcher wrappers are no longer useful: those programs were
    # removed. Discard only backups bearing Tarave's own managed suffix.
    local backup="${entry}.batocera-es-test.previous"
    local archive
    if [[ -f "$backup" || -L "$backup" ]]; then
        rm -f -- "$backup" || return 1
    fi
    for archive in "${backup}".archived.*; do
        if [[ -f "$archive" || -L "$archive" ]]; then
            rm -f -- "$archive" || return 1
        fi
    done
    # Configure the first boot after successful activation, not during build
    # or a configure-only call. A failed setup leaves the marker for retry.
    _tarave_configure_boot "$launcher" || return 1
    rm -f -- "$marker" || return 1
}

function remove_batocera-es-test() {
    _tarave_remove_managed_desktop_boot || return 1
    # An exclusive installation cannot restore uninstalled frontends.
    # Only remove the launcher if it still belongs to Tarave.
    local entry="/usr/bin/emulationstation"
    if _batocera_es_test_owns_entry "$entry"; then
        rm -f -- "$entry" || return 1
        echo "Tarave launcher removed. Install another frontend separately if needed."
    fi

    local launcher="/usr/local/bin/batocera-es-test"
    local target="$md_inst/batocera-es-test.sh"

    if [[ -L "$launcher" && "$(readlink "$launcher")" == "$target" ]]; then
        rm -f "$launcher"
    fi

    local desktop="/usr/local/share/applications/tarave-es-next.desktop"
    if [[ -f "$desktop" ]] && grep -Fqx '# TARAVE_ES_NEXT_MANAGED=1' "$desktop"; then
        rm -f -- "$desktop"
    fi
    local direct_launcher="/usr/local/bin/tarave-install"
    local direct_installed="$md_inst/install-direct.sh"
    if [[ -L "$direct_launcher" && "$(readlink "$direct_launcher")" == "$direct_installed" ]]; then
        rm -f -- "$direct_launcher"
    fi
    local direct_desktop="/usr/local/share/applications/tarave-install.desktop"
    if [[ -f "$direct_desktop" ]] &&
       grep -Fqx '# TARAVE_DIRECT_INSTALL_MANAGED=1' "$direct_desktop"; then
        rm -f -- "$direct_desktop"
    fi

    # All user ROMs, gamelists, themes, input maps and shared configs remain.
}

# Tarave maintenance. An explicit repair can apply exclusive mode to an
# already installed Tarave without recompiling the frontend.
function gui_batocera-es-test() {
    local choice
    local launcher="/usr/local/bin/batocera-es-test"
    while true; do
        choice="$(dialog --backtitle "RetroPie - Tarave" \
            --menu "Tarave management (ROMs and settings are preserved)" 16 72 8 \
            1 "Activate Tarave and uninstall classic ES / ES-X packages" \
            2 "Show native TTY test instructions" \
            3 "Reimport missing custom systems (Wine, Kodi, etc.)" \
            4 "Refresh RetroPie Setup icons/descriptions" \
            5 "Import existing gamelists (Wine, Kodi, Ports, etc.)" \
            6 "Download lightweight Batocera Minimal theme" \
            7 "Initialize independent RetroPie Setup menu" \
            2>&1 >/dev/tty)" || break
        case "$choice" in
            1)
               if dialog --backtitle "RetroPie - Tarave" --yesno \
                   "Uninstall classic ES and ES-X program files? Existing ROMs, themes and configurations are kept." 10 72; then
                   # Tarave's own binary is already installed at this point.
                   _tarave_remove_competing_frontends || return 1
                   _batocera_es_test_activate /usr/bin/emulationstation "$launcher" || return 1
                   local backup="/usr/bin/emulationstation.batocera-es-test.previous"
                   local archived
                   rm -f -- "$backup" || return 1
                   for archived in "${backup}".archived.*; do
                       if [[ -f "$archived" || -L "$archived" ]]; then
                           rm -f -- "$archived" || return 1
                       fi
                   done
               fi
               break ;;
            2) echo "Use batocera-es-test --tty-test from a physical text console."; break ;;
            3) _tarave_import_missing_systems "$home" || return 1
               echo "Missing system definitions merged into Tarave's private catalog."
               break ;;
            4) _tarave_sync_retropie_menu "$home" || return 1
               echo "Tarave RetroPie menu refreshed. Restart the frontend to reload the list."
               break ;;
            5) _tarave_sync_all_gamelists "$home" || return 1
               echo "Previous gamelists imported. Restart Tarave to reload metadata."
               break ;;
            6) sudo -H -u "$__user" "$launcher" --install-minimal-theme || return 1
               echo "Select theme 'minimal' in Tarave UI Settings > Theme Set."
               break ;;
            7) _tarave_bootstrap_retropie_menu "$home" || return 1
               echo "Independent RetroPie Setup shortcuts and metadata initialized."
               break ;;
        esac
    done
}
