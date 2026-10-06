# Verify engine adoption receipt

Facet uses the same test library as Compose for instance hierarchy, signals,
attributes, destruction and object counts. Verify owns these mechanisms.
Facet keeps explicit UI fakes for text measurements, styles, focus, cloning and
Lune datatype differences. These fakes do not prove native engine behavior.

## Scope

The baseline is Facet `954d43fdda25b0787fae22eb895ec256babe8526`, after PR 70.
Verify is `89140aab72e02e47050e6283064b72721ca7c8af`.
Compose is `60b9241d66a8b5611a01cec50893f70419341e1b`.
The registered 3,765 case IDs and all 151 sources are retained. The full plan
still selects 150 sources and 3,731 cases. The existing release-only skip and
separate `native_toast` source are retained. No case or example was removed.
Historical assertion parity is not established. Read the
[verification scope](../docs/guide/18-verification-scope.md).

The fixture and snapshot sync implementation use 923 lines, down from 1,114.
This is a reduction of 191 implementation lines. This count excludes new
sync regression tests, test adaptations, documentation and generated snapshots.
It is not the net line count of the whole pull request.

## Native contracts

Roblox `Instance.Destroy` locks `Parent`. Verify exposed cleanup that wrote to
that locked property. Region cleanup now respects Compose owner disposal.
Borrowed modal content uses Compose `runtime.borrow` in a dependent mount.
A live Studio test reopened borrowed Sheet body, header and hero instances
twice. All three survived dismissal and were destroyed when their owner ended.

Roblox descendant `AncestryChanged` handlers receive the moved ancestor and
its new parent. Live Studio confirmed this payload. The fixture test now checks
that native payload and retains its order and connection assertions.

Roblox `GuiObject.GetStyled` and native StyleSheet padding were checked.
A modal skin must preserve the StyleSheet spacing floor when it reserves art
insets. Zero-default panel padding uses the live theme spacing step when no
explicit reserve is present. Sheet keeps its own reserve. The live geometry checks
include the tail reach in Callout spacing, measure the settled sidebar rail,
and check panel padding against both theme spacing and art insets. Their
numeric tolerances and all 421 checks are retained.

Compose owns borrowing, dependent mount cleanup, shared resources and reactive
bindings. No general engine mechanism was added to Facet.

## Dependency snapshots

Both sync commands use `tools/snapshot_sync.py`. Tracked snapshots verify and
build offline. A deleted commit or upstream force push cannot break a valid
Facet checkout. SHA-256 inventories include every generated source and guide.
Checks reject changed files, extra files and extra directories.

The source archive is copied without source patches. External relative links
in copied Compose agent guides are relocated to the exact upstream commit.
The guide inventory records the relocated bytes. Four regression tests cover
offline use, damaged snapshots, repair, archive integrity, unsafe paths and
guide links.

## Evidence

Evidence is stored under `artifacts/verify/` in the adoption worktree.
`tools/verify.sh full --jobs 4` passes the native gate. All 78 producers are
accounted for by the native gate.
The suite passes 3,730 cases, fails no cases and skips the existing release-only
case. The separate Toast source passes all 34 cases. The default type solver
checks 708 targets with no owned or dependency diagnostics. All 181 negative
API probes are rejected.

Live Studio passes all 13 geometry cases and 421 checks at a 1279 by 720
viewport. The borrowed Sheet ownership test and native ancestry payload test
also pass. These checks do not establish all historical Studio coverage.

Package build, status, verification and canary checks pass. Facet remains
version 0.12.0. No package is published.
