# A helper declared below its caller is a global, and the call is swallowed

**2026-08-15**, building `newVirtualGrid { axis = "x" }`.

The control grew an "axis seam": four small helpers that are the only place the
axis becomes a coordinate (`mainOf`, `vec`, `widthOf`, `heightOf`). They were
written where they are first *needed for the blueprint* — about eighty lines below
`scrollTo`, which is where the first `vec(...)` call actually is.

Luau resolves a name at compile time against the locals **in scope at that point**.
`vec` is declared after `scrollTo`'s body, so inside that body `vec` is not the
local at all — it is a global lookup, and the global is `nil`. `vec(...)` is
therefore "attempt to call a nil value", every time, at runtime.

## Why it did not look like an error

The call site is inside `navigateIntercept`, which the input system invokes through
a protected call. The error was caught, the intercept simply returned false, and
the symptom was: **the keyboard ring stops after four steps.** No stack trace, no
console line, nothing in the suite except one spec expecting index 37 and getting
17.

`--!strict` does not catch it either. A global read is legal Luau.

## How it was actually found

Not by reading the code — the code reads fine, and the first three hypotheses
(scroll clamping, a stale window memo, the fake adapter's `clampScroll`) were all
plausible and all wrong. It was found by printing, in order:

1. inside the intercept — the target line and the computed scroll offset: **right**;
2. inside `scrollTo` — the controller, the path, `maxTop()`: **right**;
3. inside `renderer.controller.scrollTo` — **never printed.**

The gap between 2 and 3 is one expression, and that expression was the call that
was never made. Three probes, four minutes, versus an hour of theory. This is
`ENGINEERING.md`'s "measure the root cause, never guess at it" in miniature: the
instrument that ends the hunt is usually the one that asks "did this line run?"

## The rule

**Declare a helper above every caller, not above its first *interesting* caller.**
When a group of helpers exists precisely so that "one question is answered once"
— an axis seam, a unit conversion, a sign table — put the whole group at the point
the question is *decided* (here: immediately after `local isX = axis == "x"`), not
at the point the answer is first drawn.

And when a call through a protected boundary silently does nothing, suspect the
callee is `nil` before you suspect the callee is wrong.
