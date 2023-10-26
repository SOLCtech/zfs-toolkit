#!/usr/bin/env bash

# cz.solctech:purge:backup = on,keepnum=3,keepdays=15

set -euo pipefail

DIR="$(realpath "$(dirname -- "$0")")"
PLATFORM="$(uname)"

# shellcheck disable=SC1090
source "$DIR/inc/platform/${PLATFORM,,}.sh" || { echo >&2 "Incompatible platform: $PLATFORM"; exit 1; }

source "$DIR/inc/funcs.sh"

show_help() {
	cat << EOF
Usage:
./purge.sh -h|--help
./purge.sh -p|--prefix=snapshot_prefix [-n|--dry-run] [zfs_dataset]...

-h, --help		Shows help
-p, --prefix		E.g. "mybackup" for rpool/USERDATA@mybackup_20221002-23
-n, --dry-run		Calls zfs destroy with -n argument
-d, --debug		Debug mode (set -x)
-v, --verbose		Verbose mode

Note: On FreeBSD is supported only short form of params.

Purges snapshots by defined prefix recursively.
Its behaviour is controlled by zfs dataset property "cz.solctech:purge:<prefix>".
Value of property specifies if purging has to be done and how many snapshots
and/or how many days have to be kept back.

Property value format:
((on|yes|true)|(off|no|false))[,keepnum=<num>[,keepdays=<num>]]

Property value examples:
on
on,keepdays=10
on,keepnum=3,keepdays=20
off

Example:
# turn on of purging for prefix "backup" for whole rpool, keeping minimal of
# 5 snapshots per dataset and keeping snapshots not older than 25 days
$ zfs set cz.solctech:purge:backup=on,keepnum=5,keepdays=25 rpool

# for USERDATA keep more history (min. 10 snapshots and last 60 days)
$ zfs set cz.solctech:purge:backup=on,keepnum=10,keepdays=60 rpool/USERDATA

# for Projects turn off purging - no snapshots will be destroyed
$ zfs set cz.solctech:purge:backup=off rpool/USERDATA/myuser/Projects

# specify correct prefix, specify datasets (or omit for all locally imported),
# and try dry run
$ ./purge.sh --dry-run --prefix=backup rpool

# if everything seems ok, put in daily or weekly cron
EOF
}

DEFAULT_KEEPNUM=-1
DEFAULT_KEEPDAYS=-1
DRYRUN=0
VERBOSE=0
PREFIX=""
LABEL=""

# shellcheck disable=SC2048
# shellcheck disable=SC2086
eval set -- "$(purge_getopt $*)" || { show_help; exit 2; }

while true; do
	case "$1" in
	-h | --help)
		show_help
		exit
		;;
	-p | --prefix)
		shift
		PREFIX="$1"
		;;
	-l | --label)
		shift
		LABEL="$1"
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

if [[ -z "$PREFIX" ]]; then
	echo >&2 "Prefix param (-p|--prefix) has to be set!"
	exit 1
fi

COUNTER_TOTAL=0
COUNTER_SUCCESS=0

function result() {
	echo -e >&2 "zfs-toolkit/purge: total $COUNTER_TOTAL, successful $COUNTER_SUCCESS, error $(((COUNTER_TOTAL-COUNTER_SUCCESS)))"
}

trap result EXIT

DATASETS="${*:-$(zfs list -t filesystem -H -o name -d 0)}"

if ((VERBOSE == 1)); then
	echo -e >&2 "\nSelected root datasets: $(echo "$DATASETS" | xargs)"
	echo -e >&2 "\nOptions: prefix = $PREFIX, label = $LABEL, dryrun = $DRYRUN, verbose = $VERBOSE"
fi

# shellcheck disable=SC2086
TO_DESTROY="$(traverse_datasets_to_purge "$PREFIX" "$LABEL" $DEFAULT_KEEPNUM $DEFAULT_KEEPDAYS $DATASETS)" || exit 1

if [[ -z "$TO_DESTROY" ]]; then
	if ((VERBOSE == 1)); then
		echo -e >&2 "\nNothing to do ...\n"
	fi

	exit 0
fi

if ((VERBOSE == 1)); then
	echo -e >&2 "\nChecking snapshot list validity ...\n"
fi

# shellcheck disable=SC2086
check_snapshots_list "$PREFIX" $TO_DESTROY

if ((VERBOSE == 1)); then
	echo -e >&2 "\nExecuting zfs destroy ...\n"
fi

FLAGS=''

if ((VERBOSE == 1)); then
	FLAGS+=' -v'
fi

if ((DRYRUN == 1)); then
	FLAGS+=' -n'
fi

for SNAPSHOT in $TO_DESTROY; do
	((COUNTER_TOTAL+=1))
	# shellcheck disable=SC2086
	zfs destroy $FLAGS "$SNAPSHOT" && ((COUNTER_SUCCESS+=1))
done
