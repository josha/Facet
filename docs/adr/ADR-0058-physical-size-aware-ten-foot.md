# ADR-0058 — Physical-size-aware ten-foot classing (`effectiveDisplaySize`)

**Date:** 2026-08-27
**Status:** Accepted
**Number:** 0058. Additive — no ADR-0040 row. No required-prop flip and no
documented-default VALUE change on any public constructor: this corrects an
internal derivation (what `distanceProfile`/`typographyScale`/`metricScale`/
`effectiveOverscanInsets` compute from), not a documented required-prop
default. The one in-code claim it does supersede — `environment.luau`'s own
comment, "ten-foot presentation keys off the display class, not the input
class... Large alone (any input) earns the distance treatment" — is corrected
in the same commit as a stale-comment fix (ENGINEERING.md: a stale comment is
a bug), not treated as a public contract.
**Home:** `src/layout/adaptive.luau` (`adaptive.effectiveDisplaySize`,
`adaptive.conditions`), `src/env/environment.luau` (`derived.effectiveDisplaySize`
and its seven consumers), `src/client/host.luau`, `src/client/theme_controller.luau`.
**Guards:** `tests/adaptive.spec.luau` (the pure function), `tests/paradigm_tenfoot.spec.luau`
(the env-level integration + regression pins), `tests/ten_foot_metrics.spec.luau`
(one source-text pin updated to match the intentional `host.luau` change).

## Context

Director's goal-prompt item 5, verbatim: "Handheld (ROG Ally): fonts default
too small — likely classed as console/ten-foot by input, not by SCREEN SIZE.
Size classes must consider physical screen size. Fix."

### Measuring the current classing chain (item 5.1), platform-native first

**`displaySize` comes from exactly one engine signal:** `roblox_env.luau`
reads `GuiService.ViewportDisplaySize` (an `Enum.DisplaySize`, pcall-guarded —
shipped 2025-10) and publishes it verbatim as the `displaySize` env fact.
Nothing else feeds it. Three derivations read it (pre-existing, before this
round): `distanceProfile` (`"ten-foot"` iff `"Large"`), the `sizeClass`/
`heightClass` density cap (`wide`/`tall` clamp to `regular`/`medium` at
ten-foot), and the whole `themeMetrics`/`typographyScale`/`typographyPaintScale`
ladder (1.5x at `"Large"`, 1x otherwise — `snapshot.tenFootFloor`). **`Small`
and `Medium` are treated IDENTICALLY everywhere in this chain** — there is no
existing distinction between "phone" and "laptop" for TYPE/METRIC scale, only
"Large or not". This matters: the memory note "`displaySize` ≠ `sizeClass`
where Large means TV" names two genuinely independent axes — `sizeClass`
(`compact`/`regular`/`wide`) is a pure function of raw viewport WIDTH IN
PIXELS, unaware of physical size except for the SAME ten-foot density cap;
this round does not touch that axis (see "What this round does NOT change,
and why" below).

**What Roblox documents `DisplaySize` as**
([Enum reference](https://create.roblox.com/docs/reference/engine/enums/DisplaySize);
[`GuiService.ViewportDisplaySize`](https://create.roblox.com/docs/reference/engine/classes/GuiService);
[the shipping announcement](https://devforum.roblox.com/t/full-release-build-cross-platform-ui-with-the-viewportdisplaysize-api/3880384)):
`Small` = "most tablet/mobile/handheld devices", `Medium` = "most laptops and
monitors", `Large` = "most TVs or larger". A Roblox engineer's own reply in
that thread: *"We're detecting the physical size through vendor API. E.g. you
can get the inches from Android/Apple. Other platforms are more complicated,
but you can get a monitor size."* — mobile has a reliable vendor API; **every
other platform (Windows, Mac, Linux — i.e. every PC form factor, ROG Ally
included) is explicitly "more complicated"**, with no documented fallback
behavior stated anywhere reachable. The API's own ship note: *"This API should
not be used to make decisions about rendering quality"* — a caution the
director's own ten-foot type-scale use already runs against, pre-existing.

**`GuiService:IsTenFootInterface()` is DEPRECATED** (confirmed live against
the reflection database below) with no documented replacement rule and no
description of its own detection method distinct from `ViewportDisplaySize`'s.
It is not a usable independent corroborating signal (see "Rejected
alternative" below).

**`GuiService.ViewportSizeInMM`, `GetScreenResolution()`, `GetRawScreenScale()`,
`GetResolutionScale()`, `GetUIScaleMultiplier()` exist in the engine's
reflection database but are gated behind a capability ordinary game
LocalScripts do not hold** — confirmed live, directly, against a running
Roblox Studio session (`Facet-Showcase.rbxl`, Play mode, Client datamodel,
2026-08-27):

```
ViewportDisplaySize: ok=true val=Enum.DisplaySize.Large
ViewportSizeInMM: ok=false val=The current thread cannot read 'ViewportSizeInMM' (lacking capability RobloxScript)
IsTenFootInterface(): ok=true val=true
GetScreenResolution(): ok=false val=The current thread cannot call 'GetScreenResolution' (lacking capability RobloxScript)
GetRawScreenScale(): ok=false val=The current thread cannot call 'GetRawScreenScale' (lacking capability RobloxScript)
GetResolutionScale(): ok=false val=The current thread cannot call 'GetResolutionScale' (lacking capability RobloxScript)
GetUIScaleMultiplier(): ok=false val=The current thread cannot call 'GetUIScaleMultiplier' (lacking capability RobloxScript)
UIS.TouchEnabled: ok=true val=false
UIS.GamepadEnabled: ok=true val=false
UIS.PreferredInput: ok=true val=Enum.PreferredInput.KeyboardAndMouse
camera.ViewportSize: 1920, 1078
```

**This is the load-bearing measurement.** The Studio session above is an
ordinary windowed Play-test on a desktop Mac — not a console, not a TV, not a
handheld — at a 1920x1078 viewport, and `ViewportDisplaySize` reports `Large`.
`IsTenFootInterface()` agrees (`true`), so it is not an independent signal
either — both apparently share, or independently mis-hit, the same
resolution-shaped heuristic on a non-mobile platform. **This reproduces the
director's exact defect class directly**: a device nobody would call a
television gets the console bucket, at the identical resolution class
(1920x1080-ish) the ROG Ally reports. True physical-size data
(`ViewportSizeInMM`, the `Get*Scale` methods) is confirmed **not derivable**
by Facet or any third-party script — settling item 5.1's "what is derivable /
what is not" question directly rather than by inference.

**Caveat, stated plainly:** this measurement is from Roblox Studio's Play
mode, not a packaged client on real hardware — Studio's own display-metadata
access may differ from a shipped game (device-owed, below). It is nonetheless
the strongest first-party evidence available without a physical ROG Ally, it
reproduces the identical resolution class the director's report describes,
and it directly corroborates the DevForum engineer's own "more complicated on
other platforms" caveat rather than contradicting it.

## Decision

### The signal chain: `effectiveDisplaySize`

`adaptive.effectiveDisplaySize(displaySize, touchCapable)` — a pure function
in `src/layout/adaptive.luau` (the module already responsible for every other
adaptive derivation, per its own header: "PURE decisions... usable by the
solver and by tooling with no DataModel and no reactive core"):

```lua
function adaptive.effectiveDisplaySize(displaySize, touchCapable)
	if displaySize == "Large" and touchCapable == true then
		return "Medium"
	end
	return displaySize
end
```

**Touch is the corroborating signal**, chosen over every alternative
considered:

- It is **already derivable** — `UserInputService.TouchEnabled`, already
  flowing into `capabilities.touch`, no new engine call, no new capability
  requirement (unlike `ViewportSizeInMM`, confirmed inaccessible above).
- It is **physically meaningful in exactly the way `displaySize` is not**: a
  real ten-foot session — a console plugged into a TV, played from a couch —
  has no touchscreen; a PC handheld small enough to misreport `"Large"` has
  one on every shipping example (the director's own ROG Ally scenario states
  it explicitly: "touch enabled").
- **Gamepad presence is deliberately NOT the signal** — the director's own
  suspicion ("classed by input") is directly measured false in this round:
  `environment.luau`'s `distanceProfile` never read the input class at all,
  before or after this fix (`tests/paradigm_tenfoot.spec.luau`'s "gamepad
  input alone never changes the classing" case pins this). A real console
  and a PC handheld both report gamepad-primary; only touch tells them apart.

**The correction target is `"Medium"`, not `"Small"` — a deliberately
MINIMAL correction.** The only thing this round changes is "does this earn
ten-foot/console TREATMENT" (type scale, metric scale, the sizeClass density
cap, overscan margins). `"Medium"` is the smallest step that answers that
question (`typographyScale`/`metricScale`/`distanceProfile`/
`effectiveOverscanInsets` only ever branch on `"Large"` vs. everything else,
so `"Medium"` and `"Small"` are equivalent for all of them). Landing on
`"Small"` instead would be a STRONGER, separate claim — "this is definitely a
phone-class device" — that a touch signal alone does not fully justify (a
touch-capable desktop monitor or kiosk exists too), and it would additionally
change `adaptive.navPlacement`'s gamepad branch (`"Medium"`/`"Large"` →
`topBar`, `"Small"` → `bottomBar`) — a phone-vs-tablet nav-placement product
decision this round does not make (see "What this round does NOT change").

### Every ten-foot-TREATMENT consumer migrated to the corrected fact

`derived.effectiveDisplaySize` (`environment.luau`) is the ONE seam:

```lua
derived.effectiveDisplaySize = core:memo(function(use)
	local caps = use(signals.capabilities)
	local touch = type(caps) == "table" and caps.touch == true
	return adaptive.effectiveDisplaySize(use(signals.displaySize), touch)
end)
```

Seven pre-existing internal reads of raw `signals.displaySize` in
`environment.luau` migrated to `use(derived.effectiveDisplaySize)`:
`typographyScale`, `typographyPaintScale`, `themeMetrics`'s `forDisplay` call,
`sizeClass`'s inline ten-foot cap, `distanceProfile` itself,
`effectiveOverscanInsets`, `platformChrome`'s overscan-compose check. Three
external call sites also migrated, because they are the LIVE client's actual
paint decision, not a diagnostic: `adaptive.conditions`'s `displaySize` local
(feeds `navPlacement`), `client/host.luau`'s `engineAdapter` (the paint-family
ten-foot scale, ADR-0040 B-17), `client/theme_controller.luau`'s
`displaySizeFact()`/`factsForResolve()` live-environment fallback (theme
package paint resolution).

**Deliberately left reading the raw fact** (with the reasoning recorded at
each site): `client/edit_preview.luau` (an explicit developer preview of a
CHOSEN `device_profiles` display class — overriding a deliberate author
choice with an uncorroborated "maybe touch is lying" guess would defeat the
tool's purpose), `preview/matrix_rows.luau` (verifies the device-matrix
harness's SIMULATED device reports what the row asked it to — a setup
assertion, not a treatment decision), `render/renderer.luau`'s `GEOMETRY_KEYS`
re-solve watch list (transitively covered: `typographyScale`/`themeMetrics`,
already watched, both depend on `effectiveDisplaySize` and re-fire whenever
it would), `themes/snapshot.luau` itself (the pure ladder functions correctly
stay generic over whatever displaySize-shaped string they are handed —
correcting the ARGUMENT, not the function, is the right seam), and
`tokens/sheet_model.luau` / `client/screen_target.luau` /
`client/billboard_target.luau` (pure parameter pass-through; corrected
upstream at the one place each receives its value from).

`src/render/renderer.luau` and `src/client/screen_target.luau` were not
opened beyond confirming this by reading (both are inside the
`docs/handoff/SOURCE_CAP_LEDGER.md` band); no extraction was owed because
neither needed an edit.

### Rejected alternative: `IsTenFootInterface()` as the corroborating signal

Considered and measured, not merely assumed unusable: the live Studio probe
above shows `IsTenFootInterface()` returning `true` on the SAME ordinary
desktop session where `ViewportDisplaySize` reads `Large` — the two agree
(or independently share the same false positive) rather than disagreeing, so
it adds no independent information here, on top of already being deprecated
with no documented replacement contract. Not used.

### Rejected alternative: gate on `effectiveInput`/`preferredInput` instead of the delivering signal

Unlike ADR-0057's gamepad classification (which needed "which BINDING
delivered this specific value"), this decision is at the environment level
and `capabilities.touch` is already the primitive `interactionClasses`/
`effectiveInput` are themselves built from — reading `capabilities.touch`
directly is one hop shorter than reading `effectiveInput` and re-deriving
touch from it, and avoids coupling a ten-foot decision to the INPUT-PREFERENCE
resolution policy (which answers "what does the player prefer to use", a
different question from "does this hardware have a touchscreen").

### Safe default when signals conflict, and no regression

The director's own requirement, met directly: "a 7-inch 1080p handheld with a
gamepad must NOT get ten-foot/console type scaling" — a ROG-Ally-shaped
environment (1920x1080, gamepad-preferred, touch-capable, and the worst case
this round's research could not rule out, an engine-reported `"Large"`) now
resolves `effectiveDisplaySize = "Medium"`, `distanceProfile = "near"`,
`typographyScale = 1`, `themeMetrics.metricScale = 1`,
`effectiveOverscanInsets = {0,0,0,0}` — measured directly in
`tests/paradigm_tenfoot.spec.luau`. **No regression on a real console**: the
identical viewport and gamepad WITHOUT a touchscreen (a PS5-shaped
environment) is byte-identical to before this round —
`effectiveDisplaySize = "Large"`, `distanceProfile = "ten-foot"`,
`typographyScale = 1.5`, the 60/90 overscan margins, the `sizeClass` density
cap — same test file, pinned as a regression guard. **When physical size is
genuinely unknowable** (no touch signal either way — the vast majority of
existing fixtures, including the entire 1808-line `tests/ten_foot_metrics.spec.luau`
ladder, none of which sets `capabilities.touch`), the correction never fires
and current behavior stands exactly as documented in that file's own
characterization tests — verified by running the full file unmodified against
this change (see "Suite tails" in the task report).

## What this round does NOT change, and why

- **`sizeClass` (`compact`/`regular`/`wide`) is unchanged for the Ally
  scenario** — it still reads `"wide"` at 1920px width, exactly as it did
  before, because `sizeClass`'s WIDTH-only breakpoint is a genuinely separate
  axis from the ten-foot cap this round corrects (the memory note's own
  "displaySize ≠ sizeClass" distinction). A high-resolution small-physical
  screen choosing a desktop-density LAYOUT (grid columns, sidebar-vs-bottom
  nav via the WIDTH breakpoint alone) is a real, plausible, SEPARATE
  contributor to "things look small on a handheld" that this round's platform
  research surfaced but the director's item 5 does not name and this ADR does
  not resolve — recorded here as a candidate follow-up, not fixed.
- **`adaptive.navPlacement`'s gamepad branch outcome is unchanged** for the
  concrete Ally scenario: `"Medium"` (the corrected value) and `"Large"` (the
  uncorrected one) both resolve to `topBar` in its existing rule, so this
  round's correction does not cross the boundary that would flip it to
  `bottomBar` (the near-distance handheld treatment the branch's own comment
  names for `"Small"`). Audited in `tests/paradigm_tenfoot.spec.luau`
  ("navPlacement's gamepad branch is unchanged by this fix") rather than
  silently left untested. Whether a `"Large"`-reporting, touch-capable,
  gamepad-primary device should ALSO get phone-style bottom tabs is a
  separate, more specific product question this round does not decide.

## Device-owed

Studio cannot BE a PC handheld and its own display-metadata access may not
match a packaged client (standing rider, binding context). Owed on real
hardware:

1. **A ROG-Ally-class device** (or the closest available PC handheld):
   confirm what `GuiService.ViewportDisplaySize` and `UserInputService.TouchEnabled`
   actually report live, and confirm the shipped app's type scale/overscan
   feel handheld-appropriate rather than console-inflated.
2. **A PS5 (or Xbox) on a real TV**: confirm ten-foot treatment is
   unchanged — type scale, overscan margins, and focus-ring strengthening all
   present exactly as before this round.
3. **A touch-capable desktop/monitor or kiosk**, if one is available: confirm
   the conservative direction chosen (keep normal type rather than force
   ten-foot) reads as intended rather than as a regression for that class of
   device — the one case this design deliberately trades away precision for
   safety.
