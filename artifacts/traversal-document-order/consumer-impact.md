# Consumer impact — LuauUI `traversal-document-order` → Rascal Rally

**Ledger row:** TD-15
**Contract:** `docs/plans/agent-execution-contract.md` § "Rascal Rally consumer lockstep"
**Game source:** `games/RascalRally/code`
**Game suite at this LuauUI source:** **3026 passed, 0 failed**
(was `3019 passed, 1 failed` before this stage — see §3)

Rascal Rally's normal and debug Rojo projects mount `GameStudio/ui/LuauUI/src`
directly, so every changed contract is audited here against the game's real callers
with file:line evidence, not asserted.

---

## 1. Changed contracts, and what each does to the game

| # | Changed contract | Kind | Production callers in `games/RascalRally/code/src` | Action |
|---|---|---|---|---|
| 1 | `traversalPriority` — new optional prop on `Button`/`Toggle`/`TextField`/`Grip` | additive, optional | **none** (`grep -rn traversalPriority src/`) | none needed |
| 2 | `handle.focusOrder()` — new method on the present handle | additive | **none** | none needed; now exercised by a new game test (§2) |
| 3 | `FocusScope.traversalRank` — new optional field | additive, internal to the graph | **none** (`grep -rn newFocusGraph src/`) | none needed |
| 4 | `graph.setOrder(name, order, rank?)` — new optional 3rd arg | additive, back-compatible | **none** | none needed |
| 5 | `graph.replaceGroups(scope, groups, rank?)` — new optional 3rd arg | additive, back-compatible | **none** | none needed |
| 6 | `graph.focusMap(scopeName?)` — new method | additive | **none** | none needed |
| 7 | `ButtonSpec`/`ToggleSpec`/`TextFieldSpec`/`GripSpec` gain `traversalPriority: number?` | additive optional field | **none** construct these specs with exhaustive type annotations | none needed |
| 8 | **Behavior:** Tab visits a focusable `Grip` in document position | behavioral | **none** — see §1.1 | none needed; pinned by a new tripwire test (§2) |
| 9 | Docs: `PresenterOpts`/`PresentOpts.keyboardNavigation`, corrected gameplay-band numbers | documentation | n/a | game docs make no claim about either; no game doc change was correct |

### 1.1 Why the behavioral change (#8) is a genuine no-op here

The change moves **focusable Grips only**. The shipped controls that produce one are
exactly two — `newSlider`'s track (`src/controls/slider.luau:427`) and `newRating`'s
strip (`src/controls/rating.luau:305`). Table's column-resize Grip carries
`focusable = false` (`src/controls/table.luau:1079`, "POINTER ONLY NOW"), so it is
not a focus stop at all.

Rascal Rally mounts **none of the three**:

```
$ grep -rn "newSlider\|newRating\|UI.Grip" src/
(no matches)
```

Nor does it hand LuauUI a focus map of its own (`grep -rn navigationGroups src/` →
no matches), so its surfaces take the framework-derived, now-ranked map.

**No production edit was made, and manufacturing one would be wrong** — the
execution contract says so explicitly: *"Do not manufacture a production-game edit
for a compatible internal change. In that case, update or add the game-side
compatibility test/evidence and record why no caller change was correct."*

---

## 2. Game-side test added: `tests/luauui_focus_order_contract.spec.luau`

Five cases against the **real** shipped role-pick modal, built exactly as the game
builds it and presented through the game's own `LuauUISponsor.ROLE_MODAL_OPTS`:

1. `handle.focusOrder()` answers for a real shipped surface (schema, `present`,
   `trap = true` for the mandatory modal, non-empty).
2. **The tripwire.** Both readings of the focus map are byte-identical for this
   surface — the precise, falsifiable form of "the change is a no-op here". Asserts
   non-empty first, so an empty map cannot pass as a clean no-op.
3. Every entry's authored `priority` is `0` (the game declares no tiers).
4. `ranked = true` — the framework owns this surface's map, so game surfaces are
   opted **into** document-order traversal rather than accidentally out of it.
5. The dump survives dismissal, so a device-pass debug overlay cannot crash the
   client.

**The tripwire is proved to bite.** Temporarily wrapping the role-pick modal around
a `newSlider` made case 2 fail and nothing else:

```
MUTATION: a Slider added to a game surface —
  ✗ both readings of the focus map are identical — no focusable Grip in this surface
```

That is the point of it: the day somebody adds a Slider to a Rascal Rally screen,
this test tells them the Tab order of a shipped surface just changed, instead of a
director finding it in a playtest.

---

## 3. A pre-existing game-test failure, fixed (Step 8 lockstep debt)

`tools/gate.sh desktop-keyboard-navigation` re-run at the **unmodified** pre-change
source returned `FAIL_RECOVERABLE`, and one of the two causes was the game suite:

```
✗ the results surfaces keep Space for the celebration skip, not for Activate
    tests/luauui_closed_key_contract.spec:134: expected false to be true
```

**Cause.** That test's mutation-proof half asserts a surface presented *without*
`gameplayGuard` **does** claim `Space` for Activate. LuauUI Step 8 made the Space
binding conditional on `keyboardNavigation`, which defaults to **`false`** (the
director's fix for Space stealing the avatar's jump). The game rig's
`presenterWorld()` builds `newPresenter` with no opts, so no Space binding can exist
whatever `gameplayGuard` says, and the proof cannot pass.

**Fix.** A `keyboardPresenterWorld()` helper builds the same world with
`keyboardNavigation = true`, and the mutation half uses it — putting the surface in
the one state where `gameplayGuard` has something to decide. The shipped screens are
untouched and still present through the game's own presenter with its own opts.

**And the gap that hid it.** The first half of that pair (`gameplayGuard = false`
binds no Space) had been passing *for the wrong reason* since Step 8: with
`keyboardNavigation` off by default, **no** surface binds Space, so the assertion
could not fail. A new case pins the default itself:

> `a results surface WITH the guard binds no Space even under keyboard navigation`

so the pair now states the whole rule instead of half of it.

**Game behavior is unchanged by all of this.** `ResultsScreen.PRESENT_OPTS`,
`PRESENT_OPTS_RACER` (`gameplayGuard = false`, `src/client/LuauUISponsor/ResultsScreen.luau:315,334`)
and `LuauUISponsor/init.luau:583` (`gameplayGuard = true`) are byte-identical; the
production LuauUI Sponsor default and the `UseLuauUISponsor = false` legacy rollback
are untouched.

---

## 4. Commands and results

| Command | Result |
|---|---|
| `GameStudio/ui/LuauUI/run-tests.sh` | **3113 passed** (stage start 3079) |
| `games/RascalRally/code/run-tests.sh` | **3026 passed, 0 failed** (before: 3019 passed, **1 failed**) |
| `grep -rn "newSlider\|newRating\|UI.Grip\|navigationGroups\|newFocusGraph" src/` | no matches |
| Studio canary in the game's own place | **row TD15-consumer-canary — see `studio/traversal.json`** |

---

## 5. Preserved, explicitly

- Game behavior, content ownership, and feature flags: unchanged.
- The production LuauUI Sponsor default and the `UseLuauUISponsor = false` legacy
  rollback: unchanged.
- The legacy Sponsor modules (`SponsorRacerList`/`SponsorGui`/`SponsorWidgetKit`):
  untouched.
