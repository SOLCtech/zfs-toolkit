function purge_getopt() {
	getopt "hp:l:ndv" "$@"
}

function snapshot_getopt() {
	getopt "hp:l:endv" "$@"
}

function date_keepdays() {
	local KEEPDAYS

	KEEPDAYS="$1"

	date -v"-${KEEPDAYS}d" +%s
}

function head_negative_n() {
	local KEEPNUM LIST

	KEEPNUM="$1"
	LIST="$(cat -)"

	DELNUM=$(($(echo "$LIST" | wc -l)-KEEPNUM))

	if ((DELNUM>0)); then
		echo "$LIST" | head -n "$DELNUM"
	fi
}
