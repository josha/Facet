# `withAnimation` size — Studio canary, 2026-08-14

**Tier: MicroProfiler-less Studio session, real engine, real `GuiObject`s.** Not
a device claim. Taken because the size half only reaches a player through
`src/client/screen_target.luau`'s `applyRect`, which Lune cannot execute — the
SF-M9 defect class in this repo is precisely "a channel that is headless-green
and live-broken", and the headless suite proves the record, never the write.

## Method

`LuauUI-Showcase.rbxl` open in Studio. The place's bundled `LuauUI` copy predated
this work, so the two diffs (`render/renderer`, `client/screen_target`) were
patched into the place's ModuleScripts in Edit mode to match `HEAD` exactly, then
Play was started and the surface built in the **Client** datamodel against a real
`screen_target` adapter parented into `PlayerGui`. The canary folder was
destroyed afterwards; the place was not saved.

Surface: a `VStack` `Panel` whose `height` is bound to a memo (100 → 200 px)
holding one `Text`, with a fixed 40 px `Tail` box beneath it. Read back from the
engine objects themselves — `GuiObject.Size` and `GuiObject.Position`, not from
any framework diagnostic.

## What the engine reported

| stage | `/S/Panel` | `/S/Panel/Label` | `/S/Tail` | records |
|---|---|---|---|---|
| before | *(no instance — elided)* | `22x20 @ 0,0` | `0x40 @ 0,100` | 0 |
| seed | `22x100 @ 0,0` | `22x20 @ 0,0` | `0x40 @ 0,100` | 2 |
| +8 frames | `22x171 @ 0,0` | `22x20 @ 0,0` | `0x40 @ 0,171` | 2 |
| settled | `22x200 @ 0,0` | `22x20 @ 0,0` | `0x40 @ 0,200` | 0 |

## What that establishes, and one thing it found

1. **The engine `Size` really travels.** At the seed the Panel's solved height is
   200 and the engine object is 100 — it has somewhere to fly from — and it lands
   on 200 exactly. This is the write no headless assertion can reach.

2. **One spring, across two different property kinds, on the real engine.** At
   frame 8 the Panel's painted *height* is 171 and the Tail's painted *y* is 171.
   The same number, not a correlation: the growth and the displacement it caused
   are the same `p` times the same 100 px delta. A subtree that tore would show
   two numbers here.

3. **The size delta does not reach the subtree, live.** `/S/Panel/Label` is
   `22x20 @ 0,0` at every stage — it neither stretched nor drifted while its
   parent's box opened. The flat-tree asymmetry holds against the engine and not
   only against the fake adapter's mirror of it.

4. **THE FINDING: an elided container materializes correctly under a size
   record.** `/S/Panel` is an *inert layout container* and has **no engine
   instance at all** before the animation — LuauUI's inert-container elision does
   not build one. A size record on a node with no instance is the obvious way
   this could have thrown, and it is invisible to the headless suite because the
   fake target materializes everything. It does not throw: the transform write
   materializes the instance on demand (the same lazy path the elision was
   designed with) and the node appears at its *old* height, mid-flight, exactly
   as a never-elided node would. That is the one thing this canary was most
   worth taking for, and it is now recorded rather than assumed.

## Not covered here

- A MicroProfiler capture over the lab's `motion-flight` workload —
  `PENDING_PHYSICAL`, and the only tier that can see the `canvasGroup` /
  `Stage` re-buffer cost.
- Any device claim. None is made anywhere in this work.
