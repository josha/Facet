# ADR-0033 — Time-based easing: the engine owns the curve, the clock owns the time

**Date:** 2026-08-15
**Status:** Accepted
**Amends:** ADR-0022 (motion authority) — adds a third driver behind the shared `MotionValue` handle and a second named registry beside `motion.registerClass`
**Commissioned by:** the director, closing the framework-comparison survey's **G-1** (ranked BUILD NOW, the only row in its §4 where a developer moving to Facet lost a capability outright). That survey was removed from this repository on 2026-08-30 and is archived privately at `Facet-private-archive/docs/reference/fusion-comparison.md`
**Companions:** `docs/research/2026-08-15-roblox-easing-engine-facts.md`, `artifacts/time-based-easing/`

## Context

Facet's motion vocabulary was springs, `timeline`, `chase`, `counter`, `timer`
and `glide`. `Enum.EasingStyle`, `TweenInfo` and the word `easing` appeared
nowhere in `src/`.

The gap is not "no duration" — `clock:timer` and `clock:glide` both take one. The
gap is that **both are strictly linear**, so the shape between the endpoints was
not authorable, and a spring cannot substitute because it approaches its target
asymptotically: `response` is a feel dial and settle time is emergent, so "over
exactly 400 ms, quad ease-out" is not expressible and a cooldown cannot be
commanded to arrive on the beat.

~~The consumer proof was already in the repo. RascalRally's
`src/shared/CommitBeatModel.luau` ramps on `p^1.6` ... the Facet port had to
flatten it to a linear `clock:timer`.~~

**WITHDRAWN 2026-08-15, by the consumer rider this ADR commissioned.** The claim
does not survive contact with the code, and it was the strongest argument in this
section, so it is struck rather than quietly softened:

* `TELL_RAMP_POWER = 1.6` shapes a blink **frequency** ramp
  (`f(p) = SLOW + (FAST-SLOW)*p^1.6`, integrated closed-form), not a value over
  time. **No curve primitive can express it** — an easing curve is
  value-at-time.
* Its only callers are the **legacy** modules. The Facet port never calls
  `tellLit`/`tellPhaseCycles` at all.
* The blink was removed by a **director ruling** (amendment A24, 2026-07-31 — "the
  wind-up TELL is a PLATE ramp"), not lost to a missing primitive.
* Legacy's own visible swell is **linear** in progress, and so is the port's
  `TableMetrics.tellWash`. So `StoryFlow.luau:586`'s linear `clock:timer` is a
  faithful match, not a flattening.

**No shipped consumer had a curve taken away from it.** The primitive stands on
what it makes possible — a duration that arrives on time, which no spring can
promise — and that argument was always sufficient. Reaching for a regression that
turned out not to exist made the case weaker, not stronger, and the correction is
here so the next reader does not cite it.

## The question the director settled

The original brief asked which was honest: the engine's own tweening, or a
Lua-side curve on the existing clock. Mid-mission the director ruled: **"let's
make sure tweening uses Roblox's animation system wherever possible."** That
flipped the burden of proof — the decision below is not *whether* to use the
engine but *where the engine can actually serve*, and every boundary is measured
rather than asserted (all numbers live, Studio, 2026-08-15; method and A/A
controls in `docs/research/2026-08-15-roblox-easing-engine-facts.md`).

Roblox's animation system is two separable things, and they answer differently.

### Decision 1 — `TweenService:GetValue` **is** the evaluator

`TweenService:GetValue(alpha, style, direction)` is a **pure** function: a number
in, a number out, touching no `Instance`. That is the property that lets it drive
a value Facet owns, and it is exactly the piece "time-based easing" means. It is
therefore the production evaluator, installed onto the clock by
`motion_driver.bind`, so a client that binds gets the engine's own easing with no
wiring of its own. `Enum.EasingStyle` defines the vocabulary; a style Roblox adds
later is a line of data, not an implementation.

**AMENDED 2026-08-15.** This decision originally claimed native was "the default,
not an opt-in a game forgets to wire". The consumer rider measured otherwise:
**RascalRally requires `motion_driver` nowhere** — all four of its Facet surfaces
hand-roll their own frame source (`FacetSponsor/init.luau:1029` on `PreRender`;
`FacetRacerListGui:72` and `GaragePilotGui:93` on `Heartbeat`). So on the one
shipped consumer, a curve evaluates on the **pure twin**, and the claim was true
of the binding rather than of the clients.

It is benign — the twin is pinned to the engine at max |err| 4.73e-7, so nothing
looks different — but it is exactly the gap to check first if a curve ever feels
wrong on device, and "the default" was a claim about a bind that this consumer
does not perform. Making native genuinely unconditional would mean installing the
evaluator where the clock is BUILT rather than where it is driven; that is a
change with its own tradeoff (the presenter is engine-free by contract) and is
deliberately not made here.

Cost, stated with its control first: A/A spread 3.8% across warm runs (the cold
first run was 37% and is excluded as warm-up). ABBA over 200,000 calls: **58.6 ns
per engine call against 9.2 ns for a pure Lua curve — 6.3x.** In frame terms that
is 3.5 µs at sixty concurrent tweens, 0.02% of a 16.7 ms budget.

**The engine is not cheaper here. It is correct, and correct is the reason to take
it.** Saying so explicitly matters: "native" was not allowed to stand in for
"faster" on this decision, and it would have been wrong if it had.

### Decision 2 — `TweenService:Create` cannot serve, and this is why

`Create` targets an `Instance`, so driving a `MotionValue` through it needs a proxy
instance per animated value. Four measured or structural facts close it:

1. **Cost.** A/A control spread 41.0% (small N, stated first). Arming 500 values:
   **6.1 µs each plus one `Instance` each**, against 0.031 µs for the ramp Facet
   already runs — ~196x — and a retarget is `Cancel` + `Create` + `Play`, i.e. a
   dead `Tween` object every time a `withAnimation` is interrupted.
2. **The headless suite could not cover the shipped path.** `clock:step(dt)` under
   a scripted clock is the entire reason the motion authority is testable
   (ADR-0022 Decision 1). A real `Tween` advances on the engine's wall clock and
   cannot be stepped, so the tween half of motion would ship untested and Lune
   would be testing a fallback the player never runs — the false-evidence class
   this codebase already has lessons about.
3. **Ordering and batching.** `Tween.Completed` fires on the engine's schedule,
   not in the clock's post phase, and a proxy's property change would land outside
   the one-transaction-per-frame commit that makes a dense motion frame cost one
   propagation instead of twenty.
4. **Reduced motion.** The engine will not consult `motionPolicy`. Under `Create`
   the policy would have to be honoured by *not building the tween*, a second code
   path beside the value layer's existing one.

Fidelity itself is not the objection and was checked rather than assumed: in a
real Play session an engine tween updates its property on **89–100% of frames**.
The Edit-mode reading of 24% was an **instrument artifact** — Edit throttles — and
is recorded as a trap, not as a finding.

### Decision 3 — a pure twin ships, pinned by a differential oracle

Lune has no `TweenService`, so `src/motion/curves.luau` carries a pure evaluator
and the clock takes it by injection exactly as it takes `now`. The twin is **not a
second opinion**: `artifacts/time-based-easing/engine-oracle.md` records a
differential oracle over **33,033 samples** (11 styles × 3 directions × 1,001
alphas) with **max |twin − engine| = 4.73e-7**, and a frozen subset of that corpus
travels with `tests/motion_tween.spec.luau` so drift reddens in the suite rather
than only in a session nobody re-runs.

The oracle earned its place immediately: the twin was first written with Penner's
elastic period of 0.3 and the oracle reddened `elastic` in all three directions at
max |err| 0.0248 while the other eight styles agreed to < 1e-4. Fitting against
the engine gave **p = 1/3.25 exactly**, which is not the textbook constant and
would never have been found by reading.

### Decision 4 — a curve is a NAME, and the registry ships empty

`motion.registerCurve(name, { duration, style, direction? })`, one-for-one with
`motion.registerClass`. An inline spec table at a call site is refused exactly as
an inline spring literal is, for the same reason: a library gets forty slightly
different feels one call site at a time.

The registry ships **empty**, which is the one place this deviates from the class
precedent's four built-ins. There is no defensible built-in *duration*: 400 ms is
a decision about one specific surface, where a class's two physics numbers
generalize. Registering a curve is the act of choosing, once, with a name.

The five public members mirror the five class members one-for-one. Two sibling
registries that read differently would be a lookup at every call site; the
symmetry is the decision, not the default.

### Decision 5 — reduced motion is inherited, not re-decided

`clock:tween` goes through the same value layer as every other primitive, so it
inherits ADR-0022's policy unchanged, and the policy is unaffected by the engine
driving the curve (Facet still owns the time, so it still owns the branch).

- **Decorative (the default, as `clock:spring`)**: `setTarget` places the terminus
  instantly and fires the *same* settle event on the same frame.
- **Informational (`kind = "informational"`)**: keeps running to the same
  wall-clock terminus with writes quantized to the 250 ms tick. A cooldown sweep
  must declare this — **a frozen cooldown and a hung game look identical**, the
  same reasoning the indeterminate spinner already ships on.

This ADR also writes down, for the first time, the rule the authority was already
following: **the `kind` default follows what the value MEANS.** Only primitives
whose content is inherently elapsed time (`timer`) or a resampled stream (`glide`)
default to informational. A tween's meaning is the caller's, so it defaults
decorative like a spring.

### Decision 6 — `withAnimation` accepts a curve

`presenter.withAnimation` takes a registered **curve** name as well as a class
name. Decided rather than defaulted: the flight is one progress value from 1 to 0
read through `Readable<number>`, and a tween value is that same handle with a
different driver, so "over exactly 300 ms, quad ease-out" — the shape every design
handoff arrives in — needs no second mechanism.

The one real difference is the interruption carry. A spring hands its velocity to
the call that interrupts it; a curve has none to hand, so the session carries
`carriesVelocity = false` and that seam is skipped rather than raising inside an
armed commit. A curve-driven interruption still re-bases from the offset on
screen, so it redirects without a jump; only the speed kinks, which is what a
tween is.

Refusing curves here would have left the framework's headline animation verb
unable to speak the vocabulary the registry exists to hold — the asymmetry that
becomes a defect later.

## Consequences

- New public surface: `motion.registerCurve` / `resolveCurve` / `curveNames` /
  `isRegisteredCurve` / `resetCurves`, `clock:tween`, `clock:setEasing`. All in
  `docs/reference/api.md` and the surface ledger.
- `src/client/motion_driver.luau` now takes a second engine dependency
  (`TweenService`) and installs the evaluator at `bind`. It is guarded: a
  presenter stub without a clock degrades to the proven-equal twin rather than
  throwing at bind time.
- `src/motion/` remains engine-free and headlessly deterministic. The evaluator is
  injected, never imported.
- `docs/plans/roblox-native-primitives.md` §10.1 recommended "use `TweenService`
  for tween-shaped motion … while the *interpolation* runs at the edge". This ADR
  adopts the first half and refuses the second, with Decision 2's measurements as
  the reason: the interpolation at the edge is precisely what would have put the
  shipped path outside the suite.
