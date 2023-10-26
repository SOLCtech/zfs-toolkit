#!/usr/bin/env bash

# cz.solctech:snapshot:auto:15min = on|off|no-dive

set -euo pipefail

DIR="$(realpath "$(dirname -- "$0")")"
PLATFORM="$(uname)"

readonly DIR PLATFORM

# shellcheck disable=SC1090
source "$DIR/inc/platform/${PLATFORM,,}.sh" || { echo >&2 "Incompatible platform: $PLATFORM"; exit 1; }

source "$DIR/inc/funcs.sh"
source "$DIR/inc/snapshot-funcs.sh"

show_help() {
	cat << EOF
Usage:
snapshot.sh -h|--help
snapshot.sh -l|--label=label [-p|--prefix=auto] [-e|--force-empty] [-n|--dry-run] [zfs_dataset]...

-h, --help		Shows help
-p, --prefix		Default "auto". E.g. "somethingelse" for rpool/USERDATA@somethingelse_20230507-2245_hourly
-l, --label		Label for finer resolution. E.g. "hourly" for rpool/USERDATA@auto_20230507-2245_hourly
-e, --force-empty	Force creating of empty snapshots
-n, --dry-run		Does not actually create snapshot
-d, --debug		Debug mode (set -x)
-v, --verbose		Verbose mode

Note: On FreeBSD is supported only short form of params.

Creates snapshots by defined prefix and label recursively.
Its behaviour is controlled by zfs dataset property "cz.solctech:snapshot:<prefix>:<label>".
Value of property specifies if snapshot creation has to be done.

Property value format:
((on|yes|true)|(off|no|false))[,(no-dive|nodive)]

Property value examples:
on
off
on,no-dive

Example:
# allow snapshot creation for default prefix "auto" and label "hourly" for whole rpool
$ zfs set cz.solctech:snapshot:auto:hourly=on rpool

# don't want auto snapshots for anything in rpool/STORAGE/docker, even don't want traverse into child datasets
$ zfs set cz.solctech:snapshot:auto:hourly=no-dive rpool/STORAGE/docker

# specify correct prefix, specify datasets (or omit for all locally imported),
# and try dry run
$ ./snapshot.sh --dry-run --label=hourly rpool

# if everything seems ok, put in hourly cron
EOF
}

DRYRUN=0
VERBOSE=0
ARG_PREFIX="auto"
ARG_LABEL=""
FORCE_EMPTY=0

# shellcheck disable=SC2048
# shellcheck disable=SC2086
eval set -- "$(snapshot_getopt $*)" || { show_help; exit 2; }

while true; do
	case "$1" in
	-h | --help)
		show_help
		exit
		;;
	-p | --prefix)
		shift
		ARG_PREFIX="$1"
		;;
	-l | --label)
		shift
		ARG_LABEL="$1"
		;;
	-e | --force-empty)
		FORCE_EMPTY=1
		;;
	-n | --dry-run)
		DRYRUN=1
		;;
	-d | --debug)
		set -x
		;;
	-v | --verbose)
		VERBOSE=1
		;;
	--)
		shift
		break
		;;
	esac
	shift
done

readonly ARG_PREFIX ARG_LABEL FORCE_EMPTY DRYRUN VERBOSE

if [[ -z "$ARG_LABEL" ]]; then
	echo >&2 "Label param (-l|--label) has to be set!"
	exit 1
fi

ARG_DATASETS="${*:-$(zfs list -t filesystem -H -o name -d 0)}"
readonly ARG_DATASETS

if ((VERBOSE == 1)); then
	echo -e >&2 "\nSelected root datasets: $(echo "$ARG_DATASETS" | xargs)"
	echo -e >&2 "\nOptions: prefix = $ARG_PREFIX, label = $ARG_LABEL, force-empty = $FORCE_EMPTY, dryrun = $DRYRUN, verbose = $VERBOSE"
fi

# shellcheck disable=SC2086
traverse_datasets "$ARG_PREFIX" "$ARG_LABEL" $ARG_DATASETS

if ((DRYRUN == 1)); then
	echo -e >&2 "\n\nDry run mode was enabled. No changes were made!!!"
fi
