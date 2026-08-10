# Row Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SwiftUI-parity swipe actions for rows — a general `newRowActions` composite (swipe reveals leading/trailing action buttons on springs, full swipe commits the first action), wired into Table with full cross-input coverage (touch, mouse, keyboard, gamepad, edit mode), then a full refresh of `docs/reference/swiftui-parity.md`.

**Architecture:** A pure decision module (`row_actions_state.luau`) owns all thresholds/verdicts; a composite (`row_actions.luau`) owns blueprints, springs, input entry points, and the contribution bundle (outside-dismiss, action bindings); Table wraps each row and composes pointer handlers with reorder via an axis lock. Spec: `docs/plans/row-actions.md`.

**Tech Stack:** Luau, LuauUI internals (specGuard, motion clock/springs, drag_velocity, contribution bundles, presenter), lune test harness, Studio MCP for device verification.

## Global Constraints

- Repo: `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/LuauUI` (git branch `sponsor/director-round-2026-08-04`; commit only your own files, other uncommitted work exists — including `docs/reference/swiftui-parity.md`, do not clobber it).
- Run one spec: `lune run tests/run -- tests/<name>.spec.luau`. Full suite: `./run-tests.sh`. Gates: `tools/gate.sh <gate-name>`.
- Suite-grep gate checks MUST use Form A: `out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*<test name>"` — never pipe the suite straight into grep (masks exit code).
- Specs are validated at build: `specGuard.assertKnownKeys(where, spec, KEYS, "spec")` with `specGuard.keySet({...})`; unknown keys are errors; empty action list `{}` is an error (use nil).
- No literal colors/metrics in controls — theme references only (`"danger"`, `"onDanger"`, `"controls.rowActions.*"`, space steps like `"m"`). Resolved via `snapshot.resolveNumber`.
- Composites return `{ blueprint, dump, dispose }`; `dispose` calls `scope:dispose()`; callbacks fire synchronously, exactly once per commit, quarantined on throw.
- Every fixture/example calls `controller.diagnostics()` and fails on any finding; device sweep includes 320×640.
- Action labels are localization-safe: must survive ~1.4x pseudo-loc expansion (wrap/auto-fit, never clip).
- Reduced motion: reveal/commit snap (`kind = "decorative"` default behavior); check via `clock:isReduced()` only where a non-spring code path is needed.
- Commit after every green task. Message prefix `feat(row-actions):` / `test(row-actions):` / `docs:`.
- **Performance (director directive 2026-08-10):** the wrapper must be near-free when idle. (a) Trays mount **lazily** — a closed row materialises ZERO tray GuiObjects (`UI.When` on first gesture/open; instance census proved inert containers are the framework's cost center). (b) An inert passthrough (no actions) adds no extra container if the elision pass can absorb it — verify against the elision rules. (c) During a drag, offset writes go through the single `applyOffset` seam — no per-frame re-layout of the whole row list (incremental layout should scope the change to the row; check `arranged` counts). (d) Task 11 gains a perf row: run the existing scroll/fling perf workload (perf lab places, `docs/plans/performance-stress-places.md`) with 200 wrapped rows vs unwrapped baseline — budget: ≤5% added cost on steady scroll and fling ms/f, zero added GuiObjects while closed (report actual numbers in `artifacts/row-actions/device-matrix.md`). Compare scope totals, not step-p50 (step-p50 cannot see mount).

---

### Task 1: Pure state module `row_actions_state`

**Files:**
- Create: `src/input/row_actions_state.luau`
- Test: `tests/row_actions_state.spec.luau`
- Modify: `tests/run.luau` (register the new spec file the same way neighboring specs are registered)

**Interfaces:**
- Consumes: nothing (pure math; no Instances, no clock, no engine).
- Produces (used by Tasks 3–6, 10):

```luau
row_actions_state.AXIS_LOCK_PX = 8       -- movement before an axis verdict
row_actions_state.OPEN_FRACTION = 0.5    -- of tray width → snap open
row_actions_state.COMMIT_FRACTION = 0.6  -- of row width → full-swipe commit
row_actions_state.RESISTANCE = 0.55      -- rubber-band factor past limits
row_actions_state.VELOCITY_PROJECT_S = 0.08 -- release: project velocity 80ms

row_actions_state.new(opts: {
	rowWidth: number,          -- px
	leadingWidth: number,      -- total leading tray width px (0 = none)
	trailingWidth: number,     -- total trailing tray width px (0 = none)
	fullSwipeLeading: boolean,
	fullSwipeTrailing: boolean,
}) -> State

State.axisVerdict(dx: number, dy: number) -> "pending" | "horizontal" | "vertical"
State.clampDrag(rawOffset: number) -> number   -- rubber-banded content offset
State.settle(offset: number, velocityX: number) -> Verdict

type Verdict = {
	target: number,                       -- px offset the spring should aim at
	edge: ("leading" | "trailing")?,      -- nil when closing
	commit: boolean,                      -- true = full-swipe: fire edge's FIRST action
}
```

Sign convention: positive offset = content pushed right = **leading** tray revealed; negative = **trailing**. `settle` picks: commit when the edge allows fullSwipe and `|projected| >= COMMIT_FRACTION * rowWidth` (projected = offset + velocityX * VELOCITY_PROJECT_S); else open (`target = ±trayWidth`) when `|projected| >= OPEN_FRACTION * trayWidth`; else closed (`target = 0`). An edge with zero tray width never opens (clamp rubber-bands immediately). `clampDrag` past the tray width without fullSwipe compresses: `trayWidth + (raw - trayWidth) * RESISTANCE`; with fullSwipe it tracks the finger linearly (SwiftUI stretch).

- [ ] **Step 1: Write the failing tests**

```luau
-- tests/row_actions_state.spec.luau
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local state = require("../src/input/row_actions_state")

describe("row_actions_state", function()
	local function mk(over)
		local opts = {
			rowWidth = 320,
			leadingWidth = 80,
			trailingWidth = 160,
			fullSwipeLeading = false,
			fullSwipeTrailing = true,
		}
		for k, v in over or {} do opts[k] = v end
		return state.new(opts)
	end

	it("axis verdict stays pending under the lock radius", function()
		local s = mk()
		expect(s.axisVerdict(5, 4)).toBe("pending")
		expect(s.axisVerdict(9, 2)).toBe("horizontal")
		expect(s.axisVerdict(2, 9)).toBe("vertical")
	end)

	it("ties go vertical (scroll wins ambiguity)", function()
		expect(mk().axisVerdict(9, 9)).toBe("vertical")
	end)

	it("drag tracks linearly inside the tray", function()
		local s = mk()
		expect(s.clampDrag(-100)).toBe(-100) -- within trailing tray (160)
		expect(s.clampDrag(60)).toBe(60)     -- within leading tray (80)
	end)

	it("rubber-bands past a non-fullSwipe tray", function()
		local s = mk()
		-- leading: fullSwipe off, tray 80; 40px past compresses by 0.55
		expect(s.clampDrag(120)).toBeCloseTo(80 + 40 * 0.55, 3)
	end)

	it("tracks the finger past a fullSwipe tray", function()
		local s = mk()
		expect(s.clampDrag(-240)).toBe(-240) -- trailing has fullSwipe
	end)

	it("an absent edge rubber-bands from zero", function()
		local s = mk({ leadingWidth = 0 })
		expect(s.clampDrag(50)).toBeCloseTo(50 * 0.55, 3)
		local v = s.settle(27, 0)
		expect(v.target).toBe(0)
		expect(v.edge).toBe(nil)
	end)

	it("settles open at half tray width", function()
		local s = mk()
		local v = s.settle(-81, 0) -- 160 * 0.5 = 80
		expect(v.target).toBe(-160)
		expect(v.edge).toBe("trailing")
		expect(v.commit).toBe(false)
	end)

	it("settles closed under half tray width", function()
		local v = mk().settle(-79, 0)
		expect(v.target).toBe(0)
		expect(v.commit).toBe(false)
	end)

	it("velocity projects the release (flick opens from a short drag)", function()
		-- 40px + (-600 px/s * 0.08s) = -88 → open
		local v = mk().settle(-40, -600)
		expect(v.target).toBe(-160)
		expect(v.edge).toBe("trailing")
	end)

	it("commits on full swipe past 60% of row width", function()
		local v = mk().settle(-200, 0) -- 320 * 0.6 = 192
		expect(v.commit).toBe(true)
		expect(v.edge).toBe("trailing")
	end)

	it("never commits when fullSwipe is off for that edge", function()
		local v = mk().settle(300, 0) -- leading, fullSwipe off
		expect(v.commit).toBe(false)
		expect(v.target).toBe(80)
		expect(v.edge).toBe("leading")
	end)
end)
```

- [ ] **Step 2: Register the spec in `tests/run.luau` (copy the neighboring require/register line pattern), run, verify FAIL**

Run: `lune run tests/run -- tests/row_actions_state.spec.luau`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `src/input/row_actions_state.luau`**

```luau
--!strict
-- Pure decision module for row swipe actions (spec: docs/plans/row-actions.md).
-- No Instances, no clock, no engine — every verdict is a function of inputs.

local row_actions_state = {}

row_actions_state.AXIS_LOCK_PX = 8
row_actions_state.OPEN_FRACTION = 0.5
row_actions_state.COMMIT_FRACTION = 0.6
row_actions_state.RESISTANCE = 0.55
row_actions_state.VELOCITY_PROJECT_S = 0.08

export type Verdict = {
	target: number,
	edge: ("leading" | "trailing")?,
	commit: boolean,
}

function row_actions_state.new(opts: {
	rowWidth: number,
	leadingWidth: number,
	trailingWidth: number,
	fullSwipeLeading: boolean,
	fullSwipeTrailing: boolean,
})
	local self = {}

	function self.axisVerdict(dx: number, dy: number): string
		if dx * dx + dy * dy < row_actions_state.AXIS_LOCK_PX ^ 2 then
			return "pending"
		end
		-- ties go vertical: scrolling must never lose an ambiguous gesture
		return if math.abs(dx) > math.abs(dy) then "horizontal" else "vertical"
	end

	local function edgeFor(offset: number): (string?, number, boolean)
		if offset > 0 then
			return "leading", opts.leadingWidth, opts.fullSwipeLeading
		elseif offset < 0 then
			return "trailing", opts.trailingWidth, opts.fullSwipeTrailing
		end
		return nil, 0, false
	end

	function self.clampDrag(raw: number): number
		local _, tray, fullSwipe = edgeFor(raw)
		local mag = math.abs(raw)
		if fullSwipe or mag <= tray then
			return raw
		end
		return math.sign(raw) * (tray + (mag - tray) * row_actions_state.RESISTANCE)
	end

	function self.settle(offset: number, velocityX: number): Verdict
		local projected = offset + velocityX * row_actions_state.VELOCITY_PROJECT_S
		local edge, tray, fullSwipe = edgeFor(projected)
		if edge == nil or tray <= 0 then
			return { target = 0, edge = nil, commit = false }
		end
		local mag = math.abs(projected)
		if fullSwipe and mag >= opts.rowWidth * row_actions_state.COMMIT_FRACTION then
			return { target = math.sign(projected) * opts.rowWidth, edge = edge, commit = true }
		end
		if mag >= tray * row_actions_state.OPEN_FRACTION then
			return { target = math.sign(projected) * tray, edge = edge, commit = false }
		end
		return { target = 0, edge = nil, commit = false }
	end

	return self
end

return row_actions_state
```

- [ ] **Step 4: Run the spec, verify PASS; run the full suite, verify no regressions**

Run: `lune run tests/run -- tests/row_actions_state.spec.luau` then `./run-tests.sh`
Expected: PASS; suite count grows, zero failures.

- [ ] **Step 5: Commit**

```bash
git add src/input/row_actions_state.luau tests/row_actions_state.spec.luau tests/run.luau
git commit -m "feat(row-actions): pure swipe state module (axis lock, rubber band, settle verdicts)"
```

---

### Task 2: Theme metrics for row actions

**Files:**
- Modify: `src/tokens/default_style.luau` (control metrics block; follow how `controls.slider.*` entries are declared)
- Test: extend `tests/row_actions_state.spec.luau`? No — theme resolution belongs to the composite; add the assertions in Task 3's spec instead. This task only adds tokens + a resolution smoke test in the existing themes spec if one exists (search `tests/` for the spec covering `snapshot.resolveNumber` and add two cases there).

**Interfaces:**
- Produces theme paths consumed by Task 3:
  - `controls.rowActions.buttonMinWidth` = 64 (px; a tray button never narrower)
  - `controls.rowActions.buttonPad` = `"s"`-equivalent 8 (inner horizontal padding)
  - `controls.rowActions.editAffordance` = 28 (edit-mode minus circle diameter)
- Colors: reuse existing `danger` / `onDanger` for destructive, `surfaceStrong` / `content` for normal actions. **No new color tokens.**

- [ ] **Step 1: Add the three metrics to the default theme, copying the exact declaration style of the nearest `controls.*` block in `src/tokens/default_style.luau`**
- [ ] **Step 2: Add two resolution cases to the existing themes/snapshot spec (`snapshot.resolveNumber(snap, "controls.rowActions.buttonMinWidth") == 64`, same for `editAffordance`), run that spec, verify PASS**
- [ ] **Step 3: Run `./run-tests.sh` (theme-shape tests may pin the token tree — fix any legitimately affected pins, never loosen them), commit**

```bash
git add src/tokens/default_style.luau tests/<themes-spec>.spec.luau
git commit -m "feat(row-actions): theme metrics for action trays"
```

---

### Task 3: `newRowActions` composite — spec, blueprints, static reveal

**Files:**
- Create: `src/controls/row_actions.luau`
- Modify: `src/init.luau` (register `newRowActions = require("@self/controls/row_actions").build` next to the other `new*` control lines; do NOT bump VERSION yet — Task 12)
- Test: `tests/row_actions.spec.luau` (+ register in `tests/run.luau`)

**Interfaces:**
- Consumes: `row_actions_state` (Task 1), theme metrics (Task 2), `specGuard`, chip.luau's build/dump/dispose pattern.
- Produces (consumed by Tasks 4–10):

```luau
row_actions.build(LuauUI, core, spec: {
	id: string?,
	content: Blueprint,                 -- required
	leading: { ActionSpec }?,           -- nil = none; {} = spec error
	trailing: { ActionSpec }?,
	fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?, -- default true
}) -> {
	blueprint: Blueprint,
	dump: () -> { schema: string, id: string, offset: number,
	              openEdge: string?, phase: string }, -- phase: closed|dragging|open|committing
	dispose: () -> (),
	-- internal seam for Table + coordinator (NOT public API; underscore prefix):
	_open: (edge: "leading" | "trailing") -> (),
	_close: () -> (),
	_isOpen: () -> boolean,
	_pointerHandlers: PointerHandlers,   -- Task 5 fills these in
	_commitFirst: (edge: "leading" | "trailing") -> boolean, -- Task 5; keyboard Delete path
}

type ActionSpec = {
	id: string?,                        -- defaults to label
	role: ("normal" | "destructive")?,  -- destructive paints danger/onDanger
	label: string,
	icon: string?,                      -- standard_icons name; nil = text only
	onAction: () -> (),
}
```

Blueprint shape (ids matter — tests and Table address them by path):

```
ZStack id=<spec.id or "RowActions">
├─ HStack id="TrayLeading"   (alignH start; hidden width 0 when closed)
│   └─ Button id="Action:<action.id>" per action (fill height; danger bg for destructive)
├─ HStack id="TrayTrailing"  (alignH end)
│   └─ Button id="Action:<action.id>" per action
└─ ZStack id="Content"       (the wrapped row; slides horizontally by `offset`)
```

- [ ] **Step 1: Write the failing tests** — mirror `tests/chip.spec.luau`'s `presenterWorld` harness verbatim (fake_target adapter, `LuauUI.newPresenter`, `pres.present(screen)`). Cases:

```luau
-- tests/row_actions.spec.luau (structure; use chip.spec.luau's world-builder idioms)
it("validates unknown spec keys", ...)          -- expect(...).toThrow with "did you mean"
it("rejects an empty action list", ...)          -- leading = {} → error("use nil")
it("is an inert passthrough with no actions", ...) -- content renders; dump().phase == "closed"; no Tray nodes mounted
it("mounts trailing tray buttons with ids Action:<id>", ...)
it("destructive action paints danger tokens", ...)   -- adapter.node(trayButtonPath).props background/tint
it("labels survive 1.4x pseudo-loc without clipping", ...) -- long label; assert button width >= buttonMinWidth and text not truncated (copy the pattern from an existing localization/text_audit test)
it("_open slides content by tray width; _close returns it; dump reflects openEdge", ...)
it("dispose unmounts and releases the scope", ...)  -- copy chip's disposal assertions
```

- [ ] **Step 2: Run, verify FAIL (`newRowActions` unknown / module not found)**
- [ ] **Step 3: Implement the composite skeleton.** Follow `chip.luau` end-to-end: `ROW_ACTIONS_KEYS = specGuard.keySet({ "content", "fullSwipe", "id", "leading", "trailing" })`; `specGuard.assertKnownKeys("newRowActions", spec, ROW_ACTIONS_KEYS, "spec")`; validate each ActionSpec the same way (`ACTION_KEYS`); normalize `fullSwipe` (boolean → both edges). Compute tray widths: `#actions * max(buttonMinWidth, measured label width + 2*buttonPad)`. Content slide: hold `offset` in a `core:signal(0)`; **investigate how `value_reveal.luau` / the toast slide bind an animated number into blueprint geometry and use that exact mechanism** (expected: a Readable accepted by a position/margin prop or a `syncGeometry` hook; if only direct proxy writes exist — the `drag_registry.writeProxyFor` pattern at `src/input/drag_registry.luau:388-396` — encapsulate that in one `applyOffset(px)` function so later tasks touch nothing else). `_open(edge)` sets offset to the tray width (no animation yet — Task 4). No pointer handling yet.
- [ ] **Step 4: Run spec → PASS; `./run-tests.sh` → no regressions**
- [ ] **Step 5: Commit**

```bash
git add src/controls/row_actions.luau src/init.luau tests/row_actions.spec.luau tests/run.luau
git commit -m "feat(row-actions): newRowActions composite — spec, trays, static reveal"
```

---

### Task 4: Reveal motion (springs, proportional buttons, reduced motion)

**Files:**
- Modify: `src/controls/row_actions.luau`
- Test: extend `tests/row_actions.spec.luau`

**Interfaces:**
- Consumes: presenter's motion clock. The composite receives it the way drag_registry does (`presenter.luau:461-462` creates `self.motionClock`); trace how a composite reaches it — expected path: the presenter/contribution seam. If composites cannot reach the presenter clock today, add an optional `motion` field to the contribution bundle mirroring how `bindActionSystem` is delivered, and have the presenter supply `motionClock` on attach. Keep the fallback: no clock (bare mount in a unit test) = snap to target.
- Produces: `_open/_close` now animate; `_settleTo(verdict)` for Task 5.

Behavior: one spring drives `offset` (`motionClock:spring(0, "object")` — match the class name drag flight uses at `drag_registry.luau:376`). `core:observe(spring, ...)` writes `applyOffset(spring:get())` (dispose pattern: `drag_registry.luau:388-396`). Tray buttons resize proportionally: each button's width = `trayFraction * |offset| / trayWidth`, so buttons "stretch in" with the reveal (SwiftUI feel) — derive per-button width from the same observed value, no second spring. Reduced motion: springs already snap under reduced policy (decorative default) — assert it, don't special-case it.

- [ ] **Step 1: Failing tests** — using the motion-test idiom from `tests/motion_spring.spec.luau:23-30` (`clock:step(FRAME)` loops):
```luau
it("_open animates offset toward tray width over stepped frames", ...) -- after 1 frame: 0 < offset < trayWidth; after 60: toBeCloseTo(trayWidth)
it("buttons grow proportionally with offset", ...)                     -- at half reveal, button width ≈ half its share
it("reduced motion snaps the reveal in one frame", ...)                -- motionPolicy = reduced world; one step → offset == trayWidth
it("dispose mid-flight leaks nothing", ...)                            -- open, step 3 frames, dispose; further steps change nothing
```
- [ ] **Step 2: Run → FAIL. Step 3: implement. Step 4: spec + full suite → PASS. Step 5: Commit** `feat(row-actions): spring reveal with proportional tray buttons`

---

### Task 5: Mouse gesture — axis lock, velocity handoff, full-swipe commit

**Files:**
- Modify: `src/controls/row_actions.luau`
- Test: `tests/row_actions_input.spec.luau` (+ register in `tests/run.luau`)

**Interfaces:**
- Consumes: `row_actions_state.axisVerdict/clampDrag/settle` (Task 1), `drag_velocity` (`tracker.push(x, y, t)` / `tracker.velocity()` — `src/input/drag_velocity.luau`), blueprint PointerHandlers (`src/blueprint.luau:85-88`; window-space positions; `onPointerDown` returns `false` to decline capture).
- Produces: `_pointerHandlers` (attached to the Content hit surface; Table composes them in Task 10), `_commitFirst(edge)`.

Handler lifecycle: pointerDown records origin, returns `true` only tentatively — until axis verdict resolves, moves accumulate; on `"vertical"` → call `onPointerCancel` semantics on itself and release (decline further involvement; see Step 3 note); on `"horizontal"` → drive `offset = state.clampDrag(dx + startOffset)` live and `tracker.push` every move; pointerUp → `verdict = state.settle(offset, vx)`; commit path: spring to off-screen, then collapse row height to 0 over the same spring family, then fire `onAction` exactly once, then `_close()` bookkeeping. `onAction` throw is quarantined (copy the callback-quarantine helper other controls use — grep `quarantine` in `src/`). `_commitFirst(edge)` = the same commit path minus the gesture (keyboard Delete reuses it); returns false if the edge has no actions.

- [ ] **Step 1: Failing tests** — drive pointers headlessly exactly like `tests/drag_public.spec.luau:141-152` (`adapter.driveDragStart/Continue/End` with `pointerType = "mouse"`), stepping the clock between moves:
```luau
it("horizontal drag reveals; release past half-tray snaps open", ...)
it("release under half-tray snaps closed", ...)
it("vertical drag never moves the offset (axis lock)", ...)
it("a leftward flick (velocity) opens from a short drag", ...)
it("full swipe commits: row slides off, collapses, onAction fires exactly once", ...)
it("commit with a throwing onAction still closes and does not refire", ...)
it("fullSwipe = { trailing = false } refuses to commit on trailing", ...)
it("_commitFirst('trailing') fires the first trailing action once", ...)
it("pointer cancel mid-drag springs back to closed", ...)
```
- [ ] **Step 2: FAIL. Step 3: implement. Step 4: PASS + full suite. Step 5: Commit** `feat(row-actions): pointer gesture with axis lock, flick, full-swipe commit`

---

### Task 6: Touch path spike, then touch input wiring

The one platform unknown: whether row-level pointer/gesture events fire for touch pans inside a native vertically-scrolling Body, and whether accepting them fights native scroll. Reorder deliberately declines touch (`table.luau:821-823` returns false so native scroll owns the pan) — but a *horizontal* pan doesn't scroll a Y-only ScrollingFrame, which is what makes swipe viable.

**Files:**
- Create: `artifacts/row-actions/touch-spike.md` (findings; decision record)
- Modify: `src/controls/row_actions.luau` (whichever path wins)
- Test: extend `tests/row_actions_input.spec.luau` with `pointerType = "touch"` variants of Task 5's cases (headless), plus the Studio canary below.

- [ ] **Step 1: Spike in Studio (timebox ~1h).** Use the open empty place. Sync a minimal fixture (a Y-scrolling list of rows built with `newRowActions`) via the examples pipeline (see `docs/` for the showcase sync recipe — memory: HTTP source push + `LuauUIShowcaseAPI`). With the device emulator emitting touch input, test two candidates and record which delivers usable horizontal pans without breaking vertical scroll: (a) blueprint PointerHandlers with `pointerType == "touch"` accepted on down + axis lock, (b) engine TouchPan via `touch_gestures.normalize`/`newArbiter` fed from the row's adapter events. Note: the emulator cannot produce `preferredInput = Touch` (known trap) — that only affects preferred-input styling, not touch event delivery; say so in the artifact.
- [ ] **Step 2: Write `artifacts/row-actions/touch-spike.md`** — candidate, evidence (what fired, what scrolled), decision, and the exact wiring chosen.
- [ ] **Step 3: Implement the winning path behind the same `_pointerHandlers`/state seam (no new decision logic — the state module already owns axis lock and settle).**
- [ ] **Step 4: Headless touch-variant tests PASS + full suite. Step 5: Commit** `feat(row-actions): touch swipe wiring (spike-verified)` including the artifact.

---

### Task 7: Open-state coordinator + outside-tap/scroll close

**Files:**
- Modify: `src/controls/row_actions.luau`
- Test: extend `tests/row_actions_input.spec.luau`

**Interfaces:**
- Consumes: contribution bundle (`popup_button.luau:338-346` is the reference: `outsideDismiss = { active, dismiss }`, `handleCancel`), `controller.observeScroll(path, cb)` (`table.luau:2178` shows usage post-present).
- Produces: `row_actions.newCoordinator(core)` — **PUBLIC API**, registered in `src/init.luau` as `newRowActionsCoordinator` (director decision 2026-08-09: plain VStack/ScrollView lists wrap rows themselves and share a coordinator for one-open + scroll-close; Table just does this wiring for you). The build spec gains a public `coordinator` key (add to `ROW_ACTIONS_KEYS`; optional). →

```luau
{
	claim: (instance) -> (),   -- closes the previously open instance
	release: (instance) -> (),
	bindScroll: (controller, path: string) -> () -> (), -- any scroll movement closes the open row
}
```

The `coordinator` spec key is optional (Table passes one shared coordinator to every row's wrapper; a VStack list creates its own via `newRowActionsCoordinator` and passes it to each wrapped row; standalone use without one stays valid — each instance then only manages itself). On `_open`/gesture-reveal past the axis lock: `coordinator.claim(self)`. Outside-tap: attach `outsideDismiss` with `active` = an `isOpen` Readable and `dismiss = _close`. **Pin the round-7 lesson:** the dismiss must not swallow the click that lands on another row — assert the second row's tap still registers (see spec "does-not-swallow-unrelated-clicks").

- [ ] **Step 1: Failing tests:**
```luau
it("opening row B closes row A", ...)
it("scroll movement closes the open row", ...)          -- fire the observeScroll callback
it("outside tap closes AND the tapped control still receives its press", ...)
it("Cancel (handleCancel) closes an open row and reports handled", ...)
it("a row unmounting while open clears its coordinator entry", ...)
it("a VStack of wrapped rows sharing newRowActionsCoordinator gets one-open behavior", ...)
```
- [ ] **Step 2: FAIL. Step 3: implement. Step 4: PASS + suite. Step 5: Commit** `feat(row-actions): one-open coordinator, outside-tap and scroll dismissal`

---

### Task 8: Keyboard + gamepad — Delete key and the action menu

**Files:**
- Modify: `src/controls/row_actions.luau`
- Test: extend `tests/row_actions_input.spec.luau`

**Interfaces:**
- Consumes: `bindActionSystem` contribution (presenter action wiring at `presenter.luau:2461-2516`; PopupButton is the model for a transient focus-trapped panel: `outsideDismiss + transientScope + handleCancel` + `UI.When`-mounted panel of focusable Buttons), `system.deviceKey("<key>", pressed)` for tests.
- Produces: two input actions scoped to the wrapper while its content subtree holds focus:
  - `"RowActionsDelete"` — `Delete` and `Backspace` keys → `_commitFirst` on the first `destructive` action (trailing list searched first, then leading). No destructive action = the binding is not registered at all.
  - `"RowActionsMenu"` — `Shift+Return` and gamepad `ButtonX` → toggles a small menu (PopupButton-pattern panel listing every action as a focusable Button; Activate runs the action and closes; Cancel closes).

- [ ] **Step 1: Failing tests:**
```luau
it("Delete on a focused row fires the first destructive action", ...)   -- focus the row content, system.deviceKey("Delete", true/false)
it("Delete does nothing when no destructive action exists", ...)
it("Shift+Return opens the menu; Activate on an item runs it and closes", ...)
it("ButtonX opens the same menu", ...)
it("Cancel closes the menu without firing anything", ...)
it("menu traps focus while open (transientScope)", ...)
```
- [ ] **Step 2: FAIL. Step 3: implement (copy popup_button's contribution bundle shape wholesale). Step 4: PASS + suite. Step 5: Commit** `feat(row-actions): Delete key and Shift+Return/ButtonX action menu`

---

### Task 9: Edit-mode affordance (leading minus)

**Files:**
- Modify: `src/controls/row_actions.luau` (accept an internal `editing: Readable<boolean>?` seam field)
- Test: extend `tests/row_actions.spec.luau`

Behavior (iOS pattern): while `editing` is true and the row has a destructive action, a leading minus button (diameter `controls.rowActions.editAffordance`, `danger` glyph on `surfaceStrong`) appears via `UI.When` — same conditional-mount pattern as Table's handle (`table.luau:1079-1122`). Activating it opens the trailing tray with the destructive action emphasized (just `_open("trailing")` — the tray already paints destructive in danger). It does NOT delete directly (matches iOS: minus reveals Delete, a second tap confirms).

- [ ] **Step 1: Failing tests:** minus absent when not editing / absent when no destructive action / tap opens trailing tray.
- [ ] **Step 2–4: FAIL → implement → PASS + suite. Step 5: Commit** `feat(row-actions): edit-mode delete affordance`

---

### Task 10: Table integration

**Files:**
- Modify: `src/controls/table.luau`
- Test: extend `tests/table.spec.luau` (integration block) and `tests/row_actions_input.spec.luau` (reorder-vs-swipe arbitration)

**Interfaces:**
- Consumes: everything above. Anchors in `table.luau`: `TABLE_KEYS` (line 167-187), `rowBlueprint` return (line 1124-1129), `rowPointerHandlers` (line 783), `editingSignal` (line 317-321).
- Produces public Table spec key:

```luau
rowActions: ((item: any) -> { leading: { ActionSpec }?, trailing: { ActionSpec }?,
                              fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })? }?)?
```

Implementation notes (verify each against the live file before editing):
1. Add `"rowActions"` to `TABLE_KEYS`.
2. In `rowBlueprint`, when `spec.rowActions` returns non-nil for the item: build a `row_actions` instance wrapping the row ZStack (the line-1124 return value becomes the `content`), passing the table-owned shared coordinator (create one per table in the build scope) and `editingSignal` as the editing seam.
3. **Per-row instance lifecycle:** keep `rowActionsByKey: { [string]: instance }` in the table scope. On each rows rebuild, dispose entries whose key is gone; dispose all on table dispose. Find where Table already reacts to `spec.rows` changes (the ForEach/reorder bookkeeping) and hook the same place — do not add a second rows observer.
4. **Pointer composition with reorder:** the Hit Button currently gets reorder's handlers (line 1059-1062). Replace with a composed dispatcher: reorder declines touch already; for mouse, route through the axis lock — `vertical` → forward the whole gesture to reorder's handlers (replaying the down at its origin), `horizontal` → row_actions. The dispatcher lives in `row_actions` as a small exported helper `row_actions.composeWithReorder(rowHandlers, reorderHandlers, state)` so table.luau stays thin.
5. Keyboard Delete/menu bind per-row via the wrapper (Task 8) — nothing extra in table.luau beyond passing focus-scope info if the contribution needs the row's focus root path.

- [ ] **Step 1: Failing tests:**
```luau
it("rowActions wraps only rows whose callback returns actions", ...)   -- nil rows have no RowActions node in the tree
it("unknown keys inside the returned action table error at build", ...)
it("swiping row B closes row A (shared coordinator through Table)", ...)
it("mouse vertical drag on a reorderable row still reorders", ...)     -- existing reorder test pattern, now through the dispatcher
it("mouse horizontal drag on the same row reveals actions instead", ...)
it("editing signal shows the minus on rows with a destructive action", ...)
it("rows removed from spec.rows dispose their wrapper (no leak)", ...) -- mirror the framework's leak assertions (grep "leak" in tests/ for the idiom)
it("a data refresh mid-gesture cancels: onAction never fires for a replaced key", ...)
it("Delete key on a focused row deletes via the row's destructive action", ...)
```
- [ ] **Step 2: FAIL. Step 3: implement. Step 4: PASS + FULL suite (this touches reorder — run `tests/table*.spec.luau` and `tests/paradigm_table.spec.luau` first, then everything). Step 5: Commit** `feat(row-actions): Table rowActions integration with reorder-composed gestures`

---

### Task 11: Example fixture + Studio five-view device matrix

**Files:**
- Create: an example under `examples/` following the gallery registration pattern (grep how `ex02` registers; add the next free slot) — a mail-style list: trailing = Delete (destructive) + Flag, leading = Mark Read. Two surfaces: (1) a plain **VStack in a ScrollView** with hand-wrapped rows sharing a `newRowActionsCoordinator` (proves the non-Table path), (2) a reorderable, editable Table using `rowActions`.
- Create: `artifacts/row-actions/device-matrix.md` (evidence: per-view screenshots + diagnostics output)

- [ ] **Step 1: Build the example; every fixture calls `controller.diagnostics()` and the example fails loudly on findings.**
- [ ] **Step 2: Sync to the open Studio place (HTTP source push recipe), drive the five-view matrix via the `LuauUIScenarioAPI` BindableFunctions (traps: `run()` returns a JSON *string*; `compact-phone-landscape` needs `pinnedDeviceId`; sweep includes 320×640). At each view: swipe-open, full-swipe delete, keyboard Delete, ButtonX menu, edit-mode minus, reorder still works.**
- [ ] **Step 3: Capture screenshots into the artifact; run diagnostics at every view; record PASS/FAIL per cell in `device-matrix.md`.**
- [ ] **Step 4: Fix anything found (loop). Step 5: Commit** `test(row-actions): gallery example + five-view device matrix evidence`

---

### Task 12: Gate checks, version, API docs

**Files:**
- Modify: `tools/lune/gate_manifest.luau` (new checks), `src/init.luau` (VERSION → next minor per ADR-0011, update the ADR), `docs/reference/api.md` (careful: file has uncommitted local edits — read first, add the `newRowActions` + Table `rowActions` sections without disturbing them)

- [ ] **Step 1: Add gate checks (Form A only), e.g.:**
```luau
{
	name = "row-actions-suite",
	requirements = { "ROW-ACTIONS-001" },
	run = 'out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*full swipe commits" && echo "$out" | grep -q "✓.*closes row A" && echo "$out" | grep -q "✓.*axis lock"',
},
{
	name = "row-actions-device-matrix",
	requirements = { "ROW-ACTIONS-001" },
	run = 'f=artifacts/row-actions/device-matrix.md && test -f "$f" && ! grep -q "FAIL" "$f" && ! grep -qE "PENDING" "$f"',
	evidence = "artifacts/row-actions/device-matrix.md",
},
```
(bare PENDING states make gates un-passable — only add rows you can complete.)
- [ ] **Step 2: Run `python tools/check_manifest_integrity.py` (manifest integrity, catches Form-B mistakes) and the relevant gate via `tools/gate.sh`; confirm each new check can actually fail (mutate one grep target, watch it go red, restore — confirm the mutation BITES).**
- [ ] **Step 3: Bump VERSION + ADR-0011 note; update `docs/reference/api.md`. Step 4: Commit** `feat(row-actions): gate checks, version bump, API reference`

---

### Task 13: RascalRally consumer compatibility evidence

Per the root constitution: LuauUI changes ship with Rascal Rally consumer work in the same task. No RR Table uses `rowActions` yet, so the expected deliverable is **evidence, not edits**.

**Files:**
- Create: `artifacts/row-actions/rr-compat.md`

- [ ] **Step 1: Grep RR (`games/RascalRally/code`) for every `newTable`/Table spec-key usage; confirm none passes unknown keys that the new validation would now reject and that no public contract changed shape.**
- [ ] **Step 2: Run RR's relevant test suite (see `games/RascalRally` docs for the command; suite was ~3094) and one affected-game Studio canary (load the game place, exercise one Table surface, run diagnostics).**
- [ ] **Step 3: Record commands + outputs in `rr-compat.md`. Commit** `test(row-actions): RascalRally compatibility evidence`

---

### Task 14: Full swiftui-parity re-audit

**Files:**
- Modify: `docs/reference/swiftui-parity.md` — **it has uncommitted local edits; `git diff docs/reference/swiftui-parity.md` FIRST and reconcile, never clobber.**

- [ ] **Step 1: Read the current doc + its uncommitted diff; inventory its item list and section structure.**
- [ ] **Step 2: Dispatch fresh-context subagents, one per area (state/reactivity, layout, controls, styling/theming, input/accessibility, motion, performance, tooling/preview), each given: the area's old audit verdicts, the current SwiftUI (June 2026/Xcode 27) baseline for that area (WebSearch as needed), and instructions to re-verdict every item against today's LuauUI citing file/test evidence — no verdict without a citation. Fresh context is the point: old judgments must not survive by inertia.**
- [ ] **Step 3: Synthesize into the doc: new validation date (today), per-area verdict tables, an explicit "changed since 2026-07-22" section, the swipeActions row flipped to covered citing `newRowActions` + `tests/row_actions*.spec.luau`, LuauUI version updated (0.5.0 → the Task-12 version).**
- [ ] **Step 4: One fresh-context reviewer subagent reads only the final doc for internal consistency and unsupported claims; fix findings.**
- [ ] **Step 5: Commit** `docs: full swiftui-parity re-audit against v0.<N> (row actions shipped)`

---

### Task 15 (optional, deferrable): trash + flag icons

The standard icon set has no delete/trash glyph (nearest: `close`, `edit`, `more` — `src/themes/standard_icons.luau:50-106`). Text-only actions ship fine (icon nil → label). If the director wants glyphs:

- [ ] Generate `trash` and `flag` icons via the art pipeline (`GameStudio/ART_PIPELINE.md`), upload headlessly via Open Cloud with `assetType="Image"` (the compactLabel recipe), add entries to `standard_icons.ART`, and extend the icon spec test. Commit `feat(row-actions): trash/flag standard icons`.

---

## Execution order & review gates

Tasks 1→10 are strictly ordered. 11–13 can interleave after 10. 14 runs last (needs the shipped feature). After Task 10 and again after Task 13: dispatch the RED-TEAM `code-reviewer` agent (fresh context) over the diff; fix findings before proceeding. Physical-device confirmation remains the standing pending rider (Studio emulator cannot produce `preferredInput=Touch`).

---

### Task 8b: Input Action System modifier support + Shift+Return menu binding (director-approved 2026-08-10)

**Why:** Task 8 proved Shift+Return inexpressible — the action system has no key-modifier concept, and Return is the screen's Activate. Director chose the root fix over a plain-key workaround.

**Files:** src/input/ (action system binding layer), src/present/presenter.luau (binding wiring), src/controls/row_actions.luau (bind Shift+Return once expressible), tests (action-system modifier specs + row_actions menu-key cases). All presenter/input files are foreign-M → surgical staging.

- [ ] **Step 1: Investigate** how bindings are declared and matched today (the exact structures Task 8's report §Shift+Return analysis maps out). Design the smallest additive modifier slot: a binding may declare `modifiers = { shift = true }` (ctrl/alt reserved but valid); matching requires declared modifiers held and — decision to verify — whether a modifier-bound key must PREEMPT the unmodified binding of the same key (Shift+Return must not also fire Activate). Follow the action system's existing precedence rules; write the design into the report before coding.
- [ ] **Step 2: TDD the action system change** in the input-system spec file (failing tests: modified binding fires only with modifier held; unmodified binding unaffected when modifier NOT held; modified binding preempts unmodified same-key binding when held; gamepad bindings ignore modifier slots).
- [ ] **Step 3: Implement minimally**; full suite (the action system has deep existing coverage — zero regressions).
- [ ] **Step 4: Bind RowActionsMenu to Shift+Return** in row_actions.luau; menu tests: Shift+Return toggles; plain Return still activates content; Shift+Return while menu open = close (toggle).
- [ ] **Step 5: Registry/docs**: inputProofs citation for the keyboard menu path; api.md note. Commit `feat(row-actions): Shift+Return menu via action-system modifier support` + trailers.
