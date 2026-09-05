# Facet Parity — Plan C ADDENDUM: the lever wave (T12–T17) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Parent plan:** `docs/superpowers/plans/2026-09-03-facet-parity-C.md` (Tasks 0–10). This
file is its ADDENDUM: the build wave the owner ruled for on 2026-09-04 ("if we still
land well above 0.5 and well above vide, we should assess what we're doing poorly and
find other things to optimize"), ranked by
`.superpowers/sdd/2026-09-03-facet-parity-C/task-9b-assessment.md`. It renumbers from
**Task 12** so nothing collides with the parent's 0–10. **Task 10 (C9, closing) still
runs LAST**, after T17.

**Goal:** Remove the one defect that is 93 % of every remaining leaf-edit class — *a
container with one dirty child pays a full pass over all of its children*, paid four
times in four modules — and un-poison the headless instrument that has been hiding it.
`battle_hud` L `updateItem-hp` 1.824 ms Lune / 3.382 ms live → the measured floor of
**0.124 ms Lune / 0.129 ms live**, with every public counter, every rect and every
engine `Position` byte-identical.

**Architecture:** (1) **T12** makes the Lune arena honest: `tests/lib/fake_target`
stops building a formatted string on every `setRect` and stops walking the whole node
map on every coordinate-space host move — three of the campaign's five headline Lune
rows are majority harness and every lever below would otherwise be ranked against
them. (2) **T13–T15** bound the three solve-side container walks — `contentSize`'s
three passes (measure), `stack.arrange`'s pass 1 + placement loop (arrange),
`layout_node.build`'s rebuild child loop (build) — each to the children the dirty set
names, by keeping the per-child facts the container already computed on the container
node, keyed by the SAME `(offer, scope, mStamp)` triple C2 established. (3) **T16**
does the same for the commit's sibling scan, and is PROFILE-GATED on what T13–T15
leave. (4) **T17** attributes the live-only 1.5 ms that no headless lever can touch.

**Tech Stack:** unchanged from the parent — Luau under Lune 0.10.4, stylua,
`tools/test.sh`, `tools/verify.sh affected --jobs 1`,
`python3 tools/check_source_size.py`, `python3 tools/commit_isolated.py`;
`tests/lib/fake_target.luau` is the headless render target; FacetBench (`../FacetBench`,
`main` at `af4f519`) is the arena; RascalRally
(`../../../games/RascalRally/code`) is the production consumer.

**Spec:** `docs/superpowers/specs/2026-09-03-facet-parity-design.md` remains the
authority for behaviour (nothing here changes behaviour). The MEASUREMENT authority for
this wave is `.superpowers/sdd/2026-09-03-facet-parity-C/task-9b-assessment.md` §2, §3,
§6 — every gate, counter and expected number below is read off it, and §6's lever
letters map to tasks as L2→T12, L1a→T13, L1b→T14, L1c→T15, L1d→T16, L3→T17.

**Line numbers below are at `09d2dfcc` and DRIFT as tasks land — locate by the quoted
symbol or comment, never by number.**

## Task 11 — CLOSED-SUBSUMED (ruling A-1)

**Task 11 (`stack.luau` pass 1, `deps.measureIfDirty`) is closed without being built.**
T7's fix round booked it at "8.3–21.6 % of every `battle_hud` update class" off a
`profile.span("StackPass1")` reading. T9b built the working prototype — a `measureFast`
that answers from the node's `mA*`/`mB*` slots without entering `measure` at all (no
`measureCalls` bump, no `ctx.offers` writes, no verdict replay, no `record`) — and
measured it **ABBA**: measure entries `2,221 → 1,118`, and the clock moved
`battle_hud` L `updateItem-hp` **1.824 → 1.729 ms (−5.2 %)**, `setState` −4.5 %,
`addItem-damage` −4.0 %. The booked gate measured the *whole* of pass 1, including the
work that has to happen; the lever is only the call overhead and it is ~0.095 ms.

**It is subsumed by Task 14.** If pass 1 stops looping over clean children at all, the
call it would have made does not exist. Task 14 carries T11's one real finding forward:
a fast path that skips `measure` also skips the two `ctx.offers` writes, and
`ctx.offers` feeds the `offerW`/`offerH` of an entry literal — so a child that is
arrange-dirty but measure-clean would record a `nil` offer and **disarm both anchor
arms next frame** (the same self-disarming-cache class T7 booked as finding 2). T14
step 4 owes that channel a verdict.

---

## Global Constraints (inherited from the parent plan; the deltas are marked ▲)

- Facet repo `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`, branch **`facet-parity`**. Commits via `python3 tools/commit_isolated.py -m <msgfile> <path[:marker]>` (`--dry-run` first); **never amend; nothing merged or pushed** (the branch menu is Task 10's).
- Gates on EVERY Facet commit, FOREGROUND, one lune process at a time: `tools/test.sh` (full); `tools/verify.sh affected --jobs 1` BEFORE committing; `python3 tools/check_source_size.py`; `stylua --check src tests tools bench examples`. After any file EXTRACTION also run `python3 tools/check_brand_drift.py` by hand.
- **RascalRally lockstep on every Facet `src/` change:** `cd games/RascalRally/code && ./run-tests.sh 2>&1 | tee <transcript>` green at or above the recorded base count (T9 closed at **8,452/0** Facet, **3,591/0** RR), plus the rider spec the task names.
- **Source cap.** At `09d2dfcc`: `renderer.luau` **195,709** (4,291 to the cap), `row_actions.luau` 195,427, `table.luau` 191,789, `solver.luau` **190,112** (9,888). The campaign STOP line is **197,500**. ▲ Budgets for this wave, measured AFTER stylua and recorded in the ledger at each task's gate: **T13 ≤ +4,000** on `solver.luau` (the only task competing for that headroom — if it will not fit, the `stack_measure.luau` seam is taken FIRST in its own commit, T13 step 0); T14 `stack.luau` (21,399) and T15 `layout_node.luau` (96,496) and T16 `commit_walks.luau` (87,667) have **no cap constraint**; **no task in this wave may touch `renderer.luau` by more than +200 chars.**
- **No public API or behaviour change.** ▲ Additionally: **no public COUNTER may move except the ones each task names in its Interfaces block**, and a task that moves one re-records every pin on it — Facet AND RascalRally — in the SAME commit.
- **Counters, never wall-time.** Every demonstrator pins a counter AND `solves=N` for its drive (0 stated when the drive caused none); `scene.new()` → ONE discarded warm-up tick → the measured tick; pin idiom `` expect(`name={actual}`).toBe(`name={expected}`) ``; a "currently N" number is READ OFF THE RUN at HEAD with a throwaway probe before it is written into a spec (the T2 lesson).
- **Differential oracle** after every driver step, on the fake adapter, all 9 `device_views.VIEWS` incl. `narrow-portrait` 320x640: `scene.snapshot()` (engine `presentedPosition`/`presentedSize`, focus triple, per-path `controller.rectOf`/`screenRectOf`) byte-equal to the full-solve arm `c` (`{ measureReuse = false, incremental = false }`). There is no `controller.refresh({ full = true })` and this wave adds none. Copy the non-vacuity guard and the "`b`/`d` DRIVEN every step, COMPARED selectively" rule verbatim.
- **A fast path that skips a function owes a LIST of everything that function published** (the T9 lesson). T13, T14, T15 and T16 each write that list into their spec header and the ledger BEFORE code, with a per-channel verdict: served / gated / stated-unreachable.
- ▲ **The T9 lesson, restated as this wave's first step in every task: the OWED LIST comes before the red test, and the red test's number is READ OFF A RUN, never predicted.** T8's whole reorder regression was a counter that fell 8x while the class did not follow; T5's `findNode` was a 2.4x live regression under 8,365 green cases. **Every task in this wave runs `attr` before it commits** (the standing rule T5 booked and no task has yet obeyed).
- ▲ **Three measurement arms, every task, ABBA where the claim is milliseconds.** **A** = a detached worktree at the task's parent SHA (`git worktree add ../Facet-T<N-1> <sha>`, recorded); **B** = HEAD with the change; **C** = HEAD with the change's COUNTER only and its mechanism disabled by one flag, so a seam or a counter that costs something is visible (T8 measured `scanCount += 1` alone at +0.7–2.6 %). Machine contention invalidates a two-arm read — T7 proved it — so A/B/B/A interleaved, medians of ≥2 per arm.
- Spec discovery is the hand-kept require list in `tests/run.luau` — **every new spec is added there** (and considered for `tests/lib/tiers.luau`'s exclusions if it is a device-matrix oracle).
- `commit_walks.skip` compares ENTRY TABLE IDENTITY; rects are `table.freeze`d — never mutate a rect in place.
- Fresh-context adversarial review per task (the SDD task review), ≤5 fix rounds, rulings in `.superpowers/sdd/2026-09-03-facet-parity-C/progress.md`; RED-TEAM at Task 10.
- ▲ **Another agent may hold uncommitted `src/` edits in the shared tree** (T9's reviewer held `render_stats.luau`, `z_order.luau`, `zorder_bounded.spec.luau` at the time this plan was written). `commit_isolated.py` stages only the named path — **name paths explicitly, never `git add -A`, and re-check your own edits are still present after every long-running command** (the T6/T7 shared-tree hazard).

## Rulings made while writing this addendum

| # | Ruling | Why |
|---|---|---|
| A-1 | **Task 11 is CLOSED-SUBSUMED, not deferred.** | Measured at −5.2 % against a booked 8–22 %, and Task 14 removes the call site entirely. Shipping both would be one commit's worth of risk for a gain the next commit deletes. |
| A-2 | **T12 (the harness) goes FIRST, before any product lever.** | `nameplates` L `updateItems-plates` is 23.99 ms Lune of which **21.34 ms is `fake_target.setRect`**; `war_room reorder` is 30.9 ms of which **10.28 ms** is. Ranking T13–T16 against those rows would be ranking against the instrument. It also gives T13–T16 an `attr` baseline whose deltas mean what they say. |
| A-3 | **The three solve-side caches are keyed by C2's triple `(maxW, offerHeightKey(maxH), ctx.scopeKey)` plus `node.mStamp`, and by nothing else.** No new invalidation axis is introduced by this wave. | C2 already proved that triple sound for the child side and the suite pins it (`measure_serve.spec`). A container cache keyed differently is a second invalidation story that can drift from the first; keyed the same, a stamp bump drops both at once. |
| A-4 | **A cached aggregate is PATCHED for a sum and RESCANNED for a max whose argmax shrank.** `mainSum += new - old` is exact in the reals and exact in Luau doubles for the values a layout produces (integers and halves from `roundPx`); `crossMax` keeps its argmax index, is exact on an increase, and falls back to the loop it replaces only when the argmax child's own cross extent DECREASES. | A running max cannot be patched downward without the second-best. Storing second-best is a second thing to keep correct; a rescan on the rare shrink is exact by construction and costs exactly what today costs. |
| A-5 | **Every counter this wave adds is a `last*` snapshot published through `render_stats.publish` from `work`, never a cumulative.** | The wave's counters answer "how many children did this tick touch", which is a per-tick question. T9's `zVisits`/`zPasses` are cumulative for a reason that does not apply here (they must survive a commit re-run the class table cannot see). |
| A-6 | **T16 is PROFILE-GATED and may end as a booking line.** | The sibling scan is 0.089 ms of 1.824 ms today (4.9 %). After T13–T15 remove ~1.7 ms it will be ~0.089 of ~0.15 — a much larger *share* of a much smaller number. The gate is on the ABSOLUTE ms it can return, not the share: build only if `cw.harvest` ≥ 5 % of a leaf-edit class AND ≥ 0.05 ms. T8 already found one unsound version of this index; it earns its risk only on a real number. |
| A-7 | **T17 may deliver an ATTRIBUTION and a booking rather than a fix.** | 1.5 ms of `battle_hud` L live cost sits on a class with ZERO engine writes. If it is engine-side, naming the mechanism with a capture is the whole deliverable and the campaign report says so plainly. If it is `client/text_premeasure`, it is Facet's and it gets a headless pin. |

---

### Task 12 (L2 → FacetBench §C10): the headless target stops being the measurement

**No Facet `src/` file is touched. No public Facet number moves.** This is a test-double
fix whose product gain is zero and whose measurement gain is that the next four tasks
can be believed.

**The two charges, measured (T9b §2.4, §2.6, §6-L2), with the instrument that found them:**

| # | site | cost | evidence |
|---|---|---|---|
| 1 | `tests/lib/fake_target.luau:646` — `table.insert(ops, \`rect {handle.path} {rect.x},{rect.y} {rect.w}x{rect.h}\`)` builds a formatted string on **every** `setRect` | **1.40 µs/write** | `os.clock` brackets inside `rect_pass.applyOne` around `adapter.setRect` alone: `war_room reorder` **10.28 ms over 7,335 calls**, against a `rectPass.apply` span of 12.97 ms and a Facet-side `applyOne` remainder of 2.42 ms (0.33 µs/rect) |
| 2 | `tests/lib/fake_target.luau:657-660` — a coordinate-space host's move iterates the WHOLE `nodes` map with `string.sub(path, 1, #prefix) == prefix` | **O(hosts × nodes)**, 85 µs per host | `os.clock` brackets inside `translate_lane.run`: `nameplates` L `updateItems-plates` `L9.tApply` **21.11 ms over 248 hosts**, of which `adapter.setRect` is **21.34 of the 21.49 ms lane span**; the same class LIVE is **2.876 ms** |

**Files:**
- Modify: `tests/lib/fake_target.luau`
  - `export type Opts` (`:161`) gains `ops: boolean?`; `fake_target.new` (`:163`) binds `local recordOps = (opts ~= nil and opts.ops == true)`.
  - Every `table.insert(ops, …)` site (**21 of them**: `:343`, `:483`, `:646`, `:701`, `:874`, `:958`, `:1030`, `:1039`, `:1101`, `:1111`, `:1147`, `:1184`, `:1257`, `:1419`, `:1453`, `:1464`, `:1528`, `:1570`, `:1711`, `:1838`, and any the scan below finds) goes through ONE local `note(fmt)` that returns immediately when `recordOps` is false — **the interpolation must be inside the guard, not at the call site**, or the string is still built.
  - `adapter.ops()` (`:1047`) asserts when `recordOps` is false, with the message naming `fake_target.new({ ops = true })` — a silent empty list is the failure mode this whole task is about.
  - A `childrenOf` index maintained beside `nodes`, replacing the prefix walk at `:657-660`.
- Modify: every spec that calls `adapter.ops()` / `w.adapter.ops()` — found by `grep -rn "\.ops()" tests/ bench/ examples/` — to construct its target with `{ ops = true }`. Where the target is built by a helper (`tests/lib/world.luau`, `tests/lib/scene*.luau`), the helper takes the flag through.
- Modify: `tests/lib/fake_target_seam.spec.luau` (or the nearest existing fake-target spec; create `tests/fake_target_ops_opt.spec.luau` if none owns this) — the two pins below.
- Create: `tests/fake_target_ops_opt.spec.luau`; register in `tests/run.luau`.

**Interfaces:**
- Consumes: nothing new.
- Produces: `fake_target.Opts.ops: boolean?` (default **false**); `fake_target.new({ ops = true })`; `adapter.ops(): { string }` unchanged in shape, now asserting when unarmed. **No change to `adapter.setRect`'s signature, to `handle.rect` / `handle.storedRect` / `handle.hitRect` / `handle.presentedPosition`, or to `adapter.engineWrites()`.**

- [ ] **Step 1: the owed list, then red.** Write into `tests/fake_target_ops_opt.spec.luau`'s header the list of everything `ops` is read for (grep result, path by path) and the list of everything the prefix walk publishes: `node.rect`, `node.hitRect`, and `adapter._composePresentation(node)`'s outputs (`presentedPosition`, `presentedSize`). Then red:
  - `it("a target built without ops refuses adapter.ops rather than answering empty")` — `expect(function() fake_target.new().ops() end).toThrow()`.
  - `it("a coordinate-space host move recomposes exactly the same descendants by index as by prefix scan")` — build a 3-deep host chain with a sibling subtree that shares a path PREFIX but not a parent (e.g. `/S/Host` and `/S/Host2/Leaf`), move `/S/Host`, and pin `presentedPosition` for every node against a from-scratch `spaceOriginOf` recomputation over all nodes. **This case is the one the index can get wrong and the prefix walk cannot** — `#prefix` matching makes `/S/Host2` a non-match only because of the trailing `/`; an index keyed on the parent path must reproduce that exactly. Read the expected numbers OFF THE RUN at HEAD.
  - The counter pin for the drive: `solves=1` on the mount tick, `solves=0` on the lane-served move (`stats.lastLaneTranslates=1`).

- [ ] **Step 2: the `ops` gate.** In `fake_target.new`:

```luau
	--[[ THE OP LOG IS OPT-IN (Plan C addendum, T12). Every one of the twenty-odd
		`table.insert(ops, …)` sites below interpolates a formatted string, and
		`setRect` is on the commit's hot loop: measured at 1.40 us per write from
		inside `rect_pass.applyOne`, which is 10.28 ms of the 30.9 ms
		`war_room_inventory L reorder` class in FacetBench — a THIRD of a headline
		number spent by the instrument reading it.

		THE INTERPOLATION IS INSIDE THE GUARD, NOT AT THE CALL SITE. `note(\`rect …\`)`
		builds the string and then throws it away; `if recordOps then` around the
		insert is the same. The only shape that does not pay is a guard the caller
		takes BEFORE it composes, which is why every site below reads
		`if recordOps then note(...) end` and why the scan in
		`tests/fake_target_ops_opt.spec.luau` pins exactly that spelling. ]]
	local recordOps = opts ~= nil and (opts :: any).ops == true
	local function note(line: string)
		table.insert(ops, line)
	end
```

  and each site becomes `if recordOps then note(\`rect {handle.path} …\`) end`. The spec
  pins by SOURCE SCAN that **no `table.insert(ops` remains** and that **every `note(`
  call is lexically inside an `if recordOps then`** — a later site added without the
  guard is then a red test, not a silent 1.4 µs.

- [ ] **Step 3: the parent→children index.** Beside `local nodes` (`:164`):

```luau
	--[[ WHO IS DIRECTLY UNDER WHOM (T12). The coordinate-space recompose in `setRect`
		used to find a host's subtree by walking EVERY node in this target and testing
		`string.sub(path, 1, #prefix) == prefix` — O(hosts x nodes) per commit, which on
		FacetBench's `nameplates L` tick is 248 hosts x 1,503 nodes and 21.3 of the
		class's 24.0 ms. The same class LIVE is 2.876 ms; the engine reparents for free
		and this fake was charging Facet for the difference.

		KEYED ON THE PARENT PATH, WHICH IS WHAT THE PREFIX TEST ACTUALLY MEANT. The old
		test matched `prefix = path .. "/"`, so `/S/Host2/Leaf` was NOT under `/S/Host`
		— the trailing separator is the whole of the semantics, and an index keyed on a
		bare prefix would silently widen it. `parentPathOf` cuts at the LAST separator,
		which is the same cut `hostFor` walks. ]]
	local childrenOf: { [string]: { [string]: true } } = {}
	local function parentPathOf(path: string): string?
		local i = #path
		while i > 1 do
			if string.sub(path, i, i) == "/" then
				return string.sub(path, 1, i - 1)
			end
			i -= 1
		end
		return nil
	end
	local function indexNode(path: string)
		local parent = parentPathOf(path)
		if parent == nil then
			return
		end
		local bucket = childrenOf[parent]
		if bucket == nil then
			bucket = {}
			childrenOf[parent] = bucket
		end
		bucket[path] = true
	end
	local function unindexNode(path: string)
		local parent = parentPathOf(path)
		local bucket = if parent ~= nil then childrenOf[parent] else nil
		if bucket ~= nil then
			bucket[path] = nil
			if next(bucket) == nil then
				childrenOf[parent :: string] = nil
			end
		end
		childrenOf[path] = nil
	end
```

  `indexNode` is called wherever `nodes[path] = …` is written (`adapter.create` `:405+`,
  and `adopt`'s re-key `:1030`); `unindexNode` wherever `nodes[path] = nil` is written
  (`remove` `:874`, `discard` `:1039`, `destroyRoot` `:1147`, and `adopt`'s old path).
  **The spec pins by source scan that the two sets of sites are the same size** — an
  unindexed create is a descendant that stops recomposing, which is exactly the silent
  class this task exists to remove.

  Then the walk at `:657-660` becomes a recursion over the index:

```luau
		if selfHost ~= nil and selfHost.hostSpace == true then
			--[[ DEPTH-FIRST OVER THE INDEX, not a scan of the map. Same set, same order
				property that matters (a node is recomposed after every host above it,
				because the recursion descends), same `spaceOriginOf` per node — this
				changes WHICH NODES ARE VISITED, never what is computed for one. ]]
			local function recompose(parentPath: string)
				local bucket = childrenOf[parentPath]
				if bucket == nil then
					return
				end
				for path in bucket do
					local node = nodes[path]
					if node ~= nil and node.storedRect ~= nil then
						local sx, sy = spaceOriginOf(node)
						local st = node.storedRect
						node.rect = if sx == 0 and sy == 0
							then st
							else { x = st.x + sx, y = st.y + sy, w = st.w, h = st.h }
						local sh = node.storedHitRect
						if sh ~= nil then
							node.hitRect = if sx == 0 and sy == 0
								then sh
								else { x = sh.x + sx, y = sh.y + sy, w = sh.w, h = sh.h }
						end
						adapter._composePresentation(node)
					end
					recompose(path)
				end
			end
			recompose(handle.path)
		end
```

  **The one semantic difference to check, and it is the reason step 1's fixture exists:**
  the old walk visited every node whose path had the prefix **whether or not its
  intermediate ancestors existed in `nodes`**; the recursion stops at a missing link.
  In this target every mounted node is in `nodes`, and the spec's chain fixture pins it.

- [ ] **Step 4: green + the differential oracle arm.** `tests/fake_target_ops_opt.spec.luau` green. Then the standing oracle: `host_space_oracle` (6 fixtures), `translate_arm`'s O3 oracle, `measure_split` / `measure_reuse` / `rect_cow` / `node_reuse`, and `tests/host_move_write_cost.spec.luau` — **all of them run on this adapter, so all of them are this task's oracle**, over all 9 `device_views.VIEWS` including `narrow-portrait` 320x640. Arm `c` (`{ measureReuse = false, incremental = false }`) must stay byte-equal, non-vacuity guard in place.

- [ ] **Step 5: the mutation (Step-7 discipline).** Three mutations, each must BITE:
  1. Drop the trailing `/` semantics — key `childrenOf` on a bare prefix — must redden the `/S/Host2/Leaf` case.
  2. Remove one `unindexNode` call site — must redden a remove-then-move fixture (a stale bucket entry recomposes a dead node).
  3. Hoist an interpolation outside its `if recordOps` — must redden the source-scan pin.
  Record which mutation reddened which case in the ledger; a mutation that does not bite means the case is not a witness.

- [ ] **Step 6: gates + measurement + commit.** `tools/test.sh` full (≥ 8,452/0), `tools/verify.sh affected --jobs 1`, `stylua --check`, `check_source_size` (no `src/` change, so this is an attestation), RR `./run-tests.sh` (≥ 3,591/0 — **RR consumes `Facet/src` and not `Facet/tests`, so RR must be unaffected; if it moves, something is wrong**). Measurement, three arms as the Global Constraints define, `lune run tools/profile/attr <wl> L 3` from the FacetBench scratch pair:

  | class | before (Lune) | **expected after** | live, unchanged |
  |---|---:|---:|---:|
  | `nameplates L updateItems-plates` | 23.99 | **~2.6** | 2.876 |
  | `war_room_inventory L reorder` | 29.3 | **~19** | — |
  | `war_room_inventory L removeItem-items` | 15.2 | **~10.3** | — |
  | `killfeed_nameplates L addItem-feed` | 2.108 | ~1.0 | — |
  | `battle_hud L updateItem-hp` | 1.824 | **1.824 (± noise — 4 writes)** | 3.382 |

  **The `battle_hud L updateItem-hp` row is the control**: it writes 4 rects and moves no
  host, so this task must NOT move it. A change there means the `ops` guard cost
  something. Commit `T12: the headless target's op log is opt-in and a host move walks an index, not the map (C10)`.

- [ ] **Step 7: FacetBench §C10.** Write `../FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` **§C10 — the instrument was a third of the reading**: the two charges with their `os.clock` evidence, the before/after `attr` table above, the live row that agreed with the fixed number all along (2.876), and the standing rule this makes enforceable — *a Lune class number is only comparable to a live one once the harness share is under 5 %*. Commit in FacetBench separately.

---

### Task 13 (L1a → FacetBench §C11): `contentSize` keeps its container's aggregate

**The gate is already met and is not re-derived:** `span:Facet/measure` is **1.038 ms of
1.824 ms (57 %)** on `battle_hud` L `updateItem-hp`, **1.534 of 2.579 (59 %)** on
`war_room setState`, **0.213 of 0.476 (45 %)** on `killfeed` hp. The mechanism is
`contentSize`'s vstack/hstack branch making **three full passes over the children** —
PASS 1 (`solver.luau:1370-1386`), the fill pass (`:1471-1485`), and the `crossMax` loop
(`:1486-1489`) — plus `crossOf` and `marginMain` allocated fresh per call
(`:1356-1357`). Counters at HEAD, `battle_hud` L `updateItem-hp`: `lastMeasureCalls`
**2,221**, `lastMeasureServed` **2,206**, `lastMeasured` **6**, `lastLayoutNodes` 5,127.

**THE OWED LIST — what a skipped child's `measure` would have published, written into
`tests/container_aggregate.spec.luau`'s header AND the ledger BEFORE code** (the T9
lesson's rule 1). This is NOT C2's eleven-row table over again: C2 answered "may this
CHILD be served"; T13 asks "may this PARENT skip asking". Every row below is a thing
`measure(ctx, child, …)` does that not calling it would lose:

| # | channel | site | verdict |
|---|---|---|---|
| 1 | `ctx.offers[child.wKey]` / `[child.hKey]` | `solver.luau:1758-1759` (serve) and `record` | **SERVED** — T13 writes both from the offer in hand, exactly as the serve does. **This is T11's finding and it is not optional**: a child that is arrange-dirty but measure-clean whose entry literal is rebuilt reads `ctx.offers` for `offerW`/`offerH`, and a `nil` there disarms both anchor arms for the life of the surface (T7 finding 2) |
| 2 | `ctx.textStates` / `ctx.compact` / `ctx.textFacts` for the child | serve `:1766-1770` | **SERVED** — from the child's own `mA*`/`mB*` slot, the same values the serve replays, branched on `kind == "text" or kind == "composition"` exactly as the serve branches |
| 3 | `ctx.fitCuts += scuts` | serve `:1771` | **SERVED** — the child's recorded cuts, added the same way |
| 4 | `record(ctx, child, …)`'s slot refresh | `:1553+` | **STATED-UNREACHABLE** — the recorder rewrites the slot the answer came from; a skipped child's slot is already that value. The `mStamp` axis is shared and is checked by the gate below |
| 5 | `ctx.compositions` / `ctx.hasScroll` / `armContainer` / `ctx.boundary` / the adopted-slate diagnostics | the C2 table's rows 4–8 | **GATED** — by the IDENTICAL gate C2 uses, asked of the child: `subtreeHasScroll`, `subtreeHasComposition`, `containerRelativeInside`, `ctx.analyze`, `ctx.measureQuiet`. A container whose cache holds a child that would fail any of those never caches at all (step 3's `cacheable` latch) |
| 6 | `ctx.mdepth` / `ctx.deepNesting` | `measureUncached` | **BALANCED BY CONSTRUCTION, stated** — the child is not entered, so nothing is pushed and nothing is owed; `deepNesting` is a perf latch a later slow path re-arms |

**Files:**
- Modify: `src/layout/solver.luau`
  - `contentSize`'s vstack/hstack branch (`:1355-1496`): the aggregate cache, PASS 1's patch arm, the `crossMax` argmax.
  - The `Node` type comment beside C2's slot fields: six new container fields (below).
  - `Ctx` + the `work` record (`:3514+`): `childVisits`.
- Modify: `src/render/render_stats.luau` (`publish`): `stats.lastChildVisits = work.childVisits or 0`. **≤ 9 lines; `renderer.luau` is NOT touched** (T8's precedent — the publish block already lives in `render_stats`).
- Create: `tests/container_aggregate.spec.luau`; register in `tests/run.luau`. Consider `tiers.SLOW` if it runs the 9-view oracle over more than 3 fixtures (`measure_serve.spec` is already a candidate; do not add a second silent 350 s).
- Modify: `tests/measure_serve.spec.luau`, `tests/measure_split.spec.luau`, `tests/nameplates_baseline.spec.luau`, `tests/translate_arm.spec.luau`, `tests/anchor_arrange.spec.luau` — every `lastMeasureCalls` / `lastMeasureServed` / caster-tick term pin, re-recorded from a run.
- Modify (RR): `tests/facet_measure_fanout_contract.spec.luau` — the fanout literals and the two accounting identities. **Same commit.**
- **Step 0 (conditional): the seam.** `check_source_size` says `solver.luau` is 190,112 with 9,888 to the cap. If the change measures over **+4,000 after stylua**, STOP and take the seam FIRST in its own commit: `src/layout/stack_measure.luau` carrying the whole vstack/hstack branch of `contentSize` (`:1355-1496`, ~7,500 chars) as `stackMeasure.contentSize(deps, ctx, node, isH, children, n, innerMaxW, innerMaxH, gap, pt, pr, pb, pl) -> (number, number)`. Its Deps are the five `stack.luau` already takes (`measure`, `dim`, `sides`, `mainDimOf`, `shrink`) — so it passes the one-way test — plus `memoPlan` is NOT needed. Give it `tests/stack_measure_seam.spec.luau` modelled line-for-line on `tests/stack_seam.spec.luau`: `fieldsRead(src, "ctx")` a CLOSED set, and the read-vs-write half asserting it assigns no field of `ctx`/`node`/`child`/`deps`. Run `python3 tools/check_brand_drift.py` by hand after the extraction.

**Interfaces:**
- Consumes: `ctx.reuse.measureContains` (the measure half of the dirty closure, ancestor-closed); `ctx.scopeKey`; `ctx.measureStamp`; `offerHeightKey(ctx, node, maxH)`; the child's C2 slots `mStamp`, `mAOfferW/mAOfferH/mAScope/mAW/mAH/mACuts/mATextState/mACompact/mATextFacts` and the `mB*` twin; `node.subtreeHasScroll`, `node.subtreeHasComposition`, `node.containerRelativeInside`.
- Produces, on the CONTAINER layout `Node` (six fields, all `nil` on a container that has never cached):
  - `Node.aStamp: number?` — the `ctx.measureStamp` the cache was filled at
  - `Node.aOfferW: number?`, `Node.aOfferH: number?`, `Node.aScope: string?` — A-3's triple
  - `Node.aMain: { number }?` — per-child main extent INCLUDING that child's main margins (what PASS 1 adds into `mainSum`), indexed by child index; `nil` at a `fill` child's index
  - `Node.aCross: { number }?` — per-child cross extent including cross margins, the `crossOf` array
  - `Node.aSum: number?`, `Node.aCrossMax: number?`, `Node.aCrossIdx: number?` — the two aggregates and the argmax index
- Produces: `work.childVisits: number` (children a container's own loops touched, summed over the solve) and `stats.lastChildVisits`.
- **Moves (and re-records in the same commit): `lastMeasureCalls`, `lastMeasureServed`.** **Does NOT move: `lastMeasured`, `lastArranged`, `lastRectInserts`, `lastSkipped`, `lastSolveSkipped`, `lastLayoutNodes`, `lastAnchorSkipped`, `rectWrites`, `propWrites`, `engineWrites`, `solves`, `partialSolves`.**

- [ ] **Step 1: the owed list, then red.** Write the six-row table above into the spec header and the ledger. Then `tests/container_aggregate.spec.luau` on `tests/lib/deep_stack_scene.luau` (the 1,000-row world T6 built), warm one tick, then `scene.text(500, "x")`:
  - Pins READ OFF THE RUN at HEAD first, via a throwaway probe: `lastMeasureCalls=<N>`, `lastMeasureServed=<M>`, `lastMeasured=1`, `solves=1`. Expected after: **`lastChildVisits` falls from `<N>`-ish to ≤ 12** and `lastMeasured` is **unchanged at 1**.
  - `it("a viewport change caches nothing and serves nothing")` — `env:set` drive, `lastChildVisits` equals the full walk, `solves=1`, no `reuse`.
  - `it("a width write on the container itself refills the cache at the new offer")` — the triple moved, so the cache misses by key, not by dirt.
  - One case per GATED row (5): a container with a `ScrollView` child, with a `Composition` child, with a `containerRelative` child, an `analyze` solve, a non-quiet solve — each pins `lastChildVisits` at the FULL walk (the cache refuses) and `controller.compositionAt` still answers for the composition fixture.
  - `it("the offer channel survives a skipped child")` — the T11/T7 case: a child that is arrange-dirty but measure-clean, whose entry literal IS rebuilt, must carry a non-nil `offerW`/`offerH`; drive it and pin `lastAnchorSkipped` on the NEXT frame at its HEAD value. **This is the case that fails silently for the life of a surface if step 3 forgets row 1.**

- [ ] **Step 2: the counter, alone (arm C).** Add `ctx.childVisits`, the `work` field and the `render_stats` publish, with **no mechanism**. Measure it (T8 measured a bare `scanCount += 1` at +0.7–2.6 % because `skip` ran 9,040×/step; `childVisits += 1` will run ~2,200×/step here). If arm C is distinguishable from arm A, the increment moves to a per-LOOP `+= n` rather than per-child, and the spec's pin is written against that. Record the arm-C number in the ledger either way.

- [ ] **Step 3: the mechanism.** In `contentSize`'s vstack/hstack branch, replacing `:1355-1357` and wrapping PASS 1:

```luau
	--[[ THE CONTAINER'S OWN AGGREGATE, KEPT (Plan C addendum, T13 — ruling A-3/A-4).
		This branch used to recompute a stack's content size from scratch on every
		measure: PASS 1 over every child, the fill pass over the rest, and a third loop
		for `crossMax` — plus two fresh tables. On `battle_hud L` a ONE-LEAF write
		measured 6 nodes and entered `measure` 2,221 times, 2,206 of which C2 answered
		from the child's own slots in 0.47 us each. C2 made the ANSWER cheap; it could
		not make the PARENT'S LOOP shorter, and the loop is 57 % of the class.

		SO THE PARENT KEEPS WHAT IT COMPUTED. `aMain[idx]` and `aCross[idx]` are the two
		per-child numbers PASS 1 derives, `aSum` and `aCrossMax`/`aCrossIdx` the two
		aggregates. Keyed by C2's OWN triple plus its stamp (ruling A-3) so a stamp bump
		drops the container's cache and its children's slots together and there is not a
		second invalidation story to keep in step.

		THE PATCH IS EXACT, NOT APPROXIMATE (ruling A-4). A sum patches both ways:
		`aSum += new - old`. A MAX patches upward only, so `aCrossIdx` records who owns
		it and a shrink AT the argmax falls back to the very loop this replaces — exact
		by construction, and it costs what today costs on the rare frame it happens.

		AND THE GATE IS C2'S GATE, ASKED OF THE CHILDREN. A container may cache only if
		every child it would skip is one C2 would have served: no scroll, no
		composition, no container-relative dim, not analysing, quiet. `cacheable` goes
		false at the first child that fails and the container then behaves exactly as it
		does today, forever, at that offer. ]]
	local mainSum, fillWeightSum = 0, 0
	local scope = ctx.scopeKey
	local aOfferH = offerHeightKey(ctx, node, if isH then innerMaxH else innerMaxW)
	local reuse = ctx.reuse
	local dirty = if reuse ~= nil then reuse.measureContains else nil
	local hit = reuse ~= nil
		and dirty ~= nil
		and ctx.measureQuiet
		and not ctx.analyze
		and node.aStamp == ctx.measureStamp
		and node.aScope == scope
		and node.aOfferW == innerMaxW
		and node.aOfferH == aOfferH
	local crossOf: { [number]: number }
	local marginMain: { [number]: number }
	if hit then
		crossOf = node.aCross :: { [number]: number }
		marginMain = node.aMargin :: { [number]: number }
		mainSum = node.aSum :: number
	else
		crossOf = {}
		marginMain = {}
		node.aMain, node.aCross, node.aMargin = {}, crossOf, marginMain
	end
	local aMain = node.aMain :: { [number]: number }
	local cacheable = true
	local shrinkBasis: { [number]: number }? = nil
	-- PASS 1: children with a definite main extent measure against the whole
	-- inner box, and consume it. On a HIT, only the children `measureContains`
	-- names are re-asked; every other index keeps the number it contributed.
	for idx, child in children do
		local childMainDim = dim(child, if isH then "w" else "h")
		if childMainDim.type == "fill" then
			fillWeightSum += childMainDim.weight or 1
			continue
		end
		if
			hit
			and dirty[child.id] ~= true
			and aMain[idx] ~= nil
			and child.subtreeHasScroll ~= true
			and child.subtreeHasComposition ~= true
			and child.containerRelativeInside ~= true
		then
			--[[ THE SKIP, AND THE THREE CHANNELS IT OWES (the owed list, rows 1-3).
				`measure` was not called, so nothing it publishes has been published —
				and the entry literal of a child that is ARRANGE-dirty but
				MEASURE-clean reads `ctx.offers` for its `offerW`/`offerH`. A nil there
				disarms BOTH anchor arms for the life of the surface (T7 finding 2), so
				this is not bookkeeping. ]]
			ctx.offers[child.wKey or (child.id .. "|w")] = innerMaxW
			ctx.offers[child.hKey or (child.id .. "|h")] = innerMaxH
			local kind = child.kind
			if kind == "text" or kind == "composition" then
				local sameA = child.mAOfferW == innerMaxW and child.mAScope == scope
				ctx.textStates[child.id] = if sameA then child.mATextState else child.mBTextState
				ctx.compact[child.id] = if sameA then child.mACompact else child.mBCompact
				ctx.textFacts[child.id] = if sameA then child.mATextFacts else child.mBTextFacts
			end
			ctx.fitCuts += (if child.mAOfferW == innerMaxW then child.mACuts else child.mBCuts) or 0
			mainSum += 0 -- already in `aSum`; stated so the two arms read alike
			continue
		end
		cacheable = cacheable
			and child.subtreeHasScroll ~= true
			and child.subtreeHasComposition ~= true
			and child.containerRelativeInside ~= true
		ctx.childVisits += 1
		local mt, mr, mb, ml = sides(child.margin)
		marginMain[idx] = if isH then ml + mr else mt + mb
		local cw, ch = measure(ctx, child, innerMaxW, innerMaxH)
		local mainContribution = if isH then cw + ml + mr else ch + mt + mb
		local previous = aMain[idx]
		aMain[idx] = mainContribution
		if hit and previous ~= nil then
			mainSum += mainContribution - previous -- ruling A-4: exact both ways
		else
			mainSum += mainContribution
		end
		crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
		if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
			local basis = shrinkBasis or {}
			basis[idx] = if isH then cw else ch
			shrinkBasis = basis
		end
	end
```

  …the shrink pass (PASS 1.5), the fill pass and the diagnostics are UNCHANGED — the
  fill pass already `continue`s on `crossOf[idx] ~= nil`, and on a hit that array is
  populated, so it re-measures exactly the `fill` children it re-measures today. The
  `crossMax` loop becomes:

```luau
	--[[ THE MAX, PATCHED UPWARD AND RESCANNED DOWNWARD (ruling A-4). A running max has
		no inverse: if the child that OWNED it just got smaller, the new max is
		somebody else's and only a scan knows whose. So the argmax rides with the
		value, an increase is one compare, and a decrease at the argmax costs exactly
		the loop this replaces — on the frame it happens, which is rare and which the
		spec drives on purpose (`it("a shrink at the argmax rescans")`). ]]
	local crossMax, crossIdx = 0, 0
	if hit and node.aCrossIdx ~= nil and crossOf[node.aCrossIdx] == node.aCrossMax then
		crossMax, crossIdx = node.aCrossMax :: number, node.aCrossIdx :: number
		for idx in touchedThisPass do
			local v = crossOf[idx] or 0
			if v > crossMax then
				crossMax, crossIdx = v, idx
			end
		end
	else
		for idx = 1, n do
			local v = crossOf[idx] or 0
			if v > crossMax then
				crossMax, crossIdx = v, idx
			end
		end
	end
	if cacheable and reuse ~= nil then
		node.aStamp, node.aScope, node.aOfferW, node.aOfferH = ctx.measureStamp, scope, innerMaxW, aOfferH
		node.aSum, node.aCrossMax, node.aCrossIdx = mainSum, crossMax, crossIdx
	else
		node.aStamp = nil
	end
```

  `touchedThisPass` is a small array appended in PASS 1's non-skip arm and in the fill
  pass — **not a third table per call**: hoist it onto the ctx as a reusable scratch
  (`ctx.aTouched`, `table.clear`ed at the top of the branch) so a container that hits
  allocates NOTHING. **`node.aStamp = nil` on the uncacheable arm is load-bearing**: a
  container that once cached and then gained a scroll child must not keep a stale hit.

- [ ] **Step 4: L5 (`ctx.offers`) — fold in ONLY if the budget allows.** T9b §6-L5: `ctx.offers` is a per-solve table that grows to 2 × `measureServed` (~4,500 entries/tick on `battle_hud` L) with a `child.id .. "|w"` concat on any node without a cached `wKey`. **Its measured time gain is ~zero** (T9b arm 4's null result: −16.6 % allocation bought 0 % clock), so it is worth doing only as a rider inside a round already editing `solve_ctx`. **If `check_source_size` shows T13 landing above +3,200 after stylua, SKIP it and re-book.** If it goes in: move the pair onto the node beside the C2 slots (`node.oW`, `node.oH`, stamped with `mStamp`), and change the single in-solve reader — the entry literal's `offerW = ctx.offers[node.wKey or (node.id .. "|w")]` in `arrangeBody` — to read the node. Nothing else reads `ctx.offers` (T7's second NULL mutation established that, and it is why this is a rider and not a task).

- [ ] **Step 5: green + the differential oracle arm.** `container_aggregate.spec` green. Then, on the fake adapter, over all **9** `device_views.VIEWS` incl. `narrow-portrait` 320x640, three drives (text write, width write, viewport change) on **three** fixtures — `deep_stack_scene`, a nested-stack fixture, and one with a `fill` child and a `shrinkWeight` child — with `scene.snapshot()` byte-equal to arm `c` (`{ measureReuse = false, incremental = false }`), non-vacuity guard in place, `b`/`d` DRIVEN every step and COMPARED selectively. **Plus the public reader pin: `controller.compositionAt` compared on the composition fixture** (C2's row-4 precedent). Then the standing suites that already compare against arm `c`: `host_space_oracle`, `translate_arm`, `measure_split`, `measure_reuse`, `rect_cow`, `node_reuse`, `anchor_skip`.

- [ ] **Step 6: the mutation (Step-7 discipline).** Each must BITE, each recorded:
  1. `mainSum += mainContribution` instead of the delta on the hit arm → a wrong content height on the second write to the same row.
  2. Drop the `aCrossIdx == argmax` guard (patch the max unconditionally) → redden `it("a shrink at the argmax rescans")`.
  3. Drop the `ctx.offers` writes in the skip arm → redden the T7-finding-2 case from step 1.
  4. Drop `node.aStamp = nil` on the uncacheable arm → redden the ScrollView-arrives-later case.
  5. Widen the gate by removing `child.containerRelativeInside ~= true` → must redden the container-relative case (**if it does NOT, record the null exactly as T6/T7 recorded theirs and KEEP the term with the null stated at both sites** — C2's own `containerRelativeInside` term is a known null for a reason that may or may not extend here).

- [ ] **Step 7: gates, RR, measurement, commit.** `tools/test.sh` full; `tools/verify.sh affected --jobs 1`; `stylua --check`; `python3 tools/check_source_size.py` **and record the new `solver.luau` size in `tools/lune/verify/data/source-cap-ledger.md`**; RR `./run-tests.sh` with `facet_measure_fanout_contract` re-recorded IN THIS COMMIT. Measurement, three arms (A = worktree at T12's SHA, B = HEAD, C = counter-only from step 2), ABBA, `attr <wl> L 3`:

  | class | before (post-T12) | **expected after** |
  |---|---:|---:|
  | `battle_hud L updateItem-hp` | 1.824 | **~0.79** (−1.04) |
  | `battle_hud L setState` | 1.927 | ~0.89 |
  | `war_room_inventory L setState` | 2.579 | **~1.05** (−1.53) |
  | `killfeed_nameplates L updateItem-hp` | 0.520 | **~0.29** (−0.23) |
  | `war_room_inventory L reorder` (post-T12 ~19) | ~19 | ~17 (−2.06) |
  | `nameplates L updateItem-hp` | 0.006 | **0.006 (control — anchored, no stack loop)** |

  Commit `T13: a stack keeps its own aggregate and re-asks only the children the dirty set names (C11)`.

- [ ] **Step 8: FacetBench §C11.** Write §C11 — the mechanism in one paragraph, the counter table (`lastChildVisits` before/after, `lastMeasured` unmoved), the three-arm ms table, the arm-C number for the counter alone, and the honest statement of what did NOT move and why (`nameplates`, because C3's anchor skip already meant no container loop ran there). Commit in FacetBench separately.

---

### Task 14 (L1b → FacetBench §C12): `stack.arrange` replays its own placement

**The gate is met:** `span:Facet/arrange` is **0.612 ms of 1.824 (34 %)** on
`battle_hud` L `updateItem-hp`, **0.809 of 2.579 (31 %)** on `war_room setState`,
**0.186 of 0.476 (39 %)** on `killfeed` hp. Counters at HEAD, `battle_hud` L hp:
`arrangeBody` entered **1,109** times of which **1,104** take the early skip and **5**
run a body; `lastArranged` 5, `lastRectInserts` 5, `engineWrites` 4.

**Measured evidence that the lever is real, and the shape of its failure.** T9b built a
crude ceiling arm of exactly this design — replay the previous placement when every
dirty child measures to the size it already had — and ran it ABBA:
`battle_hud setState` **1.822 → 1.535 (−16 %)**, `removeItem-damage` **2.505 → 1.403
(−44 %)**. It did **not** fire on `updateItem-hp`, and the reason is the design note this
task must not repeat: **the arm compared a child's MEASURED size to its PLACED rect**,
which differ for a `fill` child (the placement loop resolves the main extent from
`fillPx`, not from `desired`). **The compare is measured-to-measured**, which is what
`aMain` from T13 already is.

**THE OWED LIST — what a skipped child's placement would have published** (spec header +
ledger, before code):

| # | channel | site | verdict |
|---|---|---|---|
| 1 | `place(ctx, child, childRect, out)` → `arrangeBody`'s entry write | `stack.luau:438` | **SERVED by not needing to be** — the child's entry in `out` IS the previous solve's entry (`out` is `reuse.previous.rects`), and a replayed child's rect is unchanged, so the entry already describes it. This is `arrangeBody`'s own skip argument, one level up |
| 2 | `noteContainment(ctx, node, child, childRect, innerX, innerY, innerW, innerH, not isH)` | `stack.luau:437` | **REPLAYED** — a containment finding is a `ctx.diagnostics` entry, and a skipped child files none. Solve-level replay of a skipped subtree's diagnostics already exists (`solver.solve`'s `ctx.skipped > 0 or ctx.translated > 0` arm); this task extends the SAME replay to a replayed stack child, or the finding silently disappears for exactly the parts of the screen that did not change |
| 3 | the overflow diagnostic + the shrink `clipMain` | `stack.luau:259-271` | **STATED-UNREACHABLE on the replay arm** — the replay requires `availMain` unchanged, which requires `mainSum` and the inner box unchanged, so the branch's condition (`availMain < 0`) has the value it had; if the previous arrange filed the finding it is in `ctx.diagnostics` via row 2's replay |
| 4 | `ctx.walkedIds[child.id]` | `arrangeBody`, on the `reuse ~= nil` arm | **NOT SERVED, stated** — a replayed child was not walked, which is exactly what the flag means; `solve`'s diagnostic replay reads it and this is the population it was built for |
| 5 | `ctx.arranged`, `ctx.rectInserts` | `arrangeBody:2407-2408` | **NOT SERVED, and that is the ACCEPTANCE TEST** — `work.skipped` is derived by subtraction from these, and `lastArranged`/`lastRectInserts` must not move. A replayed child was already not counted (it took `arrangeBody`'s early skip); this task removes the CALL, not the count |
| 6 | `deps.measure(ctx, child, …)` in pass 1 | `stack.luau:144` | **SERVED from `aMain`** — T13's per-child array is the same number pass 1 computes, at the same offer, under the same key |

**Files:**
- **Step 0 (its own commit, per ruling T7-3): widen `tests/stack_seam.spec.luau:163`'s read-set deliberately.** The replay reads `ctx.reuse` and writes nothing new, so `fieldsRead(stackSrc, "ctx")` goes `{ "diagnostics", "hiddenDepth" }` → `{ "aTouched", "diagnostics", "hiddenDepth", "reuse" }` (exact set read off the run), and the read-vs-write half must still assert the module assigns no field of `ctx`/`node`/`child`/`deps`. **Commit the widening ALONE, with its reasoning, before any behaviour change** — T7's ruling exists because a read-set that widens inside a behaviour commit stops being a check.
- Modify: `src/layout/stack.luau` — `stackLib.arrange`'s prologue (the replay), pass 1's measure call (reads `aMain`), and the placement loop's prefix rebase.
- Modify: `src/layout/solver.luau` — `Node` gains the placement half of the cache (below); `ctx.arrangeEntries`; `work.arrangeEntries`. **`arrangeBody` is NOT restructured** — the replay is entirely inside `stack.arrange`, above the point where it would call `place`.
- Modify: `src/render/render_stats.luau` — `stats.lastArrangeEntries`.
- Create: `tests/stack_replay.spec.luau`; register.
- Modify (RR): `tests/facet_anchor_arrange.spec.luau` if and only if a counter it pins moves — **it should not**, and that is a pin, not a hope.

**Interfaces:**
- Consumes: `reuse.dirtyContains` (the FULL dirty closure, ancestor-closed — not the measure half); T13's `Node.aMain`; `out[child.id].rect` (the previous solve's frozen rect).
- Produces, on the CONTAINER layout `Node`: `Node.pInnerX/pInnerY/pInnerW/pInnerH: number?` (the inner box the placement was computed for) and `Node.pRect: { [number]: any }?` (per-child index → the frozen rect it was placed at). `Node.pStamp` is NOT needed — the inner box quadruple plus `aMain` identity is the key.
- Produces: `work.arrangeEntries` / `stats.lastArrangeEntries` — **1,109 → ≤ 10** on `battle_hud` L `updateItem-hp`.
- **Must NOT move: `lastArranged`, `lastRectInserts`, `lastSkipped`, `lastSolveSkipped`, `rectWrites`, `propWrites`, `engineWrites`, `lastAnchorSkipped`, `lastTranslated`, `lastCommitVisits`, `solves`.**

- [ ] **Step 1: the owed list, then red.** Table above into the spec header and the ledger. Then `tests/stack_replay.spec.luau` on `deep_stack_scene`, warm, `scene.text(500, "x")`:
  - Pins read off the run: `lastArrangeEntries=<1109-ish>` at HEAD → **≤ 10** after; `lastArranged`, `lastRectInserts`, `rectWrites`, `engineWrites` at their HEAD values, unchanged, in the SAME assertion block; `solves=1`.
  - `it("a row that CHANGES height shifts every later row and no earlier one")` — `scene.height(500, +12)`; pin that the rects of rows 0–499 are the SAME TABLES (identity) and rows 501–999 moved by exactly 12. **This is the prefix-rebase witness.**
  - `it("a FILL child is compared measured-to-measured, not against its placed rect")` — the fixture that broke T9b's ceiling arm: a stack with one `fill` child and one dirty sibling; the replay must FIRE (it did not in the crude arm).
  - `it("a containment finding survives a replayed child")` — a child that overflows its parent, replayed; `controller.diagnostics()` still reports it (row 2).
  - `it("a viewport change replays nothing")` — `lastArrangeEntries` at the full walk.

- [ ] **Step 2: the counter, alone (arm C).** `ctx.arrangeEntries += 1` at the top of `arrangeBody`, published, mechanism off. Measure. It runs ~1,100×/step — the same order as T8's `scanCount`, which cost +0.7–2.6 % — so this arm is not a formality. Record it.

- [ ] **Step 3: the mechanism.** At the top of `stackLib.arrange`, immediately after `local children = node.children or {}`:

```luau
	--[[ THE STACK REPLAYS ITS OWN PLACEMENT (Plan C addendum, T14). A one-leaf write
		on a 1,000-row list entered `arrangeBody` 1,109 times to run FIVE bodies: pass 1
		measured every child, the placement loop built a `childRect` for every child,
		and 1,104 of them reached `arrangeBody` only to take its early skip. The skip
		was already free; GETTING THERE was the bill.

		SO THE STACK KEEPS ITS CURSOR. `pRect[idx]` is the rect each child was placed
		at and `pInner*` is the box that placement was computed in. On a reuse arrange
		into the same inner box, one hash probe per child says who is dirty; only those
		are re-measured, and the compare is MEASURED-to-MEASURED against T13's
		`aMain[idx]` — never measured-against-placed, which is the mistake that made
		the first prototype of this arm fire on `setState` and `removeItem` and never
		on `updateItem-hp`: a `fill` child's placed main extent comes from `fillPx`,
		not from its measurement, so the two disagree by construction.

		DELTA ZERO IS THE COMMON CASE AND COSTS THE DIRTY CHILDREN ONLY. A non-zero
		delta at index k shifts every index after k by exactly that many pixels and
		leaves every index before it ALONE — a prefix rebase, which is what a cursor
		is. Anything else (a fill weight in play, a shrink deficit, a hug child, a
		gap or distribute change, an align change) falls through to the full body
		below, unchanged. ]]
	local reuse = (ctx :: any).reuse
	local prevRects = node.pRect
	if
		reuse ~= nil
		and reuse.dirtyContains ~= nil
		and prevRects ~= nil
		and node.pInnerX == innerX
		and node.pInnerY == innerY
		and node.pInnerW == innerW
		and node.pInnerH == innerH
		and node.aMain ~= nil
		and (ctx :: any).noSkipDepth == 0
		and node.distribute == nil
	then
		local dirty = reuse.dirtyContains
		local aMain = node.aMain
		local delta, deltaFrom, ok = 0, math.huge, true
		for idx, child in children do
			if dirty[child.id] ~= true then
				continue
			end
			local before = aMain[idx]
			if before == nil then
				ok = false -- a `fill` child, or one this container never cached
				break
			end
			local mt, mr, mb, ml = deps.sides(child.margin)
			local w, h = deps.measure(ctx, child, innerW, innerH)
			local after = if isH then w + ml + mr else h + mt + mb
			if delta ~= 0 and after ~= before then
				ok = false -- two independent shifts: the cursor is not a single prefix
				break
			end
			if after ~= before then
				delta = after - before
				deltaFrom = idx
				aMain[idx] = after
			end
		end
		if ok then
			for idx, child in children do
				local prev = prevRects[idx]
				if prev == nil then
					ok = false
					break
				end
				local shifted = idx > deltaFrom and delta ~= 0
				if dirty[child.id] ~= true and not shifted then
					continue
				end
				local r = if shifted
					then {
						x = prev.x + (if isH then delta else 0),
						y = prev.y + (if isH then 0 else delta),
						w = prev.w,
						h = prev.h,
					}
					else { x = prev.x, y = prev.y, w = prev.w, h = prev.h }
				prevRects[idx] = r
				--[[ THE CONTAINMENT FINDING IS REPLAYED, NOT DROPPED (owed list row 2).
					A skipped child files no diagnostic, and dropping it silences
					`controller.diagnostics()` for exactly the parts of the screen that
					did not change — the instrument every layout defect in this repo was
					caught by. Same call, same arguments, on the rect it is keeping. ]]
				noteContainment(ctx, node, child, r, innerX, innerY, innerW, innerH, not isH)
				place(ctx, child, r, out)
			end
			if ok then
				return
			end
		end
		-- REFUSED: fall through to the full body, which overwrites `pRect` wholesale
		-- below. Nothing above wrote a rect for a child it did not also `place`.
	end
```

  …and at the END of the placement loop, beside `place(ctx, child, childRect, out)`, the
  cache fill:

```luau
		-- record what this loop decided, so the next arrange into the same box can
		-- replay it. FROZEN, like every rect: `pRect[idx]` and the entry in `out` are
		-- the SAME TABLE, and `commit_walks.skip` prunes on entry identity.
		pRect[idx] = childRect
```

  with `local pRect = {}` at the top of the placement loop and
  `node.pRect, node.pInnerX, node.pInnerY, node.pInnerW, node.pInnerH = pRect, innerX, innerY, innerW, innerH`
  after it. **`node.pRect = nil` on every early return of `arrange` that does not reach
  the placement loop** (the flow-wrap branch, the scroll branch) — a stale placement
  cache under a branch that no longer runs is the same class as T13's `aStamp`.

  **`node.distribute == nil` in the gate is deliberate and narrow.** `distribute`
  spreads leftover space across the gaps, so a delta is not a prefix shift — every gap
  after the change moves by a fraction. Refusing it outright is exact; a `distribute`
  stack falls through to today's code forever, and `selfArrangeKey` already treats
  `distribute` as an arrange-classed self-prop for the same reason.

- [ ] **Step 4: pass 1 reads `aMain` (the T11 residue).** With T13 landed, `stack.arrange`'s pass 1 (`stack.luau:136-160`) is measuring children T13's `contentSize` already measured at the same offer under the same key. **Replace the call with a read of `node.aMain[idx]` when `node.aStamp` matches this offer and the child is not in `reuse.measureContains`** — and, per T11's finding, write `ctx.offers` for that child exactly as T13's skip arm does. If `aStamp` does not match (the arrange offer differs from the measure offer, which is the common case for a `fill` container), pass 1 measures as it does today. **Measure this sub-step separately** — T9b measured the call-overhead-only version of it at −5.2 %, and if the replay in step 3 fires, pass 1 does not run at all and this is worth 0. Ship it only if the arm shows it.

- [ ] **Step 5: green + the differential oracle arm.** `stack_replay.spec` green. The 9-view, 3-fixture oracle exactly as T13 step 5 defines it, plus a **fourth fixture with a `distribute` stack** (the refused path must be byte-equal too, and a refusal that silently changed a rect is the worst outcome this task can have). Standing suites: `host_space_oracle`, `translate_arm`, `anchor_skip`, `measure_split`, `rect_cow`, `node_reuse`, `container_aggregate`.

- [ ] **Step 6: the mutation (Step-7 discipline).** Each must BITE:
  1. Compare `after` against `prev.w`/`prev.h` (measured-against-placed) → redden the `fill` case.
  2. Shift from `idx >= deltaFrom` instead of `>` → the dirty child itself double-shifts; redden the height case.
  3. Remove the `noteContainment` replay → redden the diagnostics case.
  4. Remove `node.distribute == nil` → redden the `distribute` fixture's oracle.
  5. Leave `node.pRect` set on the scroll branch's early return → redden a scroll-then-stack fixture.

- [ ] **Step 7: gates, RR, measurement, commit.** Full gates as T13 step 7. **RR `facet_anchor_arrange.spec` must be UNCHANGED** — if it moves, `lastArranged` moved, and that is a stop. Measurement, three arms, ABBA:

  | class | before (post-T13) | **expected after** |
  |---|---:|---:|
  | `battle_hud L updateItem-hp` | ~0.79 | **~0.30** (−0.49) |
  | `battle_hud L setState` | ~0.89 | ~0.32 |
  | `battle_hud L removeItem-damage` | ~2.0 | ~1.1 (T9b's ceiling arm read −44 % on this class) |
  | `war_room_inventory L setState` | ~1.05 | ~0.35 |
  | `killfeed_nameplates L updateItem-hp` | ~0.29 | ~0.14 |
  | `nameplates L updateItem-hp` | 0.006 | 0.006 (control) |

  Commit (after step 0's own commit) `T14: a stack replays its own placement and rebases the prefix a delta moved (C12)`.

- [ ] **Step 8: FacetBench §C12.** §C12 — the mechanism, the counter table (`lastArrangeEntries` 1,109 → N, with `lastArranged`/`rectWrites`/`engineWrites` shown UNMOVED beside it, because that is the safety claim), the ABBA table, the arm-C number, **and the measured-vs-placed correction written up plainly** — the first prototype of this arm compared the wrong two numbers and its null on `updateItem-hp` looked exactly like "the lever does not apply to this class".

---

### Task 15 (L1c → FacetBench §C13): `layout_node.build` keeps a container's children array

**The gate:** `toLayoutNode` is **0.138 ms of 1.824 (7.6 %)** on `battle_hud` L
`updateItem-hp` and **0.521 / 0.538 ms** on `war_room`'s remove / reorder classes.
Scaling says it is O(tree) at ~26 ns/node (S 0.021 → L 0.138 over 519 → 5,109 nodes).

**The mechanism, and why it is O(tree) despite a working store.** A store HIT is two
hash probes and returns a whole subtree without walking it
(`layout_node.luau:387-395`: `hit ~= nil and not store.dirty[node.path] and hit.axis ==
parentAxis and hit.clip == …` → `store.nodes += hit.n; return hit.built`). A **MISS**
rebuilds, and a rebuild re-visits every child (`:1348-1382`): `layoutNode.children = {}`
(a fresh array per rebuilt container), `local function appendChild(child)` (a fresh
closure per rebuilt container, capturing eight upvalues), and `toLayoutNode(...)` +
`table.insert` per child. The dirty closure marks every ANCESTOR of the changed leaf, so
the ForEach region is a miss and its loop touches all 1,000 rows — each a 26 ns hit that
returns immediately, and each still a visit and an array slot.

**THE OWED LIST — what re-running `toLayoutNode(child, …)` publishes that reusing the
array would lose:**

| # | channel | site | verdict |
|---|---|---|---|
| 1 | `store.nodes += hit.n` (the subtree size accumulator) | `:394` | **SERVED** — the reused array's children each contributed `hit.n` last time and `n` is recorded on the container's own entry (`:1521`); the reuse arm adds the container's recorded `n` minus its own 1 |
| 2 | `store.built += 1` / `store.nodes += 1` for the container | `:396-397` | **UNCHANGED** — the container is still rebuilt; only its CHILD LOOP is bounded |
| 3 | `builtIds` collection (`table.insert` per constructed node when `collect == true`) | `:408-411` | **GATED** — `collect` is the analysis arm; the reuse arm is refused outright when `store.collect` is on. One boolean, and the analysis path is not a hot path |
| 4 | the `When`/`ForEach`/`ErrorBoundary` splice in `appendChild` | `:1361-1365` | **SERVED BY IDENTITY** — the gate is `node.children` TABLE IDENTITY (below), and a region whose own children changed produces a different `node.children` on the parent only if the parent's array changed; a region's INTERNAL change marks the region in `store.dirty`, which the per-index re-run handles. **This is the row the spec's structural cases exist for** |
| 5 | `hit.axis` / `hit.clip` re-validation per child | `:390-391` | **NOT SERVED, and it is why the gate is what it is** — a reused array is only sound if `parentAxis` and `insideClipper` are the same as when it was built; both are recorded on the container's entry and compared |

**Files:**
- Modify: `src/render/layout_node.luau` — the store entry gains `kids` and `childArray`; the child loop at `:1348-1382` gains the reuse arm; the entry write at `:1516-1522`.
- Modify: `src/render/render_stats.luau` — `stats.lastBuildChildVisits`.
- Create: `tests/build_children_reuse.spec.luau`; register.

**Interfaces:**
- Consumes: `store.dirty` (the renderer's `nodeDirty`, ancestor-closed over mounted-path prefixes), `store.byNode`, `parentAxis`, `insideClipper`, `store.collect`.
- Produces on the store entry (`store.byNode[node]`, `:1519-1521`): `kids: { any }` (the MOUNT-node children table this build read — kept for identity comparison, never iterated for content) and `childArray: { any }` (the built `layoutNode.children`).
- Produces: `work`-free — `layout_node.build` publishes through `store`, so the counter is `store.childVisits`, read by the renderer where it already reads `store.nodes`, into `stats.lastBuildChildVisits`.
- **Must NOT move: `lastLayoutNodes`, `lastMeasured`, `lastArranged`, `lastSkipped`, `lastSolveSkipped`, `rectWrites`, `engineWrites`, `solves`.**

- [ ] **Step 1: the owed list, then red.** Table into the spec header + ledger. `tests/build_children_reuse.spec.luau` on `deep_stack_scene`:
  - HEAD probe first: `lastBuildChildVisits=<~1110>`, `lastLayoutNodes=<5127>`, `solves=1`. After: **`lastBuildChildVisits` ≤ 10, `lastLayoutNodes` UNCHANGED.**
  - `it("a row inserted into the list rebuilds the array")` — `node.children` is a new table, so identity fails and the full loop runs; `lastLayoutNodes` grows by exactly the new subtree.
  - `it("a ForEach region whose own children changed re-runs that index only")` — row 4's case.
  - `it("a container re-parented under a different axis rebuilds")` — `hit.axis` (row 5); drive by moving a subtree from a VStack into an HStack.
  - `it("a container that enters a clipper rebuilds")` — `hit.clip` (row 5).
  - `it("the analysis arm never reuses")` — `store.collect` on, full walk (row 3).

- [ ] **Step 2: the counter, alone (arm C).** `store.childVisits += 1` in the child loop, published, mechanism off. It runs ~1,110×/step. Measure and record.

- [ ] **Step 3: the mechanism.** Replacing `:1348-1382`:

```luau
	if #node.children > 0 then
		local childAxis: string? = if kind == "hstack" or kind == "hwrap"
			then "x"
			elseif kind == "vstack" or kind == "vwrap" then "y"
			else nil
		--[[ THE CHILDREN ARRAY IS KEPT (Plan C addendum, T15). A store HIT returns a
			whole subtree in two hash probes; a MISS rebuilds the container AND re-visits
			every child — a fresh array, a fresh `appendChild` closure over eight
			upvalues, and one `toLayoutNode` call per child. The dirty closure marks
			every ANCESTOR of a changed leaf, so a one-leaf write makes the enclosing
			ForEach region a miss and its loop touches all 1,000 rows. Each of those is a
			26 ns hit that returns immediately — and 1,000 of them is 0.14 ms, 7.6 % of
			the class, for a tree whose shape did not move.

			THE GATE IS TABLE IDENTITY, NOT LENGTH. `node.children` is the MOUNT tree's
			array; `mount` builds a NEW table whenever the child set changes and mutates
			it never (`mount.luau`'s region splice included), so identity is exactly
			"the shape under me is the shape I built for". A length compare would accept
			a swap; a per-element compare would cost the loop this replaces.

			AND `axis`/`clip` COME WITH IT. Those are the two inputs the per-child lookup
			at the top of this function cannot re-derive from the node it holds, so a
			reused array is sound only under the same pair — recorded on this
			container's own entry and compared here, exactly as the per-child hit
			compares them. ]]
		local prior = if store ~= nil and store.reuse and not store.collect then store.byNode[node] else nil
		local reusableKids = prior ~= nil
			and prior.kids == node.children
			and prior.childArray ~= nil
			and prior.axis == parentAxis
			and prior.clip == (insideClipper == true)
		if reusableKids then
			local built = (prior :: any).childArray
			layoutNode.children = built
			local anyDirty = false
			for i, child in node.children do
				if store.dirty[child.path] then
					anyDirty = true
					break
				end
			end
			if not anyDirty then
				--[[ NOTHING UNDER THIS CONTAINER MOVED: the array stands as it is and the
					subtree accounting comes off this container's own recorded `n`, minus
					the one this container itself is about to be counted for above. That is
					the same arithmetic the per-child hit does with `hit.n`, done once. ]]
				store.nodes = nodesAtEntry + ((prior :: any).n or 1)
			else
				reusableKids = false
			end
		end
		if not reusableKids then
			layoutNode.children = {}
			local function appendChild(child: any)
				if child.class == "When" or child.class == "ForEach" or child.class == "ErrorBoundary" then
					for _, grandchild in child.children do
						appendChild(grandchild)
					end
				else
					if store ~= nil then
						store.childVisits += 1
					end
					table.insert(
						layoutNode.children,
						toLayoutNode(child, metrics, textScale, prefOffset, childAxis, insideClipper == true or kind == "scroll", store)
					)
				end
			end
			for _, child in node.children do
				appendChild(child)
			end
		end
	end
```

  and the entry write at `:1519-1521` records the two new fields:

```luau
		store.byNode[node] = {
			built = layoutNode,
			axis = parentAxis,
			clip = insideClipper == true,
			n = store.nodes - nodesAtEntry,
			-- ...and what T15 needs to keep the array: the MOUNT children table this
			-- build read (compared by IDENTITY, never iterated) and the built array
			-- it produced.
			kids = node.children,
			childArray = layoutNode.children,
		}
```

  **The conservative shape is deliberate.** This version reuses the array only when
  **nothing** under the container is dirty — the `anyDirty` scan is one hash probe per
  child (~0.02 µs) against a `toLayoutNode` entry (~0.026 µs plus an insert), so it is
  already the win, and it is sound without reasoning about partial rebuilds. **A
  per-index re-run — rebuild only the dirty indices in place — is the stronger version
  and is DEFERRED to a fix round on a measurement**: it needs the reused array to be
  mutated, and `layoutNode.children` is read by the solver during a solve that may still
  be running under `analyzeBoundaries`. Ship the conservative one; book the other.

- [ ] **Step 4: green + the differential oracle arm.** `build_children_reuse.spec` green. The 9-view oracle on `deep_stack_scene` + a `ForEach`-region fixture + a `When` fixture, three drives each (leaf write, insert, remove), arm `c` byte-equal. Standing: `node_reuse` (its own control arm is `layoutNodeReuse = false`, which is this task's off-switch and must still be pre-fix-exact), `host_space_oracle`, `translate_arm`, `container_aggregate`, `stack_replay`.

- [ ] **Step 5: the mutation (Step-7 discipline).**
  1. Compare `#prior.kids == #node.children` instead of identity → redden the swap case.
  2. Drop the `prior.axis == parentAxis` term → redden the re-parent-across-axis case.
  3. Drop `not store.collect` → redden the analysis case.
  4. Drop the `anyDirty` scan (reuse unconditionally) → redden the leaf-write case (`lastLayoutNodes` or a rect moves).
  5. `store.nodes = nodesAtEntry + prior.n` written as `store.nodes += prior.n` → redden `lastLayoutNodes`.

- [ ] **Step 6: gates, RR, measurement, commit.** Full gates; RR green with **no pin moved**. Three arms, ABBA:

  | class | before (post-T14) | **expected after** |
  |---|---:|---:|
  | `battle_hud L updateItem-hp` | ~0.30 | **~0.17** (−0.13) |
  | `war_room_inventory L reorder` | ~17 | ~16.5 (−0.52) |
  | `killfeed_nameplates L updateItem-hp` | ~0.14 | ~0.10 |
  | `nameplates L updateItems-plates` (post-T12 ~2.6) | ~2.6 | ~2.4 (−0.23) |

  Commit `T15: a rebuilt container keeps its children array when the shape under it did not move (C13)`.

- [ ] **Step 7: FacetBench §C13.** §C13 — the store-hit-vs-store-miss asymmetry stated plainly (the hit was always O(1); the miss was always O(children)), the counter table, the ABBA table, and the DEFERRED per-index version with the reason.

---

### Task 16 (L1d → FacetBench §C14): the commit's sibling scan, PROFILE-GATED

**GATE (ruling A-6) — this task may end as a booking line.** Build ONLY if, measured at
the T15 SHA with `attr <wl> L 3`, `cw.harvest` is **≥ 5 % of a leaf-edit class AND
≥ 0.05 ms in absolute terms** on at least one of `battle_hud L updateItem-hp`,
`war_room L setState`, `killfeed L updateItem-hp`. At `09d2dfcc` it is **0.089 ms of
1.824 (4.9 %)**; after T13–T15 the class is ~0.17 ms and the same 0.089 ms would be
**52 %** — the share gate will pass trivially and the ABSOLUTE gate is the real one.
If it does not pass, write the booking line into `progress.md` and the closing report,
and go to Task 17.

**The mechanism, and the exact form T8 proved unsound.** `descendOf` (`:722`) misses the
cache and calls `buildDescend(node)` (`:731`), which scans **every** child
(`commit_walks.luau:607` `for i, child in kids do`) computing `entryVerdict` per child;
the file's own header says "the FIRST walk to reach a node pays its whole sibling scan
and the other seven pay none of it". `lastCommitScans` is exactly this number: **1,137
against `lastCommitVisits` 52** on `battle_hud` L `updateItem-hp`.

**T8's review already refuted the naive index** and the refutation is the design here: a
`dirtyChildren` index loses rects, because **a dirty parent's CLEAN child gets a new
entry whenever the solve re-arranged it** — driven, a `fill` box goes 300 → 220 px while
the index is empty, and it paints 300 px for the life of the surface behind a green
suite. **The sound form is a SUPERSET filter over what the SOLVE actually wrote**, which
the solve already publishes: `work.walkedIds` (every node whose `arrangeBody` ran) and
`work.translatedPaths` (every node the translate arm re-based), plus `nodeDirty` /
`commitDirty` themselves. A child in none of those three sets has an entry table
identical to `lastCommitEntry[path]` **by construction** — that is `arrangeBody`'s skip
contract — so `entryVerdict` would have answered "settled" and the scan can be skipped
for it without being asked.

**THE OWED LIST — what `entryVerdict(child)` publishes that the filter must reproduce:**

| # | channel | site | verdict |
|---|---|---|---|
| 1 | the `(settled, moved)` pair feeding `skipB`/`skipM`/`skipC` | `:512`, `:628-633` | **SERVED conservatively** — a child outside all three sets is `settled = true`, which is `skipB = skipM = skipC = true` on a non-dirty child: it is pruned from all three lists, exactly as the scan would prune it |
| 2 | `scanCount += 1` | `:524`, `:608` | **CHANGES BY DESIGN** — `lastCommitScans` IS the counter this task moves, and it is the acceptance number |
| 3 | the three fork points (`skipM ~= skipB`, `skipC ~= skipM`) and the prefix-copy aliasing | `:637-694` | **UNCHANGED** — the filter only decides WHICH children are examined; every child that IS examined goes through today's code unchanged, and a child that is not is a prune in all three lists, which the aliasing already represents as "not in any list" |
| 4 | `sawChrome` | `:668-694` | **STATED** — T8's Minor 1 established it is output-neutral because of the LATCH'S LIFETIME, not the loop. A filtered child cannot un-latch it; a filtered child that WOULD have set it is a child with a chrome entry, which means a changed entry, which means it is in one of the three sets |
| 5 | the unpruned (full) arm at `:826-863` | `:814` | **UNTOUCHED** — `pruning == false` returns `node.children` and this task adds nothing there |

**Files:**
- Modify: `src/render/commit_walks.luau` — `commit_walks.new`'s ctx gains `walked` (a `{ [string]: true }` union of `work.walkedIds` and `work.translatedPaths`, built by the renderer once per commit); `buildDescend`'s child loop gains the filter.
- Modify: `src/render/renderer.luau` — hand `walked` into the commit ctx. **≤ 200 chars** (the Global Constraints cap for this wave; `renderer.luau` is at 195,709 with 4,291 to the cap).
- Create: `tests/commit_scan_filter.spec.luau`; register.

**Interfaces:**
- Consumes: `result.work.walkedIds`, `result.work.translatedPaths`, `nodeDirty`, `commitDirty`.
- Produces: no new public field. **Moves: `lastCommitScans` (1,137 → ≤ 60 on `battle_hud` L hp).** **Must NOT move: `lastCommitVisits`, `lastCommitVisitsByWalk`, `lastCommitListCells`, `rectWrites`, `propWrites`, `engineWrites`, `elided`, `creates`, `removes`, `parked`, `recycled`.**

- [ ] **Step 1: run the gate.** `attr battle_hud L 3`, `war_room_inventory L 3`, `killfeed_nameplates L 3` at the T15 SHA. Write `cw.harvest`'s ms and share per class into `progress.md`. **If no class passes both halves of ruling A-6, STOP and book.**
- [ ] **Step 2: the owed list, then red.** Table into the spec header + ledger. `tests/commit_scan_filter.spec.luau`: HEAD probe → `lastCommitScans=<1137-ish>`, `lastCommitVisits=<52>`, `solves=1`; after: **`lastCommitScans` ≤ 60 with `lastCommitVisits` UNCHANGED in the same assertion block.** Plus **T8's own case, driven, as the acceptance test: `it("a clean child of a dirty parent")`** — a `fill` box under a dirty parent whose width goes 300 → 220 while it is in no dirty set; its rect must be committed at 220. Plus the reorder case (`war_room`-shaped: nearly every child dirty, the filter must degrade to today's scan without costing extra) and a viewport-change case (unpruned arm, untouched).
- [ ] **Step 3: the counter, alone (arm C).** Not applicable — the counter already exists (`lastCommitScans`, T8). Arm C here is **the filter built and the union table populated, with the filter's `continue` removed**, so the cost of building `walked` is measured on its own. T8 measured the bare `scanCount += 1` at +0.7–2.6 %; a per-commit union over `walkedIds` is the analogous risk and must be priced.
- [ ] **Step 4: the mechanism.** In `buildDescend`'s loop, immediately after `local p = child.path`:

```luau
			--[[ A CHILD THE SOLVE NEVER TOUCHED CANNOT HAVE A NEW ENTRY (Plan C addendum,
				T16). `arrangeBody`'s skip is the contract: a subtree it skipped kept its
				entry TABLE, and `skip` prunes on entry identity — so for such a child
				`entryVerdict` answers `settled = true` BY CONSTRUCTION and the probe is
				pure cost. On `battle_hud L` a one-leaf write asks it 1,137 times to
				descend 52 nodes.

				THE FILTER IS A SUPERSET, WHICH IS THE HALF T8 GOT WRONG AND SAID SO. A
				`dirtyChildren` index is unsound: a dirty parent's CLEAN child gets a new
				entry whenever the solve re-arranged it, and driven, a `fill` box goes
				300 -> 220 px while the index is empty and paints 300 for the life of the
				surface. `walked` is not a dirty set — it is `work.walkedIds` union
				`work.translatedPaths`, i.e. every node whose entry this solve could have
				REPLACED — so a child outside it, outside `nodeDirty` and outside
				`commitDirty` is settled with no probe, and everything else takes today's
				path unchanged. A stale or over-wide `walked` costs a probe, never a
				missed write. ]]
			if walked ~= nil and walked[p] ~= true and nodeDirty[p] ~= true and (commitDirty == nil or (commitDirty :: any)[p] ~= true) then
				continue
			end
			scanCount += 1
```

  (the pre-existing `scanCount += 1` moves BELOW the filter — the counter must measure
  the questions actually asked, which is what makes it the acceptance number).

- [ ] **Step 5: green + the differential oracle arm.** 9 views, arm `c` byte-equal, on `deep_stack_scene` + the `fill`-child fixture + a chrome-bearing fixture (`UI.Path` + `expandTarget`, the two conditions that disable the prune — `commit_walks.luau:803`, `:967`) so the unpruned arm is exercised. Standing: every commit-walk oracle plus `commit_dirt_classes.spec`.
- [ ] **Step 6: the mutation.** (1) Drop the `nodeDirty[p]` term → redden a dirty-child case. (2) Use `nodeDirty` alone (T8's unsound index) → **must redden the `fill` case**; if it does not, the fixture is not a witness and step 2 is wrong. (3) Move `scanCount += 1` back above the filter → redden the counter pin.
- [ ] **Step 7: gates, RR, measurement, commit.** Full gates; `check_source_size` with `renderer.luau` recorded. Three arms, ABBA; expected `battle_hud L updateItem-hp` **~0.17 → ~0.09**, `killfeed L hp` ~0.10 → ~0.07, `war_room reorder` ~16.5 → ~16.2. Commit `T16: the commit asks about a child only when the solve could have replaced its entry (C14)`.
- [ ] **Step 8: FacetBench §C14.** §C14 — including, plainly, that T8 named this mechanism unsound in one form and this is the other form, with the `fill`-child case as the difference.

---

### Task 17 (L3 → FacetBench §C15): the live-only 1.5 ms

**The finding this task starts from** (T9b §5), measured at `09d2dfcc` through
`FacetBenchRun` with the marker read back (`af4f519`, `solver.luau` 190,112 = clean HEAD):

| class | Lune | live | **surplus** | engine writes |
|---|---:|---:|---:|---:|
| `battle_hud L updateItem-hp` | 1.824 | 3.382 | **+1.56 ms** | 4 |
| `battle_hud L setState` | 1.927 | 3.426 | **+1.50 ms** | **0** |
| `nameplates L updateItem-hp` | 0.006 | 0.295 | +0.29 | 2 |

Live scaling over S/M/L (519 / 2,049 / 5,109 nodes): slope **0.635 µs/node**, intercept
**0.129 ms** — so the surplus is in the MARGINAL, not the floor, and it is ~1.95x the
Lune marginal (0.326). A class with **zero engine writes** costing 1.5 ms more live than
headless is not property-write cost.

**The first suspect, with its evidence:** the first live drive of the session printed
`C stack overflow (when calling anonymous function on line 484 in
ReplicatedStorage.ui.Facet.src.client.text_premeasure)` followed by
`Script timeout: exhausted allowed execution time`. `client/text_premeasure` has no
headless counterpart and no instrument in this campaign has ever looked at it.

**Files (conditional on what the capture says):**
- Create: `../FacetBench/docs/studio-runs/2026-09-05-microprofiler-battle_hud-hp.md` — the capture and its attribution.
- Modify (only if the cost is Facet-side): the named module, plus a headless pin.
- Create (only if Facet-side): `tests/text_premeasure_bound.spec.luau` or the equivalent for whatever the capture names; register.

**Interfaces:** none until the capture says. **This task may produce a booking and a
mechanism instead of a change (ruling A-7), and that is a complete deliverable.**

- [ ] **Step 1: the capture.** Follow `../FacetBench/docs/studio-runs/2026-09-01-microprofiler-campaign-before.md`'s method **exactly** — read the tick rate from `session:FetchGlobalDesc().TickToMsCpu` rather than calibrating it, and BOUND the frame window to the run's own frames (the 256-frame ring dilutes the percentiles otherwise). Drive `battle_hud` L, facet only, `updateItem-hp`, **through the direct `require(...).run{…}` call inside ONE `execute_luau`** — the one thing the RemoteEvent relay cannot do — with **nothing else running** (`DRIVING.md`: the MCP VM keeps its own require cache and the "refused, not queued" guard does not span the two VMs). Facet's own `profile` spans ON. Stamp and read back the marker first; a disagreement between the disk marker, the mounted `Source` and the console is a hard stop.
- [ ] **Step 2: attribute the 1.5 ms.** Produce the per-span live table for one `updateItem-hp` step: `Facet/measure`, `Facet/arrange`, `Facet/commit`, `Facet/mount`, `Facet/react`, `Facet/dirtyScan`, `Facet/lane` — **and the engine bars beside them**. Answer one question in one sentence: *is the surplus inside Facet's own spans (so T13–T16 will take most of it) or outside them (so it is engine or premeasure and a separate lever)?*
- [ ] **Step 3: the `text_premeasure` line-484 overflow.** Read `src/client/text_premeasure.luau:484`'s anonymous function and its recursion. **Reproduce it in a spec if it is Facet's** — an unbounded recursion over a 5,109-node tree that a 200-sample battle_hud drive can reach is a correctness defect independent of any millisecond, and it belongs on the RED-TEAM list at Task 10 whether or not it is the 1.5 ms. If it is NOT reproducible headless (it may need real `GetTextBoundsAsync`), say so and book it with the console line as the evidence.
- [ ] **Step 4: the fix, or the booking.** If Facet-side: fix it, pin it headless, and re-drive live to show the surplus gone. If engine-side: name the mechanism (which Roblox call, on how many objects, why 4 writes cost 1.5 ms) and book it, with the number the campaign report must quote.
- [ ] **Step 5: gates + commit.** If any `src/` changed: full gates, RR lockstep, `check_source_size`. If not: the FacetBench doc alone. Commit `T17: the live-only millisecond and a half, attributed (C15)` (or `…, booked` if step 4 booked).
- [ ] **Step 6: FacetBench §C15.** §C15 — the capture, the attribution, the per-class live/Lune surplus table, and the standing rule it produces: **a headless lever's live gain is unknown until the live/headless ratio for its class is attributed** — this campaign predicted "about 2x" from a scaling fit and that is the weakest number in the whole report.

---

## Self-review (done while writing)

**Spec coverage vs T9b §6.** Every lever in the assessment's ranked list has a task or an
explicit disposition: L2 → T12; L1a → T13; L1b → T14; L1c → T15; L1d → T16
(profile-gated, ruling A-6); L3 → T17; **L4 (allocation) is NOT a task** — T9b measured
it as a clock null (−16.6 % allocation, 0 % time) and §4 says plainly not to spend a
round on it without a live arm first, so it is folded into T17's live capture as an
observation (`gcSwingKb` 31,982 facet vs 44 vide) rather than a build; **L5 (`ctx.offers`)
is T13 step 4, conditional on the character budget**, per its rank-8 placement.
Task 11 is dispositioned at the top with its measured number. Nothing in §6 is
unaccounted for.

**Placeholder scan.** No step says "similar to Task N", "as above" or "TBD". Every
mechanism block is Luau written against the symbols at `09d2dfcc`
(`arrangeBody`, `contentSize`'s vstack/hstack branch, `stackLib.arrange`,
`toLayoutNode`'s child loop, `buildDescend`, `fake_target.setRect`), read from the
source while writing. Three things are deliberately left to the implementer and are
LABELLED as such rather than hidden: the exact `fieldsRead` set in T14 step 0 ("read off
the run"), every "currently N" pin ("READ OFF THE RUN at HEAD with a throwaway probe"),
and T17's entire shape (ruling A-7).

**Type consistency.** The six T13 container fields, the five T14 placement fields and
the two T15 store-entry fields are all optional (`?`) and all live on tables the
codebase already treats as open records (`solver.Node`, `store.byNode[node]`), matching
C2's own 21-field precedent. `work.childVisits` / `work.arrangeEntries` are numbers
published through `render_stats.publish` as `last*` snapshots (ruling A-5), matching
`work.measureCalls`/`measureServed`. `fake_target.Opts` gains one optional boolean
beside `trackThemeRoots`. `stats.lastChildVisits` / `lastArrangeEntries` /
`lastBuildChildVisits` are three new `last*` fields in `render_stats.new()`'s record and
must be registered in `render_stats_seam.spec` (T8's precedent for
`lastCommitListCells`) — **called out here because no step body says it and a new stats
field that is not registered is a silently untested public number.**

**Ordering.** T12 before everything (ruling A-2 — otherwise T13–T16's `attr` deltas are
read against a harness). T13 before T14 (T14's compare reads T13's `aMain`). T14 step 0
is its own commit before T14's behaviour (ruling T7-3). T15 is independent of both and
could run in parallel, but is sequenced after so its `attr` baseline is stable. T16 is
gated on what T13–T15 leave. T17 is independent of all of them and could be run first by
a second agent; it is last because its deliverable may be a booking and the closing
report needs the four numbers above it.

**The one thing this plan cannot promise.** T13–T16 together reach the measured floor
**headless**. **Live, they clear 0.5 ms only if T17 finds the 1.5 ms.** Task 10's report
must say that in those words if T17 books instead of fixing.
