#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Test the installer image in QEMU: boot it with an empty second disk,
# install PyrixOS on that disk with `pyrixos-install`, then boot the
# installed disk alone and log root in with the password the installer
# set. Both boots are checked by scripts/boot-test.sh.
#
# Usage: scripts/install-test.sh INSTALLER-IMAGE [DIRECTORY]
#
# DIRECTORY receives the installed disk and the two console logs; it is
# a temporary directory, removed at the end, when not given.

set -euo pipefail

installer=${1:?usage: install-test.sh INSTALLER-IMAGE [DIRECTORY]}
here=$(dirname "$0")
password=install-test
if [ -n "${2:-}" ]; then
    dir=$2
    mkdir -p "$dir"
else
    dir=$(mktemp -d)
    trap 'rm -rf "$dir"' EXIT
fi

rm -f "$dir/disk.img"
truncate -s 8G "$dir/disk.img"
INSTALL_DISK="$dir/disk.img" INSTALL_PASSWORD=$password \
    "$here/boot-test.sh" "$installer" "$dir/installer.log"
LOGIN_PASSWORD=$password "$here/boot-test.sh" "$dir/disk.img" "$dir/installed.log"
echo "install-test: the installed system booted and root logged in"
