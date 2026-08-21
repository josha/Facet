# 12 — The performance lab

The lab is a self-contained Roblox place that makes Facet performance problems easy
to **reproduce, profile, optimize and compare** — with the same workload, the same
seed and the same conditions every time. It is not a demo. Everything on screen
exists so a number can be attributed to something.

It is also, deliberately, a place you can publish privately and open on a phone.
The weakest supported Android device is the only thing that can answer "is this fast
enough", and no amount of Studio profiling substitutes for it.

**One rule runs through this whole chapter.** Five labels, never interchangeable:

| label | what it is | what it can close |
|---|---|---|
| `lune` | `tools/perf.sh` — headless, no engine, no frame | regression trends only |
| `studio` | the real adapter in a Studio Play session | attribution and regression on the dev host |
| `emulator` | a Studio device-simulator viewport | layout and operability, **never** that device's speed |
| `desktop-retail` | the shipped desktop client | desktop device rows |
| `phone-physical` | the shipped mobile client on named hardware | **the only** class that closes the low-end budget |

---

## 12.1 Rebuild and open the place

```bash
cd GameStudio/ui/Facet
tools/build_places.sh                      # rebuilds every example place, the lab last
python3 tools/check_perf_place.py          # rebuilds from clean source and inspects the result
```

The doctor is the interesting half: `rojo build` emits a file even when a `$path` is
wrong, so `check_perf_place.py` opens the built tree and asserts the sixteen instances
the lab cannot run without (the library, `core/profile`, the scenario registry, the
reused gallery runner, the five lab modules, the ornate theme package, the bootstrap
and the raw-Roblox reference), the five version markers a capture cites, and that the
place carries no absolute developer path, no assigned `PlaceId`/`GameId` and no plugin
dependency.

**One honest limit on "self-contained".** The doctor proves the place carries no
universe/place id, no developer path and no plugin. It does **not** prove every asset
id in it is publicly readable: the place maps `examples/themes/`, and the ornate
workload needs the
ornate package, which declares 34 `rbxassetid://` images; `src/themes/standard_icons`
binds eleven more. The row images are `rbxthumb://type=AvatarHeadShot&id=<UserId>&w=48&h=48`,
which are generated from a UserId and need no upload or permission — but the theme
assets' public status is not something a build check can establish. If you publish the
place and an ornate panel renders blank, that is the reason, and it affects only the
theme-cost workload.

Then, in Studio: **File → Open from File →**
`GameStudio/ui/Facet/examples/places/Facet-PerformanceLab.rbxl`, and press Play.
No Rojo session, no plugin, no `.env`. The console prints:

```
[Facet Scenario] 'perf_lab' ready (0.8.0); steps: cleanCapture,counters,export,fault,mount,...
[Facet PerfLab] 0.8.0 ready — scopes engine=true
```

`scopes engine=true` means `debug.profilebegin` is available and the Facet phase
scopes will appear in a capture. If it says `false`, every scope silently becomes a
direct call and the capture will show `$Script` only.

### Iterating on lab sources without republishing

While developing the lab itself, serve the sources instead of rebuilding:

```bash
lune run tools/lune/studio_sync perf        # NOT the default gallery tree — see below
```

then run `tools/studio/inject.luau` through the Studio Model Context Protocol
(MCP) server, in the **Edit** datamodel.
`perf` mode matters: the gallery and the lab both mount at
`ReplicatedStorage.FacetScenarios` (the lab *reuses* the gallery's runner rather than
forking it), so serving both at once would put two different `init.luau` files at the
same path. The injector stamps `workspace.Facet_SourceStamp`, and every capture
records it — that stamp is how you prove a session is running the source you just
built rather than whatever Studio had cached.

---

## 12.2 Publish it yourself (the agent must not)

The build never publishes, uploads, or attaches a universe. To get the lab onto a
phone:

1. Open `examples/places/Facet-PerformanceLab.rbxl` in Studio.
2. **File → Publish to Roblox As…**, create a **new** experience, and set its privacy
   to **Private** (Creator Dashboard → the experience → Configure → Permissions).
   A private experience is still openable by you on any device you are signed in on.
3. Note the place id — it is not needed by the lab, only by you, to find it again.
4. On the phone, open Roblox, go to **Create / My Experiences**, and launch it.

Nothing in the place has an id baked in, so the same file can be published as many
times as you like without editing it.

---

## 12.3 Drive it

The overlay at the bottom of the screen carries the selectors, the action row, the
build/scenario/device labels and the live counters. Everything it does is also a
scriptable step, so a sweep needs no pointer:

```lua
-- Studio MCP execute_luau, Client datamodel
local HttpService = game:GetService("HttpService")
local api = workspace:WaitForChild("FacetScenarioAPI")
local function step(s) return HttpService:JSONDecode(api.step:Invoke(s)).result end

step("select:scenario=dense-scroll,rows=2000,seed=1,content=normal,theme=flat")
step("mount")
step("warmup:30")
step("run")                    -- the scenario's declared pass sequence
print(HttpService:JSONEncode(step("export:1")))
```

### The seventeen workloads

| id | question it answers |
|---|---|
| `idle-baseline` | what the place costs before any Facet work |
| `mount-ramp` | how mount, layout, Instances and memory scale with row count |
| `dense-scroll` | is steady scrolling smooth, and is windowing bounded |
| `dense-scroll-native` | which cost is unavoidable engine work vs framework overhead |
| `collection-churn` | do updates stay proportional to changed content |
| `layout-style-churn` | which invalidations cause unnecessary whole-tree work |
| `resize-relayout` | what a continuous resize costs, and how much re-solves what did not change |
| `large-text-overflow` | are measurement, disclosure and motion bounded without hiding content |
| `async-image-churn` | are decoding, resource lifecycle and UI updates separated and bounded |
| `motion-flight` | what an interpolating property costs per frame, and what a surface authoring none pays |
| `sensory-cascade` | what the per-control sensory cascade costs a tree that declares nothing |
| `variable-extents` | what a variable-extent window costs against the uniform arithmetic it replaces |
| `table-unified` | what virtualization, multi-selection and reordering cost in ONE container |
| `arrange-shapes` | WHICH tree shape makes `arrange` expensive, and whether the cost is flat per node |
| `edit-locality` | does an edit that changes nothing visible still re-solve, and does incremental layout bite on a collection edit |
| `host-move` | do a container's engine writes collapse inside a real instance host, and is that a frame-time win |
| `lifecycle-soak` | do Instances, connections, memory or stale work trend upward |

**The three before the soak are the NAMED LEVERS** (`levers.luau`), each aimed at
a cost a device capture ranked and no workload reached: `arrange` itself was the
top cost in all four captures of 2026-08-15, incremental layout had only ever
been measured on a resize, and ADR-0032's write collapse had never been priced as
frame time. One lap is one ARM, so a 60-frame dump can hold the comparison it was
taken for — `pass:flat=60`, then `pass:fill=60`.

`variable-extents` and `table-unified` mount their own surfaces
(`implementation = "none"`), so neither re-bases any number above them. Both take a `frames/reps` payload —
`pass:tableUnified=30/40` — because their headline quantities are p50s and an
operator who cannot raise n cannot get out of a wide control band. Their control
bands, deltas and the MicroProfiler pass over them are
`artifacts/performance-stress-places/optimization-log.md`; the device
recipe is `docs/handoff/2026-08-14-device-capture-collections.md`.

### One button: Run all

The panel's top row is always on screen, whatever the panel is capped at, and holds
everything a profiling session needs:

```
◀   dense-scroll   3/17   ▶   ▶ Run all
DONE 17/17 — dump now: Ctrl/Cmd+F6, Ctrl+P to pause
```

- **◀ / ▶** step through the seventeen workloads and wrap at both ends. Each step unmounts,
  selects and remounts, so the label and what is running can never disagree. The chip
  list further down jumps straight to one.
- **▶ Run all** runs every workload in order, back to back, in its own thread so the
  panel keeps repainting and **Stop** stays pressable. The status line counts
  `running 4/17 · collection-churn` as it goes.
- At the end the sweep unmounts everything and the status line tells you what to press.
  Arm the MicroProfiler first and one dump covers the whole sweep with every
  `Facet/*` phase scope in it.

**A workload that fails does not end the sweep.** Its error is recorded in the result
row and shown on the status line, and the remaining workloads still run — so one
scenario that cannot mount in this environment costs you one result, not sixteen.

`steps.sequence` is the same thing from a driver, and returns
`{ran, planned, failed, completedWholeSweep, results, dumpNext}`.

### The controls that matter

- **`select:`** — `scenario`, `impl` (`facet`/`native`/`none`), `rows`, `seed`,
  `content` (`normal`/`locale`/`identity`), `theme`, `warmup`, `frames`. An unknown
  scenario or setting is refused **by name**; `rows` is clamped to the declared ceiling.
- **`cleanCapture:on`** — *dismisses* the overlay rather than hiding it. A hidden
  ScreenGui is still a mounted tree the census counts and the frame pays for. Use it
  for any number you intend to compare.
- **`stop`** — the emergency stop. The ramp and the soak check it between steps, so a
  stress run cannot make Studio or a low-memory phone unrecoverable. `resume` clears it.
- **`reset`** — back to the idle baseline, and it *proves* teardown: the result carries
  the Instance and reactive-core census before and after.
- **`fault:window=on`** — breaks the lab's own virtualization on purpose. The next
  `mount` **must** fail with "virtualization is NOT bounded". If it does not, the
  bounded-window assertion is not wired and every windowing claim is unsupported.
  `fault:window=off` restores it.
- **`export:<n>`** — the capture row. It is **refused** if any condition is missing;
  `"unknown"` counts as missing.

### Getting a capture row onto disk without transcribing it

A Studio client cannot make an HTTP request during Play. With
`lune run tools/lune/studio_sync perf` serving, create a bridge once per session —
server side:

```lua
-- Server datamodel
local HttpService, RS = game:GetService("HttpService"), game:GetService("ReplicatedStorage")
local ev = Instance.new("RemoteEvent"); ev.Name = "Facet_PerfSave"; ev.Parent = RS
ev.OnServerEvent:Connect(function(_p, name, body)
    print(HttpService:RequestAsync({
        Url = "http://127.0.0.1:8642/save?name=" .. name .. "&dir=perf",
        Method = "POST", Body = body }).StatusCode)
end)
```

client side: `RS.Facet_PerfSave:FireServer("my-capture", HttpService:JSONEncode(payload))`.
The row lands in `artifacts/performance-stress-places/studio/` byte-for-byte as the
instrument emitted it. Then:

```bash
python3 tools/check_perf_captures.py
```

---

## 12.4 Profile it: the MicroProfiler and LibMP

Facet publishes a **closed set of nine phase scopes** (`src/core/profile.luau`):

| scope | phase |
|---|---|
| `Facet/mutate` | the batched model change |
| `Facet/react` | reactive propagation: dirty walk, memos, observers, effects |
| `Facet/measure` | the solver's measure pass |
| `Facet/arrange` | the solver's arrange pass |
| `Facet/commit` | adapter property writes |
| `Facet/mount` | Instance creation, reconciliation and disposal |
| `Facet/resource` | an async resource landing and its UI update |
| `Facet/scenario` | the lab driver's own per-frame and per-pass work |
| `Facet/reset` | the driver's teardown |

There is deliberately no label per row, key or node: `profile.span` refuses any name
outside the set, and a headless case proves the emitted label count does not scale
with row count.

**Interactively**, press <kbd>Ctrl</kbd>+<kbd>F6</kbd> in Studio (<kbd>Cmd</kbd>+
<kbd>F6</kbd> where the keyboard has a Command key) to open the MicroProfiler, then pause it (<kbd>Ctrl</kbd>+
<kbd>P</kbd>) on an interesting frame. The `Facet/*` bars sit under the script scope.

**Programmatically**, through the Studio MCP or the command bar — this is how the
numbers in `artifacts/performance-stress-places/studio/perf-lab.json` were produced:

**Arm the recording first, or everything below lies to you.** `Control` is inert until
the MicroProfiler is actually recording: `SetFrameLimit`/`EnableProfiler`/`EnableCapture`
raise `attempt to index nil with 'slotId'`, and `CaptureToBufferSync` *still returns a
buffer* — a stale one. Start it with `Ctrl`+`Alt`+`F6`, which the Studio MCP can deliver
itself (`user_keyboard_input`, datamodel `Client`); no human at the keyboard is needed.
Then prove the buffer is live before trusting a single number:

```lua
local function frameMax()
    local s = LibMP.Session.OpenFromBuffer(LibMP.Control:CaptureToBufferSync())
    local m = s:GetFrameIdMax(); s:Dispose(); return m
end
local a = frameMax(); task.wait(1); assert(frameMax() > a, "stale buffer: profiler not recording")
```

```lua
local LibMP = require("@rbx/LibMP")
LibMP.Control:SetFrameLimit(256)
LibMP.Control:EnableProfiler(true)
LibMP.Control:EnableCapture(true)
task.wait(0.15)
step("pass:scrollSteady=60")                      -- drive the workload
local buf = LibMP.Control:CaptureToBufferSync()   -- snapshot; do NOT OpenFromLiveData here
local session = LibMP.Session.OpenFromBuffer(buf)
local tickToMs = session:FetchGlobalDesc().TickToMsCpu
local ids = session:FindTimerIds("Facet/*", false)   -- returns exactly the nine, or fewer
local nameOf = {}
for _, id in ids do nameOf[id] = session:FetchTimerDesc(id).TimerName end

local iter, totals, counts = session:CreateLogIterator(), {}, {}
local st = iter:GetState()
iter:RewindTo(0, 0)
while iter:Step() do
    if st:IsExit() and not st:ThreadStackIsUnderflowed() and not st:ThreadStackWasOverflowed() then
        local id = st:TimerId()
        if nameOf[id] then
            local el = iter:GetCurrentThreadStackElement(st:ThreadStackDepth())
            if el then
                local ms = (st:Timestamp() - el:EnterTimestamp()) * tickToMs
                totals[id] = (totals[id] or 0) + ms
                counts[id] = (counts[id] or 0) + 1
            end
        end
    end
end
session:Dispose()
```

**One thing to know before you add the bars up: Facet scope times are INCLUSIVE and
they nest.** A solve driven from inside an observer runs `measure`/`arrange`/`commit`
*within* `Facet/react`, so summing `byScope` double-counts. Compare exclusive times, or
compare one phase against itself across two captures — which is what the optimization
loop actually does.

Three things measured on Studio 0.732 that will cost you an hour if you rediscover them:

- **A capture that returns data is not a capture of THIS session.** Unarmed, two
  snapshots two seconds apart returned the identical frame window and a brand-new label
  opened 1 000 times never appeared — while every call succeeded. Assert
  `GetFrameIdMax` advances.
- **Do not filter the iterator with `Configure({ TimerIds = ids })`.** It returned
  zero exits; the unfiltered iterator with a Luau-side `nameOf[id]` test returns them
  all. Filter in Luau.
- **The frame limit is a ceiling, not a promise.** A heavy workload filled the
  MicroProfiler buffers after ~60 frames at a limit of 256. Snapshot immediately
  after the pass you care about, and read `GetFrameIdMin`/`GetFrameIdMax` rather than
  assuming your window is in there.
- **A scope appears in the timer table only once it has RUN.** A capture taken without
  driving a `reset` finds eight of the nine `Facet/*` timers, which is not the same as
  the framework declaring eight. If you are auditing the scope set, exercise every
  phase first — and never assert a count you did not read out of
  `src/core/profile.luau`.

Keep the binary capture. `CaptureToBufferSync` returns a buffer you can persist; the
MicroProfiler's **Dump → Dump in binary format** writes the same data as a `.gprx`
that `Session.OpenFromFile` reads offline. Never expand every frame into a giant raw
JSON artifact — store the capture plus a derived summary.

---

## 12.5 Capture on a low-end Android device

This is the only measurement that can close the device budget. Roblox's own reason for
insisting on it is the same as this stage's: *"Most players on Roblox use phones and
tablets, and these devices have severe thermal and power constraints that limit their
performance."*

**The procedure below was corrected after a fresh-context platform review checked it
against [the first-party MicroProfiler docs](https://create.roblox.com/docs/performance-optimization/microprofiler)
— the original invented a developer-console tab, omitted the network prerequisite, and
named the wrong artifact format.**

1. Publish the place privately (12.2) and open it on the phone.
2. **Record the conditions before you start**, because they change the answer more
   than most code does: device model, Android version, Roblox client version,
   orientation, the in-experience graphics quality (Settings → Graphics Quality; set
   it explicitly rather than leaving it on Automatic), the frame-rate cap, whether
   the device is plugged in, and its thermal state. Run at least one capture from
   cold and one after ten minutes of sustained load — a throttled phone is the real
   device, and it is a different device from the one you started on.
3. **Put the phone and a development machine on the same network.** On the phone,
   open the Roblox in-experience menu → **Settings**, and set **MicroProfiler** to
   **On**. The client displays an **IP address and port**. From the development
   machine, browse to `http://<ip>:<port>` — the MicroProfiler on mobile is a **web
   UI served by the phone**, not an on-screen timeline you dump from. It shows the 30
   most recent frames by default; append `/<n>` to the URL (e.g. `/90`) for a longer
   window, and use **Re-capture** to take a fresh set once the workload is running.
   A 60-frame pass needs at least `/60`, or you will bring back half the sample.
4. Drive the workload. The overlay's action row is touch-operable; `dense-scroll` is
   the one to start with, at the default 2 000 rows, seed 1, `content=normal`,
   `theme=flat`, with **clean capture on**.
5. In the web UI, press **Save to file**. The browser downloads a standalone HTML
   file named `microprofile-<date>-<time>.html` **to the development machine**. There
   is no `.gprx` on the phone and nothing to copy off device storage — `.gprx` is what
   LibMP's `CaptureToBufferSync` produces in Studio, and the Dump-menu-to-logs route is
   the desktop/Studio one. Store that HTML beside the capture row as the primary
   artifact.
6. Record the capture beside a `phone-physical` capture row. The row must carry
   `deviceModel`, `osVersion`, `clientVersion` and `powerState`, and must **not**
   carry a `studioVersion` — `tools/check_perf_captures.py` refuses a device row that
   looks like a relabelled Studio row.

**Until that row exists**, the honest statement is *automation complete, low-end
performance not proven*. `bench/perf_budgets.json` already declares a
`phone-physical` budget with `measured: false`, and `perf_runner.checkBudgets`
refuses to satisfy it from host rows. Filling it in is what closes the two
open device rows in the lab's review packet.

---

### What the comparison looked like when this chapter was written

Studio host, `dense-scroll`, 2 000 rows, seed 1, flat theme, clean capture, three
identical repeats each, frame wait excluded:

| | p50 | GuiObjects | per row |
|---|---|---|---|
| Facet | 3.9–4.2 ms | 260 (11 rows mounted) | 23.6 |
| matched raw-Roblox reference | 1.0 ms | 119 (13 rows mounted) | 9.2 |

About **4×**, and read it as "about" — the reference early-returns when the window's
start index has not moved, so the two distributions are not quite the same amount of
work. The reference also has no focus graph, no theme authority, no async resource
lifecycle, no preferred-text reflow or disclosure, no adaptive composition and no
hit-target floor. Some of that 4× is buying those; how much is the open question, and
it is escalated with numbers in
`artifacts/performance-stress-places/decisions.md` rather than guessed at.

## 12.6 Compare two captures

Two rows are comparable only when **every** identity field agrees: scenario,
scenario/dataset/row versions, implementation, rows, seed, content, theme, dataset
digest, resource state and clean-capture flag. `capture.sameWorkload` returns the
differing fields when they do not.

A changed workload is a **new workload**. When the lab's scroll pass was split into
`scrollSteady` and `scrollSeek`, the scenario version went `perf-scenarios/1` →
`/2`, and no `/1` number was compared against a `/2` number. Do the same.

The comparison itself:

```bash
tools/perf.sh                                   # headless trend + frame-ceiling gate
lune run tools/lune/perf_baseline_scene lab-dense-scroll   # re-baseline ONE scene, not the file
```

`perf_baseline_scene` exists because `tools/perf.sh baseline` rewrites every budget —
right when the machine changes, wrong when a stage adds a scene. Re-baselining after
an **improvement** tightens the gate and is encouraged; re-baselining to make a
regression pass is the thing the plan forbids.

For Studio rows, take **three identical repeats** of each side and compare
distributions, not a single worst. A "worst" is one unlucky frame; the lab's passes
report `p50`, `p95`, `worst` and `mean` for exactly this reason. And note what the
lab excludes: a programmatic scroll's engine canvas echo takes a frame, and that
frame wait is **not** framework cost — the passes stamp `frameWaitExcluded = true`.

---

## 12.7 If you are building a fixture like this one

Read [`docs/lessons/the-solver-already-told-you.md`](../lessons/the-solver-already-told-you.md)
first. The short version, because it cost this stage a shipped defect:

- **Call `handle.controller.diagnostics()` in your fixture and fail on a non-empty
  result.** The solver reports overlap, main-axis overflow, collapsed content boxes and
  clipped essential text. A fixture that never asks is not verified, however green
  everything else is.
- **A count assertion is not a layout assertion.** `mountedRows <= windowBound` passed
  while rows painted over each other.
- **Sweep 320×640 through 1920×1080**, not your own viewport. The dev viewport is where
  layout bugs hide.
- **In a fixed-height windowed list, arrangement and row height are one decision.**
- **Measure a breakpoint inside the real fixed slot** — a free-height measurement only
  shows horizontal overflow.
- **You no longer have to notice this one yourself.** Since 2026-08-13 the framework
  checks the promise for you: a `newVirtualList` row whose content measures taller than
  the declared `itemExtent` files a finding on `controller.diagnostics()` naming both
  numbers and the row (`docs/reference/api.md` → [a lying `itemExtent`](../reference/api.md#a-lying-itemextent)).
  This lab's own `rows.heightFor` is what it was built from — it had to learn the
  viewport width, the type scale and the theme insets one device pass at a time, and
  still did not know about the accessibility text preference until rows overflowed
  their 56px slot by 11/39/59px on a real phone.

## 12.8 Return to idle and verify nothing is retained

```lua
step("reset")
```

The result carries the census on both sides. A clean teardown looks like this
(measured, clean capture on, 2 000 rows):

| | before | after |
|---|---|---|
| GuiObjects | 222 | **0** |
| signals | 84 | 26 |
| memos | 100 | 14 |
| scopes | 33 | 2 |

The residue is the lab's own overlay model and dataset signal, not the workload.
`lifecycle-soak` is the stronger form: eight identical mount/scroll/unmount cycles,
with Instances, signals, memos, scopes and connections byte-identical throughout.

If a number climbs across cycles, that is the finding — start with
`docs/lessons/` and the ownership shapes: a control that builds its own scope and
returns a `dispose` leaks once per materialized row if the caller does not own it.
