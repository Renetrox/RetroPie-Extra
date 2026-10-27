# Tarave as the only RetroPie frontend — exclusive installation

**Experimental module:** `scriptmodules/supplementary/batocera-es-test.sh` on
`experiment/batocera-es-standalone-module-20261013`.

Starting with this module version, a normal Tarave **source installation or
update** runs in **exclusive frontend mode** by default. The previous
`TARAVE_INSTALL_SIDE_BY_SIDE` opt-out is retired.

## What is removed, and when?

After Tarave's source has compiled and its private launcher/configuration
have been installed, the module asks **RetroPie-Setup itself** to uninstall
the following *registered, installed program packages* when present:

- `emulationstation-es-x`
- `emulationstation-dev`
- `emulationstation` (classic)

This uses `rp_callModule <name> remove`, not manual recursive deletion of
unrelated directories. Because RetroPie's built-in remove hooks can delete
`/usr/bin/emulationstation`, Tarave **recreates that command** to start
`batocera-es-test` after competing packages are removed.

Old Tarave-managed launcher backups are cleared **only after** the new
launcher is activated and all package removals have succeeded. On partial
failure, Tarave attempts to activate and leaves the install marker available
for a further explicit installation attempt.

This is a removal of previously installed frontend **program packages**, not
a purge of all content with “emulationstation” in its filename. An
unregistered, manually installed copy outside RetroPie-Setup is left
untouched rather than risking arbitrary deletion.

## What is preserved?

- `~/RetroPie/roms`, installed emulator binaries/cores and RetroArch configs.
- Shared `es_systems.cfg`, RetroPie Setup, ports, launch scripts.
- `~/.emulationstation`: ES / ES-X input maps, themes, scraped media,
  metadata and gamelists. Existing files remain available for migration.
- Tarave's own private data in
  `~/.local/share/batocera-es-test/.emulationstation`.

**Uninstall consequence:** Removing Tarave after an exclusive installation
will not automatically restore classic ES or ES-X; those executable packages
must be reinstalled separately. Do not enable this destructive mode until
Tarave is confirmed usable on the target SBC.

## Installing or updating

Register the experimental RetroPie-Extra module, then run `tarave-install`
from a terminal or launch its source-install action in RetroPie-Setup.
The build must succeed before other frontend packages are retired. The
install helper runs `retropie_packages.sh batocera-es-test _source_`.

An already-installed Tarave has an explicit **Tarave management →
Activate Tarave and uninstall classic ES / ES-X packages** GUI action,
which shows a confirmation dialog before removing other installed frontends.

## Regression checks

The repository's installer workflow validates Bash syntax, isolated
mocked RetroPie module removals, launcher reactivation, reinstallation
idempotence, private user data retention and the direct source installer
from a pseudo-terminal. Hardware testing (especially Orange Pi 4A,
TTY/KMS/DRM and video themes) remains necessary.

**Note:** Removing dormant frontend executables generally does not improve
Tarave's active performance. For freezes, capture Tarave's own logs,
`journalctl -b`, CPU/RAM statistics and VRAM/renderer settings.
