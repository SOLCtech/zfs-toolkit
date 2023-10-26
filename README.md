# zfs toolkit

## Property priority
local prefix:label > local prefix > inherited prefix:label > inherited prefix

## snapshot.sh

### Usage
```
snapshot.sh -h|--help
snapshot.sh -l|--label=label [-p|--prefix=auto] [-e|--force-empty] [-n|--dry-run] [zfs_dataset]...

-h, --help		Shows help
-p, --prefix		Default "auto". E.g. "somethingelse" for rpool/USERDATA@somethingelse_20230507-2245_hourly
-l, --label		Label for finer resolution. E.g. "hourly" for rpool/USERDATA@auto_20230507-2245_hourly
-e, --force-empty	Force creating of empty snapshots
-n, --dry-run		Does not actually create snapshot
-d, --debug		Debug mode (set -x)
-v, --verbose		Verbose mode
```

Note: On FreeBSD is supported only short form of params.

Creates snapshots by defined prefix and label recursively.
Its behaviour is controlled by zfs dataset property "cz.solctech:snapshot:<prefix>:<label>".
Value of property specifies if snapshot creation has to be done.

#### Property value format
((on|yes|true)|(off|no|false))[,(no-dive|nodive)]

#### Property value examples
on \
off \
on,no-dive

### Example
Allow snapshot creation for default prefix "auto" and label "hourly" for whole rpool.
```shell
zfs set cz.solctech:snapshot:auto:hourly=on rpool
```

Don't want auto snapshots for anything in rpool/STORAGE/docker, even don't want traverse into child datasets.
```shell
zfs set cz.solctech:snapshot:auto:hourly=no-dive rpool/STORAGE/docker
```

Specify correct prefix, specify datasets (or omit for all locally imported), and try dry run.
```shell
snapshot.sh --dry-run --label=hourly rpool
```

If everything seems ok, put in cron.

## purge.sh

### Usage
```
purge.sh -h|--help \
purge.sh -p|--prefix=snapshot_prefix [-n|--dry-run] [zfs_dataset]...

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
purge.sh --dry-run --prefix=backup rpool
```

If everything seems ok, put in daily or weekly cron.

## release.sh

### Usage
```
release.sh <snapshot1> [snapshot2 ...]
```

Releases all holds on given list of snapshots.

### Example
Release all holds on snapshot **rpool@backup_123**. 
```
$ release.sh rpool@backup_123

Releasing holds for snapshot: rpool@backup_123
 Hold tag: last_backup
```
