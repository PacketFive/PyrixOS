#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Build PyrixOS system descriptions and publish what they build to the
# binary cache.
#
# Usage: scripts/publish-cache.sh FILE NAME [NAME...] [-- FILE NAME...]
#
# Each FILE is a description under pkgs/systems and each NAME one of its
# derivations, such as `system` or `image`. The script builds them with
# Lattice, then pushes each output with its closure, signed with the key
# named by `cache.secret_key_file` in the Lattice settings, to the local
# cache directory CACHE_DIR (default /var/tmp/pyrixos-cache). Paths the
# cache already holds are skipped, so the directory grows run by run.
#
# With CACHE_DEST set, the directory is then copied to the public host
# with SYNC: `rsync` (CACHE_DEST is an rsync target such as
# host:/srv/cache/), `rclone` (a remote such as r2:pyrixos-cache) or
# `s3` (an s3:// URL; the aws CLI reads S3_ENDPOINT if set). Entries are
# uploaded before the files that name them, and nothing is deleted, so a
# client never sees an entry whose archive is missing.
#
# LATTICE names the lattice command (default `lattice`) and SETTINGS the
# Lattice settings file (default the Lattice default).

set -euo pipefail

LATTICE=${LATTICE:-lattice}
CACHE_DIR=${CACHE_DIR:-/var/tmp/pyrixos-cache}
SYNC=${SYNC:-rsync}
CACHE_DEST=${CACHE_DEST:-}
here=$(cd "$(dirname "$0")/.." && pwd)

# `command` skips this function, which would otherwise call itself when
# LATTICE is the bare name `lattice`.
lattice() {
    if [ -n "${SETTINGS:-}" ]; then
        command "$LATTICE" --settings "$SETTINGS" "$@"
    else
        command "$LATTICE" "$@"
    fi
}

if [ $# -lt 2 ]; then
    sed -n '4,24p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
fi

outputs=()
while [ $# -gt 0 ]; do
    file=$1
    shift
    while [ $# -gt 0 ] && [ "$1" != -- ]; do
        echo "building $file $1" >&2
        out=$(lattice build --package-set "$here/pkgs" "$file" "$1" | tail -n 1)
        outputs+=("$out")
        shift
    done
    [ $# -gt 0 ] && shift
done

mkdir -p "$CACHE_DIR"
lattice push --to "file://$(cd "$CACHE_DIR" && pwd)" "${outputs[@]}"

[ -n "$CACHE_DEST" ] || exit 0
dest=${CACHE_DEST%/}
echo "syncing $CACHE_DIR to $dest with $SYNC" >&2
case $SYNC in
rsync)
    rsync -a --ignore-existing "$CACHE_DIR/archive" "$dest/"
    rsync -a --ignore-existing --exclude archive "$CACHE_DIR/" "$dest/"
    ;;
rclone)
    rclone copy --ignore-existing "$CACHE_DIR/archive" "$dest/archive"
    rclone copy --ignore-existing --exclude 'archive/**' "$CACHE_DIR" "$dest"
    ;;
s3)
    endpoint=()
    [ -n "${S3_ENDPOINT:-}" ] && endpoint=(--endpoint-url "$S3_ENDPOINT")
    aws "${endpoint[@]}" s3 sync "$CACHE_DIR/archive" "$dest/archive"
    aws "${endpoint[@]}" s3 sync --exclude 'archive/*' "$CACHE_DIR" "$dest"
    ;;
*)
    echo "unknown SYNC $SYNC: use rsync, rclone or s3" >&2
    exit 2
    ;;
esac
