# Performance lab — review packet (roadmap Step 9)

**What is left:** two rows, both irreducibly physical. Everything automatable is done
and green. This packet turns the remainder into one focused pass on one device.

**The honest headline:** *automation complete, low-end performance not proven.* The
lab measures, profiles and compares correctly on the development host, and one
framework bottleneck was found and fixed there. Whether LuauUI meets the low-end
Android budget is **unmeasured**, and nothing in this stage may be read as saying it
does.

**And one thing worth knowing before you read any number here.** The four fresh-context
reviews found a **BLOCKER** that the 3 367-case suite, the headless perf gate and six
live Studio sessions were all green over: the first version of the solver optimization
silently dropped the `compact` and `truncated` verdicts a solve publishes — geometry
byte-identical, so nothing looked wrong, while a cut label would have lost its
full-value disclosure path. It was caught by a differential fuzz, fixed, and pinned by
`tests/measure_memo.spec.luau`. Every performance number below was re-measured after
that fix.

---

## The pending rows

### PL-P3 first — it takes two minutes and it is not about performance

Open `examples/places/LuauUI-PerformanceLab.rbxl` in Studio (**File → Open from
File**), with no Rojo session running, and press Play. Confirm:

1. the console prints `[LuauUI Scenario] 'perf_lab' ready` and
   `[LuauUI PerfLab] 0.8.0 ready — scopes engine=true`;
2. the overlay is at the bottom, showing the build line
   (`LuauUI 0.8.0 · perf-scenarios/3 · perf-dataset/1 · perf-row/4`), the scenario
   line, the viewport/input line, the nine scenario chips, the five action buttons
   (which WRAP onto as many rows as the width needs — on a phone that is three rows of
   two, and "Clean capture" must be fully readable, not clipped) and six counter lines;
3. tap **dense-scroll** in the picker — rows appear with avatars, two-line text, a
   Ready toggle, a Rate stepper and an Open button, and `mountedRows=…/13` in the
   counters stays well under the logical row count while you scroll. Then RESIZE the
   window narrow enough to restack the rows (or rotate a simulated phone): the rows must
   restack, the pitch must follow, and nothing may overlap — that transition is where
   three separate defects lived;
4. tap **dense-scroll-native** — the raw-Roblox reference mounts instead, and the
   counters show LuauUI-owned GuiObjects drop to 0;
5. tap **Reset** — the workload disappears and the counters return to the idle
   baseline.

Everything in this stage was driven through these same sources injected into an open
place; what this confirms is that the **built file's Rojo mapping** is right, which a
static tree inspection cannot. See decision packet PLN-7.

---

## The performance rows

| ID | What it needs | Why nothing here can close it |
|---|---|---|
| **PL-P1** | Repeated captures of `dense-scroll`, `dense-scroll-native`, both themes and `lifecycle-soak` on the declared low-end Android floor device, through the **retail** client, under recorded device/thermal/graphics conditions | Studio and Lune are both faster than every supported device, and neither can observe thermal throttling, a mobile GPU, or retail-client memory. The device emulator changes the viewport, not the CPU. |
| **PL-P2** | The versioned floor budget established or ratified **from those captures**, and any framework-attributed bottleneck fixed against it | A device budget invented from desktop numbers reads as a passing SLA and guarantees nothing. `bench/perf_budgets.json` already declares `phone-physical` with `measured: false`, and `perf_runner.checkBudgets` refuses to satisfy it from host rows. |

---

## The review build

`examples/places/LuauUI-PerformanceLab.rbxl` — checked in, self-contained, and
verified by `python3 tools/check_perf_place.py` to contain everything it needs, with
no universe id, no developer path and no plugin dependency. Publish it yourself
(guide §12.2); the build never publishes.

---

## The pass, in order

Roughly 30 minutes on the device. Full detail in
[`docs/guide/12-performance-lab.md`](../../docs/guide/12-performance-lab.md) §12.5.

1. **Record the conditions first.** Device model, Android version, Roblox client
   version, orientation, graphics quality (set it explicitly — do not leave it on
   Automatic), frame-rate cap, whether it is plugged in, and thermal state. These
   change the answer more than most code does.
2. **Cold run.** Launch, wait for `[LuauUI PerfLab] … ready`, then:
   `select:scenario=dense-scroll,rows=2000,seed=1` → `mount` → `cleanCapture:on` →
   `warmup:30` → `pass:scrollSteady=60` → `export:1`. Repeat the pass/export three
   times. The overlay's action row is touch-operable if you would rather tap.
3. **The reference.** `select:scenario=dense-scroll-native,rows=2000,seed=1`, same
   sequence. This is the number that says how much of the cost is unavoidable.
4. **Theme.** `select:scenario=layout-style-churn,rows=800,seed=1` → `mount` →
   `pass:themeCost`. Install, steady-ornate, teardown and steady-flat are timed apart.
5. **Soak.** `select:scenario=lifecycle-soak,rows=800,seed=3` → `pass:soak=8`. Watch
   for a monotonic climb in Instances, signals, memos, scopes or connections.
6. **Hot run.** Repeat step 2 after ten minutes of sustained load. A throttled phone
   is the real device, and it is a different device from the one you started on.
7. **Dump.** Open the mobile MicroProfiler, dump in binary format, and copy the
   `.gprx` off the device.
8. **Record.** Each `export` row must carry `deviceModel`, `osVersion`,
   `clientVersion`, `powerState`, and **must not** carry a `studioVersion`. Drop the
   rows under `artifacts/cross-platform-proof/device/` and run
   `python3 tools/check_perf_captures.py` — it refuses a device row that looks like a
   relabelled Studio row.

**If something goes wrong:** `stop` halts a running ramp or soak between steps;
`reset` returns to the idle baseline. Neither needs a restart. If the device gets
uncomfortably warm, `stop` then `reset` and let it cool — the numbers from a thermally
saturated phone are a different measurement, not a worse one, and mixing them is how a
budget gets set wrong.

---

## What the reviewer is being asked to judge

Nothing subjective. Two questions, both answered by numbers:

1. **Does `dense-scroll` hold the frame target on the floor device?** The declared
   budget is 25% of a 30 Hz frame — 8.33 ms of LuauUI work. The Studio host measured
   p50 ≈ 4.0 ms of framework work for this workload with the frame wait excluded; a
   phone will be worse, and by how much is the open question.
2. **How much of the gap is unavoidable?** The matched raw-Roblox reference ran at
   p50 ≈ 1.02 ms against LuauUI's 4.0 ms on the host (≈ 3.9×, with LuauUI creating
   23.6 GuiObjects per row against the reference's 9.2). If the same ratio holds on
   the device, the ceiling question becomes an architecture question — see decision
   packet **PLN-5** (Instance recycling), which is escalated with numbers rather than
   attempted.

---

## Optional confirmation (not claimed as done)

The consumer-impact ledger records that no Rascal Rally contract changed and that the
game's 3 089-case suite was re-run at the judged source, but **a Rascal Rally Sponsor
Studio canary was not re-run** in this stage. If a reviewer wants belt-and-braces on
the solver memo, opening the Sponsor place and driving one results screen is the
cheapest way to get it.

---

## One thing a later reader should not have to rediscover

The solver optimization in this stage went through **three** shapes before it shipped:

1. unconditional and **wrong** — it dropped `compact`/`truncated` verdicts (architecture
   BLOCKER, caught by differential fuzz);
2. unconditional and correct, but **too broad** — it regressed a scroll-free bench scene
   past its 1.5× rule (caught by the prior-gates check, standalone);
3. **scoped** to trees containing a scroll node — no regression, and the beneficiary
   keeps −11%.

Both defects were found by controls rather than by the implementer, and neither was
visible in the 3 368-case suite. If you are reviewing a similar change, the two
instruments that worked were a **differential oracle** (two source copies, fuzzed trees,
diff the full per-node output) and an **interleaved A/B** (alternate the builds within
each pair — sequential batches drift with machine state and will mislead you).

## Rollback

Every change in this stage is additive except two. To back out:

- the solver memo: `src/layout/solver.luau` — `measure` becomes `measureUncached`
  again (delete the memo wrapper and the `measureCache` field). Geometry is unchanged
  either way; only the cost differs.
- the profiler scopes: `profile.setEnabled(false)` at runtime turns every span into a
  direct call without a rebuild.

The lab itself is entirely under `examples/performance/` plus its checked-in project
file, and removing it affects nothing else.

---

## PL-8b — the three new phase scopes, re-captured live (CLOSED)

`LuauUI/present`, `LuauUI/focusmap` and `LuauUI/tick` were added in L-27 to make the
per-frame presenter work visible — it was the single largest item in a scroll frame and
none of the nine existing scopes could see any of it. The gate went red on
`microprofiler-scopes`, correctly: the recorded capture had nine.

Re-captured 2026-08-05. **All twelve declared names found by mask in a live capture**
(frames 18132–18387), `opens == closes == 313 541`, `maxDepth` 4.

### The trap, which cost most of the time

**LibMP's `Control` channel is inert until the MicroProfiler is actually recording**, and
it does not say so. Before it is armed, `Control:SetFrameLimit` / `EnableProfiler` /
`EnableCapture` all raise `attempt to index nil with 'slotId'` (LibMP:155179) — on
`Control` and on `Control.Global` alike — and, far worse, **`CaptureToBufferSync` still
returns a buffer**.

That buffer is stale. Two captures two seconds apart returned the identical frame window
(13436–13487), and a brand-new label opened 1 000 times never appeared in it. Every
reading taken from it described an old session while looking exactly like a measurement.

**A capture that returns data is not the same as a capture that returns THIS session's
data.** The one-line check: snapshot twice and assert `GetFrameIdMax` advanced. It is now
the first thing the recipe does.

### Arming it without a human

`Ctrl`+`Alt`+`F6` delivered through the Studio MCP keyboard path
(`user_keyboard_input`, datamodel `Client`) starts the recording with nobody at the
keyboard. The buffer goes live immediately, `Control`'s setters stop raising, and the
mask finds twelve instead of nine. This was previously assumed to need a person.

Drive every phase before capturing — `async-image-churn` for `resource`/`mutate`, then
`dense-scroll` `scrollSteady`/`selectRow`/`updateOne`, then `reset` — because a scope
enters the timer table only once it has RUN. That is the same trap this artifact's
existing `correction` records, and it bites again every time.
