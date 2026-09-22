--!strict
local harness = require("./lib/harness")
-- Chip control spec. A Chip is a small toggleable tag/filter pill: Activate
-- (pointer tap / click / keyboard Return / gamepad ButtonA) flips the owner-held
-- `selected` signal and calls `onToggle`; the surface reflects selection. It owns
-- NO in-flight state, so the paradigm axis is: pointer HOVER preview, touch 44px
-- floor, keyboard focus-ring + Navigate→Activate, gamepad ten-foot focus — and
-- hotSwitch = false (nothing to carry/cancel mid-gesture).
--
-- Every interaction runs through a REAL device path: adapter.tap (pointer/touch)
-- and system.deviceKey (keyboard/gamepad) via the presenter's zero-opt auto
-- composition; hover/focus-profile idioms run through the renderer's synthetic
-- hover/focus seams. No callback is ever called directly.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local Facet = require("../src") :: any
local chip = require("../src/controls/chip")
local fake_target = require("../tests/lib/fake_target")

-- renderer-level modules for the headless mount→attach→render axis (hover,
-- ten-foot focus, layout), mirroring tests/paradigm_hover + paradigm_tenfoot
local mountLib = harness
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local Compose = require("../src/vendor/compose/core")

local CHIP = "/S/Chip+target/Chip"
local CHIP2 = "/S/Chip2+target/Chip2"

-- presenter harness: the four-input auto-composition path (auto_input house style)
local function presenterWorld(opts: any?)
	local options = opts or {}
	local core = harness.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = harness.newPresenter(core, env, adapter, system)
	local selected = Compose.cell(options.selected == true)
	local toggles: { boolean } = {}
	local c = chip.build(Facet, core, {
		id = "Chip",
		label = "Rain",
		selected = selected,
		onToggle = function(v: boolean)
			table.insert(toggles, v)
		end,
	})
	local children = { c.blueprint }
	local selected2 = nil
	local c2 = nil
	if options.sibling then
		selected2 = Compose.cell(false)
		c2 = chip.build(Facet, core, { id = "Chip2", label = "Snow", selected = selected2 })
		table.insert(children, c2.blueprint)
	end
	local screen = harness.UI.Screen({ id = "S", children = children })
	local handle = pres.present(screen) -- ZERO opts: full auto-composition
	pres.refresh()
	return {
		core = core,
		env = env,
		system = system,
		adapter = adapter,
		pres = pres,
		chip = c,
		selected = selected,
		toggles = toggles,
		selected2 = selected2,
		chip2 = c2,
		handle = handle,
	}
end

-- renderer harness: mount a chip inside a Screen and attach the renderer directly
local function renderWorld(envSetup: ((any) -> ())?)
	local core = harness.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if envSetup then
		envSetup(env)
	end
	local selected = Compose.cell(false)
	local c = chip.build(Facet, core, { id = "Chip", label = "Rain", selected = selected })
	local root = mountLib.mount(core, harness.UI.Screen({ id = "S", children = { c.blueprint } }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return { core = core, env = env, adapter = adapter, controller = controller, chip = c, selected = selected }
end

describe("Chip control", function()
	-- 1. BUILD + RENDER (playbook step 2.1) --------------------------------
	it("builds, mounts, and renders headlessly with no error", function()
		local w = renderWorld()
		expect(w.chip.blueprint ~= nil).toBeTruthy()
		expect(w.adapter.node(CHIP) ~= nil).toBe(true)
		expect(w.adapter.node(CHIP).props.label).toBe("Rain")
		expect(w.core.lastError()).toBe(nil)
	end)

	-- 2. FOUR-INPUT REACHABILITY (ui_todo §0) — device-true, all four classes
	it("Chip pointer: a tap activates through the presenter (device-true)", function()
		local w = presenterWorld()
		expect(w.selected:peek()).toBe(false)
		w.adapter.tap(CHIP) -- mouse pointer tap (meta = nil)
		expect(w.selected:peek()).toBe(true)
		w.pres.refresh() -- flush the binding to the rendered surface
		expect(w.adapter.node(CHIP).props.selected).toBe(true) -- surface reflects it
		expect(w.toggles[1]).toBe(true) -- onToggle fired with the new value
		w.adapter.tap(CHIP)
		expect(w.selected:peek()).toBe(false)
	end)

	it("Chip touch: a touch tap/pan drives the control (device-true)", function()
		local w = presenterWorld()
		-- a touch-typed activation: the engine's Activated meta carries
		-- pointer="touch" (screen_target.luau), distinct from the mouse path
		w.adapter.tap(CHIP, { source = "pointer", pointer = "touch" })
		expect(w.selected:peek()).toBe(true)
		expect(w.toggles[1]).toBe(true)
		w.adapter.tap(CHIP, { source = "pointer", pointer = "touch" })
		expect(w.selected:peek()).toBe(false)
	end)

	it("Chip keyboard: focus + Return drives the control", function()
		local w = presenterWorld()
		expect(w.pres.focus.focused:peek()).toBe(CHIP) -- auto-focused sole focusable
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.selected:peek()).toBe(true)
		expect(w.toggles[1]).toBe(true)
	end)

	it("Chip gamepad: focus + ButtonA drives the control", function()
		local w = presenterWorld()
		expect(w.pres.focus.focused:peek()).toBe(CHIP)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.selected:peek()).toBe(true)
	end)

	-- 3. PARADIGM AXIS (UI-PARADIGM-001) — the STRUCTURAL IDIOM per class,
	-- distinct from mere reachability above.
	it("Chip pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)", function()
		-- the free HOVER preview layer: a pointer-live renderer wires hover onto
		-- the interactive chip surface; synthetic hover flips its state.
		local w = renderWorld(function(env)
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			env:set("preferredInput", "KeyboardAndMouse")
		end)
		expect(w.adapter.node(CHIP).hoverEnabled).toBe(true)
		w.adapter.hover(CHIP)
		expect(w.adapter.node(CHIP).hovered).toBe(true)
		w.adapter.unhover(CHIP)
		expect(w.adapter.node(CHIP).hovered).toBe(false)
	end)

	it("Chip touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)", function()
		-- the 44px hit floor: the chip enforces the Button contract's minHitSize
		-- as a real layout minimum, so a finger always has a 44px target.
		local w = renderWorld(function(env)
			env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
			env:set("preferredInput", "Touch")
		end)
		expect(w.adapter.node(CHIP).rect.h >= 44).toBe(true)
		-- and a pure-touch device allocates NO hover wiring (hover is pointer-only;
		-- nothing essential lives behind it — the tap still activates below)
		expect(w.adapter.node(CHIP).hoverEnabled ~= true).toBe(true)
	end)

	it("Chip keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)", function()
		-- Navigate (arrows) moves the visible focus RING between siblings, then
		-- Activate (Return) fires on the focused one — the keyboard idiom, which
		-- reachability (single pre-focused chip) does not exercise.
		local w = presenterWorld({ sibling = true })
		expect(w.pres.focus.focused:peek()).toBe(CHIP)
		expect(w.adapter.node(CHIP).focused == true).toBe(false) -- no navigation yet
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:peek()).toBe(CHIP2) -- Navigate moved the ring
		expect(w.adapter.node(CHIP2).focused).toBe(true)
		expect(w.adapter.node(CHIP).focused == true).toBe(false)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.selected2:peek()).toBe(true) -- Activate hit the focused chip only
		expect(w.selected:peek()).toBe(false)
	end)

	it("Chip gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)", function()
		-- the ten-foot focus strengthening (matrix D.4): a Large display renders a
		-- STRONGER focus profile than a near Medium display — the gamepad/10-foot
		-- idiom, distinct from the ButtonA reachability proof.
		local big = renderWorld(function(env)
			env:set("displaySize", "Large")
		end)
		big.controller.setFocusPath(CHIP)
		local near = renderWorld(function(env)
			env:set("displaySize", "Medium")
		end)
		near.controller.setFocusPath(CHIP)
		expect(big.adapter.node(CHIP).focusProfile).toBe("ten-foot")
		expect(near.adapter.node(CHIP).focusProfile).toBe("near")
		expect(big.adapter.node(CHIP).focusProfile ~= near.adapter.node(CHIP).focusProfile).toBe(true)
	end)

	-- 4. NO FACTORY RERUNS for a binding change (playbook step 2.4) --------
	it("flipping selected updates the surface with no factory rerun", function()
		local w = presenterWorld()
		local runsBefore = w.handle.root.counters().factoryRuns
		w.adapter.tap(CHIP)
		w.pres.refresh()
		expect(w.adapter.node(CHIP).props.selected).toBe(true)
		expect(w.handle.root.counters().factoryRuns).toBe(runsBefore) -- state-driven
	end)

	-- 5. DUMP DETERMINISM (playbook step 2.5) ------------------------------
	it("dump() is deterministic and reflects the live state", function()
		local w = presenterWorld()
		local d1 = serde.encode("json", w.chip.dump(), true)
		expect(d1).toBe(serde.encode("json", w.chip.dump(), true))
		expect(w.chip.dump().selected).toBe(false)
		w.adapter.tap(CHIP)
		expect(w.chip.dump().selected).toBe(true)
		expect(w.chip.dump().label).toBe("Rain")
	end)

	-- 6. REGISTRY NEUTRALITY (playbook step 2.6) ---------------------------
	it("build/mount/present/interact/dispose returns every registry to baseline", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = harness.newPresenter(core, env, adapter, system)
		local baseline = core.owner.size() -- AFTER the long-lived singletons

		local selected = Compose.cell(false)
		local c = chip.build(Facet, core, { id = "Chip", label = "Rain", selected = selected })
		local screen = harness.UI.Screen({ id = "S", children = { c.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		adapter.tap(CHIP)
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)

		pres.dismiss(handle)
		c.dispose()

		local after = core.owner.size()
		expect(after).toBe(baseline)
	end)

	-- 7. BUILD-TIME CONTRACT (CTRL-03, api-architecture-consistency F-2) -----
	-- `selected` is the owner's data model and the control's single mutation
	-- site. A missing one used to error on the first TAP ("attempt to index
	-- nil"); a read-only Memo used to error with "cannot set a memo" from deep
	-- inside core. Both are BUILD errors now, exactly like every sibling.
	it("rejects a missing `selected` at BUILD, naming the control and the field", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			return chip.build(Facet, core, { id = "Rain", label = "Rain" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Chip", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "selected", 1, true) ~= nil).toBe(true)
		expect(
			string.find(
				tostring(err),
				"must be a writable Compose cell holding a boolean, owned by the caller",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("rejects a read-only Memo `selected` at BUILD", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			return chip.build(Facet, core, {
				id = "Rain",
				label = "Rain",
				selected = Compose.formula(function()
					return false
				end),
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Chip", 1, true) ~= nil).toBe(true)
		expect(
			string.find(
				tostring(err),
				"must be a writable Compose cell holding a boolean, owned by the caller",
				1,
				true
			) ~= nil
		).toBe(true)
	end)
end)

describe("Removable Chip", function()
	local world = require("./lib/world")
	local function path(w, suffix)
		for candidate in w.adapter.liveNodes() do
			if string.sub(candidate, -#suffix) == suffix then
				return candidate
			end
		end
		error("missing chip " .. suffix)
	end
	for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
		it("keeps the token body inert and removes once through " .. input, function()
			local w = world.new()
			local calls = 0
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Chip("Token")({
						label = "Rain",
						onRemove = function()
							calls += 1
						end,
					}),
				})
			end)
			local remove = path(w, "/Remove")
			expect(#w.handle.focusOrder().traversal).toBe(1)
			w.adapter.tap(path(w, "/Token"))
			expect(calls).toBe(0)
			if input == "pointer" then
				w.adapter.tap(remove)
			elseif input == "touch" then
				w.adapter.touchTap(remove)
			else
				w.pres.focus.focusOn(remove)
				w.press(if input == "keyboard" then "Return" else "ButtonA")
			end
			expect(calls).toBe(1)
			local raw = require("../src/paths").nodeAt(w.handle.root.node, remove)
			expect(raw.props.label).toBe("Remove Rain")
			-- one pill (owner report 2026-09-22): the close segment continues the
			-- body's plate at its trailing edge, same line, no gap
			local body = w.adapter.node(path(w, "/Token+target/Token")).rect
			local mark = w.adapter.node(remove).rect
			expect(`{mark.x - (body.x + body.w)} {mark.y - body.y} {mark.h - body.h}`).toBe("0 0 0")
			expect(mark.w >= 44).toBe(true)
		end)
	end
	it("distinguishes a body named Remove and reserves disjoint effective targets", function()
		for _, rung in { false, "compact", "large" } do
			local snapshot = require("../src/themes/snapshot")
			local metrics = table.clone(snapshot.neutral())
			metrics.targetSizes = table.clone(metrics.targetSizes)
			metrics.targetSizes.minimum = 60
			local w = world.new({ themeMetrics = metrics })
			local selected = Compose.cell(false)
			local removes = 0
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.HStack("Tokens")({
						gap = 0,
						w.UI.Chip("Remove")({
							label = "A",
							selected = selected,
							controlSize = if rung then rung else nil,
							onRemove = function()
								removes += 1
							end,
						}),
						w.UI.Button("Next")({ label = "Next" }),
					}),
				})
			end)
			local body = "/S/Tokens/Remove+token/Remove+target/Remove"
			local remove = "/S/Tokens/Remove+token/Remove"
			local bodyHit = w.adapter.hitRectOf(body) or w.adapter.node(body).rect
			local removeHit = w.adapter.hitRectOf(remove) or w.adapter.node(remove).rect
			expect(bodyHit.x + bodyHit.w <= removeHit.x).toBe(true)
			expect(removeHit.x + removeHit.w <= w.adapter.node("/S/Tokens/Next").rect.x).toBe(true)
			local plate, mark = w.adapter.node(body).rect, w.adapter.node(remove).rect
			expect(`{tostring(rung)}: {mark.x - (plate.x + plate.w)} {mark.y - plate.y} {mark.h - plate.h}`).toBe(
				`{tostring(rung)}: 0 0 0`
			)
			w.adapter.tap(body)
			expect(selected:peek()).toBe(true)
			expect(removes).toBe(0)
			w.adapter.tap(remove)
			expect(removes).toBe(1)
			expect(selected:peek()).toBe(true)
			w.close()
		end
	end)
	it("joins the close segment to the pill in skinned themes at every rung", function()
		local snapshot = require("../src/themes/snapshot")
		for _, theme in { "pixel_quest", "fantasy_ornate" } do
			local metrics = snapshot.resolve(require("../examples/themes/" .. theme).build(Facet.themes), nil, {})
			for _, rung in { false, "compact", "large" } do
				local w = world.new({ themeMetrics = metrics })
				w.present(function()
					return w.UI.Screen("S")({
						w.UI.Chip("Token")({
							label = "Rain",
							controlSize = if rung then rung else nil,
							onRemove = function() end,
						}),
					})
				end)
				local plate = w.adapter.node(path(w, "/Token+target/Token")).rect
				local mark = w.adapter.node(path(w, "/Token+token/Remove")).rect
				expect(`{theme} {tostring(rung)}: {mark.x - (plate.x + plate.w)} {mark.y - plate.y} {mark.h - plate.h}`).toBe(
					`{theme} {tostring(rung)}: 0 0 0`
				)
				w.close()
			end
		end
	end)
	it("chooses next then previous then caller fallback through real keyed owner disposal", function()
		local w = world.new()
		local items = Compose.cell({ "A", "B", "C" })
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.VStack("List")({
					w.UI.Button("Fallback")({ label = "Add", onActivate = function() end }),
					w.UI.ForEach("Tokens")({
						items = items,
						key = function(item)
							return item
						end,
						row = function(item)
							return w.UI.Chip(item)({
								label = item,
								removeFocusFallback = "/S/List/Fallback",
								onRemove = function()
									local nextItems = {}
									for _, value in items:peek() do
										if value ~= item then
											table.insert(nextItems, value)
										end
									end
									items:set(nextItems)
								end,
							})
						end,
					}),
				}),
			})
		end)
		local a, b, c = path(w, "/A+token/Remove"), path(w, "/B+token/Remove"), path(w, "/C+token/Remove")
		w.pres.focus.focusOn(b)
		w.adapter.tap(b)
		w.settle()
		expect(w.pres.focus.focused:peek()).toBe(c)
		w.adapter.tap(c)
		w.settle()
		expect(w.pres.focus.focused:peek()).toBe(a)
		w.adapter.tap(a)
		w.settle()
		expect(w.pres.focus.focused:peek()).toBe("/S/List/Fallback")
	end)
	it("does not steal departed focus when a retained removal request is disposed later", function()
		for _, destination in { "/C+token/Remove", "/Unrelated" } do
			local w = world.new()
			local items = Compose.cell({ "A", "B", "C" })
			local requests = 0
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Button("Fallback")({ label = "Add", onActivate = function() end }),
					w.UI.Button("Unrelated")({ label = "Other command", onActivate = function() end }),
					w.UI.ForEach("Tokens")({
						items = items,
						key = function(item)
							return item
						end,
						row = function(item)
							return w.UI.Chip(item)({
								label = item,
								removeFocusFallback = "/S/Fallback",
								onRemove = function()
									requests += 1
								end,
							})
						end,
					}),
				})
			end)
			local a = path(w, "/A+token/Remove")
			w.pres.focus.focusOn(a)
			w.adapter.tap(a)
			w.settle()
			expect(requests).toBe(1)
			expect(w.adapter.node(a) ~= nil).toBe(true)
			local elsewhere = path(w, destination)
			expect(w.pres.focus.focusOn(elsewhere)).toBe(true)
			items:set({ "B", "C" })
			w.settle()
			expect(w.adapter.node(a)).toBeNil()
			expect(w.pres.focus.focused:peek()).toBe(elsewhere)
			w.close()
			expect(w.adapter.liveCount()).toBe(0)
		end
	end)

	it("does not repeat a held Remove across an input-class change and respects inherited disabled", function()
		local w = world.new()
		local enabled = Compose.cell(true)
		local calls = 0
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.ZStack("Owner")({
					enabled = enabled,
					w.UI.Chip("Token")({
						label = "Rain",
						onRemove = function()
							calls += 1
						end,
					}),
				}),
			})
		end)
		local remove = path(w, "/Remove")
		w.pres.focus.focusOn(remove)
		w.system.deviceKey("Return", true)
		expect(calls).toBe(1)
		w.env:set("capabilities", { mouse = true, keyboard = true, touch = true, gamepad = true })
		w.env:set("preferredInput", "Gamepad")
		w.settle()
		expect(w.env:get("effectiveInput"):peek()).toBe("Gamepad")
		w.system.deviceKey("Return", false)
		w.settle()
		expect(calls).toBe(1)
		w.env:set("preferredInput", "KeyboardAndMouse")
		enabled:set(false)
		w.settle()
		w.adapter.tap(remove)
		expect(calls).toBe(1)
		enabled:set(true)
		w.settle()
		w.adapter.tap(remove)
		expect(calls).toBe(2)
	end)
end)

describe("Chip target reservations", function()
	it("separates short zero-gap targets and activates the intended model at each edge", function()
		local world = require("./lib/world")
		for _, minimum in { 44, 60 } do
			local metrics = table.clone(require("../src/themes/snapshot").neutral())
			metrics.targetSizes = table.clone(metrics.targetSizes)
			metrics.targetSizes.minimum = minimum
			local w = world.new({ themeMetrics = metrics })
			local a, b = Compose.cell(false), Compose.cell(false)
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.HStack("Row")({
						gap = 0,
						w.UI.Chip("A")({ label = "A", selected = a }),
						w.UI.Chip("B")({ label = "B", selected = b }),
					}),
				})
			end)
			local ap, bp
			for _, path in w.adapter.paths() do
				if path:sub(-2) == "/A" then
					ap = path
				elseif path:sub(-2) == "/B" then
					bp = path
				end
			end
			local ar = w.adapter.hitRectOf(ap) or w.adapter.node(ap).rect
			local br = w.adapter.hitRectOf(bp) or w.adapter.node(bp).rect
			expect(ar.w >= minimum and ar.h >= minimum).toBe(true)
			expect(ar.x + ar.w <= br.x).toBe(true)
			-- The fake exposes engine activation metadata; native coordinate hit testing
			-- is a separate aggregate witness. These points lie inside one target only.
			w.adapter.touchTap(ap, { x = ar.x + ar.w - 1, y = ar.y + ar.h / 2 })
			expect(a:peek()).toBe(true)
			expect(b:peek()).toBe(false)
			w.adapter.touchTap(bp, { x = br.x + 1, y = br.y + br.h / 2 })
			expect(a:peek()).toBe(true)
			expect(b:peek()).toBe(true)
		end
	end)
end)
