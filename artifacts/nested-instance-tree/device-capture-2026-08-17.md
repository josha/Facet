# Device MicroProfiler capture, 2026-08-17 — `host-move`, and what the engine actually does

**Evidence tier: 3 — physical device**, and therefore authoritative over every
headless (tier 1) and Studio (tier 2) number this round produced. Five binary
MicroProfiler dumps taken by the game director from `LuauUI-PerformanceLab.rbxl`.

| | |
|---|---|
| device | Samsung **SM-A102U1** (Galaxy A10e), Android 11 — read from each blob's own device record, not assumed |
| GPU | Mali |
| captures | `hostmove1.html`, `arm2.html`, `arm3.html`, `arm4.html`, `arm5.html` |
| workload | `host-move`, the lever added this round: a list of 6-cell rows with a header above it toggling 20↔60px every rep, so the list's origin moves every rep |

---

## 0. The headline, before anything else

| question | answer |
|---|---|
| Are all five usable? | **No — four.** `hostmove1.html` has a **zero-frame aggregate window** and carries no timings at all. It was arm 1, which was the A/A partner. |
| Is there an A/A control spread? | **NO, and nothing below should be read as if there were.** Arm 1 was it. See §2 for what stands in its place and why it is weaker. |
| Does the write collapse show up in a frame, on ARM? | **Yes, in `LuauUI/commit`, and it grows with N exactly as predicted: −8.8 % at 120 leaves, −18.9 % at 600. In frame terms −0.27 ms and −2.05 ms per frame.** |
| Does hosting reduce the ENGINE's descendant relayout? | **No. Totalled across contexts it is unchanged.** ADR-0032's stated risk lands, word for word. |
| Is a hosted surface therefore cheaper overall? | **No — on this workload it is DEARER**, and the arms cannot answer the question people will want to ask. See §5, which is the most important section here. |

---

## 1. Method

Decode as recorded in `artifacts/performance-stress-places/device-capture-2026-08-14.md` §2:
base64 in a leading HTML comment → `GAK` magic + `u32` sizes → zlib → aggregate timer
table of 80-byte records at `header[0x50]`, names in a `\0`-terminated blob of
`header[0xc4]` bytes at the tail, frequency `header[0x28]` = 1 000 000 000 (nanoseconds),
window `header[0x20]`.

**The decode is validated, not assumed:** `LuauUI/tick` reads **exactly 60** in all four
usable captures — one per frame over a 60-frame window — which is the same cross-check
the 2026-08-14 round used. `hostmove1.html` reads `header[0x20] = 0`.

**Arm identity was taken from the blobs, not from the filenames.** The engine's own
layout diagnostics name the tree: the hosted arms carry
`Cause=/HostArm/Rows Root=/HostArm/Rows` — the host is its **own relayout root** — and
the unhosted arms carry no such record at all. That independently confirms
1/2/4 = hosted and 3/5 = unhosted, which is the order the handoff note prescribes.

## 2. The A/A control is MISSING, stated before any delta

Arm 1 (`hosted`) and arm 2 (`hostedRepeat`) were the A/A pair. Arm 1 produced no
aggregate, so **there is no measured run-to-run spread on the clock** and no number
below is protected by one.

Two weaker things stand in its place, and neither is a substitute:

* **A structural A/A did hold.** Arms 1 and 2 produced **byte-identical** engine layout
  accounting — 127 relayouts / 248 updates / 247 resizes, both. The two hosted runs did
  the same work; only the timing of one was recorded.
* **A noise proxy.** `LuauUI/react` should be arm-independent (it is the reactive
  settle, not layout) and reads 0.1040 / 0.0975 / 0.1037 / 0.1005 ms per occurrence
  across the four arms — a **6.7 % spread**. Treat 6.7 % as the floor below which
  nothing here is a claim.

**Consequence: the N=20 result (−8.8 %) is at the edge of that floor and should not be
leaned on. The N=100 result (−18.9 %) is comfortably outside it.**

## 3. Where the time goes — ms per frame, 60-frame window

| scope | hosted N=20 | unhosted N=20 | hosted N=100 | unhosted N=100 |
|---|---:|---:|---:|---:|
| `arrange` | 6.771 | 6.312 | **28.533** | 20.799 |
| `measure` | 3.898 | 3.233 | 15.709 | 14.878 |
| **`commit`** | **4.233** | **4.499** | **12.361** | **14.407** |
| `present` | 4.006 | 3.667 | 22.691 | 21.270 |
| `mount` | 0.129 | 0.135 | 0.628 | 0.772 |
| `focusmap` | 0.262 | 0.251 | 0.334 | 0.270 |
| `react` | 0.121 | 0.107 | 0.119 | 0.117 |
| `tick` | 0.063 | 0.061 | 0.046 | 0.047 |
| **TOTAL** | **19.484** | **18.266** | **80.421** | **72.561** |

## 4. `commit` is where this round's change lives, and it delivers

`LuauUI/commit` is the scope containing `adapter.setRect` → `applyRect` → the engine
`Position` writes. It is the only scope this round's ordering fix and minimal-write
contract touch.

| | hosted | unhosted | delta | per frame |
|---|---:|---:|---:|---:|
| N=20 (120 leaves) | 1.9539 ms/occ | 2.1426 | **−8.8 %** | −0.266 ms |
| N=100 (600 leaves) | 5.7495 ms/occ | 7.0854 | **−18.9 %** | **−2.046 ms** |

**And it scales the way the handoff note said it must if the mechanism is real.** Over
5× the rows, hosted `commit` grows **2.94×** and unhosted grows **3.31×**. The
falsifiable prediction was that the unhosted arm's cost climbs with row count faster
than the hosted arm's; it does, and the gap widens from 0.27 ms to 2.05 ms per frame.

## 5. THE ENGINE DOES NOT DO LESS WORK — it does the same work in a different place

This is the section that matters most, and it is the one that goes against the round.

The Rendering-context root looks spectacular:

| arm | `Context=Rendering Cause=LuauUI_HostArm` resizes |
|---|---:|
| hosted N=20 | **3** |
| unhosted N=20 | 122 |
| hosted N=100 | **3** |
| unhosted N=100 | 602 |

O(1) against O(N), on the engine's own accounting. **It does not survive totalling.**

| arm | relayouts | updates | resizes |
|---|---:|---:|---:|
| hosted N=20 | 127 | 248 | 247 |
| unhosted N=20 | 125 | 245 | 244 |
| hosted N=100 | 607 | **1808** | 1207 |
| unhosted N=100 | 605 | 1205 | 1204 |

At N=20 the two are within **1.2 %**. At N=100 relayouts and resizes are **the same**
and the hosted arm does **50 % MORE updates**, because a `ScrollView` adds an
`AbsoluteCanvasSize` context of its own. The `Resizes = 3` above is work
**re-attributed to another context, not work removed**.

ADR-0032 §Risks predicted exactly this and should be read as confirmed:

> *"the engine still recomputes every descendant's `AbsolutePosition` in the nested arm
> — that work moves from Luau into C++, it does not vanish."*

**So the round's win is Luau-side, and only Luau-side.** That was always what was
claimed; this is the first evidence that the other half genuinely does not follow.

## 6. The confound, and why these arms cannot answer the obvious question

**`unhosted` removes the `ScrollView` entirely, so the arms differ by more than
hosting.** The evidence is in the table above: `arrange` is **37 % SLOWER** hosted at
N=100 (28.533 vs 20.799 ms/frame), because a scroll host is real layout work — a canvas
extent, a clip, a bar gutter. Total LuauUI cost is **80.4 ms/frame hosted against
72.6 unhosted**: on this workload the hosted surface is **dearer overall**.

That is not a defect in the round's change and it must not be read as one. It means the
arms answer *"what does a `ScrollView` cost?"* at least as much as *"what does hosting
buy?"*, and only the `commit` column isolates the latter.

**The comparison that would price this round's actual change is a different one:** the
same hosted arm, old code against new. The 241→1 write measurement did exactly that in
Studio. Doing it on device needs two builds, and that is the honest next capture — not
another hosted-vs-unhosted pass.

## 7. Two lab defects found by running it

1. **`hostmove1.html` is a zero-frame aggregate** — the fourth such aiming failure in
   this lab's history (`tableUnified.html`, 2026-08-15, was the third). The handoff note
   told the operator to check `arrange=` before dumping and that check did not prevent
   it, because of (2).
2. **The status line flashed too fast to read** (director: *"the line flashes really
   quickly to where it's hard to read"*). The counter-bearing line was written at the
   END of a lap and immediately overwritten by a counter-LESS line at the START of the
   next — and a `host-move` lap is 24 reps, well under a second. The number was present
   and unreadable, which for a human-in-the-loop instrument is the same as absent.
   **Fixed:** the last measured lap's counters now ride the line until the next lap
   replaces them.
3. **The note's licensing reading was wrong.** It said `arrange=24`. The device read
   **27**, because a lap's 24 reps sit on top of the mount and settle solves. The
   reading that licenses a dump is **`arrange` in the twenties**, not exactly 24; the
   reading that means STOP is unchanged — **0 or 1**.
