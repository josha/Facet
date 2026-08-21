# `withAnimation` animates size — the design, and the deferral it reversed

**Shipped 2026-08-14.** Source comments in `src/render/renderer.luau`,
`src/client/screen_target.luau` and `tests/lib/fake_target.luau` point here for
the *why*; the code carries the *what*. Reader-facing documentation is
[`../reference/swiftui-parity.md`](../reference/swiftui-parity.md) §8.1.

## The question, and the short answer

The game director asked: *"should we improve our `withAnimation` system to
handle more than position?"*

Yes, and there is a clean stopping point rather than an open-ended list.
`withAnimation` interpolates the difference between two commits, so the only
values it can interpolate are the values a commit **produces**: the solver's
rect — `x`, `y`, `w`, `h`. Position was two of the four. All four now animate,
and that is the whole set. Everything else SwiftUI's `withAnimation` reaches is
an *authored paint* value, which Facet has none of in this channel — see
"Opacity" below, where the answer is *not yet, and here is the actual blocker*.

## ELI5

A screen that changes redraws instantly. `withAnimation` says "still land it
instantly, but *paint* it arriving". Until now that only worked for things that
**moved**. If a card got taller, the card popped to its new height while
everything below it slid down — one thing on screen not travelling with the
rest. Now the card grows too, on the same spring, and lands on the same frame.

One thing worth knowing because it is not obvious: when a box grows, the things
**inside** it do not grow. A label pinned to the top of a card stays exactly
where it is while the card opens underneath it. That is deliberate and it falls
out of how Facet draws (below).

## Judging the round-2 deferral

`parity-round2.md` §"Size is NOT animated this round" recorded five
mechanisms. Judged one at a time, against source, on 2026-08-13/14.

| # | Recorded mechanism | Verdict |
|---|---|---|
| 1 | *"`applyRect` also writes the hit expander, the focus-ring float, `refitIconArt` and `applyPathPoints` — an interpolated size re-fits icon art and re-scales normalized path control points **every frame of the flight**"* | **FALSE, and it was already false when written.** The shipped *position* animation's write path is `screen_target`'s `transform` branch, which calls `recomputePresentationOffset(other)` **and `applyRect(other)` for every handle in the animated subtree, every frame** — and `applyRect` unconditionally calls `refitIconArt` and (for a Path2D node) `applyPathPoints`. Those four passengers were already on the per-frame budget for every position flight that has ever run. Size adds **no call**; it changes two numbers inside calls that were already happening. This was the load-bearing reason, and it does not hold. |
| 2 | A wrapped `TextLabel` re-wraps and can ellipsize mid-flight; a `Slice`/`Tile` image re-caps | **TRUE, and not a blocker.** This is what animating a size *means*, and SwiftUI's own frame animation means the same thing — Apple's `Animatable` describes interpolation of the value itself, with no carve-out for content that relayouts ([SW-144]). It is a consequence to be aware of, not a reason to refuse. Authors who need text to hold still across a growth have the same tool SwiftUI authors do: don't put a re-wrapping string in the dimension you are animating. |
| 3 | A clip host re-bases children against the **solved** rect, so a shrinking host cuts them | **TRUE, and correct.** A clip host that shrinks should crop; that is what clipping is. Children are positioned from the solved rect either way, so nothing is misplaced — the crop simply travels with the box. |
| 4 | A `canvasGroup` renders its subtree into a buffer sized to itself | **TRUE, and the one genuinely new per-frame cost.** Re-allocating a render buffer 60 times a second is real GPU work that a position flight never provokes. It is not a correctness problem and it is bounded by the flight, so it is **measured rather than refused**: the performance lab's `motion-flight` workload exists for exactly this, and the honest position is "we know where to look" rather than "it is free". |
| 5 | `Stage`/ViewportFrame re-projects its scene | **TRUE, same class as 4**, same disposition. |

**Conclusion.** One of the five was a description of work already being done;
three describe what a size animation *is*; one is a real cost with a real
instrument now pointed at it. The deferral was correct as a sequencing call for
round 2 — "do not invent a size channel while designing the position one" — and
wrong as a permanent verdict. Reversed.

## The mechanism, and the asymmetry

Nothing new was built. A `withAnimation` record was `{ x, y, set }`; it is now
`{ x, y, w, h, set }`, and `animationWrite` scales all four by the one progress
spring. The authority manifest is untouched (`transform` was already
`presentation`); the solver is untouched; there is no new channel, no new prop,
and no second writer.

The interesting half is the asymmetry, because it is the same fact producing
opposite rules:

> **Facet's instance tree is flat.** Every node parents under the root gui
> unless a real parent claimed it, and the solver positions absolutely.

- For **position**, that means a container's move carries nothing inside it — so
  a descendant must re-add every ancestor's offset, records are installed at
  animation *roots*, and a child that did **not** move while its parent did needs
  a compensating record to hold it still.
- For **size**, that same flatness means a container's growth carries nothing
  inside it either — and there it means a child must be **left alone**. Its rect
  is absolute; the parent's painted box growing around it must not reach it. So
  the size half is the node's **own absolute delta**, with no `inh`, no
  accumulation, and no compensating record.

Both the live adapter and the headless fake mirror that split: the offset walks
ancestors, the size reads one own-path entry. `tests/presentation_channel.spec`
pins it from the source side, with a negative assertion (`sw +=` must not appear
in the ancestor walk) that has been seen to bite.

## Decisions taken

**Reduced motion is inherited, not re-decided.** `withAnimation` is *decorative*
motion — the instant layout already carries every fact and the travel was pure
continuity — so the existing `motionClock:isReduced()` branch installs no records
and a size lands instantly for the same reason a position does. No new policy.

**There is a trap under testing that branch, and it cost a check.** Under reduced
motion the spring settles *synchronously inside* `setTarget`, and `claim`
registers `onSettle` before aiming, so records install and clear within the same
call. A record-**count** assertion therefore reads zero whether the branch exists
or not: deleting `if not motionClock:isReduced()` outright reddened **nothing**,
including the pre-existing reduced-motion case. What the branch actually buys is
the writes it never spends — "install and immediately clear" is two rounds of
amplified subtree writes per root for a visual no-op — so the check counts
adapter transform writes instead, and that one bites.

**Hit geometry follows the painted position and the solved size.** The ratified
PLAT-4 rule, unchanged: `screenRectOf` composes presentation offsets (so a
shifted control is pressable where it looks) and never scale or rotation (which
would turn a hit rect into a quad). Size joins the second group — a node
mid-growth hit-tests at the box it will have, exactly as a scaled node already
did. The *paint* half of the same box does follow the flight, including the
focus-ring float and Path2D control points, so a ring does not visibly detach
from the control it marks.

**Records are re-based on interruption, both halves.** A path claimed by a second
call carries the offset *and* the extent it is painted at right now into the new
record, so a card interrupted half-grown continues from the height on screen. The
velocity carry-over takes the largest of the four components, since all four are
pixels on one spring.

## Opacity — judged, and deliberately not shipped

The parity doc's `opacity(_:)` row records a real structural obstacle:
`transparency` is presentation-owned, the manifest permits exactly one authority
per engine property per class, and there is no presentation channel for an
authored prop. That obstacle is **still true**, and this mission did not route
around it. What this mission can add is the precise scope:

**It is not the animation system that blocks an animated opacity — it is that
there is nothing authored to animate.** `withAnimation` diffs what a commit
produces. A commit produces a rect. Opacity, rotation, scale and colour are all
authored paint values, and Facet has **no authored prop in the presentation
channel at all**: its three presentation-authority properties are `transform`,
`transparency` and `dragHeld`, every one renderer-driven, and none of them
appears in `blueprint_schema.luau`.

So the ordering is: (1) an ADR for the authority seam, including the composition
rule Apple states — applying `opacity` to a view whose opacity is already
transformed "multiplies the effect of the underlying opacity transformation"
([SW-141]) — resolved at the one write site and reconciled with the native
sheet's ownership of `BackgroundTransparency`/`TextTransparency`; (2) the
authored prop; and only then (3) the animation, which by that point is one more
component in a tuple that is already scaled by one progress value. Building (3)
first would mean inventing a second writer for a property the manifest exists to
keep single — the exact failure it was built to prevent. Not done, on purpose.

**Rotation and scale are the same shape**, and worth naming so nobody re-derives
it: both are already presentation-channel properties with a live write path, and
both are unreachable from `withAnimation` for the identical reason — no authored
declaration to diff. SwiftUI is explicit that neither changes a view's frame
([SW-146], [SW-147]), so they would be paint-only siblings of the size half
rather than substitutes for it.

## Performance

An interpolating property is per-frame work, so the lab gained a workload rather
than an assertion: `motion-flight`, pass `motionFlight`. Four arms — idle,
position-only (24 rows re-order), position+size (the same 24 rows resize), idle
again — with both flight arms seeding the **same** record count so the C-minus-B
difference is the marginal cost of the size half and not the cost of a bigger
experiment. It reports `harnessSpreadMs` = |A − A′| first, because a delta
smaller than the harness's own same-arm spread is noise.

**Tiers, and the headless one is weaker than it looks.** The lab harness supplies
`telemetry.clock` as a monotonic 1 ms stub, so under Lune every millisecond
figure the pass reports is synthetic and identical across arms *by construction*.
Headless, only the counts mean anything, and only the counts are asserted. The
timings are a Studio quantity, taken inside the lab bootstrap's per-frame
`Facet/scenario` scope. Neither tier is a device claim.

| Tier | Status |
|---|---|
| Headless Lune — structural regression signal | **Run.** 24 records on each flight arm, both sampled only while live (47 frames at 60 Hz for `container`, against a 120-frame cap), surface dismissed, channel clean. `tests/perf_lab.spec.luau`. |
| Studio session — real engine, real `GuiObject`s | **Run**, and it found something. [`../../artifacts/swiftui-parity-round3/with-animation-size-studio-canary.md`](../../artifacts/swiftui-parity-round3/with-animation-size-studio-canary.md): the engine `Size` really travels (100 → 171 at frame 8 → 200), the Panel's painted *height* and the Tail's painted *y* are the **same number** mid-flight so one spring holds across two property kinds on the real engine, and the child stayed `22x20` throughout. THE FINDING: `/S/Panel` is an **inert-elided container with no engine instance at all** before the flight — the one shape that could have thrown on a size record and the one the fake target cannot model, because it materializes everything. It materializes on demand and paints from its old height correctly. |
| MicroProfiler in Studio — a profiled capture over `motion-flight` | `PENDING_PHYSICAL` — the workload and the capture path exist; the capture has not been taken. This is the tier that can see the `canvasGroup`/`Stage` re-buffer cost from mechanism 4 above. |
| Physical device | `PENDING_PHYSICAL`. No device claim is made anywhere in this work. |

## RascalRally

The live consumer has zero `withAnimation` call sites and three write-only
`setPresentationTransform(path, {x, y, scale})` writers, so nothing in the game
was forced to change and no product change was authorized or made. The evidence
the standing rule asks for is a contract block in
`games/RascalRally/code/tests/facet_motion_and_scroll_contract.spec.luau`
(commit `24c1679`, +7 cases): a real shipped reactive size change — the docked
racer list's content-hugging panel growing 160 → 280 px as the grid fills — plus
the invariant that matters most to that package, that a settled record clears to
`nil` and not to a `{w=0,h=0}` residue, since `facet_sponsor_entry.spec.luau`
pins `props.transform == nil` at rest in six places. Every case
mutation-proved against a deliberately broken framework, restored byte-exact.
Suite 3166 passed / 2 failed, both pre-existing and confirmed by re-running the
file at `HEAD`.

Worth recording because it happened twice independently: that agent's
reduced-motion case was ALSO green under the "delete the branch" mutation, for
the same reason described above, and was rewritten the same way — to count
adapter writes. Two agents hit the identical trap from opposite ends of the same
seam, which is a good sign the trap is a property of the design and not of one
author's carelessness.

## Owed

- The Studio MicroProfiler capture over `motion-flight`, and the `canvasGroup`
  buffer-churn number it is the only tier that can see.
- `examples/places/Facet-Showcase.rbxl` rebuild for the new demo card. The
  scenario is registered in `scenarios/init.luau` and `demo_picker.DEMOS` and is
  swept by `tests/overflow_sweep.spec.luau` at every viewport and theme; the
  place binary was left alone because several agents held it modified at the
  time.
- The `api.md` per-frame-cap drift, unchanged and still owed from round 2: the
  reference claims a cap that is not implemented. Not repeated in the parity doc.
