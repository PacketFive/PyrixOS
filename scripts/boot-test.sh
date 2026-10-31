#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Boot a PyrixOS disk image in QEMU with UEFI firmware and check it on
# the serial console: root logs in, systemd reports the state running
# with no failed unit, Lattice lists the booted system, and the machine
# powers off.
#
# Usage: scripts/boot-test.sh IMAGE [LOG]
#
# By default the test waits for the automatic login of the test and
# installer images. With LOGIN_PASSWORD set, it logs root in with that
# password instead, as on an installed system. With INSTALL_DISK set to
# a raw disk file, it attaches the file as a second disk and runs
# `pyrixos-install --yes` on it with the root password INSTALL_PASSWORD.
#
# OVMF_CODE and OVMF_VARS name the firmware files, by default those of
# the Debian and Ubuntu ovmf package. IMAGE is not changed: QEMU writes
# to a temporary overlay.

set -euo pipefail

image=${1:?usage: boot-test.sh IMAGE [LOG]}
log=${2:-boot-test.log}
code=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
vars_template=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
boot_timeout=${BOOT_TIMEOUT:-300}
install_disk=${INSTALL_DISK:-}
install_password=${INSTALL_PASSWORD:-pyrixos}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$vars_template" "$work/vars.fd"

accel=tcg
if [ -w /dev/kvm ]; then accel=kvm; fi

drives=(-drive file="$image",format=raw,if=virtio,snapshot=on)
if [ -n "$install_disk" ]; then
    drives+=(-drive file="$install_disk",format=raw,if=virtio)
fi

coproc QEMU {
    exec qemu-system-x86_64 -machine q35,accel="$accel" -m 2048 -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file="$code" \
        -drive if=pflash,format=raw,file="$work/vars.fd" \
        "${drives[@]}" \
        -nic user,model=virtio-net-pci \
        -display none -monitor none -serial stdio 2>&1
}
: > "$log"

# The console lines read by the last wait_for.
seen=()

# Reads the console until a line holds $1, for at most $2 seconds. A
# prompt that ends without a newline, such as "login: ", is matched when
# the read times out on it.
wait_for() {
    local pattern=$1 deadline=$((SECONDS + $2)) line
    seen=()
    while [ "$SECONDS" -lt "$deadline" ]; do
        line=
        if IFS= read -r -t 5 line <&"${QEMU[0]}" || [ -n "$line" ]; then
            line=${line%$'\r'}
            printf '%s\n' "$line" >> "$log"
            seen+=("$line")
            if [[ $line == *"$pattern"* ]]; then return 0; fi
        elif [ -z "${QEMU_PID:-}" ] || ! kill -0 "$QEMU_PID" 2> /dev/null; then
            return 1
        fi
    done
    return 1
}

# Runs a command in the root shell and waits at most $3 seconds, by
# default 120, for it to finish. The marker is printed from an
# arithmetic expansion, so the echo of the command line does not match.
run() {
    printf '%s; echo "DONE-$((%d + 1))"\n' "$1" "$2" >&"${QEMU[1]}"
    wait_for "DONE-$(($2 + 1))" "${3:-120}"
}

# True when a line of the last command's output is exactly $1, once
# terminal escapes, such as those of bracketed paste, and carriage
# returns are removed.
shopt -s extglob
printed() {
    local line
    for line in "${seen[@]}"; do
        line=${line//$'\e['*([0-9;?])[a-zA-Z]/}
        line=${line//$'\r'/}
        if [ "$line" = "$1" ]; then return 0; fi
    done
    return 1
}

fail() {
    echo "boot-test: $1; the console is in $log" >&2
    if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2> /dev/null || true; fi
    exit 1
}

if [ -n "${LOGIN_PASSWORD:-}" ]; then
    wait_for "login:" "$boot_timeout" || fail "no login prompt on the serial console"
    sleep 2
    printf 'root\n' >&"${QEMU[1]}"
    wait_for "Password:" 60 || fail "no password prompt"
    printf '%s\n' "$LOGIN_PASSWORD" >&"${QEMU[1]}"
else
    wait_for "automatic login" "$boot_timeout" || fail "no login on the serial console"
fi
sleep 3
run "systemctl is-system-running --wait" 100 || fail "systemd did not settle"
printed running || fail "the system is not running"
run "systemctl --failed --no-legend --plain | wc -l" 200 || fail "systemctl failed"
printed 0 || fail "a unit failed"
run "readlink /run/current-system" 300 || fail "no current system"
run "lattice systems" 400 || fail "lattice did not run"
if [ -n "$install_disk" ]; then
    run "printf '%s\\n' '$install_password' > /tmp/password && pyrixos-install --yes --password-file /tmp/password /dev/vdb; echo INSTALL-STATUS-\$?" 500 1800 ||
        fail "pyrixos-install did not finish"
    printed "INSTALL-STATUS-0" || fail "pyrixos-install failed"
fi
printf 'poweroff\n' >&"${QEMU[1]}"
wait_for "reboot: Power down" 120 || fail "the machine did not power off"
wait "$QEMU_PID" || true
echo "boot-test: $image booted and powered off; the console is in $log"
