# A per-path cache outlives the node it remembers

**Found live 2026-08-04** (RascalRally production, the Step 8.5 director round's
tail): the sponsor HUD's watch-cycle buttons painted their full semantic labels
— "Previous racer" / "Next racer" — ellipsized to "…" in their 44 px boxes, at
**every** text preference, after one minimize → restore → minimize pose dance.
A fresh mount painted the compactLabel chevrons correctly, which is why the
device pass that shipped the feature (2026-07-27) saw it working.

## The mechanism

`applyCompactLabel` keeps a minimal-write cache, `lastCompact[path]`, so a
steady layout costs zero writes. Paths are **reused** across a structural
remount (a `When` branch, a ForEach row, a re-created ViewThatFits candidate):
the re-created Button is born painting its **full** label (creation-time
props), but the surviving `lastCompact[path] == true` said the swap was already
applied — so the post-solve seam never wrote the glyph again, for the rest of
the session.

`structuralSync`'s removal block already cleared eight sibling caches for
exactly this reason (its own comment: *"paths are REUSED across a structural
remount … Leaving them made a fresh instance inherit the old verdict"* —
verifier finding V10). `lastCompact` was added after that comment was written
and was never added to the list.

## The rules

1. **Any `last*[path]` minimal-write cache must die in `structuralSync`'s
   removal block.** The block is the one place node death is known; a cache
   cleared anywhere else (or nowhere) makes a reborn node inherit a dead
   node's verdict. When adding a new per-path cache, add its clear line in the
   same commit.
2. **A fixture that mounts once cannot witness a remount defect.** Every
   headless witness for compactLabel was green because every fixture mounted
   the button once. The regression pin (`compact_label.spec` — "a REMOUNTED
   button gets its verdict re-applied") toggles a `When` off and on and reads
   the drawn label after the second mount; the consumer pin
   (RascalRally `luauui_sponsor_table.spec` — "the ‹ › GLYPHS survive a
   pose-toggle remount") drives the production presenter through the exact
   live dance. Mutation-verified: commenting the clear line fails only these.
3. **"Device-verified once" dates a behaviour, it does not guarantee it.** The
   chevrons were verified on device the day they shipped; the defect needed a
   second mount to appear and no scripted pass ever did one.

## The sibling lesson from the same director round (game-side fix, framework-relevant)

The headless measurer (`text_metrics` + calibration) reads GothamSSm Heavy
~1 px **narrower** than the engine paints it. A fixed box sized *near-exactly*
to a measured string ("2nd" in the results standings' 44 px place cell at
`Largest`) passes every headless truncation pin and still ellipsizes live.
Reserves derived from the measurer must either carry an explicit margin
(RascalRally `ResultsParts.PLACE_PAINT_MARGIN`) or use the deliberately
over-estimating glyph-em path — and a headless truncation pin on a box with
< ~2 px of slack is not a witness; only the live `TextFits` read is.
