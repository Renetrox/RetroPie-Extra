#!/usr/bin/env bash
# RetroPie-Setup module for Renetrox OpenBOR 4.0 ARM64
# Uses the tested BUILD_LINUX_LE_arm64 target from OpenBOR-Opi-3-linux-arm64.

rp_module_id="openbor4"
rp_module_desc="OpenBOR 4.0 (Renetrox Linux ARM64)"
rp_module_help="Place your .pak files in $romdir/openbor"
rp_module_section="exp"
rp_module_flags=""
rp_module_licence="BSD https://raw.githubusercontent.com/Renetrox/OpenBOR-Opi-3-linux-arm64/main/LICENSE"

function depends_openbor4() {
    getDepends \
        git \
        build-essential \
        pkg-config \
        libsdl2-dev \
        libpng-dev \
        libvorbis-dev \
        libvpx-dev \
        zlib1g-dev
}

function sources_openbor4() {
    gitPullOrClone "$md_build" https://github.com/Renetrox/OpenBOR-Opi-3-linux-arm64.git main
}

function build_openbor4() {
    cd "$md_build/engine" || return 1

    # This fork has a native Linux ARM64 Makefile target.
    # Do not use the root CMake build: it follows a different build path.
    make clean || true
    make BUILD_LINUX_LE_arm64=1 -j"$(nproc)" || return 1

    md_ret_require="$md_build/engine/OpenBOR"
}

function install_openbor4() {
    md_ret_files=(
        "engine/OpenBOR"
    )
}

function configure_openbor4() {
    mkRomDir "openbor"

    # OpenBOR expects Paks/Saves/ScreenShots/Logs relative to its cwd.
    # The wrapper only sets cwd; it never writes inside /opt at runtime.
    cat >"$md_inst/openbor.sh" <<'EOF'
#!/usr/bin/env bash
set -e
INST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INST_DIR"
exec "$INST_DIR/OpenBOR"
EOF
    chmod +x "$md_inst/openbor.sh"

    addEmulator 1 "$md_id" "openbor" "$md_inst/openbor.sh"
    addSystem "openbor" "OpenBOR" ".pak .PAK"

    for dir in Saves ScreenShots; do
        mkUserDir "$md_conf_root/openbor/$md_id/$dir"
    done

    rm -rf "$md_inst/Paks" "$md_inst/Saves" "$md_inst/ScreenShots" "$md_inst/Logs"

    ln -s "$romdir/openbor" "$md_inst/Paks"
    ln -s "$md_conf_root/openbor/$md_id/Saves" "$md_inst/Saves"
    ln -s "$md_conf_root/openbor/$md_id/ScreenShots" "$md_inst/ScreenShots"
    ln -s "/dev/shm" "$md_inst/Logs"
}