# zfs toolkit

## Property priority
local prefix:label > local prefix > inherited prefix:label > inherited prefix

## purge.sh

### Usage
```
./purge.sh -h|--help \
./purge.sh -p|--prefix=snapshot_prefix [-n|--dry-run] [zfs_dataset]...

-h, --help		Shows help
-p, --prefix		E.g. "mybackup" for rpool/USERDATA@mybackup_20221002-23
-n, --dry-run		Calls zfs destroy with -n argument
-d, --debug             Debug mode (set -x)
-v, --verbose		Verbose mode
```

Note: On FreeBSD is supported only short form of params.

Purges snapshots by defined prefix recursively.
Its behaviour is controlled by zfs dataset property "**cz.solctech:purge:\<prefix\>**". Value of property specifies if purging has to be done and how many snapshots and/or how many days have to be kept back.

#### Property value format
((on|yes|true)|(off|no|false))[,keepnum=#num[,keepdays=#num]]

#### Property value examples
on \
on,keepdays=10 \
on,keepnum=3,keepdays=20 \
off

### Example
Turn on of purging for prefix "**backup**" for whole **rpool**, keeping minimal of 5 snapshots per dataset and keeping snapshots not older than 25 days.
```shell
zfs set cz.solctech:purge:backup=on,keepnum=5,keepdays=25 rpool
```

For **USERDATA** keep more history (min. 10 snapshots and last 60 days).
```shell
zfs set cz.solctech:purge:backup=on,keepnum=10,keepdays=60 rpool/USERDATA
```

For **Projects** turn off purging - no snapshots will be destroyed.
```shell
zfs set cz.solctech:purge:backup=off rpool/USERDATA/myuser/Projects
```

Specify correct prefix, specify datasets (or omit for all locally imported), and try dry run.
```shell
./purge.sh --dry-run --prefix=backup rpool
```

If everything seems ok, put in daily or weekly cron.
