# Compose dependency

This directory is a generated, read-only snapshot of upstream Compose.
`UPSTREAM.lock` is the authority: it records the repository, the exact Git
commit, and a SHA-256 for every file. `patches` is empty. Do not edit these
files. `skills/compose/` holds the upstream agent skill and API reference from
the same commit, under the same lock.

```sh
python3 tools/sync_compose.py --check   # fail if any file differs from the lock
python3 tools/sync_compose.py           # restore the snapshot from the pin
```

A fresh clone builds and tests without network access. The verify gate runs the
check, so a local change to the snapshot cannot land.

To upgrade, set `commit` in `UPSTREAM.lock`, regenerate the two hash
inventories from that commit, run the sync, and commit the result. To read from
a local checkout instead of the network:

```sh
python3 tools/sync_compose.py --source /path/to/compose
```
