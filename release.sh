#!/usr/bin/env bash

set -euo pipefail
#set -x

DIR="$(realpath "$(dirname -- "$0")")"
readonly DIR

source "$DIR/inc/snapshot-funcs.sh"


if [ $# -eq 0 ]; then
    echo -e >&2 "Usage: $0 <snapshot1> [snapshot2 ...]"
    exit 1
fi

for snapshot in "$@"; do
    if has_hold "$snapshot"; then
        echo -e >&2 "Releasing holds for snapshot: $snapshot"
        release_holds "$snapshot"
    else
        echo -e >&2 "No holds found for snapshot: $snapshot"
    fi
done
