#!/usr/bin/env bash
#
# Tarave standalone frontend module for RetroPie
#
# Installs its own executable and private settings, and becomes the default
# RetroPie EmulationStation frontend after a successful source install.
# The original ES/ES-X launcher is backed up for a reversible rollback.
# ROMs, emulators, settings and other frontend packages are never removed.
#
# This installs the non-BATOCERA build of the experimental fork.
# Batocera-specific services, launch hooks, and emulator hotkeys are
# NOT provided by this package.

rp_module_id="batocera-es-test"
rp_module_desc="Tarave - independent RetroPie frontend with safe automatic activation"
rp_module_help="Tarave for RetroPie.\n\nInstalls Tarave as the active RetroPie frontend, whether classic ES or ES-X was active before. The prior launcher is backed up, not uninstalled, and is restored when Tarave is removed.\nSettings, music and themes remain private. Set TARAVE_INSTALL_SIDE_BY_SIDE=1 to install without changing the default.\nThe previous /usr/bin/emulationstation launcher is saved and can be restored using this package's GUI.\n\nStart with: batocera-es-test\nDirect visible installer: tarave-install (from a terminal)\nInstall official Batocera Minimal theme: batocera-es-test --install-minimal-theme\nRefresh all previous gamelists: batocera-es-test --sync-gamelists\nInitialize isolated RetroPie menu: batocera-es-test --initialize-retropie-menu\nRefresh RetroPie Setup icons/metadata: batocera-es-test --sync-retropie-menu\nRe-import missing systems: batocera-es-test --import-legacy-systems\nConsole test: batocera-es-test --tty-test\nPrivate settings: $home/.local/share/batocera-es-test/.emulationstation\nSystems: /opt/retropie/configs/all/emulationstation/es_systems.cfg (if present), otherwise /etc/emulationstation/es_systems.cfg."
rp_module_licence="MIT https://github.com/Renetrox/batocera-emulationstation/blob/master/LICENSE.md"
rp_module_repo="git https://github.com/Renetrox/batocera-emulationstation.git experiment/retropie-standalone-20261013"
rp_module_section="exp"
rp_module_flags=""

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
        printf 'previous=%q\n' "$backup"
        cat <<'WRAPPER'
# On a real Linux text console with no X11/Wayland session, try the
# native SDL KMS/DRM driver. The previous working ES is the safety net
# if this GPU/SDL build cannot create a KMS/EGL context.
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "$(tty 2>/dev/null)" =~ ^/dev/tty[0-9]+$ ]]; then
    export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-kmsdrm}"
    export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
    if "$front" "$@"; then
        exit 0
    else
        status="$?"
        echo "ES-X Next console start failed (status $status)." >&2
        if [[ -x "$previous" ]] &&
           [[ "$(readlink -f "$previous")" != "$(readlink -f "$front")" ]]; then
            echo "Restoring the previous EmulationStation for this session." >&2
            unset SDL_VIDEODRIVER SDL_AUDIODRIVER
            exec "$previous" "$@"
        fi
        exit "$status"
    fi
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

    # A successful source install selects Tarave automatically, without
    # replacing the previous ES/ES-X package or touching its private data.
    # Source installs set the marker in install(); configure-only calls don't.
    _tarave_activate_after_install /usr/bin/emulationstation "$launcher" \
        "$md_inst/.tarave-activate-after-install" || return 1
}

# Activating as the default is the normal result of installing Tarave,
# just as installing ES-X makes it the selected RetroPie frontend.
# Explicit side-by-side installs remain supported; a later "configure" does
# not undo a user's decision to restore ES-X or classic EmulationStation.
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

    if [[ "${TARAVE_INSTALL_SIDE_BY_SIDE:-0}" == "1" ]] &&
       ! _batocera_es_test_owns_entry "$entry"; then
        echo "Tarave installed alongside existing EmulationStation (opt-out requested)."
        rm -f -- "$marker"
        return 0
    fi

    if ! _batocera_es_test_activate "$entry" "$launcher"; then
        echo "Tarave installation completed but automatic activation failed." >&2
        echo "The previous frontend was preserved; retry using the package's GUI." >&2
        return 1
    fi
    rm -f -- "$marker" || return 1
}

function remove_batocera-es-test() {
    # Restore the earlier frontend BEFORE the installed Next files disappear.
    _batocera_es_test_restore /usr/bin/emulationstation || return 1

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

    # Preserve ALL per-user Tarave/ES-X data, themes, input maps, ROMs and
    # RetroPie system catalogs. Package removal only unlinks installed launchers.
}

# Optional frontend switch. Existing desktop/tty RetroPie autostart invokes
# /usr/bin/emulationstation and will use the selected frontend after switching.
function gui_batocera-es-test() {
    local choice
    local launcher="/usr/local/bin/batocera-es-test"
    while true; do
        choice="$(dialog --backtitle "RetroPie - ES-X Next" \
            --menu "Select the active frontend (no ROM/config deletion)" 16 72 8 \
            1 "Activate ES-X Next as default" \
            2 "Restore previously installed EmulationStation / ES-X" \
            3 "Keep both; manually test with batocera-es-test --tty-test" \
            4 "Reimport missing custom systems (Wine, Kodi, etc.)" \
            5 "Refresh RetroPie Setup icon/descriptions in Tarave" \
            6 "Copy all previous gamelists (Wine, Kodi, Ports, etc.)" \
            7 "Download lightweight Batocera Minimal theme (optional)" \
            8 "Initialize independent RetroPie Setup menu in Tarave" \
            2>&1 >/dev/tty)" || break
        case "$choice" in
            1) _batocera_es_test_activate /usr/bin/emulationstation "$launcher" ;;
            2) _batocera_es_test_restore /usr/bin/emulationstation ;;
            3) echo "Use batocera-es-test --tty-test from a physical text console."; break ;;
            4) _tarave_import_missing_systems "$home" || return 1
               echo "Missing system definitions merged into Tarave's private catalog."
               break ;;
            5) _tarave_sync_retropie_menu "$home" || return 1
               echo "Tarave RetroPie menu refreshed. Restart the frontend to reload the list."
               break ;;
            6) _tarave_sync_all_gamelists "$home" || return 1
               echo "Previous gamelists imported. Restart Tarave to reload metadata."
               break ;;
            7) sudo -H -u "$__user" "$launcher" --install-minimal-theme || return 1
               echo "Select theme 'minimal' in Tarave UI Settings > Theme Set."
               break ;;
            8) _tarave_bootstrap_retropie_menu "$home" || return 1
               echo "Independent RetroPie Setup shortcuts and metadata initialized."
               break ;;
        esac
    done
}
