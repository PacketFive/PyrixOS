#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Check a PyrixOS WSL root file system on Linux (RFC 0006 section 8):
# unpack it, check /etc/wsl.conf and /etc/wsl-distribution.conf, and,
# in a user namespace chrooted into it, check that /sbin/init is the
# init of the current system and that systemd and Lattice run.
#
# Usage: scripts/wsl-test.sh ROOTFS.tar.gz
#
# Booting the root file system needs WSL on Windows; this test checks
# what can be checked without it.

set -euo pipefail

rootfs=${1:?usage: wsl-test.sh ROOTFS.tar.gz}
work=$(mktemp -d)
trap 'chmod -R u+w "$work" 2> /dev/null; rm -rf "$work"' EXIT

fail() {
    echo "wsl-test: $1" >&2
    exit 1
}

tar -xzf "$rootfs" -C "$work" --no-same-owner --no-same-permissions
root=$work
grep -qx "systemd=true" "$root/etc/wsl.conf" || fail "/etc/wsl.conf does not turn systemd on"
grep -qx "default=root" "$root/etc/wsl.conf" || fail "/etc/wsl.conf names no default user"
grep -q "^defaultName=" "$root/etc/wsl-distribution.conf" || fail "/etc/wsl-distribution.conf names no distribution"
[ "$(readlink "$root/sbin/init")" = /lattice/profiles/system/init ] || fail "/sbin/init is not the system's init"
[ -e "$root/lattice/var/registration.json" ] || fail "the store registration is missing"

sw=/lattice/profiles/system/sw
unshare -r chroot "$root" "$sw/bin/sh" -c "
    set -e
    export PATH=$sw/bin
    test -x /sbin/init
    head -n 2 /sbin/init
    $sw/lib/systemd/systemd --version | head -n 1
    lattice --help > /dev/null
" || fail "the system's programs do not run in the root file system"
echo "wsl-test: $rootfs unpacked; its init, systemd and Lattice run"
