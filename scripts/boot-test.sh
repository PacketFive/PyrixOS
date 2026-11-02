#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Boot a PyrixOS disk image in QEMU, by default with UEFI firmware, and
# check it on the serial console: root logs in, systemd reports the
# state running with no failed unit, Lattice lists the booted system,
# and the machine powers off.
#
# Usage: scripts/boot-test.sh IMAGE [LOG]
#
# By default the test waits for the automatic login of the test and
# installer images. With LOGIN_PASSWORD set, it logs root in with that
# password instead, as on an installed system. With INSTALL_DISK set to
# a raw disk file, it attaches the file as a disk and runs
# `pyrixos-install --yes` on it with the root password INSTALL_PASSWORD.
#
# An IMAGE whose name ends in .iso is attached as a CD on a virtio SCSI
# controller; any other is attached as a virtio disk, read as qcow2,
# VHDX or VDI when its name ends in .qcow2, .vhdx or .vdi and as a raw
# disk otherwise. With MEDIUM=disk, an ISO image is attached as a disk
# too, as a USB stick it was written to would be. An IMAGE that is a directory holds the files of
# `netboot_files`: the machine has no disk and boots from the network,
# with the directory served over TFTP and ipxe.efi as the boot file.
#
# ARCH names the machine to emulate: x86_64, the default, riscv64 or
# aarch64. OVMF_CODE and OVMF_VARS name the UEFI firmware files, by
# default those of the Debian and Ubuntu ovmf, qemu-efi-riscv64 and
# qemu-efi-aarch64 packages. With FIRMWARE=bios, an x86_64 machine
# starts from QEMU's BIOS, SeaBIOS, instead. With FIRMWARE=u-boot, a
# riscv64 or aarch64 machine starts from the files of `uboot_firmware`
# in the directory UBOOT: OpenSBI and U-Boot, or U-Boot alone. IMAGE is not changed: QEMU writes to a
# temporary overlay.

set -euo pipefail

image=${1:?usage: boot-test.sh IMAGE [LOG]}
log=${2:-boot-test.log}
arch=${ARCH:-x86_64}
case $arch in
x86_64)
    machine=(-machine q35)
    firmware=/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd
    ;;
riscv64)
    # QEMU's ACPI tables for riscv64 describe neither the UART nor PCIe,
    # so the kernel finds no console and no disk; without them, EDK2
    # passes the device tree instead.
    machine=(-machine virt,acpi=off -cpu rv64)
    firmware=/usr/share/qemu-efi-riscv64/RISCV_VIRT_CODE.fd:/usr/share/qemu-efi-riscv64/RISCV_VIRT_VARS.fd
    ;;
aarch64)
    machine=(-machine virt -cpu max)
    firmware=/usr/share/AAVMF/AAVMF_CODE.fd:/usr/share/AAVMF/AAVMF_VARS.fd
    ;;
*)
    echo "boot-test: unknown ARCH $arch" >&2
    exit 2
    ;;
esac
code=${OVMF_CODE:-${firmware%%:*}}
vars_template=${OVMF_VARS:-${firmware#*:}}
boot_timeout=${BOOT_TIMEOUT:-300}
install_disk=${INSTALL_DISK:-}
install_password=${INSTALL_PASSWORD:-pyrixos}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
firmware_args=()
case ${FIRMWARE:-uefi} in
bios)
    if [ "$arch" != x86_64 ]; then
        echo "boot-test: FIRMWARE=bios needs ARCH=x86_64" >&2
        exit 2
    fi
    ;;
u-boot)
    uboot=${UBOOT:?FIRMWARE=u-boot needs UBOOT, the directory of uboot_firmware}
    case $arch in
    riscv64) firmware_args=(-bios "$uboot/fw_dynamic.bin" -kernel "$uboot/u-boot.bin") ;;
    aarch64) firmware_args=(-bios "$uboot/u-boot.bin") ;;
    *)
        echo "boot-test: FIRMWARE=u-boot needs ARCH=riscv64 or aarch64" >&2
        exit 2
        ;;
    esac
    ;;
*)
    cp "$vars_template" "$work/vars.fd"
    firmware_args=(-drive if=pflash,format=raw,readonly=on,file="$code"
        -drive if=pflash,format=raw,file="$work/vars.fd")
    ;;
esac

accel=tcg
if [ "$arch" = "$(uname -m)" ] && [ -w /dev/kvm ]; then
    accel=kvm
    if [ "$arch" = aarch64 ]; then machine=(-machine virt -cpu host); fi
fi
# Every wait is this many times longer when another machine is emulated.
scale=1
if [ "$arch" != "$(uname -m)" ]; then scale=${SLOW_FACTOR:-6}; fi

medium=${MEDIUM:-disk}
if [[ $image == *.iso ]] && [ -z "${MEDIUM:-}" ]; then medium=cd; fi
if [ -d "$image" ]; then medium=network; fi
nic=user,model=virtio-net-pci
memory=2048
if [ "$medium" = network ]; then
    # The root file system is loaded into memory with the kernel.
    drives=()
    nic=$nic,tftp=$image,bootfile=ipxe.efi
    memory=4096
    install_target=/dev/vda
elif [ "$medium" = cd ]; then
    drives=(-device virtio-scsi-pci,id=scsi -device scsi-cd,drive=cd,bus=scsi.0
        -drive if=none,id=cd,file="$image",format=raw,media=cdrom,readonly=on)
    install_target=/dev/vda
else
    format=raw
    case $image in
    *.qcow2) format=qcow2 ;;
    *.vhdx) format=vhdx ;;
    *.vdi) format=vdi ;;
    esac
    drives=(-drive file="$image",format="$format",if=virtio,snapshot=on)
    install_target=/dev/vdb
fi
if [ -n "$install_disk" ]; then
    drives+=(-drive file="$install_disk",format=raw,if=virtio)
fi

coproc QEMU {
    exec "qemu-system-$arch" "${machine[@]}" -accel "$accel" -m "$memory" -smp 2 \
        ${firmware_args[@]+"${firmware_args[@]}"} \
        ${drives[@]+"${drives[@]}"} \
        -nic "$nic" \
        -display none -monitor none -serial stdio 2>&1
}
: > "$log"

# The console lines read by the last wait_for.
seen=()

# Reads the console until a line holds $1, for at most $2 seconds. A
# prompt that ends without a newline, such as "login: ", is matched when
# the read times out on it.
wait_for() {
    local pattern=$1 deadline=$((SECONDS + $2 * scale)) line
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
    run "printf '%s\\n' '$install_password' > /tmp/password && pyrixos-install --yes --password-file /tmp/password $install_target; echo INSTALL-STATUS-\$?" 500 1800 ||
        fail "pyrixos-install did not finish"
    printed "INSTALL-STATUS-0" || fail "pyrixos-install failed"
fi
printf 'poweroff\n' >&"${QEMU[1]}"
wait_for "reboot: Power down" 120 || fail "the machine did not power off"
wait "$QEMU_PID" || true
echo "boot-test: $image booted and powered off; the console is in $log"
