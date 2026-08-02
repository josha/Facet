# Prior gates — before vs after the Step 5.5 cleanup

All 16 registered gates were run twice with the same script: once at the frozen
baseline **before any source edit**, and once at the final cleanup source.

- Before: `baseline/prior-gates-before.txt`
- After: `prior-gates.txt` (raw runner output, unedited)

| Gate | Before | After | |
|---|---|---|---|
| phase-0-foundation | PASS | PASS | |
| phase-1-minimal-screen | PASS | PASS | |
| phase-2-settings-parity | PASS | PASS | |
| phase-3-pilot | PASS | PASS | |
| part-2-director | PASS | PASS | |
| phase-4-hardening | PASS | PASS | |
| input-adaptation-audit | PASS | PASS | |
| expansion-textinput | PASS | PASS | |
| input-paradigms | PASS | PASS | |
| native-substrate | PASS | PASS | |
| native-stylesheets | PASS | PASS | |
| authoring-adaptive-ui | **FAIL (exit 1)** | **FAIL (exit 1)** | unchanged — see below |
| theme-packages-and-skinning | **FAIL (exit 1)** | **PASS** | **repaired by this stage** |
| rich-skinning-v2 | PASS | PASS | |
| cross-platform-proof | PASS | PASS | |
| sponsor-framework-gaps | PASS | PASS | |

**15 of 16 exit zero. Nothing regressed. One gate was repaired.**

## The two that are not a plain PASS

**`authoring-adaptive-ui` — FAIL at baseline, FAIL after, identically.** Its only
non-passing row is `physical-and-human-rows`, state `PENDING`, which the gate
runner treats as failing by design (a `PENDING` row must not pass a gate). This is
that stage's own standing physical/human rider and it is byte-identically the same
before and after, so it is **unregressed**, not caused here. The Step 5 record
already carried it this way ("PASS\* authoring-adaptive-ui … 1 PENDING … unchanged
since that stage closed = UNREGRESSED").

**`theme-packages-and-skinning` — FAIL at baseline, PASS after.** This was **red
before the cleanup started** and the cleanup found out why. Its
`metric-snapshot-single-source` check ended in

```
cmp -s artifacts/.../baseline-neutral-dump.json artifacts/.../final-neutral-dump.json
```

— a comparison of **two stored files**. That proves nothing about the current tree,
and it went red the moment `tools/lune/_theme_baseline`, whose target path
**defaulted** to `baseline-neutral-dump.json`, was run without an argument
(2026-07-28 13:40, before this stage's baseline freeze — the file's mtime and a
prose "do not run this without an argument" warning in
`docs/handoff/SHOWCASE_DEVICE_PASS.md` are the record).

Fixed in two places (ledger **C-08**/**C-09**): the check now runs
`tools/lune/check_flat_baseline`, which **regenerates** the neutral render from
live source and byte-compares 1 140 nodes against the frozen 3.5 baseline with a
named allow-list; and the generator now **requires** its target path, so running it
bare exits 2 with an explanation instead of destroying a comparison input. A
required argument needs no prose warning.
