# ADR-0035 mutation evidence — every check deliberately broken, and what reddened

**2026-08-15.** Each row below is a real edit applied to the working tree,
`tests/preferred_transparency.spec.luau` run against it, and the edit reverted in the
same process. A check that reddens nothing is a check that proves nothing, and this
file reports one such non-result honestly (M5, first two attempts) rather than
counting it as a pass.

Harness: a python wrapper that asserts the anchor exists before editing, runs the
spec, restores the original bytes in a `finally`, and — added after M5 — **fails loudly
when the mutated file does not compile**, because a mutation that does not load
produces the same "nothing reddened" output as a mutation nothing catches.

| # | the deliberate defect | what reddened |
|---|---|---|
| **M1** | `backdropTransparency` returns `base`, ignoring the preference entirely | *is base x preference — 1 is the identity and 0 is fully opaque*<br>*a garbage preference is the IDENTITY, never a silent paint change*<br>*scaling an INVISIBLE background does not dim it, it reveals it* |
| **M2** | a **second** translucent background appears in the sheet (`Raised panel` → `BackgroundTransparency = 0.2`) | *the ONLY rule painting a see-through background is the backdrop*<br>*the declared patch scope is exactly the measured set of translucent backgrounds* |
| **M3** | the hairline joins the patch scope — the "multiply everything" edit arriving by the back door | *the declared patch scope is exactly the measured set…*<br>*scaling an INVISIBLE background does not dim it, it reveals it*<br>*the DISABLED dim is untouched — the alpha there is the state, not a backdrop*<br>*the HAIRLINE is untouched — a stroke is a border, and the setting names backgrounds* |
| **M4a** | the renderer's push **at attach** is dropped | *arrives at attach with no consumer wiring at all* |
| **M4b** | the renderer's **mid-session observer** is dropped | *…and again when the player moves the setting mid-session* |
| **M5** | the preference is folded into the **authored** opacity term (`presentation.composeAlpha`), published through the adapter by the renderer — the exact fight ADR-0035 Decision 2 refuses | *opacity 0.5 stays 0.5 at every preference, including fully opaque* |
| **M6** | the bespoke painter reverts to the bare token read (`= style.extra.scrimOpacity`) | *the bespoke scrim write goes through backdropTransparency, not a bare token read* |
| **M7** | the native rule patch stops reading the declared scope | *the native rule patch goes through it too, over the DECLARED scope* |
| **M8** | `SCRIM_RULE` drifts from the rule name both builders emit | *the ONLY rule painting a see-through background is the backdrop*<br>*…and in a compiled theme package too, whatever its own dim is* |

## The non-result, reported rather than hidden

**M5 first reported NULL twice.** Both times the injected line was
`(_G :: any).__prefT = …` / `(adapter :: any).__prefT = …` placed after a statement
ending in `)`, which Luau rejects:

```
syntax error: src/render/renderer:3229: Ambiguous syntax: this looks like an argument
list for a function call, but could also be a start of new statement; use ';' to
separate statements
```

The module failed to load, the spec run produced no `✓`/`✗` lines at all, and the
harness read that as "nothing reddened". **A broken mutation is not a null result**,
and reporting it as one would have published a false claim that the
authored-opacity refusal was untested — the opposite mistake to the one this
discipline usually guards against, and just as wrong.

It was caught by not believing it: a control probe printed inside `composeAlpha`
showed the function *was* reached (`COMPOSEALPHA nil 0.5`), so a null there was
impossible if the mutation had run. Rewritten as
`local __ad: any = adapter` + `__ad.__prefT = …`, it compiled and reddened the named
case immediately.

The harness now refuses to classify a run containing `syntax error` / `Ambiguous` as a
null result. That guard is the transferable part.

## What mutation testing could NOT reach here

`src/client/screen_paint.luau` and `src/client/screen_target.luau` reach engine
globals at load, so their behaviour cannot be mutated under Lune — only their
**source** can be pinned (M6, M7 are source contracts). The behaviour those two files
own is covered by the live Studio probes instead, in both paint modes:
`artifacts/adr-0035-preferred-transparency/live-probes.md` §2–§4. Stated here so the
coverage boundary is a recorded fact rather than an assumption.
