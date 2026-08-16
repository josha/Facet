# swiftui-parity-round4 — the reds this stage carries, and one defect in a checker

Two prior gates were red when round 4 was registered. One was **repaired**; one is
**carried** with its diagnosis. The carried one exposed a defect in the checker
itself, and that defect is booked here as its own item rather than living only in a
gate note or a commit message.

---

## DEFECT CR-1 — `theme_sync_cli` recommends the change that DELETES the feature

**Severity: high. Status: open. Owner: whoever next runs a theme Studio session.**

`tools/lune/theme_sync_cli.luau --check` compares a **live Studio dump of the active
theme sheet** against a **committed theme package** and fails on drift. It is the
engine of `theme-packages-and-skinning` / `style-editor-sync`.

Today it fails like this:

```
theme_sync: FAIL — 3 token(s) drifted between the theme sheet and
                   'examples/themes/fantasy_parchment.luau'.
  - controls.progress.circularSize:      sheet nil vs committed 30.000000
  - controls.progress.circularThickness: sheet nil vs committed 3.000000
  - controls.progress.spinnerDotSize:    sheet nil vs committed 9.000000
run theme_sync to write the sheet's values back into the committed package:
  lune run tools/lune/theme_sync_cli -- --dump …/parchment-live-dump.json \
      --package examples/themes/fantasy_parchment.luau
```

**The check is right and the code is right.** `33faac2` (2026-08-14, *the ring and
the dot spinner are theme-sized, and all eight packages now SAY so*) added those
three metrics to every package. The dump it is compared against is a Studio capture
from **2026-08-11** and therefore predates them, so the sheet has nothing to offer
for keys that did not exist when it was taken. The correct repair is a **re-record**.

**The defect is the last two lines of that message.** The tool prints one suggested
fix, unconditionally, and in *this* direction — `sheet nil` vs `committed <value>` —
that suggestion means **write `nil` over three shipped metrics**. Running it would:

1. delete `circularSize`, `circularThickness` and `spinnerDotSize` from the package;
2. make `style-editor-sync` go **green**;
3. silently un-ship a feature, with the gate then agreeing that everything is fine.

That is a checker actively recommending damage, and it recommends it at exactly the
moment somebody is looking for the quickest way to clear a red. The failure mode is
not hypothetical — clearing a red is the most common reason anyone reads this
message at all.

**What the tool should do instead** (proposed, not built here): distinguish the two
drift directions. `sheet has a value, package differs` is a genuine sync candidate
and the current suggestion is correct. `sheet has **nil** for a key the package
declares` is a **stale dump**, not drift, and the suggestion must be *re-record the
dump*, never *write the sheet back*. A dump that is missing keys the package
declares should probably be refused outright as stale before any comparison runs.

**What guards it in the meantime.** The `theme-sync-red-carried` row of the
`swiftui-parity-round4` gate asserts that the three metric **assignments** are still
present in a shipped package. So taking the tool's advice reddens *that* row instead
of greening `style-editor-sync`. That is a tripwire, not a fix.

### CR-1's own sub-finding: the tripwire was initially unable to fire

The row first greped the three metric **names**. Mutation M17 (delete
`circularSize = 30,`) did **not** redden it, because `fantasy_parchment.luau` names
all three in a **comment sixty lines above the table**:

```
-- ...and `controls.progress.circularSize` / `circularThickness` / `spinnerDotSize`
```

The grep was satisfied by **prose describing the feature it had just lost** — a
check that cannot fail. Re-anchored on the assignment (`^[[:space:]]*<name> = `),
the baseline still passes and the mutation bites. This is the fourth instance of
this class recorded today; it is only ever found by running the mutation.

---

## CR-2 — `large-text-accessibility` / `overflow-policy`: REPAIRED, not allow-listed

`4a948d0` (2026-08-14, *the truncations the wrap rule made visible, declared*)
renamed the LT6-ACTION case from

> `LT6-ACTION a Button's action label wraps and grows instead of ellipsizing at any preference`

to

> `LT6-ACTION a Button's action label wraps and grows WHILE wrapping can succeed, and never breaks a word`

— a **strictly stronger** claim. Ten of the row's eleven greps still matched, so the
gate sat `FAIL_RECOVERABLE` for two days on one pattern, and the failure looked like
a flaky suite rather than a stale name.

Repaired by re-pointing the grep at the current title, with the repair recorded in
that row's own note. **Not** allow-listed: round 3 set the precedent that a prior
gate broken by the current stage's work is repaired, and the allowlist is only for
failures the stage did not cause and cannot fix.

**The standing hazard this leaves.** A rename is the cheapest way in the world to
break a name-based check, and this is now the second consecutive stage to find one
by hand. `tools/check_manifest_integrity.py` verifies that every suite grep is
*anchored to the pass marker*; nothing verifies that every suite grep still *matches
something*. A checker that replays every grep in `gate_manifest.luau` against one
complete transcript would have caught both this and round 3's `overflow-sweep`
rename on the day they landed. It does not exist. Booked.

---

## CR-3 — `theme-packages-and-skinning` / `style-editor-sync` is allow-listed, with a condition

It is the one addition to round 4's prior-gates allowlist, and it comes off the list
the moment somebody runs one Studio session with the parchment package loaded and
re-records `artifacts/theme-packages-and-skinning/theme-sync/parchment-live-dump.json`.

Round 4 also **removed** one entry — `(traversal-document-order, studio-evidence)` —
because that red genuinely closed (`a78fd88`). An allowlist that only ever grows is
a second manifest of things nobody looks at.
