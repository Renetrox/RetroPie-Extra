#!/usr/bin/env bash
#
# Batocera-ES (Renetrox standalone experiment) for RetroPie
#
# ES-X Next installs as RetroPie's active EmulationStation entrypoint.
# The previous /usr/bin/emulationstation launcher is preserved for rollback.
# This module never removes ES-X or rewrites its saved settings.
#
# This installs the non-BATOCERA build of the experimental fork.
# Batocera-specific services, launch hooks, and emulator hotkeys are
# NOT provided by this package.

rp_module_id="batocera-es-test"
rp_module_desc="ES-X Next (Batocera-ES fork) - RetroPie frontend with reversible launcher takeover"
rp_module_help="ES-X Next for Linux/RetroPie.\n\nAfter installation the usual emulationstation command (including RetroPie autostart) launches ES-X Next.\nThe previous executable/launcher is backed up as /usr/bin/emulationstation.batocera-es-test.previous and restored on removal.\nES-X and its settings are not deleted.\n\nDirect launch: batocera-es-test\nUser settings: $home/.local/share/batocera-es-test/.emulationstation\nUses RetroPie's /etc/emulationstation/es_systems.cfg if present."
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
        libudev-dev gettext
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
        "LICENSE.md"
        "README.md"
    )
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
        echo "ES-X Next entrypoint unavailable: $command" >&2
        return 1
    fi

    # Do not overwrite a launcher that another installer has since taken over.
    if [[ ( -e "$backup" || -L "$backup" ) ]] && ! _batocera_es_test_owns_entry "$entry"; then
        echo "Existing backup at $backup, but $entry belongs to another frontend." >&2
        echo "Leaving both unchanged. Restore/remove that launcher before switching." >&2
        return 1
    fi

    local tmp moved_original=0
    tmp="$(mktemp "${entry}.batocera-es-test.XXXXXX")" || return 1
    {
        printf '#!/usr/bin/env bash\n'
        printf '# BATOCERA_ES_TEST_MANAGED_ENTRYPOINT=1\n'
        printf '# RetroPie frontend selector, managed by batocera-es-test.\n'
        printf 'exec %q "$@"\n' "$command"
    } > "$tmp"
    if ! chmod 755 "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    if ! _batocera_es_test_owns_entry "$entry" && [[ -e "$entry" || -L "$entry" ]]; then
        if ! mv -T -- "$entry" "$backup"; then
            rm -f "$tmp"
            echo "Could not preserve existing EmulationStation launcher." >&2
            return 1
        fi
        moved_original=1
    fi

    if ! mv -fT -- "$tmp" "$entry"; then
        rm -f "$tmp"
        if (( moved_original )); then
            mv -T -- "$backup" "$entry" || true
        fi
        echo "Could not enable ES-X Next launcher." >&2
        return 1
    fi

    echo "ES-X Next is now the active EmulationStation frontend: $entry"
    if [[ -e "$backup" || -L "$backup" ]]; then
        echo "Previous launcher saved at: $backup"
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

function configure_batocera-es-test() {
    [[ "$md_mode" == "remove" ]] && return 0

    local launcher="/usr/local/bin/batocera-es-test"
    local target="$md_inst/batocera-es-test.sh"

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

# Reference RetroPie's system catalog without copying or modifying it.
# A user's own file is preferred over this link and is never overwritten.
if [[ ! -e "$user_cfg/es_systems.cfg" && ! -L "$user_cfg/es_systems.cfg" ]]; then
    if [[ -r /etc/emulationstation/es_systems.cfg ]]; then
        ln -s /etc/emulationstation/es_systems.cfg "$user_cfg/es_systems.cfg"
    else
        echo "Warning: no RetroPie es_systems.cfg found at /etc/emulationstation." >&2
    fi
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

    # RetroPie autostart.sh and desktop entry already call "emulationstation".
    # Interpose a small launcher instead of uninstalling or overwriting ES-X.
    _batocera_es_test_activate /usr/bin/emulationstation "$launcher" || return 1
}

function remove_batocera-es-test() {
    # Restore the earlier frontend BEFORE the installed Next files disappear.
    _batocera_es_test_restore /usr/bin/emulationstation || return 1

    local launcher="/usr/local/bin/batocera-es-test"
    local target="$md_inst/batocera-es-test.sh"

    if [[ -L "$launcher" && "$(readlink "$launcher")" == "$target" ]]; then
        rm -f "$launcher"
    fi

    # User settings, gamelists, and original EmulationStation remain untouched.
}
