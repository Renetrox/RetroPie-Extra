#!/usr/bin/env bash

# This file is part of RetroPie-Extra, a supplement to RetroPie.
# FreeJ2ME-Plus module adapted for the current TASEmulators fork.

rp_module_id="lr-freej2me-plus"
rp_module_desc="Java ME emulator - FreeJ2ME-Plus libretro core."
rp_module_help="ROM Extensions: .jar .JAR\n\nCopy your Java ME (J2ME) ROMs to $romdir/j2me\n\nThe matching freej2me-lr.jar will be installed automatically in $biosdir."
rp_module_licence="GPL3 https://raw.githubusercontent.com/TASEmulators/freej2me-plus/devel/LICENSE"
rp_module_repo="git https://github.com/TASEmulators/freej2me-plus.git devel"
rp_module_section="exp"
rp_module_flags=""

function depends_lr-freej2me-plus() {
    getDepends ant default-jdk
}

function sources_lr-freej2me-plus() {
    gitPullOrClone
}

function build_lr-freej2me-plus() {
    # Current upstream build.xml still targets Java 6. Modern JDKs reject
    # -source/-target 1.6, while 1.7 builds successfully for our RetroPie test.
    sed -i 's/<property name="source.version" value="1\.6"\/>/<property name="source.version" value="1.7"\/>/' build.xml
    sed -i 's/<property name="target.version" value="1\.6"\/>/<property name="target.version" value="1.7"\/>/' build.xml

    ant

    make -C src/libretro clean
    make -C src/libretro

    md_ret_require="$md_build/src/libretro/freej2me_plus_libretro.so"
}

function install_lr-freej2me-plus() {
    md_ret_files=(
        'build/freej2me.jar'
        'build/freej2me-lr.jar'
        'src/libretro/retropie.txt'
        'src/libretro/freej2me_plus_libretro.so'
    )
}

function configure_lr-freej2me-plus() {
    mkRomDir "j2me"
    ensureSystemretroconfig "j2me"

    addEmulator 1 "$md_id" "j2me" "$md_inst/freej2me_plus_libretro.so"
    addSystem "j2me" "J2ME" ".jar .JAR"

    # The libretro core starts freej2me-lr.jar from RetroArch's system directory.
    # Keep the Java side matched to the native core installed by this module.
    cp -v "$md_inst/freej2me-lr.jar" "$biosdir/freej2me-lr.jar"
    chown "$user:$user" "$biosdir/freej2me-lr.jar"
}
