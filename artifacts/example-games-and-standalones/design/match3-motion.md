# Match-3 motion — design

Reworks `examples/gallery/examples/07_match3.luau` (627 lines). Binding scope:
`docs/plans/example-games-and-standalones.md`, "Match-3 motion".

---

## 1. What is there now, and why it is the wrong shape

The board logic is good and stays: a 6×6 grid, five kinds, a seeded Lehmer
generator, a deal that clears accidental opening runs and re-deals until a legal
move exists, cascade resolution, async tile art with a recovery path, and
four-input play. None of that is in question.

The presentation is the problem, and the file says so itself at lines 398-402: swaps
are instantaneous **by deliberate choice**, with a comment recording that animating a
tile over time was "a separate expansion gate" and "intentionally not built".

Concretely, today:

- **Swap** (`swapCells`) swaps two values in the grid array and calls `syncAll()`.
- **Match** (`resolve`) sets matched cells to `nil` immediately.
- **Gravity and refill** (`collapse`) shift the array down, insert at the top, and
  `syncAll()` repaints every cell's signal in one synchronous pass.

Every cell is a fixed position holding a `kind` signal. So a "swap" is two pictures
exchanging inside two stationary boxes. Nothing moves, because nothing *is* a tile —
there are only cells that currently show something.

That is the thing requirement M3-1 names: **give every tile a stable identity, so
motion represents the same tile moving rather than a picture changing inside a fixed
cell.** It is a change of what the board *is*, not a coat of animation on what it
already was.

**One thing the current file gets right and must keep getting right:** an exhaustive
scan finds zero uses of `TweenService`, `task.wait`, `task.delay`, `RunService`,
`Instance.new`, or raw pixel offsets. There is nothing to migrate off. The whole risk
of this rewrite is *introducing* one of them while building motion, which is exactly
what the plan forbids.

## 2. The board becomes a set of tiles

```
model:  tiles = { { id = 17, kind = "c", row = 3, col = 5 }, … }
              — id is allocated once, at deal or refill, and never reused
              — row/col are where the tile IS, and the only thing a move changes
```

Rendered as an anchored, keyed collection:

```lua
UI.Anchor{
  id = "Board", width = …, height = …,
  children = { UI.ForEach{
      items = tilesSignal,
      key   = function(t) return tostring(t.id) end,
      row   = function(t, itemScope) return tileButton(t, itemScope) end,
      transition = { enter = "materialize", exit = "fade", class = "…" },
  } },
}
```

Three published facts make this the right container, and each is why a lesser one is
not:

- **`UI.ForEach` is a keyed structural region**: "add/remove/move only; surviving keys
  keep their mounted identity and scopes; duplicate keys are hard errors". A tile that
  moves is a *surviving key*. That is M3-1, satisfied by the framework rather than by
  the example.
- **`UI.Anchor` offsets may be reactive**, and api.md names this exact idiom: "a keyed
  `ForEach` of anchored children whose `u`/`v` signals move is the minimap-dot /
  name-tag idiom: a dot update is an arrange pass and a rect write — never a
  re-measure, never a remount, so nothing blinks."
- **`presenter.withAnimation(class, fn)` paints every node whose box changed**
  travelling from where it was to where it now is. A tile's offset change *is* a box
  change. The layout still lands instantly and exactly — only the paint travels — so
  hit-testing and focus never chase a moving pixel, which is what keeps the board
  playable mid-animation.

Each tile is a real `UI.Button` with its own effective-target floor. It is not a
marker layer: markers are display-only by contract and sit below that floor, and these
have to be tappable.

## 3. The sequence, phase by phase

The plan requires a visible ordering. Each phase below names the public mechanism
that produces it and the evidence that proves it happened.

| # | Phase | Mechanism | Evidence |
|---|---|---|---|
| 1 | The two selected tiles travel to each other's positions | swap `row`/`col` on both tiles inside `presenter.withAnimation` | an intermediate dump between the two endpoints shows both tiles at neither endpoint |
| 2 | An invalid swap returns them, with feedback | swap, then swap back inside a second `withAnimation`, plus the existing refusal message | the same intermediate evidence in both directions, and the refusal text |
| 3 | A valid match marks and removes the matched tiles | remove those ids from `items`; `ForEach`'s `exit` transition runs | the tiles are gone from the model and still mounted-but-retiring for the exit's duration |
| 4 | Survivors drop into their new rows | decrement `row` on each survivor inside `withAnimation` | intermediate positions between old and new row |
| 5 | New tiles enter from above | append new ids with `row` above the board, then move them in — or let the `enter` transition carry them | new ids appear; their first painted position is not their resting one |
| 6 | Cascades repeat 3-5 before input unlocks | the resolution state machine below | the lock is observable, and the phase log lists each repetition |

**A departing tile retires, it does not vanish.** The framework's own contract: an
exiting `ForEach` row "stays mounted in its slot, clamped to its old index, turns
non-interactive — focus order and tap routing both skip it — and disposes when the
exit completes". So a matched tile cannot be tapped on its way out, and the example
writes no code to prevent it.

**The 500 ms exit cap is flat and non-overridable**, and it is *clock* time. Nothing
animates and no deferred teardown completes without `presenter.tick(dt)`.

## 4. The resolution state machine

A cascade is a sequence of phases with durations, which is exactly the shape that
tempts a `task.wait` loop. It gets none.

`presenter.onTick(fn)` is, in the framework's own words, "the one sanctioned frame
source outside the motion clock — a second `RunService` connection in a consumer is
the bug class it prevents". The example registers one hook, owned by its scope, and
advances its phase on the presenter's own clock:

```
onTick → elapsed += dt
       → if elapsed >= phaseDuration then advance to the next phase
```

Under the headless suite the same machine is driven by a scripted `dt`, so every
intermediate frame in §3's evidence column is a deterministic assertion rather than a
race. That is the whole reason the resolution runs on the injected clock and not on
wall time.

**Input is locked while resolving**, and visibly: the tiles read as unavailable rather
than silently swallowing taps, because a control that ignores a tap without saying so
is indistinguishable from a frozen game. A tap during resolution is refused with the
same message vocabulary the game already uses for its other refusals.

## 5. Reduced motion is the framework's job, not the example's

This is worth stating plainly because it is the most likely place for the rewrite to
grow a branch it must not have.

Structural transitions under reduced motion "place instantly and fire the same events
on the same frame — nothing is dropped, because the motion authority's own
reduced-motion contract does the substituting". `presenter.withAnimation` rides the
same authority.

So the example writes **no** `if reducedMotion then` anywhere. Ordering, feedback,
final state and the game's rules are identical because they are driven by the state
machine, not by the animation; decorative travel disappears because the motion
authority removed it. The Full/Reduced parity test asserts that the two runs produce
the same board, the same score, the same phase log and the same deterministic replay —
and that the Reduced run does not substitute some other busy effect, because there is
no code path in which it could.

Simultaneous moving and flashing tiles are bounded by the board: six by six, and a
cascade step moves at most one column's worth at a time.

## 6. What the tests must catch that endpoint assertions cannot

The existing 22 cases stay. The new ones are all about the middle of a motion, because
"the board is correct afterwards" is exactly what the current instantaneous
implementation already proves.

- **Identity.** After a swap, the mounted node for tile 17 is the same node it was
  before — same identity, same scope. A rewrite that keys by cell passes every
  endpoint test and fails this one.
- **Intermediate position.** At a scripted `dt` halfway through a swap, both tiles are
  at neither endpoint. This is the case that fails if someone reintroduces an instant
  snap.
- **Ordering.** Removal strictly precedes gravity; gravity strictly precedes refill;
  input unlocks strictly after the last cascade.
- **Interruption and reset.** A reset mid-cascade leaves no lingering animation record,
  no retiring row, and no registered tick hook.
- **Full/Reduced parity.** Same outcomes, same events, same replay.
- **No second animation system.** A source scan of the example for `TweenService`,
  `RunService`, `task.wait`, `task.delay`, and raw instance writes — which currently
  finds zero and must keep finding zero.

## 7. Boundaries

| Owns | What |
|---|---|
| **Example** | tile identity allocation, the board model, seeds, match/gravity/refill rules, the legal-opening guarantee, phase durations, refusal copy, and which motion classes it asks for |
| **Facet** | keyed identity across a move, the travel itself, structural enter/exit, the clock, the tick hook, the exit cap, the reduced-motion substitution, and the retiring subtree's non-interactivity |

If a phase in §3 cannot be expressed through those public mechanisms, that is a
framework gap: it gets a row in the responsibility ledger and is fixed in Facet behind
a public API. It does not become a local helper in an example.
