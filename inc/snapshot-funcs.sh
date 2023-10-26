function traverse_datasets() {
	local PREFIX LABEL DATASETS DATASET

	PREFIX="$1"
	LABEL="$2"
	shift 2
	DATASETS="$*"

	for DATASET in $DATASETS; do
		if ((VERBOSE == 1)); then
			echo -e >&2 "\nDataset: $DATASET"
		fi

		process_dataset "$PREFIX" "$LABEL" "$DATASET" || continue
		DIRECT_CHILDREN="$(get_direct_children "$DATASET")" || exit 1

		if [[ -n $DIRECT_CHILDREN ]]; then
			# shellcheck disable=SC2086
			traverse_datasets "$PREFIX" "$LABEL" $DIRECT_CHILDREN || exit 1
		fi
	done
}

function process_dataset() {
	local PREFIX LABEL DATASET PROPERTY ONOFF NODIVE

	PREFIX="$1"
	LABEL="$2"
	DATASET="$3"

	PROPERTY="$(get_dataset_property "$DATASET" "snapshot:${PREFIX}:${LABEL}" "local" || get_dataset_property "$DATASET" "snapshot:${PREFIX}" "local" || get_dataset_property "$DATASET" "snapshot:${PREFIX}:${LABEL}" || get_dataset_property "$DATASET" "snapshot:${PREFIX}")"

	read -r ONOFF NODIVE <<< "$(parse_snapshot_properties "$PROPERTY")"

	if ((ONOFF == 1)); then
		create_snapshot "$PREFIX" "$LABEL" "$DATASET"
	fi

	return "$NODIVE";
}

function parse_snapshot_properties() {
	local VALUE IFS PARAM ONOFF=0 NODIVE=0

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
		fi
	done

	if ((VERBOSE == 1)); then
		echo >&2 "  $([ $ONOFF = 1 ] && echo "enabled" || echo "disabled")$([ $NODIVE = 1 ] && echo ", no dive")"
	fi

	echo "$ONOFF $NODIVE"
}

function create_snapshot() {
	local PREFIX LABEL DATASET SNAPSHOT IS_DATASET_CHANGED

	PREFIX="$1"
	LABEL="$2"
	DATASET="$3"

	if ((FORCE_EMPTY == 1)) || is_dataset_changed "$PREFIX" "$DATASET"; then
		SNAPSHOT="${DATASET}@${PREFIX}_$(date -u +"%Y%m%d-%H%M")_${LABEL}"

		if ((VERBOSE == 1)); then
			echo >&2 "  Creating a snapshot '$SNAPSHOT' ..."
		fi

		if ((DRYRUN == 0)); then
			zfs snapshot "$SNAPSHOT" || {
				echo >&2 "Failed to create snapshot '$SNAPSHOT'!"
				return 1
			}
		fi
	else
		IS_DATASET_CHANGED="$?"
		if ((VERBOSE == 1)); then
			if ((IS_DATASET_CHANGED == 1)); then
				echo >&2 "  No changes, not creating a snapshot ..."
			else
				echo >&2 "Failed to check diff from latest snapshot! (Permissions?)"
			fi
		fi
	fi
}

function is_dataset_changed() {
	local PREFIX DATASET LATEST_SNAPSHOT DIFF

	PREFIX="$1"
	DATASET="$2"

	LATEST_SNAPSHOT="$(get_latest_snapshot "$PREFIX" "$DATASET")"

	if [ -z "$LATEST_SNAPSHOT" ]; then
		return 0
	fi

	DIFF="$(zfs diff -H "$LATEST_SNAPSHOT" 2> /dev/null)" || {
		return 2
	}

	if [ -z "$DIFF" ]; then
		return 1
	else
		return 0
	fi
}

function get_latest_snapshot() {
	local PREFIX DATASET LIST

	PREFIX="$1"
	DATASET="$2"

	LIST="$(zfs list -t snapshot -H -p -o name -s creation "$DATASET" 2> /dev/null)" || {
		echo >&2 "Dataset $DATASET not found!"
		exit 1
	}

	LIST="$(echo "$LIST" | grep "@${PREFIX}_" | tail -n1)"

	echo "$LIST"
}
