# `text.facts` / `text.lineBox` and the `composition.floorPx` fix — mutation evidence

Ruled and built 2026-08-15. Plan: `docs/plans/variable-item-extents.md`
("RULED 2026-08-15, WITH STAGE 2, AND THE ANSWER IS NOT YET" → built).

Every mutation below was applied to the shipped source, the affected spec files
were run, the mutation was reverted, and the suite re-confirmed green. A check
that has never been seen to fail is not evidence.

Harness: `tests/text_line_box.spec.luau` (20 cases) run in isolation;
`tests/luauui_line_box_contract.spec.luau` (10 cases) for the Rascal Rally rider.

---

## The finding that changed the design of the proof

**M1–M4 mutate SHARED code and the differential oracle (§4) did not fire.**

That is not a hole; it is the point, and it is worth recording because the next
agent will otherwise read §4 as covering more than it does. `text.lineBox` does
not *reproduce* the solver's arithmetic — it **calls** it
(`text_metrics.reservedSize`, `text_metrics.lineBoxPx`, the same two functions
`render/layout_node.textOf` and `text_metrics.measureAt` spend). So a mutation
inside those primitives moves the prediction and the measurement together and no
differential can see it. The guarantee there is stronger than a differential: it
is *identity*. §1–§3's cases, which assert concrete numbers, are what hold the
primitives, and they all fired.

The differential's real job is the **composition** — which scale, which offset,
which role's line height, read through which seam — and M5–M9/M15 prove it does
that job.

---

## LuauUI — 15 mutations, 15 killed

| # | mutation | file | killed by |
|---|---|---|---|
| M1 | `lineBoxPx`: `math.ceil` → `math.floor` | `src/layout/text_metrics.luau` | 6 cases (ceil-once, offset-order, all three `floorPx` defects, the untouched-halves case) |
| M2 | `reservedSize`: `size*scale + offset` → `(size+offset)*scale` | `src/layout/text_metrics.luau` | §2 "the offset is ADDITIVE and lands AFTER the scale" |
| M3 | `reserveScale`: `max(measure, paint)` → `measure` | `src/themes/snapshot.luau` | §1 "a SUB-1 preference reserves at the PAINT scale" |
| M4 | `textOffset`: always `0` | `src/themes/snapshot.luau` | 7 cases across §1/§2/§3 |
| M5 | `lineBox`: pass `nil` line height (always the library factor) | `src/layout/text_fit.luau` | §2 numeric-size role case, §2 role-override case, **§4 differential** |
| M6 | `facts{env}`: `typographyScale` only, dropping the max | `src/layout/text_fit.luau` | §1 two-forms-agree, **§4 differential** |
| M7 | `lineBox`: ceil per line, summed (`lines * lineBoxPx(…, 1, …)`) | `src/layout/text_fit.luau` | §2 ceil-once, two `floorPx` defects, **§4 differential** |
| M8 | `facts{env}`: `offset = 0` | `src/layout/text_fit.luau` | §1 two-forms-agree, §1 re-derive-on-change, **§4 differential** |
| M9 | `lineBox`: a numeric size takes `control`'s factor, not `body`'s | `src/layout/text_fit.luau` | §2 numeric-size role case, **§4 differential** |
| M10 | `floorPx`: revert the **ceil** only (raw product) | `src/layout/composition.luau` | §3 DEFECT 1 (+4 others — removing the ceil moves every number) |
| M11 | `floorPx`: revert the **scale** only (`facts.scale = 1`) | `src/layout/composition.luau` | §3 DEFECT 2, **and nothing else** |
| M12 | `floorPx`: revert the **offset** only (`facts.offset = 0`) | `src/layout/composition.luau` | §3 DEFECT 3 (+ the named-role case) |
| M13 | `lineBox`: ignore an explicit `role` | `src/layout/text_fit.luau` | §2 role-override, §2 refusals |
| M14 | `facts{metrics}`: ignore the snapshot's ten-foot `density` | `src/layout/text_fit.luau` | 5 cases across §1/§2/§3 |
| M15 | `lineBox`: a role-NAMED size takes `body`'s factor | `src/layout/text_fit.luau` | §2 role-override, **§4 differential** |

### Two mutations SURVIVED on the first attempt, and what closed them

**M9 survived the entire file.** `sizeRole or "body"` → `"control"` changed
nothing anywhere, because **every one of the eight shipped theme packages gives
every typography role the same `lineHeight`** (`out[role] = { …, lineHeight =
1.35 }`). Under all nine reference configurations, "which role's line height did
you take?" has no observable answer — so the differential, the case, and the
whole corpus were blind to it.

Closed by adding `RAGGED`, a snapshot resolved with per-role `lineHeight`
overrides (`body` 1.1, `control` 1.9, `title` 1.6, `caption` 1.45). It is a case
in §2 **and** a corpus theme in §4. M9 and M15 then both fire.

**M13 survived** for the same reason, one level along: the `role` override case
was written against Fantasy Parchment, where `title` and `body` are both 1.35, so
"the override moved the answer" was vacuously true. Rewritten against `RAGGED`.

*Lesson, general: a corpus that is uniform along an axis cannot test that axis, and
"nine reference themes" reads like breadth right up until you check whether they
differ in the dimension you are asserting about.*

---

## Rascal Rally rider — 3 mutations, 3 killed

`tests/luauui_line_box_contract.spec.luau`.

| # | mutation | file | killed by |
|---|---|---|---|
| RR-M1 | `TableMetrics.LINE_FACTOR` 1.2 → 1.25 | `src/client/LuauUISponsor/TableMetrics.luau` | the mirror case, and the `lineGrowth`-equals-the-framework case |
| RR-M2 | `floorPx` loses scale and offset (framework-side) | `GameStudio/ui/LuauUI/src/layout/composition.luau` | both consumer-side floor cases |
| RR-M3 | `ResultsParts.LINE_HEIGHT` 1.2 → 1.3 | `src/client/LuauUISponsor/ResultsParts.luau` | the mirror case, and the recorded-over-reserve case |

RR-M2 is the one that matters most: it proves the game-side rider genuinely
observes a framework change rather than restating a game constant.

---

## Live verification (Roblox Studio, LuauUI-Showcase.rbxl, Edit datamodel)

Freshness first: the datamodel was confirmed to carry strings written minutes
earlier — `function text_metrics.lineBoxPx`, `function text_fit.facts`,
`function snapshot.reserveScale`, `textFit.lineBox({` inside
`layout/composition`, `ROW_TEXT_SIZE = 16` in the adopted
`virtual_list_native`, and the ABSENCE of `local NEUTRAL_LINE_FACTOR` in
`variable_extents` (the private copy this change deleted).

Then **clone-and-require** (L-37: `require` is cached per datamodel, so reading
the right source does not prove you ran it). The clone was parented under a
throwaway folder, required, exercised, and the folder destroyed and confirmed
absent in the same call.

```
VERSION=0.9.0   facts=function  lineBox=function
Medium/+0  scale=1    off=0   1line=20  3line=58   floorPx1=20
Medium/+4  scale=1    off=4   1line=24  3line=72   floorPx1=24
Medium/+10 scale=1    off=10  1line=32  3line=94   floorPx1=32
Medium/+14 scale=1    off=14  1line=36  3line=108  floorPx1=36
Large/+0   scale=1.5  off=0   1line=29  3line=87   floorPx1=29
Large/+4   scale=1.5  off=4   1line=34  3line=101  floorPx1=34
Large/+10  scale=1.5  off=10  1line=41  3line=123  floorPx1=41
Large/+14  scale=1.5  off=14  1line=46  3line=137  floorPx1=46
```

Every number matches the headless suite exactly, and `composition.floorPx` now
agrees with `text.lineBox` at every one of the eight configurations — where
before the fix it returned **19.2 at all eight**.

### The engine's own TextBounds, which is the point of going live at all

```
+0   reserved=16  engine 3-line height=48  framework 3-line box=58  (engine 16.0 px/line)
+14  reserved=30  engine 3-line height=90  framework 3-line box=108 (engine 30.0 px/line)
```

The real `TextService:GetTextBoundsAsync` draws BuilderSans at **1.0 em per
line**; the framework reserves at its `LINE_HEIGHT_FACTOR` of 1.2. So the
reserved box is **20% larger than the engine draws, at every preference** — a
pre-existing framework property that this change neither introduced nor altered
(`lineBoxPx` is byte-identical to the arithmetic `measureAt` already used), and
it is the safe direction: the box is never short of the glyphs. Recorded here
because it is the number a future agent will want when asking whether the line
box can be tightened, and because "the headless formula diverges from the engine"
is exactly what a live check is for — it does diverge, by a known factor, upward.

---

## Suite results

| suite | before | after |
|---|---|---|
| LuauUI (`./tools/test.sh`) | 5395 passed / 0 failed | **5440 passed / 0 failed** |
| Rascal Rally (`./run-tests.sh`) | 3238 passed / 0 failed | **3248 passed / 0 failed** |

Both totals include work from a second agent live in the same tree
(`src/focus/focus_graph.luau`, the two grid controls, ADR-0030 and its two
specs). This change's own contribution is **+20 LuauUI cases**
(`tests/text_line_box.spec.luau`) and **+10 Rascal Rally cases**
(`tests/luauui_line_box_contract.spec.luau`).

`python3 tools/check_source_size.py`: PASS, `KNOWN_OVER` empty.
`src/layout/solver.luau` is unchanged at 178,598 chars.
