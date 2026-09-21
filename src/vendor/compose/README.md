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

## Changing the pin

```sh
python3 tools/sync_compose.py --bump <full 40-character commit>
```

`--bump` changes the commit name, both hash inventories and the files together,
from one archive of that commit. It prints the snapshot files that changed and
any document that still names the previous commit. Then re-record the
provenance receipt and run `tools/verify.sh full`.

Do not edit `commit` by hand. `--check` compares the files with the lock's
inventory; it cannot ask, offline, whether that inventory came from the commit
the lock names. A hand-edited `commit` therefore still verifies, against the old
files.

To read from a local checkout instead of the network, add
`--source /path/to/compose` to either command.
