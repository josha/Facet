# Transient UI outlives nothing — sustain the state before capturing it

**Date:** 2026-07-28 (sponsor-framework-gaps close)

## What happened

Every screenshot of the live toast fixture showed an empty strip while every
numeric probe (geometry, opacity, order, visibility, clock ticks) was green.
Hours went into paint-defect hypotheses (CanvasGroup-under-emulator rasterization
was the leading one, eventually REFUTED by a minimal probe: a Frame inside a
CanvasGroup renders fine under the device emulator).

The truth: a toast lives ~4 s and `presentToast`'s layer **disposes its whole
ScreenGui when the schedule drains**. The MCP `screen_capture` round-trip is
slower than that. Every capture postdated the layer's destruction. A probe Frame
planted inside the live layer "failed to render" for the same reason — it was
destroyed with the layer before the shot landed.

The near-miss on top: the ONE good frame was overwritten by a "crisper" retry
that waited 2 s — long enough for the burst to drain. The burst step floods 8
toasts through 3 lanes at the 1.5 s dwell floor; the whole show is over in ~4 s.

## The rules

1. **Before debugging "X doesn't render", prove X still EXISTS at capture time.**
   One `FindFirstChild` after the capture returns beats an afternoon of paint
   forensics. Self-retiring surfaces (toasts, transient layers, retire-model
   exits) destroy their own evidence.
2. **Sustain the state, then shoot.** Drive a loop that re-presents the
   transient state for tens of seconds (`task.spawn` + re-invoke every ~1–2 s),
   or shoot with the fast local window capture (`capture_viewport.sh`)
   immediately after the drive call — never after a "let it settle" sleep whose
   length you haven't checked against the state's lifetime.
3. **A probe planted inside a self-disposing container inherits its lifetime.**
   Park diagnostic markers in their own ScreenGui, not in the subject's.
4. Mid-fade rows in the final shot are honest churn evidence; settle-state
   opacity belongs to the headless pins, not the screenshot.

## Where it bit

`artifacts/sponsor-framework-gaps/captures/sf_toast_stack.png` — see the
manifest note. The genuinely real defect nearby (toast body painting zero-width
from a hug HStack of fill children) was found and pinned separately; the capture
race then masqueraded as its "fix not working".
