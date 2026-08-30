# Archive receipt — the capability comparison, moved out of the public tree

**Workstream E1, 2026-08-30.** The tracked comparison document was product
research rather than product documentation, so it was refreshed against the
current Facet surface, written to the checksummed private archive outside Git,
and the tracked copy removed from the branch tip.

This receipt exists because the archive's `MANIFEST.json` and `SHA256SUMS` are
owned by the archive tool, not by this workstream. **Nothing here was written
into either file.** The director registers the row below.

## The row to register

| Field | Value |
|---|---|
| **Path** | `GameStudio/ui/Facet-private-archive/research/swiftui-capability-comparison-2026-08-30.md` |
| **Bytes** | `321697` |
| **Lines** | `2608` |
| **SHA-256** | `bdff768feaefe68c046655adddce5167535f169750be6d79d8093a203ed88dd6` |
| **Produced by** | workstream E1, 2026-08-30 |
| **Source it replaces** | `docs/reference/swiftui-parity.md` (2384 lines), removed from the branch tip with `git rm` in the same change |

Reproduce the digest with:

```bash
shasum -a 256 \
  GameStudio/ui/Facet-private-archive/research/swiftui-capability-comparison-2026-08-30.md
```

## What the archived file is

The previous revision's structure, refreshed. It carries a research header
naming the research date, the Facet commit it was taken at
(`6907f859ce5abb58259290a85fd7ceb6b0e8fdfd`, `Facet.VERSION` `0.10.0`), and the
three labels every claim now carries — **FACT** (a written statement in a named
primary source), **MEASURED** (a number or behaviour observed by running a named
instrument on a named date), **INFERENCE** (a conclusion drawn from those). A
fourth marker, `[UNVERIFIED 2026-08-30]`, is on every claim this pass could not
close; those claims are carried forward rather than silently re-asserted or
silently deleted.

The refresh is by **area, not cell by cell**, and the header says so. Seven
capability areas were re-derived from the live tree because they had moved
enough to change a verdict; rows outside those areas are carried at their
2026-08-15 reading. Every count in the document's own tables was re-measured.

## Old revisions stay in Git history

This comparison is product research, not sensitive data. **No Git history was
rewritten and none is proposed.** Every revision of
`docs/reference/swiftui-parity.md` before 2026-08-30 remains reachable in this
repository's history, and the owner packet must say so plainly. If the owner
later requires their removal from all public history, that is a separate
destructive-history decision needing its own verified candidate and rollback
plan.
