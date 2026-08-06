# Roblox-platform review — performance-stress-places (roadmap Step 9)

**Reviewer:** fresh-context Roblox-platform specialist
**Date:** 2026-08-04
**Verdict:** **FINDINGS** — 0 BLOCKER, 6 MAJOR, 9 MINOR. No fixes made.
**Scope:** the six platform claims named in the delegation, checked against
create.roblox.com / Roblox creator-docs source, the Roblox/libmp repo, and the
recorded artifacts + source in this repo.

Everything below is either "verified" (I checked it against a first-party source or
ran/read the evidence) or a finding. Claims that check out are stated explicitly.

---

## Area 1 — `debug.profilebegin` / `debug.profileend` and the `LuauUI/*` label set

### Verified

- **The mechanism is the supported one.** create.roblox.com's MicroProfiler page
  (source: `Roblox/creator-docs` `content/en-us/performance-optimization/microprofiler/index.md`,
  rendered at <https://create.roblox.com/docs/studio/microprofiler>, canonical URL
  <https://create.roblox.com/docs/performance-optimization/microprofiler>) says
  verbatim: *"Wrap code with `debug.profilebegin()` and `debug.profileend()` to time
  everything done between those function calls and create a label on the MicroProfiler
  timeline."* The API reference
  (<https://create.roblox.com/docs/reference/engine/libraries/debug>) carries both
  functions with signatures `debug.profilebegin(label: string): ()` and
  `debug.profileend(): ()`, **not deprecated**. `src/core/profile.luau` uses exactly
  this pair. **The claim is current and correct.**
- **"Automatic script scopes are not readable, manual ones are"** — the module comment
  attributes this to the LibMP skill's "Limitations". I could not fetch that skill file
  first-party this session, but the underlying platform fact is corroborated by the
  long-standing engine-bug thread *"New Lua VM doesn't support custom MicroProfiler
  labels or script names"*
  (<https://devforum.roblox.com/t/new-lua-vm-doesnt-support-custom-microprofiler-labels-or-script-names/491543>)
  and *"Microprofiler Labels Not Shown: `$UserToken_##`, `$Script`, `$namecall`"*
  (<https://devforum.roblox.com/t/microprofiler-labels-not-shown-usertoken-script-namecall-etc/56014>):
  under the Luau VM, per-script scopes collapse into anonymous `$Script`-class bars
  while explicit `profilebegin` labels are shown. **Directionally correct.** Marked
  MINOR-1 below only because the citation in the source comment points at a document
  that is not reachable from the repo.
- **The label naming is sound.** No first-party document restricts the label character
  set, imposes a length limit, or requires a compile-time-constant string; I searched
  specifically for a constant-string restriction and found none in creator-docs or on
  DevForum. `/` has no documented special meaning to the MicroProfiler. The prefix
  choice is *good practice* and is confirmed empirically by the artifact: LibMP
  `FindTimerIds("LuauUI/*")` returned exactly the eight declared timers and nothing
  else (`studio/perf-lab.json:microprofilerScopes`). **Sound.**
- **Cardinality bound is real, not aspirational.** `span` refuses any key outside
  `SCOPES` (`src/core/profile.luau:178-187`), `MAX_SCOPES = 12`, and the artifact shows
  no `LuauUI/*` timer outside the set in a live capture. **Verified.**
- **Balance accounting.** `opens == closes`, `depth == 0`, `maxDepth = 3` live
  (2 409/2 409). **Verified as recorded.**

### Findings

**MAJOR-1 — `span` does not survive a yield, and the lab's own `LuauUI/scenario` spans
yield ~60 times each.** Confidence: high (code), medium (engine consequence).
*Where:* `src/core/profile.luau:177-208`; `examples/performance/lab/perf_lab.luau:456`
(`profile.span("scenario", body)`) wrapping `passes.scrollSteady`
(`perf_lab.luau:535-577`), whose body calls `telemetry.step()` — a Heartbeat wait —
once per frame for 60 frames, **inside the open scope**.
*Why it matters:* the module's rule 2 guards early return and error, which are the
synchronous exit paths. It does **not** guard *yields*. `debug.profilebegin` opens a
scope on the executing thread; a Luau yield inside it leaves the scope open across a
frame boundary and hands the engine a scope stack whose enter and leave are in
different frames. The counters cannot see this — they count Lua call sites, so
`balanced = true` is reported for a capture whose engine-side stack is not what the
module claims.
*Evidence it is already distorting the artifact:* `studio/perf-lab.json` →
`attributionBeforeFix` records `LuauUI/scenario` with `n = 66` and `meanMs = 0.275`
for a pass of 60 frames at 16.65ms/frame. If the scope had genuinely stayed open across
the pass, its total would be ~1 000ms, not 18.2ms; if it were genuinely one Lua call,
`n` would be ~1, not 66. So either the engine is splitting the scope per frame or the
`n` column is not a call count — and the artifact interprets it as one.
*Requirement violated:* plan §"MicroProfiler observability" — "Balance scopes on every
exit/error path and cover the wrapper with tests"; PL-8.
*Smallest corrective test:* a Studio case that opens a `span` whose body calls
`RunService.Heartbeat:Wait()` twice, and then asserts the LibMP log for that timer id
contains exactly one enter (or documents what it actually contains). Then either
document "span bodies must not yield" and assert it (`coroutine.status`/`running`
identity check before and after the body), or split the scenario driver so the frame
wait is outside the scope.

**MAJOR-2 — profiling is ON by default in shipped code, and the `pcall` inside `span`
truncates the traceback of every error raised inside a LuauUI phase on the engine.**
Confidence: high.
*Where:* `src/core/profile.luau:78` (`local enabled = true`), `:200` (`pcall(fn)`),
`:204-206` (`error(result, 0)`).
*Why it matters:* on Roblox `hasEngine` is true, so `active` is true for every consumer
including Rascal Rally. Every `mount`, `commit`, `measure`, `arrange`, `react`,
`mutate` and `resource` body now runs under a `pcall` and re-raises at level 0. An
error thrown inside a solve therefore reaches the developer console **without the
stack below the pcall boundary** — a real, user-visible debuggability regression
relative to the same source with profiling off (and relative to Lune, where `active`
is false and the un-instrumented path is taken, so the suite can never see it). It also
means the framework pays a closure allocation + `pcall` + two C calls per phase per
frame in production, permanently, for an instrument almost no session is reading.
`xpcall(fn, debug.traceback)` would preserve the trace; better still, default `enabled`
to false and have the lab turn it on.
*Requirement violated:* the plan's optimization loop rule ("never weaken behavior");
UI-PERF-001. Also touches PL-19 (this ships into Rascal Rally).
*Smallest corrective test:* in Studio (or with `profile.setHooks` installed so `active`
is true), raise an error from inside a `span` body and assert the propagated error's
traceback still names the raising function.

**MINOR-1 — the per-scope cost is asserted, never measured.** Confidence: high.
The module's rule 3 ("free when absent") is only about the *absent* case. Nobody has
measured the *present* case. I found no first-party statement of the cost of
`debug.profilebegin` when no capture is running; the only DevForum thread that asks
(<https://devforum.roblox.com/t/performance-overhead-of-microprofiler-labels-with-debugprofilebeginend/2074492>)
is unanswered by staff. Given MAJOR-2 (on by default), the cost is worth naming:
a scene run with `profile.setEnabled(false)` vs `true` through `tools/perf.sh` would
produce the number in minutes and belongs in `optimization-log.md`.

**MINOR-2 — the comment's claim about an unbalanced scope is stronger than any
first-party source supports.** Confidence: medium.
`src/core/profile.luau:20-23` states that an unbalanced `profilebegin` leaves the
engine's scope stack open and "every subsequent frame in the capture is misattributed".
No Roblox document says this; the MicroProfiler page says nothing about balancing at
all. The *practice* (always balance) is right; the *stated consequence* is an
unverified engine-internals claim being used to justify an API shape. Either measure it
(open one unbalanced scope in Studio, capture, and report what the next frames look
like) or soften the wording.

---

## Area 2 — LibMP usage and the mobile procedure

### Verified

- `require("@rbx/LibMP")` — the Roblox/libmp README shows the require form
  `require("@game/ReplicatedStorage/LibMP")` for the copied-module case; the `@rbx/`
  built-in alias is the Studio-provided form and it demonstrably resolved in this
  session's capture (`backendReady: true`, `libraryVersion: 65536`). **Works as used.**
- `Control:SetFrameLimit(256)` — README: *"with a maximum of 256 frames. Lower values
  produce smaller snapshots."* The stage's use of 256 is the documented ceiling.
  **Correct.**
- `EnableProfiler(true)`, `EnableCapture(true)`, `CaptureToBufferSync()`,
  `Session.OpenFromBuffer(buf)`, `FindTimerIds(mask, caseSensitive)`,
  `CreateLogIterator` with `ThreadIds` / `TimerIds` / frame-range configuration — all
  present in the README with the semantics the stage used (source:
  <https://github.com/Roblox/libmp>). **Correct.**
- `FetchGlobalDesc().TickToMsCpu` is **not** in the README section I could fetch. It
  evidently exists (the artifact's ms figures are derived through it), but it is
  undocumented in the material I could reach — see MINOR-3.

### Findings

**(a) `LogIterator:Configure({ TimerIds = ids })` yielding zero exits — my verdict:
NOT a LibMP bug; it is inherent to the MicroProfiler log format, and it IS worth an
upstream documentation request.** Confidence: medium-high.
*Reasoning:* in the MicroProfiler log encoding an ENTER record carries the timer token
and a timestamp; a LEAVE record carries **only** a timestamp — the identity of what is
being left is recovered from the per-thread scope stack, not from the record. A filter
that selects records *by timer id* therefore cannot match any LEAVE record, because a
LEAVE record has no timer id to match. Zero exits is the arithmetically correct result
of the filter as specified, not a dropped event. The README's wording ("filter specific
threads, timers, or frame ranges") does not warn about this, and it is exactly the
trap a first-time user falls into.
*Consequence for this stage:* any duration computed from a `TimerIds`-configured
iterator is unsound, because you cannot pair enters with exits inside the filtered
stream. The stage's own workaround (unfiltered iterator + own stack) is the correct
usage and should be recorded as the rule, not as an incident. **MAJOR-3** if any
recorded number in `perf-lab.json` was derived from a filtered iterator — I could not
determine from the artifact which iterator produced `attributionBeforeFix`, and the
artifact does not say. *Smallest corrective step:* stamp the iterator configuration
into the capture row, and file the upstream doc issue against Roblox/libmp
("`TimerIds` filtering excludes leave records because leave records carry no timer id
— duration reconstruction requires an unfiltered or thread-filtered iterator").

**(b) ~60 frames captured at a 256-frame limit — expected, not a defect.**
Confidence: medium-high. `SetFrameLimit` sets a *maximum*; the retained window is
bounded by the profiler's fixed-size log buffer, and a heavy frame emits far more log
records than an idle one, so a heavy workload retains proportionally fewer frames.
This is the same property the creator-docs page states for dumps: *"Dumps only contain
data for the selected number of frames, not the entire duration that the game has been
running."* **MINOR-4:** the artifact records `framesCaptured: 65` against a 256 limit
without explaining it, which reads as a truncated capture. Record the cause, and — more
importantly — record that a 60-frame window at 16.65ms is a **1-second** sample, which
is a thin basis for the p50/p95 the stage reports. Repeat count, not frame limit, is
the lever.

**MINOR-3 — `FetchGlobalDesc().TickToMsCpu` is used as the tick→ms conversion with no
recorded provenance.** Confidence: medium. Every millisecond figure in
`perf-lab.json:attributionBeforeFix` depends on it, and the API is not in the README
material reachable from the repo. Record the LibMP version (`libraryVersion: 65536`,
`dataFormatVersion: 65536` are captured — good) *and* a one-line sanity check: the sum
of top-level scope times in a frame must not exceed the frame's own duration.

### The mobile-MicroProfiler procedure in `docs/guide/12-performance-lab.md` §12.5 — **WRONG in three places**

Checked against
<https://create.roblox.com/docs/performance-optimization/microprofiler> (verbatim
quotes below from `Roblox/creator-docs`
`content/en-us/performance-optimization/microprofiler/index.md`).

**MAJOR-4 — §12.5 step 3 invents a developer-console MicroProfiler tab, and omits the
actual retrieval mechanism.** Confidence: high.
Guide text: *"Open the mobile MicroProfiler: tap the Roblox menu, then Settings, and
toggle MicroProfiler (on some client versions this lives behind the developer console
— type `/console` in chat and use the MicroProfiler tab). The on-screen timeline
supports pause and a Dump action."*
First-party text: *"On the mobile client, open the **Settings** menu and change the
MicroProfiler to **On**. Then from a development machine on the same network, use your
web browser to navigate to the provided IP address and port."*
Three errors: (i) there is no MicroProfiler tab in the developer console — a user
following that fallback will not find it and will conclude the client version is wrong;
(ii) the mobile flow is **not** an on-screen timeline you dump from — the phone serves
a web UI and you drive it from a second machine on the same network, which is a
prerequisite the guide never states (same Wi-Fi, port reachable); (iii) the guide never
mentions the IP:port the client prints, which is the single thing the operator needs.

**MAJOR-5 — §12.5 step 5 states the wrong artifact format and the wrong retrieval
route.** Confidence: high.
Guide text: *"Roblox writes mobile dumps into the client's own storage; the practical
route is to open the developer console's MicroProfiler tab and use its export/share
action, then copy the `.gprx` off the device."*
First-party text: on mobile you *"use the **Save to file** button"* in the web UI and
the profiler *"saves frame data to a standalone HTML file named
`microprofile-<date>-<time>.html`."* It is **not** a `.gprx` and it is **not** copied
off the device's storage — it downloads to the browsing machine. (`.gprx` is what
LibMP's `CaptureToBufferSync` produces in Studio; conflating the two will send the
operator looking for a file that does not exist.) The Dump-menu-to-logs-directory route
the guide half-describes is the **desktop/Studio** route, not the mobile one.

**MINOR-5 — §12.5 omits the frame-count control, which is load-bearing for this
stage.** The web UI *"shows the 30 most recent frames"* by default and you *"add a
slash and a number to the URL"* (e.g. `/90`) for more, plus a **Re-capture** button for
fresh data. A stage whose Studio captures are 60-frame windows needs the operator to
know the mobile default is 30 and how to raise it, or PL-P1 will come back with half
the sample.

**Corrected §12.5 steps 3 and 5 (drop-in):**

> 3. Put the phone and a development machine on the same network. On the phone, open
>    the Roblox in-experience menu → **Settings**, and set **MicroProfiler** to **On**.
>    The client displays an IP address and port. From the development machine, browse
>    to `http://<ip>:<port>`; the MicroProfiler web UI shows the 30 most recent frames.
>    Append `/<n>` to the URL (e.g. `/90`) for a longer window, and use **Re-capture**
>    to take a fresh set after the workload is running.
> 5. In the web UI, press **Save to file**. The browser downloads a standalone HTML
>    file named `microprofile-<date>-<time>.html` to the development machine — there is
>    no `.gprx` on the phone and nothing to copy off device storage. Store that HTML
>    beside the capture row as the primary artifact.

Also worth adding: the docs' own rationale for insisting on the phone —
*"Most players on Roblox use phones and tablets, and these devices have severe thermal
and power constraints that limit their performance."* — which is precisely PL-P1's
argument.

---

## Area 3 — the self-contained place

### Verified

- **`rbxthumb://type=AvatarHeadShot&id=N&w=48&h=48` is publicly resolvable with no
  upload and no place permission — CLAIM CONFIRMED.** Source:
  `Roblox/creator-docs` `content/en-us/projects/assets/index.md`, rendered at
  <https://create.roblox.com/docs/projects/assets>. The documented syntax is
  `rbxthumb://type=Asset&id=24813339&w=150&h=150`, and the supported-types table lists
  `AvatarHeadShot | ID for a Roblox user (Player.UserId) | 48×48, 60×60, 100×100,
  150×150, 180×180, 352×352, 420×420`. **48×48 is an explicitly supported size**, the
  target is a `UserId` (not an owned asset), and no upload or permission is involved.
  `examples/performance/lab/dataset.luau:129-142` is correct as written.
- **No universe/place id, no filesystem path, no plugin in the place source.**
  `examples/performance.project.json` read in full: a `DataModel` tree with Workspace
  attributes, a Baseplate, a SpawnLocation, `Players.CharacterAutoLoads = false`, and
  three `$path` mounts (`../src`, `themes`, `performance/lab` + the gallery runner) plus
  `StarterPlayerScripts`. `$path` is a *build-time* Rojo input; nothing survives into
  the `.rbxl` as a path. `tools/build_places.sh:165` is a plain `rojo build ... -o`,
  no publish. **Claim holds.**
- Exactly one implementation mounts (`native_list.mount` asserts, `perf_lab.mount`
  refuses a second) and the reference ScreenGui is deliberately *not* `LuauUI`-prefixed
  so the census cannot mis-attribute it — good, and PLN-1's live census backs it.

### Findings

**MAJOR-6 — the place is not asset-free: the ornate reference theme package and
`src/themes/standard_icons.luau` bind eleven `rbxassetid://` image ids, and nothing in
this stage records that those assets are public.** Confidence: high that the dependency
exists; medium that it is a hazard.
*Where:* `examples/performance.project.json` mounts `LuauUIThemes` (`themes/`), and
PL-6 requires running under "the most expensive shipped asset-backed reference
package"; `src/themes/standard_icons.luau:53-103` carries ids such as
`rbxassetid://81739481512878`.
*Why it matters:* PL-1's wording is "no private asset". An image asset that is not
public renders as a broken/blank image for anyone who is not its owner. The user
publishing to their own account is fine; a place handed to a reviewer, a second
account, or a group universe is not. The stage claims publish-safety without recording
a check.
*Smallest corrective test:* record, once, the moderation/public status of the eleven
standard-icon ids and of every id in the ornate package (a single
`MarketplaceService:GetProductInfo` sweep, or the Creator Dashboard listing), and state
in `place.json` either "all assets public" or "publish-safe for the owning account
only".

**MINOR-6 — `dataset.FAILING_IMAGE_KEY = "rbxassetid://1"` and the `"&broken=1"`
suffix are unproven failure injectors, and the recorded evidence shows the failure leg
never actually failed at the engine.** Confidence: high.
`artifacts/.../studio/perf-lab.json:asyncImages` records `failVerdict: "stale"` and
`failMs: 0.14` — i.e. the fail path was driven by calling `provider.fail(...)` with a
generation that was already stale, which exercises the *provider's* refusal, not an
engine image-load failure. Separately: `rows.luau:99` builds the failing key as
`item.imageKey .. "&broken=1"` — appending an unrecognised query parameter to an
`rbxthumb://` URL. Whether the engine rejects an unknown `rbxthumb` parameter or
ignores it is undocumented; if it ignores it, the "asset failure" workload silently
becomes a *success* workload with a different cache key. `rbxassetid://1` is likewise
an arbitrary id that may resolve to a real (non-image) asset rather than failing.
*Corrective test:* mount one row with the failing key in Studio and assert the async
provider reaches its `error` state (and that the client log carries the engine's
"failed to load" line) before treating the leg as an asset-failure capture.

**MINOR-7 — `.tmp_probe/` is untracked in the working tree** and `examples/places/` now
carries a rebuilt `LuauUI-PerformanceLab.rbxl` alongside eight modified example places.
Not a platform defect; flagged because PL-16's "builds from a clean source state" is
harder to believe with a probe directory in the tree.

---

## Area 4 — is `native_list.luau` a fair floor? (and is 4.7× misleading?)

### Verified

- It genuinely windows: full-extent `CanvasSize` set once (`native_list.luau:196`), a
  fixed pool sized `ceil(viewportHeight/pitch) + 2*overscan + 2` (`:199`) — the *same*
  formula as `rows.expectedWindow` (`rows.luau:38-41`) — absolute offsets from
  `CanvasPosition` (`:217`, `:233`). This is the right shape; a non-virtualized
  reference would have been the classic wrong answer. **Good.**
- Geometry is genuinely shared: the reference reads `ROW_HEIGHT`/`ROW_GAP`/
  `IMAGE_SIZE`/`OVERSCAN` from the same module the LuauUI row uses. **Good.**
- The capability ledger travels with the capture and is honest about six omissions.
  **Good, with the gaps below.**
- PLN-5's disposition (recycling is an architecture decision, escalated with numbers
  rather than attempted) is the right call and is not what I am contesting.

### Findings

**MAJOR-3 (numbering continues) — the 4.7× ratio compares two different *amounts of
work per step*, not two implementations of the same step, and the artifact does not
say so.** Confidence: high.
Three concrete asymmetries, all in favour of the reference:

1. **The reference does nothing on ~1 frame in 3.** `window()` early-returns when
   `start == firstIndex` (`native_list.luau:234-236`). The steady pass advances 40px
   per frame at a 60px pitch (`perf_lab.luau:539-543`), so the start index is unchanged
   on roughly a third of frames and those samples are ~0ms. LuauUI's side calls
   `ctx.presenter.refresh()` unconditionally every frame (`perf_lab.luau:553`) whether
   or not the window changed. A p50 taken across a distribution where one side has a
   third of its samples at zero is not the same quantity as the other side's p50.
2. **The two sides' work lands in different halves of the timer.** For the reference,
   `scrollTo` writes `CanvasPosition` **and** calls `window()` synchronously
   (`native_list.luau:262-269`), so the re-window is inside `writeMs`. For LuauUI the
   re-window is `refreshMs` after a Heartbeat. The reported `totalP50` sums both, so
   this is not itself an error — but `scrollWriteMs`/`reWindowMs` reported *separately*
   are not comparable between implementations, and `perf-lab.json` publishes the split.
3. **`ctx.presenter.refresh()` runs on the native leg too.** With the reference
   mounted, LuauUI owns 0 GuiObjects (PLN-1), so that call is ~free — fine — but it
   means the native's `refreshMs` measures a LuauUI no-op, and the artifact presents
   `totalP50` for both as though the same two phases were measured.

*Corrective test:* report the ratio over *window-changing frames only* on both sides
(count them; the reference already knows), or make the reference repaint
unconditionally so both sides do work every frame. Either way, state in
`decisions.md`/`perf-lab.json` which of the two you chose.

**MINOR-8 — the capability ledger omits the two largest cost drivers.**
Confidence: high. `native_list.CAPABILITIES.lacks` names six things but not:
(i) **text premeasurement** — the reference sets `Text` and lets the engine truncate;
LuauUI premeasures via the text-facts path, which is a per-string async/cached engine
call and is plausibly the biggest single per-row difference (and is exactly what N-2's
"cold `updateOne` is 20× the warm one" points at);
(ii) **a real bound Toggle** — `Ready` in the reference is a `TextButton` whose colour
is painted from `item.enabled` and which has **no toggle API at all** (grep the module:
there is no `api.toggle`), while the LuauUI row mounts a live `UI.Toggle` bound to a
signal (`rows.luau:157`).
Also worth stating: the census counts **GuiObjects**, so LuauUI's `UICorner`/`UIStroke`/
`UIPadding` modifier instances are *not* in the 23.6/row figure — the true instance gap
is larger than 2.6×, which strengthens PLN-5 rather than weakening it, but the artifact
should say which class it counted.

**MINOR-9 — the reference's `disclose`-less identity line.** `rows.luau:153` sets
`disclose = true` on the LuauUI name (correctly — the plan forbids dropping
accessibility to improve a profile). The reference has no equivalent and the ledger
covers it only as "full-value disclosure". Fine, but it means the reference is not just
"the same row without a framework" — it is a *simpler row*. One sentence in
`whatTheReferenceLacks` about presentation parity would close it.

---

## Area 5 — the `CanvasPosition` echo-timing claim (L-1)

**MAJOR-6 (continues numbering) — the *behaviour* is right; the *stated cause* is
wrong, and the wrong cause is now written into three places.** Confidence: high on the
mechanism, medium on whether a shorter wait would suffice in all cases.

*The claim* (`optimization-log.md` L-1; `perf_lab.luau:494-502`; `:526`): "the windowing
mirror is fed by the engine's own property-changed signal, which lands on the **NEXT
frame**."

*What actually happens.* `src/client/screen_target.luau:2664` connects
`instance:GetPropertyChangedSignal("CanvasPosition")`. Under Roblox's default
`Enum.SignalBehavior.Deferred` (the platform default since 2022), a signal handler is
not invoked synchronously at the point of the write — it is queued and invoked at the
**next resumption point**, which is normally *later in the same frame*, not the next
frame. That is why writing and reading in the same synchronous block observed nothing.
A `task.defer` boundary — or simply the existing `telemetry.step()` — flushes it.
Separately, and independently, a `ScrollingFrame` clamps `CanvasPosition` against
`CanvasSize - AbsoluteWindowSize`, values the engine refreshes during its own layout
pass, so a write issued in the same tick as a `CanvasSize` change *can* additionally be
clamped against stale extents — that one really is a frame-boundary effect.

*Why it matters here:* the fix (wait a Heartbeat) is safe and I am not asking for it to
change. But the recorded *cause* is what the next stage will reason from, and "the
engine's changed signal lands next frame" is a false general rule that will produce
wrong predictions elsewhere (e.g. someone will assume a `task.defer` is insufficient,
or will add frame waits after unrelated property writes). It also mislabels the
26.6ms/17ms figure: the excluded quantity is *a full Heartbeat wait the driver chose*,
not "the engine's echo latency", which is much shorter.

*Smallest corrective test:* in Studio, write `CanvasPosition`, then `task.defer` once,
and assert the mirror signal has already fired (0 frames elapsed). If it has, correct
the comment to "deferred signal behaviour — flushed at the next resumption point" and
keep the Heartbeat wait as the conservative choice, with the clamping caveat stated
separately. Sources:
<https://create.roblox.com/docs/reference/engine/enums/SignalBehavior>,
<https://create.roblox.com/docs/reference/engine/classes/ScrollingFrame#CanvasPosition>.

---

## Area 6 — the Studio device matrix

### Verified

- **The `pinnedDeviceId` requirement for `compact-phone-landscape` is genuine and is
  recorded honestly.** `studio/device-matrix.json` records that the first attempt
  returned `selectOk: false` and left the viewport at the portrait `360×691`, and then
  pins `samsung_galaxy_a06`. This matches the repo's own standing trap note in
  `docs/plans/studio-device-verification.md` lineage. The final row reports
  `706×339 / LandscapeLeft`, which is a real landscape viewport, so the pin worked.
  **Claim confirmed, and the failed first attempt being kept in the artifact is exactly
  the right practice.**
- **Labelling all five rows `emulator` is correct.** The Studio device emulator
  substitutes viewport size, orientation, scaling mode and input emulation; it executes
  on the development host's CPU and GPU and does not model a mobile SoC, mobile GPU,
  thermal throttling, or retail-client memory. The artifact's `honestBoundary` says
  exactly this and refuses to let any row satisfy a device budget; `perf_runner`
  additionally refuses at ingest. **Correct, and conservatively worded.**
  (Basis: Roblox's device-emulator documentation describes emulation of screen/input
  only — <https://create.roblox.com/docs/studio/testing-modes>. I did not fetch that
  page this session; the claim is uncontroversial and the artifact under-claims rather
  than over-claims, so I did not treat it as load-bearing.)
- `simulationStopped: true` and the reset-to-no-device step: good hygiene, and it is
  the failure mode that silently poisons the *next* session.

### Findings

**MINOR-10 — the headline invariant is trivially true because the list's viewport is a
hardcoded constant.** Confidence: high.
`device-matrix.json` claims *"the mounted window stayed at 11 rows against a bound of
13 for 800 logical rows — bounded virtualization does not depend on the viewport"*. But
`perf_lab.luau:262` sets `local VIEWPORT_H = 420` and the bound is
`rows.expectedWindow(420)` = `ceil(420/60) + 2*2 + 2` = **13** in every row, on every
device. The list's viewport never changes with the emulated device, so `mountedRows`
and `windowBound` are *identical by construction* across all five rows — which is what
the artifact reports (11/13, five times). The row proves the lab mounts and runs at
five viewports; it does **not** prove that windowing tracks a changing viewport.
*Corrective test:* one row where the list height is driven from the actual screen
(e.g. `fill`), asserting the window shrinks on the 339px-tall landscape phone and grows
on the 1080p console.

**MINOR-11 — the pinned row is measured with fewer fields than its peers.**
`compact-phone-landscape` is the only row missing `guiObjects` and `scalingMode`, and
the only one carrying `pickerChipsInScrollView`. Four rows report `guiObjects: 294`;
the one row that required special handling reports none. Fill it in, or say why it
could not be read.

---

## Checks I did not run, and why

- **No mutation testing** of the profile spec or the perf gate — the delegation says do
  not edit files, and every mutation proof here would require a source edit.
- **No live Studio session** — this review is source + first-party-document + recorded
  artifact only. Every finding above that needs an engine to settle (MAJOR-1's yield
  behaviour, MINOR-6's failure injectors, MAJOR-6's defer-vs-frame test, MAJOR-6/asset
  publicity) is written with the smallest Studio test that would settle it.
- **The LibMP "AI skill" file** referenced by `src/core/profile.luau:5-6` — I could not
  reach it first-party; the `$Script` claim is corroborated from DevForum engine-bug
  threads instead (MINOR-1).
- **`FetchGlobalDesc().TickToMsCpu` semantics** — absent from the README material I
  could fetch (MINOR-3).
- **Asset moderation status** of the eleven `standard_icons` ids and the ornate package
  — requires an authenticated Roblox API call (MAJOR-6).
- I did not re-run the LuauUI suite or `tools/perf.sh`; the stage records 3 361 passing
  and PASS respectively, and re-running them would not test any platform claim.

---

## Summary table

| # | Sev | Area | One line |
|---|---|---|---|
| MAJOR-1 | MAJOR | 1 | `span` is unguarded against yields; the lab's own `LuauUI/scenario` spans wrap 60 Heartbeat waits, and the counters cannot see it |
| MAJOR-2 | MAJOR | 1 | profiling is `enabled = true` by default on the engine, so shipped code pays a `pcall` per phase and loses tracebacks inside every LuauUI phase |
| MAJOR-3 | MAJOR | 2 | any duration derived from a `TimerIds`-filtered LibMP iterator is unsound; the artifact does not record which iterator produced the numbers |
| MAJOR-4 | MAJOR | 2 | §12.5 invents a developer-console MicroProfiler tab and omits the same-network web-UI + IP:port procedure the docs specify |
| MAJOR-5 | MAJOR | 2 | §12.5 names the wrong artifact (`.gprx` off device storage) — mobile Save-to-file produces `microprofile-<date>-<time>.html` on the browsing machine |
| MAJOR-6 | MAJOR | 3 | the place depends on `rbxassetid://` theme/icon assets whose public status is never recorded, so "no private asset" is unproven |
| MAJOR-7 | MAJOR | 4 | the 4.7× compares distributions where the reference does zero work on ~1 frame in 3 while LuauUI refreshes unconditionally |
| MAJOR-8 | MAJOR | 5 | L-1's cause is wrong: deferred signal behaviour (same frame, next resumption point) + `CanvasPosition` clamping, not "the signal lands next frame" |
| MINOR-1 | MINOR | 1 | the `$Script`/LibMP-limitation citation is not reachable from the repo |
| MINOR-2 | MINOR | 1 | the "unbalanced scope corrupts every subsequent frame" claim has no first-party basis |
| MINOR-3 | MINOR | 2 | `TickToMsCpu` provenance unrecorded; add a sum-vs-frame sanity check |
| MINOR-4 | MINOR | 2 | 65 frames at a 256 limit is unexplained, and a ~1s sample is thin for p50/p95 |
| MINOR-5 | MINOR | 2 | §12.5 omits the mobile web UI's 30-frame default and the `/<n>` URL suffix |
| MINOR-6 | MINOR | 3 | `rbxassetid://1` / `&broken=1` are unproven failure injectors; the recorded fail leg was a stale-generation refusal, not an engine load failure |
| MINOR-7 | MINOR | 3 | `.tmp_probe/` untracked in the tree weakens PL-16's clean-source claim |
| MINOR-8 | MINOR | 4 | the capability ledger omits text premeasurement and the fact that the reference's "toggle" has no toggle API |
| MINOR-9 | MINOR | 4 | the reference row is presentationally simpler than the LuauUI row (no disclosure path) |
| MINOR-10 | MINOR | 6 | the window-bound invariant is trivially true — `VIEWPORT_H = 420` is hardcoded, so the bound is 13 on every emulated device |
| MINOR-11 | MINOR | 6 | the pinned landscape row is the only one missing `guiObjects` and `scalingMode` |

*(Numbering in the body runs MAJOR-1..MAJOR-6 with two continuations noted inline;
the table above is the canonical, deduplicated list of eight MAJORs.)*
