function get_snapshots_to_purge() {
	local DATASET PREFIX LABEL KEEPNUM KEEPDAYS LIST DATE IFS FILTERED_LIST SNAP SNAPDATE SNAPNAME

	DATASET="$1"
	PREFIX="$2"
	LABEL="$3"
	KEEPNUM="$4"
	KEEPDAYS="$5"

	LIST="$(zfs list -t snapshot -H -p -o creation,name -s creation "$DATASET" 2> /dev/null)" || {
		echo >&2 "Dataset $DATASET not found."
		exit 1
	}

	if [[ -z "$LABEL" ]]; then
		LIST="$(echo "$LIST" | grep "@${PREFIX}_" | head_negative_n "$KEEPNUM")"
	else
		LIST="$(echo "$LIST" | grep -E "@${PREFIX}_[0-9]{8}-[0-9]{4}_${LABEL}" | head_negative_n "$KEEPNUM")"
	fi

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

	if ((VERBOSE == 1)) && [[ -n "$FILTERED_LIST" ]]; then
		echo >&2 "  Found snapshots to purge:"

		IFS=$' '
		for SNAP in $FILTERED_LIST; do
			echo >&2 "    $SNAP"
		done
	fi

	echo "$FILTERED_LIST"
}

function get_dataset_property() {
	local DATASET PROPERTY_NAME SOURCE PROPERTY

	DATASET="$1"
	PROPERTY_NAME="cz.solctech:$2"
	SOURCE="${3:-inherited}"

	# cz.solctech:purge:backup = on,keepnum=3,keepdays=15
	PROPERTY="$(zfs get -t filesystem,volume -H -p -o value -s "$SOURCE" "$PROPERTY_NAME" "$DATASET" 2> /dev/null)" || {
		echo >&2 "Reading property $PROPERTY_NAME of dataset $DATASET failed."
		exit 1
	}

	if [[ -z "$PROPERTY" ]]; then
		return 1
	fi

	echo "$PROPERTY"
}

function parse_purge_properties() {
	local VALUE IFS PARAM ONOFF=0 KEEPNUM=-1 KEEPDAYS=-1 NODIVE=0

	#on,keepnum=3,keepdays=15
	VALUE="$1"

	IFS=','
	for PARAM in $VALUE; do
		PARAM="${PARAM,,}"

		if [[ "$PARAM" =~ ^(yes|on|true|enabled?)$ ]]; then
			ONOFF=1
		elif [[ "$PARAM" =~ ^(no|off|false|disabled?)$ ]]; then
			ONOFF=0
		elif [[ "$PARAM" =~ ^(no-dive|nodive)$ ]]; then
 			NODIVE=1
		elif [[ "$PARAM" =~ ^keepnum=[0-9]+ ]]; then
			KEEPNUM=$(echo "$PARAM" | cut -d '=' -s -f 2)
		elif [[ "$PARAM" =~ ^keepdays=[0-9]+ ]]; then
			KEEPDAYS=$(echo "$PARAM" | cut -d '=' -s -f 2)
		fi
	done

	if ((VERBOSE == 1)); then
		echo >&2 "  $([ $ONOFF = 1 ] && echo "enabled" || echo "disabled")$([ $NODIVE = 1 ] && echo ", no dive")"
	fi

	echo "$ONOFF $NODIVE $KEEPNUM $KEEPDAYS"
}

function get_direct_children() {
	local DATASET="$1"

	zfs list -t filesystem,volume -H -o name -d 1 "$DATASET" 2> /dev/null | tail -n +2 || {
		echo >&2 "Listing of $DATASET children failed."
		exit 1
	}
}

function traverse_datasets_to_purge() {
	local PREFIX LABEL PARENT_KEEPNUM PARENT_KEEPDAYS DATASETS DATASET

	PREFIX="$1"
	LABEL="$2"
	PARENT_KEEPNUM="$3"
	PARENT_KEEPDAYS="$4"
	shift 4
	DATASETS="$*"

	for DATASET in $DATASETS; do
		if ((VERBOSE == 1)); then
			echo -e >&2 "\nDataset: $DATASET"
		fi

		process_dataset_to_purge "$PREFIX" "$LABEL" "$PARENT_KEEPNUM" "$PARENT_KEEPDAYS" "$DATASET" || continue
		DIRECT_CHILDREN="$(get_direct_children "$DATASET")" || exit 1

		if [[ -n $DIRECT_CHILDREN ]]; then
			# shellcheck disable=SC2086
			traverse_datasets_to_purge "$PREFIX" "$LABEL" "$PARENT_KEEPNUM" "$PARENT_KEEPDAYS" $DIRECT_CHILDREN || exit 1
		fi
	done
}

function process_dataset_to_purge() {
	local PREFIX LABEL PARENT_KEEPNUM PARENT_KEEPDAYS DATASET PROPERTY KEEPNUM KEEPDAYS

	PREFIX="$1"
	LABEL="$2"
	PARENT_KEEPNUM="$3"
	PARENT_KEEPDAYS="$4"
	DATASET="$5"

	PROPERTY="$(get_dataset_property "$DATASET" "purge:${PREFIX}:${LABEL}" "local" || get_dataset_property "$DATASET" "purge:${PREFIX}" "local" || get_dataset_property "$DATASET" "purge:${PREFIX}:${LABEL}" || get_dataset_property "$DATASET" "purge:${PREFIX}")"

	read -r ONOFF NODIVE KEEPNUM KEEPDAYS <<< "$(parse_purge_properties "$PROPERTY")"

	if ((KEEPNUM < 0)); then
		KEEPNUM=$PARENT_KEEPNUM
	fi

	if ((KEEPDAYS < 0)); then
		KEEPDAYS=$PARENT_KEEPDAYS
	fi

	if ((VERBOSE == 1)); then
		echo >&2 "  keep number = $KEEPNUM, keep days = $KEEPDAYS"
	fi

	if ((ONOFF == 1)); then
		get_snapshots_to_purge "$DATASET" "$PREFIX" "$LABEL" "$KEEPNUM" "$KEEPDAYS" || exit 1
	fi

	return "$NODIVE";
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
