# Fix: Mupen64Plus profile-name matching in RetroPie-Setup

RetroPie's EmulationStation Mupen64Plus input converter at
`scriptmodules/supplementary/emulationstation/configscripts/mupen64plus.sh`
checks whether a profile already exists using:

```bash
if grep -Fq "$DEVICE_NAME" "$file" ; then
```

This tests for a substring **anywhere** in InputAutoCfg.ini.
When `[GamepadPlus]` exists, it incorrectly treats `Gamepad` as registered,
even when `[Gamepad]` is missing. This prevented the newly named
`Gamepad` profile from being created on an Orange Pi 4A.

The minimal replacement:

```bash
if grep -Fxq "[$DEVICE_NAME]" "$file" ; then
```

tests for the **whole literal section header**, consistent with the
`[${DEVICE_NAME}]` header the configuration generator writes.

## Reproduce and optionally apply

```bash
bash tests/test-mupen64plus-profile-match.sh
bash tools/fix-mupen64plus-profile-match.sh
```

The fixer accepts an optional explicit target script path, makes a
timestamped backup and is idempotent. It refuses unknown variants.
It changes only the *generator*, not the user's InputAutoCfg.ini.

A RetroPie-Setup update can replace this local change. The independent
`mupen64plus-frameskip` installer will **not** patch official files
without permission.

Tests cover `Gamepad` versus `GamepadPlus`/`Gamepad-igs`,
literal metacharacters, backup, and repeated application.
A real controller remap on the Orange Pi must still be smoke-tested.
