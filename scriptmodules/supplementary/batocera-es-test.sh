#!/usr/bin/env bash
#
# Batocera-ES (Renetrox standalone experiment) for RetroPie
#
# Side-by-side test package: DOES NOT replace /usr/bin/emulationstation,
# DOES NOT remove ES-X, and DOES NOT rewrite the user's existing
# ~/.emulationstation or /etc/emulationstation settings.
#
# This installs the non-BATOCERA build of the experimental fork.
# Native scraping and manual controller configuration use the Tarave bridges.
# Batocera distribution services are not provided by this package.

rp_module_id="batocera-es-test"
rp_module_desc="Tarave-ES - experimental RetroPie frontend (Batocera base)"
rp_module_help="Tarave-ES experiment for Linux/RetroPie.\n\nLaunch from an X11 desktop with: batocera-es-test\n\nUser settings: $home/.local/share/batocera-es-test/.emulationstation\nUses RetroPie's /etc/emulationstation/es_systems.cfg if present.\n\nDoes not replace EmulationStation/ES-X. Includes native scrapers and a RetroPie controller bridge. Emulator support depends on installed RetroPie configurators."
rp_module_licence="MIT https://github.com/Renetrox/batocera-emulationstation/blob/master/LICENSE.md"
rp_module_repo="git https://github.com/Renetrox/batocera-emulationstation.git experiment/skyscraper-gui-prototype"
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
        -DTARAVE_ESX_SCRAPER_COMPAT=ON
        -DTARAVE_ENABLE_SKYSCRAPER=OFF
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

function configure_batocera-es-test() {
    [[ "$md_mode" == "remove" ]] && return 0

    local launcher="/usr/local/bin/batocera-es-test"
    local target="$md_inst/batocera-es-test.sh"

    # Never replace the system EmulationStation executable or startup script.
    # Keep per-user data separate from ES-X and normal RetroPie configs.
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
}

function remove_batocera-es-test() {
    local launcher="/usr/local/bin/batocera-es-test"
    local target="$md_inst/batocera-es-test.sh"

    if [[ -L "$launcher" && "$(readlink "$launcher")" == "$target" ]]; then
        rm -f "$launcher"
    fi

    # User settings, gamelists, and original EmulationStation remain untouched.
}
