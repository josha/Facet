# Legacy style reference (director-requested, 2026-07-30)

Captured from the SHIPPED legacy presenter (flag off), rig-held racing, live
play staged via arm→tap. Full frames + crops. The styling authority for
DV-1..DV-8; per the director: "make sure we style the racer list, icon, and
lock/timer similarly."

| File | Shows |
|---|---|
| `legacy-pill-t2-ring-pillband.png` | **THE applied-card pill** (Bruno P3): thin GOLD-stroked rounded pill, gold spark icon inside, author badge ("S" in a circle) attached at the LEFT cap with the depleting countdown ring around the badge; sits between name and position. This is the form + gold(help) hue reference |
| `legacy-pill-t0-land / -t2-ring / -t6-cooldown` (+ crops) | Ring lifecycle: land → mid-deplete → cooldown continuation (same pill identity throughout) |
| `legacy-pill-t2-ring-rowband.png` | **Row resting anatomy**: flat dark plate, NO outline, subtle corner, swatch circle left, bold white name, bold P# right; generous row gap |
| First rowband crop (map edge) | **Map name tag**: bold white text on a dark pill beside the dot — the DV-3 readability bar |
| `legacy-pill-locked-pillband.png` | **Finished-row treatment** (Toby P3): checkered glyph, receded name/swatch, latched position, emptied gate strip |
| Bolt's pill in `../rows/FIX-max-rawpane-racing.png` (LuauUI side, pre-DV) | A second pill variant (red-ringed badge) for contrast comparison |

Not captured live: the FOREIGN-LOCK form (lock glyph + refilled reopen ring) —
both staging attempts got swallowed by race finishes (finished empties the
gate strip, §4.1). Its exact form: SponsorWidgetKit lock glyph builder +
reopen-ring construction; the ratified description is §4.2 `locked` /
`lockedForever`. Style it from source + §4.2; verify in the next live pass
with a longer race or an early-race shield write.

Purple (hinder) hue: not present in these frames (the staged play landed a
help/gold pill); extract the exact purple from legacy source constants
(SponsorTuning / SponsorWidgetKit family colors) — DV-1's instruction.
