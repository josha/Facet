# Facet Transitions Round Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the transitions.dev motions Facet lacks (faster exits, Alert/Menu materialize, toggle overshoot, focus-lift spring, list stagger, input shake, radial and button pops, disclosure motion) without moving any perf scene more than +10%.

**Architecture:** Every addition is paint-only: it writes the presentation channel (`offset`/`scale`/`rotation`/`opacity`, or the structural-transition coordinator's own progress spring) and never the solver. Springs come from the presenter's motion clock through each control's `bindMotion` contribution hook; native-paint tweens (toggle knob, focus lift) use `TweenService` guarded by `isReducedMotion()`. New vocabulary is two words: the `dismiss` motion class and the `exitClass` / `stagger` transition fields.

**Tech Stack:** Luau (Roblox), Lune headless test runner (`./run-tests.sh`), stylua, `tools/perf.sh` perf gate, `tools/verify.sh full`, Rojo + Roblox Studio for the two device canaries.

**Spec:** `docs/superpowers/specs/2026-09-12-facet-transitions-design.md`

## Global Constraints

- Work in `GameStudio/ui/Facet` (all paths below are relative to it unless prefixed `RR:` = `games/RascalRally/code`).
- Paint-only law: no motion may write `Size`, a layout prop, or trigger a solve. Pinned by Task 13.
- Zero new Instances for motion. The only sanctioned exception is the documented icon-swap recipe (two stacked images during one fade).
- Idle is free: a settled value must stop writing. Pinned by Task 13.
- `src/render/renderer.luau` is at 196,755 of the 200,000-char Source write cap: **do not edit it**. `src/present/presenter.luau` (193,610) and `src/client/screen_target.luau` (187,811) get at most a few hundred characters each; check with `wc -c` after editing.
- Every new spring/timeline is `kind = "decorative"` (the default): reduce-motion places it instantly and fires the same settle.
- Exit cap: the flat 500 ms `EXIT_CAP_SECONDS` in `src/render/transitions.luau:46` stays.
- Perf: after Tasks 2, 3, 10 and 14, `tools/perf.sh` must pass AND no existing scene's `observed_p95_ms` in `bench/perf_budgets.json` may rise more than 10% vs. the committed file (`git diff bench/perf_budgets.json` after a `tools/perf.sh` run; the runner rewrites `observed_*` fields). `picker-menu-open-close` and `radial-menu-open-close` are the sensitive rows.
- Commit messages: sentence-case subject like the log (`git log --oneline -5`), body optional, and end with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Q3CdDrUWvKjteS28qMyAhi
  ```
- Register every new spec file in `tests/run.luau` by appending `require("./<name>.spec")` immediately above `local ok = testkit.run({`. The fast tier derives from that list.
- Format with `stylua src tests bench` before each commit (rokit toolchain: `export PATH="$HOME/.rokit/bin:$PATH"`).
- Test runner: `./run-tests.sh --fast` for the inner loop, `./run-tests.sh` (full, ~270 s) before each commit that touches `src/`.
- Rascal Rally consumes `src/` directly. Task 6 and Task 16 carry the consumer work; do not skip them.

---

## File map

| File | Responsibility in this plan |
|---|---|
| `src/motion/classes.luau` | `dismiss` built-in class (Task 1) |
| `src/blueprint_schema.luau` | `exitClass` (Task 1) and `stagger` (Task 8) transition keys |
| `src/render/transitions.luau` | per-phase class retune (Task 1); stagger delay (Task 8) |
| `src/controls/alert.luau` | materialize in/out (Task 2) |
| `src/controls/menu.luau` | materialize popover (Task 3) |
| `src/client/screen_paint.luau` | toggle knob overshoot easing (Task 4) |
| `src/client/screen_target.luau` | ten-foot focus lift tween (Task 5) |
| `src/controls/text_input.luau` | `invalid` signal + shake (Task 9) |
| `src/controls/radial_menu.luau` | bloom stagger, hover lift, commit pop (Task 10) |
| `src/controls/button.luau` | `pop` release overshoot (Task 11) |
| `src/controls/disclosure_group.luau` | caret rotation, content slide, `presenter` glide (Task 12) |
| `tests/motion_paint_only.spec.luau` | the paint-only + idle-free gate (Task 13) |
| `bench/perf_scenes.luau`, `tools/check_perf_scenes.py`, `bench/perf_budgets.json` | `control-motion` scene (Task 14) |
| `docs/reference/api.md`, `docs/guide/15-adaptive-recipes.md`, `CHANGELOG.md` | docs + recipes (Task 15) |
| `RR: tests/facet_transition_contract.spec.luau` | consumer contract (Tasks 6, 16) |

---

### Task 1: `dismiss` class and asymmetric `exitClass` (spec 1C)

**Files:**
- Modify: `src/motion/classes.luau:67-72`
- Modify: `src/blueprint_schema.luau:200-201` (TRANSITION_KEYS), `:648-690` (validator)
- Modify: `src/render/transitions.luau:53` (defaults), `:69-78` (Spec type), `:90-109` (resolve), `:508-540` (entryFor), `:564-615` (beginEnter), `:641-662` (beginExit)
- Test: `tests/motion_spring.spec.luau:42,71`, `tests/transitions.spec.luau` (new describe)

**Interfaces:**
- Produces: motion class `"dismiss"` = `{ dampingRatio = 1.0, response = 0.2 }`; transition field `exitClass?: string` (default `"dismiss"`); `transitions.resolve(declared).exitClass`.

- [ ] **Step 1: Update the class-vocabulary pins to expect `dismiss`**

In `tests/motion_spring.spec.luau` change line 42 to:
```lua
expect(classes.names()).toEqual({ "container", "decay", "dismiss", "object", "reward" })
```
and line 71's expected substring to `"container, decay, dismiss, object, reward"`. Add inside the same `describe("motion classes (the vocabulary)"` block:
```lua
it("ships dismiss as the faster exit twin of container", function()
	expect(classes.resolve("dismiss").dampingRatio).toBe(1.0)
	expect(classes.resolve("dismiss").response).toBe(0.2)
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `lune run tests/run_fast 2>&1 | grep -A3 "motion classes"`
Expected: FAIL — names list lacks `dismiss`.

- [ ] **Step 3: Add the class**

In `src/motion/classes.luau` `BUILT_IN`:
```lua
local BUILT_IN: { [string]: Class } = {
	container = { dampingRatio = 1.0, response = 0.35 },
	object = { dampingRatio = 1.0, response = 0.28 },
	reward = { dampingRatio = 0.7, response = 0.18 },
	decay = { dampingRatio = 1.0, response = 0.5 },
	-- the EXIT twin of `container` (transitions round 2026-09-12): closes read
	-- best ~1.7x faster than opens (transitions.dev's 250/150 ms pairing), and a
	-- structural exit defaults to it — see render/transitions.luau `exitClass`
	dismiss = { dampingRatio = 1.0, response = 0.2 },
}
```

- [ ] **Step 4: Write the coordinator test**

Append to `tests/transitions.spec.luau` (uses the file's own `world`, `attach`, `whenScreen`, `FRAME` helpers):
```lua
describe("transition coordinator: exits are faster than enters by default", function()
	local function framesUntilIdle(clock: any): number
		local n = 0
		while clock:activeCount() > 0 and n < 600 do
			clock:step(FRAME)
			n += 1
		end
		return n
	end

	it("a default fade exits in fewer frames than it entered", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, _, controller, coordinator = attach(core, env, clock, whenScreen(on, { enter = "fade" }))
		local enterFrames = framesUntilIdle(clock)
		on:set(false)
		local exitFrames = framesUntilIdle(clock)
		controller.refresh()
		expect(enterFrames > 0).toBe(true)
		expect(exitFrames < enterFrames).toBe(true)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("exitClass restores symmetry when declared", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, _, controller, coordinator =
			attach(core, env, clock, whenScreen(on, { enter = "fade", class = "container", exitClass = "container" }))
		local enterFrames = framesUntilIdle(clock)
		on:set(false)
		local exitFrames = framesUntilIdle(clock)
		controller.refresh()
		expect(exitFrames).toBe(enterFrames)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("a re-entry mid-exit keeps its velocity across the retune", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, whenScreen(on, { enter = "fade" }))
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		on:set(false)
		for _ = 1, 4 do
			clock:step(FRAME)
		end
		local panel = adapter.node("/S/Gate/then/Panel")
		local midway = panel.canvasGroupInstance.groupTransparency
		expect(midway > 0 and midway < 1).toBe(true)
		on:set(true)
		-- the value is continuous across the class swap: no jump on the reversal frame
		expect(panel.canvasGroupInstance.groupTransparency).toBe(midway)
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		expect(panel.canvasGroupInstance.groupTransparency).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("resolve fills exitClass with dismiss and refuses a non-string", function()
		local spec = transitionsLib.resolve({ enter = "fade" })
		expect(spec.class).toBe("container")
		expect(spec.exitClass).toBe("dismiss")
		local ok, err = pcall(transitionsLib.resolve, { enter = "fade", exitClass = 3 })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "exitClass", 1, true) ~= nil).toBe(true)
	end)
end)
```

- [ ] **Step 5: Run to verify it fails**

Run: `lune run tests/run_fast 2>&1 | grep -B2 -A6 "faster than enters"`
Expected: FAIL — `unknown transition field 'exitClass'`.

- [ ] **Step 6: Schema — accept `exitClass`**

In `src/blueprint_schema.luau` replace the `TRANSITION_KEYS` literal with:
```lua
local TRANSITION_KEYS: { [string]: boolean } =
	{ enter = true, exit = true, class = true, exitClass = true, fade = true, distance = true, pivot = true }
```
In the `transition = function(v)` validator, change the unknown-field message to
`(enter | exit | class | exitClass | fade | distance | pivot)` and add after the `class` check:
```lua
local exitClass = (v :: any).exitClass
if exitClass ~= nil and (type(exitClass) ~= "string" or exitClass == "") then
	return false,
		'exitClass names the MOTION CLASS the exit runs on (default "dismiss", the faster twin of "container")'
end
```

- [ ] **Step 7: Coordinator — resolve, retune, and use it**

In `src/render/transitions.luau`:

Add beside `DEFAULT_CLASS`:
```lua
local DEFAULT_EXIT_CLASS = "dismiss"
```
Add `exitClass: string,` to `export type Spec` after `class`. In `transitions.resolve` add `exitClass = declared.exitClass or DEFAULT_EXIT_CLASS,` to the returned table.

In `entryFor`, record the class the spring was built with — add `class = spec.class,` to the `entry` literal — and move the observe/onSettle wiring into a reusable local declared **above** `entryFor`:
```lua
	-- the progress spring's two listeners, wired once per spring (entryFor builds
	-- the first; retune builds a replacement when the phase's class differs)
	local function listen(entry: any)
		entry.unobserve = core:observe(entry.progress, function()
			writeEntry(entry)
		end)
		entry.progress:onSettle(function()
			if entry.phase == "enter" then
				finishEnter(entry)
			elseif entry.phase == "exit" then
				finishExit(entry)
			end
		end)
	end

	-- ONE SPRING PER TRANSITION still holds; what changes between phases is its
	-- CLASS. A MotionValue's class is fixed at construction, so a phase that
	-- wants a different one gets a fresh spring seeded with the old value AND
	-- velocity — the reversal keeps its momentum exactly as before.
	local function retune(entry: any, class: string)
		if entry.class == class then
			return
		end
		local old = entry.progress
		local fresh = clock:spring(old:get(), class)
		fresh:setVelocity(old:getVelocity())
		if entry.unobserve ~= nil then
			entry.unobserve()
			entry.unobserve = nil
		end
		old:dispose()
		entry.progress = fresh
		entry.class = class
		listen(entry)
	end
```
Replace the inline `entry.unobserve = core:observe(...)` / `entry.progress:onSettle(...)` block in `entryFor` with `listen(entry)`. (Check `disposeEntry` at `:468` already calls `entry.unobserve()` and `entry.progress:dispose()`; if it indexes them unguarded, leave it — both are always set after `listen`.)

In `beginEnter`, after `local entry = entryFor(path, node, spec, 0, alphaPath)` add `retune(entry, spec.class)`.
In `beginExit`, after `local entry = entryFor(path, node, spec, 1, alphaPath)` add `retune(entry, spec.exitClass)`.

- [ ] **Step 8: Run the tests**

Run: `lune run tests/run_fast 2>&1 | tail -5`
Expected: PASS, including `tests/transitions.spec.luau` and `tests/motion_spring.spec.luau`. If a pre-existing transitions test pins an exit alpha at a specific frame, re-read it: exits are now faster, so a "still mid-flight at frame N" assertion may need N lowered. Change only the frame count, never the assertion's meaning.

- [ ] **Step 9: Full suite + format + commit**

```bash
export PATH="$HOME/.rokit/bin:$PATH"; stylua src tests && ./run-tests.sh 2>&1 | tail -3
git add src/motion/classes.luau src/blueprint_schema.luau src/render/transitions.luau tests/motion_spring.spec.luau tests/transitions.spec.luau
git commit -m "Transitions: exits run on the faster dismiss class by default (exitClass)"
```

---

### Task 2: Alert materializes in and dips out (spec 1A)

**Files:**
- Modify: `src/controls/alert.luau:39-57` (KEYS), `:523-530` (Center ZStack), `:613-616` (presentModal)
- Test: `tests/alert.spec.luau` (new `it`)

**Interfaces:**
- Consumes: Task 1's `exitClass` default.
- Produces: `AlertSpec.transition?` (a transition table or `"instant"`), default `{ enter = "materialize" }`.

- [ ] **Step 1: Write the failing test**

Append to `tests/alert.spec.luau`, using its `fixture(opts, spec)` helper (read lines 7-30 first; it returns the world `w` and the built alert; `w.pres` is the presenter, `w.adapter` the fake target):
```lua
describe("alert: the modal materializes", function()
	local FRAME = 1 / 60
	it("enters through a fade group and leaves faster than it came", function()
		local w, alert = fixture({}, { id = "Confirm", title = "Delete?", actions = { { id = "ok", label = "OK" } } })
		local handle = alert.present()
		local center = w.adapter.node("/Confirm/Center")
		expect(center.canvasGroupInstance ~= nil).toBe(true)
		expect(center.canvasGroupInstance.groupTransparency).toBe(1)
		local enterFrames = 0
		while center.canvasGroupInstance.groupTransparency > 0 and enterFrames < 600 do
			w.pres.tick(FRAME)
			enterFrames += 1
		end
		expect(enterFrames > 0).toBe(true)
		w.pres.dismiss(handle)
		local exitFrames = 0
		while w.adapter.node("/Confirm/Center") ~= nil and exitFrames < 600 do
			w.pres.tick(FRAME)
			exitFrames += 1
		end
		expect(exitFrames < enterFrames).toBe(true)
	end)

	it("transition = 'instant' opts out", function()
		local w, alert = fixture({}, {
			id = "Quick",
			title = "Hi",
			actions = { { id = "ok", label = "OK" } },
			transition = { enter = "instant" },
		})
		alert.present()
		expect(w.adapter.node("/Quick/Center").canvasGroupInstance.groupTransparency).toBe(0)
	end)
end)
```
If `fixture`'s signature differs from `(opts, spec)`, adapt the two calls to it; the assertions stay.

- [ ] **Step 2: Run to verify it fails**

Run: `lune run tests/run_fast 2>&1 | grep -B2 -A6 "modal materializes"`
Expected: FAIL — unknown spec key `transition` / `canvasGroupInstance` nil.

- [ ] **Step 3: Implement**

In `src/controls/alert.luau`:
- add `"transition",` to `KEYS`.
- make the Center ZStack the fade group: `UI.ZStack({ id = "Center", canvasGroup = true, width = UI.fill(), height = UI.fill(), children = { content } })`.
- the presentModal call becomes:
```lua
handle = presenter.presentModal(blueprint, {
	initialFocus = if initial then { id = initial } else nil,
	outsideTapCancel = false,
	-- the modal open (transitions round 2026-09-12): scale 0.96 → 1 with a
	-- fade, and the default `dismiss` exit dips out faster than it came
	transition = spec.transition or { enter = "materialize" },
})
```

- [ ] **Step 4: Run tests, then the transient-surface bench proof**

Run: `lune run tests/run_fast 2>&1 | tail -3` → PASS.
Run: `tools/perf.sh 2>&1 | tail -15` → PASS; then `git diff --stat bench/perf_budgets.json` and eyeball `alert-present-dismiss`'s `observed_p95_ms` (≤ +10%). Do **not** commit `bench/perf_budgets.json` in this task; `git checkout bench/perf_budgets.json`.

- [ ] **Step 5: Commit**

```bash
stylua src tests && ./run-tests.sh 2>&1 | tail -3
git add src/controls/alert.luau tests/alert.spec.luau
git commit -m "Alert: the modal materializes in and dismisses on the faster exit class"
```

---

### Task 3: Menu popover materializes from its anchor (spec 1B)

**Files:**
- Modify: `src/controls/menu.luau:677-695` (panel wrapper), `:836-858` (presentAnchored opts, `sourcePath`)
- Test: `tests/menu.spec.luau` (`rowPath`/`sheetRow` helpers at `:107-115`, new `it`), `tests/menu_scenario.spec.luau` (path pins, if any)

**Interfaces:**
- Produces: the floating menu panel is wrapped in `/…/Popup/Panel`; sheets are unchanged.

- [ ] **Step 1: Write the failing test**

In `tests/menu.spec.luau` append (use the file's `world(opts)` helper and its open-menu helper; read `:50-120` first):
```lua
describe("menu: the floating panel materializes", function()
	local FRAME = 1 / 60
	it("fades and grows in, then leaves faster", function()
		local w = world({})
		-- open the menu exactly as the file's other tests do (its helper), then:
		local popup = w.adapter.node(rowPath(0, "Cut"):gsub("/Panel/Item:Cut$", "/Popup"))
		expect(popup ~= nil and popup.canvasGroupInstance ~= nil).toBe(true)
		expect(popup.canvasGroupInstance.groupTransparency).toBe(1)
		for _ = 1, 90 do
			w.pres.tick(FRAME)
		end
		expect(popup.canvasGroupInstance.groupTransparency).toBe(0)
	end)
end)
```
Update `rowPath` so a level-0 floating row reads `/{surfaceId}/Layer/Surface/Popup/Panel/Item:{id}`; `sheetRow` stays on `/Panel/` (a sheet is not wrapped).

- [ ] **Step 2: Run to verify it fails**

Run: `lune run tests/run_fast 2>&1 | grep -B2 -A6 "panel materializes"` → FAIL (no `Popup` node).

- [ ] **Step 3: Implement**

In `src/controls/menu.luau`, where the panel builder ends `return panel` (`:695`):
```lua
		if isSheet then
			return panel
		end
		-- the FADE GROUP the materialize transition needs (picker_menu's exact
		-- `Popup` shape, 2026-09-11): one CanvasGroup around the floating panel so
		-- it grows in as one plate rather than row by row
		return UI.ZStack({
			id = "Popup",
			canvasGroup = true,
			width = { type = "hug" },
			height = { type = "content" },
			children = { panel },
		})
```
Change the submenu `sourcePath` (`:843`) to include the wrapper for floating levels: `/{surfaceIdFor(level - 1)}/Layer/Surface/Popup/{PANEL_ID}/Item:{last}` (keep the sheet form if `isSheet`; read how `isSheet` is scoped there — if the panel builder's `isSheet` is not in scope at `:843`, hoist it to a local computed once per open).

In the `presentAnchoredFn` opts add:
```lua
				-- the short fade-and-grow every pop-up menu materializes with; an
				-- anchored surface with no pivot of its own grows from the corner it
				-- hangs at (render/transitions `pivot` inference)
				transition = if isSheet then nil else { enter = "materialize" },
```

- [ ] **Step 4: Fix every path pin**

Run: `grep -rn "Surface/Panel/" tests/menu*.spec.luau src/controls/menu.luau ../../../games/RascalRally/code/src ../../../games/RascalRally/code/tests | grep -v sheet` and update each floating-menu pin to `Surface/Popup/Panel/`.

- [ ] **Step 5: Run, bench check, commit**

Run: `./run-tests.sh 2>&1 | tail -3` → PASS. Run `tools/perf.sh` → PASS, check `picker-menu-open-close` moved ≤ +10%, then `git checkout bench/perf_budgets.json`.
```bash
stylua src tests
git add src/controls/menu.luau tests/menu.spec.luau tests/menu_scenario.spec.luau
git commit -m "Menu: the floating panel materializes from its anchor and dismisses fast"
```

---

### Task 4: Toggle knob overshoot (spec 1E)

**Files:**
- Modify: `src/client/screen_paint.luau:459-461` (motionInfo), `:1403` (knob tween)

**Interfaces:**
- Consumes: `style.motion.normal` (0.2 s). No new tokens.

Headless tests cannot see `TweenService`; the verification is the Studio canary in Task 16. This task is a two-line change plus a source-size check.

- [ ] **Step 1: Add an overshoot TweenInfo beside `motionInfo`**

```lua
	local function motionInfo(duration: number): TweenInfo
		return TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	-- the toggle knob's two-step settle (transitions.dev's `(.34,1.35,.64,1)`):
	-- Back/Out overshoots ~10% and returns, which is what a switch thumb wants and
	-- a colour never does — colour stays on `motionInfo`
	local function overshootInfo(duration: number): TweenInfo
		return TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
```

- [ ] **Step 2: Use it on the knob position only**

Line 1403 becomes:
```lua
			TweenService:Create(knob, overshootInfo(style.motion.normal), { Position = knobPos }):Play()
```
The track colour tween on `:1396` keeps `motionInfo`. The `isReducedMotion()` branch above it is untouched (it snaps).

- [ ] **Step 3: Verify, commit**

```bash
stylua src && wc -c src/client/screen_paint.luau && ./run-tests.sh --fast 2>&1 | tail -3
git add src/client/screen_paint.luau
git commit -m "Toggle: the knob settles with a Back overshoot; the track colour does not"
```

---

### Task 5: Ten-foot focus lift springs instead of snapping (spec 1D)

**Files:**
- Modify: `src/client/screen_target.luau:3250-3270`

**Interfaces:**
- Consumes: `TweenService` (already required at `:22`), `isReducedMotion()` (`:283`), `style.extra.tenFootFocusScale`, `style.motion.normal`.

- [ ] **Step 1: Replace the two instant `Scale` writes with one helper**

Above the block at `:3250` add a file-local helper (near `isReducedMotion`'s definition, `:283`, is the natural home):
```lua
	-- the ten-foot focus lift TRAVELS (transitions round 2026-09-12): a pad
	-- moving focus across a row used to snap each control to 1.05 and the last
	-- back to 1 on the same frame. One tween per focus change, cancelled by the
	-- next; reduced motion keeps the instant write
	local function aimFocusScale(handle: any, target: number)
		local focusScale = handle.focusScale
		if focusScale == nil then
			return
		end
		if handle.focusScaleTween ~= nil then
			handle.focusScaleTween:Cancel()
			handle.focusScaleTween = nil
		end
		if isReducedMotion() or focusScale.Scale == target then
			focusScale.Scale = target
			return
		end
		local tween = TweenService:Create(
			focusScale,
			TweenInfo.new(style.motion.normal, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = target }
		)
		handle.focusScaleTween = tween
		tween:Play()
	end
```
(`style` must be in scope where the helper lives; if the file's `style` is a per-call value rather than an upvalue at `:283`, place the helper immediately above the `if strong and lift then` block at `:3253` instead, where `style` is already visible.)

Then the block at `:3253-3267` becomes:
```lua
			if strong and lift then
				if handle.focusScale == nil then
					local focusScale = Instance.new("UIScale")
					focusScale.Name = "FocusScale"
					focusScale.Parent = instance
					handle.focusScale = focusScale
				end
				aimFocusScale(handle, style.extra.tenFootFocusScale)
			elseif handle.focusScale ~= nil then
				aimFocusScale(handle, 1)
			end
		else
			if handle.focusScale ~= nil then
				aimFocusScale(handle, 1)
			end
		end
```
Wherever the handle is destroyed/recycled (grep `handle.focusScale = nil` and `focusScale:Destroy`), cancel `handle.focusScaleTween` first.

- [ ] **Step 2: Verify size and suite, commit**

```bash
stylua src && wc -c src/client/screen_target.luau   # must stay < 199,000
./run-tests.sh --fast 2>&1 | tail -3
git add src/client/screen_target.luau
git commit -m "Ten-foot focus lift tweens between controls instead of snapping"
```
Device proof: Task 16's pad canary.

---

### Task 6: Rascal Rally contract test for Tier 1

**Files:**
- Create: `RR: tests/facet_transition_contract.spec.luau`
- Modify: `RR: tests/run.luau` (append require above `local ok = testkit.run()`)

**Interfaces:**
- Consumes: `Facet.motion` class registry, the `When` transition coordinator, `ResultsScreen`'s declared `{ enter = "materialize", exit = "instant", class = "container" }` (`RR: src/client/FacetSponsor/ResultsScreen.luau:299`).

- [ ] **Step 1: Write the contract**

```lua
--!strict
--[[ THE CONSUMER RIDER for the Facet transitions round (2026-09-12).
	Root CLAUDE.md: every Facet default change carries a game-side test. Two
	defaults moved upstream: structural exits now run on the `dismiss` class,
	and Alert/Menu materialize. This game's ResultsScreen declares an
	`exit = "instant"`, so its behaviour must be byte-identical; a default When
	in the game must exit faster than it enters. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Facet = require("../../../../GameStudio/ui/Facet/src") :: any
local fake_target = require("../../../../GameStudio/ui/Facet/tests/lib/fake_target")

local FRAME = 1 / 60

local function world()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 844, h = 390 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	return core, env, adapter, pres
end

local function gate(core: any, on: any, transition: any)
	local UI = Facet.UI
	return UI.Screen({
		id = "S",
		children = {
			UI.When({
				id = "Gate",
				condition = on,
				transition = transition,
				thenView = function()
					return UI.ZStack({ id = "Panel", canvasGroup = true, children = { UI.Button({ id = "Go", label = "Go" }) } })
				end,
			}),
		},
	})
end

describe("Facet transitions rider", function()
	it("the game's Facet carries the dismiss class", function()
		expect(Facet.motion.isRegisteredClass("dismiss")).toBe(true)
	end)

	it("a default When exits faster than it enters", function()
		local core, _, adapter, pres = world()
		local on = core:signal(true)
		pres.present(gate(core, on, { enter = "fade" }))
		local panel = adapter.node("/S/Gate/then/Panel")
		local enterFrames = 0
		while panel.canvasGroupInstance.groupTransparency > 0 and enterFrames < 600 do
			pres.tick(FRAME)
			enterFrames += 1
		end
		on:set(false)
		local exitFrames = 0
		while adapter.node("/S/Gate/then/Panel") ~= nil and exitFrames < 600 do
			pres.tick(FRAME)
			exitFrames += 1
		end
		expect(enterFrames > 0 and exitFrames < enterFrames).toBe(true)
	end)

	it("ResultsScreen's declared instant exit is unchanged", function()
		local core, _, adapter, pres = world()
		local on = core:signal(true)
		pres.present(gate(core, on, { enter = "materialize", exit = "instant", class = "container" }))
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		on:set(false)
		expect(adapter.node("/S/Gate/then/Panel")).toBeNil()
	end)
end)
```
If `Facet.motion.isRegisteredClass` is not the public spelling, read `docs/reference/api.md` §"motion.registerClass" (it lists `motion.isRegisteredClass(name)`) and the `src/init.luau` export; use whichever exists.

- [ ] **Step 2: Register and run**

Append `require("./facet_transition_contract.spec")` to `RR: tests/run.luau` above `local ok = testkit.run()`.
Run: `cd games/RascalRally/code && ./run-tests.sh 2>&1 | tail -3` → PASS.

- [ ] **Step 3: Commit (RR repo)**

```bash
git add tests/facet_transition_contract.spec.luau tests/run.luau
git commit -m "Facet transitions rider: dismiss class present, instant exits unchanged"
```

---

### Task 7: RED-TEAM Tier 1

Dispatch `code-reviewer` (opus) on the diff `git diff <pre-Task-1 sha>..HEAD -- src tests` in Facet plus the RR commit. Ask specifically for: (a) the `retune` velocity hand-off under reduce-motion (the old spring may already be settled; `getVelocity()` must be 0, not nil), (b) any caller reading `entry.progress` captured before a retune (grep `entry.progress` in `transitions.luau`), (c) Menu path pins missed in RR. Fix findings in place, re-run `./run-tests.sh` and RR's suite, commit as "Transitions Tier 1: review fixes".

---

### Task 8: `stagger` on list transitions (spec 2F)

**Files:**
- Modify: `src/blueprint_schema.luau` (TRANSITION_KEYS, validator), `src/render/transitions.luau` (Spec, resolve, beginEnter)
- Test: `tests/transitions.spec.luau`

**Interfaces:**
- Produces: `transition.stagger?: number` (seconds per item, default 0, cap 8 items); `transitions.STAGGER_CAP = 8`.

- [ ] **Step 1: Write the failing test**

```lua
describe("transition coordinator: stagger", function()
	local function rows(core: any, on: any, stagger: number?)
		local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		return UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "Gate",
					condition = on,
					thenView = function()
						return UI.ForEach({
							id = "List",
							items = items,
							key = function(item)
								return item.id
							end,
							transition = { enter = "fade", stagger = stagger },
							row = function(item)
								return UI.ZStack({ id = "Row", canvasGroup = true, children = { UI.Text({ id = "T", text = item.id }) } })
							end,
						})
					end,
				}),
			},
		})
	end
	local function alphaOf(adapter: any, key: string): number
		return adapter.node(`/S/Gate/then/List/[{key}]/Row`).canvasGroupInstance.groupTransparency
	end

	it("later rows start later, and none starts before its delay", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, rows(core, on, 0.05))
		-- frame 1: only the first row has moved
		clock:step(FRAME)
		expect(alphaOf(adapter, "a") < 1).toBe(true)
		expect(alphaOf(adapter, "b")).toBe(1)
		expect(alphaOf(adapter, "c")).toBe(1)
		for _ = 1, 3 do
			clock:step(FRAME)
		end -- 4 frames ≈ 67 ms > 50 ms: b has started, c (100 ms) has not
		expect(alphaOf(adapter, "b") < 1).toBe(true)
		expect(alphaOf(adapter, "c")).toBe(1)
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(alphaOf(adapter, "c")).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("exits never stagger", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, rows(core, on, 0.05))
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		on:set(false)
		clock:step(FRAME)
		expect(alphaOf(adapter, "a") > 0).toBe(true)
		expect(alphaOf(adapter, "c") > 0).toBe(true)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("reduced motion lands every row on the first frame", function()
		local core, env, clock = world(true)
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, rows(core, on, 0.05))
		expect(alphaOf(adapter, "c")).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("the schema refuses a negative stagger", function()
		local ok, err = pcall(transitionsLib.resolve, { enter = "fade", stagger = -1 })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "stagger", 1, true) ~= nil).toBe(true)
	end)
end)
```
Adjust the ForEach row path (`/[a]/Row`) to the mount layer's real keyed-row path — copy it from the existing `describe("mount retire model: ForEach")` tests at `:287`.

- [ ] **Step 2: Run to verify it fails** — `unknown transition field 'stagger'`.

- [ ] **Step 3: Schema**

Add `stagger = true` to `TRANSITION_KEYS`, add it to the unknown-field message, and after the `distance` check:
```lua
local stagger = (v :: any).stagger
if stagger ~= nil and (type(stagger) ~= "number" or stagger ~= stagger or stagger < 0 or stagger == math.huge) then
	return false, "stagger is a non-negative number of SECONDS between one row's enter and the next (capped at 8 rows)"
end
```

- [ ] **Step 4: Coordinator**

`Spec` gains `stagger: number,`; `resolve` returns `stagger = if type(declared.stagger) == "number" then declared.stagger else 0,`. Add module constants:
```lua
-- a list stagger is a RHYTHM, not a queue: past this many rows every further row
-- starts with the last one, so a 600-row list never books 600 timers
local STAGGER_CAP = 8
```
Inside `transitions.new`, add state and a helper:
```lua
	-- rows entering in the SAME clock step under the same parent are a batch;
	-- the batch counter resets when the step count moves
	local staggerStep, staggerCounts = -1, {} :: { [string]: number }
	local function staggerDelay(path: string, spec: Spec): number
		if spec.stagger <= 0 then
			return 0
		end
		local step = clock:stats().steps
		if step ~= staggerStep then
			staggerStep, staggerCounts = step, {}
		end
		local parent = string.match(path, "^(.*)/[^/]+$") or ""
		local n = staggerCounts[parent] or 0
		staggerCounts[parent] = n + 1
		return math.min(n, STAGGER_CAP) * spec.stagger
	end
```
In `beginEnter`, replace the final `entry.progress:setTarget(1)` with:
```lua
		local delay = staggerDelay(path, spec)
		if delay <= 0 then
			entry.progress:setTarget(1)
			return
		end
		-- hold at the absent place, then aim; the timer is decorative so reduced
		-- motion settles it on the spot and the row lands with its siblings
		stopCap(entry)
		local hold = clock:timer({ from = 0, to = 1, duration = delay, kind = "decorative" })
		entry.cap = hold
		hold:onSettle(function()
			if entry.cap == hold then
				entry.cap = nil
			end
			if entry.phase == "enter" and not entry.disposed then
				entry.progress:setTarget(1)
			end
		end)
```
(`entry.cap` is reused so `stopCap`, `cancelExit` and `disposeEntry` already tear the hold down; `beginExit` calls `stopCap` before arming its own cap, so an exit during the hold cancels it.) Export `transitions.STAGGER_CAP = STAGGER_CAP`.

- [ ] **Step 5: Run, format, full suite, commit**

```bash
lune run tests/run_fast 2>&1 | tail -3 && stylua src tests && ./run-tests.sh 2>&1 | tail -3
git add src/blueprint_schema.luau src/render/transitions.luau tests/transitions.spec.luau
git commit -m "Transitions: stagger, a per-row enter delay capped at eight rows"
```

---

### Task 9: TextInput `invalid` shake (spec 2H)

**Files:**
- Modify: `src/controls/text_input.luau:144-170` (KEYS), `:821-830` (rootSpec), `:946-960` (contribution), plus the `validationError` writer at `:505-535`
- Test: `tests/text_input.spec.luau`

**Interfaces:**
- Produces: `TextInputSpec.invalid?: Signal<boolean>` (caller-owned; a false→true edge shakes). The number presentation also shakes when its own `validationError` becomes non-empty.
- Consumes: `clock:timeline`, the authored `offset` presentation prop (`{ x, y }`, paint-only).

- [ ] **Step 1: Write the failing test**

Append to `tests/text_input.spec.luau` (its `world(opts)` helper at `:32`; it returns a world with `pres`, `adapter`, `core`; a text input is built with `Facet.Controls.TextInput(core, spec)` and presented inside a `UI.Screen` — copy the file's first `it` for the mount recipe):
```lua
describe("text input: invalid shakes", function()
	local FRAME = 1 / 60
	it("a false→true edge nudges the root sideways and returns to rest", function()
		local w = world()
		local invalid = w.core:signal(false)
		local value = w.core:signal("")
		local input = Facet.Controls.TextInput(w.core, { id = "Name", value = value, invalid = invalid })
		w.pres.present(Facet.UI.Screen({ id = "S", children = { input.blueprint } }))
		local root = w.adapter.node("/S/Name")
		local rest = root.props.offset
		expect(rest == nil or rest.x == 0).toBe(true)
		invalid:set(true)
		w.pres.tick(FRAME)
		w.pres.tick(FRAME)
		local moved = root.props.offset
		expect(moved ~= nil and moved.x ~= 0).toBe(true)
		for _ = 1, 40 do
			w.pres.tick(FRAME)
		end
		local settled = root.props.offset
		expect(settled == nil or settled.x == 0).toBe(true)
		-- the solver never moved: the field's rect is where it was
		expect(w.adapter.node("/S/Name/Field").rect.x).toBe(w.adapter.node("/S/Name/Field").rect.x)
	end)

	it("reduced motion keeps the tint and drops the shake", function()
		local w = world({ reducedMotion = true })
		local invalid = w.core:signal(false)
		local input = Facet.Controls.TextInput(w.core, { id = "Name", value = w.core:signal(""), invalid = invalid })
		w.pres.present(Facet.UI.Screen({ id = "S", children = { input.blueprint } }))
		invalid:set(true)
		w.pres.tick(FRAME)
		local off = w.adapter.node("/S/Name").props.offset
		expect(off == nil or off.x == 0).toBe(true)
	end)
end)
```
(Read how the fake target exposes a node's presentation offset — `props.offset` or `presentedPosition`; `tests/with_animation.spec.luau` shows the accessor. Use that one.)

- [ ] **Step 2: Run to verify it fails** — unknown spec key `invalid`.

- [ ] **Step 3: Implement**

In `src/controls/text_input.luau`:
- add `"invalid",` to `TEXT_INPUT_KEYS`; validate `spec.invalid == nil or (type(spec.invalid) == "table" and spec.invalid.kind == "signal")` with an error naming `Signal<boolean>`.
- state, near `validationError` (`:281`):
```lua
	-- THE SHAKE (transitions round 2026-09-12): four legs on the paint-only
	-- `offset`, ±8 px, 80/60/60/40 ms. The tint is the information; the shake is
	-- decorative, so reduced motion (the timeline's own policy) drops it whole.
	local shakeOffset = scope:own(core:signal(0))
	local clock: any = nil
	local shaking: any = nil
	local SHAKE_PX = 8
	local function shake()
		if clock == nil then
			return
		end
		if shaking ~= nil then
			shaking:interrupt()
		end
		local function leg(x: number)
			return function()
				shakeOffset:set(x)
			end
		end
		shaking = clock:timeline({
			beats = {
				{ at = 0, run = leg(-SHAKE_PX), terminal = leg(0) },
				{ at = 0.08, run = leg(SHAKE_PX), terminal = leg(0) },
				{ at = 0.14, run = leg(-SHAKE_PX * 0.5), terminal = leg(0) },
				{ at = 0.2, run = leg(SHAKE_PX * 0.25), terminal = leg(0) },
				{ at = 0.24, run = leg(0), terminal = leg(0) },
			},
			onDone = function()
				shaking = nil
				shakeOffset:set(0)
			end,
		})
	end
	if spec.invalid ~= nil then
		local was = spec.invalid:get()
		scope:own(core:observe(spec.invalid, function(now)
			if now == true and was ~= true then
				shake()
			end
			was = now
		end))
	end
```
- in the number branch, call `shake()` right after each `validationError:set(<non-empty>)` (`:505`, `:514`, `:524`, `:531`).
- `rootSpec` gains `offset = scope:own(core:memo(function(use) return { x = use(shakeOffset), y = 0 } end)),`. If `UI.Anchor` does not accept `offset` (check `class("Anchor"` in the schema for `offset = OFFSET`), wrap the root once in `UI.ZStack({ id = id, offset = …, children = { anchor } })` and give the Anchor a distinct id; then update `dump()`'s paths.
- in the `contribution.attach(blueprint, { … })` table at `:948` add:
```lua
			bindMotion = function(c)
				clock = c
			end,
```

- [ ] **Step 4: Run, format, suite, commit**

```bash
lune run tests/run_fast 2>&1 | tail -3 && stylua src tests && ./run-tests.sh 2>&1 | tail -3
git add src/controls/text_input.luau tests/text_input.spec.luau
git commit -m "TextInput: an invalid edge shakes the field on the paint-only offset"
```

---

### Task 10: RadialMenu bloom stagger, hover lift, commit pop (spec 2G radial)

**Files:**
- Modify: `src/controls/radial_menu.luau:1098-1112` (row progress), `:1193-1205` (selected), `:1484-1502` (Visual node), `:829-860` (commit)
- Test: `tests/radial_menu.spec.luau` (its `setup`, `launcher`, `sector`, `tapOpen` helpers at `:6-70`)

**Interfaces:**
- Consumes: the row's existing `progress` spring (`object`), `contraction`, `candidate`, `clock`.
- Produces: per-row `lift` spring (1 → 1.04 while the row is the candidate), a `pop` kick on commit, and a 20 ms per-wedge bloom stagger (total ≤ 120 ms).

- [ ] **Step 1: Write the failing tests**

```lua
describe("radial: bloom, lift, pop", function()
	local FRAME = 1 / 60
	it("wedges bloom in sequence, all within 120 ms", function()
		local w, c = setup()
		tapOpen(w, c)
		w.pres.tick(FRAME) -- frame 1
		local first = w.adapter.node(sector(c, "a")).children[1].props.scale
		local last = w.adapter.node(sector(c, "f")).children[1].props.scale
		expect(first > last).toBe(true) -- the first wedge is further along
		for _ = 1, 8 do
			w.pres.tick(FRAME)
		end -- 150 ms: every wedge has started
		expect(w.adapter.node(sector(c, "f")).children[1].props.scale > 0.82).toBe(true)
	end)

	it("the candidate wedge lifts and the committed wedge pops", function()
		local w, c = setup()
		tapOpen(w, c)
		for _ = 1, 60 do
			w.pres.tick(FRAME)
		end
		c.api.setCandidateById("b")
		for _ = 1, 30 do
			w.pres.tick(FRAME)
		end
		local visual = w.adapter.node(sector(c, "b")).children[1]
		expect(visual.props.scale > 1.02).toBe(true)
		c.api.select("b")
		local peak = 0
		for _ = 1, 20 do
			w.pres.tick(FRAME)
			peak = math.max(peak, visual.props.scale or 0)
		end
		expect(peak > 1.05).toBe(true)
	end)
end)
```
Use the file's real helpers for "make `b` the candidate" (a pointer move via `w.pres` input or the existing `api` verb — grep `candidate` in the spec) and for the wedge's Visual node path; the two assertions are the deliverable, the helper names are the file's.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Implement in the `row(s, rs)` builder**

After `local progress = …` (`:1100`), add:
```lua
		-- the wedge's LIFT (candidate under the pointer/stick) and POP (commit):
		-- one spring, `reward` for the overshoot; the pop is a velocity kick on
		-- the same spring, so a lift-then-commit is one continuous motion
		local lift = if clock then rs:own(clock:spring(1, "reward", { eps = 0.00001 })) else nil
		local LIFT_SCALE, POP_KICK = 1.04, 1.6
```
In the effect that sets `progress:setTarget(if active then 1 else 0)` (`:1110`), stagger the enter: compute the wedge's ordinal `i` in `use(layout).sectors` inside the existing loop and replace the single `setTarget` with:
```lua
				if active then
					local delay = math.min(i - 1, 5) * 0.02 -- ≤ 100 ms for the sixth+
					if delay > 0 and progress:get() < 0.001 and not progress.blooming then
						progress.blooming = true
						local hold = rs:own(clock:timer({ from = 0, to = 1, duration = delay, kind = "decorative" }))
						hold:onSettle(function()
							progress.blooming = nil
							progress:setTarget(1)
						end)
					else
						progress:setTarget(1)
					end
				else
					progress:setTarget(0)
				end
```
Lift target follows the candidate: after `selected` (`:1193`) add
```lua
		if lift then
			rs:own(core:observe(candidate, function(key)
				lift:setTarget(if key == s.key then LIFT_SCALE else 1)
			end))
		end
```
The Visual node's `scale = contraction` (`:1500`) becomes
```lua
			scale = rm(function(use)
				return use(contraction) * (if lift then use(lift) else 1)
			end),
```
In `commit(s)` (`:842`, after `capture = nil` and before the completion policy) kick the committed row's spring: keep a `liftByKey: { [string]: any }` table in the control scope, register `liftByKey[s.key] = lift` in `row`, clear on the row scope's dispose, and in `commit`:
```lua
		local popped = liftByKey[s.key]
		if popped ~= nil then
			popped:setVelocity(POP_KICK)
		end
```

- [ ] **Step 4: Run, bench check, commit**

```bash
lune run tests/run_fast 2>&1 | tail -3 && stylua src tests && ./run-tests.sh 2>&1 | tail -3
tools/perf.sh 2>&1 | tail -8   # radial-menu-open-close ≤ +10%; then git checkout bench/perf_budgets.json
git add src/controls/radial_menu.luau tests/radial_menu.spec.luau
git commit -m "RadialMenu: wedges bloom in sequence, the candidate lifts, the commit pops"
```

---

### Task 11: Button `pop` (spec 2G button)

**Files:**
- Modify: `src/controls/button.luau:10-28` (KEYS), `:132-145` (activate), `:384-400` (root blueprint), `:483-491` (bindMotion)
- Test: `tests/button_behavior.spec.luau`

**Interfaces:**
- Produces: `ButtonSpec.pop?: boolean` — on activate the root's paint-only `scale` kicks 1 → ~1.06 → 1 on a `reward` spring.

- [ ] **Step 1: Write the failing test** (copy the mount recipe from the file's first `it`):

```lua
describe("button: pop", function()
	local FRAME = 1 / 60
	it("an activate kicks the root scale and it returns to 1", function()
		local w = world()
		local hits = 0
		local b = Facet.Controls.Button(w.core, { id = "Go", label = "Go", pop = true, onActivate = function() hits += 1 end })
		w.pres.present(Facet.UI.Screen({ id = "S", children = { b.blueprint } }))
		w.pres.activate("/S/Go")
		local root = w.adapter.node("/S/Go")
		local peak = 1
		for _ = 1, 30 do
			w.pres.tick(FRAME)
			peak = math.max(peak, root.props.scale or 1)
		end
		expect(hits).toBe(1)
		expect(peak > 1.03).toBe(true)
		for _ = 1, 60 do
			w.pres.tick(FRAME)
		end
		expect(math.abs((root.props.scale or 1) - 1) < 0.001).toBe(true)
	end)
end)
```
(`w.pres.activate(path)` — use whatever verb the file already uses to press a button headlessly.)

- [ ] **Step 2: Run to verify it fails** — unknown key `pop`.

- [ ] **Step 3: Implement**

- add `"pop",` to `KEYS`.
- near the top of `button.build` after `clock` is declared (`:76`):
```lua
	-- THE POP (transitions round 2026-09-12): a release overshoot for reward-shaped
	-- buttons, opt-in. One `reward` spring at rest on 1; activate kicks its
	-- velocity, the spring overshoots and returns. Paint-only `scale`.
	local popScale = if spec.pop then scope:own(core:signal(1)) else nil
	local popMotion: any = nil
	local POP_KICK = 1.4
	local function bindPopMotion()
		if popScale == nil or popMotion ~= nil or clock == nil then
			return
		end
		popMotion = scope:own(clock:spring(1, "reward", { eps = 0.00001 }))
		scope:own(core:observe(popMotion, function()
			popScale:set(popMotion:get())
		end))
	end
```
- in `activate` (`:132`), before `spec.onActivate(meta)`: `if popMotion ~= nil then popMotion:setVelocity(POP_KICK) end`.
- root `UI.Button({ … })` gains `scale = popScale,` (nil when not opted in — confirm the Button class lists `scale`; the schema comment at `:1053` says the press dip multiplies with it).
- in `bindMotion` (`:483`) call `bindPopMotion()` after `clock = c`.

- [ ] **Step 4: Run, format, suite, commit**

```bash
lune run tests/run_fast 2>&1 | tail -3 && stylua src tests && ./run-tests.sh 2>&1 | tail -3
git add src/controls/button.luau tests/button_behavior.spec.luau
git commit -m "Button: opt-in pop, a reward-spring release overshoot on activate"
```

---

### Task 12: DisclosureGroup caret rotation, content slide, glide (spec 2I)

**Files:**
- Modify: `src/controls/disclosure_group.luau:26-41` (Spec/KEYS), `:74-90` (toggle), `:125-175` (caret + content), `:178-200` (contribution)
- Test: `tests/text_disclosure.spec.luau` or a new `tests/disclosure_group.spec.luau` (check which file already builds `newDisclosureGroup`; add there)

**Interfaces:**
- Produces: `DisclosureGroupSpec.presenter?` (when given, the toggle runs inside `presenter.withAnimation("container", …)` so siblings glide); the caret is ONE `chevron.trailing` glyph with a paint-only `rotation` spring 0 → 90; content mounts with `{ enter = "slide-up", distance = 12 }`.

- [ ] **Step 1: Write the failing test**

```lua
describe("disclosure: caret turns, content slides", function()
	local FRAME = 1 / 60
	it("the caret rotates toward 90 on expand and back on collapse", function()
		local w = makeWorld()
		local expanded = w.core:signal(false)
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return Facet.UI.Text({ id = "Body", text = "hello" })
			end,
		})
		w.pres.present(Facet.UI.Screen({ id = "S", children = { group.blueprint } }))
		local caret = w.adapter.node("/S/Adv/Header/Caret")
		expect(caret.props.rotation or 0).toBe(0)
		expanded:set(true)
		for _ = 1, 60 do
			w.pres.tick(FRAME)
		end
		expect(math.abs((caret.props.rotation or 0) - 90) < 0.5).toBe(true)
		expect(w.adapter.node("/S/Adv/Content/then/Body") ~= nil).toBe(true)
		expanded:set(false)
		for _ = 1, 60 do
			w.pres.tick(FRAME)
		end
		expect(math.abs(caret.props.rotation or 0) < 0.5).toBe(true)
	end)
end)
```

- [ ] **Step 2: Run to verify it fails** — `/Header/Caret` is absent (today there are `CaretOpen`/`CaretShut` gates).

- [ ] **Step 3: Implement**

- `Spec` gains `presenter: any?`; `DISCLOSURE_GROUP_KEYS` gains `"presenter"`.
- replace the two caret `When`s with one glyph:
```lua
	local CARET = themePackage.iconGlyph("chevron.trailing") or ">"
	local caretAngle = scope:own(core:signal(if expanded:get() then 90 else 0))
	local clock: any, caretMotion: any = nil, nil
	local function aimCaret()
		local target = if expanded:get() then 90 else 0
		if caretMotion ~= nil then
			caretMotion:setTarget(target)
		else
			caretAngle:set(target)
		end
	end
	scope:own(core:observe(expanded, aimCaret))
	…
	children = {
		chrome_slots.attachHint(
			UI.Text({ id = "Caret", text = CARET, textSize = "control", rotation = caretAngle }),
			{ icon = "chevron.trailing" }
		),
		UI.Text({ id = "Label", … }),
	},
```
- content: `UI.When({ id = "Content", condition = expanded, thenView = spec.content, transition = { enter = "slide-up", distance = 12 } })`.
- in `toggle()` wrap the `expanded:set(next_)` (and the `onToggle` call) as:
```lua
		local function flip()
			expanded:set(next_)
		end
		if spec.presenter ~= nil then
			spec.presenter.withAnimation("container", flip)
		else
			flip()
		end
```
(Keep the focus hand-back that precedes it exactly where it is — it must run BEFORE the content unmounts.)
- contribution: add
```lua
		bindMotion = function(c)
			clock = c
			if caretMotion == nil then
				caretMotion = scope:own(clock:spring(caretAngle:get(), "object", { eps = 0.01 }))
				scope:own(core:observe(caretMotion, function()
					caretAngle:set(caretMotion:get())
				end))
			end
		end,
```
- Update `dump()` if it listed the two old caret ids.

- [ ] **Step 4: Run, format, suite, commit**

```bash
lune run tests/run_fast 2>&1 | tail -3 && stylua src tests && ./run-tests.sh 2>&1 | tail -3
git add src/controls/disclosure_group.luau tests/<the spec you edited>
git commit -m "DisclosureGroup: the caret turns, content slides in, siblings glide under a presenter"
```

---

### Task 13: The paint-only + idle-free gate (spec §3.1, §3.3)

**Files:**
- Create: `tests/motion_paint_only.spec.luau`
- Modify: `tests/run.luau` (register)

**Interfaces:**
- Consumes: Tasks 8-12's controls; `controller.diagnostics()` / `controller.stats()` solve counters (read `tests/lib/world.luau` and `tests/with_animation.spec.luau` for the accessor that reports solves / moved rects); `clock:stats().writes`.

- [ ] **Step 1: Write the gate**

```lua
--!strict
-- THE PAINT-ONLY LAW for the transitions round (2026-09-12): every motion added
-- (shake, pop, lift, caret turn, stagger) writes the presentation channel and
-- NEVER the solver. Two invariants, both counted: (1) a motion frame moves no
-- solved rect; (2) a settled motion writes nothing (idle is free).
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local worldLib = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
local FRAME = 1 / 60

local function world()
	return worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
end

-- the solver's own count of rects it moved since the last read
local function movedRects(w: any): number
	return w.pres.diagnostics().movedRects -- adapt to the real accessor name
end

describe("motion is paint-only and idle is free", function()
	it("a shake, a pop and a caret turn move zero solved rects", function()
		local w = world()
		local invalid = w.core:signal(false)
		local expanded = w.core:signal(false)
		local hits = 0
		local input = Facet.Controls.TextInput(w.core, { id = "Name", value = w.core:signal(""), invalid = invalid })
		local button = Facet.Controls.Button(w.core, { id = "Go", label = "Go", pop = true, onActivate = function() hits += 1 end })
		local group = Facet.Controls.DisclosureGroup(w.core, {
			id = "Adv", label = "Advanced", expanded = expanded,
			content = function() return UI.Text({ id = "Body", text = "x" }) end,
		})
		w.pres.present(UI.Screen({ id = "S", gap = 8, children = { input.blueprint, button.blueprint, group.blueprint } }))
		for _ = 1, 5 do w.pres.tick(FRAME) end
		movedRects(w) -- drain
		invalid:set(true)
		w.pres.activate("/S/Go")
		for _ = 1, 30 do w.pres.tick(FRAME) end
		expect(movedRects(w)).toBe(0)
		expect(hits).toBe(1)
	end)

	it("a settled control writes nothing across 60 idle frames", function()
		local w = world()
		local invalid = w.core:signal(false)
		local input = Facet.Controls.TextInput(w.core, { id = "Name", value = w.core:signal(""), invalid = invalid })
		w.pres.present(UI.Screen({ id = "S", children = { input.blueprint } }))
		invalid:set(true)
		for _ = 1, 60 do w.pres.tick(FRAME) end -- shake done
		local before = w.pres.motionClock():stats().writes
		for _ = 1, 60 do w.pres.tick(FRAME) end
		expect(w.pres.motionClock():stats().writes).toBe(before)
		expect(w.pres.motionClock():activeCount()).toBe(0)
	end)

	it("a staggered list of 30 rows never writes Size", function()
		local w = world()
		local on = w.core:signal(true)
		local items = {}
		for i = 1, 30 do items[i] = { id = `r{i}` } end
		w.pres.present(UI.Screen({
			id = "S",
			children = {
				UI.When({ id = "Gate", condition = on, thenView = function()
					return UI.ForEach({
						id = "List", items = w.core:signal(items), key = function(it_) return it_.id end,
						transition = { enter = "fade", stagger = 0.02 },
						row = function(it_) return UI.ZStack({ id = "Row", canvasGroup = true, children = { UI.Text({ id = "T", text = it_.id }) } }) end,
					})
				end }),
			},
		}))
		movedRects(w)
		for _ = 1, 90 do w.pres.tick(FRAME) end
		expect(movedRects(w)).toBe(0)
	end)
end)
```
Replace `w.pres.diagnostics().movedRects` / `w.pres.motionClock()` with the accessors the suite really has (grep `movedRects` in `tests/` and `bench/`; the theme-swap proofs in `tools/check_perf_scenes.py` read `movedRects` from a scene's extras, so the counter exists on the controller). Register the file in `tests/run.luau`.

- [ ] **Step 2: Run it, make it pass, commit**

`lune run tests/run_fast 2>&1 | grep -A8 "paint-only"` → PASS (if a count is non-zero, that is a real defect in Tasks 8-12: fix the control, not the test).
```bash
stylua tests && git add tests/motion_paint_only.spec.luau tests/run.luau
git commit -m "Gate: the transitions round's motion is paint-only and idle is free"
```

---

### Task 14: `control-motion` perf scene + proof + scoped baseline (spec §3.4)

**Files:**
- Modify: `bench/perf_scenes.luau` (append scene), `tools/check_perf_scenes.py` (PRODUCTION entry), `bench/perf_budgets.json` (one new row only)

- [ ] **Step 1: Add the scene** (after `dense-motion`, same `newStack` recipe):

```lua
-- transitions round (2026-09-12): the four new Luau-side motions on one screen —
-- a 30-row staggered list re-keyed every 30 iters, one disclosure flipped every
-- 20, one invalid pulse every 15, one popped button every 10; one scripted
-- clock step + one refresh per iter. The proof is the same one dense-motion
-- keeps: one transaction per stepped frame, however many values moved.
table.insert(scenes, {
	name = "control-motion",
	requirement = "UI-PERF-001",
	dataset = "30-row staggered ForEach + DisclosureGroup + TextInput.invalid + Button.pop; 1 clock step + 1 refresh per iter",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local gen = 0
		local function batch()
			gen += 1
			local out = table.create(30)
			for i = 1, 30 do
				out[i] = { id = `g{gen}-{i}` }
			end
			return out
		end
		local items = core:signal(batch())
		local invalid = core:signal(false)
		local expanded = core:signal(false)
		local pops = 0
		local input = Facet.Controls.TextInput(core, { id = "Name", value = core:signal(""), invalid = invalid })
		local button = Facet.Controls.Button(core, { id = "Go", label = "Go", pop = true, onActivate = function() pops += 1 end })
		local group = Facet.Controls.DisclosureGroup(core, {
			id = "Adv", label = "Advanced", expanded = expanded,
			content = function() return UI.Text({ id = "Body", text = "body" }) end,
		})
		pres.present(UI.Screen({
			id = "Motion",
			gap = 4,
			children = {
				input.blueprint,
				button.blueprint,
				group.blueprint,
				UI.ForEach({
					id = "List", items = items, key = function(item) return item.id end,
					transition = { enter = "fade", stagger = 0.02 },
					row = function(item)
						return UI.ZStack({ id = "Row", canvasGroup = true, height = 20, children = { UI.Text({ id = "T", text = item.id, textSize = 14 }) } })
					end,
				}),
			},
		}))
		return { core = core, adapter = adapter, pres = pres, items = items, batch = batch, invalid = invalid, expanded = expanded, n = 0, rekeys = 0, flips = 0, pulses = 0, popsRef = function() return pops end, input = input, button = button, group = group }
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		if state.n % 30 == 0 then state.items:set(state.batch()); state.rekeys += 1 end
		if state.n % 20 == 0 then state.expanded:set(not state.expanded:get()); state.flips += 1 end
		if state.n % 15 == 0 then state.invalid:set(state.n % 30 ~= 0); state.pulses += 1 end
		if state.n % 10 == 0 then state.pres.activate("/Motion/Go") end
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.pres.tick(1 / 60)
		local motion = os.clock() - t1
		local t2 = os.clock()
		state.pres.refresh()
		return { mutate = mutate, motion = motion, commit = os.clock() - t2 }
	end,
	extras = function(state)
		local stats = state.pres.motionClock():stats()
		return { rekeys = state.rekeys, flips = state.flips, pulses = state.pulses, pops = state.popsRef(), motionSteps = stats.steps, motionTransactions = stats.transactions }
	end,
	teardown = function(state)
		state.input.dispose(); state.button.dispose(); state.group.dispose()
	end,
})
```
(`state.pres.activate` and `motionClock()` — use the presenter verbs the bench's other scenes use; `dense-hud` activates a button headlessly, copy its call.)

- [ ] **Step 2: Add the proof** to `tools/check_perf_scenes.py` `PRODUCTION`:
```python
    "control-motion": lambda x: (
        None
        if x.get("rekeys", 0) > 0 and x.get("flips", 0) > 0 and x.get("pulses", 0) > 0 and x.get("pops", 0) > 0
        and x.get("motionSteps", 0) > 0 and x.get("motionSteps") == x.get("motionTransactions")
        else f"the control-motion frame did not do its work: {x!r}"
    ),
```

- [ ] **Step 3: Baseline ONLY the new scene, then run the gate**

```bash
export PATH="$HOME/.rokit/bin:$PATH"
lune run tools/lune/perf_baseline_scene control-motion
tools/perf.sh 2>&1 | tail -12
python3 tools/check_perf_scenes.py
git diff bench/perf_budgets.json | grep '"observed_p95_ms"'   # every EXISTING row ≤ +10% vs HEAD
```
If an existing row moved more than 10%, stop: profile before re-baselining (never `tools/perf.sh baseline`).

- [ ] **Step 4: Commit**

```bash
git add bench/perf_scenes.luau tools/check_perf_scenes.py bench/perf_budgets.json
git commit -m "Perf lab: control-motion scene prices the transitions round's Luau-side motion"
```

---

### Task 15: Docs, recipes, changelog (spec 2J + recipes)

**Files:**
- Modify: `docs/reference/api.md:2391-2452` (transitions), `:9709-9730` (classes), the `newAlert`/`newMenu`/`newTextInput`/`newButton`/`newDisclosureGroup`/`newRadialMenu` spec tables (grep each `#### ` heading)
- Modify: `docs/guide/15-adaptive-recipes.md` (three recipes), `CHANGELOG.md` `[Unreleased]`

- [ ] **Step 1: api.md**
  - Transitions bullet list: add **`exitClass`** (default `"dismiss"`; "closes are faster than opens by default; declare `exitClass = class` for symmetry") and **`stagger`** (seconds per row, ForEach only in effect, capped at 8 rows, exits never stagger).
  - Classes paragraph: "Five ship: … `dismiss` (1.0 / 0.2), the exit twin of `container`."
  - Spec tables: `Alert.transition`, `TextInput.invalid`, `Button.pop`, `DisclosureGroup.presenter`; a line under RadialMenu: "wedges bloom with a 20 ms stagger, the candidate lifts 4%, a commit pops".
- [ ] **Step 2: Recipes** in `docs/guide/15-adaptive-recipes.md`, each ≤ 15 lines with a code block:
  - **Text-state swap**: a `UI.ForEach` whose `items` is `{ { id = text } }` keyed by the text with `transition = { enter = "slide-up", fade = true, distance = 8 }` — old text exits up, new rises.
  - **Icon swap**: `UI.When` pair on a boolean with `transition = { enter = "fade" }` on each; two images overlap for one `dismiss` beat — the round's one sanctioned extra instance.
  - **Card resize**: `presenter.withAnimation("container", function() expanded:set(true) end)`.
- [ ] **Step 3: CHANGELOG** `[Unreleased]` bullet: "Transitions round (2026-09-12, transitions.dev survey): structural exits default to the new `dismiss` class (`exitClass` opts out); Alert and Menu materialize; `stagger` on list enters; TextInput `invalid` shake; Button `pop`; RadialMenu bloom/lift/pop; DisclosureGroup caret turn + slide (+`presenter` glide); toggle-knob overshoot; ten-foot focus lift tweens. New perf scene `control-motion`; gate `tests/motion_paint_only.spec.luau`."
- [ ] **Step 4: Verify docs gates and commit**

```bash
tools/verify.sh --fast 2>&1 | tail -5     # docs/links/prop-parity producers
git add docs CHANGELOG.md
git commit -m "Docs: the transitions round — exitClass, stagger, pops, shake, recipes"
```

---

### Task 16: RED-TEAM Tier 2, RR lockstep, full verify, canaries

- [ ] **Step 1: RED-TEAM** — dispatch `code-reviewer` (opus) over Tasks 8-14's diff. Ask for: stagger's `entry.cap` reuse vs. `beginExit`'s own cap (an exit that begins during a hold must not fire the hold's `setTarget(1)` later), the timeline `interrupt()` re-entry in the shake, `liftByKey` leaks on radial row dispose, `popMotion` on a disposed scope. Fix, re-run, commit "Transitions Tier 2: review fixes".
- [ ] **Step 2: RR contract, Tier 2** — extend `RR: tests/facet_transition_contract.spec.luau` with one `it` that mounts a 3-row keyed ForEach with `stagger = 0.02` and asserts the third row is still at alpha 1 after one tick and at 0 after 90 (same shape as Task 8's test). Run `cd games/RascalRally/code && ./run-tests.sh`. Commit in RR.
- [ ] **Step 3: Full verify**

```bash
cd GameStudio/ui/Facet && tools/verify.sh full 2>&1 | tail -20
```
Expected: PASS incl. the `perf` producer. Fix anything red before the canaries.
- [ ] **Step 4: Studio canaries** (owner-run if the Studio MCP is down; follow `docs/guide/11-device-verification.md`):
  1. Rascal Rally: open a screen with an Alert (RolePick) and a Menu; capture open + close. Expect the card to grow in and dip out; the popover to grow from its anchor.
  2. Ten-foot: emulate console, move focus across three buttons with the pad; capture. Expect the lift to travel, not snap.
  3. A Toggle flip; expect the knob to overshoot once.
  Save captures under `artifacts/transitions-round/` and note them in the CHANGELOG bullet.
- [ ] **Step 5: Final commit and report** — list every scene's `observed_p95_ms` before/after in the report (table), the two suites' counts, and the three captures.

---

## Self-review

- **Spec coverage:** 1A→T2, 1B→T3, 1C→T1, 1D→T5, 1E→T4, 2F→T8, 2G→T10+T11, 2H→T9, 2I→T12, 2J→T15, §3.1/§3.3→T13, §3.4→T14 (+T2/T3/T10 spot checks), §3.5→T6+T16, §3.6→Global Constraints, recipes→T15. Tier 3 intentionally absent.
- **Placeholders:** none; where a helper name in an existing spec file is unknown the plan names the file and line to copy it from and keeps the assertion fixed.
- **Type consistency:** `exitClass`/`stagger` are the only new transition keys; `dismiss` is the only new class; `Spec.class`/`Spec.exitClass` names match between resolve, retune and tests; `invalid`, `pop`, `presenter`, `transition` are the only new control keys.
