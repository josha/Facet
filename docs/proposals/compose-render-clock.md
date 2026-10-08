# Compose render clock option

## Task and API

A client can apply a native UI transform before paint. Give the Roblox
runtime an optional motion clock selection: Heartbeat by default, or
PreRender for visual motion. Keep tween, ramp and timeline APIs unchanged.
Use one runtime clock. Keep cancellation and owner cleanup unchanged.
Do not connect each control to a second animation scheduler.

## Measurement

The Verify case `measures the render sample before and after the Compose
clock step` in `tests/zoom_travel.spec.luau` controls the two event signals.
It requests scale 2 from scale 1. At PreRender N, before any Heartbeat step,
the scale is still 1. It then advances Heartbeat by 1/60 second. At PreRender
N+1 the scale is greater than 1. This is one rendered sample of difference,
or 16.67 ms at 60 Hz. An interrupt keeps the current scale, then later samples decrease
monotonically to the new target 0.8.
This is a headless event-order measurement. It is not a phone timing capture.
A Studio capture must record the real event order and paint samples.

## Boundary

Time-based zoom and travel use the current Compose clock in this pull request.
Pointer contact uses no clock. Facet applies pinch scale and focus position
inside TouchPinch, and mouse pan inside UIDragDetector.DragContinue.
The input case checks each property before a clock step. Native touch pan
remains ScrollingFrame policy. Do not change the generated Compose snapshot.
The lead will take this proposal upstream.

## Proof for the option

Compare both clocks with the same target, duration and easing. Record
PreRender samples and clock samples. Check monotonic motion, interruption
from the current value, reduced motion, owner cleanup and one subscription
per runtime. A server or headless runtime must keep a supported default.
