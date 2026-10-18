#!/usr/bin/env bash
# Does not write any system launcher; tests the module's isolated functions.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
home="$HOME"
source "$root/scriptmodules/supplementary/batocera-es-test.sh"
original="$temp/emulationstation"
next="$temp/next"
cat > "$original" <<'ORIGINAL'
#!/usr/bin/env bash
printf 'original:%s\n' "$*"
ORIGINAL
cat > "$next" <<'NEXT'
#!/usr/bin/env bash
if [[ "${MOCK_KMS_FAIL:-0}" == "1" ]]; then exit 42; fi
printf 'next:%s\n' "$*"
NEXT
chmod 755 "$next" "$original"
_batocera_es_test_activate "$original" "$next"
[[ "$("$original" 'hello world' '--angle=x y')" == 'next:hello world --angle=x y' ]]
[[ -x "$original.batocera-es-test.previous" ]]
# A second install/configure must be idempotent and preserve the prior binary.
_batocera_es_test_activate "$original" "$next"
[[ "$("$original.batocera-es-test.previous" 'old')" == 'original:old' ]]
# Simulate a physical TTY and a failed KMS/DRM EGL context. The previous
# frontend must be launched rather than leaving the RetroPie boot blank.
cat > "$temp/tty" <<'FAKETTY'
#!/usr/bin/env bash
echo /dev/tty3
FAKETTY
chmod 755 "$temp/tty"
tty_fallback="$(env -u DISPLAY -u WAYLAND_DISPLAY MOCK_KMS_FAIL=1 PATH="$temp:$PATH" "$original" 'back up')"
[[ "$tty_fallback" == 'original:back up' ]]
_batocera_es_test_restore "$original"
[[ "$("$original" 'hello world')" == 'original:hello world' ]]
[[ ! -e "$original.batocera-es-test.previous" ]]
# Never change a new command owned by another installer.
_batocera_es_test_activate "$original" "$next"
cat > "$original" <<'FOREIGN'
#!/usr/bin/env bash
echo foreign
FOREIGN
chmod 755 "$original"
if _batocera_es_test_activate "$original" "$next"; then
    echo 'ERROR: overwrote an entrypoint owned by another frontend' >&2
    exit 1
fi
[[ "$("$original")" == foreign ]]
[[ "$("$original.batocera-es-test.previous")" == 'original:' ]]
echo 'PASS: RetroPie entrypoint backup, quoted arguments and rollback'
