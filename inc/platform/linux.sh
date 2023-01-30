function purge_getopt() {
	getopt -l "help,prefix:,dry-run,debug,verbose" -o "hp:ndv" -- "$@"
}

function date_keepdays() {
	local KEEPDAYS

	KEEPDAYS="$1"

	date +%s --date="-${KEEPDAYS} days"
}

function head_negative_n() {
	head -n -"$1"
}
