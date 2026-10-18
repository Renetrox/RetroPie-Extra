#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
script="$work/mupen64plus.sh"
cat > "$script" <<'FIXTURE'
if grep -Fq "$DEVICE_NAME" "$file" ; then
    rm /tmp/mp64tempconfig.cfg
    return
fi
FIXTURE

file="$work/InputAutoCfg.ini"
cat > "$file" <<'CONFIG'
; GamepadPlus_START
[GamepadPlus]
plugged = True
; GamepadPlus_END
[Gamepad-igs]
plugged = True
CONFIG

DEVICE_NAME='Gamepad'
if ! grep -Fq "$DEVICE_NAME" "$file"; then
    echo 'Original false-positive not reproduced!' >&2; exit 1
fi

bash "$root/tools/fix-mupen64plus-profile-match.sh" "$script"
grep -Fqx 'if grep -Fxq "[$DEVICE_NAME]" "$file" ; then' "$script"
profile_exists() { grep -Fxq "[$1]" "$file"; }

if profile_exists Gamepad; then echo 'False match for Gamepad!' >&2; exit 1; fi
profile_exists GamepadPlus
profile_exists Gamepad-igs
printf '[Gamepad]\n[Gamepad (X)]\n' >> "$file"
profile_exists Gamepad
profile_exists 'Gamepad (X)'
if profile_exists 'Gamepad .*'; then echo 'Regex false match!' >&2; exit 1; fi

before="$(find "$work" -maxdepth 1 -name 'mupen64plus.sh.bak-*' | wc -l)"
bash "$root/tools/fix-mupen64plus-profile-match.sh" "$script"
after="$(find "$work" -maxdepth 1 -name 'mupen64plus.sh.bak-*' | wc -l)"
[[ "$before" -eq 1 && "$after" -eq 1 ]]
echo 'PASS: exact profile matching, aliases, metacharacters, backup, idempotence'
