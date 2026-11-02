#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Build the PyrixOS images of one or more architectures, test them in
# QEMU, and prepare them as the assets of a GitHub release.
#
# Usage: scripts/release-images.sh VERSION ARCH [ARCH...]
#
# ARCH is x86_64, riscv64 or aarch64. For x86_64 the assets are the
# disk image, the installer image, the live ISO image, its network boot
# files, the qcow2, VHDX and VDI disks and the WSL root file system; for
# riscv64 and aarch64 they are the disk image and the U-Boot firmware.
# Disk images and directories are compressed with xz, and the ISO image
# and the WSL root file system are kept as they are, so that they can be
# written to a USB stick or imported directly. The assets and their
# SHA256SUMS go to OUT (default /var/tmp/pyrixos-release/VERSION).
#
# Before anything is written, each disk image is booted with
# scripts/boot-test.sh, and on x86_64 the installer image installs a
# system with scripts/install-test.sh. SKIP_TESTS=1 skips the tests.
#
# With UPLOAD=1, the assets are uploaded to a draft prerelease with the
# tag vVERSION in REPO (default PacketFive/PyrixOS), created if missing,
# with gh. The release stays a draft until it is published on GitHub.
#
# LATTICE names the lattice command (default `lattice`), SETTINGS the
# Lattice settings file and STORE_ROOT the store root of that file
# (default /lattice), where the built images are read from.

set -euo pipefail

if [ $# -lt 2 ]; then
    sed -n '4,28p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
fi

version=$1
shift
LATTICE=${LATTICE:-lattice}
STORE_ROOT=${STORE_ROOT:-/lattice}
OUT=${OUT:-/var/tmp/pyrixos-release/$version}
REPO=${REPO:-PacketFive/PyrixOS}
here=$(cd "$(dirname "$0")/.." && pwd)
limit=$((2 * 1024 * 1024 * 1024))

settings=()
[ -z "${SETTINGS:-}" ] || settings=(--settings "$SETTINGS")

# The directory in the store of derivation $2 of description $1.
build() {
    local out
    echo "building $1 $2" >&2
    out=$("$LATTICE" "${settings[@]}" build --package-set "$here/pkgs" "$here/pkgs/systems/$1" "$2" | tail -n 1)
    echo "$STORE_ROOT/store/${out#/lattice/store/}"
}

work=$(mktemp -d "${TMPDIR:-/var/tmp}/pyrixos-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$OUT"

# Copy file $1 to the asset $2, compressing it when $2 ends in .xz.
asset() {
    echo "writing $2" >&2
    case $2 in
    *.xz) xz -T0 -6 -c "$1" > "$OUT/$2" ;;
    *) install -m 644 "$1" "$OUT/$2" ;;
    esac
}

# Pack directory $1 into the asset $2, a reproducible .tar.xz.
asset_dir() {
    echo "writing $2" >&2
    tar --sort=name --format=gnu --owner=0 --group=0 --numeric-owner --mtime=@0 \
        -C "$1" -cf - . | xz -T0 -6 > "$OUT/$2"
}

# Boot the disk image $1 of architecture $2 unless SKIP_TESTS is set.
boot() {
    [ -z "${SKIP_TESTS:-}" ] || return 0
    install -m 644 "$1" "$work/test.img"
    ARCH=$2 "$here/scripts/boot-test.sh" "$work/test.img" "$work/$2-boot.log"
    rm -f "$work/test.img"
}

for arch in "$@"; do
    name=pyrixos-$version-$arch
    case $arch in
    x86_64)
        disk=$(build default.pyb image)
        installer=$(build installer.pyb image)
        vm=$(build default.pyb vm)
        iso=$(build live.pyb image)
        netboot=$(build live.pyb netboot)
        wsl=$(build wsl.pyb image)
        boot "$disk/pyrixos.img" x86_64
        if [ -z "${SKIP_TESTS:-}" ]; then
            install -m 644 "$installer/pyrixos-inst.img" "$work/installer.img"
            "$here/scripts/install-test.sh" "$work/installer.img" "$work/install"
            rm -rf "$work/installer.img" "$work/install"
        fi
        asset "$disk/pyrixos.img" "$name.img.xz"
        asset "$installer/pyrixos-inst.img" "pyrixos-installer-$version-$arch.img.xz"
        asset "$(echo "$iso"/*.iso)" "pyrixos-live-$version-$arch.iso"
        asset_dir "$netboot" "pyrixos-netboot-$version-$arch.tar.xz"
        for format in qcow2 vhdx vdi; do
            asset "$vm/pyrixos.$format" "$name.$format.xz"
        done
        asset "$(echo "$wsl"/*.tar.gz)" "pyrixos-wsl-$version-$arch.tar.gz"
        ;;
    riscv64 | aarch64)
        disk=$(build "$arch/default.pyb" image)
        firmware=$(build "$arch/default.pyb" firmware)
        boot "$disk/pyrixos.img" "$arch"
        asset "$disk/pyrixos.img" "$name.img.xz"
        asset_dir "$firmware" "pyrixos-u-boot-$version-$arch.tar.xz"
        ;;
    *)
        echo "unknown architecture $arch: use x86_64, riscv64 or aarch64" >&2
        exit 2
        ;;
    esac
done

cd "$OUT"
for file in *; do
    [ "$file" != SHA256SUMS ] || continue
    if [ "$(stat -c %s "$file")" -ge "$limit" ]; then
        echo "$file is 2 GiB or larger, which a GitHub release asset cannot be" >&2
        exit 1
    fi
done
find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum > "$work/SHA256SUMS"
mv "$work/SHA256SUMS" SHA256SUMS
ls -l "$OUT" >&2

[ -n "${UPLOAD:-}" ] || exit 0
tag=v$version
if ! gh release view "$tag" -R "$REPO" > /dev/null 2>&1; then
    gh release create "$tag" -R "$REPO" --draft --prerelease --title "PyrixOS $version" \
        --notes "Images of PyrixOS $version. Check downloads against SHA256SUMS."
fi
gh release upload "$tag" -R "$REPO" --clobber "$OUT"/*
