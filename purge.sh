#!/bin/bash

# cz.solctech:purge:backup = on,keepnum=3,keepdays=15

set -euo pipefail

DIR="$(realpath "$(dirname -- "$0")")"

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

DEFAULT_KEEPNUM=3
DEFAULT_KEEPDAYS=15
DRYRUN=0
VERBOSE=0
PREFIX=""

options=$(getopt -l "help,prefix:,dry-run,debug,verbose" -o "hp:ndv" -- "$@")

eval set -- "$options"

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
	echo "Prefix param (-p|--prefix) has to be set!"
	exit 1
fi

DATASETS="${*:-$(zfs list -t filesystem -H -o name -d 0)}"

if ((VERBOSE == 1)); then
	echo -e >&2 "\nSelected root datasets: $(echo "$DATASETS" | xargs)"
fi

# shellcheck disable=SC2086
TO_DESTROY="$(traverse_datasets_to_purge "$PREFIX" $DEFAULT_KEEPNUM $DEFAULT_KEEPDAYS $DATASETS)" || exit 1

if ((VERBOSE == 1)); then
	echo -e >&2 "\nChecking snapshot list validity ...\n"
fi

# shellcheck disable=SC2086
check_snapshots_list "$PREFIX" $TO_DESTROY

if ((VERBOSE == 1)); then
	echo -e >&2 "\nExecuting zfs destroy ...\n"
fi

if ((DRYRUN == 1)); then
	echo "$TO_DESTROY" | xargs -n1 --no-run-if-empty zfs destroy -vn
else
	echo "$TO_DESTROY" | xargs -n1 --no-run-if-empty zfs destroy -v
fi
