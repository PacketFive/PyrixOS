#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Boot a PyrixOS disk image in QEMU with UEFI firmware and check it on
# the serial console: the system reaches the root shell the test image
# logs in automatically, systemd reports its state, Lattice runs, and
# the machine powers off.
#
# Usage: scripts/boot-test.sh IMAGE [LOG]
#
# OVMF_CODE and OVMF_VARS name the firmware files, by default those of
# the Debian and Ubuntu ovmf package. The image is not changed: QEMU
# writes to a temporary overlay.

set -euo pipefail

image=${1:?usage: boot-test.sh IMAGE [LOG]}
log=${2:-boot-test.log}
code=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
vars_template=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
boot_timeout=${BOOT_TIMEOUT:-300}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$vars_template" "$work/vars.fd"

accel=tcg
if [ -w /dev/kvm ]; then accel=kvm; fi

coproc QEMU {
    exec qemu-system-x86_64 -machine q35,accel="$accel" -m 2048 -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file="$code" \
        -drive if=pflash,format=raw,file="$work/vars.fd" \
        -drive file="$image",format=raw,if=virtio,snapshot=on \
        -nic user,model=virtio-net-pci \
        -display none -monitor none -serial stdio 2>&1
}
: > "$log"

# Reads the console until a line holds $1, for at most $2 seconds.
wait_for() {
    local pattern=$1 deadline=$((SECONDS + $2)) line
    while [ "$SECONDS" -lt "$deadline" ]; do
        if IFS= read -r -t 5 line <&"${QEMU[0]}"; then
            line=${line%$'\r'}
            printf '%s\n' "$line" >> "$log"
            if [[ $line == *"$pattern"* ]]; then return 0; fi
        elif [ -z "${QEMU_PID:-}" ] || ! kill -0 "$QEMU_PID" 2> /dev/null; then
            return 1
        fi
    done
    return 1
}

# Runs a command in the root shell. The marker is printed from an
# arithmetic expansion, so the echo of the command line does not match.
run() {
    printf '%s; echo "DONE-$((%d + 1))"\n' "$1" "$2" >&"${QEMU[1]}"
    wait_for "DONE-$(($2 + 1))" 120
}

fail() {
    echo "boot-test: $1; the console is in $log" >&2
    if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2> /dev/null || true; fi
    exit 1
}

wait_for "automatic login" "$boot_timeout" || fail "no login on the serial console"
sleep 2
run "systemctl is-system-running --wait" 100 || fail "systemd did not settle"
run "systemctl --failed --no-legend --plain" 200 || fail "systemctl failed"
run "readlink /run/current-system" 300 || fail "no current system"
run "lattice systems" 400 || fail "lattice did not run"
printf 'poweroff\n' >&"${QEMU[1]}"
wait_for "reboot: Power down" 120 || fail "the machine did not power off"
wait "$QEMU_PID" || true
echo "boot-test: $image booted and powered off; the console is in $log"
