#!/usr/bin/env bash
#
# Mupen64Plus-ReARMed: restoration-focused libretro core.
# Kept separate from standalone mupen64plus-frameskip and stock N64 cores.

rp_module_id="lr-mupen64plus-rearmed"
rp_module_desc="Nintendo 64 emulator - Mupen64Plus-ReARMed (legacy renderers and frameskip)"
rp_module_help="ROM Extensions: .z64 .n64 .v64 .zip\n\nCopy Nintendo 64 ROMs to $romdir/n64\n\nDefaults to Glide64 when available. Select a different renderer from RetroArch Core Options if needed."
rp_module_licence="GPL2 https://github.com/libretro/parallel-n64"
rp_module_repo="git https://github.com/Renetrox/Mupen64Plus-ReARMed.git frameskip-modern"
rp_module_section="exp"
rp_module_flags=""

function depends_lr-mupen64plus-rearmed() {
    getDepends build-essential pkg-config libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev zlib1g-dev
}

function sources_lr-mupen64plus-rearmed() {
    gitPullOrClone
}

function build_lr-mupen64plus-rearmed() {
    local args=()
    # GLES-only systems should build the fast legacy GL path without GLideN64.
    if isPlatform "gles"; then
        args+=(FORCE_GLES=1)
    fi

    # Preserve RetroPie's default CPU architecture autodetection in Makefile.
    # Limit concurrency for low-RAM SBCs such as Orange Pi.
    make "${args[@]}" clean
    make -j2 "${args[@]}"

    md_ret_require="$md_build/mupen64plus_rearmed_libretro.so"
}

function install_lr-mupen64plus-rearmed() {
    md_ret_files=('mupen64plus_rearmed_libretro.so')
}

function configure_lr-mupen64plus-rearmed() {
    mkRomDir "n64"
    ensureSystemretroconfig "n64"

    # Do not replace users' existing N64 default emulator.
    addEmulator 0 "$md_id" "n64" "$md_inst/mupen64plus_rearmed_libretro.so"
    addSystem "n64"
}
