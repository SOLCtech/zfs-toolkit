function purge_getopt() {
	getopt -l "help,prefix:,label:,dry-run,debug,verbose" -o "hp:l:ndv" -- "$@"
}

function snapshot_getopt() {
	getopt -l "help,prefix:,label:,force-empty,dry-run,debug,verbose" -o "hp:l:endv" -- "$@"
}

function date_keepdays() {
	local KEEPDAYS

	KEEPDAYS="$1"

	date +%s --date="-${KEEPDAYS} days"
}

function head_negative_n() {
	head -n -"$1"
}
