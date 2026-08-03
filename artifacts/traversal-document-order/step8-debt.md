# Step 8 debt cleared in this stage (ledger row TD-16)

The handoff listed five open items from `desktop-keyboard-navigation`, and
re-running that stage's gate at its own **unmodified** source turned up two more.
This is what each one was and what was done.

---

## From the handoff

### 1. `PresenterOpts.keyboardNavigation` — undocumented → **documented**

`docs/reference/api.md` § `newPresenter`. The opt existed and was load-bearing
(it is why Space stopped stealing the avatar's jump) but no reference entry said
so, including that it **defaults to `false`** and that the bindings additionally
require live keyboard capability and an engaged responder.

### 2. `PresentOpts.keyboardNavigation` — undocumented → **documented**

Same file, in the `present()` options list and as its own paragraph: the
per-surface override of the presenter default.

### 3. `Grip.focusVisual` — **already documented; the handoff was stale**

`docs/reference/api.md` line ~1050 documents it in full, including the
construction-only rule and why a Slider's track opts out. No change was needed and
none was invented. Recorded here because "the handoff said it was missing" is
otherwise the kind of claim a later reader re-derives from scratch.

### 4. The false gameplay-band number — **corrected in both places**

`docs/guide/07-input.md` and `docs/adr/ADR-0014-first-responder.md` described the
default PlayerScripts contexts as sitting at a "historical default 1000", which
invited the reading that the avatar occupies the 2000 band.

Measured on the shipped `PlayerModule`: **Camera 100, Character 150, Vehicle 200,
Transformer 300**. The 2000 figure is Roblox's *recommendation for a game's own
sink*, not where the avatar sits.

No behavior depends on this — LuauUI is at 1500 (plain) and 3000 (engaged), which
clear all four either way — so this is a documentation correction, and both places
now say so explicitly rather than silently swapping one number for another.

### 5. The unverified post-sink key drive — **still open, carried as TD-13**

Step 8 could not complete an end-to-end key drive after `keyboardNavigation` made
surfaces sink: three consecutive `execute_luau` timeouts on any call routed
through the driver's `keyboard` mode. This stage retries it in a fresh session as
ledger row TD-13. It is **not** claimed closed by this document.

---

## Found by re-running the Step 8 gate before touching anything

`tools/gate.sh desktop-keyboard-navigation` at the pre-change source returned
`FAIL_RECOVERABLE`, not the `exit 0` the stage is recorded as achieving. Neither
failure was caused by this stage. Full write-up in `decisions.md` TDN-5.

### 6. `adjust-claim-is-subtree-scoped` grepped a **renamed test** → **fixed**

| | |
|---|---|
| Check greps | `a sibling button.s arrows reach the game instead of firing a dead Adjust` |
| Test is named | `a sibling button's arrows fire no dead Adjust` (`tests/keyboard_navigation.spec.luau:616`) |

The test exists and passes. The grep matched nothing, so the check failed —
silently carrying one of the stage's headline claims. The grep now matches the
real name, and this stage's gate carries a negative grep so the stale string
cannot come back.

### 7. `library-suite-green` pinned **3070** against a **3079** finish → **fixed**

The note beside the check states the intent exactly — *"the floor lands as the
FINAL number so a regression of this stage's own pins fails the gate"* — and the
number did not. Nine of Step 8's own tests sat outside its floor. Re-pinned to
**3079**, its true final count, with the correction recorded in the check's note.

### 8. `rascalrally-consumer` ran a game test asserting a **pre-Step-8 world**

This one is a real consumer-lockstep miss, not a stale string, and is fixed in
`consumer-impact.md` rather than here.

`games/RascalRally/code/tests/luauui_closed_key_contract.spec.luau:134` proves its
own mutation by asserting that a surface presented **without** `gameplayGuard`
*does* claim `Space` for Activate. Step 8 made the Space binding conditional on
`keyboardNavigation`, which defaults to **false**, and the game's `presenterWorld()`
helper builds `newPresenter` with no opts — so no Space binding can exist and the
mutation-proof half cannot pass, whatever the guard does.

The assertion was correct when written and describes a world Step 8 deliberately
replaced. The Step 8 rule that should have caught it is the execution contract's
own: *"A LuauUI gate cannot pass while its Rascal Rally consumer is stale, failing,
or unaudited."*
