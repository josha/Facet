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
local function node(path: string, props: { [string]: any }?, children: { any }?, class: string?): any
	return { path = path, props = props or {}, children = children or {}, class = class }
end

-- a Box-classed node, the one class a `tint` genuinely paints a background
-- rect through (task POP fix round 1) — the constructor real call sites use
-- (`UI.Box{ tint = ... }`) always carries this class
local function box(path: string, props: { [string]: any }?, children: { any }?): any
	return node(path, props, children, "Box")
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

	it("the message formatter is safe on a non-finding, and decides nothing (review N10)", function()
		--[[ `countsAsBackdropIssue` is the one DECIDER; `backdropIssue` formats.
			`countsAsBackdropIssue(nil)` answers false — a non-table is not a
			finding — so the formatter used to fall into the acknowledged branch
			and index it. Nothing in `src/` hands it one, but it is public, over a
			list its caller filters. ]]
		expect(transitionsLib.countsAsBackdropIssue(nil :: any)).toBe(false)
		local issue = transitionsLib.backdropIssue(nil :: any)
		expect(string.find(issue, "expected a finding", 1, true) ~= nil).toBe(true)
		expect(string.find(transitionsLib.backdropIssue({} :: any), "expected a finding", 1, true) ~= nil).toBe(true)
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

	--[[ REVIEW FINDING 2 (fix round 1): the first shipped detector only read
		`props.surface` — a `tint`-painted `Box` (RascalRally's own house style
		for `StartCountdown.CountdownScrim`, `Ticker.EntryPlate`,
		`TableScreen.TablePlate`, and more) rode straight through it. These four
		cases pin the generalized rule: a `tint` PAINTS unless it is provably
		fully transparent, and ONLY on the one class (`Box`) whose `tint` is a
		background fill rather than a glyph/picture/stroke colour. ]]
	it("an opaque tint on a Box, DIRECT child of the fade group, is a finding — via = tint", function()
		local group = node("/S/Group", { canvasGroup = true }, {
			box("/S/Group/Plate", { tint = { direct = "#000000" } }),
		})
		local findings = transitionsLib.findBackdropFindings(group.path, group)
		expect(#findings).toBe(1)
		expect(findings[1].via).toBe("tint")
		expect(findings[1].surface).toBeNil() -- via=tint never populates `surface`
	end)

	it("a tint with `transparency = 1` (fully invisible) never paints, so it is never a finding", function()
		local group = node("/S/Group", { canvasGroup = true }, {
			box("/S/Group/Ghost", { tint = { direct = "#000000", transparency = 1 } }),
		})
		expect(#transitionsLib.findBackdropFindings(group.path, group)).toBe(0)
	end)

	it("a REACTIVE tint (no readable `.transparency`) is treated as opaque — the safe default direction", function()
		-- `core:memo`'s own Readable shape (`{ kind = "memo", _node = ..., get = fn }`)
		-- carries no `.transparency` field at all; unreadable counts as painting
		local reactiveTint: any = { kind = "memo", _node = {}, get = function() end }
		local group = node("/S/Group", { canvasGroup = true }, {
			box("/S/Group/Plate", { tint = reactiveTint }),
		})
		expect(#transitionsLib.findBackdropFindings(group.path, group)).toBe(1)
	end)

	it(
		"a `tint` on a NON-Box class (Text/Path/Image/Stage colour a glyph/stroke/picture, never a plate) is not a finding",
		function()
			local group = node("/S/Group", { canvasGroup = true }, {
				node("/S/Group/Line", { tint = { direct = "#ffffff" } }, {}, "Text"),
			})
			expect(#transitionsLib.findBackdropFindings(group.path, group)).toBe(0)
		end
	)

	--[[ REVIEW FINDING 3 (fix round 1): the SELF-CASE — the declared node IS
		the canvasGroup — is not a separate, unproven code path. `resolveAlphaTarget`
		does not repair it (see that function's own header), but detection here
		takes NO node-identity shortcut: this is the exact shape `resolveAlphaTarget`
		returns UNCHANGED for a self-case (`node.props.canvasGroup == true`), fed
		straight into the SAME finder every other case in this file uses — and it
		reddens exactly the same. RascalRally's `MessageLayer.ribbon`'s pre-fix
		`HostRibbon`/`RibbonPlate` (surface) was measured in precisely this shape. ]]
	it(
		"the SELF-CASE (declared node IS the canvasGroup) is caught by the identical finder — no special case needed",
		function()
			local selfCase = node("/S/HostRibbon", { canvasGroup = true }, {
				node("/S/HostRibbon/RibbonPlate", { surface = "raised" }),
				node("/S/HostRibbon/RibbonBody", {}),
			})
			local findings = transitionsLib.findBackdropFindings(selfCase.path, selfCase)
			expect(#findings).toBe(1)
			expect(findings[1].backdropPath).toBe("/S/HostRibbon/RibbonPlate")
		end
	)

	--[[ THE ACKNOWLEDGEMENT (task 7 item 3). Alert's `Center → Card` and Menu's
		`Popup → Panel` are byte-identical in shape to `buggyScreen` below — one
		canvasGroup, one child, and that child is the opaque plate — and no tree
		read can tell them apart, because there is nothing in the tree that
		differs. What differs is OFF the tree: a modal's backdrop is the
		presenter's scrim, painted at full opacity outside the fade group, so the
		invariant is satisfied by something this finder cannot see; a full-bleed
		page push has no scrim and its plate IS the only backdrop.

		So the difference is DECLARED, at the one place that knows it, and the
		finder reports the acknowledged shape under its own kind rather than
		stopping seeing it. An UNACKNOWLEDGED sole-child plate is a finding
		exactly as before — which is what keeps `buggyScreen` and the MUTATION
		PROOF below meaning what they meant. ]]
	it("an ACKNOWLEDGED sole-child plate reports its own kind, and is not counted", function()
		local group = node("/S/Center", { canvasGroup = true }, {
			node("/S/Center/Card", { surface = "raised" }, {
				node("/S/Center/Card/Title", {}),
			}),
		})
		local findings = transitionsLib.findBackdropFindings(group.path, group, true)
		expect(#findings).toBe(1)
		expect(findings[1].via).toBe("acknowledged-plate")
		expect(findings[1].backdropPath).toBe("/S/Center/Card")
		expect(transitionsLib.countsAsBackdropIssue(findings[1])).toBe(false)
		-- ...and the SAME shape unacknowledged is the ordinary finding
		local unacknowledged = transitionsLib.findBackdropFindings(group.path, group)
		expect(unacknowledged[1].via).toBe("surface")
		expect(transitionsLib.countsAsBackdropIssue(unacknowledged[1])).toBe(true)
	end)

	it("the acknowledgement covers ONLY the sole-child shape — a plate beside content still reports", function()
		--[[ the doc line's own refusal: "do not write it to silence a backdrop
			finding on a plate that sits behind separately-fading content". A group
			with a sibling has something the plate is genuinely a backdrop FOR, so
			the acknowledgement does not reach it however it is declared. ]]
		local group = node("/S/HostRibbon", { canvasGroup = true }, {
			node("/S/HostRibbon/RibbonPlate", { surface = "raised" }),
			node("/S/HostRibbon/RibbonBody", {}),
		})
		local findings = transitionsLib.findBackdropFindings(group.path, group, true)
		expect(#findings).toBe(1)
		expect(findings[1].via).toBe("surface")
		expect(transitionsLib.countsAsBackdropIssue(findings[1])).toBe(true)
	end)

	it("a TINT-painted sole-child plate acknowledges the same way", function()
		local group = node("/S/Popup", { canvasGroup = true }, {
			box("/S/Popup/Panel", { tint = { direct = "#101010" } }, { node("/S/Popup/Panel/Row", {}) }),
		})
		local findings = transitionsLib.findBackdropFindings(group.path, group, true)
		expect(#findings).toBe(1)
		expect(findings[1].via).toBe("acknowledged-plate")
	end)

	it("the schema refuses a plate value it cannot honour, and takes the one it can", function()
		local UIlocal = UI
		local ok, err = pcall(function()
			return UIlocal.When({
				id = "Gate",
				condition = customFactory.new():signal(true),
				transition = { enter = "materialize", plate = "hides" },
				thenView = function()
					return UIlocal.Box({ id = "Leaf" })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "plate", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "SCRIM", 1, true) ~= nil).toBe(true)
		expect(transitionsLib.resolve({ enter = "materialize", plate = "fades" }).plate).toBe("fades")
		expect(transitionsLib.resolve({ enter = "materialize" }).plate).toBeNil()
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

-- ============================================================================
-- D. THE THREE SHIPPED MODAL/POPOVER SURFACES, LIVE — the shape the gate
--    reports is the shape a modal is SUPPOSED to have, so each one declares it
--    (task 7 item 3). The claim is read off a real mount, not off the source:
--    every coordinator the drive creates is captured, and the UNFILTERED list
--    is what says the acknowledgement actually reached the coordinator.
-- ============================================================================

local backdropSweep = require("./lib/backdrop_sweep")

local function onlyAcknowledged(all: { any }, expectedBackdrop: string)
	expect(#all).toBe(1)
	expect(all[1].via).toBe(transitionsLib.ACKNOWLEDGED_PLATE)
	expect(all[1].backdropPath).toBe(expectedBackdrop)
	expect(transitionsLib.countsAsBackdropIssue(all[1])).toBe(false)
end

describe("backdrop-before-content: the modal/popover surfaces acknowledge their own plate", function()
	it("Controls.Alert — Center → Card", function()
		local w: any
		local alert: any
		local counted, all = backdropSweep.capture(function()
			w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
			alert = Facet.Controls.Alert(w.core, {
				id = "Ack",
				title = "Delete?",
				actions = { { id = "ok", label = "OK" } },
			})
			alert.present(w.pres)
			w.pres.refresh()
		end)
		expect(#counted).toBe(0)
		onlyAcknowledged(all, "/Ack/Center/Card")
		alert.dispose()
	end)

	it("Controls.Alert — a caller override is MERGED, not overwritten", function()
		--[[ the acknowledgement is about the SHAPE, which a caller changing the
			form does not change; so it rides an overriding `transition` too. A
			caller who writes `plate` themselves keeps their value — there is no
			second value to keep here, so what this pins is that the merge happens
			at all. ]]
		local w: any
		local alert: any
		local counted, all = backdropSweep.capture(function()
			w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
			alert = Facet.Controls.Alert(w.core, {
				id = "Over",
				title = "Delete?",
				actions = { { id = "ok", label = "OK" } },
				transition = { enter = "fade", class = "object" },
			})
			alert.present(w.pres)
			w.pres.refresh()
		end)
		expect(#counted).toBe(0)
		onlyAcknowledged(all, "/Over/Center/Card")
		alert.dispose()
	end)

	it("Controls.Alert — a READABLE transition is acknowledged too (review N3)", function()
		--[[ the first shape of `acknowledgePlate` returned a Readable untouched —
			"there is no table here to merge into" — which meant a caller who
			bound their transition to a signal got no acknowledgement at all, and
			the reference sweeps counted their modal. A Readable has a VALUE, and
			a memo is the framework's own way to derive one; it is owned on the
			alert's scope, so it dies with the control. ]]
		local w: any
		local alert: any
		local declared: any
		local counted, all = backdropSweep.capture(function()
			w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
			declared = w.core:signal({ enter = "materialize", class = "object" })
			alert = Facet.Controls.Alert(w.core, {
				id = "Bound",
				title = "Delete?",
				actions = { { id = "ok", label = "OK" } },
				transition = declared,
			})
			alert.present(w.pres)
			w.pres.refresh()
		end)
		expect(#counted).toBe(0)
		onlyAcknowledged(all, "/Bound/Center/Card")
		alert.dispose()
		declared:dispose()
	end)

	--[[ A CALLER'S OWN VALUES WIN, AND IDENTITY SURVIVES WHEN NOTHING IS OWED
		(review N3; widened by RED-TEAM F8, 2026-09-13). The merge acquired a second
		key: a `materialize` with no `scale` is owed the text-safe band, because that
		band answers an ENGINE fact about the type on this card rather than a taste
		the control holds — a caller naming the form to change its motion class was
		not asking for their title to re-flow a beat after it settled.

		So the passthrough is now conditional on there being nothing to add, which is
		the honest statement of the rule the identity check was always standing in
		for. A declaration that makes BOTH claims still reaches the presenter
		uncloned; so does a form that drives no scale at all. One that is owed the
		band is cloned, and every key the caller wrote survives the clone. ]]
	it("a caller's own values win, and an untouched declaration is passed through uncloned", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local function presented(id: string, declared: any): any
			local alert = Facet.Controls.Alert(w.core, {
				id = id,
				title = "Delete?",
				actions = { { id = "ok", label = "OK" } },
				transition = declared,
			})
			local handle = alert.present(w.pres)
			local reached = handle.transition
			alert.dispose()
			return reached
		end

		-- nothing owed: both claims already made, so the caller's table IS the one
		-- the presenter is handed
		local complete = { enter = "materialize", plate = "fades", scale = 0.9 }
		expect(presented("Own", complete)).toBe(complete)
		-- ...and a form that drives no scale is owed no band
		local slide = { enter = "slide-up", plate = "fades" }
		expect(presented("Slide", slide)).toBe(slide)

		-- owed the band: cloned, and every key the caller wrote survives
		local partial = { enter = "materialize", plate = "fades", class = "decay" }
		local merged = presented("Partial", partial)
		expect(merged).never().toBe(partial)
		expect(merged.plate).toBe("fades")
		expect(merged.class).toBe("decay")
		expect(merged.scale).toBe(1.015)
		expect(partial.scale).toBeNil() -- the caller's own table is not written to

		local declared = w.core:signal({ enter = "materialize", plate = "fades", scale = 0.9 })
		local bound = Facet.Controls.Alert(w.core, {
			id = "OwnBound",
			title = "Delete?",
			actions = { { id = "ok", label = "OK" } },
			transition = declared,
		})
		local boundHandle = bound.present(w.pres)
		expect(boundHandle.transition:get()).toBe(declared:get())
		bound.dispose()
		declared:dispose()
	end)

	it("Controls.Menu — Popup → Panel", function()
		local w: any
		local control: any
		local counted, all = backdropSweep.capture(function()
			w = worldLib.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
			control = Facet.Controls.Menu(w.core, {
				id = "M",
				trigger = UI.Button({
					id = "Trigger",
					label = "More",
					width = { type = "fixed", px = 120 },
					height = { type = "fixed", px = 44 },
				}),
				items = {
					{ id = "a", label = "Accessory", onSelect = function() end },
					{ id = "b", label = "Body", onSelect = function() end },
				},
			})
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.Anchor({
						id = "Body",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { control.blueprint },
					}),
				},
			}))
			w.adapter.tap("/S/Body/Trigger")
			w.pres.refresh()
		end)
		expect(#counted).toBe(0)
		onlyAcknowledged(all, "/Menu-M/Layer/Surface/Popup/Panel")
		control.dispose()
	end)

	it("picker_menu's Popup — the menu-style Picker", function()
		local w: any
		local picker: any
		local counted, all = backdropSweep.capture(function()
			w = worldLib.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
			picker = Facet.Controls.Picker(w.core, {
				id = "Quality",
				label = "Quality",
				style = "menu",
				env = w.env,
				selected = w.core:signal("a"),
				options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
			})
			w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
			picker.api.open()
			w.pres.refresh()
		end)
		expect(#counted).toBe(0)
		expect(#all).toBe(1)
		expect(all[1].via).toBe(transitionsLib.ACKNOWLEDGED_PLATE)
		expect(transitionsLib.countsAsBackdropIssue(all[1])).toBe(false)
		picker.dispose()
	end)
end)
