#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Shows what the builder is doing. Run it on the builder as the user of
# the runner.
#
#   scripts/builder-watch.sh          the running lattice builds and the
#                                     derivations they are building
#   scripts/builder-watch.sh log      follow the output of the running CI
#                                     step, as the GitHub log shows it
#
# For a view that refreshes itself:
#
#   watch -n 5 scripts/builder-watch.sh
#
# RUNNER_DIR is the directory of the runner, /opt/pyrixos-builder/runner
# by default.

set -uo pipefail

RUNNER_DIR=${RUNNER_DIR:-/opt/pyrixos-builder/runner}
pages="$RUNNER_DIR/_diag/pages"

status() {
    local pid child out found=''
    for pid in $(pgrep -f "bin/lattice .*build"); do
        found=1
        printf '%11s  lattice %s\n' "$(ps -o etime= -p "$pid")" \
            "$(tr '\0' ' ' < "/proc/$pid/cmdline" | sed 's/.*bin\/lattice //')"
    done
    [ -n "$found" ] || { echo "No lattice build is running."; return; }
    for pid in $(pgrep -f "cloche\.namespaces"); do
        for child in $(pgrep -P "$pid"); do
            out=$(tr '\0' '\n' < "/proc/$child/environ" 2>/dev/null | sed -n 's/^out=//p')
            [ -n "$out" ] || continue
            printf '%11s    building %s\n' "$(ps -o etime= -p "$pid")" "${out#/lattice/store/*-}"
        done
    done
}

# The runner writes the live log of the job in pages, and starts a new
# file when a page is full. Each step has a second copy, so follow only
# the pages of the job, found in the newest worker log, and move to the
# next page or the next job when one appears.
follow() {
    local file='' newest job worker tail_pid=''
    trap '[ -z "$tail_pid" ] || kill "$tail_pid" 2>/dev/null' EXIT
    while :; do
        newest=
        # The runner names its files without spaces, so ls is safe here.
        # shellcheck disable=SC2012
        worker=$(ls -t "$RUNNER_DIR"/_diag/Worker_*.log 2>/dev/null | head -n 1)
        if [ -n "$worker" ]; then
            job=$(sed -n 's/.*JobRunner\] Job ID //p' "$worker" | tail -n 1)
            # shellcheck disable=SC2012
            [ -z "$job" ] || newest=$(ls -t "$pages"/*_"$job"_*.log 2>/dev/null | head -n 1)
        fi
        if [ -n "$newest" ] && [ "$newest" != "$file" ]; then
            [ -z "$tail_pid" ] || kill "$tail_pid" 2>/dev/null
            file=$newest
            tail -n 20 -F "$file" | cut -c30- &
            tail_pid=$!
        fi
        sleep 5
    done
}

case ${1:-status} in
    status) status ;;
    log) follow ;;
    *) echo "usage: $0 [status|log]" >&2; exit 2 ;;
esac
