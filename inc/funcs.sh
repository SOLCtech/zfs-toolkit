function get_snapshots_to_purge() {
	local DATASET PREFIX KEEPNUM KEEPDAYS LIST DATE IFS FILTERED_LIST SNAP SNAPDATE SNAPNAME

	DATASET="$1"
	PREFIX="$2"
	KEEPNUM="$3"
	KEEPDAYS="$4"

	LIST="$(zfs list -t snapshot -H -p -o creation,name -s creation "$DATASET" 2> /dev/null)" || {
		echo >&2 "Dataset $DATASET not found."
		exit 1
	}

	LIST="$(echo "$LIST" | grep "@${PREFIX}_" | head_negative_n "$KEEPNUM")"
	DATE="$(date_keepdays "$KEEPDAYS")"

	IFS=$'\n'

	FILTERED_LIST=""

	for SNAP in $LIST; do
		SNAPDATE=$(echo "$SNAP" | cut -d $'\t' -s -f 1)
		SNAPNAME=$(echo "$SNAP" | cut -d $'\t' -s -f 2)

		if (("$SNAPDATE" < "$DATE")); then
			FILTERED_LIST="$FILTERED_LIST $SNAPNAME"
		fi
	done

	FILTERED_LIST=$(echo "$FILTERED_LIST" | xargs)

	if ((VERBOSE == 1)); then
		echo >&2 "  Found snapshots to purge:"

		IFS=$' '
		for SNAP in $FILTERED_LIST; do
			echo >&2 "    $SNAP"
		done
	fi

	echo "$FILTERED_LIST"
}

function get_dataset_property() {
	local DATASET SECTION PREFIX PROPERTY_NAME PROPERTY IFS VALUE SOURCE

	DATASET="$1"
	SECTION="$2"
	PREFIX="$3"

	PROPERTY_NAME="cz.solctech:${SECTION}:${PREFIX}"

	# cz.solctech:purge:backup = on,keepnum=3,keepdays=15
	PROPERTY="$(zfs get -t filesystem -H -p -o value,source "$PROPERTY_NAME" "$DATASET" 2> /dev/null)" || {
		echo >&2 "Reading property $PROPERTY_NAME of dataset $DATASET failed."
		exit 1
	}

	IFS=$'\t'
	read -r VALUE SOURCE <<< "$PROPERTY"

	if [[ "$VALUE" == "-" ]]; then
		return 1
	fi

	echo "$VALUE"
}

function parse_purge_properties() {
	local VALUE IFS PARAM ONOFF=0 KEEPNUM=-1 KEEPDAYS=-1

	#on,keepnum=3,keepdays=15
	VALUE="$1"

	IFS=','
	for PARAM in $VALUE; do
		PARAM="${PARAM,,}"

		if [[ "$PARAM" =~ ^(yes|on|true)$ ]]; then
			ONOFF=1
		elif [[ "$PARAM" =~ ^(no|off|false)$ ]]; then
			ONOFF=0
		elif [[ "$PARAM" =~ ^keepnum=[0-9]+ ]]; then
			KEEPNUM=$(echo "$PARAM" | cut -d '=' -s -f 2)
		elif [[ "$PARAM" =~ ^keepdays=[0-9]+ ]]; then
			KEEPDAYS=$(echo "$PARAM" | cut -d '=' -s -f 2)
		fi
	done

	if ((ONOFF == 0)); then
		if ((VERBOSE == 1)); then
    		echo >&2 "  OFF"
		fi

		return 1
	fi

	echo "$KEEPNUM $KEEPDAYS"
}

function get_direct_children() {
	local DATASET="$1"

	zfs list -t filesystem -H -o name -d 1 "$DATASET" 2> /dev/null | tail -n +2 || {
		echo >&2 "Listing of $DATASET children failed."
		exit 1
	}
}

function traverse_datasets_to_purge() {
	local PREFIX PARENT_KEEPNUM PARENT_KEEPDAYS DATASETS DATASET

	PREFIX="$1"
	PARENT_KEEPNUM="$2"
	PARENT_KEEPDAYS="$3"
	shift 3
	DATASETS="$*"

	for DATASET in $DATASETS; do
		if ((VERBOSE == 1)); then
			echo -e >&2 "\nDataset: $DATASET"
		fi

		process_dataset_to_purge "$PREFIX" "$PARENT_KEEPNUM" "$PARENT_KEEPDAYS" "$DATASET" || continue
		DIRECT_CHILDREN="$(get_direct_children "$DATASET")" || exit 1

		if [[ -n $DIRECT_CHILDREN ]]; then
			# shellcheck disable=SC2086
			traverse_datasets_to_purge "$PREFIX" "$PARENT_KEEPNUM" "$PARENT_KEEPDAYS" $DIRECT_CHILDREN || exit 1
		fi
	done
}

function process_dataset_to_purge() {
	local PREFIX PARENT_KEEPNUM PARENT_KEEPDAYS DATASET PROPERTY PROPERTIES KEEPNUM KEEPDAYS

	PREFIX="$1"
	PARENT_KEEPNUM="$2"
	PARENT_KEEPDAYS="$3"
	DATASET="$4"

	PROPERTY=$(get_dataset_property "$DATASET" purge "$PREFIX")
	PROPERTIES=$(parse_purge_properties "$PROPERTY") || return 0

	read -r KEEPNUM KEEPDAYS <<< "$PROPERTIES"

	if ((KEEPNUM < 0)); then
		KEEPNUM=$PARENT_KEEPNUM
	fi

	if ((KEEPDAYS < 0)); then
		KEEPDAYS=$PARENT_KEEPDAYS
	fi

	if ((VERBOSE == 1)); then
		echo >&2 "  ON, keep number = $KEEPNUM, keep days = $KEEPDAYS"
	fi

	get_snapshots_to_purge "$DATASET" "$PREFIX" "$KEEPNUM" "$KEEPDAYS" || exit 1
}

function check_snapshots_list() {
	local PREFIX SNAPSHOT_LIST

	PREFIX="$1"
	shift 1
	SNAPSHOT_LIST="$*"

	for SNAPSHOT in $SNAPSHOT_LIST; do
		check_if_snapshot "$PREFIX" "$SNAPSHOT"
	done
}

function check_if_snapshot() {
	local PREFIX SNAPSHOT

	PREFIX="$1"
	SNAPSHOT="$2"

	echo "$SNAPSHOT" | grep -E "^[^[:blank:]]+@${PREFIX}[^[:blank:]]+$" > /dev/null 2>&1 || {
		echo -e >&2 "\nFATAL ERROR!\nDataset '$SNAPSHOT' seems to does not correspond to prefix '$PREFIX' and/or does not match snapshot format."
		exit 1
	}

	TYPE="$(zfs get -H -p -o value type "$SNAPSHOT")"

	[[ "$TYPE" == 'snapshot' ]] || {
		echo -e >&2 "\nFATAL ERROR!\nType of dataset '$SNAPSHOT' is not 'snapshot' but '$TYPE'!!!"
		exit 1
	}
}
