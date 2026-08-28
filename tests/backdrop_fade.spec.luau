--!strict
--[[ BACKDROP-BEFORE-CONTENT — the pop class fixed-3's cause C rhymed with
	(framework-gaps-phase2-followups task POP, director item 10 + mandate b).

	THE VIDEO (newpop.mov): tapping a Glade "Recent visitors" row fades a detail
	card in OVER the list — mid-fade BOTH the card's text and the list behind it
	are legible, settling clean a beat later. Root cause, measured headlessly
	(no frame-diff, no engine, no timing — see section C): `shop.wisp` (and
	three siblings through the shared `sheet()`/`page()` helpers) put an opaque
	`surface = "raised"` plate INSIDE the one `canvasGroup` its push transition
	targets. `CanvasGroup.GroupTransparency` is ONE scalar Roblox composites
	over the WHOLE subtree, so the plate necessarily reached full opacity at the
	exact instant its text did — "the backdrop is legible no later than the
	content" (the director's own invariant, mandate b) was impossible BY
	CONSTRUCTION, not merely unlikely.

	THE GENERAL MECHANISM (not a per-site patch): `src/render/transitions.luau`
	now SPLITS THE WRITE. Position/scale still target the node the caller
	declared (a plain `UIScale`/offset moves a plate and its content as one
	rigid unit, canvasGroup or not). Alpha alone needs the group, and when the
	declared node is not itself one, the coordinator now finds the ONE
	canvasGroup in its subtree and routes `GroupTransparency` there — the
	backdrop is then never a descendant of what fades. `sheet()`/`page()`/
	`shop.wisp`/the charm tiers were restructured to use exactly that shape:
	the plate is a direct, NON-canvasGroup child; the content one level further
	in is the fade group.

	MANDATE (b), ANSWERED. This whole class is visible with ZERO frames
	stepped: `transitions.findBackdropFindings` is a pure structural read of
	`.props`/`.children` — section A proves it red on the unfixed shape and
	green on the fixed one with no clock, no engine, no adapter at all. Section
	B proves the SAME thing through the live coordinator (a real `beginEnter`),
	confirming the structural finding and the actual `GroupTransparency` write
	agree. Section C proves the real reference app: every `sheet()`-based Glade
	modal (wisp, charm, provisions, picker) reports zero findings post-fix. What
	this file does NOT claim: whether a player perceives the double-exposure as
	jarring is a question of duration and contrast this instrument does not
	answer — that is the device sweep's (mandate a's) to make, on the shipped
	build this fix produces.

	THE GATE: `tools/check_gate_pins.py` reads this file's own suite-grep
	pattern (see the manifest); registered in `tests/run.luau` so a FUTURE
	backdrop-inside-fade-group construction reddens CI the moment its push
	transition first runs, anywhere in the framework or its reference apps —
	not a script someone has to remember to re-run.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local transitionsLib = require("../src/render/transitions")
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local clockLib = require("../src/motion/clock")
local fake_target = require("./lib/fake_target")
local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local gladeProof = require("../examples/reference/p1_glade") :: any

local FRAME = 1 / 60

-- ============================================================================
-- A. THE PURE STRUCTURAL FINDER — no clock, no engine, no adapter: a mounted
--    node's own `.props`/`.children` are the whole input.
-- ============================================================================

-- a bare mounted-node stand-in: `findBackdropFindings`/`resolveAlphaTarget`
-- read exactly these three fields off a real one (`src/mount.luau`'s
-- `mountNode` produces the same shape), so a plain table exercises them with
-- no mount, no core, no scope.
local function node(path: string, props: { [string]: any }?, children: { any }?): any
	return { path = path, props = props or {}, children = children or {} }
end

describe("backdrop-before-content: the pure structural finder", function()
	it("an opaque surface as a DIRECT child of the fade group is the finding", function()
		local group = node("/S/Group", { canvasGroup = true }, {
			node("/S/Group/Plate", { surface = "raised" }),
		})
		local findings = transitionsLib.findBackdropFindings(group.path, group)
		expect(#findings).toBe(1)
		expect(findings[1].path).toBe("/S/Group")
		expect(findings[1].backdropPath).toBe("/S/Group/Plate")
		expect(findings[1].surface).toBe("raised")
	end)

	it("names the fix in plain language", function()
		local group = node("/S/Group", { canvasGroup = true }, {
			node("/S/Group/Plate", { surface = "raised" }),
		})
		local issue = transitionsLib.backdropIssue(transitionsLib.findBackdropFindings(group.path, group)[1])
		expect(string.find(issue, "surface", 1, true) ~= nil).toBe(true)
		expect(string.find(issue, "OUTSIDE the fade group", 1, true) ~= nil).toBe(true)
	end)

	it('`surface = "plain"` never paints, so it is never a finding', function()
		local group = node("/S/Group", { canvasGroup = true }, {
			node("/S/Group/Ghost", { surface = "plain" }),
		})
		expect(#transitionsLib.findBackdropFindings(group.path, group)).toBe(0)
	end)

	it("no surface anywhere is zero findings", function()
		local group = node("/S/Group", { canvasGroup = true }, {
			node("/S/Group/Label", { text = "hi" }),
		})
		expect(#transitionsLib.findBackdropFindings(group.path, group)).toBe(0)
	end)

	it("a surface TWO levels in is ordinary content, not a second backdrop — deliberately out of scope", function()
		local group = node("/S/Group", { canvasGroup = true }, {
			node("/S/Group/Row", {}, {
				node("/S/Group/Row/Card", { surface = "raised" }),
			}),
		})
		expect(#transitionsLib.findBackdropFindings(group.path, group)).toBe(0)
	end)

	it("MUTATION PROOF: the fixed shape is clean, and re-nesting the plate reddens it", function()
		-- THE FIXED SHAPE (what `shop.wisp` looks like after this task): the
		-- plate is a SIBLING one level out, the fade group wraps content only.
		local fixedContent = node("/S/Plate/Content", { canvasGroup = true }, {
			node("/S/Plate/Content/Name", {}),
		})
		expect(#transitionsLib.findBackdropFindings(fixedContent.path, fixedContent)).toBe(0)

		-- THE MUTATION: re-introduce task POP's own root cause by moving the
		-- plate back inside the group (`shop.wisp` before this task's fix).
		local mutated = node("/S/Group", { canvasGroup = true }, {
			node("/S/Group/Plate", { surface = "raised" }, {
				node("/S/Group/Plate/Name", {}),
			}),
		})
		local findings = transitionsLib.findBackdropFindings(mutated.path, mutated)
		expect(#findings).toBe(1)
		expect(findings[1].backdropPath).toBe("/S/Group/Plate")
	end)
end)

-- ============================================================================
-- B. THE LIVE COORDINATOR — a real `beginEnter`, a real `GroupTransparency`
--    write, over `tests/lib/fake_target`. Proves the structural finding and
--    the actual engine write agree, and that the write SPLITS: transform
--    still rides the whole card, alpha isolates to the resolved content group.
-- ============================================================================

local function world()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local clock = clockLib.new(core, { motionPolicy = env:get("motionPolicy") })
	return core, env, clock
end

local function attach(core: any, env: any, clock: any, screen: any)
	local coordinator = transitionsLib.new({ core = core, clock = clock })
	local root = mountLib.mount(core, screen, { transitions = coordinator })
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	coordinator.bindController(controller)
	return root, adapter, controller, coordinator
end

-- the FIXED shape, as `shop.wisp` builds it post-task-POP: `Wrap` (plain,
-- carries transform), `Plate` (surface, never fades), `Group` (the ONE
-- canvasGroup, one level further in).
local function fixedScreen(condition: any): any
	return UI.Screen({
		id = "S",
		children = {
			UI.When({
				id = "Gate",
				condition = condition,
				transition = { enter = "materialize", class = "container" },
				thenView = function()
					return UI.ZStack({
						id = "Wrap",
						children = {
							UI.VStack({
								id = "Plate",
								surface = "raised",
								children = {
									UI.ZStack({
										id = "Group",
										canvasGroup = true,
										children = { UI.Button({ id = "Go", label = "Go" }) },
									}),
								},
							}),
						},
					})
				end,
			}),
		},
	})
end

-- the ORIGINAL, BUGGY shape (`shop.wisp` before this task): the plate is
-- INSIDE the one canvasGroup the push transition targets.
local function buggyScreen(condition: any): any
	return UI.Screen({
		id = "S",
		children = {
			UI.When({
				id = "Gate",
				condition = condition,
				transition = { enter = "materialize", class = "container" },
				thenView = function()
					return UI.ZStack({
						id = "Group",
						canvasGroup = true,
						children = {
							UI.VStack({
								id = "Plate",
								surface = "raised",
								children = { UI.Button({ id = "Go", label = "Go" }) },
							}),
						},
					})
				end,
			}),
		},
	})
end

describe("backdrop-before-content: the live coordinator", function()
	it("RED — the buggy shape: the coordinator reports the finding, and the plate itself fades", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter, _, coordinator = attach(core, env, clock, buggyScreen(on))
		local findings = coordinator.findings()
		expect(#findings).toBe(1)
		expect(findings[1].backdropPath).toBe("/S/Gate/then/Group/Plate")
		-- the smoking gun (task POP): the PLATE's own instance carries
		-- `GroupTransparency` because it IS the canvasGroup's only child —
		-- the exact newpop.mov mechanism, headless.
		local plate = adapter.node("/S/Gate/then/Group")
		expect(plate.canvasGroupInstance.groupTransparency).toBe(1) -- seeded absent
		clock:step(FRAME)
		expect(plate.canvasGroupInstance.groupTransparency < 1).toBe(true)
	end)

	it("GREEN — the fixed shape: zero findings, and the plate NEVER fades while the content does", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter, _, coordinator = attach(core, env, clock, fixedScreen(on))
		expect(#coordinator.findings()).toBe(0)
		local plate = adapter.node("/S/Gate/then/Wrap/Plate")
		local group = adapter.node("/S/Gate/then/Wrap/Plate/Group")
		expect(plate.canvasGroupInstance).toBeNil() -- never a fade group at all
		expect(group.canvasGroupInstance.groupTransparency).toBe(1) -- seeded absent
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		expect(group.canvasGroupInstance.groupTransparency).toBe(0) -- settled, content visible
		expect(plate.canvasGroupInstance).toBeNil() -- the plate was never touched
	end)

	it("THE SPLIT: transform still rides the WHOLE card (materialize scales `Wrap`, not just `Group`)", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, fixedScreen(on))
		-- `Wrap` is `entry.path` (what the caller declared); the whole card
		-- scales as one rigid unit, plate included, so a materialize still
		-- reads as the CARD growing in, not just its inner text
		local wrap = adapter.node("/S/Gate/then/Wrap")
		expect(wrap.props.transform.scale).toBeCloseTo(0.96, 1e-6)
		clock:step(FRAME)
		expect(wrap.props.transform.scale > 0.96).toBe(true)
	end)
end)

-- ============================================================================
-- C. THE REAL REPRO — the reference app itself, headless. RED before this
--    task's shop.luau changes (this session's own scratch measurement, quoted
--    in task-pop-report.md, found 3 findings on `shop.wisp` alone); GREEN now,
--    across every `sheet()`-based Glade modal the video family covers.
-- ============================================================================

-- built on the shared substrate (reuse audit REUSE-88/95/96/104; controller
-- ruling R12's own follow-up trigger: "the next spec file that ADDS a builder
-- migrates its file [to `tests/lib/world.luau`] instead") rather than a new
-- spec-local hand-rolled presenter.
local function gladeWorld(width: number?, height: number?): any
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = width or 390, h = height or 844 },
		presenterOpts = { keyboardNavigation = true },
	})
	local built = gladeProof.build(Facet, w.core, {
		env = w.env,
		actionSystem = w.system,
		presenter = w.pres,
		adapter = w.adapter,
	})
	local handle = w.pres.present(built.screen, built.present)
	built.api.bindHandle(handle)
	w.pres.refresh()
	-- capture every surface `presentModal` opens (a plain wrap, not a mock: the
	-- real function still runs, this only ALSO remembers what it returned) so
	-- each push's own coordinator is reachable without a private API
	local captured: { any } = {}
	local originalPresentModal = w.pres.presentModal
	w.pres.presentModal = function(...): any
		local h = originalPresentModal(...)
		table.insert(captured, h)
		return h
	end
	return { core = w.core, env = w.env, adapter = w.adapter, presenter = w.pres, built = built, captured = captured }
end

describe("backdrop-before-content: the real Glade modals (newpop.mov's family)", function()
	it("openWisp — the exact repro (tapping a Recent-visitors row) is clean", function()
		local w = gladeWorld()
		w.built.steps.selectGlade(w.built, "mossholm")
		w.built.steps.openWisp(w.built, "tidewisp")
		local handle = w.captured[#w.captured]
		expect(handle ~= nil).toBe(true)
		expect(#handle.coordinator.findings()).toBe(0)
		w.built.dispose()
	end)

	it(
		"every OTHER sheet()-based modal (charm, provisions, picker) is clean too — the shared fix, not a one-off",
		function()
			local w = gladeWorld()
			w.built.steps.selectGlade(w.built, "mossholm")

			w.built.steps.openCharm(w.built)
			expect(#w.captured[#w.captured].coordinator.findings()).toBe(0)
			w.built.steps.dismissTop(w.built)

			w.built.steps.openShop(w.built)
			expect(#w.captured[#w.captured].coordinator.findings()).toBe(0)
			w.built.steps.dismissTop(w.built)

			w.built.steps.openPicker(w.built, "mossholm")
			expect(#w.captured[#w.captured].coordinator.findings()).toBe(0)
			w.built.steps.dismissTop(w.built)

			w.built.dispose()
		end
	)
end)
