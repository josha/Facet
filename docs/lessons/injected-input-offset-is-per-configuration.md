# Injected pointer coordinates are offset per DEVICE CONFIGURATION, not per session

**Measured:** 2026-07-26, Studio 0.731.0.7310942, one Play session, one place.

Injecting a pointer event through the Studio MCP and reading the position the
engine reports back gives two different answers in the same session:

| Emulated configuration | Injected Y | Engine reported Y | Offset |
|---|---|---|---|
| `samsung_galaxy_s22_ultra` portrait, viewport 360×691 | 645 | 598 | **47** |
| `ipad_9th_generation` landscape, viewport 1080×810 | 717 | 717 | **0** |

The offset is not the GUI inset (58 here), not a constant, and not a property of
the session. It follows the emulated configuration — presumably the letterboxing
of the emulated viewport inside the Studio game-view pane.

## Why this is dangerous rather than annoying

A click aimed with a remembered constant lands somewhere else, and **the
screenshot still looks correct** — this is the recorded Studio trap ("screenshots
can look aimed correctly even when routed input landed elsewhere") with a
specific mechanism attached. In the run that found it, a click aimed at a visible
button landed 47px above it, `GetGuiObjectsAtPosition` confirmed it had hit the
scroll region instead, and the control simply did not activate. Read carelessly,
that is a framework bug report.

Worse, it can make an *intentional-failure* proof pass for the wrong reason: a
suppressed-effect test and a missed click produce the same "nothing happened".

## What to do

1. **Calibrate per row, not per session.** Inject once anywhere, read the raw
   event's reported position, and add the delta to subsequent aim points. The
   `perf_capture` scenario exposes this as a `calibrateInput` step; the driver
   never guesses the offset.
2. **Check `gameProcessed`.** A click that lands on no GUI element is not
   consumed by the GUI, so `gameProcessed == false` on the raw event is a free
   second opinion that the aim was wrong.
3. **Confirm with the effect, not the picture.** Pair the raw native event with
   the property write that changes what a player sees. "The press reached the
   engine and never reached the screen" and "the press missed" must not be the
   same observation.

## Not to be confused with a capability claim

While chasing this, the same session also published two claims that turned out to
be wrong for a different reason — a *boolean* capability probe that used invented
member names and reported the resulting throw as a security refusal. See
[`capability-probes-must-be-tri-state.md`](capability-probes-must-be-tri-state.md).
The offset above is a real measurement; those were not.

Related: [`injected-mouse-coords-are-gui-space.md`](injected-mouse-coords-are-gui-space.md)
(the coordinate SPACE), [`device-emulator-truths.md`](device-emulator-truths.md)
(what the emulator does and does not model), and
[`studio-viewport-1x1-instrument-trap.md`](studio-viewport-1x1-instrument-trap.md)
(a blind instrument reporting confidently).
