#!/usr/bin/env bash
# Regression: a real PTY receives interactive Tarave source-install output,
# while the working _source_ RetroPie path is invoked verbatim.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/scriptmodules/supplementary/batocera-es-test/install-direct.sh"
bash -n "$installer"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/user" "$scratch/bin"
setup="$scratch/RetroPie-Setup"
mkdir -p "$setup/ext/RetroPie-Extra/scriptmodules/supplementary"
touch "$setup/ext/RetroPie-Extra/scriptmodules/supplementary/batocera-es-test.sh"
cat > "$setup/retropie_packages.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'Mock RetroPie: %s\n' "$*"
[[ "$*" == "batocera-es-test _source_" ]] || exit 98
[[ "${MOCK_FAIL:-0}" == "1" ]] && exit 42
exit 0
MOCK
cat > "$scratch/bin/sudo" <<'MOCKSUDO'
#!/usr/bin/env bash
[[ "${1:-}" == "-v" ]] && exit 0
exec "$@"
MOCKSUDO
chmod +x "$setup/retropie_packages.sh" "$scratch/bin/sudo"
export PATH="$scratch/bin:$PATH"
export HOME="$scratch/user"
export TARAVE_RETROPIE_SETUP="$setup"

# Without a real terminal, do not run interactive apt/sudo installations.
if bash "$installer" > "$scratch/nontty.txt" 2>&1; then
    echo "Direct installer incorrectly accepted a non-interactive call" >&2
    exit 1
fi
grep -q 'needs an interactive terminal' "$scratch/nontty.txt"

# script(1) supplies a proper PTY while GitHub Actions itself has none.
script -q -e -c "bash '$installer'" /dev/null > "$scratch/tty.txt"
grep -q 'Mock RetroPie: batocera-es-test _source_' "$scratch/tty.txt"
grep -q 'Mock RetroPie: batocera-es-test _source_' "$HOME/tarave-install.log"
grep -q 'installation complete' "$scratch/tty.txt"

# Propagate the actual failed source-install exit code (not tee's exit code).
export MOCK_FAIL=1
status=0
script -q -e -c "bash '$installer'" /dev/null > "$scratch/failure.txt" || status=$?
[[ "$status" == "42" ]] || { echo "Wrong failure code: $status" >&2; exit 1; }
grep -q 'failed with status 42' "$scratch/failure.txt"

echo 'PASS: direct source-installer PTY, visible log and accurate exit status'
