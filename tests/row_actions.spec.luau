--!strict
-- RowActions control spec (Task 3: composite skeleton, static reveal). Mirrors
-- tests/chip.spec.luau's presenterWorld/renderWorld idioms. This file proves:
--   1. the spec/ActionSpec authoring contract (unknown keys, empty-list refusal);
--   2. the true inert passthrough when neither edge has actions;
--   3. the lazy tray structure (Action:<id> buttons, destructive role);
--   4. long-label survival at the theme's buttonMinWidth floor;
--   5. the static _open/_close/dump seam (Tasks 4-6 build motion on it);
--   6. registry neutrality on dispose;
-- and, because the tray buttons are reached through the composite's OWN
-- input contribution (contribution.attach + a routed handleActivate — see
-- src/controls/row_actions.luau), the four-input REACHABILITY and PARADIGM
-- proofs the extension checker requires of every interactive control
-- (ui_todo §0; UI-PARADIGM-001), exercised through the standard tap/
-- deviceKey device-true paths, same as tests/chip.spec.luau.
--
-- RowActions owns NO in-flight gesture state as of this task (no pointer
-- handling — Step 3 of the plan): hotSwitch = false in the registry row is
-- accurate for what ships here, and Tasks 5-8 (drag/touch/keyboard-adjust)
-- must revisit it once a mid-gesture class flip has something to carry.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local fake_target = require("../tests/lib/fake_target")
local lt = require("./lib/large_text")

-- renderer-level modules for the headless mount->attach->render axis (hover,
-- ten-foot focus), mirroring tests/chip.spec.luau's renderWorld
local mountLib = require("../src/mount")
local renderer = require("../src/render/renderer")
-- the solver's OWN headless text measurement (src/layout/text_metrics), used
-- to independently verify the "no clipping" claim against the button's REAL
-- font/size (read off controller.textAt), not a guessed one.
local text_metrics = require("../src/layout/text_metrics")

local ROW = "/S/Row"
local TRAILING_TRAY = ROW .. "/TrayTrailingWhen/then/TrayTrailing"
local DELETE_PATH = TRAILING_TRAY .. "/Action:delete"

-- a REALISTIC row height (a List/Table row is never text-line-tall) — the
-- tray Buttons fill it, so a too-short fixture would blame the composite for
-- what is really an unrealistic caller-provided row box.
local function content(id: string?)
	return LuauUI.UI.Text({ id = id or "Body", text = "Row content", height = { type = "fixed", px = 48 } })
end

-- Task 4: `_open`/`_close` now ANIMATE through a presenter's real motion
-- clock (delivered via the new `bindMotion` contribution seam), so a test
-- that wants the FULLY REVEALED/CLOSED state after calling them must step
-- frames first — `pres.tick(dt)` takes an EXPLICIT dt (src/present/
-- presenter.luau tickBody: "the headless suite passes a scripted dt"), so
-- this is deterministic regardless of wall-clock time; no scripted clock
-- injection needed (contrast tests/drag_public.spec.luau's `LuauUI.motion.
-- newClock`, which exists to override a DIFFERENT clock — the drag
-- registry's, wired through `controller.setDragCollaborators` — not the
-- presenter's own `self.motionClock` this composite now rides). 90 frames
-- (1.5s) comfortably settles an "object"-class spring (response 0.28s).
local FRAME = 1 / 60
local SETTLE_FRAMES = 90
local function settle(pres: any, frames: number?)
	for _ = 1, frames or SETTLE_FRAMES do
		pres.tick(FRAME)
	end
end

-- presenter harness: the four-input auto-composition path (chip.spec's house
-- style). `build` receives `core` and returns the row_actions instance.
local function presenterWorld(build: (core: any) -> any)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local ra = build(core)
	local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	return { core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
end

-- a world whose trailing tray is ALREADY revealed before the first present —
-- the honest way to reach a lazily-mounted tray button's device-true story
-- without this spec depending on Tasks 5-8's drag/touch gesture machinery
-- (hard rule: prove reachability through the standard Button path, or stop).
local function openTrailingWorld(actions: { any }?)
	local fired: { string } = {}
	local w = presenterWorld(function(core)
		return row_actions.build(LuauUI, core, {
			id = "Row",
			content = content(),
			trailing = actions or {
				{
					id = "delete",
					label = "Delete",
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
		})
	end)
	-- ^ presenterWorld already called present()+refresh() with the tray
	-- CLOSED; open it now and refresh again so the buttons exist to focus.
	w.ra._open("trailing")
	w.pres.refresh()
	return {
		core = w.core,
		env = w.env,
		system = w.system,
		adapter = w.adapter,
		pres = w.pres,
		ra = w.ra,
		fired = fired,
	}
end

-- renderer harness: mount a row_actions (trailing tray pre-opened) and attach
-- the renderer directly, mirroring chip.spec.luau's renderWorld.
local function renderWorldOpen(envSetup: ((any) -> ())?, actions: { any }?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if envSetup then
		envSetup(env)
	end
	local ra = row_actions.build(LuauUI, core, {
		id = "Row",
		content = content(),
		trailing = actions or { { id = "delete", label = "Delete", onAction = function() end } },
	})
	ra._open("trailing")
	local root = mountLib.mount(core, LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return { core = core, env = env, adapter = adapter, controller = controller, ra = ra }
end

describe("RowActions control", function()
	-- 1. AUTHORING CONTRACT (constitution §4; ARCH-1) ------------------------
	it("validates unknown spec keys", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, { contnet = content() } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "you mean", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an empty action list", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, { content = content(), leading = {} })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "nil", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an unknown ActionSpec key", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, {
				content = content(),
				trailing = { { label = "Delete", onAction = function() end, oaction = function() end } :: any },
			})
		end)
		expect(ok).toBe(false)
		-- "onAction" is a 2-edit neighbor of "oaction" (drop 'n', case-fold 'A')
		expect(string.find(tostring(err), "you mean", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an ActionSpec with an unknown role", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, {
				content = content(),
				trailing = { { label = "Delete", role = "scary", onAction = function() end } :: any },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "normal, destructive", 1, true) ~= nil).toBe(true)
	end)

	-- 2. INERT PASSTHROUGH (perf directive) -----------------------------------
	it("is an inert passthrough with no actions", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, { id = "Row", content = content("Body") })
		end)
		expect(w.adapter.node("/S/Body") ~= nil).toBe(true) -- content mounted, unwrapped
		expect(w.adapter.node(ROW) == nil).toBe(true) -- no RowActions wrapper node at all
		expect(w.ra.dump().phase).toBe("closed")
		expect(w.ra._isOpen()).toBe(false)
	end)

	-- 3. LAZY TRAY STRUCTURE ---------------------------------------------------
	it("mounts trailing tray buttons with ids Action:<id> only once revealed", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		-- CLOSED: zero tray GuiObjects (the perf directive's lazy mount)
		expect(w.adapter.node(DELETE_PATH) == nil).toBe(true)
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.adapter.node(DELETE_PATH) ~= nil).toBe(true)
		expect(w.adapter.node(DELETE_PATH).props.label).toBe("Delete")
	end)

	it("destructive action paints danger tokens; normal action paints the default role", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{ id = "delete", label = "Delete", role = "destructive", onAction = function() end },
					{ id = "flag", label = "Flag", onAction = function() end },
				},
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.adapter.node(TRAILING_TRAY .. "/Action:delete").props.role).toBe("destructive")
		expect(w.adapter.node(TRAILING_TRAY .. "/Action:flag").props.role).toBe("default")
	end)

	-- 4. LOCALIZATION SAFETY ----------------------------------------------------
	-- A tray Button with no children solves through the SOLVER'S OWN text-
	-- measure branch (src/layout/solver.luau: `class == "Button"` with no
	-- children -> `kind = "text"`), so `controller.textAt(path)` publishes the
	-- SAME per-text facts tests/text_audit.spec.luau reads for a plain UI.Text
	-- (font, size, lines, naturalLines, truncated) — the real measured-
	-- against-the-real-box facts, not a guess.
	--
	-- A prior version of this test asserted `rect.w >= buttonMinWidth`
	-- (hardcoded floor, true even for a button PINNED at exactly 64px) and
	-- `props.label` equality (always true — this control never mutates the
	-- string); neither could ever fail. Code review (mutating the tray
	-- button's width to `{ type = "fixed", px = 64 }`) caught that the old
	-- test kept passing.
	--
	-- Investigating that mutation live (a throwaway headless repro) found
	-- `textFacts.truncated` can NEVER be true here regardless: `lt.PSEUDO`
	-- (like every string `pseudoLocalize` produces) is always two "words" —
	-- the source text plus a space-separated dot-padding suffix
	-- (tests/fixtures/a11y_l10n_fixtures.luau `pseudoLocalize`) — so
	-- `isSingleWord` (src/render/renderer.luau) is always false for it, the
	-- Button never takes the single-line/clip path, and a too-narrow box
	-- makes it WRAP instead (measured live: the 64px-pinned mutation wraps
	-- the label to 5 lines and balloons the row from 48px to 108px tall,
	-- `truncated` stays `false` throughout — wrapping, unlike a line-capped
	-- ellipsis, is never "truncated"). So the fact that actually distinguishes
	-- "grew wide enough" from "clipped/reflowed" is `lines == 1`: this
	-- composite's contract (`buttonMinWidth` is a floor a button WIDENS past,
	-- Task 2/docs/reference/api.md `newRowActions`) promises a tray action
	-- reads as ONE line, never wraps — the iOS pattern this control follows
	-- never reflows an action label. Backed by an independent measurement
	-- (the solver's own `text_metrics.measure`, at the button's REAL font/
	-- size) proving the box is wide enough for the natural one-line width.
	it("labels survive 1.4x pseudo-loc without clipping (button never narrower than buttonMinWidth)", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = lt.PSEUDO, onAction = function() end } },
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		-- Task 4: the reveal (and each button's proportional width) now
		-- animates — settle the spring before reading the FULLY OPEN width
		-- this test is actually about (localization safety at rest, not the
		-- in-flight shape — that is covered separately below).
		settle(w.pres)
		w.pres.refresh()
		local node = w.adapter.node(DELETE_PATH)
		expect(node ~= nil).toBe(true)
		expect(node.props.label).toBe(lt.PSEUDO)
		expect(node.rect.w >= 64).toBe(true) -- the theme's buttonMinWidth floor (Task 2)

		local facts = w.handle.controller.textAt(DELETE_PATH)
		expect(facts ~= nil).toBe(true)
		expect(facts.truncated).toBe(false)
		expect(facts.lines).toBe(1) -- never wraps: the button widens instead of reflowing

		-- independent proof, not just the solver's own verdict: the box the
		-- button actually solved to is wide enough for the label's real
		-- natural (single-line) width at its real font/size, plus its padding.
		local natural = text_metrics.measure(lt.PSEUDO, facts.font, facts.size, math.huge)
		local buttonPad = 8 -- controls.rowActions.buttonPad (Task 2 default = style.space.s)
		expect(node.rect.w >= natural.width + 2 * buttonPad).toBe(true)
	end)

	-- 5. THE REVEAL SEAM (Task 4 builds spring motion on this) -----------------
	it("_open slides content by tray width; _close returns it; dump reflects openEdge", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra.dump().openEdge).toBe(nil)

		-- `openEdge`/`phase`/`_isOpen()` flip INSTANTLY (Task 4 never delayed
		-- those — only the pixel `offset` itself animates); the spring needs
		-- settling before `offset` reaches the tray width.
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.ra.dump().openEdge).toBe("trailing")
		expect(w.ra.dump().phase).toBe("open")
		expect(w.ra._isOpen()).toBe(true)
		settle(w.pres)
		w.pres.refresh()
		local trayRect = w.adapter.node(TRAILING_TRAY).rect
		expect(w.ra.dump().offset).toBeCloseTo(-trayRect.w, 0.5)

		w.ra._close()
		expect(w.ra.dump().openEdge).toBe(nil)
		expect(w.ra.dump().phase).toBe("closed")
		expect(w.ra._isOpen()).toBe(false)
		settle(w.pres)
		expect(w.ra.dump().offset).toBe(0) -- settle SNAPS exactly onto the target
	end)

	-- 5b. SPRING MOTION (Task 4) ------------------------------------------------
	it("_open animates offset toward tray width over stepped frames", function()
		local function build()
			return presenterWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = content("Body"),
					trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				})
			end)
		end
		-- learn the settled tray width from a throwaway world (same spec, so
		-- the same measured width), rather than reaching into internals
		local ref = build()
		ref.ra._open("trailing")
		ref.pres.refresh()
		settle(ref.pres)
		local trayWidth = -ref.ra.dump().offset
		expect(trayWidth > 0).toBe(true)

		local w = build()
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.ra.dump().offset).toBe(0) -- nothing has animated yet

		w.pres.tick(FRAME)
		local afterOne = w.ra.dump().offset
		expect(afterOne < 0).toBe(true) -- moving toward the (negative) trailing target
		expect(afterOne > -trayWidth).toBe(true) -- not there yet

		for _ = 1, 59 do
			w.pres.tick(FRAME)
		end
		expect(-w.ra.dump().offset).toBeCloseTo(trayWidth, 0.5) -- 60 frames: settled
	end)

	it("buttons grow proportionally with offset", function()
		local function build()
			return presenterWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = content("Body"),
					trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				})
			end)
		end
		local ref = build()
		ref.ra._open("trailing")
		ref.pres.refresh()
		settle(ref.pres)
		ref.pres.refresh()
		local fullWidth = ref.adapter.node(DELETE_PATH).rect.w
		local trayWidth = -ref.ra.dump().offset
		expect(fullWidth > 0).toBe(true)

		local w = build()
		w.ra._open("trailing")
		w.pres.refresh()
		-- a handful of frames in: neither at rest nor fully revealed
		for _ = 1, 8 do
			w.pres.tick(FRAME)
		end
		w.pres.refresh()
		local frac = math.abs(w.ra.dump().offset) / trayWidth
		expect(frac > 0.05 and frac < 0.95).toBe(true) -- genuinely mid-flight
		local midWidth = w.adapter.node(DELETE_PATH).rect.w
		expect(midWidth).toBeCloseTo(fullWidth * frac, 1) -- SAME observed value, no second spring
	end)

	it("reduced motion snaps the reveal in one frame", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("reducedMotion", true) -- derives env:get("motionPolicy") == "reduced"
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = content("Body"),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		pres.present(LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } }))
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		pres.tick(FRAME) -- one step: decorative motion under reduced policy snaps
		pres.refresh()
		local trayRect = adapter.node(TRAILING_TRAY).rect
		expect(ra.dump().offset).toBe(-trayRect.w)
	end)

	it("dispose mid-flight leaks nothing", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = content("Body"),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		for _ = 1, 3 do
			pres.tick(FRAME)
		end
		local mid = ra.dump().offset
		expect(mid < 0).toBe(true) -- in flight: neither 0 nor settled

		pres.dismiss(handle)
		ra.dispose()

		for _ = 1, 10 do
			pres.tick(FRAME)
		end
		expect(ra.dump().offset).toBe(mid) -- disposed: further steps change nothing

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	it("_settleTo retargets the spring at the verdict (Task 5 wires the gesture that produces one)", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		local trayWidth = -w.ra.dump().offset

		w.ra._settleTo({ target = 0, edge = nil, commit = false })
		settle(w.pres)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra.dump().openEdge).toBe(nil)

		w.ra._settleTo({ target = -trayWidth, edge = "trailing", commit = false })
		settle(w.pres)
		expect(w.ra.dump().offset).toBe(-trayWidth)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	it("_open on an edge with no actions is a no-op", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		w.ra._open("leading") -- no leading actions declared
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
	end)

	-- 6. DISPOSAL / REGISTRY NEUTRALITY ------------------------------------------
	it("dispose unmounts and releases the scope", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = content("Body"),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		adapter.tap(DELETE_PATH)

		pres.dismiss(handle)
		ra.dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	-- 7. FOUR-INPUT REACHABILITY (ui_todo §0) — device-true, all four classes.
	-- Proven through the standard UI.Button path a revealed tray action IS
	-- (hard rule: honest reachability through what this task actually built,
	-- not a fabricated proof of the swipe gesture itself — that is Tasks 5-8).
	it("RowActions pointer: a tap on a revealed tray action activates it (device-true)", function()
		local w = openTrailingWorld()
		expect(#w.fired).toBe(0)
		w.adapter.tap(DELETE_PATH)
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions touch: a touch tap on a revealed tray action activates it (device-true)", function()
		local w = openTrailingWorld()
		w.adapter.tap(DELETE_PATH, { source = "pointer", pointer = "touch" })
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions keyboard: focus + Return activates a revealed tray action", function()
		local w = openTrailingWorld()
		expect(w.pres.focus.focused:get()).toBe(DELETE_PATH)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions gamepad: focus + ButtonA activates a revealed tray action", function()
		local w = openTrailingWorld()
		expect(w.pres.focus.focused:get()).toBe(DELETE_PATH)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.fired[1]).toBe("delete")
	end)

	-- 8. PARADIGM AXIS (UI-PARADIGM-001) — the STRUCTURAL IDIOM per class. Every
	-- tray action IS a standard UI.Button, so it inherits the Button contract's
	-- own affordances; these cases prove the composite does not defeat them.
	it("RowActions pointer affordance: the pointer structural idiom (hover on a revealed tray action)", function()
		local w = renderWorldOpen(function(env)
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			env:set("preferredInput", "KeyboardAndMouse")
		end)
		expect(w.adapter.node(DELETE_PATH).hoverEnabled).toBe(true)
		w.adapter.hover(DELETE_PATH)
		expect(w.adapter.node(DELETE_PATH).hovered).toBe(true)
		w.adapter.unhover(DELETE_PATH)
		expect(w.adapter.node(DELETE_PATH).hovered).toBe(false)
	end)

	it("RowActions touch affordance: the touch structural idiom (44px floor on a revealed tray action)", function()
		local w = renderWorldOpen(function(env)
			env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
			env:set("preferredInput", "Touch")
		end)
		expect(w.adapter.node(DELETE_PATH).rect.h >= 44).toBe(true)
	end)

	it("RowActions keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate)", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local fired: { string } = {}
		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = content("Body"),
			trailing = {
				{
					id = "flag",
					label = "Flag",
					onAction = function()
						table.insert(fired, "flag")
					end,
				},
				{
					id = "delete",
					label = "Delete",
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
		})
		ra._open("trailing")
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		pres.present(screen)
		pres.refresh()
		local flagPath = TRAILING_TRAY .. "/Action:flag"
		local deletePath = TRAILING_TRAY .. "/Action:delete"
		expect(pres.focus.focused:get()).toBe(flagPath) -- Navigate order: leftmost tray button first
		expect(adapter.node(flagPath).focused).toBe(true)
		system.deviceKey("Right", true)
		system.deviceKey("Right", false)
		expect(pres.focus.focused:get()).toBe(deletePath) -- Navigate moved the ring
		expect(adapter.node(deletePath).focused).toBe(true)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(fired[1]).toBe("delete") -- Activate hit the focused action only
	end)

	it(
		"RowActions gamepad affordance: the gamepad structural idiom (ten-foot focus on a revealed tray action)",
		function()
			local big = renderWorldOpen(function(env)
				env:set("displaySize", "Large")
			end)
			big.controller.setFocusPath(DELETE_PATH)
			local near = renderWorldOpen(function(env)
				env:set("displaySize", "Medium")
			end)
			near.controller.setFocusPath(DELETE_PATH)
			expect(big.adapter.node(DELETE_PATH).focusProfile).toBe("ten-foot")
			expect(near.adapter.node(DELETE_PATH).focusProfile).toBe("near")
		end
	)
end)
