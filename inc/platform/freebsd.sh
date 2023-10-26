function purge_getopt() {
	getopt "hp:l:ndv" "$@"
}

function snapshot_getopt() {
	getopt "hp:l:endv" "$@"
}

function date_keepdays() {
	local KEEPDAYS
	KEEPDAYS="$1"
	readonly KEEPDAYS

	date -v"-${KEEPDAYS}d" +%s
}

function head_negative_n() {
	local KEEPNUM LIST DELNUM
	KEEPNUM="$1"
	LIST="$(cat -)"
	readonly KEEPNUM LIST

	DELNUM=$(($(echo "$LIST" | wc -l)-KEEPNUM))
	readonly DELNUM

	if ((DELNUM>0)); then
		echo "$LIST" | head -n "$DELNUM"
	fi
}
